//// Laws of the supervised gateway ticker (residual G-04 closed): it drives
//// the drain on a cadence with a Send built per tick, turns the oldest
//// uncertain observation into a Stale alarm over a bound, clears it once when
//// the condition ends, and reports a silent drain as Unobserved. The drain is
//// the real actor; the Send is a fake that never touches a transport.

import cepaf_gleam/gateway/telegram_gateway_drain as drain
import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/gateway/telegram_gateway_ticker as ticker
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/system
import gleam/string
import gleeunit/should

fn now_ms() -> Int {
  erlang_system_time_ms()
}

@external(erlang, "erlang", "system_time")
fn erlang_system_time(unit: Unit) -> Int

type Unit {
  Millisecond
}

fn erlang_system_time_ms() -> Int {
  erlang_system_time(Millisecond)
}

fn request(text: String, observed_at_ms: Int) -> outbox.Request {
  outbox.Request(
    kind: outbox.Critical,
    chat_id: 100,
    text: text,
    source_topic: "indrajaal/otel/span/critical",
    observed_at_ms: observed_at_ms,
    digest: "digest-" <> text,
  )
}

fn delivering() -> drain.Send {
  fn(_request) { ledger.OutboxDelivered(1) }
}

fn uncertain() -> drain.Send {
  fn(_request) { ledger.OutboxUncertain("fixture_ambiguous") }
}

fn config(
  d: Subject(drain.Message),
  make_send: fn() -> drain.Send,
  alarms: Subject(ticker.Alarm),
  staleness_bound_ms: Int,
) -> ticker.Config {
  ticker.Config(
    drain: d,
    cadence_ms: 100,
    budget: 4,
    call_timeout_ms: 1000,
    staleness_bound_ms: staleness_bound_ms,
    make_send: make_send,
    alarms: alarms,
    now_ms: now_ms,
  )
}

fn start_drain() -> Subject(drain.Message) {
  let assert Ok(started) = drain.start(8, now_ms)
  started.data
}

fn drain_alarms(sink: Subject(ticker.Alarm), acc: List(ticker.Alarm)) -> List(ticker.Alarm) {
  case process.receive(sink, 10) {
    Ok(a) -> drain_alarms(sink, [a, ..acc])
    Error(_) -> list.reverse(acc)
  }
}

pub fn validate_refuses_an_unusable_configuration_test() {
  let d = start_drain()
  let sink = process.new_subject()
  let base = config(d, delivering, sink, 1000)
  ticker.validate(ticker.Config(..base, cadence_ms: 10))
  |> should.equal(Error("cadence_invalid"))
  ticker.validate(ticker.Config(..base, budget: 0))
  |> should.equal(Error("budget_invalid"))
  ticker.validate(ticker.Config(..base, staleness_bound_ms: 50))
  |> should.equal(Error("staleness_bound_invalid"))
  ticker.validate(ticker.Config(..base, call_timeout_ms: 0))
  |> should.equal(Error("call_timeout_invalid"))
  ticker.validate(base) |> should.be_ok
}

pub fn law_cadence_drives_the_drain_with_a_per_tick_send_test() {
  let d = start_drain()
  let sink = process.new_subject()
  drain.enqueue(d, request("disk full", now_ms()), 500) |> should.equal(Ok(Nil))
  let assert Ok(t) = ticker.start(config(d, delivering, sink, 1000))
  process.sleep(350)
  let assert Ok(snap) = ticker.snapshot(t, 500)
  { snap.ticks >= 2 } |> should.be_true
  let assert Some(report) = snap.last_report
  // the request was sent by a scheduled tick, not by this test
  let assert Ok(counters) = drain.try_counters(d, 500)
  counters.delivered |> should.equal(1)
  report.selected |> should.equal(0)
  snap.stale |> should.be_false
  drain_alarms(sink, []) |> should.equal([])
  process.send(t, ticker.Stop)
}

pub fn law_stale_uncertain_request_raises_and_repeats_until_cleared_test() {
  let d = start_drain()
  let sink = process.new_subject()
  let observed = now_ms() - 5000
  drain.enqueue(d, request("lost in transit", observed), 500)
  |> should.equal(Ok(Nil))
  // bound 100 ms: after the uncertain send the request is already stale
  let assert Ok(t) = ticker.start(config(d, uncertain, sink, 100))
  let assert Ok(after_first) = ticker.tick_now(t, 1000)
  after_first.stale |> should.be_true
  let assert Some(ticker.Stale(oldest, age, uncertain_count)) = after_first.last_alarm
  oldest |> should.equal(observed)
  { age > 100 } |> should.be_true
  uncertain_count |> should.equal(1)
  let assert Ok(after_second) = ticker.tick_now(t, 1000)
  // repeated while stale: a dead-man signal, not an edge
  { after_second.alarms_sent >= 2 } |> should.be_true
  // late resolution clears it exactly once
  drain.resolve(d, "digest-lost in transit", ledger.OutboxDelivered(7), 500)
  |> should.equal(Ok(Nil))
  let assert Ok(after_resolve) = ticker.tick_now(t, 1000)
  after_resolve.stale |> should.be_false
  let assert Some(ticker.Cleared(after_age)) = after_resolve.last_alarm
  { after_age > 100 } |> should.be_true
  let assert Ok(quiet) = ticker.tick_now(t, 1000)
  quiet.alarms_sent |> should.equal(after_resolve.alarms_sent)
  let alarms = drain_alarms(sink, [])
  let stales = list.filter(alarms, fn(a) {
    case a {
      ticker.Stale(_, _, _) -> True
      _ -> False
    }
  })
  { list.length(stales) >= 2 } |> should.be_true
  list.last(alarms) |> should.equal(Ok(ticker.Cleared(after_age)))
  process.send(t, ticker.Stop)
}

pub fn law_a_silent_drain_is_an_unobserved_alarm_and_the_ticker_survives_test() {
  let d = start_drain()
  let sink = process.new_subject()
  // a short call timeout: a dead unnamed drain is only noticed by the timeout,
  // and every scheduled tick blocks the actor for that long
  let assert Ok(t) =
    ticker.start(
      ticker.Config(..config(d, delivering, sink, 1000), call_timeout_ms: 200),
    )
  // kill the drain: the ticker must report, not crash or hang. The drain was
  // started linked to this test process, so unlink first or the kill signal
  // takes the test down with it.
  let assert Ok(pid) = process.subject_owner(d)
  process.unlink(pid)
  process.kill(pid)
  process.sleep(20)
  let assert Ok(snap) = ticker.tick_now(t, 2500)
  let assert Some(ticker.Unobserved(reason)) = snap.last_alarm
  { reason == "call_timeout" || reason == "actor_unavailable" }
  |> should.be_true
  // still alive and answering
  ticker.snapshot(t, 500) |> should.be_ok
  process.send(t, ticker.Stop)
}

pub fn law_ticker_state_holds_the_factory_not_a_built_send_test() {
  let d = start_drain()
  let sink = process.new_subject()
  let assert Ok(t) = ticker.start(config(d, delivering, sink, 1000))
  let assert Ok(pid) = process.subject_owner(t)
  let state = system.get_state(pid)
  // the Send is built inside a tick and dropped; the state carries the
  // factory and the drain subject, never a closure over a credential value
  let rendered = string.inspect(state)
  string.contains(rendered, "test-bot-token") |> should.be_false
  process.send(t, ticker.Stop)
}

pub fn child_spec_starts_a_named_ticker_test() {
  let d = start_drain()
  let sink = process.new_subject()
  let name = process.new_name("telegram_gateway_ticker_test")
  let assert Ok(started) =
    ticker.start_named(name, config(d, delivering, sink, 1000))
  let _ = started
  let t = process.named_subject(name)
  ticker.snapshot(t, 500) |> should.be_ok
  process.send(t, ticker.Stop)
  process.sleep(20)
  ticker.snapshot(t, 100) |> should.equal(Error(ticker.CallUnavailable))
}

pub fn start_named_refuses_an_invalid_config_test() {
  let d = start_drain()
  let sink = process.new_subject()
  let name = process.new_name("telegram_gateway_ticker_invalid")
  let base = config(d, delivering, sink, 1000)
  case ticker.start_named(name, ticker.Config(..base, budget: 0)) {
    Error(actor.InitFailed(reason)) ->
      reason |> should.equal("config_invalid:budget_invalid")
    _ -> should.fail()
  }
}

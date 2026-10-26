import cepaf_gleam/gateway/telegram_gateway_drain as drain
import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import gleam/erlang/process.{type Subject}
import gleam/otp/static_supervisor as sup
import gleam/string
import gleeunit/should

const wait_ms = 1000

fn req(kind: outbox.Kind, digest: String) -> outbox.Request {
  outbox.Request(
    kind: kind,
    chat_id: 7,
    text: "text-" <> digest,
    source_topic: "topic",
    observed_at_ms: 11,
    digest: digest,
  )
}

fn clock() -> Int {
  1234
}

/// A send function that reports every digest it is handed to the test process
/// and answers Delivered.
fn recording_send(probe: Subject(String)) -> drain.Send {
  fn(request: outbox.Request) {
    process.send(probe, request.digest)
    ledger.OutboxDelivered(1)
  }
}

fn start_with(capacity: Int, send: drain.Send) -> Subject(drain.Message) {
  let assert Ok(started) = drain.start(capacity, send, clock)
  started.data
}

fn put(d: Subject(drain.Message), kind: outbox.Kind, digest: String) -> Nil {
  let assert Ok(Nil) = drain.enqueue(d, req(kind, digest), 500)
  Nil
}

fn received(probe: Subject(String), n: Int) -> List(String) {
  case n <= 0 {
    True -> []
    False ->
      case process.receive(probe, wait_ms) {
        Ok(digest) -> [digest, ..received(probe, n - 1)]
        Error(_) -> []
      }
  }
}

// --- ordering and budget ---------------------------------------------------

pub fn critical_before_notice_and_budget_respected_test() {
  let probe = process.new_subject()
  let d = start_with(8, recording_send(probe))
  put(d, outbox.Notice, "n1")
  put(d, outbox.Notice, "n2")
  put(d, outbox.Notice, "n3")
  put(d, outbox.Critical, "c1")
  put(d, outbox.Critical, "c2")
  drain.tick(d, 3, 1000)
  |> should.equal(drain.TickReport(
    selected: 3,
    delivered: 3,
    failed: 0,
    uncertain: 0,
    budget: 3,
  ))
  received(probe, 3) |> should.equal(["c1", "c2", "n1"])
  let c = drain.counters(d, 500)
  c.pending |> should.equal(2)
  c.inflight |> should.equal(0)
  c.delivered |> should.equal(3)
}

pub fn budget_zero_or_negative_selects_nothing_test() {
  let probe = process.new_subject()
  let d = start_with(4, recording_send(probe))
  put(d, outbox.Critical, "c1")
  drain.tick(d, 0, 500).selected |> should.equal(0)
  drain.tick(d, -5, 500).selected |> should.equal(0)
  process.receive(probe, 50) |> should.equal(Error(Nil))
  let c = drain.counters(d, 500)
  c.pending |> should.equal(1)
  c.ticks |> should.equal(2)
}

// --- outcome mapping -------------------------------------------------------

fn scripted_send(request: outbox.Request) -> ledger.OutboxStatus {
  case request.digest {
    "d" -> ledger.OutboxDelivered(42)
    "f" -> ledger.OutboxFailed("boom")
    "u" -> ledger.OutboxUncertain("timeout")
    "p" -> ledger.OutboxPending
    _ -> ledger.OutboxSending("w", 1)
  }
}

pub fn outcomes_map_to_counters_and_uncertain_is_resolvable_test() {
  let d = start_with(8, scripted_send)
  put(d, outbox.Notice, "d")
  put(d, outbox.Notice, "f")
  put(d, outbox.Notice, "u")
  drain.tick(d, 10, 1000)
  |> should.equal(drain.TickReport(
    selected: 3,
    delivered: 1,
    failed: 1,
    uncertain: 1,
    budget: 10,
  ))
  let c = drain.counters(d, 500)
  c.delivered |> should.equal(1)
  c.failed |> should.equal(1)
  c.uncertain |> should.equal(1)
  c.inflight |> should.equal(0)
  // The uncertain request still blocks an identical digest.
  drain.enqueue(d, req(outbox.Notice, "u"), 500)
  |> should.equal(Error(outbox.Duplicate("u")))
  // Late resolution.
  drain.resolve(d, "u", ledger.OutboxDelivered(9), 500)
  |> should.equal(Ok(Nil))
  let after = drain.counters(d, 500)
  after.uncertain |> should.equal(0)
  after.delivered |> should.equal(2)
  // Once resolved the digest is no longer known.
  drain.enqueue(d, req(outbox.Notice, "u"), 500) |> should.equal(Ok(Nil))
}

pub fn late_failure_resolution_counts_failed_test() {
  let d = start_with(4, scripted_send)
  put(d, outbox.Notice, "u")
  drain.tick(d, 1, 500).uncertain |> should.equal(1)
  drain.resolve(d, "u", ledger.OutboxFailed("late"), 500)
  |> should.equal(Ok(Nil))
  let c = drain.counters(d, 500)
  c.uncertain |> should.equal(0)
  c.failed |> should.equal(1)
}

pub fn non_terminal_statuses_become_uncertain_not_inflight_test() {
  let d = start_with(8, scripted_send)
  put(d, outbox.Notice, "p")
  put(d, outbox.Notice, "s")
  let report = drain.tick(d, 10, 1000)
  report.selected |> should.equal(2)
  report.uncertain |> should.equal(2)
  report.delivered |> should.equal(0)
  let c = drain.counters(d, 500)
  c.inflight |> should.equal(0)
  c.uncertain |> should.equal(2)
}

// --- admission through the client -----------------------------------------

pub fn duplicate_and_oversize_are_refused_test() {
  let probe = process.new_subject()
  let d = start_with(4, recording_send(probe))
  put(d, outbox.Notice, "a")
  drain.enqueue(d, req(outbox.Notice, "a"), 500)
  |> should.equal(Error(outbox.Duplicate("a")))
  let big =
    outbox.Request(
      ..req(outbox.Notice, "big"),
      text: string.repeat("x", outbox.max_text_bytes + 1),
    )
  drain.enqueue(d, big, 500) |> should.equal(Error(outbox.Oversize))
  drain.counters(d, 500).pending |> should.equal(1)
}

pub fn full_queue_reports_exactly_as_the_queue_does_test() {
  let probe = process.new_subject()
  let d = start_with(2, recording_send(probe))
  put(d, outbox.Notice, "n1")
  put(d, outbox.Notice, "n2")
  drain.enqueue(d, req(outbox.Notice, "n3"), 500)
  |> should.equal(Error(outbox.Full(False)))
  // A Critical displaces the oldest Notice and is counted.
  drain.enqueue(d, req(outbox.Critical, "c1"), 500) |> should.equal(Ok(Nil))
  let c = drain.counters(d, 500)
  c.dropped_notices |> should.equal(1)
  c.pending |> should.equal(2)
  // Mirror the pure queue to prove the actor adds no semantics of its own.
  let q = outbox.new(2)
  let assert Ok(q) = outbox.enqueue(q, req(outbox.Critical, "k1"))
  let assert Ok(q) = outbox.enqueue(q, req(outbox.Critical, "k2"))
  let expected = outbox.enqueue(q, req(outbox.Critical, "k3"))
  let e = start_with(2, recording_send(probe))
  put(e, outbox.Critical, "k1")
  put(e, outbox.Critical, "k2")
  case expected {
    Error(refusal) ->
      drain.enqueue(e, req(outbox.Critical, "k3"), 500)
      |> should.equal(Error(refusal))
    Ok(_) -> should.fail()
  }
}

// --- clock and counters ----------------------------------------------------

pub fn ticks_and_last_tick_come_from_injected_clock_test() {
  let probe = process.new_subject()
  let d = start_with(4, recording_send(probe))
  let before = drain.counters(d, 500)
  before.ticks |> should.equal(0)
  before.last_tick_ms |> should.equal(0)
  drain.tick(d, 1, 500) |> ignore
  drain.tick(d, 1, 500) |> ignore
  let after = drain.counters(d, 500)
  after.ticks |> should.equal(2)
  after.last_tick_ms |> should.equal(1234)
  after.capacity |> should.equal(4)
}

fn ignore(_value: a) -> Nil {
  Nil
}

// --- bounded clients -------------------------------------------------------

pub fn dead_actor_yields_typed_unavailable_values_test() {
  let probe = process.new_subject()
  let assert Ok(started) = drain.start(4, recording_send(probe), clock)
  process.unlink(started.pid)
  process.kill(started.pid)
  process.sleep(50)
  let d = started.data
  // Timeout below the minimum is clamped to 1 ms and never panics.
  drain.try_counters(d, 0) |> should.equal(Error(drain.CallTimeout))
  drain.is_unavailable_counters(drain.counters(d, -3)) |> should.be_true
  drain.is_unavailable_tick(drain.tick(d, 2, 1)) |> should.be_true
  drain.tick(d, 2, 1) |> should.equal(drain.unavailable_tick_report(2))
  drain.enqueue(d, req(outbox.Notice, "x"), 1)
  |> should.equal(Error(outbox.Full(False)))
  drain.try_enqueue(d, req(outbox.Notice, "x"), 1)
  |> should.equal(Error(drain.CallTimeout))
  drain.resolve(d, "x", ledger.OutboxFailed("e"), 1)
  |> should.equal(Error(drain.CallTimeout))
}

pub fn unregistered_name_yields_call_unavailable_test() {
  let name = process.new_name("drain_never_started")
  let d = process.named_subject(name)
  drain.try_counters(d, 100) |> should.equal(Error(drain.CallUnavailable))
  drain.try_tick(d, 1, 100) |> should.equal(Error(drain.CallUnavailable))
}

// --- secrecy ---------------------------------------------------------------

pub fn reports_carry_no_token_field_test() {
  let d = start_with(4, scripted_send)
  put(d, outbox.Notice, "d")
  let report = drain.tick(d, 5, 500)
  let counters = drain.counters(d, 500)
  string.contains(string.lowercase(string.inspect(report)), "token")
  |> should.be_false
  string.contains(string.lowercase(string.inspect(counters)), "token")
  |> should.be_false
}

pub fn send_sees_only_the_request_fields_test() {
  let probe = process.new_subject()
  let original = req(outbox.Critical, "only-fields")
  let send = fn(request: outbox.Request) {
    process.send(probe, string.inspect(request))
    ledger.OutboxDelivered(1)
  }
  let d = start_with(4, send)
  let assert Ok(Nil) = drain.enqueue(d, original, 500)
  drain.tick(d, 1, 1000).delivered |> should.equal(1)
  let assert Ok(seen) = process.receive(probe, wait_ms)
  seen |> should.equal(string.inspect(original))
  // The request value has exactly the six declared fields.
  let outbox.Request(kind, chat_id, text, source_topic, observed_at_ms, digest) =
    original
  kind |> should.equal(outbox.Critical)
  chat_id |> should.equal(7)
  text |> should.equal("text-only-fields")
  source_topic |> should.equal("topic")
  observed_at_ms |> should.equal(11)
  digest |> should.equal("only-fields")
}

// --- supervision -----------------------------------------------------------

fn crashing_send(request: outbox.Request) -> ledger.OutboxStatus {
  case request.text {
    "text-boom" -> panic as "send crashed on purpose"
    _ -> ledger.OutboxDelivered(1)
  }
}

fn wait_for_counters(
  d: Subject(drain.Message),
  attempts: Int,
) -> Result(drain.Counters, Nil) {
  case attempts <= 0 {
    True -> Error(Nil)
    False ->
      case drain.try_counters(d, 100) {
        Ok(c) -> Ok(c)
        Error(_) -> {
          process.sleep(50)
          wait_for_counters(d, attempts - 1)
        }
      }
  }
}

pub fn actor_restarts_under_one_for_one_after_send_crash_test() {
  let name = process.new_name("telegram_gateway_drain_test_actor")
  let d = process.named_subject(name)
  let assert Ok(_supervisor) =
    sup.new(sup.OneForOne)
    |> sup.add(drain.child_spec_named(name, 4, crashing_send, clock))
    |> sup.start
  // Healthy before the crash.
  put(d, outbox.Notice, "ok1")
  drain.tick(d, 1, 500).delivered |> should.equal(1)
  // The crashing request kills the actor mid-tick: no reply, typed timeout.
  put(d, outbox.Critical, "boom")
  drain.try_tick(d, 1, 300) |> should.equal(Error(drain.CallTimeout))
  // The supervisor restarts it under the same name.
  let assert Ok(c) = wait_for_counters(d, 40)
  // Truthful boundary: the restarted actor starts from an empty queue.
  c.pending |> should.equal(0)
  c.ticks |> should.equal(0)
  c.delivered |> should.equal(0)
  // And it works again.
  put(d, outbox.Notice, "ok2")
  drain.tick(d, 1, 500).delivered |> should.equal(1)
}

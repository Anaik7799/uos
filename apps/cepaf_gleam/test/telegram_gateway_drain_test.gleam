import cepaf_gleam/gateway/telegram_gateway_drain as drain
import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import gleam/erlang/process.{type Subject}
import gleam/otp/static_supervisor as sup
import gleam/otp/system
import gleam/string
import gleeunit/should

const wait_ms = 1000

/// A credential-shaped value that a test Send captures on purpose. It must
/// never be observable through the actor.
const sentinel = "SENTINEL-TOKEN-7f3a9c-never-in-state"

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

fn start_with(capacity: Int) -> Subject(drain.Message) {
  let assert Ok(started) = drain.start(capacity, clock)
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

fn report(
  selected: Int,
  delivered: Int,
  failed: Int,
  uncertain: Int,
  budget: Int,
  failed_digests: List(String),
) -> drain.TickReport {
  drain.TickReport(
    selected: selected,
    delivered: delivered,
    failed: failed,
    uncertain: uncertain,
    budget: budget,
    failed_digests: failed_digests,
  )
}

fn state_text(d: Subject(drain.Message)) -> String {
  let assert Ok(pid) = process.subject_owner(d)
  string.inspect(system.get_state(pid))
}

// --- ordering and budget ---------------------------------------------------

pub fn critical_before_notice_and_budget_respected_test() {
  let probe = process.new_subject()
  let d = start_with(8)
  put(d, outbox.Notice, "n1")
  put(d, outbox.Notice, "n2")
  put(d, outbox.Notice, "n3")
  put(d, outbox.Critical, "c1")
  put(d, outbox.Critical, "c2")
  drain.tick(d, 3, recording_send(probe), 1000)
  |> should.equal(report(3, 3, 0, 0, 3, []))
  received(probe, 3) |> should.equal(["c1", "c2", "n1"])
  let c = drain.counters(d, 500)
  c.pending |> should.equal(2)
  c.inflight |> should.equal(0)
  c.delivered |> should.equal(3)
}

pub fn budget_zero_or_negative_selects_nothing_test() {
  let probe = process.new_subject()
  let d = start_with(4)
  put(d, outbox.Critical, "c1")
  drain.tick(d, 0, recording_send(probe), 500).selected |> should.equal(0)
  drain.tick(d, -5, recording_send(probe), 500).selected |> should.equal(0)
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
    "z" -> ledger.OutboxDelivered(0)
    "neg" -> ledger.OutboxDelivered(-7)
    _ -> ledger.OutboxSending("w", 1)
  }
}

pub fn outcomes_map_to_counters_and_uncertain_is_resolvable_test() {
  let d = start_with(8)
  put(d, outbox.Notice, "d")
  put(d, outbox.Notice, "f")
  put(d, outbox.Notice, "u")
  drain.tick(d, 10, scripted_send, 1000)
  |> should.equal(report(3, 1, 1, 1, 10, ["f"]))
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
  let d = start_with(4)
  put(d, outbox.Notice, "u")
  drain.tick(d, 1, scripted_send, 500).uncertain |> should.equal(1)
  drain.resolve(d, "u", ledger.OutboxFailed("late"), 500)
  |> should.equal(Ok(Nil))
  let c = drain.counters(d, 500)
  c.uncertain |> should.equal(0)
  c.failed |> should.equal(1)
}

pub fn non_terminal_statuses_become_uncertain_not_inflight_test() {
  let d = start_with(8)
  put(d, outbox.Notice, "p")
  put(d, outbox.Notice, "s")
  let r = drain.tick(d, 10, scripted_send, 1000)
  r.selected |> should.equal(2)
  r.uncertain |> should.equal(2)
  r.delivered |> should.equal(0)
  let c = drain.counters(d, 500)
  c.inflight |> should.equal(0)
  c.uncertain |> should.equal(2)
}

/// Review G-05: a delivery claim without a positive message id is not a
/// delivery, whether it comes from Send or from a late Resolve.
pub fn delivered_with_non_positive_id_is_uncertain_test() {
  let d = start_with(8)
  put(d, outbox.Critical, "z")
  put(d, outbox.Critical, "neg")
  let r = drain.tick(d, 10, scripted_send, 1000)
  r.delivered |> should.equal(0)
  r.uncertain |> should.equal(2)
  drain.resolve(d, "z", ledger.OutboxDelivered(0), 500) |> should.equal(Ok(Nil))
  drain.resolve(d, "neg", ledger.OutboxDelivered(-1), 500)
  |> should.equal(Ok(Nil))
  let c = drain.counters(d, 500)
  c.delivered |> should.equal(0)
  c.uncertain |> should.equal(2)
  // A positive id resolves it.
  drain.resolve(d, "z", ledger.OutboxDelivered(1), 500) |> should.equal(Ok(Nil))
  drain.counters(d, 500).delivered |> should.equal(1)
}

/// Review G-04: a failed Critical is named in the report, not dropped.
pub fn failed_digests_are_surfaced_test() {
  let d = start_with(8)
  put(d, outbox.Critical, "f")
  put(d, outbox.Notice, "d")
  let r = drain.tick(d, 10, scripted_send, 1000)
  r.failed_digests |> should.equal(["f"])
  r.failed |> should.equal(1)
  drain.unavailable_tick_report(3).failed_digests |> should.equal([])
}

// --- admission through the client -----------------------------------------

pub fn duplicate_and_oversize_are_refused_test() {
  let d = start_with(4)
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
  let d = start_with(2)
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
  let e = start_with(2)
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
  let d = start_with(4)
  let before = drain.counters(d, 500)
  before.ticks |> should.equal(0)
  before.last_tick_ms |> should.equal(0)
  drain.tick(d, 1, recording_send(probe), 500) |> ignore
  drain.tick(d, 1, recording_send(probe), 500) |> ignore
  let after = drain.counters(d, 500)
  after.ticks |> should.equal(2)
  after.last_tick_ms |> should.equal(1234)
  after.capacity |> should.equal(4)
}

fn ignore(_value: a) -> Nil {
  Nil
}

// --- bounded clients -------------------------------------------------------

/// Review G-07: no reply is `Unobserved`, which no queue refusal can produce.
pub fn dead_actor_yields_typed_unavailable_values_test() {
  let probe = process.new_subject()
  let assert Ok(started) = drain.start(4, clock)
  process.unlink(started.pid)
  process.kill(started.pid)
  process.sleep(50)
  let d = started.data
  // Timeout below the minimum is clamped to 1 ms and never panics.
  drain.try_counters(d, 0) |> should.equal(Error(drain.CallTimeout))
  drain.is_unavailable_counters(drain.counters(d, -3)) |> should.be_true
  drain.is_unavailable_tick(drain.tick(d, 2, recording_send(probe), 1))
  |> should.be_true
  drain.tick(d, 2, recording_send(probe), 1)
  |> should.equal(drain.unavailable_tick_report(2))
  drain.enqueue(d, req(outbox.Notice, "x"), 1)
  |> should.equal(Error(outbox.Unobserved("call_timeout")))
  drain.try_enqueue(d, req(outbox.Notice, "x"), 1)
  |> should.equal(Error(drain.CallTimeout))
  drain.resolve(d, "x", ledger.OutboxFailed("e"), 1)
  |> should.equal(Error(drain.CallTimeout))
}

pub fn unregistered_name_yields_call_unavailable_test() {
  let probe = process.new_subject()
  let name = process.new_name("drain_never_started")
  let d = process.named_subject(name)
  drain.try_counters(d, 100) |> should.equal(Error(drain.CallUnavailable))
  drain.try_tick(d, 1, recording_send(probe), 100)
  |> should.equal(Error(drain.CallUnavailable))
  drain.enqueue(d, req(outbox.Notice, "x"), 100)
  |> should.equal(Error(outbox.Unobserved("actor_unavailable")))
}

// --- secrecy ---------------------------------------------------------------

pub fn reports_carry_no_token_field_test() {
  let d = start_with(4)
  put(d, outbox.Notice, "d")
  let r = drain.tick(d, 5, scripted_send, 500)
  let counters = drain.counters(d, 500)
  string.contains(string.lowercase(string.inspect(r)), "token")
  |> should.be_false
  string.contains(string.lowercase(string.inspect(counters)), "token")
  |> should.be_false
}

/// Review G-01: a Send that captured a credential-shaped value is passed per
/// tick and never retained; the actor's own state never contains it.
pub fn state_holds_no_send_closure_test() {
  let probe = process.new_subject()
  let captured = sentinel
  let send = fn(request: outbox.Request) {
    process.send(probe, captured <> ":" <> request.digest)
    ledger.OutboxDelivered(1)
  }
  let d = start_with(4)
  put(d, outbox.Notice, "s1")
  string.contains(state_text(d), sentinel) |> should.be_false
  drain.tick(d, 1, send, 1000).delivered |> should.equal(1)
  let assert Ok(_) = process.receive(probe, wait_ms)
  // After the tick the closure is gone from the actor; the state carries only
  // the queue, the clock and the counters.
  string.contains(state_text(d), sentinel) |> should.be_false
  string.contains(string.lowercase(state_text(d)), "token") |> should.be_false
}

/// Review G-02: an exception inside Send is contained; its reason (which here
/// carries the sentinel) reaches neither the report nor the state, and the
/// actor keeps serving.
pub fn send_crash_is_contained_as_uncertain_without_payload_test() {
  let send = fn(request: outbox.Request) {
    case request.digest {
      "boom" -> panic as { "send crashed with " <> sentinel }
      _ -> ledger.OutboxDelivered(1)
    }
  }
  let d = start_with(4)
  put(d, outbox.Notice, "boom")
  put(d, outbox.Notice, "fine")
  let r = drain.tick(d, 2, send, 1000)
  r |> should.equal(report(2, 1, 0, 1, 2, []))
  string.contains(string.inspect(r), sentinel) |> should.be_false
  string.contains(state_text(d), sentinel) |> should.be_false
  let c = drain.counters(d, 500)
  c.uncertain |> should.equal(1)
  c.delivered |> should.equal(1)
  c.ticks |> should.equal(1)
  // The crashed request is uncertain, not retried and not lost.
  drain.enqueue(d, req(outbox.Notice, "boom"), 500)
  |> should.equal(Error(outbox.Duplicate("boom")))
}

pub fn send_sees_only_the_request_fields_test() {
  let probe = process.new_subject()
  let original = req(outbox.Critical, "only-fields")
  let send = fn(request: outbox.Request) {
    process.send(probe, string.inspect(request))
    ledger.OutboxDelivered(1)
  }
  let d = start_with(4)
  let assert Ok(Nil) = drain.enqueue(d, original, 500)
  drain.tick(d, 1, send, 1000).delivered |> should.equal(1)
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

/// A kill (not a Send crash, which is contained) restarts the actor under
/// its name with an EMPTY queue: the stated boundary, no recovery.
pub fn actor_restarts_under_one_for_one_after_kill_test() {
  let probe = process.new_subject()
  let name = process.new_name("telegram_gateway_drain_test_actor")
  let d = process.named_subject(name)
  let assert Ok(_supervisor) =
    sup.new(sup.OneForOne)
    |> sup.add(drain.child_spec_named(name, 4, clock))
    |> sup.start
  put(d, outbox.Notice, "ok1")
  drain.tick(d, 1, recording_send(probe), 500).delivered |> should.equal(1)
  put(d, outbox.Critical, "lost-on-restart")
  let assert Ok(pid) = process.named(name)
  process.kill(pid)
  let assert Ok(c) = wait_for_counters(d, 40)
  c.pending |> should.equal(0)
  c.ticks |> should.equal(0)
  c.delivered |> should.equal(0)
  // The lost digest is accepted again: there is no durable memory of it.
  drain.enqueue(d, req(outbox.Critical, "lost-on-restart"), 500)
  |> should.equal(Ok(Nil))
  drain.tick(d, 1, recording_send(probe), 500).delivered |> should.equal(1)
}

/// Review G-04 residual: counters carry the oldest uncertain observation (0
/// when none, -1 when unobserved) so a ticker can alarm on staleness.
pub fn counters_expose_the_oldest_uncertain_observation_test() {
  let d = start_with(8)
  drain.counters(d, 500).uncertain_oldest_observed_at_ms |> should.equal(0)
  put(d, outbox.Notice, "u")
  drain.tick(d, 1, scripted_send, 500).uncertain |> should.equal(1)
  drain.counters(d, 500).uncertain_oldest_observed_at_ms |> should.equal(11)
  drain.unavailable_counters().uncertain_oldest_observed_at_ms
  |> should.equal(-1)
}

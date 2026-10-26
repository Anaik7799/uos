//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/gateway/telegram_gateway_drain</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZENOH-005, SC-JIDOKA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Supervised drain actor for the bounded Telegram gateway outbox.
////
//// The actor owns exactly one `telegram_gateway_outbox.Queue` and empties it
//// through an INJECTED `Send` function. The actor never holds, receives or
//// logs a bot token: the transport that knows the credential lives behind the
//// injected function and is not this module's concern. The actor state has no
//// token field and no string field other than what an `outbox.Request`
//// already carries.
////
//// Truthfulness boundaries:
////   * `Send` is called synchronously inside a tick. The caller bounds it; a
////     slow send delays the tick reply and a client timeout is reported as a
////     typed `CallTimeout`, never as an empty success.
////   * `OutboxPending`/`OutboxSending` coming back from `Send` are not terminal
////     and are recorded as `OutboxUncertain("non_terminal_status")`, so no
////     request is left in flight after a tick and none is silently retried.
////   * A crash inside `Send` crashes the actor. The queue lives only in the
////     actor, so a supervisor restart yields an empty queue: requests that
////     were pending or uncertain at the crash are NOT recovered here. Durable
////     recovery belongs to the delivery ledger, not to this process.
////   * The convenience clients `enqueue`, `tick` and `counters` keep the
////     specified total signatures. On timeout or an absent actor they return
////     an explicit unavailable value (see each function). The `try_*` clients
////     return the typed `CallError` and are preferred by new callers.

import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/harness/telegram_delivery_ledger.{
  type OutboxStatus, OutboxDelivered, OutboxFailed, OutboxPending, OutboxSending,
  OutboxUncertain,
}
import gleam/erlang/process.{type Name, type Subject}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision

/// Transport boundary. Receives only the typed request; returns the observed
/// delivery status. Called inside the actor process.
pub type Send =
  fn(outbox.Request) -> OutboxStatus

pub type Message {
  Enqueue(
    request: outbox.Request,
    reply: Subject(Result(Nil, outbox.Backpressure)),
  )
  Tick(budget: Int, reply: Subject(TickReport))
  GetCounters(reply: Subject(Counters))
  Resolve(digest: String, status: OutboxStatus, reply: Subject(Nil))
}

pub type TickReport {
  TickReport(
    selected: Int,
    delivered: Int,
    failed: Int,
    uncertain: Int,
    budget: Int,
  )
}

pub type Counters {
  Counters(
    capacity: Int,
    pending: Int,
    inflight: Int,
    uncertain: Int,
    delivered: Int,
    failed: Int,
    dropped_notices: Int,
    ticks: Int,
    last_tick_ms: Int,
  )
}

/// Why a client call produced no observed reply.
pub type CallError {
  /// No reply within the bounded timeout. The request may or may not have
  /// been processed by the actor.
  CallTimeout
  /// The target is a registered name with no live process at call time.
  CallUnavailable
}

/// Smallest and largest client timeout, in milliseconds.
pub const min_timeout_ms = 1

pub const max_timeout_ms = 3000

type State {
  State(
    queue: outbox.Queue,
    send: Send,
    now_ms: fn() -> Int,
    ticks: Int,
    last_tick_ms: Int,
  )
}

fn initial_state(capacity: Int, send: Send, now_ms: fn() -> Int) -> State {
  State(
    queue: outbox.new(capacity),
    send: send,
    now_ms: now_ms,
    ticks: 0,
    last_tick_ms: 0,
  )
}

// ---------------------------------------------------------------------------
// Start and supervision
// ---------------------------------------------------------------------------

/// Start an unnamed drain actor linked to the caller.
pub fn start(
  capacity: Int,
  send: Send,
  now_ms: fn() -> Int,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(initial_state(capacity, send, now_ms))
  |> actor.on_message(handle_message)
  |> actor.start()
}

/// Start a drain actor registered under `name`. Clients keep the name (and
/// `process.named_subject(name)`), so the handle survives a supervisor restart.
pub fn start_named(
  name: Name(Message),
  capacity: Int,
  send: Send,
  now_ms: fn() -> Int,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(initial_state(capacity, send, now_ms))
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start()
}

/// Worker child so a supervisor can own the actor. A restart creates a new
/// anonymous `Subject`; use `child_spec_named` when clients must keep a handle.
pub fn child_spec(
  capacity: Int,
  send: Send,
  now_ms: fn() -> Int,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start(capacity, send, now_ms) })
}

/// Worker child registered under a stable name, so `process.named_subject(name)`
/// addresses whichever incarnation is currently alive.
pub fn child_spec_named(
  name: Name(Message),
  capacity: Int,
  send: Send,
  now_ms: fn() -> Int,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, capacity, send, now_ms) })
}

// ---------------------------------------------------------------------------
// Actor
// ---------------------------------------------------------------------------

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Enqueue(request, reply) ->
      case outbox.enqueue(state.queue, request) {
        Ok(queue) -> {
          process.send(reply, Ok(Nil))
          actor.continue(State(..state, queue: queue))
        }
        Error(refusal) -> {
          process.send(reply, Error(refusal))
          actor.continue(state)
        }
      }
    Tick(budget, reply) -> {
      let #(report, queue) = run_tick(state, budget)
      process.send(reply, report)
      actor.continue(
        State(
          ..state,
          queue: queue,
          ticks: state.ticks + 1,
          last_tick_ms: state.now_ms(),
        ),
      )
    }
    GetCounters(reply) -> {
      process.send(reply, snapshot(state))
      actor.continue(state)
    }
    Resolve(digest, status, reply) -> {
      let queue = outbox.drain_result(state.queue, digest, status)
      process.send(reply, Nil)
      actor.continue(State(..state, queue: queue))
    }
  }
}

fn snapshot(state: State) -> Counters {
  Counters(
    capacity: outbox.capacity(state.queue),
    pending: outbox.len(state.queue),
    inflight: outbox.inflight_count(state.queue),
    uncertain: outbox.uncertain_count(state.queue),
    delivered: outbox.delivered_count(state.queue),
    failed: outbox.failed_count(state.queue),
    dropped_notices: outbox.dropped_notices(state.queue),
    ticks: state.ticks,
    last_tick_ms: state.last_tick_ms,
  )
}

type Tally {
  Tally(queue: outbox.Queue, delivered: Int, failed: Int, uncertain: Int)
}

fn run_tick(state: State, budget: Int) -> #(TickReport, outbox.Queue) {
  let #(selected, selected_queue) = outbox.select(state.queue, budget)
  let tally =
    list.fold(
      selected,
      Tally(queue: selected_queue, delivered: 0, failed: 0, uncertain: 0),
      fn(acc, request) {
        let status = normalise(state.send(request))
        let queue = outbox.drain_result(acc.queue, request.digest, status)
        case status {
          OutboxDelivered(_) ->
            Tally(..acc, queue: queue, delivered: acc.delivered + 1)
          OutboxFailed(_) -> Tally(..acc, queue: queue, failed: acc.failed + 1)
          _ -> Tally(..acc, queue: queue, uncertain: acc.uncertain + 1)
        }
      },
    )
  #(
    TickReport(
      selected: list.length(selected),
      delivered: tally.delivered,
      failed: tally.failed,
      uncertain: tally.uncertain,
      budget: budget,
    ),
    tally.queue,
  )
}

/// Non-terminal statuses must not leave a request in flight. They are
/// recorded as uncertain: delivery was neither confirmed nor refuted.
fn normalise(status: OutboxStatus) -> OutboxStatus {
  case status {
    OutboxPending -> OutboxUncertain("non_terminal_status")
    OutboxSending(_, _) -> OutboxUncertain("non_terminal_status")
    OutboxDelivered(_) -> status
    OutboxFailed(_) -> status
    OutboxUncertain(_) -> status
  }
}

// ---------------------------------------------------------------------------
// Clients (bounded; never crash the caller on timeout)
// ---------------------------------------------------------------------------

fn clamp_timeout(timeout_ms: Int) -> Int {
  case timeout_ms < min_timeout_ms {
    True -> min_timeout_ms
    False ->
      case timeout_ms > max_timeout_ms {
        True -> max_timeout_ms
        False -> timeout_ms
      }
  }
}

/// `process.call` panics on timeout in the installed gleam_erlang, so the call
/// is a send plus a bounded receive on a fresh subject. A reply that arrives
/// after the timeout is left in the caller's mailbox under a unique tag.
fn bounded_call(
  drain: Subject(Message),
  timeout_ms: Int,
  make_request: fn(Subject(reply)) -> Message,
) -> Result(reply, CallError) {
  case live(drain) {
    False -> Error(CallUnavailable)
    True -> {
      let reply = process.new_subject()
      process.send(drain, make_request(reply))
      case process.receive(reply, clamp_timeout(timeout_ms)) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(CallTimeout)
      }
    }
  }
}

/// `process.send` asserts that a named subject is registered. Check first so a
/// call made between a crash and the restart returns a typed error instead of
/// crashing the caller. A registration lost between this check and the send
/// remains a narrow race owned by gleam_erlang.
fn live(drain: Subject(Message)) -> Bool {
  case process.subject_name(drain) {
    Ok(name) ->
      case process.named(name) {
        Ok(_) -> True
        Error(_) -> False
      }
    Error(_) -> True
  }
}

pub fn try_enqueue(
  drain: Subject(Message),
  request: outbox.Request,
  timeout_ms: Int,
) -> Result(Result(Nil, outbox.Backpressure), CallError) {
  bounded_call(drain, timeout_ms, fn(reply) { Enqueue(request, reply) })
}

pub fn try_tick(
  drain: Subject(Message),
  budget: Int,
  timeout_ms: Int,
) -> Result(TickReport, CallError) {
  bounded_call(drain, timeout_ms, fn(reply) { Tick(budget, reply) })
}

pub fn try_counters(
  drain: Subject(Message),
  timeout_ms: Int,
) -> Result(Counters, CallError) {
  bounded_call(drain, timeout_ms, fn(reply) { GetCounters(reply) })
}

/// Late resolution of an Uncertain (or in-flight) request by digest.
pub fn resolve(
  drain: Subject(Message),
  digest: String,
  status: OutboxStatus,
  timeout_ms: Int,
) -> Result(Nil, CallError) {
  bounded_call(drain, timeout_ms, fn(reply) { Resolve(digest, status, reply) })
}

/// Specified total client. A queue refusal is returned exactly as the queue
/// reports it. If no reply was observed (timeout or absent actor) the result
/// is `Error(Full(False))`: the request is NOT known to be admitted. The actor
/// may nevertheless have admitted it; a retry is safe because a repeated
/// digest is refused as `Duplicate`. Use `try_enqueue` to tell the cases apart.
pub fn enqueue(
  drain: Subject(Message),
  request: outbox.Request,
  timeout_ms: Int,
) -> Result(Nil, outbox.Backpressure) {
  case try_enqueue(drain, request, timeout_ms) {
    Ok(result) -> result
    Error(_) -> Error(outbox.Full(False))
  }
}

/// The report returned when no reply was observed. Every field is -1, which no
/// real report can contain, so it cannot be mistaken for "nothing selected".
pub fn unavailable_tick_report(budget: Int) -> TickReport {
  TickReport(
    selected: -1,
    delivered: -1,
    failed: -1,
    uncertain: -1,
    budget: budget,
  )
}

/// Counters returned when no reply was observed. `capacity` is 0, which a real
/// queue never reports (capacity is clamped to 1..64), and all other fields
/// are -1.
pub fn unavailable_counters() -> Counters {
  Counters(
    capacity: 0,
    pending: -1,
    inflight: -1,
    uncertain: -1,
    delivered: -1,
    failed: -1,
    dropped_notices: -1,
    ticks: -1,
    last_tick_ms: -1,
  )
}

pub fn is_unavailable_tick(report: TickReport) -> Bool {
  report.selected == -1
}

pub fn is_unavailable_counters(counters: Counters) -> Bool {
  counters.capacity == 0
}

pub fn tick(
  drain: Subject(Message),
  budget: Int,
  timeout_ms: Int,
) -> TickReport {
  case try_tick(drain, budget, timeout_ms) {
    Ok(report) -> report
    Error(_) -> unavailable_tick_report(budget)
  }
}

pub fn counters(drain: Subject(Message), timeout_ms: Int) -> Counters {
  case try_counters(drain, timeout_ms) {
    Ok(value) -> value
    Error(_) -> unavailable_counters()
  }
}

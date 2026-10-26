//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/telegram/telegram_media_janitor</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T4, SC-JIDOKA-001, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Supervised, bounded janitor for the Telegram media store. On a cadence it
//// calls `telegram_media_store.reclaim_expired` exactly once per tick, keeps a
//// bounded history of the receipts, and stops itself (a Jidoka stop) after
//// three consecutive failed runs until an operator sends `Resume`.
////
//// Truthfulness boundaries:
////   * The actor performs NO file operation of its own. Every deletion is made
////     by `reclaim_expired`, which owns the expiry, `.tmp-` and foreign-file
////     laws. The actor only schedules, records and pauses.
////   * Retention is enforced only while this actor runs. Until a run happens an
////     expired object stays on disk and keeps counting toward the ceiling. A
////     paused or dead janitor enforces nothing.
////   * Placement under a production supervisor is deployment configuration.
////     This module supplies `child_spec_named`; it does not add itself to any
////     supervision tree, and nothing here establishes that it is running in
////     production.
////   * A restart yields a fresh actor with `runs = 0` and an empty history.
////     The history is observation memory, not durable state: the receipts of
////     earlier runs are not recovered, but the store they acted on is.
////   * `now_ms` is injected. The actor trusts it as given; clock soundness is
////     the caller's concern (`SC-TIME`).
////   * A scheduled tick is a `send_after` message. A tick that is already
////     queued when the actor pauses is ignored, never run.

import cepaf_gleam/harness/telegram_media_store as store
import gleam/erlang/process.{type Name, type Subject, type Timer}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision

/// Smallest cadence: one second.
pub const min_cadence_ms = 1000

pub const max_objects_ceiling = 10_000

pub const history_limit_ceiling = 64

/// Consecutive failed runs after which the actor pauses.
pub const pause_after_errors = 3

pub type Config {
  Config(
    policy: store.Policy,
    cadence_ms: Int,
    max_objects: Int,
    history_limit: Int,
    now_ms: fn() -> Int,
  )
}

/// One reclaim run. `started_ms` is the `now_ms` sample the run used.
pub type Run {
  Run(started_ms: Int, outcome: Result(store.ReclaimReceipt, String))
}

/// Bounded view of the actor. `history` is oldest first and holds at most
/// `history_limit` runs; `runs` counts every run since this incarnation
/// started. `next_tick_ms` is None while paused.
pub type Snapshot {
  Snapshot(
    runs: Int,
    last: Option(Run),
    history: List(Run),
    consecutive_errors: Int,
    paused: Bool,
    next_tick_ms: Option(Int),
  )
}

pub type Message {
  /// Scheduled (or injected) cadence tick. Ignored while paused.
  Tick
  /// Run one reclaim now and reply with it. Does not touch the cadence.
  RunNow(reply: Subject(Run))
  GetSnapshot(reply: Subject(Snapshot))
  /// Leave the paused state. A no-op when not paused.
  Resume
  Stop
}

/// Why a client call produced no observed reply.
pub type CallError {
  CallTimeout
  CallUnavailable
}

pub const min_timeout_ms = 1

pub const max_timeout_ms = 3000

// ------------------------------------------------------------------- config

/// Refuses an unusable configuration before any actor exists. The policy check
/// reuses the store's own validation (`object_path` answers `policy_invalid`
/// for a bad policy and any other result for a valid one).
pub fn validate(config: Config) -> Result(Config, String) {
  case
    config.cadence_ms >= min_cadence_ms,
    config.max_objects >= 1 && config.max_objects <= max_objects_ceiling,
    config.history_limit >= 1 && config.history_limit <= history_limit_ceiling
  {
    False, _, _ -> Error("cadence_invalid")
    _, False, _ -> Error("max_objects_invalid")
    _, _, False -> Error("history_limit_invalid")
    True, True, True ->
      case store.object_path(config.policy, zero_digest) {
        Error("policy_invalid") -> Error("policy_invalid")
        _ -> Ok(config)
      }
  }
}

const zero_digest = "0000000000000000000000000000000000000000000000000000000000000000"

// ------------------------------------------------------------ start and spec

type State {
  State(
    config: Config,
    self: Subject(Message),
    runs: Int,
    history: List(Run),
    consecutive_errors: Int,
    paused: Bool,
    timer: Option(Timer),
    next_tick_ms: Option(Int),
  )
}

fn initialise(
  config: Config,
  self: Subject(Message),
) -> Result(actor.Initialised(State, Message, Subject(Message)), String) {
  let state =
    State(
      config: config,
      self: self,
      runs: 0,
      history: [],
      consecutive_errors: 0,
      paused: False,
      timer: None,
      next_tick_ms: None,
    )
  Ok(
    actor.initialised(schedule(state, config.now_ms()))
    |> actor.returning(self),
  )
}

/// Start an unnamed janitor linked to the caller.
pub fn start(config: Config) -> Result(Subject(Message), String) {
  case validate(config) {
    Error(reason) -> Error(reason)
    Ok(valid) ->
      case
        actor.new_with_initialiser(1000, fn(self) { initialise(valid, self) })
        |> actor.on_message(handle_message)
        |> actor.start
      {
        Ok(started) -> Ok(started.data)
        Error(_) -> Error("janitor_start_failed")
      }
  }
}

/// Start a janitor registered under `name`, so clients keep a handle across a
/// supervisor restart.
pub fn start_named(
  name: Name(Message),
  config: Config,
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  case validate(config) {
    Error(reason) -> Error(actor.InitFailed("config_invalid:" <> reason))
    Ok(valid) ->
      actor.new_with_initialiser(1000, fn(self) { initialise(valid, self) })
      |> actor.on_message(handle_message)
      |> actor.named(name)
      |> actor.start
  }
}

/// Worker child registered under a stable name (same shape as the gateway
/// drain actor's `child_spec_named`).
pub fn child_spec_named(
  name: Name(Message),
  config: Config,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, config) })
}

// -------------------------------------------------------------------- actor

/// Replace any outstanding timer with exactly one new one, so the cadence is a
/// single chain however many ticks are injected.
fn schedule(state: State, now: Int) -> State {
  cancel(state.timer)
  State(
    ..state,
    timer: Some(process.send_after(state.self, state.config.cadence_ms, Tick)),
    next_tick_ms: Some(now + state.config.cadence_ms),
  )
}

fn cancel(timer: Option(Timer)) -> Nil {
  case timer {
    Some(t) -> {
      let _ = process.cancel_timer(t)
      Nil
    }
    None -> Nil
  }
}

/// The pause is a stop of the cadence: the timer is cancelled and no next tick
/// exists until `Resume`.
fn pause(state: State) -> State {
  cancel(state.timer)
  State(..state, paused: True, timer: None, next_tick_ms: None)
}

/// The single place a reclaim is called. Updates the counters and the bounded
/// history; the caller decides about the cadence.
fn execute(state: State, now: Int) -> #(Run, State) {
  let outcome =
    store.reclaim_expired(state.config.policy, now, state.config.max_objects)
  let run = Run(started_ms: now, outcome: outcome)
  let errors = case outcome {
    Ok(_) -> 0
    Error(_) -> state.consecutive_errors + 1
  }
  let history = bounded(list.append(state.history, [run]), state.config)
  #(
    run,
    State(
      ..state,
      runs: state.runs + 1,
      history: history,
      consecutive_errors: errors,
    ),
  )
}

fn bounded(history: List(Run), config: Config) -> List(Run) {
  list.drop(history, int_max(0, list.length(history) - config.history_limit))
}

fn int_max(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}

fn tripped(state: State) -> Bool {
  state.consecutive_errors >= pause_after_errors
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Tick ->
      case state.paused {
        True -> actor.continue(state)
        False -> {
          let now = state.config.now_ms()
          let #(_, ran) = execute(state, now)
          case tripped(ran) {
            True -> actor.continue(pause(ran))
            False -> actor.continue(schedule(ran, now))
          }
        }
      }
    RunNow(reply) -> {
      let now = state.config.now_ms()
      let #(run, ran) = execute(state, now)
      process.send(reply, run)
      case tripped(ran) && !ran.paused {
        True -> actor.continue(pause(ran))
        False -> actor.continue(ran)
      }
    }
    GetSnapshot(reply) -> {
      process.send(reply, snapshot_of(state))
      actor.continue(state)
    }
    Resume ->
      case state.paused {
        False -> actor.continue(state)
        True ->
          actor.continue(schedule(
            State(..state, paused: False, consecutive_errors: 0),
            state.config.now_ms(),
          ))
      }
    Stop -> {
      cancel(state.timer)
      actor.stop()
    }
  }
}

fn snapshot_of(state: State) -> Snapshot {
  Snapshot(
    runs: state.runs,
    last: list.last(state.history) |> option.from_result,
    history: state.history,
    consecutive_errors: state.consecutive_errors,
    paused: state.paused,
    next_tick_ms: state.next_tick_ms,
  )
}

// ------------------------------------------------------------------ clients

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

/// A registered name with no live process is reported, not crashed on.
fn live(janitor: Subject(Message)) -> Bool {
  case process.subject_name(janitor) {
    Ok(name) ->
      case process.named(name) {
        Ok(_) -> True
        Error(_) -> False
      }
    Error(_) -> True
  }
}

fn bounded_call(
  janitor: Subject(Message),
  timeout_ms: Int,
  make_request: fn(Subject(reply)) -> Message,
) -> Result(reply, CallError) {
  case live(janitor) {
    False -> Error(CallUnavailable)
    True -> {
      let reply = process.new_subject()
      process.send(janitor, make_request(reply))
      case process.receive(reply, clamp_timeout(timeout_ms)) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(CallTimeout)
      }
    }
  }
}

pub fn snapshot(
  janitor: Subject(Message),
  timeout_ms: Int,
) -> Result(Snapshot, CallError) {
  bounded_call(janitor, timeout_ms, fn(reply) { GetSnapshot(reply) })
}

/// Run one reclaim immediately. The reply is the `Run` the actor recorded.
pub fn run_now(
  janitor: Subject(Message),
  timeout_ms: Int,
) -> Result(Run, CallError) {
  bounded_call(janitor, timeout_ms, fn(reply) { RunNow(reply) })
}

/// Fire-and-forget. Returns False when the named actor is not registered.
pub fn resume(janitor: Subject(Message)) -> Bool {
  send_if_live(janitor, Resume)
}

pub fn stop(janitor: Subject(Message)) -> Bool {
  send_if_live(janitor, Stop)
}

fn send_if_live(janitor: Subject(Message), message: Message) -> Bool {
  case live(janitor) {
    False -> False
    True -> {
      process.send(janitor, message)
      True
    }
  }
}

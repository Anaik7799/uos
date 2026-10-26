//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/telegram/telegram_media_janitor</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T4, SC-JIDOKA-001, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Supervised, bounded janitor for the Telegram media store. On a cadence it
//// calls `telegram_media_store.reclaim_expired` and then
//// `telegram_media_store.reclaim_orphans` once per tick (together deleting at
//// most `max_objects`), keeps a bounded history of the receipts, and stops
//// itself (a Jidoka stop) after three consecutive failed runs until an
//// operator sends `Resume`.
////
//// A run FAILS when either call errors, or when it attempted deletions and
//// every one was refused (`delete_failed`, a symlink, a directory): a janitor
//// that can remove nothing is not working. `index_invalid` and the benign
//// `no_longer_*` races are not attempts.
////
//// Supervision: `child_spec_named` is a Transient worker (a `Stop` is a normal
//// exit and is not restarted). `isolated_child_spec_named` wraps it in its own
//// supervisor with its own restart budget, so a janitor crash loop exhausts
//// that supervisor and not the service supervisor it is placed under.
////
//// Truthfulness boundaries:
////   * The actor performs NO file operation of its own. Every deletion is made
////     by the store, which owns the expiry, grace, `.tmp-` and foreign-file
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
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result

/// Smallest cadence: one second.
pub const min_cadence_ms = 1000

pub const max_objects_ceiling = 10_000

pub const history_limit_ceiling = 64

/// Consecutive failed runs after which the actor pauses.
pub const pause_after_errors = 3

/// Most refusal entries one history run carries (expired and orphan refusals
/// together); the rest are counted in `refused_dropped`.
pub const refused_detail_limit = 32

/// Restart budget of the janitor's own supervisor: ten restarts in sixty
/// seconds, independent of the service supervisor's three in five.
pub const isolation_intensity = 10

pub const isolation_period_s = 60

pub type Config {
  Config(
    policy: store.Policy,
    cadence_ms: Int,
    max_objects: Int,
    history_limit: Int,
    /// Orphans (`.tmp-`, index-less `.bin`, undecodable index) younger than
    /// this are never touched; at least `store.min_orphan_grace_ms`.
    orphan_grace_ms: Int,
    now_ms: fn() -> Int,
  )
}

/// One reclaim run. `started_ms` is the `now_ms` sample the run used.
/// `outcome` is the expiry reclaim, `orphans` the orphan reclaim (empty when
/// the expiry reclaim used the whole `max_objects` bound). `refused` is the
/// exact number of refusals in both receipts; their lists here are cut to
/// `refused_detail_limit` entries and `refused_dropped` counts the cut ones.
pub type Run {
  Run(
    started_ms: Int,
    outcome: Result(store.ReclaimReceipt, String),
    orphans: Result(store.OrphanReceipt, String),
    refused: Int,
    refused_dropped: Int,
  )
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
    /// Refusals in the latest run, and the sum over every run of this
    /// incarnation.
    last_refused: Int,
    refused_total: Int,
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
      case config.orphan_grace_ms >= store.min_orphan_grace_ms {
        False -> Error("orphan_grace_invalid")
        True ->
          case store.object_path(config.policy, zero_digest) {
            Error("policy_invalid") -> Error("policy_invalid")
            _ -> Ok(config)
          }
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
    refused_total: Int,
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
      refused_total: 0,
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

/// Worker child registered under a stable name. `Transient`: a crash is
/// restarted, a `Stop` (a normal exit) is not. Placed directly under a
/// supervisor it shares that supervisor's restart budget; prefer
/// `isolated_child_spec_named` under a supervisor whose budget other children
/// depend on.
pub fn child_spec_named(
  name: Name(Message),
  config: Config,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, config) })
  |> supervision.restart(supervision.Transient)
}

/// The janitor inside its own one-for-one supervisor with its own restart
/// budget (`isolation_intensity` in `isolation_period_s`). Crashes are
/// absorbed there; only when that budget is exhausted does the inner
/// supervisor exit, which the parent sees as one failure of one child (it is
/// restarted with a fresh budget, as `Transient`). A `Stop` leaves the inner
/// supervisor alive and the janitor gone, and nothing restarts it.
pub fn isolated_child_spec_named(
  name: Name(Message),
  config: Config,
) -> supervision.ChildSpecification(static_supervisor.Supervisor) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(
    intensity: isolation_intensity,
    period: isolation_period_s,
  )
  |> static_supervisor.add(child_spec_named(name, config))
  |> static_supervisor.supervised
  |> supervision.restart(supervision.Transient)
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

/// Refusal reasons that are not a failed attempt: a malformed index is the
/// orphan reclaim's job once it ages, and a `no_longer_*` is a lost race.
const benign_refusals = ["index_invalid", "no_longer_expired", "no_longer_orphan"]

fn attempted(refused: List(#(String, String))) -> Int {
  list.length(
    list.filter(refused, fn(entry) { !list.contains(benign_refusals, entry.1) }),
  )
}

/// Failed: either call errored, or deletions were attempted and none removed
/// anything (every attempt refused).
fn run_failed(
  expired: Result(store.ReclaimReceipt, String),
  orphans: Result(store.OrphanReceipt, String),
) -> Bool {
  case expired, orphans {
    Ok(e), Ok(o) ->
      attempted(e.refused) + attempted(o.refused) > 0
      && list.length(e.removed) + list.length(o.removed) == 0
    _, _ -> True
  }
}

fn refusal_count(
  expired: Result(store.ReclaimReceipt, String),
  orphans: Result(store.OrphanReceipt, String),
) -> Int {
  let e = case expired {
    Ok(r) -> list.length(r.refused)
    Error(_) -> 0
  }
  let o = case orphans {
    Ok(r) -> list.length(r.refused)
    Error(_) -> 0
  }
  e + o
}

/// Cut the refusal lists carried in a run to `refused_detail_limit` entries in
/// total (expired first); the number cut is recorded.
fn bound_refusals(run: Run) -> Run {
  let kept_expired = case run.outcome {
    Ok(r) -> list.take(r.refused, refused_detail_limit)
    Error(_) -> []
  }
  let room = refused_detail_limit - list.length(kept_expired)
  let kept_orphans = case run.orphans {
    Ok(r) -> list.take(r.refused, room)
    Error(_) -> []
  }
  Run(
    ..run,
    outcome: result.map(run.outcome, fn(r) {
      store.ReclaimReceipt(..r, refused: kept_expired)
    }),
    orphans: result.map(run.orphans, fn(r) {
      store.OrphanReceipt(..r, refused: kept_orphans)
    }),
    refused_dropped: run.refused
      - list.length(kept_expired)
      - list.length(kept_orphans),
  )
}

/// The single place a reclaim is called. Updates the counters and the bounded
/// history; the caller decides about the cadence. The orphan reclaim gets what
/// the expiry reclaim left of `max_objects`, so one tick never deletes more
/// than `max_objects` objects in total.
fn execute(state: State, now: Int) -> #(Run, State) {
  let config = state.config
  let outcome = store.reclaim_expired(config.policy, now, config.max_objects)
  let budget = case outcome {
    Ok(receipt) -> config.max_objects - receipt.examined
    Error(_) -> config.max_objects
  }
  let orphans = case budget < 1 {
    True -> Ok(store.empty_orphan_receipt())
    False ->
      store.reclaim_orphans(config.policy, now, budget, config.orphan_grace_ms)
  }
  let refused = refusal_count(outcome, orphans)
  let errors = case run_failed(outcome, orphans) {
    False -> 0
    True -> state.consecutive_errors + 1
  }
  let run =
    bound_refusals(Run(
      started_ms: now,
      outcome: outcome,
      orphans: orphans,
      refused: refused,
      refused_dropped: 0,
    ))
  let history = bounded(list.append(state.history, [run]), config)
  #(
    run,
    State(
      ..state,
      runs: state.runs + 1,
      history: history,
      consecutive_errors: errors,
      refused_total: state.refused_total + refused,
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
    last_refused: case list.last(state.history) {
      Ok(run) -> run.refused
      Error(_) -> 0
    },
    refused_total: state.refused_total,
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

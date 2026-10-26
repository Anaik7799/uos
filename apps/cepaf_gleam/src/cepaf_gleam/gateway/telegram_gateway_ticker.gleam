//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/gateway/telegram_gateway_ticker</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZENOH-005, SC-JIDOKA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Supervised ticker for the Telegram gateway drain (review residual G-04,
//// closed in the residuals plan of 2026-10-26).
////
//// On a cadence the ticker drives one bounded `telegram_gateway_drain.tick`
//// with a `Send` it builds fresh for that tick, then reads the drain's
//// `Counters` and turns `uncertain_oldest_observed_at_ms` into an alarm:
////   * `Stale(oldest, age, uncertain)` while the oldest uncertain request is
////     older than `staleness_bound_ms` (repeated on every tick while stale, a
////     dead-man signal rather than an edge);
////   * `Cleared(after_age)` once, on the tick where a stale condition ends;
////   * `Unobserved(reason)` when the drain did not answer the tick or the
////     counters (`call_timeout`, `actor_unavailable`): a silent drain is an
////     alarm, never a quiet success.
//// Alarms go to a typed `Subject(Alarm)` the deployment supplies. Routing them
//// to an operator (a Telegram Critical, a board message) is the sink's job.
////
//// Truthfulness boundaries:
////   * The `Send` closure, which captures the bot credential, lives in THIS
////     process for the duration of a tick and is rebuilt by `make_send` each
////     time; the drain never keeps it (review G-01). The ticker state keeps the
////     factory, not a built Send.
////   * The ticker does not retry a send and does not resolve uncertain
////     requests; a `Stale` alarm is information for whoever holds the drain
////     Subject (review G-05).
////   * `now_ms` is injected and trusted as given (`SC-TIME`).
////   * Placement under a production supervisor is deployment configuration;
////     `telegram_service.gateway_ticker_child` builds the spec, nothing here
////     adds itself to a tree.

import cepaf_gleam/gateway/telegram_gateway_drain as drain
import gleam/erlang/process.{type Name, type Subject, type Timer}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision

/// Smallest cadence: a tenth of a second.
pub const min_cadence_ms = 100

/// Largest number of requests one tick may send.
pub const max_budget = 64

pub type Config {
  Config(
    /// The drain to tick; a named subject keeps working across its restart.
    drain: Subject(drain.Message),
    cadence_ms: Int,
    budget: Int,
    /// Bound on each drain call (clamped by the drain's own limits).
    call_timeout_ms: Int,
    /// An uncertain request older than this is stale.
    staleness_bound_ms: Int,
    /// Builds the per-tick Send; called once per tick, result dropped after.
    make_send: fn() -> drain.Send,
    alarms: Subject(Alarm),
    now_ms: fn() -> Int,
  )
}

pub type Alarm {
  Stale(oldest_observed_at_ms: Int, age_ms: Int, uncertain: Int)
  Cleared(after_age_ms: Int)
  Unobserved(reason: String)
}

/// Bounded view of the ticker.
pub type Snapshot {
  Snapshot(
    ticks: Int,
    last_report: Option(drain.TickReport),
    stale: Bool,
    last_alarm: Option(Alarm),
    alarms_sent: Int,
    next_tick_ms: Option(Int),
  )
}

pub type Message {
  /// Scheduled (or injected) cadence tick.
  Tick
  /// Run one tick now and reply with the snapshot after it. Does not touch
  /// the cadence.
  TickNow(reply: Subject(Snapshot))
  GetSnapshot(reply: Subject(Snapshot))
  Stop
}

pub type CallError {
  CallTimeout
  CallUnavailable
}

pub const min_timeout_ms = 1

pub const max_timeout_ms = 3000

// ------------------------------------------------------------------- config

/// Refuses an unusable configuration before any actor exists.
pub fn validate(config: Config) -> Result(Config, String) {
  case
    config.cadence_ms >= min_cadence_ms,
    config.budget >= 1 && config.budget <= max_budget,
    config.staleness_bound_ms >= config.cadence_ms,
    config.call_timeout_ms >= drain.min_timeout_ms
      && config.call_timeout_ms <= drain.max_timeout_ms
  {
    False, _, _, _ -> Error("cadence_invalid")
    _, False, _, _ -> Error("budget_invalid")
    _, _, False, _ -> Error("staleness_bound_invalid")
    _, _, _, False -> Error("call_timeout_invalid")
    True, True, True, True -> Ok(config)
  }
}

// ------------------------------------------------------------ start and spec

type State {
  State(
    config: Config,
    self: Subject(Message),
    ticks: Int,
    last_report: Option(drain.TickReport),
    stale: Bool,
    last_alarm: Option(Alarm),
    alarms_sent: Int,
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
      ticks: 0,
      last_report: None,
      stale: False,
      last_alarm: None,
      alarms_sent: 0,
      timer: None,
      next_tick_ms: None,
    )
  Ok(
    actor.initialised(schedule(state, config.now_ms()))
    |> actor.returning(self),
  )
}

/// Start an unnamed ticker linked to the caller.
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
        Error(_) -> Error("ticker_start_failed")
      }
  }
}

/// Start a ticker registered under `name`.
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
/// restarted, a `Stop` is not.
pub fn child_spec_named(
  name: Name(Message),
  config: Config,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() { start_named(name, config) })
  |> supervision.restart(supervision.Transient)
}

// -------------------------------------------------------------------- actor

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

fn raise(state: State, alarm: Alarm) -> State {
  process.send(state.config.alarms, alarm)
  State(..state, last_alarm: Some(alarm), alarms_sent: state.alarms_sent + 1)
}

/// The staleness decision from one `Counters` sample. `oldest` is 0 when no
/// request is uncertain; a positive age over the bound is stale.
pub fn staleness(
  counters: drain.Counters,
  now: Int,
  bound_ms: Int,
) -> Option(#(Int, Int)) {
  let oldest = counters.uncertain_oldest_observed_at_ms
  case oldest > 0 && now - oldest > bound_ms {
    True -> Some(#(oldest, now - oldest))
    False -> None
  }
}

/// The single place a tick runs: one drain tick with a fresh Send, one
/// counters read, one alarm decision.
fn execute(state: State) -> State {
  let config = state.config
  let now = config.now_ms()
  let ticked = State(..state, ticks: state.ticks + 1)
  case
    drain.try_tick(config.drain, config.budget, config.make_send(), config.call_timeout_ms)
  {
    Error(drain.CallTimeout) -> raise(ticked, Unobserved("call_timeout"))
    Error(drain.CallUnavailable) -> raise(ticked, Unobserved("actor_unavailable"))
    Ok(report) -> {
      let reported = State(..ticked, last_report: Some(report))
      case drain.try_counters(config.drain, config.call_timeout_ms) {
        Error(drain.CallTimeout) -> raise(reported, Unobserved("call_timeout"))
        Error(drain.CallUnavailable) ->
          raise(reported, Unobserved("actor_unavailable"))
        Ok(counters) ->
          case staleness(counters, now, config.staleness_bound_ms) {
            Some(#(oldest, age)) ->
              raise(
                State(..reported, stale: True),
                Stale(oldest, age, counters.uncertain),
              )
            None ->
              case reported.stale {
                True -> {
                  let after = case reported.last_alarm {
                    Some(Stale(_, age, _)) -> age
                    _ -> 0
                  }
                  raise(State(..reported, stale: False), Cleared(after))
                }
                False -> reported
              }
          }
      }
    }
  }
}

fn handle_message(
  state: State,
  message: Message,
) -> actor.Next(State, Message) {
  case message {
    Tick -> {
      let ran = execute(state)
      actor.continue(schedule(ran, state.config.now_ms()))
    }
    TickNow(reply) -> {
      let ran = execute(state)
      process.send(reply, snapshot_of(ran))
      actor.continue(ran)
    }
    GetSnapshot(reply) -> {
      process.send(reply, snapshot_of(state))
      actor.continue(state)
    }
    Stop -> {
      cancel(state.timer)
      actor.stop()
    }
  }
}

fn snapshot_of(state: State) -> Snapshot {
  Snapshot(
    ticks: state.ticks,
    last_report: state.last_report,
    stale: state.stale,
    last_alarm: state.last_alarm,
    alarms_sent: state.alarms_sent,
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

fn live(ticker: Subject(Message)) -> Bool {
  case process.subject_name(ticker) {
    Ok(name) ->
      case process.named(name) {
        Ok(_) -> True
        Error(_) -> False
      }
    Error(_) -> True
  }
}

fn bounded_call(
  ticker: Subject(Message),
  timeout_ms: Int,
  make_request: fn(Subject(reply)) -> Message,
) -> Result(reply, CallError) {
  case live(ticker) {
    False -> Error(CallUnavailable)
    True -> {
      let reply = process.new_subject()
      process.send(ticker, make_request(reply))
      case process.receive(reply, clamp_timeout(timeout_ms)) {
        Ok(value) -> Ok(value)
        Error(_) -> Error(CallTimeout)
      }
    }
  }
}

pub fn snapshot(
  ticker: Subject(Message),
  timeout_ms: Int,
) -> Result(Snapshot, CallError) {
  bounded_call(ticker, timeout_ms, fn(reply) { GetSnapshot(reply) })
}

/// Run one tick immediately; the reply is the snapshot after it.
pub fn tick_now(
  ticker: Subject(Message),
  timeout_ms: Int,
) -> Result(Snapshot, CallError) {
  bounded_call(ticker, timeout_ms, fn(reply) { TickNow(reply) })
}

//// Finite opt-in driver. Service retains all canonical effect authority.
//// UTC lease expiry and monotonic duration ceilings are distinct clocks.
import cepaf_gleam/harness/telegram_lifecycle_adapter as lifecycle
import cepaf_gleam/harness/telegram_service as service
import gleam/erlang/process
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

pub type Config {
  Config(max_cycles: Int, lifetime_ms: Int, idle_ms: Int,
    poll_deadline_ms: Int, dispatch_deadline_ms: Int, max_timeouts: Int)
}

pub type Terminal {
  Terminal(reason: String, completed_cycles: Int)
}

pub type Message {
  Begin
  Stop
  ServiceDown
  TimerFired(id: Int)
  StateObserved(id: Int, state: service.ServiceState)
  PollCompleted(id: Int, outcome: Result(service.ServiceStepResult, String))
  DispatchCompleted(id: Int, outcome: Result(service.ServiceStepResult, String))
}

type Phase { Ready Checking Polling Dispatching Waiting }
type ClockUnit { Millisecond }

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: ClockUnit) -> Int

type State {
  State(target: process.Subject(service.ServiceMessage),
    self: process.Subject(Message), observer: process.Subject(Terminal),
    config: Config, monitor: process.Monitor, timer: Option(process.Timer),
    id: Int, phase: Phase, completed: Int, timeouts: Int,
    deadline_mono_ms: Int, lease: Option(service.AuthorityLease))
}

pub fn validate(config: Config) -> Result(Nil, String) {
  case config.max_cycles >= 1 && config.max_cycles <= 100_000
    && config.lifetime_ms >= 1 && config.lifetime_ms <= 3_600_000
    && config.idle_ms >= 10 && config.idle_ms <= 10_000
    && config.poll_deadline_ms >= 1 && config.poll_deadline_ms <= 300_000
    && config.dispatch_deadline_ms >= 1 && config.dispatch_deadline_ms <= 300_000
    && config.max_timeouts >= 1 && config.max_timeouts <= 10 {
    True -> Ok(Nil)
    False -> Error("invalid_loop_configuration")
  }
}

pub fn start(target: process.Subject(service.ServiceMessage), config: Config,
  observer: process.Subject(Terminal),
) -> Result(actor.Started(process.Subject(Message)), String) {
  use _ <- result.try(validate(config))
  use pid <- result.try(case process.subject_name(target) {
    Ok(_) -> Error("named_service_subject_refused")
    Error(_) -> process.subject_owner(target)
      |> result.map_error(fn(_) { "service_subject_unavailable" })
  })
  case process.is_alive(pid) {
    False -> Error("service_process_down")
    True ->
      actor.new_with_initialiser(5000, fn(self) {
        let monitor = process.monitor(pid)
        let state = State(target, self, observer, config, monitor, None,
          0, Ready, 0, 0, monotonic_time(Millisecond) + config.lifetime_ms, None)
        process.send(self, Begin)
        actor.initialised(state)
        |> actor.selecting(base_selector(state))
        |> actor.returning(self)
        |> Ok
      })
      |> actor.on_message(handle)
      |> actor.start()
      |> result.map_error(fn(_) { "loop_start_failed" })
  }
}

fn base_selector(state: State) -> process.Selector(Message) {
  process.new_selector()
  |> process.select(state.self)
  |> process.select_specific_monitor(state.monitor, fn(_) { ServiceDown })
}

fn remaining_ms(state: State) -> Int {
  let local_left = state.deadline_mono_ms - monotonic_time(Millisecond)
  case state.lease {
    None -> local_left
    Some(lease) -> int.min(local_left,
      { lease.valid_until_us - service.ffi_system_now_utc_us() } / 1000)
  }
}

fn cancel(state: State) {
  case state.timer {
    Some(timer) -> { let _ = process.cancel_timer(timer) Nil }
    None -> Nil
  }
}

fn finish(state: State, reason: String) -> actor.Next(State, Message) {
  cancel(state)
  process.demonitor_process(state.monitor)
  // This requests revocation; the event does not assert cleanup confirmation.
  process.send(state.target, service.RevokeAuthority)
  process.send(state.observer, Terminal(reason, state.completed))
  actor.stop()
}

fn arm(state: State, phase: Phase, budget_ms: Int) -> State {
  cancel(state)
  let id = state.id + 1
  let delay = int.max(1, int.min(budget_ms, remaining_ms(state)))
  let timer = process.send_after(state.self, delay, TimerFired(id))
  State(..state, id: id, phase: phase, timer: Some(timer))
}

fn check_state(state: State) -> actor.Next(State, Message) {
  case remaining_ms(state) <= 0 {
    True -> finish(state, "lifetime_expired")
    False -> {
      let next = arm(state, Checking, int.min(1000, state.config.poll_deadline_ms))
      let reply = process.new_subject()
      process.send(state.target, service.GetState(reply))
      actor.continue(next) |> actor.with_selector(
        base_selector(next) |> process.select_map(reply, fn(s) { StateObserved(next.id, s) }))
    }
  }
}

fn poll(state: State) -> actor.Next(State, Message) {
  case remaining_ms(state) <= 0 {
    True -> finish(state, "lifetime_expired")
    False -> {
      let next = arm(state, Polling, state.config.poll_deadline_ms)
      let reply = process.new_subject()
      process.send(state.target, service.PollCycle(service.ffi_system_now_utc_us(), reply))
      actor.continue(next) |> actor.with_selector(
        base_selector(next) |> process.select_map(reply, fn(r) { PollCompleted(next.id, r) }))
    }
  }
}

fn dispatch(state: State) -> actor.Next(State, Message) {
  case remaining_ms(state) <= 0 {
    True -> finish(state, "lifetime_expired")
    False -> {
      let next = arm(state, Dispatching, state.config.dispatch_deadline_ms)
      let reply = process.new_subject()
      process.send(state.target, service.AutomaticDispatchTick(service.ffi_system_now_utc_us(), reply))
      actor.continue(next) |> actor.with_selector(
        base_selector(next) |> process.select_map(reply, fn(r) { DispatchCompleted(next.id, r) }))
    }
  }
}

fn wait_next(state: State, delay_ms: Int) -> actor.Next(State, Message) {
  case remaining_ms(state) <= 0 {
    True -> finish(state, "lifetime_expired")
    False -> {
      let next = arm(state, Waiting, delay_ms)
      actor.continue(next) |> actor.with_selector(base_selector(next))
    }
  }
}

fn backoff(n: Int, delay: Int) -> Int {
  case n <= 1 { True -> delay False -> backoff(n - 1, int.min(10_000, delay * 2)) }
}

fn accept_state(state: State, observed: service.ServiceState) -> actor.Next(State, Message) {
  case observed.authority_revoked {
    True -> finish(state, "authority_unavailable")
    False -> case observed.writer_state {
      lifecycle.ServiceWriterHold(_) -> finish(state, "writer_held")
      lifecycle.ServiceWriterClean -> case observed.authority {
        None -> finish(state, "authority_unavailable")
        Some(lease) -> {
          let unchanged = case state.lease {
            None -> True
            Some(prior) -> prior.lease_id == lease.lease_id
              && prior.expected_task_attempt == lease.expected_task_attempt
              && prior.coordinator_epoch == lease.coordinator_epoch
          }
          case unchanged {
            False -> finish(state, "authority_changed")
            True -> {
              let lease_left = { lease.valid_until_us - service.ffi_system_now_utc_us() } / 1000
              case lease_left > 0 {
                False -> finish(state, "lifetime_expired")
                True -> poll(State(..state, lease: Some(lease)))
              }
            }
          }
        }
      }
    }
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case remaining_ms(state) <= 0 {
    True -> finish(state, "lifetime_expired")
    False -> handle_active(state, message)
  }
}

fn handle_active(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Stop -> finish(state, "operator_stop")
    ServiceDown -> finish(state, "service_down")
    Begin -> case state.phase { Ready -> check_state(state) _ -> actor.continue(state) }
    TimerFired(id) -> case id == state.id {
      False -> actor.continue(state)
      True -> case remaining_ms(state) <= 0 {
        True -> finish(state, "lifetime_expired")
        False -> case state.phase {
          Waiting -> check_state(state)
          Ready -> actor.continue(state)
          _ -> finish(state, "operation_timeout")
        }
      }
    }
    StateObserved(id, observed) ->
      case id == state.id && state.phase == Checking {
        True -> accept_state(state, observed)
        False -> actor.continue(state)
      }
    PollCompleted(id, outcome) -> case id == state.id && state.phase == Polling {
      False -> actor.continue(state)
      True -> case outcome {
        Ok(service.PollEmpty) | Ok(service.PollCommitted(_, _)) -> dispatch(State(..state, timeouts: 0))
        Ok(_) -> finish(state, "unexpected_poll_result")
        Error("http_poll_updates_failed: http_poll_network_error: timeout") -> {
          let count = state.timeouts + 1
          case count > state.config.max_timeouts {
            True -> finish(state, "timeout_budget_exhausted")
            False -> wait_next(State(..state, timeouts: count), backoff(count, 1000))
          }
        }
        Error(_) -> finish(state, "poll_error")
      }
    }
    DispatchCompleted(id, outcome) ->
      case id == state.id && state.phase == Dispatching {
        False -> actor.continue(state)
        True -> case outcome {
          Error(_) -> finish(state, "dispatch_error")
          Ok(service.DispatchCycleResult(_, _)) -> {
            let next = State(..state, completed: state.completed + 1)
            case next.completed >= next.config.max_cycles {
              True -> finish(next, "max_cycles")
              False -> wait_next(next, next.config.idle_ms)
            }
          }
          Ok(_) -> finish(state, "unexpected_dispatch_result")
        }
      }
  }
}

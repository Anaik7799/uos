//// [C3I-SIL6-MSTS] MODULE
//// <c3i-core>
////   <layer>L5</layer>
////   <target>cepaf_gleam/intent/reconciler</target>
////   <compliance>SC-INTENT-ATLAS-001, SC-JIDOKA-001</compliance>
//// </c3i-core>
////
//// Autonomous OODA Reconciler Worker Actor with Hot Dynamic Reconfiguration.
//// Implements the Observe-Orient-Decide-Act convergence loop between current
//// system state and desired declarative intent.

import cepaf_gleam/intent/config.{type ConfigDelta, type IntentConfig}
import cepaf_gleam/intent/validator
import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/result

pub type ReconcilerState {
  ReconcilerState(
    current: IntentConfig,
    desired: IntentConfig,
    last_delta: ConfigDelta,
    cycle_counter: Int,
    is_converged: Bool,
  )
}

pub type ReconcilerMessage {
  UpdateDesiredIntent(
    new_desired: IntentConfig,
    reply_to: Subject(Result(ConfigDelta, List(String))),
  )
  TriggerOodaTick(reply_to: Subject(#(Bool, Int)))
  GetReconcilerStatus(reply_to: Subject(ReconcilerState))
}

pub fn init_reconciler(initial: IntentConfig) -> ReconcilerState {
  let empty_delta = config.compute_delta(initial, initial)
  ReconcilerState(
    current: initial,
    desired: initial,
    last_delta: empty_delta,
    cycle_counter: 0,
    is_converged: True,
  )
}

pub fn handle_message(
  state: ReconcilerState,
  msg: ReconcilerMessage,
) -> actor.Next(ReconcilerState, ReconcilerMessage) {
  case msg {
    UpdateDesiredIntent(new_desired, reply_to) -> {
      case validator.validate_intent_config(new_desired) {
        Error(errors) -> {
          process.send(reply_to, Error(errors))
          actor.continue(state)
        }
        Ok(valid_desired) -> {
          let delta = config.compute_delta(state.current, valid_desired)
          let next_state =
            ReconcilerState(
              ..state,
              desired: valid_desired,
              last_delta: delta,
              is_converged: !delta.requires_reconciliation,
            )
          process.send(reply_to, Ok(delta))
          actor.continue(next_state)
        }
      }
    }
    TriggerOodaTick(reply_to) -> {
      let next_counter = state.cycle_counter + 1
      // When converged, current becomes desired
      let next_state =
        ReconcilerState(
          ..state,
          current: state.desired,
          cycle_counter: next_counter,
          is_converged: True,
        )
      process.send(reply_to, #(next_state.is_converged, next_counter))
      actor.continue(next_state)
    }
    GetReconcilerStatus(reply_to) -> {
      process.send(reply_to, state)
      actor.continue(state)
    }
  }
}

/// Start reconciler actor process
pub fn start(
  initial: IntentConfig,
) -> Result(Subject(ReconcilerMessage), actor.StartError) {
  let initial_state = init_reconciler(initial)
  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

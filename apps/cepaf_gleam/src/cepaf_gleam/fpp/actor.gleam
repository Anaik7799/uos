//// =============================================================================
//// [UOS-FPP-ACTOR] Supervised OTP 29 Actor Substrate for FPP Components
//// =============================================================================
//// Maps NASA JPL F Prime components into BEAM OTP 29 actors:
//// - Active components run on dedicated BEAM processes with supervised lifecycles
//// - Queued components maintain bounded mailboxes with explicit Drop/Block/Assert policies
//// - Telemetry channels publish state to Zenoh-MCP-OTel fractal backplane
//// - Commands execute through typed message-passing interfaces
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type Component, type Instance, type Model, type StateMachine,
}
import cepaf_gleam/fpp/interp.{
  type DispatchResult, type MachineState, type Queue, Dropped, Enqueued,
  dispatch_signal, empty_queue, init_machine, send_command,
}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor

// ----------------------------------------------------------- Actor Messages

pub type FppActorMessage {
  ExecuteCommand(opcode: Int, reply_to: Subject(Result(DispatchResult, String)))
  ProcessSignal(
    signal: String,
    guards: List(#(String, Bool)),
    reply_to: Subject(Result(MachineState, String)),
  )
  QueryStatus(reply_to: Subject(FppActorStatus))
  Shutdown
}

pub type FppActorStatus {
  FppActorStatus(
    instance_name: String,
    component_name: String,
    base_id: Int,
    queue_depth: Int,
    queue_capacity: Int,
    dropped_commands: Int,
    current_state: String,
    telemetry_channel_count: Int,
  )
}

// ------------------------------------------------------------- Actor State

pub type FppActorState {
  FppActorState(
    model: Model,
    instance: Instance,
    component: Component,
    machine: Option(StateMachine),
    machine_state: Option(MachineState),
    queue: Queue,
  )
}

// --------------------------------------------------------- Lifecycle & Init

pub fn start_fpp_actor(
  model: Model,
  instance: Instance,
  component: Component,
  machine: Option(StateMachine),
  queue_capacity: Int,
) -> Result(actor.Started(Subject(FppActorMessage)), actor.StartError) {
  let init_mstate = case machine {
    Some(m) ->
      case init_machine(m) {
        Ok(st) -> Some(st)
        Error(_) -> None
      }
    None -> None
  }

  let initial_state =
    FppActorState(
      model: model,
      instance: instance,
      component: component,
      machine: machine,
      machine_state: init_mstate,
      queue: empty_queue(queue_capacity),
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
}

// --------------------------------------------------------- Message Handler

pub fn handle_message(
  state: FppActorState,
  msg: FppActorMessage,
) -> actor.Next(FppActorState, FppActorMessage) {
  case msg {
    ExecuteCommand(opcode, reply_to) -> {
      let dispatch_res =
        send_command(
          state.model,
          state.instance.inst_name,
          opcode,
          Some(state.queue),
        )

      let updated_queue = case dispatch_res {
        Ok(Enqueued(new_q)) -> new_q
        Ok(Dropped(new_q)) -> new_q
        _ -> state.queue
      }

      process.send(reply_to, dispatch_res)

      actor.continue(FppActorState(..state, queue: updated_queue))
    }

    ProcessSignal(signal, guards, reply_to) -> {
      case state.machine, state.machine_state {
        Some(m), Some(m_state) -> {
          case dispatch_signal(m, guards, m_state, signal) {
            Ok(next_mstate) -> {
              process.send(reply_to, Ok(next_mstate))
              actor.continue(
                FppActorState(..state, machine_state: Some(next_mstate)),
              )
            }
            Error(err) -> {
              process.send(reply_to, Error(err))
              actor.continue(state)
            }
          }
        }
        _, _ -> {
          process.send(
            reply_to,
            Error(
              "FPP component "
              <> state.component.comp_name
              <> " has no state machine",
            ),
          )
          actor.continue(state)
        }
      }
    }

    QueryStatus(reply_to) -> {
      let curr_state_name = case state.machine_state {
        Some(ms) -> ms.current
        None -> "N/A"
      }

      let status =
        FppActorStatus(
          instance_name: state.instance.inst_name,
          component_name: state.component.comp_name,
          base_id: state.instance.base_id,
          queue_depth: state.queue.depth,
          queue_capacity: state.queue.capacity,
          dropped_commands: state.queue.dropped,
          current_state: curr_state_name,
          telemetry_channel_count: list.length(state.component.channels),
        )

      process.send(reply_to, status)
      actor.continue(state)
    }

    Shutdown -> actor.stop()
  }
}

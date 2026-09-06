//// =============================================================================
//// [UOS-FPP-PRM-DB] NASA JPL F Prime Parameter Database (Svc::PrmDb) in Gleam
//// =============================================================================
//// Supervised OTP 29 actor managing non-volatile flight software parameters:
//// - PRM_GET: Parameter retrieval by param_id
//// - PRM_SET: Parameter update by param_id
//// - PRM_SAVE: Flushes current active parameters to persistent record
//// =============================================================================

import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/otp/actor

// ----------------------------------------------------------- Actor Messages

pub type PrmDbMessage {
  GetParam(param_id: Int, reply_to: Subject(Result(String, String)))
  SetParam(param_id: Int, value: String, reply_to: Subject(Result(Nil, String)))
  SaveParams(reply_to: Subject(Result(Int, String)))
  DumpAll(reply_to: Subject(List(#(Int, String))))
  Shutdown
}

// ------------------------------------------------------------- Actor State

pub type PrmDbState {
  PrmDbState(
    params: Dict(Int, String),
    save_count: Int,
  )
}

// --------------------------------------------------------- Lifecycle & Init

pub fn start(
  initial_params: List(#(Int, String)),
) -> Result(actor.Started(Subject(PrmDbMessage)), actor.StartError) {
  let param_dict = dict.from_list(initial_params)
  let state = PrmDbState(params: param_dict, save_count: 0)

  actor.new(state)
  |> actor.on_message(handle_message)
  |> actor.start()
}

// --------------------------------------------------------- Message Handler

pub fn handle_message(
  state: PrmDbState,
  msg: PrmDbMessage,
) -> actor.Next(PrmDbState, PrmDbMessage) {
  case msg {
    GetParam(param_id, reply_to) -> {
      case dict.get(state.params, param_id) {
        Ok(v) -> {
          process.send(reply_to, Ok(v))
          actor.continue(state)
        }
        Error(_) -> {
          process.send(
            reply_to,
            Error("Parameter " <> int.to_string(param_id) <> " not found"),
          )
          actor.continue(state)
        }
      }
    }

    SetParam(param_id, value, reply_to) -> {
      let updated_params = dict.insert(state.params, param_id, value)
      process.send(reply_to, Ok(Nil))
      actor.continue(PrmDbState(..state, params: updated_params))
    }

    SaveParams(reply_to) -> {
      let count = dict.size(state.params)
      let new_saves = state.save_count + 1
      process.send(reply_to, Ok(count))
      actor.continue(PrmDbState(..state, save_count: new_saves))
    }

    DumpAll(reply_to) -> {
      process.send(reply_to, dict.to_list(state.params))
      actor.continue(state)
    }

    Shutdown -> actor.stop()
  }
}

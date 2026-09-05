//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/agents/leadership</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-HA-001</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/agui/events
import cepaf_gleam/agui/zenoh_bus
import cepaf_gleam/moz/client as moz
import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{type Option, None}
import gleam/otp/actor

pub type LeadershipMessage {
  CheckLease
  GracefulDrain
  Stop
}

pub type Role {
  Primary
  Backup
  Draining
}

pub type LeadershipState {
  LeadershipState(
    id: String,
    role: Role,
    moz: moz.MoZClientState,
    lease_holder: String,
    lease_ttl_ms: Int,
    missed_heartbeats: Int,
    zenoh_session: Option(zenoh.Session),
  )
}

pub fn start(
  id: String,
) -> Result(actor.Started(Subject(LeadershipMessage)), actor.StartError) {
  let initial =
    LeadershipState(
      id: id,
      role: Backup,
      moz: moz.new(),
      lease_holder: "",
      lease_ttl_ms: 0,
      missed_heartbeats: 0,
      zenoh_session: None,
    )

  actor.new(initial)
  |> actor.on_message(handle_message)
  |> actor.start()
}

fn handle_message(
  state: LeadershipState,
  msg: LeadershipMessage,
) -> actor.Next(LeadershipState, LeadershipMessage) {
  case msg {
    CheckLease -> {
      // P2-7: Check Zenoh lease via MoZ query (SC-HA-001)
      let #(new_moz, result) = moz.send_query(state.moz, "plan", "ha_status")
      case result {
        Ok(_payload) -> {
          // If lease holder is us, we're Primary
          let new_role = case state.lease_holder == state.id {
            True -> Primary
            False -> Backup
          }
          actor.continue(LeadershipState(..state, role: new_role, moz: new_moz))
        }
        Error(_) -> {
          // Lease check failed — increment missed heartbeats
          let missed = state.missed_heartbeats + 1
          case missed >= 3 {
            True -> {
              // 3 missed heartbeats: promote to Primary (SC-SIL4-015)
              io.println(
                "🏆 HA: "
                <> state.id
                <> " promoting to Primary (3 missed heartbeats)",
              )
              actor.continue(
                LeadershipState(
                  ..state,
                  role: Primary,
                  missed_heartbeats: 0,
                  moz: new_moz,
                ),
              )
            }
            False ->
              actor.continue(
                LeadershipState(
                  ..state,
                  missed_heartbeats: missed,
                  moz: new_moz,
                ),
              )
          }
        }
      }
    }
    GracefulDrain -> {
      io.println(
        "🛡️ HA: "
        <> state.id
        <> " entering Graceful Drain mode. Rejecting new intents.",
      )
      // SC-WIRE: Emit AG-UI event for HA drain
      case state.zenoh_session {
        option.Some(session) -> {
          let _ =
            zenoh_bus.publish_event(
              session,
              state.id,
              events.new_step_started("graceful_drain"),
            )
          Nil
        }
        None -> Nil
      }
      actor.continue(LeadershipState(..state, role: Draining))
    }
    Stop -> actor.stop()
  }
}

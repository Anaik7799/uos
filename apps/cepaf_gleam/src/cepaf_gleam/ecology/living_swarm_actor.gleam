//// =============================================================================
//// [C3I-SIL6-MSTS] UOS LIVING SWARM AUTONOMIC OTP ACTOR & BACKGROUND RUNNER
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ecology/living_swarm_actor</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM through L6_ECOSYSTEM</layer>
////     <mesh-domain>Autonomic Swarm Supervisor, Cybernetic Singing & Living Ecology</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / AUTONOMIC-LIVING</criticality>
////     <stamp-controls>
////       SC-HOLON-001, SC-BIO-EVO-001, SC-BIO-HARMONY-001, SC-OTP-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Continuous autonomic OTP actor running the 21-holon living swarm and cybernetic
//// singing engine on the BEAM virtual machine.
////
//// Beats continuously on the Teentaal 16-beat rhythmic matrix, stepping the
//// OODA pulse for all 21 holons across 7 planes, calculating Lyapunov damping,
//// and producing live harmonic polyphonic resonance.
////
//// STAMP: SC-HOLON-001, SC-BIO-EVO-001, SC-BIO-HARMONY-001, SC-OTP-001.

import cepaf_gleam/ecology/harmonic_song.{
  type SwarmSong, render_song_ascii_sparkline, render_song_svg,
}
import cepaf_gleam/ecology/living_swarm.{
  type SwarmEcology, init_living_swarm, invoke_capability, step_swarm_cycle,
}
import cepaf_gleam/ecology/super_agent.{type SuperAgentHolon}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision

// =============================================================================
// 1. Message Protocol
// =============================================================================

pub type LivingSwarmActorMsg {
  /// Internal self-scheduled timer tick advancing the Teentaal rhythmic beat.
  Tick
  /// Bootstrap message providing the actor with its own Subject for self-scheduling.
  SetSelfSubject(subj: Subject(LivingSwarmActorMsg))
  /// Synchronous request for the current 21-holon swarm ecology state.
  GetSwarmState(reply_to: Subject(SwarmEcology))
  /// Synchronous request for the active cybernetic swarm song & chord.
  GetSwarmSong(reply_to: Subject(SwarmSong))
  /// Synchronous request for real-time ANSI terminal sparkline.
  GetTuiSparkline(reply_to: Subject(String))
  /// Synchronous request for dynamic pure SVG spectrogram.
  GetSpectrogramSvg(reply_to: Subject(String))
  /// Synchronous request to invoke an active capability on a specific holon.
  InvokeHolonCapability(
    holon_id: String,
    capability_name: String,
    reply_to: Subject(Result(SuperAgentHolon, String)),
  )
}

// =============================================================================
// 2. Actor State
// =============================================================================

pub type SwarmActorState {
  SwarmActorState(
    swarm: SwarmEcology,
    self_subject: Option(Subject(LivingSwarmActorMsg)),
    tick_interval_ms: Int,
  )
}

// =============================================================================
// 3. Actor Message Handler
// =============================================================================

pub fn handle_message(
  state: SwarmActorState,
  msg: LivingSwarmActorMsg,
) -> actor.Next(SwarmActorState, LivingSwarmActorMsg) {
  case msg {
    SetSelfSubject(subj) -> {
      actor.continue(SwarmActorState(..state, self_subject: Some(subj)))
    }

    Tick -> {
      let next_swarm = step_swarm_cycle(state.swarm)

      case state.self_subject {
        Some(subj) -> {
          let _ = process.send_after(subj, state.tick_interval_ms, Tick)
          Nil
        }
        None -> Nil
      }

      actor.continue(SwarmActorState(..state, swarm: next_swarm))
    }

    GetSwarmState(reply_to) -> {
      process.send(reply_to, state.swarm)
      actor.continue(state)
    }

    GetSwarmSong(reply_to) -> {
      process.send(reply_to, state.swarm.current_song)
      actor.continue(state)
    }

    GetTuiSparkline(reply_to) -> {
      let sparkline = render_song_ascii_sparkline(state.swarm.current_song)
      process.send(reply_to, sparkline)
      actor.continue(state)
    }

    GetSpectrogramSvg(reply_to) -> {
      let svg = render_song_svg(state.swarm.current_song)
      process.send(reply_to, svg)
      actor.continue(state)
    }

    InvokeHolonCapability(holon_id, capability_name, reply_to) -> {
      let found =
        list.find(state.swarm.holons, fn(h) { h.id == holon_id })

      case found {
        Error(_) -> {
          process.send(reply_to, Error("holon_not_found: " <> holon_id))
          actor.continue(state)
        }
        Ok(target) -> {
          case invoke_capability(target, capability_name) {
            Error(err) -> {
              process.send(reply_to, Error(err))
              actor.continue(state)
            }
            Ok(updated_holon) -> {
              let next_holons =
                list.map(state.swarm.holons, fn(h) {
                  case h.id == holon_id {
                    True -> updated_holon
                    False -> h
                  }
                })
              let next_swarm =
                living_swarm.SwarmEcology(..state.swarm, holons: next_holons)
              process.send(reply_to, Ok(updated_holon))
              actor.continue(SwarmActorState(..state, swarm: next_swarm))
            }
          }
        }
      }
    }
  }
}

// =============================================================================
// 4. Lifecycle & Supervised Startup
// =============================================================================

/// Start an active living swarm actor on the BEAM.
pub fn start_actor(
  tick_interval_ms: Int,
) -> Result(actor.Started(Subject(LivingSwarmActorMsg)), actor.StartError) {
  let interval = case tick_interval_ms <= 0 {
    True -> 1000
    False -> tick_interval_ms
  }

  let initial =
    SwarmActorState(
      swarm: init_living_swarm(),
      self_subject: None,
      tick_interval_ms: interval,
    )

  case actor.new(initial) |> actor.on_message(handle_message) |> actor.start() {
    Ok(started) -> {
      let subj = started.data
      process.send(subj, SetSelfSubject(subj))
      process.send(subj, Tick)
      Ok(started)
    }
    Error(err) -> Error(err)
  }
}

/// Supervision child specification for inclusion in the UOS root supervisor.
pub fn supervised(
  tick_interval_ms: Int,
) -> supervision.ChildSpecification(Subject(LivingSwarmActorMsg)) {
  supervision.worker(fn() { start_actor(tick_interval_ms) })
  |> supervision.restart(supervision.Permanent)
}

// =============================================================================
// 5. Synchronous Client Helpers
// =============================================================================

pub fn get_swarm(
  actor_subj: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(SwarmEcology, String) {
  let res = process.call(actor_subj, timeout_ms, fn(r) { GetSwarmState(r) })
  Ok(res)
}

pub fn get_song(
  actor_subj: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(SwarmSong, String) {
  let res = process.call(actor_subj, timeout_ms, fn(r) { GetSwarmSong(r) })
  Ok(res)
}

pub fn get_spectrogram(
  actor_subj: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(String, String) {
  let res = process.call(actor_subj, timeout_ms, fn(r) { GetSpectrogramSvg(r) })
  Ok(res)
}

pub fn get_sparkline(
  actor_subj: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(String, String) {
  let res = process.call(actor_subj, timeout_ms, fn(r) { GetTuiSparkline(r) })
  Ok(res)
}

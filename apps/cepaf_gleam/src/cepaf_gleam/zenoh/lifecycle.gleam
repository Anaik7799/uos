//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/zenoh/lifecycle</module>
////     <fsharp-lineage>Cepaf.Zenoh.LifecycleAgent.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Zenoh Mesh Orchestration</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / CRITICAL</criticality>
////     <stamp-controls>SC-ZENOH-001, SC-MESH-003, SC-MESH-011</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="otp-fault-tolerance">
////       F# `MailboxProcessor<LifecycleMessage>` ↪ Gleam `gleam/otp/actor`.
////       Mitigation: OTP Supervisors handle crashes that would permanently stall an F# Async loop.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/zenoh/client
import cepaf_gleam/zenoh/domain.{
  type Config, type LifecycleState, type ZenohHealth, Connected, Running,
  Stopped, Uninitialized, ZenohHealth, empty_health,
}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result

pub type State {
  State(
    config: Config,
    node_id: String,
    lifecycle_state: LifecycleState,
    health: ZenohHealth,
    session: Option(client.Session),
  )
}

pub type Message {
  Initialize
  HealthCheck
  Shutdown(graceful: Bool)
}

pub fn start(
  config: Config,
  node_id: String,
) -> Result(Subject(Message), actor.StartError) {
  actor.new(State(
    config: config,
    node_id: node_id,
    lifecycle_state: Uninitialized,
    health: empty_health(),
    session: None,
  ))
  |> actor.on_message(handle_message)
  |> actor.start()
  |> result.map(fn(started) { started.data })
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="fsharp-async-reply">
///     F# `agent.PostAndReply` ↠ Gleam `process.call`
///   </morphism>
///   <formal-proof>
///     <P> Pre: Actor is in `Uninitialized` or `Running` state. </P>
///     <C> handle_message(state, Initialize) </C>
///     <Q> Post: Transitions to `Running` (if Ok) or `Stopped` (if Error). </Q>
///   </formal-proof>
///   <telemetry>
///     <zenoh-topic>c3i/telemetry/l6/zenoh/lifecycle</zenoh-topic>
///     <requirement>MUST emit metrics via Zenoh upon state transition (AOR-MESH-004).</requirement>
///   </telemetry>
/// </c3i-atomic>
fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Initialize -> {
      // In a real implementation, we'd do this async or with a timeout
      let config_json = "{}"
      // TODO: Serialize config to JSON
      case client.open(config_json) {
        Ok(session) -> {
          actor.continue(
            State(
              ..state,
              lifecycle_state: Running(0),
              // TODO: get timestamp
              session: Some(session),
              health: ZenohHealth(..state.health, status: Connected),
            ),
          )
        }
        Error(e) -> {
          actor.continue(
            State(
              ..state,
              lifecycle_state: Stopped(e, 0),
              health: ZenohHealth(..state.health, status: domain.Error(e)),
            ),
          )
        }
      }
    }
    HealthCheck -> {
      // Logic for health check
      actor.continue(state)
    }
    Shutdown(_graceful) -> {
      actor.stop()
    }
  }
}

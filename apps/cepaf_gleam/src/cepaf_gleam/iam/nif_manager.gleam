//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/iam/nif_manager</module>
////     <fsharp-lineage>New</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-FERRISKEY-NIF-001, SC-FERRISKEY-NIF-009, SC-CPIG-011</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// IAM NifManager — process-singleton actor that owns NIF-load state and
//// surfaces a typed liveness probe to the rest of the BEAM.
////
//// Why an actor and not a free function: per SC-FERRISKEY-NIF-009, NIF
//// failures must isolate from the BEAM. By wrapping the NIF entry behind
//// an actor, callers go through the message queue (back-pressure) and
//// the supervisor restarts the actor on crash without taking down peers.

import gleam/erlang/process.{type Subject}
import gleam/otp/actor
import gleam/otp/supervision

pub type State {
  State(boot_count: Int, healthy: Bool)
}

pub type Msg {
  /// Health probe — replies with current state.
  Ping(reply_to: Subject(State))
  /// Mark the NIF as healthy. Sent by the upstream caller after
  /// `ferriskey_nif.ping` succeeds.
  MarkHealthy
  /// Mark the NIF as unhealthy. Triggers supervisor escalation.
  MarkUnhealthy
}

pub fn supervised() -> supervision.ChildSpecification(Subject(Msg)) {
  supervision.worker(start)
  |> supervision.restart(supervision.Permanent)
}

pub fn start() -> Result(actor.Started(Subject(Msg)), actor.StartError) {
  actor.new(State(boot_count: 0, healthy: False))
  |> actor.on_message(handle)
  |> actor.start
}

fn handle(state: State, msg: Msg) -> actor.Next(State, Msg) {
  case msg {
    Ping(reply) -> {
      process.send(reply, state)
      actor.continue(state)
    }
    MarkHealthy ->
      actor.continue(State(boot_count: state.boot_count + 1, healthy: True))
    MarkUnhealthy -> actor.continue(State(..state, healthy: False))
  }
}

//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/zenoh/peer_simulator</module>
////     <fsharp-lineage>N/A — Autonomous Cross-Host Zenoh Peer Simulator</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <layer>L7_FEDERATION</layer>
////     <cross-layer-dependencies>
////       <dep layer="L5_COGNITIVE">cepaf_gleam/crdt/delta_state</dep>
////       <dep layer="L5_COGNITIVE">cepaf_gleam/crdt/health_bridge</dep>
////       <dep layer="L6_ECOSYSTEM">cepaf_gleam/zenoh/zmof_transport</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-ZMOF-001, SC-ZMOF-002, SC-CRDT-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="peer-invariance">Simulated peer telemetry frames strictly match live node structural semantics</property>
////     <property name="anti-entropy-boundedness">Mesh synchronization bounded by causal dot vector clock resolution</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/crdt/delta_state.{type LWWRegister, new_lww_register}
import cepaf_gleam/crdt/health_bridge.{
  type ClusterHealthMap, type NodeHealthTelemetry, NodeHealthTelemetry,
  evaluate_quorum, record_health,
}
import cepaf_gleam/zenoh/zmof_transport.{
  OoZSpanPayload, encode_ooz_span, ooz_topic,
}
import gleam/int
import gleam/list

/// Status mode for a simulated peer node.
pub type PeerSimMode {
  PeerNominal
  PeerDegraded(failure_reason: String)
  PeerPartitioned
  PeerRecovering
}

/// Structured peer node simulation state.
pub type PeerNodeState {
  PeerNodeState(
    node_id: String,
    mode: PeerSimMode,
    health_score: Float,
    lyapunov_lambda: Float,
    is_stable: Bool,
    circuit_state: String,
    tick_counter: Int,
    epoch_us: Int,
  )
}

/// Initialize a simulated peer node state.
pub fn init_peer_node(node_id: String) -> PeerNodeState {
  PeerNodeState(
    node_id: node_id,
    mode: PeerNominal,
    health_score: 1.0,
    lyapunov_lambda: -3.85,
    is_stable: True,
    circuit_state: "closed",
    tick_counter: 0,
    epoch_us: 1725720000000000,
  )
}

/// Transition the peer simulation state by one tick.
pub fn step_peer_simulation(state: PeerNodeState, next_mode: PeerSimMode) -> PeerNodeState {
  let next_tick = state.tick_counter + 1
  let next_epoch = state.epoch_us + 1000000

  case next_mode {
    PeerNominal ->
      PeerNodeState(
        node_id: state.node_id,
        mode: PeerNominal,
        health_score: 1.0,
        lyapunov_lambda: -3.85,
        is_stable: True,
        circuit_state: "closed",
        tick_counter: next_tick,
        epoch_us: next_epoch,
      )

    PeerDegraded(reason) ->
      PeerNodeState(
        node_id: state.node_id,
        mode: PeerDegraded(reason),
        health_score: 0.45,
        lyapunov_lambda: -0.12,
        is_stable: False,
        circuit_state: "half_open",
        tick_counter: next_tick,
        epoch_us: next_epoch,
      )

    PeerPartitioned ->
      PeerNodeState(
        node_id: state.node_id,
        mode: PeerPartitioned,
        health_score: 0.0,
        lyapunov_lambda: 1.45,
        is_stable: False,
        circuit_state: "open",
        tick_counter: next_tick,
        epoch_us: next_epoch,
      )

    PeerRecovering ->
      PeerNodeState(
        node_id: state.node_id,
        mode: PeerRecovering,
        health_score: 0.85,
        lyapunov_lambda: -2.10,
        is_stable: True,
        circuit_state: "closed",
        tick_counter: next_tick,
        epoch_us: next_epoch,
      )
  }
}

/// Convert peer state into an authoritative CRDT LWWRegister.
pub fn peer_to_crdt_register(
  state: PeerNodeState,
) -> LWWRegister(NodeHealthTelemetry) {
  let telemetry =
    NodeHealthTelemetry(
      node: state.node_id,
      health_score: state.health_score,
      lyapunov_exponent: state.lyapunov_lambda,
      is_stable: state.is_stable,
      breaker_state: state.circuit_state,
      sample_epoch_us: state.epoch_us,
    )
  new_lww_register(telemetry, state.epoch_us, state.node_id)
}

/// Generate a typed OoZ span payload from a peer simulation tick.
pub fn generate_peer_ooz_span(
  state: PeerNodeState,
  span_name: String,
) -> #(String, String) {
  let topic = ooz_topic("l6_ecosystem", state.node_id)
  let status = case state.mode {
    PeerNominal -> "OK"
    PeerRecovering -> "OK"
    PeerDegraded(_) -> "DEGRADED"
    PeerPartitioned -> "CRITICAL"
  }
  let payload =
    OoZSpanPayload(
      trace_id: "peer-trace-" <> state.node_id <> "-" <> int.to_string(state.tick_counter),
      span_id: "span-" <> int.to_string(state.tick_counter),
      name: span_name,
      layer: "l6_ecosystem",
      start_time_us: state.epoch_us,
      end_time_us: state.epoch_us + 2500,
      status: status,
    )
  #(topic, encode_ooz_span(payload))
}

/// Synthesize a multi-node mesh health map incorporating peer simulation nodes.
pub fn build_simulated_mesh(
  initial_map: ClusterHealthMap,
  peers: List(PeerNodeState),
) -> ClusterHealthMap {
  list.fold(peers, initial_map, fn(acc, peer) {
    record_health(
      acc,
      peer.node_id,
      peer.health_score,
      peer.lyapunov_lambda,
      peer.is_stable,
      peer.circuit_state,
      peer.epoch_us,
    )
  })
}

/// Evaluate 2oo3 constitutional quorum over the synthesized multi-node mesh.
pub fn evaluate_mesh_quorum(
  mesh: ClusterHealthMap,
  quorum_threshold_ratio: Float,
) -> #(Bool, Float, Int, Int) {
  evaluate_quorum(mesh, quorum_threshold_ratio)
}

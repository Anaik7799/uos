//// =============================================================================
//// [C3I-SIL6-MSTS] TEST CONTRACT: Peer Simulator & Mesh Quorum Verification
//// =============================================================================

import cepaf_gleam/zenoh/peer_simulator.{
  PeerDegraded, PeerNominal, PeerPartitioned, PeerRecovering,
  build_simulated_mesh, evaluate_mesh_quorum, generate_peer_ooz_span,
  init_peer_node, peer_to_crdt_register, step_peer_simulation,
}
import cepaf_gleam/crdt/health_bridge.{empty_health_map}
import cepaf_gleam/zenoh/zmof_transport.{decode_ooz_span}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn peer_init_nominal_test() {
  let peer = init_peer_node("vm-1")
  peer.node_id |> should.equal("vm-1")
  peer.mode |> should.equal(PeerNominal)
  peer.health_score |> should.equal(1.0)
  peer.circuit_state |> should.equal("closed")
  peer.tick_counter |> should.equal(0)
}

pub fn peer_step_transitions_test() {
  let p0 = init_peer_node("vm-1")
  
  let p1 = step_peer_simulation(p0, PeerDegraded("High latency"))
  p1.mode |> should.equal(PeerDegraded("High latency"))
  p1.health_score |> should.equal(0.45)
  p1.circuit_state |> should.equal("half_open")
  p1.tick_counter |> should.equal(1)
  
  let p2 = step_peer_simulation(p1, PeerPartitioned)
  p2.mode |> should.equal(PeerPartitioned)
  p2.health_score |> should.equal(0.0)
  p2.circuit_state |> should.equal("open")
  p2.tick_counter |> should.equal(2)
  
  let p3 = step_peer_simulation(p2, PeerRecovering)
  p3.mode |> should.equal(PeerRecovering)
  p3.health_score |> should.equal(0.85)
  p3.circuit_state |> should.equal("closed")
  p3.tick_counter |> should.equal(3)
  
  let p4 = step_peer_simulation(p3, PeerNominal)
  p4.mode |> should.equal(PeerNominal)
  p4.health_score |> should.equal(1.0)
  p4.circuit_state |> should.equal("closed")
  p4.tick_counter |> should.equal(4)
}

pub fn peer_crdt_register_conversion_test() {
  let peer = init_peer_node("vm-1")
  let reg = peer_to_crdt_register(peer)
  
  reg.writer |> should.equal("vm-1")
  reg.value.node |> should.equal("vm-1")
  reg.value.health_score |> should.equal(1.0)
  reg.value.breaker_state |> should.equal("closed")
}

pub fn peer_ooz_span_generation_test() {
  let peer = init_peer_node("vm-1")
  let #(topic, encoded_span) = generate_peer_ooz_span(peer, "prajna.heartbeat")
  
  topic |> should.equal("indrajaal/otel/span/l6_ecosystem/vm-1")
  
  let decoded = decode_ooz_span(encoded_span)
  case decoded {
    Ok(span) -> {
      span.layer |> should.equal("l6_ecosystem")
      span.name |> should.equal("prajna.heartbeat")
      span.status |> should.equal("OK")
    }
    Error(_) -> should.fail()
  }
}

pub fn simulated_mesh_quorum_evaluation_test() {
  let p1 = init_peer_node("nas-1")
  let p2 = init_peer_node("vm-1")
  let p3 = init_peer_node("nas-backup")
  
  // 3 nominal nodes -> 3/3 healthy -> quorum true
  let mesh_healthy = build_simulated_mesh(empty_health_map(), [p1, p2, p3])
  let #(q1, _avg, healthy1, total1) = evaluate_mesh_quorum(mesh_healthy, 0.66)
  q1 |> should.equal(True)
  healthy1 |> should.equal(3)
  total1 |> should.equal(3)
  
  // 2 nominal, 1 partitioned -> 2/3 healthy >= 66% -> quorum true
  let p3_down = step_peer_simulation(p3, PeerPartitioned)
  let mesh_partial = build_simulated_mesh(empty_health_map(), [p1, p2, p3_down])
  let #(q2, _avg, healthy2, total2) = evaluate_mesh_quorum(mesh_partial, 0.66)
  q2 |> should.equal(True)
  healthy2 |> should.equal(2)
  total2 |> should.equal(3)
  
  // 1 nominal, 2 partitioned -> 1/3 healthy < 66% -> quorum false
  let p2_down = step_peer_simulation(p2, PeerPartitioned)
  let mesh_failed = build_simulated_mesh(empty_health_map(), [p1, p2_down, p3_down])
  let #(q3, _avg, healthy3, total3) = evaluate_mesh_quorum(mesh_failed, 0.66)
  q3 |> should.equal(False)
  healthy3 |> should.equal(1)
  total3 |> should.equal(3)
}

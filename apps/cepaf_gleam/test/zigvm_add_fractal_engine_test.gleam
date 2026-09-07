// =============================================================================
// [C3I-SIL6-MSTS] UOS ZIGVM ADD FRACTAL ENGINE TEST SUITE
// =============================================================================
// Verifies all 10 Fractal Layers (L0..L9), 3 Strata (A, B, C), 14-element
// Component Packet Schema, and the 6-stage Agentic Sublimation Lifecycle.
// =============================================================================

import cepaf_gleam/knowledge/zigvm_add_fractal_engine as add
import gleam/list
import gleeunit/should

pub fn fractal_layers_count_and_topology_test() {
  let layers = add.all_layers()
  list.length(layers) |> should.equal(10)

  // Verify L0 through L9 boundaries
  let assert Ok(l0) = list.first(layers)
  l0.name |> should.equal("L0 Constitutional")
  l0.evidence_gate |> should.equal("CHK-18-JJ, CHK-07-DRIVE, CHK-05-MUDA")

  let assert Ok(l9) = list.last(layers)
  l9.name |> should.equal("L9 Verification")
  l9.evidence_gate |> should.equal("CHK-08..11, EV-01..84 PASS")
}

pub fn strata_tripartite_decomposition_test() {
  let strata = add.all_strata()
  list.length(strata) |> should.equal(3)

  let assert [sa, sb, sc] = strata
  sa.name |> should.equal("Stratum A: Algebraic Core")
  sb.name |> should.equal("Stratum B: Interpretations & Engines")
  sc.name |> should.equal("Stratum C: Substrate")
}

pub fn component_packet_schema_and_invariants_test() {
  let packets = add.sample_component_packets()
  list.length(packets) |> should.equal(4)

  let assert [p1, _p2, p3, p4] = packets

  // Verify S1 Term Packet
  p1.id |> should.equal("S1-TERM")
  list.contains(p1.invariants, "Total Preorder") |> should.be_true
  list.contains(p1.operations, "cons") |> should.be_true

  // Verify S7 VFS Packet
  p3.id |> should.equal("S7-VFS")
  list.contains(p3.invariants, "8 VFS Laws") |> should.be_true

  // Verify S9 MAX Inference Packet
  p4.id |> should.equal("S9-MAX")
  list.contains(p4.invariants, "Strict Python Quarantine") |> should.be_true
}

pub fn agentic_sublimation_lifecycle_test() {
  let a0 = add.initial_agent("AGY", "session-uuid-test")
  a0.lamport |> should.equal(0)
  a0.lease_acquired |> should.be_false
  a0.sublimated |> should.be_false

  // 1. Spawn -> Observe
  let a1 = add.step_sublimation(a0, add.SpawnStage, "")
  a1.lease_acquired |> should.be_true
  a1.lamport |> should.equal(1)

  // 2. Observe -> Deliberate
  let a2 = add.step_sublimation(a1, add.ObserveStage, "")
  a2.lamport |> should.equal(2)

  // 3. Deliberate -> Act
  let a3 = add.step_sublimation(a2, add.DeliberateStage, "")
  a3.lamport |> should.equal(3)

  // 4. Act -> Verify
  let a4 = add.step_sublimation(a3, add.ActStage, "")
  a4.lamport |> should.equal(4)

  // 5. Verify -> Sublime
  let a5 = add.step_sublimation(a4, add.VerifyStage, "0xDIGEST_EVIDENCE")
  a5.lamport |> should.equal(5)
  a5.evidence_digest |> should.equal("0xDIGEST_EVIDENCE")

  // 6. Sublime (Release Lease & Ratify)
  let a6 = add.step_sublimation(a5, add.SublimeStage, "0xDIGEST_EVIDENCE")
  a6.sublimated |> should.be_true
  a6.lease_acquired |> should.be_false
  a6.lamport |> should.equal(6)
}

pub fn complete_add_engine_audit_verification_test() {
  let summary = add.verify_complete_add_engine()
  summary.total_layers |> should.equal(10)
  summary.total_strata |> should.equal(3)
  summary.all_layers_green |> should.be_true
  summary.all_strata_valid |> should.be_true
  summary.sublimation_verified |> should.be_true

  let str = add.audit_summary_string(summary)
  str |> should.equal("Layers: 10 | Strata: 3 | Packets: 4 | All Green: TRUE (100% Green)")
}

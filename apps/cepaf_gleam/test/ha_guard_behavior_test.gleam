//// Guard Behavior Specification Tests — Expected behavior for every module
//// STAMP: SC-ALLIUM-001, SC-VER-001, SC-HA-001, SC-MUDA-001
//// Layer: L5_COGNITIVE
//// यद्यदाचरति श्रेष्ठः — Whatever the great person does, others follow (Gita 3.21)

import cepaf_gleam/ha/guard_behavior
import gleam/list
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// Catalog completeness
// ═══════════════════════════════════════════════════════════════

pub fn all_behaviors_returns_24_test() {
  guard_behavior.behavior_count() |> should.equal(24)
}

pub fn all_behaviors_have_three_modules_per_layer_test() {
  let layers = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
  list.all(layers, fn(layer) {
    guard_behavior.by_layer(layer) |> list.length() == 3
  })
  |> should.be_true()
}

pub fn all_behaviors_have_unique_module_names_test() {
  let modules =
    guard_behavior.all_behaviors()
    |> list.map(fn(b) { b.module })
  let unique_count = list.unique(modules) |> list.length()
  unique_count |> should.equal(24)
}

pub fn all_behaviors_have_non_empty_invariants_test() {
  guard_behavior.all_behaviors()
  |> list.all(fn(b) { string.length(b.math_invariant) > 0 })
  |> should.be_true()
}

pub fn all_behaviors_have_valid_criticality_test() {
  guard_behavior.all_behaviors()
  |> list.all(fn(b) {
    b.criticality == "safety-critical"
    || b.criticality == "operational"
    || b.criticality == "informational"
  })
  |> should.be_true()
}

pub fn all_behaviors_expected_verdict_is_passed_test() {
  guard_behavior.all_behaviors()
  |> list.all(fn(b) { b.expected_verdict == "PASSED" })
  |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// behavior_for — lookup by module name
// ═══════════════════════════════════════════════════════════════

pub fn behavior_for_guardian_returns_ok_test() {
  guard_behavior.behavior_for("guardian")
  |> fn(r) {
    case r {
      Ok(_) -> True
      Error(_) -> False
    }
  }
  |> should.be_true()
}

pub fn behavior_for_guardian_layer_is_l0_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  b.layer |> should.equal("L0")
}

pub fn behavior_for_guardian_criticality_is_safety_critical_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  b.criticality |> should.equal("safety-critical")
}

pub fn behavior_for_guardian_max_failures_is_one_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  b.max_consecutive_failures |> should.equal(1)
}

pub fn behavior_for_unknown_module_returns_error_test() {
  let result = guard_behavior.behavior_for("not_a_real_module")
  case result {
    Error(msg) -> string.contains(msg, "unknown module") |> should.be_true()
    Ok(_) -> should.be_true(False)
  }
}

pub fn behavior_for_ha_election_layer_is_l7_test() {
  let assert Ok(b) = guard_behavior.behavior_for("ha_election")
  b.layer |> should.equal("L7")
}

pub fn behavior_for_ooda_loop_layer_is_l5_test() {
  let assert Ok(b) = guard_behavior.behavior_for("ooda_loop")
  b.layer |> should.equal("L5")
}

pub fn behavior_for_zenoh_mesh_layer_is_l6_test() {
  let assert Ok(b) = guard_behavior.behavior_for("zenoh_mesh")
  b.layer |> should.equal("L6")
}

pub fn behavior_for_plan_status_layer_is_l3_test() {
  let assert Ok(b) = guard_behavior.behavior_for("plan_status")
  b.layer |> should.equal("L3")
}

// ═══════════════════════════════════════════════════════════════
// is_violation — violation detection
// ═══════════════════════════════════════════════════════════════

pub fn is_violation_false_when_verdict_matches_zero_failures_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  guard_behavior.is_violation(b, "PASSED", 0) |> should.be_false()
}

pub fn is_violation_true_when_verdict_differs_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  guard_behavior.is_violation(b, "FAILED", 0) |> should.be_true()
}

pub fn is_violation_true_when_consecutive_failures_exceed_max_test() {
  let assert Ok(b) = guard_behavior.behavior_for("nif_bridge")
  // nif_bridge max=3; 4 failures = violation
  guard_behavior.is_violation(b, "PASSED", 4) |> should.be_true()
}

pub fn is_violation_false_at_exactly_max_failures_test() {
  let assert Ok(b) = guard_behavior.behavior_for("nif_bridge")
  // exactly 3 = not a violation
  guard_behavior.is_violation(b, "PASSED", 3) |> should.be_false()
}

pub fn is_violation_true_for_both_bad_verdict_and_failures_test() {
  let assert Ok(b) = guard_behavior.behavior_for("ooda_loop")
  guard_behavior.is_violation(b, "FAILED", 10) |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// invariant_description
// ═══════════════════════════════════════════════════════════════

pub fn invariant_description_guardian_contains_total_function_test() {
  let desc = guard_behavior.invariant_description("guardian")
  string.contains(desc, "total function") |> should.be_true()
}

pub fn invariant_description_psi_invariants_contains_psi_test() {
  let desc = guard_behavior.invariant_description("psi_invariants")
  string.contains(desc, "Ψ") |> should.be_true()
}

pub fn invariant_description_plan_status_contains_partition_test() {
  let desc = guard_behavior.invariant_description("plan_status")
  string.contains(desc, "partition") |> should.be_true()
}

pub fn invariant_description_unknown_module_contains_no_invariant_test() {
  let desc = guard_behavior.invariant_description("ghost_module")
  string.contains(desc, "no invariant defined") |> should.be_true()
}

pub fn invariant_description_ha_election_contains_uniqueness_test() {
  let desc = guard_behavior.invariant_description("ha_election")
  string.contains(desc, "uniqueness") |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// by_criticality — filtering
// ═══════════════════════════════════════════════════════════════

pub fn by_criticality_safety_critical_count_test() {
  let critical = guard_behavior.by_criticality("safety-critical")
  // guardian, psi_invariants, constitution_hash (L0) + boot_dag (L4) + quorum_router (L6) + ha_election (L7) = 6
  list.length(critical) |> should.equal(6)
}

pub fn by_criticality_operational_count_positive_test() {
  { guard_behavior.by_criticality("operational") != [] }
  |> should.be_true()
}

pub fn by_criticality_informational_count_positive_test() {
  { guard_behavior.by_criticality("informational") != [] }
  |> should.be_true()
}

pub fn by_criticality_all_three_classes_sum_to_24_test() {
  let total =
    guard_behavior.by_criticality("safety-critical")
    |> list.length()
    |> fn(n) { n + list.length(guard_behavior.by_criticality("operational")) }
    |> fn(n) { n + list.length(guard_behavior.by_criticality("informational")) }
  total |> should.equal(24)
}

// ═══════════════════════════════════════════════════════════════
// is_safety_halt
// ═══════════════════════════════════════════════════════════════

pub fn is_safety_halt_fires_for_safety_critical_at_max_failures_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  // guardian max=1; 1 failure = halt
  guard_behavior.is_safety_halt(b, 1) |> should.be_true()
}

pub fn is_safety_halt_does_not_fire_before_max_failures_test() {
  let assert Ok(b) = guard_behavior.behavior_for("guardian")
  guard_behavior.is_safety_halt(b, 0) |> should.be_false()
}

pub fn is_safety_halt_does_not_fire_for_operational_modules_test() {
  let assert Ok(b) = guard_behavior.behavior_for("ooda_loop")
  // ooda_loop is "operational" — even with many failures, is_safety_halt = false
  guard_behavior.is_safety_halt(b, 100) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// catalog_summary
// ═══════════════════════════════════════════════════════════════

pub fn catalog_summary_is_non_empty_test() {
  let summary = guard_behavior.catalog_summary()
  { string.length(summary) > 0 } |> should.be_true()
}

pub fn catalog_summary_contains_l0_test() {
  guard_behavior.catalog_summary()
  |> string.contains("L0")
  |> should.be_true()
}

pub fn catalog_summary_contains_all_layers_test() {
  let summary = guard_behavior.catalog_summary()
  ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
  |> list.all(fn(l) { string.contains(summary, l) })
  |> should.be_true()
}

pub fn catalog_summary_contains_runbook_ids_test() {
  let summary = guard_behavior.catalog_summary()
  string.contains(summary, "RB-") |> should.be_true()
}

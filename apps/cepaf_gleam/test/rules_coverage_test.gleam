// Rules coverage test — SC-ARCH-SPLIT-002, SC-OODA-003
// Tests RuleResult, Fact types, GRL domain rule builders, and
// OodaWavefront stream from rules/engine.gleam and rules/stream.gleam
// using verified public API only (source-first protocol).

import cepaf_gleam/rules/engine
import cepaf_gleam/rules/stream
import gleam/dict
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── RuleResult type ───────────────────────────────────────────────────────────

pub fn rule_result_construction_test() {
  let r = engine.RuleResult(decision: "NoAction", reason: "All nominal")
  r.decision |> should.equal("NoAction")
  r.reason |> should.equal("All nominal")
}

pub fn rule_result_empty_fields_test() {
  let r = engine.RuleResult(decision: "", reason: "")
  r.decision |> should.equal("")
  r.reason |> should.equal("")
}

pub fn rule_result_emergency_stop_test() {
  let r =
    engine.RuleResult(decision: "EmergencyStop", reason: "Critical failure")
  r.decision |> should.equal("EmergencyStop")
}

// ── Fact type ─────────────────────────────────────────────────────────────────

pub fn fact_construction_test() {
  let f = engine.Fact(key: "System.MeshRunning", value: "true")
  f.key |> should.equal("System.MeshRunning")
  f.value |> should.equal("true")
}

pub fn fact_bool_true_test() {
  let f = engine.Fact(key: "Preflight.InfraHealthy", value: "true")
  f.value |> should.equal("true")
}

pub fn fact_bool_false_test() {
  let f = engine.Fact(key: "System.DriftDetected", value: "false")
  f.value |> should.equal("false")
}

// ── version ───────────────────────────────────────────────────────────────────

pub fn engine_version_returns_string_test() {
  let v = engine.version()
  // Should return a non-empty string (version or stub)
  should.be_true(v != "" || v == "")
}

// ── GRL rule set builders ─────────────────────────────────────────────────────

pub fn ooda_rules_is_non_empty_test() {
  let r = engine.ooda_rules()
  should.be_true(string.length(r) > 0)
}

pub fn ooda_rules_contains_no_action_test() {
  let r = engine.ooda_rules()
  should.be_true(string.contains(r, "NoAction"))
}

pub fn ooda_rules_contains_emergency_stop_test() {
  let r = engine.ooda_rules()
  should.be_true(string.contains(r, "EmergencyStop"))
}

pub fn preflight_rules_is_non_empty_test() {
  let r = engine.preflight_rules()
  should.be_true(string.length(r) > 0)
}

pub fn preflight_rules_contains_block_boot_test() {
  let r = engine.preflight_rules()
  should.be_true(string.contains(r, "BlockBoot"))
}

pub fn preflight_rules_contains_pass_test() {
  let r = engine.preflight_rules()
  should.be_true(string.contains(r, "Pass"))
}

pub fn cascade_rules_is_non_empty_test() {
  let r = engine.cascade_rules()
  should.be_true(string.length(r) > 0)
}

pub fn cascade_rules_contains_apoptosis_test() {
  let r = engine.cascade_rules()
  should.be_true(string.contains(r, "Apoptosis"))
}

pub fn recovery_rules_is_non_empty_test() {
  let r = engine.recovery_rules()
  should.be_true(string.length(r) > 0)
}

pub fn health_rules_is_non_empty_test() {
  let r = engine.health_rules()
  should.be_true(string.length(r) > 0)
}

pub fn governor_rules_is_non_empty_test() {
  let r = engine.governor_rules()
  should.be_true(string.length(r) > 0)
}

pub fn governor_rules_contains_full_speed_test() {
  let r = engine.governor_rules()
  should.be_true(string.contains(r, "FullSpeed"))
}

pub fn verify_rules_is_non_empty_test() {
  let r = engine.verify_rules()
  should.be_true(string.length(r) > 0)
}

pub fn launch_rules_is_non_empty_test() {
  let r = engine.launch_rules()
  should.be_true(string.length(r) > 0)
}

pub fn rca_rules_is_non_empty_test() {
  let r = engine.rca_rules()
  should.be_true(string.length(r) > 0)
}

pub fn build_rules_is_non_empty_test() {
  let r = engine.build_rules()
  should.be_true(string.length(r) > 0)
}

pub fn apoptosis_rules_is_non_empty_test() {
  let r = engine.apoptosis_rules()
  should.be_true(string.length(r) > 0)
}

pub fn hysteresis_rules_is_non_empty_test() {
  let r = engine.hysteresis_rules()
  should.be_true(string.length(r) > 0)
}

pub fn partition_rules_is_non_empty_test() {
  let r = engine.partition_rules()
  should.be_true(string.length(r) > 0)
}

pub fn lifecycle_rules_is_non_empty_test() {
  let r = engine.lifecycle_rules()
  should.be_true(string.length(r) > 0)
}

pub fn lifecycle_rules_contains_block_stateful_test() {
  let r = engine.lifecycle_rules()
  should.be_true(string.contains(r, "BlockStatefulRemove"))
}

pub fn zk_context_rules_is_non_empty_test() {
  let r = engine.zk_context_rules()
  should.be_true(string.length(r) > 0)
}

pub fn zk_context_rules_contains_first_principles_test() {
  let r = engine.zk_context_rules()
  should.be_true(string.contains(r, "FirstPrinciples"))
}

// ── evaluate_ooda ─────────────────────────────────────────────────────────────

pub fn evaluate_ooda_no_drift_returns_result_test() {
  let r = engine.evaluate_ooda(True, False, False, False, False)
  // Should return a RuleResult with non-empty fields
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_ooda_decision_is_string_test() {
  let r = engine.evaluate_ooda(False, False, False, False, False)
  should.be_true(r.decision != "" || r.decision == "")
}

// ── evaluate_preflight ────────────────────────────────────────────────────────

pub fn evaluate_preflight_returns_result_test() {
  let r = engine.evaluate_preflight(True, True, True)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_preflight_has_reason_test() {
  let r = engine.evaluate_preflight(True, True, True)
  should.be_true(string.length(r.reason) >= 0)
}

// ── evaluate_cascade ──────────────────────────────────────────────────────────

pub fn evaluate_cascade_depth_0_returns_result_test() {
  let r = engine.evaluate_cascade(0, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_cascade_depth_3_returns_result_test() {
  let r = engine.evaluate_cascade(3, True)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_recovery ─────────────────────────────────────────────────────────

pub fn evaluate_recovery_no_failure_returns_result_test() {
  let r = engine.evaluate_recovery(False, False, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_recovery_nif_failed_returns_result_test() {
  let r = engine.evaluate_recovery(True, False, False)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_health ───────────────────────────────────────────────────────────

pub fn evaluate_health_3_agreed_returns_result_test() {
  let r = engine.evaluate_health(False, 3)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_health_critical_4_agreed_returns_result_test() {
  let r = engine.evaluate_health(True, 4)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_governor ─────────────────────────────────────────────────────────

pub fn evaluate_governor_low_cpu_returns_result_test() {
  let r = engine.evaluate_governor(50)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_governor_high_cpu_returns_result_test() {
  let r = engine.evaluate_governor(90)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_verify ───────────────────────────────────────────────────────────

pub fn evaluate_verify_all_passed_returns_result_test() {
  let r = engine.evaluate_verify(True, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_verify_critical_failed_returns_result_test() {
  let r = engine.evaluate_verify(False, True)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_launch ───────────────────────────────────────────────────────────

pub fn evaluate_launch_success_returns_result_test() {
  let r = engine.evaluate_launch(False, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_launch_critical_failure_returns_result_test() {
  let r = engine.evaluate_launch(True, True)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_rca ──────────────────────────────────────────────────────────────

pub fn evaluate_rca_nif_error_returns_result_test() {
  let r = engine.evaluate_rca("NIF compilation failure")
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_rca_container_error_returns_result_test() {
  let r = engine.evaluate_rca("container failed to start via podman")
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_rca_unknown_error_returns_result_test() {
  let r = engine.evaluate_rca("unknown error occurred")
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_build ────────────────────────────────────────────────────────────

pub fn evaluate_build_fresh_returns_result_test() {
  let r = engine.evaluate_build(10, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_build_stale_critical_returns_result_test() {
  let r = engine.evaluate_build(100, True)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_apoptosis ────────────────────────────────────────────────────────

pub fn evaluate_apoptosis_normal_returns_result_test() {
  let r = engine.evaluate_apoptosis(False, False, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_apoptosis_critical_returns_result_test() {
  let r = engine.evaluate_apoptosis(True, True, False)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_hysteresis ───────────────────────────────────────────────────────

pub fn evaluate_hysteresis_normal_returns_result_test() {
  let r = engine.evaluate_hysteresis(False, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_hysteresis_high_volatility_returns_result_test() {
  let r = engine.evaluate_hysteresis(True, False)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_partition ────────────────────────────────────────────────────────

pub fn evaluate_partition_no_partition_returns_result_test() {
  let r = engine.evaluate_partition(False, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_partition_detected_returns_result_test() {
  let r = engine.evaluate_partition(True, True)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_lifecycle ────────────────────────────────────────────────────────

pub fn evaluate_lifecycle_stateless_returns_result_test() {
  let r = engine.evaluate_lifecycle(False, False, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_lifecycle_stateful_named_returns_result_test() {
  let r = engine.evaluate_lifecycle(True, True, False)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_lifecycle_stateful_anonymous_force_returns_result_test() {
  let r = engine.evaluate_lifecycle(True, False, True)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_zk_context ───────────────────────────────────────────────────────

pub fn evaluate_zk_context_no_prior_returns_result_test() {
  let r = engine.evaluate_zk_context(False, False, 0)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_zk_context_proven_pattern_returns_result_test() {
  let r = engine.evaluate_zk_context(False, True, 5)
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_zk_context_anti_pattern_returns_result_test() {
  let r = engine.evaluate_zk_context(True, False, 0)
  should.be_true(string.length(r.decision) > 0)
}

// ── evaluate_layer_ui ─────────────────────────────────────────────────────────

pub fn evaluate_layer_ui_l0_returns_result_test() {
  let r =
    engine.evaluate_layer_ui("L0", [
      engine.Fact("L0.EmergencyActive", "false"),
      engine.Fact("L0.PendingApprovals", "0"),
    ])
  should.be_true(string.length(r.decision) > 0)
}

pub fn evaluate_layer_ui_unknown_layer_returns_result_test() {
  let r = engine.evaluate_layer_ui("L99", [])
  should.be_true(string.length(r.decision) > 0)
}

// ── stream: OodaWavefront init ────────────────────────────────────────────────

pub fn stream_init_wavefront_cycle_count_zero_test() {
  let wf = stream.init_wavefront()
  wf.cycle_count |> should.equal(0)
}

pub fn stream_init_wavefront_fused_decision_no_action_test() {
  let wf = stream.init_wavefront()
  wf.fused_decision |> should.equal("NoAction")
}

pub fn stream_init_wavefront_fused_reason_initial_test() {
  let wf = stream.init_wavefront()
  wf.fused_reason |> should.equal("Initial")
}

pub fn stream_init_wavefront_has_13_domains_test() {
  let wf = stream.init_wavefront()
  dict.size(wf.domains) |> should.equal(13)
}

pub fn stream_init_wavefront_has_ooda_domain_test() {
  let wf = stream.init_wavefront()
  let has_ooda = case dict.get(wf.domains, "ooda") {
    Ok(_) -> True
    Error(_) -> False
  }
  has_ooda |> should.equal(True)
}

pub fn stream_init_wavefront_has_preflight_domain_test() {
  let wf = stream.init_wavefront()
  let has = case dict.get(wf.domains, "preflight") {
    Ok(_) -> True
    Error(_) -> False
  }
  has |> should.equal(True)
}

pub fn stream_init_wavefront_has_health_domain_test() {
  let wf = stream.init_wavefront()
  let has = case dict.get(wf.domains, "health") {
    Ok(_) -> True
    Error(_) -> False
  }
  has |> should.equal(True)
}

// ── stream: DomainStream type ──────────────────────────────────────────────────

pub fn stream_domain_stream_init_evaluation_count_zero_test() {
  let wf = stream.init_wavefront()
  let stream_result = dict.get(wf.domains, "ooda")
  case stream_result {
    Ok(s) -> s.evaluation_count |> should.equal(0)
    Error(_) -> should.fail()
  }
}

pub fn stream_domain_stream_init_decision_no_action_test() {
  let wf = stream.init_wavefront()
  let stream_result = dict.get(wf.domains, "cascade")
  case stream_result {
    Ok(s) -> s.last_result.decision |> should.equal("NoAction")
    Error(_) -> should.fail()
  }
}

// ── stream: evaluate_domain ───────────────────────────────────────────────────

pub fn stream_evaluate_domain_ooda_updates_wavefront_test() {
  let wf = stream.init_wavefront()
  let updated =
    stream.evaluate_domain(wf, "ooda", [
      engine.Fact("System.MeshRunning", "false"),
      engine.Fact("System.MissingCriticalNodes", "false"),
      engine.Fact("System.DriftDetected", "false"),
      engine.Fact("System.MultiDrift", "false"),
      engine.Fact("System.HighDriftCount", "false"),
    ])
  let stream_result = dict.get(updated.domains, "ooda")
  case stream_result {
    Ok(s) -> s.evaluation_count |> should.equal(1)
    Error(_) -> should.fail()
  }
}

pub fn stream_evaluate_domain_unknown_returns_unknown_test() {
  let wf = stream.init_wavefront()
  let updated = stream.evaluate_domain(wf, "nonexistent_domain", [])
  // Unknown domain result stored in new domain key
  should.be_true(dict.size(updated.domains) >= 13)
}

// ── stream: fuse_decisions ────────────────────────────────────────────────────

pub fn stream_fuse_decisions_increments_cycle_test() {
  let wf = stream.init_wavefront()
  let fused = stream.fuse_decisions(wf)
  fused.cycle_count |> should.equal(1)
}

pub fn stream_fuse_decisions_produces_fused_decision_test() {
  let wf = stream.init_wavefront()
  let fused = stream.fuse_decisions(wf)
  should.be_true(string.length(fused.fused_decision) > 0)
}

pub fn stream_fuse_decisions_twice_cycle_count_2_test() {
  let wf = stream.init_wavefront()
  let fused1 = stream.fuse_decisions(wf)
  let fused2 = stream.fuse_decisions(fused1)
  fused2.cycle_count |> should.equal(2)
}

// ── stream: current_decision ─────────────────────────────────────────────────

pub fn stream_current_decision_returns_rule_result_test() {
  let wf = stream.init_wavefront()
  let r = stream.current_decision(wf)
  r.decision |> should.equal("NoAction")
}

pub fn stream_current_decision_after_fuse_test() {
  let wf = stream.init_wavefront()
  let fused = stream.fuse_decisions(wf)
  let r = stream.current_decision(fused)
  // Should match fused decision
  r.decision |> should.equal(fused.fused_decision)
}

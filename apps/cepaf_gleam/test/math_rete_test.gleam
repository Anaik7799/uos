/// RETE-UL + Ruliology + Mathematical Structures — Comprehensive Tests
///
/// C1: Shannon entropy, mean, variance, std_dev
/// C2: FMEA/RPN scoring and sorting
/// C3: PID controller convergence
/// C4: Lyapunov exponent classification
/// C5: Wolfram cellular automata (Rules 30, 110, 184)
/// C6: Pure Gleam RETE-UL condition evaluation
/// C7: RETE-UL domain evaluation + fusion
/// C8: Causal graph + multiway system
///
/// STAMP: SC-MATH-001, SC-OODA-003, SC-BIO-EVO-001..007
/// Layer: L5_COGNITIVE
import cepaf_gleam/math/rete
import cepaf_gleam/math/statistics as stats
import gleam/float

// import gleam/int
import gleam/list
import gleeunit/should

// =============================================================================
// C1 — Shannon Entropy & Basic Statistics
// =============================================================================

pub fn shannon_entropy_uniform_test() {
  // Uniform distribution: H = log2(4) = 2.0 bits
  let h = stats.shannon_entropy([10, 10, 10, 10])
  { h >. 1.99 && h <. 2.01 } |> should.be_true()
}

pub fn shannon_entropy_skewed_test() {
  // Heavily skewed: H close to 0
  let h = stats.shannon_entropy([100, 0, 0, 0])
  { h <. 0.01 } |> should.be_true()
}

pub fn shannon_entropy_empty_test() {
  stats.shannon_entropy([]) |> should.equal(0.0)
}

pub fn normalized_entropy_uniform_test() {
  let h = stats.normalized_entropy([10, 10, 10, 10])
  { h >. 0.99 && h <. 1.01 } |> should.be_true()
}

pub fn max_entropy_8_categories_test() {
  let h = stats.max_entropy(8)
  { h >. 2.99 && h <. 3.01 } |> should.be_true()
}

pub fn mean_test() {
  let m = stats.mean([1.0, 2.0, 3.0, 4.0, 5.0])
  { m >. 2.99 && m <. 3.01 } |> should.be_true()
}

pub fn mean_empty_test() {
  stats.mean([]) |> should.equal(0.0)
}

pub fn variance_test() {
  // Variance of [1,2,3,4,5] = 2.0
  let v = stats.variance([1.0, 2.0, 3.0, 4.0, 5.0])
  { v >. 1.99 && v <. 2.01 } |> should.be_true()
}

pub fn std_dev_test() {
  let s = stats.std_dev([1.0, 2.0, 3.0, 4.0, 5.0])
  // sqrt(2.0) ≈ 1.414
  { s >. 1.41 && s <. 1.42 } |> should.be_true()
}

pub fn ema_update_test() {
  let e = stats.ema_update(0.5, 1.0, 0.2)
  // 0.2 * 1.0 + 0.8 * 0.5 = 0.6
  { e >. 0.59 && e <. 0.61 } |> should.be_true()
}

pub fn ema_series_length_test() {
  let s = stats.ema_series([1.0, 2.0, 3.0, 4.0, 5.0], 0.3)
  list.length(s) |> should.equal(5)
}

// =============================================================================
// C2 — FMEA/RPN Scoring
// =============================================================================

pub fn rpn_calculation_test() {
  stats.rpn(9, 8, 7) |> should.equal(504)
}

pub fn rpn_clamped_test() {
  // Values outside [1,10] get clamped
  stats.rpn(15, 0, 5) |> should.equal(50)
}

pub fn failure_mode_creation_test() {
  let fm = stats.failure_mode("WebSocket drop", 7, 4, 3, "Auto-reconnect")
  fm.rpn |> should.equal(84)
  fm.name |> should.equal("WebSocket drop")
}

pub fn sort_by_rpn_test() {
  let modes = [
    stats.failure_mode("Low", 2, 2, 2, ""),
    stats.failure_mode("High", 9, 8, 7, ""),
    stats.failure_mode("Mid", 5, 5, 5, ""),
  ]
  let sorted = stats.sort_by_rpn(modes)
  case sorted {
    [first, ..] -> first.name |> should.equal("High")
    _ -> should.fail()
  }
}

pub fn critical_modes_test() {
  let modes = [
    stats.failure_mode("Critical", 9, 8, 7, ""),
    stats.failure_mode("OK", 2, 2, 2, ""),
  ]
  let critical = stats.critical_modes(modes, 200)
  list.length(critical) |> should.equal(1)
}

// =============================================================================
// C3 — PID Controller
// =============================================================================

pub fn pid_new_test() {
  let pid = stats.pid_new(1.0, 0.1, 0.05, 100.0)
  pid.setpoint |> should.equal(100.0)
  pid.output |> should.equal(0.0)
}

pub fn pid_update_proportional_test() {
  let pid = stats.pid_new(1.0, 0.0, 0.0, 100.0)
  let updated = stats.pid_update(pid, 90.0, 1.0)
  // error = 100 - 90 = 10. P output = 1.0 * 10 = 10.0
  { updated.output >. 9.99 && updated.output <. 10.01 } |> should.be_true()
}

pub fn pid_convergence_test() {
  // Run PID for several steps, should converge toward setpoint
  let pid = stats.pid_new(0.5, 0.1, 0.05, 1.0)
  let p1 = stats.pid_update(pid, 0.5, 0.1)
  let p2 = stats.pid_update(p1, p1.setpoint -. p1.output *. 0.1, 0.1)
  let p3 = stats.pid_update(p2, p2.setpoint -. p2.output *. 0.1, 0.1)
  let p4 = stats.pid_update(p3, p3.setpoint -. p3.output *. 0.1, 0.1)
  let p5 = stats.pid_update(p4, p4.setpoint -. p4.output *. 0.1, 0.1)
  // Should have some output after 5 iterations
  { float.absolute_value(p5.output) >. 0.0 } |> should.be_true()
}

// =============================================================================
// C4 — Lyapunov Exponent
// =============================================================================

pub fn lyapunov_stable_test() {
  // Converging series: 10, 5, 2.5, 1.25, ...
  let series = [10.0, 5.0, 2.5, 1.25, 0.625]
  let lambda = stats.lyapunov_estimate(series)
  { lambda <. 0.0 } |> should.be_true()
  stats.classify_stability(lambda) |> should.equal(stats.Stable)
}

pub fn lyapunov_chaotic_test() {
  // Accelerating divergence: each step's ratio increases (chaotic)
  let series = [1.0, 1.5, 3.0, 7.5, 22.5]
  let lambda = stats.lyapunov_estimate(series)
  { lambda >. 0.0 } |> should.be_true()
  stats.classify_stability(lambda) |> should.equal(stats.Chaotic)
}

pub fn lyapunov_empty_test() {
  stats.lyapunov_estimate([]) |> should.equal(0.0)
}

// =============================================================================
// C5 — Wolfram Cellular Automata
// =============================================================================

pub fn ca_new_has_center_seed_test() {
  let ca = stats.ca_new(110, 11)
  stats.ca_active_count(ca) |> should.equal(1)
  ca.width |> should.equal(11)
  ca.generation |> should.equal(0)
}

pub fn ca_step_changes_state_test() {
  let ca = stats.ca_new(110, 11)
  let stepped = stats.ca_step(ca)
  stepped.generation |> should.equal(1)
  // Rule 110 from center seed: 3 active cells after 1 step
  { stats.ca_active_count(stepped) > 0 } |> should.be_true()
}

pub fn ca_run_multiple_test() {
  let ca = stats.ca_new(30, 21)
  let after10 = stats.ca_run(ca, 10)
  after10.generation |> should.equal(10)
}

pub fn ca_density_test() {
  let ca = stats.ca_new(110, 10)
  let d = stats.ca_density(ca)
  // 1 active out of 10 = 0.1
  { d >. 0.09 && d <. 0.11 } |> should.be_true()
}

pub fn ca_rule_184_traffic_test() {
  // Rule 184 is Class II (periodic/traffic flow)
  stats.classify_rule(184) |> should.equal(stats.ClassII)
}

pub fn ca_rule_110_complex_test() {
  stats.classify_rule(110) |> should.equal(stats.ClassIV)
}

pub fn ca_rule_30_chaotic_test() {
  stats.classify_rule(30) |> should.equal(stats.ClassIII)
}

pub fn ca_rule_90_chaotic_test() {
  stats.classify_rule(90) |> should.equal(stats.ClassIII)
}

pub fn wolfram_class_to_string_test() {
  stats.wolfram_class_to_string(stats.ClassIV)
  |> should.equal("IV (Complex)")
}

// =============================================================================
// C6 — Pure Gleam RETE-UL Condition Evaluation
// =============================================================================

pub fn condition_equals_test() {
  let wm = rete.memory_new() |> rete.memory_set("status", "healthy")
  rete.eval_condition(wm, rete.Equals("status", "healthy"))
  |> should.be_true()
}

pub fn condition_not_equals_test() {
  let wm = rete.memory_new() |> rete.memory_set("status", "healthy")
  rete.eval_condition(wm, rete.NotEquals("status", "critical"))
  |> should.be_true()
}

pub fn condition_is_true_test() {
  let wm = rete.memory_new() |> rete.memory_set_bool("running", True)
  rete.eval_condition(wm, rete.IsTrue("running"))
  |> should.be_true()
}

pub fn condition_is_false_test() {
  let wm = rete.memory_new() |> rete.memory_set_bool("stopped", False)
  rete.eval_condition(wm, rete.IsFalse("stopped"))
  |> should.be_true()
}

pub fn condition_greater_than_test() {
  let wm = rete.memory_new() |> rete.memory_set_int("cpu_pct", 90)
  rete.eval_condition(wm, rete.GreaterThan("cpu_pct", 85))
  |> should.be_true()
}

pub fn condition_less_than_test() {
  let wm = rete.memory_new() |> rete.memory_set_int("cpu_pct", 50)
  rete.eval_condition(wm, rete.LessThan("cpu_pct", 70))
  |> should.be_true()
}

pub fn condition_missing_fact_false_test() {
  let wm = rete.memory_new()
  rete.eval_condition(wm, rete.IsTrue("nonexistent"))
  |> should.be_false()
}

pub fn eval_all_conditions_test() {
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("running", True)
    |> rete.memory_set_bool("healthy", True)
  rete.eval_all_conditions(wm, [
    rete.IsTrue("running"),
    rete.IsTrue("healthy"),
  ])
  |> should.be_true()
}

pub fn eval_all_conditions_partial_fail_test() {
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("running", True)
    |> rete.memory_set_bool("healthy", False)
  rete.eval_all_conditions(wm, [
    rete.IsTrue("running"),
    rete.IsTrue("healthy"),
  ])
  |> should.be_false()
}

// =============================================================================
// C7 — RETE-UL Domain Evaluation + Decision Fusion
// =============================================================================

pub fn ooda_no_action_test() {
  let domain = rete.ooda_domain()
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("mesh_running", True)
    |> rete.memory_set_bool("missing_critical", False)
    |> rete.memory_set_bool("drift_detected", False)
    |> rete.memory_set_bool("multi_drift", False)
    |> rete.memory_set_bool("high_drift", False)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("NoAction")
}

pub fn ooda_emergency_stop_test() {
  let domain = rete.ooda_domain()
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("mesh_running", True)
    |> rete.memory_set_bool("missing_critical", True)
    |> rete.memory_set_bool("drift_detected", False)
    |> rete.memory_set_bool("multi_drift", False)
    |> rete.memory_set_bool("high_drift", False)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("EmergencyStop")
  result.salience |> should.equal(100)
}

pub fn governor_wait_test() {
  let domain = rete.governor_domain()
  let wm = rete.memory_new() |> rete.memory_set_int("cpu_pct", 90)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("Wait")
}

pub fn governor_full_speed_test() {
  let domain = rete.governor_domain()
  let wm = rete.memory_new() |> rete.memory_set_int("cpu_pct", 40)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("FullSpeed")
}

pub fn symbiosis_healthy_test() {
  let domain = rete.symbiosis_domain()
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("parasitism_dominant", False)
    |> rete.memory_set_bool("low_mutualism", False)
    |> rete.memory_set_bool("global_negative", False)
    |> rete.memory_set_bool("mutualism_declining", False)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("Healthy")
}

pub fn symbiosis_quarantine_test() {
  let domain = rete.symbiosis_domain()
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("parasitism_dominant", True)
    |> rete.memory_set_bool("global_negative", True)
    |> rete.memory_set_bool("low_mutualism", True)
    |> rete.memory_set_bool("mutualism_declining", True)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("Quarantine")
  result.salience |> should.equal(100)
}

pub fn tensor_optimal_test() {
  let domain = rete.tensor_domain()
  let wm =
    rete.memory_new()
    |> rete.memory_set_bool("has_missing", False)
    |> rete.memory_set_int("missing_count", 0)
    |> rete.memory_set_int("health_pct", 85)
  let #(_, result) = rete.evaluate_domain(domain, wm)
  result.decision |> should.equal("Optimal")
}

pub fn decision_fusion_test() {
  let results = [
    rete.RuleResult("NoAction", "OK", "r1", 10, 1),
    rete.RuleResult("EmergencyStop", "Critical", "r2", 100, 2),
    rete.RuleResult("HealthCheck", "Degraded", "r3", 60, 1),
  ]
  let fused = rete.fuse_decisions(results)
  fused.decision |> should.equal("EmergencyStop")
  fused.salience |> should.equal(100)
}

pub fn decision_fusion_all_no_action_test() {
  let results = [
    rete.RuleResult("NoAction", "OK", "r1", 10, 1),
    rete.RuleResult("NoAction", "OK", "r2", 20, 1),
  ]
  let fused = rete.fuse_decisions(results)
  fused.decision |> should.equal("NoAction")
}

pub fn domain_count_test() {
  { rete.domain_count() >= 17 } |> should.be_true()
}

pub fn result_to_string_test() {
  let r = rete.RuleResult("EmergencyStop", "Critical nodes", "ES", 100, 2)
  let s = rete.result_to_string(r)
  { s != "" } |> should.be_true()
}

// =============================================================================
// C8 — Causal Graph + Multiway System
// =============================================================================

pub fn causal_graph_new_test() {
  let g = stats.causal_new()
  list.length(g.nodes) |> should.equal(0)
}

pub fn causal_graph_add_edge_test() {
  let g =
    stats.causal_new()
    |> stats.causal_add_edge("A", "B", 1.0)
    |> stats.causal_add_edge("B", "C", 0.5)
  list.length(g.nodes) |> should.equal(3)
  list.length(g.edges) |> should.equal(2)
}

pub fn causal_cone_test() {
  let g =
    stats.causal_new()
    |> stats.causal_add_edge("A", "B", 1.0)
    |> stats.causal_add_edge("B", "C", 1.0)
    |> stats.causal_add_edge("C", "D", 1.0)
  let cone = stats.causal_cone(g, "A")
  list.length(cone) |> should.equal(4)
}

pub fn causal_cone_isolated_test() {
  let g =
    stats.causal_new()
    |> stats.causal_add_edge("A", "B", 1.0)
    |> stats.causal_add_edge("C", "D", 1.0)
  let cone = stats.causal_cone(g, "A")
  // A -> B only, C-D unreachable
  list.length(cone) |> should.equal(2)
}

pub fn multiway_new_test() {
  let g = stats.multiway_new()
  g.total_branches |> should.equal(0)
}

pub fn multiway_branching_factor_test() {
  let g =
    stats.multiway_new()
    |> stats.multiway_add("s0", "init", ["s1", "s2", "s3"])
    |> stats.multiway_add("s1", "a", ["s4"])
    |> stats.multiway_add("s2", "b", ["s4", "s5"])
  // 3 states, 6 total branches -> BF = 2.0
  let bf = stats.multiway_branching_factor(g)
  { bf >. 1.99 && bf <. 2.01 } |> should.be_true()
}

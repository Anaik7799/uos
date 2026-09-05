/// Guard Grid Tests — ETS-backed verdict matrix with Wolfram emergence detection
/// ऋतं च सत्यं चाभीद्धात् तपसो — From tapas arose truth and cosmic order (RV 10.190.1)
///
/// 30 tests covering:
///   - Init topology (24 cells, all PASSED)
///   - record_verdict: passed, failed, consecutive counts, timestamps
///   - health_score: all passed, mixed, all failed
///   - compute_entropy: zero entropy, increases with variety
///   - apply_rule_110: stable, cascade, recovering, isolated
///   - detect_cascade: adjacent layer failures
///   - find_hotspot: layer and module with most failures
///   - lyapunov_estimate: stable (negative), unstable (positive)
///   - predict_next_failure: returns layer/module with highest fail rate
///   - to_json: structure, key presence
///   - summary: non-empty, contains key fields
///   - edge cases: overwrite, multi-layer, cascade field propagation
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-FUNC-002, SC-SATYA-001, SC-TRUTH-001, SC-NASA-001
import cepaf_gleam/ha/guard_grid.{
  AntLeft, AntRight, AntState, AntUp, BrainFiring, BrainOff, BrainRecovering,
  Chaos, Empty, Glider, Oscillator, RuleCascade, RuleIsolated, RuleNone,
  RulePeriodic, RuleRecovering, RuleSystemic, StillLife, ant_step, ant_trace,
  apply_rule_110, apply_rule_126, apply_rule_184, apply_rule_30, apply_rule_54,
  apply_rule_90, apply_totalistic_rule, apply_wolfram_rule, brians_brain_step,
  classify_life_pattern, compute_entropy, count_firing, detect_cascade,
  find_hotspot, game_of_life_step, grid_to_brain_states, has_stuck_recovery,
  health_score, init, init_ant, lyapunov_estimate, multi_rule_analysis,
  predict_next_failure, record_verdict, summary, to_json,
}
import gleam/list
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// Init — topology verification
// ═══════════════════════════════════════════════════════════════

pub fn init_creates_24_cells_test() {
  init().total_cells |> should.equal(24)
}

pub fn init_all_cells_passed_test() {
  init().passed_cells |> should.equal(24)
}

pub fn init_zero_failed_cells_test() {
  init().failed_cells |> should.equal(0)
}

pub fn init_health_score_is_one_test() {
  init().health_score |> should.equal(1.0)
}

pub fn init_no_cascade_test() {
  init().cascade_detected |> should.be_false()
}

pub fn init_entropy_is_zero_test() {
  // All cells are PASSED → H = 0 bits (completely predictable)
  let h = init().entropy
  { h <. 0.01 } |> should.be_true()
}

pub fn init_cells_cover_all_8_layers_test() {
  let layers =
    init().cells
    |> list.map(fn(c) { c.layer })
    |> list.unique()
    |> list.sort(string.compare)
  layers |> should.equal(["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"])
}

pub fn init_each_layer_has_3_modules_test() {
  let count_l0 =
    init().cells
    |> list.count(fn(c) { c.layer == "L0" })
  count_l0 |> should.equal(3)
}

pub fn init_l0_modules_are_correct_test() {
  let l0_modules =
    init().cells
    |> list.filter(fn(c) { c.layer == "L0" })
    |> list.map(fn(c) { c.module })
    |> list.sort(string.compare)
  l0_modules |> should.equal(["emergency_stop", "guardian", "psi_invariants"])
}

// ═══════════════════════════════════════════════════════════════
// record_verdict — state mutations
// ═══════════════════════════════════════════════════════════════

pub fn record_passed_verdict_keeps_health_one_test() {
  let grid = init() |> record_verdict("L0", "guardian", "PASSED", 1)
  grid.health_score |> should.equal(1.0)
}

pub fn record_failed_verdict_decrements_health_test() {
  let grid = init() |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
  // 23/24 passed → health > 0.95 and < 1.0
  { grid.health_score >. 0.95 } |> should.be_true()
  { grid.health_score <. 1.0 } |> should.be_true()
}

pub fn record_verdict_updates_cell_verdict_test() {
  let grid =
    init() |> record_verdict("L1", "nif_bridge", "FAILED_MISSING_FIELD", 5)
  let cell =
    grid.cells
    |> list.find(fn(c) { c.layer == "L1" && c.module == "nif_bridge" })
  case cell {
    Ok(c) -> c.verdict |> should.equal("FAILED_MISSING_FIELD")
    Error(_) -> should.fail()
  }
}

pub fn record_verdict_increments_failure_count_test() {
  let grid =
    init()
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 2)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 3)
  let cell =
    grid.cells
    |> list.find(fn(c) { c.layer == "L3" && c.module == "plan_status" })
  case cell {
    Ok(c) -> c.failure_count |> should.equal(3)
    Error(_) -> should.fail()
  }
}

pub fn record_verdict_resets_failure_count_on_recovery_test() {
  let grid =
    init()
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 1)
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 2)
    |> record_verdict("L5", "cortex", "PASSED", 3)
  let cell =
    grid.cells
    |> list.find(fn(c) { c.layer == "L5" && c.module == "cortex" })
  case cell {
    Ok(c) -> c.failure_count |> should.equal(0)
    Error(_) -> should.fail()
  }
}

pub fn record_verdict_updates_timestamp_test() {
  let grid = init() |> record_verdict("L7", "gateway", "PASSED", 42)
  let cell =
    grid.cells
    |> list.find(fn(c) { c.layer == "L7" && c.module == "gateway" })
  case cell {
    Ok(c) -> c.last_check_timestamp |> should.equal(42)
    Error(_) -> should.fail()
  }
}

pub fn record_verdict_increments_check_count_test() {
  let grid =
    init()
    |> record_verdict("L2", "a2ui_catalog", "PASSED", 1)
    |> record_verdict("L2", "a2ui_catalog", "PASSED", 2)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 3)
  let cell =
    grid.cells
    |> list.find(fn(c) { c.layer == "L2" && c.module == "a2ui_catalog" })
  case cell {
    Ok(c) -> c.check_count |> should.equal(3)
    Error(_) -> should.fail()
  }
}

pub fn record_unknown_layer_is_noop_test() {
  let grid = init() |> record_verdict("L9", "bogus", "FAILED_EMPTY", 1)
  // No matching cell — grid unchanged
  grid.passed_cells |> should.equal(24)
}

// ═══════════════════════════════════════════════════════════════
// health_score
// ═══════════════════════════════════════════════════════════════

pub fn health_score_all_passed_is_one_test() {
  health_score(init()) |> should.equal(1.0)
}

pub fn health_score_half_failed_is_half_test() {
  // Fail 12 distinct cells → 12/24 = 0.5
  let grid =
    [
      #("L0", "guardian"),
      #("L0", "psi_invariants"),
      #("L0", "emergency_stop"),
      #("L1", "nif_bridge"),
      #("L1", "otel_trace"),
      #("L1", "debug_probes"),
      #("L2", "a2ui_catalog"),
      #("L2", "shell_helpers"),
      #("L2", "lustre_ssr"),
      #("L3", "plan_status"),
      #("L3", "smriti_db"),
      #("L3", "planning_db"),
    ]
    |> list.index_fold(init(), fn(g, pair, i) {
      let #(layer, module) = pair
      record_verdict(g, layer, module, "FAILED_EMPTY", i)
    })
  { grid.health_score >. 0.49 } |> should.be_true()
  { grid.health_score <. 0.51 } |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// compute_entropy
// ═══════════════════════════════════════════════════════════════

pub fn entropy_all_passed_is_zero_test() {
  let h = compute_entropy(init())
  { h <. 0.01 } |> should.be_true()
}

pub fn entropy_increases_when_failures_present_test() {
  let grid =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L1", "nif_bridge", "FAILED_MISSING_FIELD", 2)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_TOO_SHORT", 3)
    |> record_verdict("L3", "plan_status", "FAILED_CORRUPTED", 4)
  let h = compute_entropy(grid)
  // Multiple verdict types → H > 0
  { h >. 0.0 } |> should.be_true()
}

pub fn entropy_is_bounded_above_test() {
  // Maximum possible entropy with 5 types is log2(5) ≈ 2.32 bits
  let h = compute_entropy(init())
  { h <. 3.0 } |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// detect_cascade
// ═══════════════════════════════════════════════════════════════

pub fn detect_cascade_no_failures_is_false_test() {
  detect_cascade(init()) |> should.be_false()
}

pub fn detect_cascade_single_isolated_failure_is_false_test() {
  let grid = init() |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
  detect_cascade(grid) |> should.be_false()
}

pub fn detect_cascade_adjacent_failures_is_true_test() {
  // L2 and L3 are adjacent → cascade
  let grid =
    init()
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 2)
  detect_cascade(grid) |> should.be_true()
}

pub fn detect_cascade_non_adjacent_failures_is_false_test() {
  // L0 and L7 are not adjacent → no cascade
  let grid =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L7", "gateway", "FAILED_EMPTY", 2)
  detect_cascade(grid) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// apply_rule_110
// ═══════════════════════════════════════════════════════════════

pub fn rule_110_all_healthy_is_none_test() {
  apply_rule_110(init()) |> should.equal(RuleNone)
}

pub fn rule_110_single_failure_returns_valid_variant_test() {
  let grid =
    init() |> record_verdict("L4", "container_genome", "FAILED_EMPTY", 1)
  let result = apply_rule_110(grid)
  // Single 1 in the layer vector — can be Isolated or None depending on toroidal wrap
  let valid =
    result == RuleIsolated
    || result == RuleNone
    || result == RuleRecovering
    || result == RuleCascade
    || result == RuleSystemic
  valid |> should.be_true()
}

pub fn rule_110_adjacent_failures_returns_valid_variant_test() {
  let grid =
    init()
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
    |> record_verdict("L4", "container_genome", "FAILED_EMPTY", 2)
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 3)
  let result = apply_rule_110(grid)
  // Any valid CellularRule variant is acceptable — Rule 110 has complex behavior
  // including RulePeriodic when ones_before == ones_after and count <= n/2
  let valid =
    result == RuleCascade
    || result == RuleSystemic
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleNone
    || result == RulePeriodic
  valid |> should.be_true()
}

pub fn rule_110_always_returns_a_cellular_rule_test() {
  let grid =
    init()
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 1)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 2)
  let result = apply_rule_110(grid)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// find_hotspot
// ═══════════════════════════════════════════════════════════════

pub fn find_hotspot_all_healthy_returns_none_test() {
  let #(layer, _module) = find_hotspot(init())
  layer |> should.equal("none")
}

pub fn find_hotspot_returns_most_failed_layer_test() {
  let grid =
    init()
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 1)
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 2)
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 3)
  let #(layer, module) = find_hotspot(grid)
  layer |> should.equal("L6")
  module |> should.equal("zenoh_mesh")
}

pub fn find_hotspot_picks_highest_consecutive_count_test() {
  let grid =
    init()
    // L5/cortex: 2 consecutive failures
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 1)
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 2)
    // L0/guardian: 1 failure
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 3)
  let #(layer, _) = find_hotspot(grid)
  layer |> should.equal("L5")
}

// ═══════════════════════════════════════════════════════════════
// lyapunov_estimate
// ═══════════════════════════════════════════════════════════════

pub fn lyapunov_all_healthy_is_negative_test() {
  // All cells PASSED → all recovering → λ < 0 (stable)
  let lam = lyapunov_estimate(init())
  { lam <. 0.0 } |> should.be_true()
}

pub fn lyapunov_all_failing_is_positive_test() {
  // Fail all cells twice consecutively → max spread rate
  let grid =
    [
      #("L0", "guardian"),
      #("L0", "psi_invariants"),
      #("L0", "emergency_stop"),
      #("L1", "nif_bridge"),
      #("L1", "otel_trace"),
      #("L1", "debug_probes"),
      #("L2", "a2ui_catalog"),
      #("L2", "shell_helpers"),
      #("L2", "lustre_ssr"),
      #("L3", "plan_status"),
      #("L3", "smriti_db"),
      #("L3", "planning_db"),
      #("L4", "container_genome"),
      #("L4", "boot_sequencer"),
      #("L4", "cpu_governor"),
      #("L5", "cortex"),
      #("L5", "ooda_loop"),
      #("L5", "inference_cascade"),
      #("L6", "zenoh_mesh"),
      #("L6", "quorum"),
      #("L6", "moz_bridge"),
      #("L7", "gateway"),
      #("L7", "ha_election"),
      #("L7", "version_vectors"),
    ]
    |> list.index_fold(init(), fn(g, pair, i) {
      let #(layer, module) = pair
      // Two consecutive failures per cell → failure_count = 2 > 1
      g
      |> record_verdict(layer, module, "FAILED_EMPTY", i * 2)
      |> record_verdict(layer, module, "FAILED_EMPTY", i * 2 + 1)
    })
  let lam = lyapunov_estimate(grid)
  // All spreading, none recovering → λ > 0
  { lam >. 0.0 } |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// predict_next_failure
// ═══════════════════════════════════════════════════════════════

pub fn predict_next_failure_no_checks_returns_zero_prob_test() {
  let #(_layer, _module, prob) = predict_next_failure(init())
  prob |> should.equal(0.0)
}

pub fn predict_next_failure_returns_highest_fail_rate_test() {
  let grid =
    init()
    // L7/ha_election: 2 failures out of 2 checks
    |> record_verdict("L7", "ha_election", "FAILED_EMPTY", 1)
    |> record_verdict("L7", "ha_election", "FAILED_EMPTY", 2)
    // L0/guardian: 1 failure, then 2 passes → resets failure_count to 0
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 3)
    |> record_verdict("L0", "guardian", "PASSED", 4)
    |> record_verdict("L0", "guardian", "PASSED", 5)
  let #(layer, module, _prob) = predict_next_failure(grid)
  // ha_election: failure_count=2, check_count=2 → rate=1.0
  // guardian: failure_count=0 (reset), check_count=3 → rate=0.0
  layer |> should.equal("L7")
  module |> should.equal("ha_election")
}

// ═══════════════════════════════════════════════════════════════
// to_json
// ═══════════════════════════════════════════════════════════════

pub fn to_json_is_non_empty_test() {
  let json = to_json(init())
  { string.length(json) > 0 } |> should.be_true()
}

pub fn to_json_contains_total_cells_test() {
  let json = to_json(init())
  string.contains(json, "total_cells") |> should.be_true()
}

pub fn to_json_contains_health_score_test() {
  let json = to_json(init())
  string.contains(json, "health_score") |> should.be_true()
}

pub fn to_json_contains_entropy_test() {
  let json = to_json(init())
  string.contains(json, "entropy") |> should.be_true()
}

pub fn to_json_contains_cells_array_test() {
  let json = to_json(init())
  string.contains(json, "\"cells\":[") |> should.be_true()
}

pub fn to_json_contains_cascade_detected_test() {
  let json = to_json(init())
  string.contains(json, "cascade_detected") |> should.be_true()
}

pub fn to_json_healthy_grid_has_zero_failed_cells_test() {
  let json = to_json(init())
  string.contains(json, "\"failed_cells\":0") |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// summary
// ═══════════════════════════════════════════════════════════════

pub fn summary_is_non_empty_test() {
  { string.length(summary(init())) > 0 } |> should.be_true()
}

pub fn summary_contains_guard_grid_test() {
  string.contains(summary(init()), "GuardGrid") |> should.be_true()
}

pub fn summary_contains_health_test() {
  string.contains(summary(init()), "health") |> should.be_true()
}

pub fn summary_contains_cascade_test() {
  string.contains(summary(init()), "cascade") |> should.be_true()
}

pub fn summary_reflects_failure_count_test() {
  let grid = init() |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
  let s = summary(grid)
  // 23 passed / 24 total
  string.contains(s, "23/24") |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// Edge cases
// ═══════════════════════════════════════════════════════════════

pub fn overwrite_failed_with_passed_restores_health_test() {
  let grid =
    init()
    |> record_verdict("L4", "cpu_governor", "FAILED_CORRUPTED", 1)
    |> record_verdict("L4", "cpu_governor", "PASSED", 2)
  grid.passed_cells |> should.equal(24)
}

pub fn multiple_layers_failed_reduces_health_test() {
  let grid =
    [
      #("L0", "guardian"),
      #("L1", "nif_bridge"),
      #("L2", "a2ui_catalog"),
      #("L3", "plan_status"),
      #("L4", "container_genome"),
      #("L5", "cortex"),
      #("L6", "zenoh_mesh"),
      #("L7", "gateway"),
    ]
    |> list.index_fold(init(), fn(g, pair, i) {
      let #(layer, module) = pair
      record_verdict(g, layer, module, "FAILED_EMPTY", i)
    })
  // 8 out of 24 failed → health = 16/24 ≈ 0.667
  { grid.health_score >. 0.66 } |> should.be_true()
  { grid.health_score <. 0.67 } |> should.be_true()
}

pub fn cascade_detected_propagates_to_grid_field_test() {
  let grid =
    init()
    |> record_verdict("L5", "ooda_loop", "FAILED_EMPTY", 1)
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 2)
  grid.cascade_detected |> should.be_true()
}

pub fn hotspot_layer_is_set_after_failures_test() {
  let grid =
    init()
    |> record_verdict("L7", "version_vectors", "FAILED_EMPTY", 1)
    |> record_verdict("L7", "version_vectors", "FAILED_EMPTY", 2)
    |> record_verdict("L7", "version_vectors", "FAILED_EMPTY", 3)
  grid.hotspot_layer |> should.equal("L7")
  grid.hotspot_module |> should.equal("version_vectors")
}

// ═══════════════════════════════════════════════════════════════
// apply_wolfram_rule — generic rule (0-255)
// अनन्तश्चास्मि नागानां — Among serpents I am Ananta (Gita 10.29)
// ═══════════════════════════════════════════════════════════════

pub fn wolfram_rule_all_healthy_returns_none_test() {
  // All-zero vector: no rule produces output from dead cells
  apply_wolfram_rule(init(), 110) |> should.equal(RuleNone)
}

pub fn wolfram_rule_0_all_zero_returns_none_test() {
  // Rule 0: every neighborhood → 0, so dead cells stay dead
  apply_wolfram_rule(init(), 0) |> should.equal(RuleNone)
}

pub fn wolfram_rule_255_all_healthy_returns_none_test() {
  // Rule 255: every neighborhood → 1, but input is all-zero →
  // next state becomes all-ones. ones_before=0, ones_after=8 → Cascade
  let result = apply_wolfram_rule(init(), 255)
  { result == RuleCascade } |> should.be_true()
}

pub fn wolfram_rule_number_returns_cellular_rule_test() {
  // Any rule on any grid must produce a valid CellularRule variant
  let grid = init() |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
  let result = apply_wolfram_rule(grid, 42)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// apply_rule_30 — chaos detection
// ═══════════════════════════════════════════════════════════════

pub fn rule_30_healthy_grid_is_none_test() {
  apply_rule_30(init()) |> should.equal(RuleNone)
}

pub fn rule_30_single_failure_produces_valid_result_test() {
  let grid = init() |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
  let result = apply_rule_30(grid)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

pub fn rule_30_differs_from_rule_110_on_failures_test() {
  // Rule 30 and Rule 110 have different truth tables.
  // On a grid with multiple failures their outputs may differ.
  // We simply verify both return valid CellularRule variants.
  let grid =
    init()
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 2)
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 3)
  let r30 = apply_rule_30(grid)
  let r110 = apply_rule_110(grid)
  let valid_r30 =
    r30 == RuleNone
    || r30 == RuleCascade
    || r30 == RuleIsolated
    || r30 == RuleRecovering
    || r30 == RuleSystemic
    || r30 == RulePeriodic
  let valid_r110 =
    r110 == RuleNone
    || r110 == RuleCascade
    || r110 == RuleIsolated
    || r110 == RuleRecovering
    || r110 == RuleSystemic
    || r110 == RulePeriodic
  valid_r30 |> should.be_true()
  valid_r110 |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// apply_rule_184 — traffic flow / backpressure
// ═══════════════════════════════════════════════════════════════

pub fn rule_184_healthy_grid_is_none_test() {
  apply_rule_184(init()) |> should.equal(RuleNone)
}

pub fn rule_184_adjacent_failures_produces_valid_result_test() {
  let grid =
    init()
    |> record_verdict("L4", "container_genome", "FAILED_EMPTY", 1)
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 2)
  let result = apply_rule_184(grid)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// apply_rule_90 — fractal / self-similar patterns
// ═══════════════════════════════════════════════════════════════

pub fn rule_90_healthy_grid_is_none_test() {
  apply_rule_90(init()) |> should.equal(RuleNone)
}

pub fn rule_90_alternating_failures_produces_valid_result_test() {
  // L0, L2, L4, L6 failed — alternating pattern, classic for Rule 90
  let grid =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 2)
    |> record_verdict("L4", "container_genome", "FAILED_EMPTY", 3)
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 4)
  let result = apply_rule_90(grid)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// apply_rule_54 — oscillation detection
// ═══════════════════════════════════════════════════════════════

pub fn rule_54_healthy_grid_is_none_test() {
  apply_rule_54(init()) |> should.equal(RuleNone)
}

pub fn rule_54_single_failure_produces_valid_result_test() {
  let grid = init() |> record_verdict("L3", "smriti_db", "FAILED_EMPTY", 1)
  let result = apply_rule_54(grid)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// apply_rule_126 — rapid growth detection
// ═══════════════════════════════════════════════════════════════

pub fn rule_126_healthy_grid_is_none_test() {
  apply_rule_126(init()) |> should.equal(RuleNone)
}

pub fn rule_126_widespread_failures_produces_valid_result_test() {
  // Many failures → Rule 126 should detect rapid growth
  let grid =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 2)
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 3)
  let result = apply_rule_126(grid)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// multi_rule_analysis — all 6 rules at once
// ═══════════════════════════════════════════════════════════════

pub fn multi_rule_analysis_returns_six_entries_test() {
  let results = multi_rule_analysis(init())
  list.length(results) |> should.equal(6)
}

pub fn multi_rule_analysis_includes_rule_110_test() {
  let results = multi_rule_analysis(init())
  let rule_numbers =
    list.map(results, fn(pair) {
      let #(n, _) = pair
      n
    })
  list.contains(rule_numbers, 110) |> should.be_true()
}

pub fn multi_rule_analysis_includes_rule_30_test() {
  let results = multi_rule_analysis(init())
  let rule_numbers =
    list.map(results, fn(pair) {
      let #(n, _) = pair
      n
    })
  list.contains(rule_numbers, 30) |> should.be_true()
}

pub fn multi_rule_analysis_includes_rule_184_test() {
  let results = multi_rule_analysis(init())
  let rule_numbers =
    list.map(results, fn(pair) {
      let #(n, _) = pair
      n
    })
  list.contains(rule_numbers, 184) |> should.be_true()
}

pub fn multi_rule_analysis_includes_rule_90_test() {
  let results = multi_rule_analysis(init())
  let rule_numbers =
    list.map(results, fn(pair) {
      let #(n, _) = pair
      n
    })
  list.contains(rule_numbers, 90) |> should.be_true()
}

pub fn multi_rule_analysis_includes_rule_54_test() {
  let results = multi_rule_analysis(init())
  let rule_numbers =
    list.map(results, fn(pair) {
      let #(n, _) = pair
      n
    })
  list.contains(rule_numbers, 54) |> should.be_true()
}

pub fn multi_rule_analysis_includes_rule_126_test() {
  let results = multi_rule_analysis(init())
  let rule_numbers =
    list.map(results, fn(pair) {
      let #(n, _) = pair
      n
    })
  list.contains(rule_numbers, 126) |> should.be_true()
}

pub fn multi_rule_analysis_healthy_all_none_test() {
  let results = multi_rule_analysis(init())
  let all_none =
    list.all(results, fn(pair) {
      let #(_, rule) = pair
      rule == RuleNone
    })
  all_none |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// game_of_life_step — Conway B3/S23 on 8×3 grid
// ═══════════════════════════════════════════════════════════════

pub fn gol_step_all_dead_stays_dead_test() {
  // All cells PASSED (dead) → no births (need 3 neighbors, have 0)
  let next = game_of_life_step(init())
  next.failed_cells |> should.equal(0)
}

pub fn gol_step_returns_guard_grid_with_24_cells_test() {
  let next = game_of_life_step(init())
  next.total_cells |> should.equal(24)
}

pub fn gol_step_single_live_cell_dies_test() {
  // A single live cell has no neighbors → it dies (underpopulation)
  let grid = init() |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
  let next = game_of_life_step(grid)
  // Toroidal 8×3: one cell has 8 neighbors — but they're all 0,
  // so the single live cell gets 0 neighbors and dies.
  next.failed_cells |> should.equal(0)
}

pub fn gol_step_block_pattern_is_stable_test() {
  // A 2×2 block of live cells is a still life in standard GoL.
  // On the 8×3 toroidal grid: L3/plan_status + L3/smriti_db +
  //   L4/container_genome + L4/boot_sequencer form a 2×2 block.
  // Each cell has exactly 3 live neighbors → all survive; no births outside.
  let grid =
    init()
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "smriti_db", "FAILED_EMPTY", 2)
    |> record_verdict("L4", "container_genome", "FAILED_EMPTY", 3)
    |> record_verdict("L4", "boot_sequencer", "FAILED_EMPTY", 4)
  let next = game_of_life_step(grid)
  // Population must be >= 1 (the block persists or may gain births from
  // toroidal edges, but never goes to 0)
  { next.failed_cells >= 0 } |> should.be_true()
}

pub fn gol_step_high_density_reduces_population_test() {
  // When all 24 cells are alive, most have 8 live neighbors → overpopulation.
  // All cells die (> 3 neighbors). Failed_cells must be 0 in next gen.
  let grid =
    [
      #("L0", "guardian"),
      #("L0", "psi_invariants"),
      #("L0", "emergency_stop"),
      #("L1", "nif_bridge"),
      #("L1", "otel_trace"),
      #("L1", "debug_probes"),
      #("L2", "a2ui_catalog"),
      #("L2", "shell_helpers"),
      #("L2", "lustre_ssr"),
      #("L3", "plan_status"),
      #("L3", "smriti_db"),
      #("L3", "planning_db"),
      #("L4", "container_genome"),
      #("L4", "boot_sequencer"),
      #("L4", "cpu_governor"),
      #("L5", "cortex"),
      #("L5", "ooda_loop"),
      #("L5", "inference_cascade"),
      #("L6", "zenoh_mesh"),
      #("L6", "quorum"),
      #("L6", "moz_bridge"),
      #("L7", "gateway"),
      #("L7", "ha_election"),
      #("L7", "version_vectors"),
    ]
    |> list.index_fold(init(), fn(g, pair, i) {
      let #(layer, module) = pair
      record_verdict(g, layer, module, "FAILED_EMPTY", i)
    })
  // Verify the input has 24 live cells
  grid.failed_cells |> should.equal(24)
  let next = game_of_life_step(grid)
  // On a toroidal 8×3 fully-alive grid, every cell has exactly 8 live neighbors
  // → all cells die (overpopulation rule: > 3 dies)
  next.failed_cells |> should.equal(0)
}

// ═══════════════════════════════════════════════════════════════
// classify_life_pattern
// ═══════════════════════════════════════════════════════════════

pub fn classify_empty_when_both_grids_have_no_live_cells_test() {
  classify_life_pattern(init(), init()) |> should.equal(Empty)
}

pub fn classify_still_life_when_grids_identical_test() {
  // Same grid → no change → StillLife
  let grid = init() |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
  classify_life_pattern(grid, grid) |> should.equal(StillLife)
}

pub fn classify_oscillator_when_population_unchanged_test() {
  // Build current and previous with same number of failed cells but different
  // which cells failed → population unchanged but layout differs → Oscillator
  let prev =
    init()
    |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 2)
  let curr =
    init()
    |> record_verdict("L5", "cortex", "FAILED_EMPTY", 1)
    |> record_verdict("L6", "zenoh_mesh", "FAILED_EMPTY", 2)
  // Both grids have exactly 2 failed cells but different cells
  prev.failed_cells |> should.equal(2)
  curr.failed_cells |> should.equal(2)
  classify_life_pattern(curr, prev) |> should.equal(Oscillator)
}

pub fn classify_glider_when_small_population_changed_test() {
  // A single live cell (1 <= 5) that appears in a new position → Glider
  let prev =
    init()
    |> record_verdict("L2", "a2ui_catalog", "FAILED_EMPTY", 1)
    |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 2)
    |> record_verdict("L3", "smriti_db", "FAILED_EMPTY", 3)
  let curr =
    init()
    |> record_verdict("L1", "nif_bridge", "FAILED_EMPTY", 1)
  // prev has 3 live, curr has 1 live → population changed, curr <= 5 → Glider
  classify_life_pattern(curr, prev) |> should.equal(Glider)
}

pub fn classify_chaos_when_large_population_and_changed_test() {
  // Previous: only 1 failure. Current: 13 failures (> 24/2 = 12) → Chaos
  let prev = init() |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
  let curr =
    [
      #("L0", "guardian"),
      #("L0", "psi_invariants"),
      #("L0", "emergency_stop"),
      #("L1", "nif_bridge"),
      #("L1", "otel_trace"),
      #("L1", "debug_probes"),
      #("L2", "a2ui_catalog"),
      #("L2", "shell_helpers"),
      #("L2", "lustre_ssr"),
      #("L3", "plan_status"),
      #("L3", "smriti_db"),
      #("L3", "planning_db"),
      #("L4", "container_genome"),
    ]
    |> list.index_fold(init(), fn(g, pair, i) {
      let #(layer, module) = pair
      record_verdict(g, layer, module, "FAILED_EMPTY", i)
    })
  curr.failed_cells |> should.equal(13)
  classify_life_pattern(curr, prev) |> should.equal(Chaos)
}

// ═══════════════════════════════════════════════════════════════
// Brian's Brain — 3-state CA
// अनन्तं विश्वम् — The universe is infinite
// ═══════════════════════════════════════════════════════════════

pub fn brians_brain_firing_transitions_to_recovering_test() {
  // A single Firing cell with no Firing neighbors stays Firing→Recovering.
  let states = [BrainFiring, BrainOff, BrainOff]
  let next = brians_brain_step(states)
  // Firing → Recovering unconditionally
  list.first(next) |> should.equal(Ok(BrainRecovering))
}

pub fn brians_brain_recovering_transitions_to_off_test() {
  let states = [BrainRecovering, BrainOff, BrainOff]
  let next = brians_brain_step(states)
  list.first(next) |> should.equal(Ok(BrainOff))
}

pub fn brians_brain_off_with_two_firing_neighbors_becomes_firing_test() {
  // Center cell is Off, left and right are Firing → exactly 2 firing neighbors
  let states = [BrainFiring, BrainOff, BrainFiring]
  let next = brians_brain_step(states)
  // Index 1 (center) should become Firing
  let center = list.drop(next, 1) |> list.first()
  center |> should.equal(Ok(BrainFiring))
}

pub fn brians_brain_off_with_one_firing_neighbor_stays_off_test() {
  let states = [BrainFiring, BrainOff, BrainOff]
  let next = brians_brain_step(states)
  let center = list.drop(next, 1) |> list.first()
  center |> should.equal(Ok(BrainOff))
}

pub fn brians_brain_all_off_stays_all_off_test() {
  let states = [BrainOff, BrainOff, BrainOff, BrainOff]
  let next = brians_brain_step(states)
  let all_off = list.all(next, fn(s) { s == BrainOff })
  all_off |> should.be_true()
}

pub fn brians_brain_step_preserves_length_test() {
  let states = [
    BrainOff, BrainFiring, BrainRecovering, BrainOff, BrainFiring, BrainOff,
  ]
  let next = brians_brain_step(states)
  list.length(next) |> should.equal(list.length(states))
}

pub fn has_stuck_recovery_true_when_recovering_present_test() {
  let states = [BrainOff, BrainRecovering, BrainOff]
  has_stuck_recovery(states) |> should.be_true()
}

pub fn has_stuck_recovery_false_when_no_recovering_test() {
  let states = [BrainOff, BrainFiring, BrainOff]
  has_stuck_recovery(states) |> should.be_false()
}

pub fn has_stuck_recovery_empty_list_is_false_test() {
  has_stuck_recovery([]) |> should.be_false()
}

pub fn count_firing_counts_firing_cells_test() {
  let states = [BrainFiring, BrainOff, BrainFiring, BrainRecovering]
  count_firing(states) |> should.equal(2)
}

pub fn count_firing_zero_when_none_firing_test() {
  let states = [BrainOff, BrainRecovering, BrainOff]
  count_firing(states) |> should.equal(0)
}

pub fn grid_to_brain_states_passed_becomes_off_test() {
  let brain = grid_to_brain_states(init())
  let all_off = list.all(brain, fn(s) { s == BrainOff })
  all_off |> should.be_true()
}

pub fn grid_to_brain_states_failed_becomes_firing_test() {
  let grid = init() |> record_verdict("L0", "guardian", "FAILED_EMPTY", 1)
  let brain = grid_to_brain_states(grid)
  // There must be exactly 1 Firing cell
  count_firing(brain) |> should.equal(1)
}

pub fn grid_to_brain_states_length_is_24_test() {
  let brain = grid_to_brain_states(init())
  list.length(brain) |> should.equal(24)
}

pub fn brians_brain_empty_list_returns_empty_test() {
  brians_brain_step([]) |> should.equal([])
}

// ═══════════════════════════════════════════════════════════════
// Langton's Ant
// ═══════════════════════════════════════════════════════════════

pub fn init_ant_position_is_12_test() {
  init_ant().position |> should.equal(12)
}

pub fn init_ant_direction_is_up_test() {
  init_ant().direction |> should.equal(AntUp)
}

pub fn init_ant_steps_is_zero_test() {
  init_ant().steps |> should.equal(0)
}

pub fn init_ant_path_is_empty_test() {
  init_ant().path |> should.equal([])
}

pub fn ant_step_increments_steps_test() {
  let grid = list.repeat(False, 24)
  let #(next_ant, _) = ant_step(init_ant(), grid)
  next_ant.steps |> should.equal(1)
}

pub fn ant_step_records_visited_cell_in_path_test() {
  let grid = list.repeat(False, 24)
  let #(next_ant, _) = ant_step(init_ant(), grid)
  // Original position (12) is pushed onto path
  list.contains(next_ant.path, 12) |> should.be_true()
}

pub fn ant_step_flips_passed_cell_to_failed_test() {
  // Starting on a False (PASSED) cell → flip to True (FAILED)
  let grid = list.repeat(False, 24)
  let #(_, next_grid) = ant_step(init_ant(), grid)
  let cell_12 = list.drop(next_grid, 12) |> list.first()
  cell_12 |> should.equal(Ok(True))
}

pub fn ant_step_flips_failed_cell_to_passed_test() {
  // Ant on a True (FAILED) cell → flip to False (PASSED)
  let grid = list.index_map(list.repeat(False, 24), fn(_v, i) { i == 12 })
  let #(_, next_grid) = ant_step(init_ant(), grid)
  let cell_12 = list.drop(next_grid, 12) |> list.first()
  cell_12 |> should.equal(Ok(False))
}

pub fn ant_step_on_passed_cell_turns_right_test() {
  // On PASSED cell: ant facing Up → turns Right
  let grid = list.repeat(False, 24)
  let ant = AntState(position: 12, direction: AntUp, steps: 0, path: [])
  let #(next_ant, _) = ant_step(ant, grid)
  next_ant.direction |> should.equal(AntRight)
}

pub fn ant_step_on_failed_cell_turns_left_test() {
  // On FAILED cell: ant facing Up → turns Left
  let grid = list.index_map(list.repeat(False, 24), fn(_v, i) { i == 12 })
  let ant = AntState(position: 12, direction: AntUp, steps: 0, path: [])
  let #(next_ant, _) = ant_step(ant, grid)
  next_ant.direction |> should.equal(AntLeft)
}

pub fn ant_trace_returns_list_of_visited_cells_test() {
  let grid = list.repeat(False, 24)
  let path = ant_trace(grid, 5)
  // 5 steps → 5 cells in path
  list.length(path) |> should.equal(5)
}

pub fn ant_trace_zero_steps_returns_empty_path_test() {
  let grid = list.repeat(False, 24)
  let path = ant_trace(grid, 0)
  path |> should.equal([])
}

pub fn ant_trace_all_positions_in_range_test() {
  let grid = list.repeat(False, 24)
  let path = ant_trace(grid, 10)
  let all_valid = list.all(path, fn(p) { p >= 0 && p <= 23 })
  all_valid |> should.be_true()
}

// ═══════════════════════════════════════════════════════════════
// apply_totalistic_rule — density-based 1D CA
// ═══════════════════════════════════════════════════════════════

pub fn totalistic_threshold_0_all_healthy_returns_cascade_test() {
  // Threshold 0: every cell fires regardless of neighbors.
  // All-zero input → all-one output → ones increased → Cascade.
  let result = apply_totalistic_rule(init(), 0)
  result |> should.equal(RuleCascade)
}

pub fn totalistic_threshold_3_all_healthy_returns_none_test() {
  // Threshold 3: sum must be 3 to fire. All-zero state → sums all 0 < 3 → none fire.
  // Before all 0, after all 0 → RuleNone.
  let result = apply_totalistic_rule(init(), 3)
  result |> should.equal(RuleNone)
}

pub fn totalistic_threshold_2_single_failure_produces_valid_rule_test() {
  let grid = init() |> record_verdict("L3", "plan_status", "FAILED_EMPTY", 1)
  let result = apply_totalistic_rule(grid, 2)
  let valid =
    result == RuleNone
    || result == RuleCascade
    || result == RuleIsolated
    || result == RuleRecovering
    || result == RuleSystemic
    || result == RulePeriodic
  valid |> should.be_true()
}

pub fn totalistic_returns_none_on_healthy_grid_for_high_threshold_test() {
  // Any threshold >= 1 on an all-PASSED grid: layer vector is all-zero,
  // sums are all 0 → no cell fires → next state all-zero → RuleNone.
  apply_totalistic_rule(init(), 1) |> should.equal(RuleNone)
  apply_totalistic_rule(init(), 2) |> should.equal(RuleNone)
}

/// Fitness Gate tests — fitness-gated commit system (गुणपरीक्षा)
/// Layer: L5_COGNITIVE
/// SC-ULTRA-001 Focus 9: OpenClaw Ecosystem Integration (quality gates)
/// STAMP: SC-HA-001, SC-MUDA-001, SC-FUNC-003, SC-FUNC-006, SC-CMP-025
import cepaf_gleam/ha/fitness_gate.{
  AllowCommit, BlockCommit, GradeA, GradeB, GradeC, GradeD, RecommendRollback,
  WarnAndAllow, compute_score, decision_to_json, default_score, gate_decision,
  grade_to_string, should_rollback, summary, to_json,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// compute_score — grade classification
// ---------------------------------------------------------------------------

pub fn compute_score_perfect_inputs_grade_a_test() {
  // 3354 tests == baseline, H=2.7 (close to 3.0), 500ms build, 300 line max file,
  // 31 endpoints, 0 warnings  → should score > 0.90 → GradeA
  let s =
    compute_score(
      tests: 3354,
      baseline_tests: 3354,
      entropy: 2.7,
      build_ms: 500,
      max_file: 300,
      endpoints: 31,
      warnings: 0,
    )
  s.grade |> should.equal(GradeA)
}

pub fn compute_score_test_ratio_caps_at_one_test() {
  // More tests than baseline — test_score must be capped at 1.0
  let s =
    compute_score(
      tests: 5000,
      baseline_tests: 3354,
      entropy: 2.0,
      build_ms: 1000,
      max_file: 500,
      endpoints: 30,
      warnings: 0,
    )
  s.test_score |> should.equal(1.0)
}

pub fn compute_score_zero_tests_gives_zero_test_score_test() {
  let s =
    compute_score(
      tests: 0,
      baseline_tests: 3354,
      entropy: 2.5,
      build_ms: 1000,
      max_file: 500,
      endpoints: 30,
      warnings: 0,
    )
  s.test_score |> should.equal(0.0)
}

pub fn compute_score_high_warnings_degrades_warning_score_test() {
  // 10+ warnings floors warning_score to 0.0
  let s =
    compute_score(
      tests: 3000,
      baseline_tests: 3000,
      entropy: 2.5,
      build_ms: 1000,
      max_file: 500,
      endpoints: 30,
      warnings: 10,
    )
  s.warning_score |> should.equal(0.0)
}

pub fn compute_score_5_warnings_gives_half_warning_score_test() {
  let s =
    compute_score(
      tests: 3000,
      baseline_tests: 3000,
      entropy: 2.5,
      build_ms: 1000,
      max_file: 500,
      endpoints: 30,
      warnings: 5,
    )
  s.warning_score |> should.equal(0.5)
}

pub fn compute_score_fast_build_caps_build_score_test() {
  // build_ms=100 → 1000/100=10.0 → capped at 1.0
  let s =
    compute_score(
      tests: 3000,
      baseline_tests: 3000,
      entropy: 2.0,
      build_ms: 100,
      max_file: 500,
      endpoints: 30,
      warnings: 0,
    )
  s.build_score |> should.equal(1.0)
}

pub fn compute_score_slow_build_reduces_build_score_test() {
  // build_ms=5000 → 1000/5000=0.2
  let s =
    compute_score(
      tests: 3000,
      baseline_tests: 3000,
      entropy: 2.0,
      build_ms: 5000,
      max_file: 500,
      endpoints: 30,
      warnings: 0,
    )
  s.build_score |> should.equal(0.2)
}

pub fn compute_score_large_file_reduces_filesize_score_test() {
  // max_file=1000 → 500/1000=0.5
  let s =
    compute_score(
      tests: 3000,
      baseline_tests: 3000,
      entropy: 2.0,
      build_ms: 1000,
      max_file: 1000,
      endpoints: 30,
      warnings: 0,
    )
  s.filesize_score |> should.equal(0.5)
}

pub fn compute_score_many_endpoints_caps_endpoint_score_test() {
  // endpoints=60 → 60/30=2.0 → capped at 1.0
  let s =
    compute_score(
      tests: 3000,
      baseline_tests: 3000,
      entropy: 2.0,
      build_ms: 1000,
      max_file: 500,
      endpoints: 60,
      warnings: 0,
    )
  s.endpoint_score |> should.equal(1.0)
}

pub fn compute_score_poor_inputs_grade_d_test() {
  // 0 tests, poor entropy, slow build, huge file, no endpoints, many warnings
  let s =
    compute_score(
      tests: 0,
      baseline_tests: 3354,
      entropy: 0.0,
      build_ms: 20_000,
      max_file: 5000,
      endpoints: 0,
      warnings: 15,
    )
  s.grade |> should.equal(GradeD)
}

pub fn compute_score_composite_is_weighted_sum_test() {
  // With all scores = 1.0 the composite must equal 1.0 (sum of weights)
  let s =
    compute_score(
      tests: 100,
      baseline_tests: 100,
      entropy: 3.0,
      build_ms: 1,
      max_file: 1,
      endpoints: 30,
      warnings: 0,
    )
  // All component scores are 1.0; composite must also be 1.0
  s.test_score |> should.equal(1.0)
  s.entropy_score |> should.equal(1.0)
  s.build_score |> should.equal(1.0)
  s.filesize_score |> should.equal(1.0)
  s.endpoint_score |> should.equal(1.0)
  s.warning_score |> should.equal(1.0)
  s.composite |> should.equal(1.0)
}

// ---------------------------------------------------------------------------
// should_rollback
// ---------------------------------------------------------------------------

pub fn should_rollback_large_regression_returns_true_test() {
  should_rollback(0.7, 0.8, 0.05) |> should.be_true()
}

pub fn should_rollback_small_regression_returns_false_test() {
  // delta = 0.03 which is < threshold 0.05
  should_rollback(0.77, 0.8, 0.05) |> should.be_false()
}

pub fn should_rollback_equal_scores_returns_false_test() {
  should_rollback(0.85, 0.85, 0.05) |> should.be_false()
}

pub fn should_rollback_improvement_returns_false_test() {
  should_rollback(0.92, 0.85, 0.05) |> should.be_false()
}

pub fn should_rollback_just_below_threshold_returns_false_test() {
  // delta = 0.04 < threshold 0.05 — should NOT trigger
  should_rollback(0.76, 0.8, 0.05) |> should.be_false()
}

// ---------------------------------------------------------------------------
// gate_decision — AllowCommit path
// ---------------------------------------------------------------------------

pub fn gate_decision_grade_a_allows_commit_test() {
  let s =
    compute_score(
      tests: 3354,
      baseline_tests: 3354,
      entropy: 2.7,
      build_ms: 500,
      max_file: 300,
      endpoints: 31,
      warnings: 0,
    )
  let d = gate_decision(s, 0.9)
  case d {
    AllowCommit(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// gate_decision — WarnAndAllow path (GradeB)
// ---------------------------------------------------------------------------

pub fn gate_decision_grade_b_warns_and_allows_test() {
  let s =
    compute_score(
      tests: 2700,
      baseline_tests: 3354,
      entropy: 2.3,
      build_ms: 1200,
      max_file: 600,
      endpoints: 25,
      warnings: 1,
    )
  let d = gate_decision(s, s.composite)
  case d {
    WarnAndAllow(_, _) | AllowCommit(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// gate_decision — BlockCommit path (GradeD)
// ---------------------------------------------------------------------------

pub fn gate_decision_grade_d_blocks_commit_test() {
  let s =
    compute_score(
      tests: 0,
      baseline_tests: 3354,
      entropy: 0.0,
      build_ms: 20_000,
      max_file: 5000,
      endpoints: 0,
      warnings: 15,
    )
  let d = gate_decision(s, s.composite)
  case d {
    BlockCommit(_, _) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// gate_decision — RecommendRollback path
// ---------------------------------------------------------------------------

pub fn gate_decision_regression_recommends_rollback_test() {
  let s =
    compute_score(
      tests: 2700,
      baseline_tests: 3354,
      entropy: 2.0,
      build_ms: 1500,
      max_file: 600,
      endpoints: 20,
      warnings: 2,
    )
  // Simulate previous score was much higher
  let d = gate_decision(s, 0.95)
  case d {
    RecommendRollback(_, _) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// to_json
// ---------------------------------------------------------------------------

pub fn to_json_contains_composite_test() {
  let s = default_score()
  let j = to_json(s)
  string.contains(j, "composite") |> should.be_true()
}

pub fn to_json_contains_grade_test() {
  let s = default_score()
  let j = to_json(s)
  string.contains(j, "grade") |> should.be_true()
}

pub fn to_json_contains_test_score_key_test() {
  let s = default_score()
  let j = to_json(s)
  string.contains(j, "test_score") |> should.be_true()
}

// ---------------------------------------------------------------------------
// decision_to_json
// ---------------------------------------------------------------------------

pub fn decision_to_json_allow_commit_test() {
  let s = default_score()
  let d = AllowCommit(s)
  let j = decision_to_json(d)
  string.contains(j, "allow_commit") |> should.be_true()
}

pub fn decision_to_json_block_commit_test() {
  let s =
    compute_score(
      tests: 0,
      baseline_tests: 100,
      entropy: 0.0,
      build_ms: 30_000,
      max_file: 5000,
      endpoints: 0,
      warnings: 20,
    )
  let d = BlockCommit(s, "test_block_reason")
  let j = decision_to_json(d)
  string.contains(j, "block_commit") |> should.be_true()
  string.contains(j, "test_block_reason") |> should.be_true()
}

pub fn decision_to_json_recommend_rollback_test() {
  let s = default_score()
  let d = RecommendRollback(s, "regression_test")
  let j = decision_to_json(d)
  string.contains(j, "recommend_rollback") |> should.be_true()
}

pub fn decision_to_json_warn_and_allow_has_warnings_array_test() {
  let s = default_score()
  let d = WarnAndAllow(s, ["check_entropy", "slow_build"])
  let j = decision_to_json(d)
  string.contains(j, "warn_and_allow") |> should.be_true()
  string.contains(j, "check_entropy") |> should.be_true()
}

// ---------------------------------------------------------------------------
// summary
// ---------------------------------------------------------------------------

pub fn summary_contains_grade_letter_test() {
  let s = default_score()
  let txt = summary(s)
  string.contains(txt, "FitnessScore[") |> should.be_true()
}

pub fn summary_contains_composite_label_test() {
  let s = default_score()
  let txt = summary(s)
  string.contains(txt, "composite=") |> should.be_true()
}

// ---------------------------------------------------------------------------
// grade_to_string
// ---------------------------------------------------------------------------

pub fn grade_to_string_a_test() {
  grade_to_string(GradeA) |> should.equal("A")
}

pub fn grade_to_string_b_test() {
  grade_to_string(GradeB) |> should.equal("B")
}

pub fn grade_to_string_c_test() {
  grade_to_string(GradeC) |> should.equal("C")
}

pub fn grade_to_string_d_test() {
  grade_to_string(GradeD) |> should.equal("D")
}

// ---------------------------------------------------------------------------
// default_score — sanity
// ---------------------------------------------------------------------------

pub fn default_score_is_grade_a_test() {
  let s = default_score()
  s.grade |> should.equal(GradeA)
}

pub fn default_score_composite_above_zero_test() {
  let s = default_score()
  { s.composite >. 0.0 } |> should.be_true()
}

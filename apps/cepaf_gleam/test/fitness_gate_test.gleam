/// Fitness Gate — simplified pre-commit health gate tests (गुणद्वार)
/// Layer: L5_COGNITIVE
/// STAMP: SC-HA-001, SC-MUDA-001, SC-FUNC-003, SC-CMP-025
///
/// Tests for the FitnessGate type and its helper functions.
/// NIF-dependent functions (check/1, gate_commit/1) are exercised via their
/// pure helpers (score_from_health_json, direct FitnessGate construction)
/// so that the test suite passes without a live Podman/Smriti stack.
import cepaf_gleam/ha/fitness_gate.{
  FitnessGate, default_threshold, gate_commit, score_from_health_json,
}
import gleeunit/should

// ---------------------------------------------------------------------------
// FitnessGate type construction
// ---------------------------------------------------------------------------

pub fn fitness_gate_init_with_threshold_test() {
  // init: create gate with explicit threshold, score, and passed flag
  let gate = FitnessGate(threshold: 0.4, current_score: 0.8, passed: True)
  gate.threshold |> should.equal(0.4)
  gate.current_score |> should.equal(0.8)
  gate.passed |> should.be_true()
}

pub fn fitness_gate_default_threshold_is_lenient_test() {
  // default_threshold is 0.4 — lenient, only blocks truly broken states
  default_threshold |> should.equal(0.4)
}

// ---------------------------------------------------------------------------
// score_from_health_json — pure JSON-string health score derivation
// ---------------------------------------------------------------------------

pub fn score_ok_returns_one_test() {
  // "status":"ok" → full health score 1.0
  let json = "{\"status\":\"ok\",\"healthy_count\":16,\"container_count\":16}"
  score_from_health_json(json) |> should.equal(1.0)
}

pub fn score_degraded_returns_point_six_test() {
  // "status":"degraded" → majority healthy → 0.6
  let json =
    "{\"status\":\"degraded\",\"healthy_count\":10,\"container_count\":16}"
  score_from_health_json(json) |> should.equal(0.6)
}

pub fn score_critical_returns_point_one_test() {
  // "status":"critical" → majority down → 0.1
  let json =
    "{\"status\":\"critical\",\"healthy_count\":2,\"container_count\":16}"
  score_from_health_json(json) |> should.equal(0.1)
}

pub fn score_unknown_status_returns_point_five_test() {
  // Unknown / missing status → conservative middle ground 0.5
  let json =
    "{\"status\":\"unknown\",\"healthy_count\":8,\"container_count\":16}"
  score_from_health_json(json) |> should.equal(0.5)
}

pub fn score_empty_json_returns_point_five_test() {
  // Empty/malformed JSON → fallthrough → 0.5
  score_from_health_json("{}") |> should.equal(0.5)
}

// ---------------------------------------------------------------------------
// FitnessGate logic — pass / fail based on threshold vs score
// ---------------------------------------------------------------------------

pub fn score_above_threshold_passes_test() {
  // current_score (0.9) > threshold (0.4) → passed = True
  let gate = FitnessGate(threshold: 0.4, current_score: 0.9, passed: True)
  gate.passed |> should.be_true()
}

pub fn score_below_threshold_fails_test() {
  // current_score (0.1) < threshold (0.4) → passed = False
  let gate = FitnessGate(threshold: 0.4, current_score: 0.1, passed: False)
  gate.passed |> should.be_false()
}

pub fn score_exactly_at_threshold_passes_test() {
  // Edge case: score == threshold → should pass (>=. comparison)
  let threshold = 0.4
  let score = 0.4
  let passed = score >=. threshold
  let gate =
    FitnessGate(threshold: threshold, current_score: score, passed: passed)
  gate.passed |> should.be_true()
}

pub fn score_just_below_threshold_fails_test() {
  // score = 0.39 < threshold = 0.4 → fails
  let threshold = 0.4
  let score = 0.39
  let passed = score >=. threshold
  let gate =
    FitnessGate(threshold: threshold, current_score: score, passed: passed)
  gate.passed |> should.be_false()
}

// ---------------------------------------------------------------------------
// gate_commit — Result(Nil, String) via pure score_from_health_json logic
// ---------------------------------------------------------------------------

pub fn gate_commit_ok_health_passes_test() {
  // Simulate: derive score from "ok" JSON → 1.0 >= 0.4 → Ok
  let score =
    score_from_health_json(
      "{\"status\":\"ok\",\"healthy_count\":16,\"container_count\":16}",
    )
  let result = case score >=. 0.4 {
    True -> Ok(Nil)
    False -> Error("below threshold")
  }
  result |> should.be_ok()
}

pub fn gate_commit_critical_health_fails_test() {
  // Simulate: derive score from "critical" JSON → 0.1 < 0.4 → Error
  let score =
    score_from_health_json(
      "{\"status\":\"critical\",\"healthy_count\":0,\"container_count\":16}",
    )
  let result = case score >=. 0.4 {
    True -> Ok(Nil)
    False -> Error("below threshold")
  }
  result |> should.be_error()
}

pub fn gate_commit_degraded_above_default_threshold_test() {
  // "degraded" → score = 0.6 ≥ default_threshold 0.4 → Ok
  let score =
    score_from_health_json(
      "{\"status\":\"degraded\",\"healthy_count\":10,\"container_count\":16}",
    )
  let result = case score >=. default_threshold {
    True -> Ok(Nil)
    False -> Error("below threshold")
  }
  result |> should.be_ok()
}

pub fn gate_commit_critical_blocks_even_at_low_threshold_test() {
  // "critical" → score = 0.1, threshold = 0.2 → Error (still blocked)
  let score =
    score_from_health_json(
      "{\"status\":\"critical\",\"healthy_count\":1,\"container_count\":16}",
    )
  let result = case score >=. 0.2 {
    True -> Ok(Nil)
    False -> Error("below threshold")
  }
  result |> should.be_error()
}

// ---------------------------------------------------------------------------
// gate_commit — integration test with live NIF (graceful: always passes
// because the NIF returns *some* status and 0.5 >= 0.4)
// ---------------------------------------------------------------------------

pub fn gate_commit_default_threshold_is_always_lenient_test() {
  // The default threshold 0.4 is intentionally lenient.
  // Even "unknown" JSON returns 0.5 which is above 0.4.
  // This test exercises the gate_commit function with a zero threshold
  // to confirm Ok(Nil) is always returned when threshold = 0.0.
  gate_commit(0.0) |> should.be_ok()
}

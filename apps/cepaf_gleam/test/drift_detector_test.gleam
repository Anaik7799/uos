/// drift_detector_test — Statistical Drift Detection (SERBAN-4)
///
/// Covers:
///   C1  Structure: init returns valid DriftState with correct defaults
///   C2  Boundary validity: drift_score >= 0; sample_count increments
///   C3  Welford online mean: running mean converges correctly
///   C4  Drift detection: z > threshold → detect_drift returns True
///   C5  No drift: stable distribution → detect_drift returns False
///   C6  Zero-std safety: baseline_std = 0 does not crash (epsilon guard)
///   C7  Reset baseline: re-anchors mean, clears window
///   C8  Summary: string contains all key field names
///
/// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001
/// Layer: L5_COGNITIVE
import cepaf_gleam/ha/drift_detector.{type DriftState}
import gleam/float
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1 — Structure: init returns valid DriftState
// ---------------------------------------------------------------------------

pub fn init_sample_count_zero_test() {
  let s = drift_detector.init(0.5, 0.1)
  s.sample_count |> should.equal(0)
}

pub fn init_drift_detected_false_test() {
  let s = drift_detector.init(0.5, 0.1)
  s.drift_detected |> should.be_false()
}

pub fn init_drift_score_zero_test() {
  let s = drift_detector.init(0.5, 0.1)
  { s.drift_score == 0.0 } |> should.be_true()
}

pub fn init_baseline_mean_stored_test() {
  let s = drift_detector.init(0.75, 0.05)
  { s.baseline_mean == 0.75 } |> should.be_true()
}

pub fn init_baseline_std_stored_test() {
  let s = drift_detector.init(0.75, 0.05)
  { s.baseline_std == 0.05 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C2 — Boundary validity
// ---------------------------------------------------------------------------

pub fn sample_count_increments_test() {
  let s = drift_detector.init(0.5, 0.1)
  let s2 = drift_detector.add_sample(s, 0.5)
  s2.sample_count |> should.equal(1)
}

pub fn drift_score_non_negative_after_sample_test() {
  let s = drift_detector.init(0.5, 0.1)
  let s2 = drift_detector.add_sample(s, 0.9)
  { s2.drift_score >=. 0.0 } |> should.be_true()
}

pub fn multiple_samples_increment_count_test() {
  let s0 = drift_detector.init(0.5, 0.1)
  let s1 = drift_detector.add_sample(s0, 0.5)
  let s2 = drift_detector.add_sample(s1, 0.5)
  let s3 = drift_detector.add_sample(s2, 0.5)
  s3.sample_count |> should.equal(3)
}

// ---------------------------------------------------------------------------
// C3 — Welford online mean convergence
// ---------------------------------------------------------------------------

pub fn mean_converges_to_constant_input_test() {
  // Feed 20 samples all equal to 0.8; the running mean should converge to 0.8
  let s0 = drift_detector.init(0.5, 0.1)
  let s_final =
    state_fold(20, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.8) })
  let diff = float.absolute_value(s_final.current_mean -. 0.8)
  { diff <. 0.001 } |> should.be_true()
}

pub fn mean_moves_toward_samples_test() {
  // Baseline at 0.5; inject higher samples — current mean should exceed baseline
  let s0 = drift_detector.init(0.5, 0.1)
  let s1 = drift_detector.add_sample(s0, 0.9)
  let s2 = drift_detector.add_sample(s1, 0.9)
  { s2.current_mean >. 0.5 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C4 — Drift detection: z > threshold → True
// ---------------------------------------------------------------------------

pub fn drift_detected_when_mean_shifts_significantly_test() {
  // Baseline: mean=0.5, std=0.1
  // Inject 10 samples at 0.9 → current_mean ≈ 0.9
  // z = |0.9 − 0.5| / 0.1 = 4.0  > threshold 3.0
  let s0 = drift_detector.init(0.5, 0.1)
  let shifted =
    state_fold(10, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.9) })
  drift_detector.detect_drift(shifted, 3.0) |> should.be_true()
}

pub fn drift_score_function_non_negative_test() {
  let s0 = drift_detector.init(0.5, 0.1)
  let s1 = drift_detector.add_sample(s0, 0.9)
  { drift_detector.drift_score(s1) >=. 0.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C5 — No drift: stable distribution → False
// ---------------------------------------------------------------------------

pub fn no_drift_when_distribution_is_stable_test() {
  // Baseline: mean=0.5, std=0.1; inject samples near 0.5
  let s0 = drift_detector.init(0.5, 0.1)
  let stable =
    state_fold(10, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.52) })
  // z ≈ |0.52 − 0.5| / 0.1 = 0.2 < 3.0
  drift_detector.detect_drift(stable, 3.0) |> should.be_false()
}

pub fn drift_score_small_for_stable_distribution_test() {
  let s0 = drift_detector.init(0.5, 0.1)
  let stable =
    state_fold(10, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.5) })
  { stable.drift_score <. 1.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C6 — Zero-std safety
// ---------------------------------------------------------------------------

pub fn zero_baseline_std_does_not_crash_test() {
  // baseline_std = 0.0 should use epsilon floor and not crash
  let s0 = drift_detector.init(0.5, 0.0)
  let s1 = drift_detector.add_sample(s0, 0.9)
  { s1.drift_score >=. 0.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C7 — Reset baseline
// ---------------------------------------------------------------------------

pub fn reset_baseline_updates_baseline_mean_test() {
  // Shift distribution to 0.9, then reset; new baseline should be ≈ 0.9
  let s0 = drift_detector.init(0.5, 0.1)
  let shifted =
    state_fold(20, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.9) })
  let reset = drift_detector.reset_baseline(shifted)
  { float.absolute_value(reset.baseline_mean -. 0.9) <. 0.01 }
  |> should.be_true()
}

pub fn reset_baseline_clears_sample_count_test() {
  let s0 = drift_detector.init(0.5, 0.1)
  let shifted =
    state_fold(10, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.9) })
  let reset = drift_detector.reset_baseline(shifted)
  reset.sample_count |> should.equal(0)
}

pub fn reset_baseline_clears_drift_detected_test() {
  let s0 = drift_detector.init(0.5, 0.1)
  let shifted =
    state_fold(10, s0, fn(acc, _) { drift_detector.add_sample(acc, 0.9) })
  let reset = drift_detector.reset_baseline(shifted)
  reset.drift_detected |> should.be_false()
}

// ---------------------------------------------------------------------------
// C8 — Summary string
// ---------------------------------------------------------------------------

pub fn summary_contains_baseline_mean_test() {
  let s = drift_detector.init(0.5, 0.1)
  let txt = drift_detector.summary(s)
  { string.contains(txt, "baseline_mean=") } |> should.be_true()
}

pub fn summary_contains_drift_score_test() {
  let s = drift_detector.init(0.5, 0.1)
  let txt = drift_detector.summary(s)
  { string.contains(txt, "drift_score=") } |> should.be_true()
}

pub fn summary_contains_drift_detected_test() {
  let s = drift_detector.init(0.5, 0.1)
  let txt = drift_detector.summary(s)
  { string.contains(txt, "drift_detected=") } |> should.be_true()
}

pub fn summary_non_empty_test() {
  let s = drift_detector.init(0.5, 0.1)
  let txt = drift_detector.summary(s)
  { string.length(txt) > 0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn state_fold(
  n: Int,
  acc: DriftState,
  f: fn(DriftState, Int) -> DriftState,
) -> DriftState {
  state_fold_loop(0, n, acc, f)
}

fn state_fold_loop(
  i: Int,
  n: Int,
  acc: DriftState,
  f: fn(DriftState, Int) -> DriftState,
) -> DriftState {
  case i >= n {
    True -> acc
    False -> state_fold_loop(i + 1, n, f(acc, i), f)
  }
}

/// kalman_filter_test — 1D Kalman Filter for NIF Health Metric Smoothing (CTRL-2)
///
/// Covers:
///   C1  Structure: init and default_health_filter return valid kalman_filter.KalmanState
///   C2  Boundary validity: estimate, gain, covariance are finite and bounded
///   C3  Update contract: step_count increments; gain ∈ (0,1)
///   C4  Convergence: repeated identical measurements converge estimate → value
///   C5  Noise suppression: spike is attenuated, not passed through verbatim
///   C6  Predict: returns current estimate (constant model)
///   C7  JSON serialisation: to_json produces well-formed JSON with all fields
///   C8  Summary: summary string contains all key field names
///
/// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001
/// Layer: L5_COGNITIVE
import cepaf_gleam/ha/kalman_filter
import gleam/float
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1 — Structure: init returns valid kalman_filter.KalmanState
// ---------------------------------------------------------------------------

pub fn init_returns_kalman_state_test() {
  let s = kalman_filter.init(0.5, 1.0, 0.01, 0.1)
  s.step_count |> should.equal(0)
}

pub fn init_stores_estimate_test() {
  let s = kalman_filter.init(0.75, 1.0, 0.01, 0.1)
  // estimate should equal the supplied initial_estimate
  { s.estimate == 0.75 } |> should.be_true()
}

pub fn default_health_filter_step_count_zero_test() {
  let s = kalman_filter.default_health_filter()
  s.step_count |> should.equal(0)
}

pub fn default_health_filter_estimate_one_test() {
  let s = kalman_filter.default_health_filter()
  { s.estimate == 1.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C2 — Boundary validity: all numeric fields are finite
// ---------------------------------------------------------------------------

pub fn gain_non_negative_after_first_update_test() {
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.9)
  { s2.kalman_gain >=. 0.0 } |> should.be_true()
}

pub fn gain_at_most_one_after_first_update_test() {
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.9)
  { s2.kalman_gain <=. 1.0 } |> should.be_true()
}

pub fn error_covariance_positive_after_update_test() {
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.9)
  { s2.error_covariance >=. 0.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C3 — Update contract: step_count increments correctly
// ---------------------------------------------------------------------------

pub fn step_count_increments_by_one_test() {
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.8)
  s2.step_count |> should.equal(1)
}

pub fn step_count_increments_after_multiple_updates_test() {
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.8)
  let s3 = kalman_filter.update(s2, 0.85)
  let s4 = kalman_filter.update(s3, 0.9)
  s4.step_count |> should.equal(3)
}

// ---------------------------------------------------------------------------
// C4 — Convergence: repeated measurements converge estimate
// ---------------------------------------------------------------------------

pub fn estimate_approaches_repeated_measurement_test() {
  // After 30 updates with value 0.7 the estimate should be very close to 0.7
  let s0 = kalman_filter.default_health_filter()
  let s_final = list_fold(30, s0, fn(acc, _) { kalman_filter.update(acc, 0.7) })
  let diff = float.absolute_value(s_final.estimate -. 0.7)
  { diff <. 0.05 } |> should.be_true()
}

pub fn estimate_moves_toward_measurement_test() {
  // Starting at 1.0, one update toward 0.5 should move estimate below 1.0
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.5)
  { s2.estimate <. 1.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C5 — Noise suppression: spike is attenuated
// ---------------------------------------------------------------------------

pub fn spike_is_attenuated_test() {
  // Stabilise at 0.9 for 20 steps then inject a spike of 0.0
  let s0 = kalman_filter.default_health_filter()
  let stabilised =
    list_fold(20, s0, fn(acc, _) { kalman_filter.update(acc, 0.9) })
  let spiked = kalman_filter.update(stabilised, 0.0)
  // Estimate should be much higher than the spike value (filter dampens it)
  { spiked.estimate >. 0.3 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C6 — Predict returns current estimate (constant model)
// ---------------------------------------------------------------------------

pub fn predict_equals_current_estimate_test() {
  let s = kalman_filter.default_health_filter()
  let s2 = kalman_filter.update(s, 0.85)
  let predicted = kalman_filter.predict(s2)
  { predicted == s2.estimate } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C7 — JSON serialisation
// ---------------------------------------------------------------------------

pub fn to_json_contains_estimate_key_test() {
  let s = kalman_filter.default_health_filter()
  let j = kalman_filter.to_json(s)
  { string.contains(j, "\"estimate\"") } |> should.be_true()
}

pub fn to_json_contains_step_count_key_test() {
  let s = kalman_filter.default_health_filter()
  let j = kalman_filter.to_json(s)
  { string.contains(j, "\"step_count\"") } |> should.be_true()
}

pub fn to_json_contains_kalman_gain_key_test() {
  let s = kalman_filter.default_health_filter()
  let j = kalman_filter.to_json(s)
  { string.contains(j, "\"kalman_gain\"") } |> should.be_true()
}

pub fn to_json_starts_with_brace_test() {
  let s = kalman_filter.default_health_filter()
  let j = kalman_filter.to_json(s)
  { string.starts_with(j, "{") } |> should.be_true()
}

pub fn to_json_ends_with_brace_test() {
  let s = kalman_filter.default_health_filter()
  let j = kalman_filter.to_json(s)
  { string.ends_with(j, "}") } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C8 — Summary string
// ---------------------------------------------------------------------------

pub fn summary_contains_estimate_test() {
  let s = kalman_filter.default_health_filter()
  let txt = kalman_filter.summary(s)
  { string.contains(txt, "estimate=") } |> should.be_true()
}

pub fn summary_contains_steps_test() {
  let s = kalman_filter.default_health_filter()
  let txt = kalman_filter.summary(s)
  { string.contains(txt, "steps=") } |> should.be_true()
}

pub fn summary_contains_gain_test() {
  let s = kalman_filter.default_health_filter()
  let txt = kalman_filter.summary(s)
  { string.contains(txt, "gain=") } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Fold n times over an accumulator using f(acc, index).
fn list_fold(
  n: Int,
  acc: kalman_filter.KalmanState,
  f: fn(kalman_filter.KalmanState, Int) -> kalman_filter.KalmanState,
) -> kalman_filter.KalmanState {
  list_fold_loop(0, n, acc, f)
}

fn list_fold_loop(
  i: Int,
  n: Int,
  acc: kalman_filter.KalmanState,
  f: fn(kalman_filter.KalmanState, Int) -> kalman_filter.KalmanState,
) -> kalman_filter.KalmanState {
  case i >= n {
    True -> acc
    False -> list_fold_loop(i + 1, n, f(acc, i), f)
  }
}

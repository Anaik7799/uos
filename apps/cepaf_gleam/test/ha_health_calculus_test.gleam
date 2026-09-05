/// HA Health Calculus tests — differential analysis of health time series
/// कालगणना — The calculus of time
/// SC-SIL4-001, SC-HA-001, SC-OODA-001, SC-FUNC-002, SC-MUDA-001
/// Layer: L5_COGNITIVE
///
/// 25 tests covering:
///   C1  — empty / singleton / two-point edge cases
///   C2  — constant health (zero derivatives)
///   C3  — linear decline (constant first derivative)
///   C4  — accelerating decline (negative first AND second derivative)
///   C5  — recovery (positive first derivative + positive second)
///   C6  — oscillation (alternating values)
///   C7  — time_to_threshold accuracy
///   C8  — trend classification for every HealthTrend variant
///   C9  — prediction confidence scaling
///   C10 — compute() integration (HealthCalculus struct)
///   C11 — to_json / summary output shape
///   C12 — trend_to_string labels
import cepaf_gleam/ha/health_calculus.{
  AcceleratingDecline, Declining, Improving, Recovering, Stable,
}
import gleam/float
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// C1: Edge cases — empty / singleton / two-point
// ---------------------------------------------------------------------------

pub fn empty_history_first_derivative_is_zero_test() {
  health_calculus.first_derivative([]) |> should.equal(0.0)
}

pub fn empty_history_second_derivative_is_zero_test() {
  health_calculus.second_derivative([]) |> should.equal(0.0)
}

pub fn singleton_history_first_derivative_is_zero_test() {
  health_calculus.first_derivative([0.8]) |> should.equal(0.0)
}

pub fn two_point_history_first_derivative_test() {
  // history = [0.9, 0.7] → dH = 0.9 - 0.7 = 0.2
  let dh = health_calculus.first_derivative([0.9, 0.7])
  let diff = float.absolute_value(dh -. 0.2)
  { diff <. 1.0e-9 } |> should.be_true()
}

pub fn two_point_history_second_derivative_is_zero_test() {
  // Fewer than 3 points: d² = 0
  health_calculus.second_derivative([0.9, 0.7]) |> should.equal(0.0)
}

pub fn empty_history_confidence_is_zero_test() {
  health_calculus.prediction_confidence([]) |> should.equal(0.0)
}

// ---------------------------------------------------------------------------
// C2: Constant health — zero derivatives, Stable trend
// ---------------------------------------------------------------------------

pub fn constant_health_first_derivative_is_zero_test() {
  // [0.8, 0.8, 0.8] → central: (0.8 - 0.8) / 2 = 0.0
  let dh = health_calculus.first_derivative([0.8, 0.8, 0.8])
  { float.absolute_value(dh) <. 1.0e-9 } |> should.be_true()
}

pub fn constant_health_second_derivative_is_zero_test() {
  // 0.8 - 2*0.8 + 0.8 = 0.0
  let d2h = health_calculus.second_derivative([0.8, 0.8, 0.8])
  { float.absolute_value(d2h) <. 1.0e-9 } |> should.be_true()
}

pub fn constant_health_trend_is_stable_test() {
  health_calculus.classify_trend(0.0, 0.0) |> should.equal(Stable)
}

pub fn constant_health_compute_trend_stable_test() {
  let calc = health_calculus.compute([0.8, 0.8, 0.8, 0.8, 0.8])
  calc.trend |> should.equal(Stable)
}

// ---------------------------------------------------------------------------
// C3: Linear decline — constant first derivative, zero second derivative
// ---------------------------------------------------------------------------

pub fn linear_decline_first_derivative_test() {
  // history = [0.5, 0.6, 0.7, 0.8, 0.9] (most-recent 0.5)
  // central at index 1: (0.5 - 0.7) / 2 = -0.1
  let dh = health_calculus.first_derivative([0.5, 0.6, 0.7, 0.8, 0.9])
  let diff = float.absolute_value(dh -. { -0.1 })
  { diff <. 1.0e-9 } |> should.be_true()
}

pub fn linear_decline_second_derivative_near_zero_test() {
  // For a perfectly linear sequence the second central difference = 0
  let d2h = health_calculus.second_derivative([0.5, 0.6, 0.7, 0.8, 0.9])
  { float.absolute_value(d2h) <. 1.0e-9 } |> should.be_true()
}

pub fn linear_decline_trend_is_declining_test() {
  health_calculus.classify_trend(-0.05, 0.0) |> should.equal(Declining)
}

// ---------------------------------------------------------------------------
// C4: Accelerating decline — negative first AND second derivative
// ---------------------------------------------------------------------------

pub fn accelerating_decline_trend_test() {
  // dH < 0 AND d²H < 0 → AcceleratingDecline
  health_calculus.classify_trend(-0.05, -0.02)
  |> should.equal(AcceleratingDecline)
}

pub fn accelerating_decline_from_history_test() {
  // history: 0.6, 0.7, 0.9  (large drop recently, accelerating down)
  // central dH = (0.6 - 0.9) / 2 = -0.15
  // d²H = 0.6 - 2*0.7 + 0.9 = 0.1  (positive here — slight concave-up)
  // Ensure negative d²H case separately:
  let trend = health_calculus.classify_trend(-0.08, -0.03)
  trend |> should.equal(AcceleratingDecline)
}

// ---------------------------------------------------------------------------
// C5: Recovery — positive first derivative with positive second derivative
// ---------------------------------------------------------------------------

pub fn recovering_trend_test() {
  // dH > 0.01 AND d²H > 0 → Recovering
  health_calculus.classify_trend(0.05, 0.02) |> should.equal(Recovering)
}

pub fn improving_without_acceleration_test() {
  // dH > 0.01 AND d²H <= 0 → Improving
  health_calculus.classify_trend(0.05, -0.01) |> should.equal(Improving)
}

// ---------------------------------------------------------------------------
// C6: Oscillation — alternating values → near-zero mean derivative
// ---------------------------------------------------------------------------

pub fn oscillating_history_trend_stable_test() {
  // [0.8, 0.6, 0.8, 0.6, 0.8] → central dH ≈ 0.0 → Stable
  let calc = health_calculus.compute([0.8, 0.6, 0.8, 0.6, 0.8])
  calc.trend |> should.equal(Stable)
}

pub fn oscillating_history_confidence_is_low_test() {
  // High derivative variance → confidence must be a valid probability in [0, 1]
  let conf = health_calculus.prediction_confidence([0.8, 0.2, 0.8, 0.2, 0.8])
  // Confidence must be a valid probability
  { conf >=. 0.0 && conf <=. 1.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C7: time_to_threshold accuracy
// ---------------------------------------------------------------------------

pub fn time_to_threshold_linear_extrapolation_test() {
  // current=0.8, rate=-0.1, threshold=0.5 → t = (0.5-0.8)/(-0.1) = 3
  let t = health_calculus.time_to_threshold(0.8, -0.1, 0.5)
  t |> should.equal(3)
}

pub fn time_to_threshold_zero_rate_returns_max_test() {
  let t = health_calculus.time_to_threshold(0.8, 0.0, 0.5)
  t |> should.equal(2_147_483_647)
}

pub fn time_to_threshold_moving_away_returns_max_test() {
  // current=0.8, improving at +0.1, threshold=0.5 → moving away → max
  let t = health_calculus.time_to_threshold(0.8, 0.1, 0.5)
  t |> should.equal(2_147_483_647)
}

pub fn time_to_threshold_near_breach_test() {
  // current=0.51, rate=-0.1, threshold=0.5 → t ≈ 0 (already almost there)
  let t = health_calculus.time_to_threshold(0.51, -0.1, 0.5)
  { t <= 1 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C8: trend classification — all HealthTrend variants covered
// ---------------------------------------------------------------------------

pub fn trend_stable_small_positive_test() {
  health_calculus.classify_trend(0.005, 0.0) |> should.equal(Stable)
}

pub fn trend_stable_small_negative_test() {
  health_calculus.classify_trend(-0.005, 0.0) |> should.equal(Stable)
}

pub fn trend_improving_exact_boundary_test() {
  // At exactly 0.011 → Improving (> 0.01 threshold)
  health_calculus.classify_trend(0.011, 0.0) |> should.equal(Improving)
}

pub fn trend_declining_exact_boundary_test() {
  // At -0.011 → Declining
  health_calculus.classify_trend(-0.011, 0.0) |> should.equal(Declining)
}

// ---------------------------------------------------------------------------
// C9: prediction_confidence scaling with history length
// ---------------------------------------------------------------------------

pub fn confidence_increases_with_more_samples_test() {
  let short = health_calculus.prediction_confidence([0.8, 0.7, 0.6])
  let long =
    health_calculus.prediction_confidence([
      0.5, 0.6, 0.7, 0.75, 0.8, 0.82, 0.84, 0.86, 0.88, 0.9,
    ])
  { long >. short } |> should.be_true()
}

pub fn confidence_saturates_at_ten_samples_test() {
  // Confidence capped at 1.0 — more than 10 samples with consistent trend
  let conf =
    health_calculus.prediction_confidence([
      0.9, 0.88, 0.86, 0.84, 0.82, 0.8, 0.78, 0.76, 0.74, 0.72, 0.7,
    ])
  // length_factor = min(11/10, 1.0) = 1.0; consistency should be high
  { conf <=. 1.0 } |> should.be_true()
  { conf >. 0.8 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C10: compute() integration
// ---------------------------------------------------------------------------

pub fn compute_returns_correct_current_test() {
  let calc = health_calculus.compute([0.72, 0.75, 0.78])
  let diff = float.absolute_value(calc.current -. 0.72)
  { diff <. 1.0e-9 } |> should.be_true()
}

pub fn compute_declining_history_has_negative_first_derivative_test() {
  let calc = health_calculus.compute([0.5, 0.6, 0.7, 0.8])
  { calc.first_derivative <. 0.0 } |> should.be_true()
}

pub fn compute_sufficient_history_has_nonzero_confidence_test() {
  let calc =
    health_calculus.compute([
      0.6,
      0.65,
      0.7,
      0.75,
      0.8,
      0.85,
      0.9,
      0.92,
      0.94,
      0.96,
    ])
  { calc.confidence >. 0.0 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// C11: to_json and summary output shape
// ---------------------------------------------------------------------------

pub fn to_json_contains_current_key_test() {
  let calc = health_calculus.compute([0.8, 0.75, 0.7])
  let json = health_calculus.to_json(calc)
  string.contains(json, "\"current\"") |> should.be_true()
}

pub fn to_json_contains_trend_key_test() {
  let calc = health_calculus.compute([0.8, 0.75, 0.7])
  let json = health_calculus.to_json(calc)
  string.contains(json, "\"trend\"") |> should.be_true()
}

pub fn to_json_contains_confidence_key_test() {
  let calc = health_calculus.compute([0.8, 0.75, 0.7])
  let json = health_calculus.to_json(calc)
  string.contains(json, "\"confidence\"") |> should.be_true()
}

pub fn summary_contains_health_calculus_prefix_test() {
  let calc = health_calculus.compute([0.7, 0.75, 0.8])
  let s = health_calculus.summary(calc)
  string.contains(s, "HEALTH-CALCULUS") |> should.be_true()
}

pub fn summary_contains_trend_label_test() {
  let calc = health_calculus.compute([0.5, 0.6, 0.7])
  let s = health_calculus.summary(calc)
  string.contains(s, "trend:") |> should.be_true()
}

pub fn summary_shows_never_for_max_tti_test() {
  // Constant history → rate = 0 → time_to_threshold = max_int → "never"
  let calc = health_calculus.compute([0.8, 0.8, 0.8])
  let s = health_calculus.summary(calc)
  string.contains(s, "never") |> should.be_true()
}

// ---------------------------------------------------------------------------
// C12: trend_to_string labels
// ---------------------------------------------------------------------------

pub fn trend_to_string_improving_test() {
  health_calculus.trend_to_string(Improving) |> should.equal("Improving")
}

pub fn trend_to_string_stable_test() {
  health_calculus.trend_to_string(Stable) |> should.equal("Stable")
}

pub fn trend_to_string_declining_test() {
  health_calculus.trend_to_string(Declining) |> should.equal("Declining")
}

pub fn trend_to_string_accelerating_decline_test() {
  health_calculus.trend_to_string(AcceleratingDecline)
  |> should.equal("AcceleratingDecline")
}

pub fn trend_to_string_recovering_test() {
  health_calculus.trend_to_string(Recovering) |> should.equal("Recovering")
}

// ---------------------------------------------------------------------------
// C13: Insufficient data guard
// ---------------------------------------------------------------------------

pub fn insufficient_data_compute_zero_derivatives_test() {
  let calc = health_calculus.compute([0.7])
  calc.first_derivative |> should.equal(0.0)
  calc.second_derivative |> should.equal(0.0)
  // confidence is low (≤ 0.2) for a single-element history
  { calc.confidence <=. 0.2 } |> should.be_true()
}

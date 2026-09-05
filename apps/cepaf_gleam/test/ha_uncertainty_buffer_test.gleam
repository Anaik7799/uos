/// Uncertainty Buffer Tests — NIF output confidence intervals (SERBAN-2)
///
/// 13 tests covering: from_measurement, from_samples, is_reliable, merge,
/// to_json, summary.
///
/// Layer: L5_COGNITIVE
/// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001
/// Ultrathink: Focus #5 (Continuous Formal Verification),
///              Focus #6 (Embedded SLM Cognitive Kernels)
///
/// अनिश्चितता स्वीकारः ज्ञानस्य आरम्भः — Accepting uncertainty is the beginning of knowledge
import cepaf_gleam/ha/uncertainty_buffer.{
  from_measurement, from_samples, is_reliable, merge, summary, to_json,
}
import gleam/float
import gleam/string
import gleeunit/should

// ===========================================================================
// 1. from_measurement
// ===========================================================================

pub fn from_measurement_interval_contains_value_test() {
  let uv = from_measurement(0.75, 0.05)
  { uv.lower <=. uv.value && uv.value <=. uv.upper } |> should.be_true()
}

pub fn from_measurement_zero_noise_high_confidence_test() {
  let uv = from_measurement(0.9, 0.0)
  // lower == upper == value
  uv.lower |> should.equal(0.9)
  uv.upper |> should.equal(0.9)
  uv.confidence |> should.equal(1.0)
}

pub fn from_measurement_confidence_in_unit_interval_test() {
  let uv = from_measurement(0.5, 0.3)
  { uv.confidence >=. 0.0 && uv.confidence <=. 1.0 } |> should.be_true()
}

pub fn from_measurement_negative_noise_uses_absolute_value_test() {
  let uv_pos = from_measurement(0.5, 0.1)
  let uv_neg = from_measurement(0.5, -0.1)
  uv_pos.lower |> should.equal(uv_neg.lower)
  uv_pos.upper |> should.equal(uv_neg.upper)
}

// ===========================================================================
// 2. from_samples
// ===========================================================================

pub fn from_samples_empty_returns_zero_confidence_test() {
  let uv = from_samples([])
  uv.confidence |> should.equal(0.0)
  uv.value |> should.equal(0.0)
}

pub fn from_samples_single_element_zero_confidence_test() {
  let uv = from_samples([42.0])
  uv.confidence |> should.equal(0.0)
  uv.value |> should.equal(42.0)
}

pub fn from_samples_identical_values_high_confidence_test() {
  // All identical → σ = 0 → CV = 0 → confidence = 1.0
  let uv = from_samples([5.0, 5.0, 5.0, 5.0, 5.0])
  uv.value |> should.equal(5.0)
  { uv.confidence >. 0.9 } |> should.be_true()
}

pub fn from_samples_mean_is_correct_test() {
  // Mean of [1.0, 2.0, 3.0] = 2.0
  let uv = from_samples([1.0, 2.0, 3.0])
  let diff = float.absolute_value(uv.value -. 2.0)
  { diff <. 0.0001 } |> should.be_true()
}

pub fn from_samples_interval_bounds_ordering_test() {
  let uv = from_samples([1.0, 2.0, 3.0, 4.0, 5.0])
  { uv.lower <=. uv.value && uv.value <=. uv.upper } |> should.be_true()
}

// ===========================================================================
// 3. is_reliable
// ===========================================================================

pub fn is_reliable_above_threshold_returns_true_test() {
  let uv = from_measurement(0.9, 0.01)
  // confidence close to 1.0 — reliable above 0.5
  is_reliable(uv, 0.5) |> should.be_true()
}

pub fn is_reliable_below_threshold_returns_false_test() {
  let uv = from_samples([])
  // confidence = 0.0 — not reliable above any positive threshold
  is_reliable(uv, 0.1) |> should.be_false()
}

// ===========================================================================
// 4. merge
// ===========================================================================

pub fn merge_two_certain_values_keeps_max_confidence_test() {
  let a = from_measurement(0.8, 0.0)
  let b = from_measurement(0.6, 0.0)
  let m = merge(a, b)
  { m.confidence >=. 0.9 } |> should.be_true()
}

// ===========================================================================
// 5. to_json and summary
// ===========================================================================

pub fn to_json_contains_value_key_test() {
  let uv = from_measurement(0.7, 0.05)
  { string.contains(to_json(uv), "\"value\"") } |> should.be_true()
}

pub fn summary_contains_conf_label_test() {
  let uv = from_measurement(0.7, 0.05)
  { string.contains(summary(uv), "conf=") } |> should.be_true()
}

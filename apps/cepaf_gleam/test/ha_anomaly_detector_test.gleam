/// F16 Anomaly Detection with Statistical Baselines — 25-test suite
/// Layer: L5_COGNITIVE
/// STAMP: SC-SIL4-001, SC-HA-001, SC-GLM-UI-001, SC-MUDA-001
/// Ultrathink: Focus #8 (Continuous Stochastic Apoptosis), #5 (Formal Verification)
///
/// विद्याविद्ये ईशते — The Lord rules over knowledge and ignorance (Shvetashvatara 1.10)
import cepaf_gleam/ha/anomaly_detector.{
  Anomaly, AnomalyHigh, AnomalyLow, InsufficientData, Normal, init_baseline,
  init_baseline_default, is_anomaly, is_high, is_insufficient, is_low, is_normal,
  observe, result_to_string, to_json, update_stats, z_score,
}
import gleam/string
import gleeunit/should

// ===========================================================================
// Initialisation
// ===========================================================================

pub fn init_baseline_creates_zeroed_state_test() {
  let b = init_baseline("cpu_usage", 3.0)
  b.sample_count |> should.equal(0)
  b.mean |> should.equal(0.0)
  b.std_dev |> should.equal(0.0)
  b.sigma_threshold |> should.equal(3.0)
  b.metric_name |> should.equal("cpu_usage")
}

pub fn init_baseline_default_uses_3_sigma_test() {
  let b = init_baseline_default("latency_ms")
  b.sigma_threshold |> should.equal(3.0)
  b.metric_name |> should.equal("latency_ms")
}

// ===========================================================================
// Welford's algorithm — update_stats
// ===========================================================================

pub fn update_stats_first_observation_test() {
  let b = init_baseline_default("metric")
  let b2 = update_stats(b, 10.0)
  b2.sample_count |> should.equal(1)
  b2.mean |> should.equal(10.0)
  b2.last_value |> should.equal(10.0)
  b2.min_value |> should.equal(10.0)
  b2.max_value |> should.equal(10.0)
}

pub fn update_stats_two_observations_mean_test() {
  let b = init_baseline_default("metric")
  let b2 = update_stats(b, 10.0) |> update_stats(20.0)
  b2.sample_count |> should.equal(2)
  // mean = (10 + 20) / 2 = 15
  b2.mean |> should.equal(15.0)
}

pub fn update_stats_std_dev_stable_series_test() {
  // All identical values => std_dev = 0
  let b = init_baseline_default("metric")
  let b2 =
    b
    |> update_stats(5.0)
    |> update_stats(5.0)
    |> update_stats(5.0)
    |> update_stats(5.0)
  b2.mean |> should.equal(5.0)
  b2.std_dev |> should.equal(0.0)
}

pub fn update_stats_tracks_min_max_test() {
  let b = init_baseline_default("metric")
  let b2 =
    b
    |> update_stats(3.0)
    |> update_stats(7.0)
    |> update_stats(1.0)
    |> update_stats(9.0)
  b2.min_value |> should.equal(1.0)
  b2.max_value |> should.equal(9.0)
}

pub fn update_stats_increments_sample_count_test() {
  let b = init_baseline_default("m")
  let b5 =
    b
    |> update_stats(1.0)
    |> update_stats(2.0)
    |> update_stats(3.0)
    |> update_stats(4.0)
    |> update_stats(5.0)
  b5.sample_count |> should.equal(5)
}

pub fn update_stats_preserves_metric_name_test() {
  let b = init_baseline_default("my_metric")
  let b2 = update_stats(b, 42.0)
  b2.metric_name |> should.equal("my_metric")
}

// ===========================================================================
// Z-score
// ===========================================================================

pub fn z_score_above_mean_positive_test() {
  // z = (15 - 10) / 5 = 1.0
  z_score(15.0, 10.0, 5.0) |> should.equal(1.0)
}

pub fn z_score_below_mean_negative_test() {
  // z = (5 - 10) / 5 = -1.0
  z_score(5.0, 10.0, 5.0) |> should.equal(-1.0)
}

pub fn z_score_zero_std_dev_returns_zero_test() {
  z_score(99.0, 10.0, 0.0) |> should.equal(0.0)
}

pub fn z_score_at_mean_is_zero_test() {
  z_score(10.0, 10.0, 5.0) |> should.equal(0.0)
}

// ===========================================================================
// observe/2 — the main integration function
// ===========================================================================

pub fn observe_first_sample_insufficient_test() {
  let b = init_baseline_default("cpu")
  let #(_, result) = observe(b, 50.0)
  result |> is_insufficient() |> should.be_true()
}

pub fn observe_normal_value_in_range_test() {
  // Build a stable baseline around 100.0, then check a value inside 3 sigma
  let b =
    init_baseline_default("cpu")
    |> update_stats(100.0)
    |> update_stats(100.0)
    |> update_stats(100.0)
    |> update_stats(100.0)
    |> update_stats(100.0)
    |> update_stats(100.0)
  // At this point std_dev is 0, so any value would yield z=0 => Normal
  let #(_, result) = observe(b, 100.0)
  result |> is_normal() |> should.be_true()
}

pub fn observe_high_anomaly_detected_test() {
  // Build a baseline with mean=10, std_dev~=1, then spike to 100 (>>3 sigma)
  let b =
    init_baseline("latency", 3.0)
    |> update_stats(9.0)
    |> update_stats(10.0)
    |> update_stats(11.0)
    |> update_stats(10.0)
    |> update_stats(9.0)
    |> update_stats(10.0)
    |> update_stats(11.0)
    |> update_stats(10.0)
    |> update_stats(9.0)
    |> update_stats(10.0)
  let #(_, result) = observe(b, 100.0)
  result |> is_anomaly() |> should.be_true()
  case result {
    Anomaly(_, _, direction) -> direction |> is_high() |> should.be_true()
    _ -> should.fail()
  }
}

pub fn observe_low_anomaly_detected_test() {
  // Build a baseline with mean~=10, then plunge to -100 (<<3 sigma)
  let b =
    init_baseline("latency", 3.0)
    |> update_stats(9.0)
    |> update_stats(10.0)
    |> update_stats(11.0)
    |> update_stats(10.0)
    |> update_stats(9.0)
    |> update_stats(10.0)
    |> update_stats(11.0)
    |> update_stats(10.0)
    |> update_stats(9.0)
    |> update_stats(10.0)
  let #(_, result) = observe(b, -100.0)
  result |> is_anomaly() |> should.be_true()
  case result {
    Anomaly(_, _, direction) -> direction |> is_low() |> should.be_true()
    _ -> should.fail()
  }
}

pub fn observe_updates_baseline_sample_count_test() {
  let b = init_baseline_default("m")
  let #(b2, _) = observe(b, 5.0)
  b2.sample_count |> should.equal(1)
  let #(b3, _) = observe(b2, 6.0)
  b3.sample_count |> should.equal(2)
}

// ===========================================================================
// Predicates
// ===========================================================================

pub fn is_anomaly_on_anomaly_result_test() {
  is_anomaly(Anomaly(99.0, 5.0, AnomalyHigh)) |> should.be_true()
}

pub fn is_anomaly_on_normal_result_test() {
  is_anomaly(Normal(10.0, 0.5)) |> should.be_false()
}

pub fn is_normal_on_normal_result_test() {
  is_normal(Normal(10.0, 0.5)) |> should.be_true()
}

pub fn is_insufficient_on_insufficient_result_test() {
  is_insufficient(InsufficientData(1, 2)) |> should.be_true()
}

pub fn direction_high_test() {
  is_high(AnomalyHigh) |> should.be_true()
  is_low(AnomalyHigh) |> should.be_false()
}

pub fn direction_low_test() {
  is_low(AnomalyLow) |> should.be_true()
  is_high(AnomalyLow) |> should.be_false()
}

// ===========================================================================
// Serialisation
// ===========================================================================

pub fn result_to_string_normal_test() {
  let s = result_to_string(Normal(10.0, 0.5))
  s |> string.contains("Normal") |> should.be_true()
  s |> string.contains("10.0") |> should.be_true()
}

pub fn result_to_string_anomaly_high_test() {
  let s = result_to_string(Anomaly(99.0, 4.2, AnomalyHigh))
  s |> string.contains("ANOMALY") |> should.be_true()
  s |> string.contains("HIGH") |> should.be_true()
}

pub fn result_to_string_anomaly_low_test() {
  let s = result_to_string(Anomaly(-5.0, -4.5, AnomalyLow))
  s |> string.contains("LOW") |> should.be_true()
}

pub fn result_to_string_insufficient_test() {
  let s = result_to_string(InsufficientData(1, 2))
  s |> string.contains("InsufficientData") |> should.be_true()
  s |> string.contains("1") |> should.be_true()
}

pub fn to_json_contains_metric_name_test() {
  let b = init_baseline_default("error_rate")
  let json = to_json(b)
  json |> string.contains("error_rate") |> should.be_true()
  json |> string.contains("mean") |> should.be_true()
  json |> string.contains("std_dev") |> should.be_true()
  json |> string.contains("sample_count") |> should.be_true()
}

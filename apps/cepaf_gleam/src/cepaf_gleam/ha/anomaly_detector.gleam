//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/anomaly_detector</module>
////     <fsharp-lineage>None — novel statistical anomaly detection (F16)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Statistical anomaly detection using Welford's online algorithm for
////       numerically stable running mean and standard deviation. Detects metric
////       deviations beyond configurable sigma thresholds. Zero I/O — pure
////       functional state-in / state-out interface.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-002, SC-GLM-UI-001, SC-MUDA-001, SC-HA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Welford (1962) online algorithm ↪ Gleam pure functions.
////       Running mean and M2 (sum of squared deviations) updated per observation.
////       Variance = M2 / (n - 1) for n >= 2; std_dev = sqrt(variance).
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 ↠ Erlang float.
////       Mitigation: Welford's algorithm is numerically stable; precision loss
////       is bounded and acceptable for statistical anomaly thresholds.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// STATISTICAL ANOMALY DETECTION — F16
//// विद्याविद्ये ईशते — The Lord rules over knowledge and ignorance (Shvetashvatara 1.10)
////
//// Detects statistical anomalies in time-series metrics using:
////   - Welford's online algorithm (numerically stable running mean/variance)
////   - Z-score threshold detection (default: 3.0 sigma)
////   - Directional classification (AnomalyHigh / AnomalyLow)
////   - Minimum sample gate (requires >= 2 observations for meaningful std_dev)
////
//// Algorithm (Welford 1962):
////   n     = n + 1
////   delta = value - mean
////   mean  = mean + delta / n
////   delta2 = value - mean
////   m2    = m2 + delta * delta2
////   variance = m2 / (n - 1)   -- for n >= 2
////   std_dev  = sqrt(variance)
////
//// Z-score: z = (value - mean) / std_dev
////   |z| > sigma_threshold => Anomaly(direction)
////   |z| <= sigma_threshold => Normal
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-GLM-UI-001, SC-MUDA-001, SC-HA-001

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// External FFI — Erlang math:sqrt/1 for numerically stable square root
// ---------------------------------------------------------------------------

@external(erlang, "math", "sqrt")
fn erlang_sqrt(x: Float) -> Float

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/// A single metric observation
pub type Observation {
  Observation(value: Float, timestamp: Int, metric_name: String)
}

/// Direction of an anomaly
pub type AnomalyDirection {
  AnomalyHigh
  AnomalyLow
}

/// Result of checking a single observation against a baseline
pub type AnomalyResult {
  /// Value within the sigma threshold — normal operation
  Normal(value: Float, z_score: Float)
  /// Value exceeds the sigma threshold — anomaly detected
  Anomaly(value: Float, z_score: Float, direction: AnomalyDirection)
  /// Not enough observations to compute std_dev yet
  InsufficientData(sample_count: Int, min_required: Int)
}

/// Statistical baseline for a single metric.
/// Internally carries m2 (sum of squared deviations from mean) for
/// Welford's algorithm; exposed fields are the human-readable statistics.
pub type Baseline {
  Baseline(
    metric_name: String,
    /// Running mean (Welford)
    mean: Float,
    /// Running population standard deviation estimate
    std_dev: Float,
    /// Number of observations absorbed so far
    sample_count: Int,
    /// Minimum value observed
    min_value: Float,
    /// Maximum value observed
    max_value: Float,
    /// Most recently observed value
    last_value: Float,
    /// |z| > sigma_threshold triggers Anomaly (default 3.0)
    sigma_threshold: Float,
    /// Internal: sum of squared deviations from mean (Welford's M2)
    m2: Float,
  )
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Minimum samples required before anomaly detection is meaningful
pub const min_samples_required: Int = 2

/// Default sigma threshold (3-sigma rule covers 99.73% of normal distribution)
pub const default_sigma_threshold: Float = 3.0

// ---------------------------------------------------------------------------
// Initialisation
// ---------------------------------------------------------------------------

/// Initialise a fresh baseline for the given metric.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pure constructor ↪ zeroed Welford state</morphism>
///   <formal-proof>
///     <P> metric_name is non-empty; sigma_threshold > 0.0 </P>
///     <C> init_baseline(metric_name, sigma_threshold) </C>
///     <Q> Baseline with sample_count=0, mean=0.0, std_dev=0.0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init_baseline(metric_name: String, sigma_threshold: Float) -> Baseline {
  Baseline(
    metric_name: metric_name,
    mean: 0.0,
    std_dev: 0.0,
    sample_count: 0,
    min_value: 0.0,
    max_value: 0.0,
    last_value: 0.0,
    sigma_threshold: sigma_threshold,
    m2: 0.0,
  )
}

/// Initialise a baseline with the default sigma threshold (3.0).
pub fn init_baseline_default(metric_name: String) -> Baseline {
  init_baseline(metric_name, default_sigma_threshold)
}

// ---------------------------------------------------------------------------
// Welford's Online Algorithm
// ---------------------------------------------------------------------------

/// Update running mean, M2, and std_dev using Welford's algorithm.
///
/// Numerically stable O(1) per-sample update.  For n >= 2 the variance
/// estimate is unbiased (Bessel's correction: M2 / (n-1)).
pub fn update_stats(baseline: Baseline, value: Float) -> Baseline {
  let n = baseline.sample_count + 1
  let delta = value -. baseline.mean
  let new_mean = baseline.mean +. delta /. int.to_float(n)
  let delta2 = value -. new_mean
  let new_m2 = baseline.m2 +. delta *. delta2

  let new_std_dev = case n >= 2 {
    True -> {
      let variance = new_m2 /. int.to_float(n - 1)
      // Clamp to zero to guard against tiny negative floats from rounding
      let safe_variance = case variance <. 0.0 {
        True -> 0.0
        False -> variance
      }
      erlang_sqrt(safe_variance)
    }
    False -> 0.0
  }

  let new_min = case baseline.sample_count == 0 || value <. baseline.min_value {
    True -> value
    False -> baseline.min_value
  }
  let new_max = case baseline.sample_count == 0 || value >. baseline.max_value {
    True -> value
    False -> baseline.max_value
  }

  Baseline(
    ..baseline,
    mean: new_mean,
    std_dev: new_std_dev,
    sample_count: n,
    min_value: new_min,
    max_value: new_max,
    last_value: value,
    m2: new_m2,
  )
}

// ---------------------------------------------------------------------------
// Z-score computation
// ---------------------------------------------------------------------------

/// Compute the standard score: z = (value - mean) / std_dev.
///
/// Returns 0.0 when std_dev is zero (constant signal — treat as normal).
pub fn z_score(value: Float, mean: Float, std_dev: Float) -> Float {
  case std_dev == 0.0 {
    True -> 0.0
    False -> { value -. mean } /. std_dev
  }
}

// ---------------------------------------------------------------------------
// Core observe/check logic
// ---------------------------------------------------------------------------

/// Ingest a new value, update the baseline, and classify the observation.
///
/// Returns the updated Baseline and an AnomalyResult.  The caller is
/// responsible for persisting the updated Baseline.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Observation ↪ updated Baseline + classified result</morphism>
///   <formal-proof>
///     <P> baseline is initialised; value is finite Float </P>
///     <C> observe(baseline, value) </C>
///     <Q>
///       If n < min_samples_required: InsufficientData
///       Else if |z| > sigma_threshold: Anomaly(direction)
///       Else: Normal(value, z)
///     </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn observe(baseline: Baseline, value: Float) -> #(Baseline, AnomalyResult) {
  let updated = update_stats(baseline, value)
  let result = classify(updated, value)
  #(updated, result)
}

/// Classify a value against an already-updated baseline.
fn classify(baseline: Baseline, value: Float) -> AnomalyResult {
  case baseline.sample_count < min_samples_required {
    True -> InsufficientData(baseline.sample_count, min_samples_required)
    False -> {
      let z = z_score(value, baseline.mean, baseline.std_dev)
      let abs_z = float.absolute_value(z)
      case abs_z >. baseline.sigma_threshold {
        False -> Normal(value, z)
        True -> {
          let direction = case z >. 0.0 {
            True -> AnomalyHigh
            False -> AnomalyLow
          }
          Anomaly(value, z, direction)
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Convenience predicates
// ---------------------------------------------------------------------------

/// Returns True if the result is an Anomaly variant.
pub fn is_anomaly(result: AnomalyResult) -> Bool {
  case result {
    Anomaly(_, _, _) -> True
    Normal(_, _) -> False
    InsufficientData(_, _) -> False
  }
}

/// Returns True if the result is Normal.
pub fn is_normal(result: AnomalyResult) -> Bool {
  case result {
    Normal(_, _) -> True
    Anomaly(_, _, _) -> False
    InsufficientData(_, _) -> False
  }
}

/// Returns True if there is not yet enough data to classify.
pub fn is_insufficient(result: AnomalyResult) -> Bool {
  case result {
    InsufficientData(_, _) -> True
    Normal(_, _) -> False
    Anomaly(_, _, _) -> False
  }
}

// ---------------------------------------------------------------------------
// Direction helpers
// ---------------------------------------------------------------------------

/// Returns True when the anomaly direction is above the mean.
pub fn is_high(direction: AnomalyDirection) -> Bool {
  case direction {
    AnomalyHigh -> True
    AnomalyLow -> False
  }
}

/// Returns True when the anomaly direction is below the mean.
pub fn is_low(direction: AnomalyDirection) -> Bool {
  case direction {
    AnomalyLow -> True
    AnomalyHigh -> False
  }
}

// ---------------------------------------------------------------------------
// Serialisation helpers
// ---------------------------------------------------------------------------

/// Convert an AnomalyResult to a human-readable string (logging / TUI).
pub fn result_to_string(result: AnomalyResult) -> String {
  case result {
    Normal(value, z) ->
      "Normal(value="
      <> float.to_string(value)
      <> " z="
      <> float.to_string(z)
      <> ")"
    Anomaly(value, z, direction) -> {
      let dir_str = case direction {
        AnomalyHigh -> "HIGH"
        AnomalyLow -> "LOW"
      }
      "ANOMALY(value="
      <> float.to_string(value)
      <> " z="
      <> float.to_string(z)
      <> " direction="
      <> dir_str
      <> ")"
    }
    InsufficientData(n, required) ->
      "InsufficientData(have="
      <> int.to_string(n)
      <> " need="
      <> int.to_string(required)
      <> ")"
  }
}

/// Serialise a Baseline to a compact JSON string.
pub fn to_json(baseline: Baseline) -> String {
  "{"
  <> "\"metric_name\":"
  <> "\""
  <> baseline.metric_name
  <> "\","
  <> "\"mean\":"
  <> float.to_string(baseline.mean)
  <> ","
  <> "\"std_dev\":"
  <> float.to_string(baseline.std_dev)
  <> ","
  <> "\"sample_count\":"
  <> int.to_string(baseline.sample_count)
  <> ","
  <> "\"min_value\":"
  <> float.to_string(baseline.min_value)
  <> ","
  <> "\"max_value\":"
  <> float.to_string(baseline.max_value)
  <> ","
  <> "\"last_value\":"
  <> float.to_string(baseline.last_value)
  <> ","
  <> "\"sigma_threshold\":"
  <> float.to_string(baseline.sigma_threshold)
  <> "}"
}

/// Serialise a list of AnomalyResults to a JSON array.
pub fn results_to_json(results: List(AnomalyResult)) -> String {
  let inner =
    results
    |> list_map_join(
      fn(r) {
        case r {
          Normal(value, z) ->
            "{\"type\":\"normal\",\"value\":"
            <> float.to_string(value)
            <> ",\"z_score\":"
            <> float.to_string(z)
            <> "}"
          Anomaly(value, z, direction) -> {
            let dir_str = case direction {
              AnomalyHigh -> "high"
              AnomalyLow -> "low"
            }
            "{\"type\":\"anomaly\",\"value\":"
            <> float.to_string(value)
            <> ",\"z_score\":"
            <> float.to_string(z)
            <> ",\"direction\":\""
            <> dir_str
            <> "\"}"
          }
          InsufficientData(n, req) ->
            "{\"type\":\"insufficient_data\",\"sample_count\":"
            <> int.to_string(n)
            <> ",\"min_required\":"
            <> int.to_string(req)
            <> "}"
        }
      },
      ",",
    )
  "[" <> inner <> "]"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn list_map_join(
  items: List(a),
  mapper: fn(a) -> String,
  sep: String,
) -> String {
  do_map_join(items, mapper, sep, "")
}

fn do_map_join(
  items: List(a),
  mapper: fn(a) -> String,
  sep: String,
  acc: String,
) -> String {
  case items {
    [] -> acc
    [x] -> {
      let s = mapper(x)
      case string.is_empty(acc) {
        True -> s
        False -> acc <> sep <> s
      }
    }
    [x, ..rest] -> {
      let s = mapper(x)
      let new_acc = case string.is_empty(acc) {
        True -> s
        False -> acc <> sep <> s
      }
      do_map_join(rest, mapper, sep, new_acc)
    }
  }
}

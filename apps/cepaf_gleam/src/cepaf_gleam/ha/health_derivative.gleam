//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/health_derivative</module>
////     <fsharp-lineage>None — novel stateful derivative tracker (F20)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       d(Health)/dt — Predictive derivative calculus for health time series.
////       Tracks velocity and acceleration of system health using real
////       wall-clock timestamps (milliseconds). Predicts future health via
////       Taylor expansion and classifies alert severity from derivatives.
////       Integrates with truth_audit and freshness_monitor for proactive OODA.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-TRUTH-001, SC-EVO-KPI-001, SC-MATH-001, SC-SIL4-001, SC-OODA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Timestamped health samples ↪ HealthDerivative (velocity, acceleration,
////       prediction, alert classification). All state passed by value — pure.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic on ms timestamps.
////       Precision adequate for operator alerting; not used for safety actuation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// HEALTH DERIVATIVE — STATEFUL d(H)/dt DERIVATIVE TRACKING FOR PREDICTIVE ALERTS
////
//// Tracks the first and second derivatives of system health in real time,
//// using actual wall-clock timestamps from HealthSample records so that
//// derivatives are in physical units (change per second).
////
//// Numerical differentiation scheme (central difference, 3+ samples):
////
////   dt₁ = (t[0] - t[2]) / 2  (milliseconds, then converted to seconds)
////   v   = (h[0] - h[2]) / (dt₁ / 1000.0)    — first derivative [/s]
////   a   = (h[0] - 2·h[1] + h[2]) / (Δt/1000)²  — second derivative [/s²]
////
////   2-sample case uses forward/backward difference (1st-order):
////   v = (h[0] - h[1]) / dt_s
////
//// Prediction uses Taylor expansion (order 2):
////   H(t+Δ) ≈ H + v·Δ + 0.5·a·Δ²
////   Result clamped to [0.0, 1.0].
////
//// Samples are kept in a ring-buffer list (most-recent first) capped at 10.
////
//// STAMP: SC-TRUTH-001, SC-EVO-KPI-001, SC-MATH-001, SC-SIL4-001, SC-OODA-001

import gleam/float
import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A single health measurement at a wall-clock point in time.
pub type HealthSample {
  HealthSample(
    /// Milliseconds since epoch (or any monotone reference)
    timestamp_ms: Int,
    /// Health value in [0.0, 1.0]
    value: Float,
  )
}

/// Alert level derived from derivative analysis.
pub type DerivativeAlert {
  /// Health stable or improving — no action required
  Stable
  /// Health declining slowly (velocity < -0.01 /s)
  Declining
  /// Health declining AND accelerating downward (v < 0 AND a < 0)
  Accelerating
  /// Predicted health will cross 0.5 threshold within 60 s at current rate
  CriticalPredicted
  /// Current health is already below 0.5 threshold
  Critical
}

/// Derivative state — tracks velocity, acceleration, and predictions for
/// a single health time-series.  Immutable; update() returns a new record.
pub type HealthDerivative {
  HealthDerivative(
    /// Current (most-recent) health value — [0.0, 1.0]
    current: Float,
    /// First derivative d(H)/dt — rate of change per second (positive = improving)
    velocity: Float,
    /// Second derivative d²(H)/dt² — acceleration per s² (negative = worsening faster)
    acceleration: Float,
    /// Predicted health 60 s from now via Taylor expansion, clamped [0.0, 1.0]
    predicted_60s: Float,
    /// Predicted health 300 s (5 min) from now, clamped [0.0, 1.0]
    predicted_300s: Float,
    /// Recent samples: most-recent first, capped at 10
    samples: List(HealthSample),
    /// Alert level derived from current derivatives and predictions
    alert: DerivativeAlert,
  )
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Critical health threshold — below this health is in danger
const critical_threshold: Float = 0.5

/// Seconds ahead for the short prediction window
const short_prediction_s: Float = 60.0

/// Seconds ahead for the long prediction window
const long_prediction_s: Float = 300.0

/// Maximum samples retained in the ring-buffer
const max_samples: Int = 10

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a HealthDerivative with a starting health value.
///
/// No timestamp is taken at init time — the first HealthSample is added via
/// update/2.  Until at least one sample is provided via update the initial
/// health is stored as `current`; derivatives are zero.
pub fn init(initial_health: Float) -> HealthDerivative {
  let clamped = clamp(initial_health, 0.0, 1.0)
  HealthDerivative(
    current: clamped,
    velocity: 0.0,
    acceleration: 0.0,
    predicted_60s: clamped,
    predicted_300s: clamped,
    samples: [],
    alert: Stable,
  )
}

/// Add a new health sample and recompute all derivative fields.
///
/// The sample is prepended to the ring-buffer (most-recent first).
/// Only the last `max_samples` (10) samples are retained.
/// Derivatives are recomputed from the updated buffer.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">
///     (HealthDerivative, HealthSample) ↪ HealthDerivative
///   </morphism>
///   <formal-proof>
///     <P> Pre: state is valid HealthDerivative. sample.value in [0,1].
///         sample.timestamp_ms is monotone-increasing relative to newest
///         sample in state.samples (caller's responsibility). </P>
///     <C> update(state, sample) </C>
///     <Q> Post: returned state has sample prepended; buffer capped at 10.
///         Derivatives computed from updated buffer.
///         Predictions clamped to [0.0, 1.0].
///         Alert classified from derivatives and predictions. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn update(
  state: HealthDerivative,
  sample: HealthSample,
) -> HealthDerivative {
  // Prepend newest sample, cap ring-buffer
  let new_samples =
    [sample, ..state.samples]
    |> list.take(max_samples)

  let v = compute_velocity(new_samples)
  let a = compute_acceleration(new_samples)
  let p60 =
    clamp(predict_from(sample.value, v, a, short_prediction_s), 0.0, 1.0)
  let p300 =
    clamp(predict_from(sample.value, v, a, long_prediction_s), 0.0, 1.0)

  HealthDerivative(
    current: sample.value,
    velocity: v,
    acceleration: a,
    predicted_60s: p60,
    predicted_300s: p300,
    samples: new_samples,
    alert: classify_alert_from(sample.value, v, a, p60),
  )
}

/// Classify the alert level from the current derivative state.
///
/// Rules (applied in priority order):
///   1. Critical         — current < threshold
///   2. CriticalPredicted — predicted_60s < threshold (but current is OK)
///   3. Accelerating     — v < 0 AND a < 0
///   4. Declining        — v < -0.01
///   5. Stable           — otherwise
pub fn classify_alert(state: HealthDerivative) -> DerivativeAlert {
  classify_alert_from(
    state.current,
    state.velocity,
    state.acceleration,
    state.predicted_60s,
  )
}

/// Predict health at `dt_seconds` ahead using Taylor expansion (order 2).
///
///   H(t+Δ) ≈ current + velocity·Δ + 0.5·acceleration·Δ²
///
/// Result is clamped to [0.0, 1.0].
pub fn predict(state: HealthDerivative, dt_seconds: Float) -> Float {
  clamp(
    predict_from(state.current, state.velocity, state.acceleration, dt_seconds),
    0.0,
    1.0,
  )
}

/// Human-readable one-line summary of the current derivative state.
///
/// Example:
///   H=0.72 v=-0.02/s a=-0.001/s² p60=0.52 p300=-0.28→0.00 alert:CriticalPredicted
pub fn summary(state: HealthDerivative) -> String {
  "H="
  <> float.to_string(state.current)
  <> " v="
  <> float.to_string(state.velocity)
  <> "/s a="
  <> float.to_string(state.acceleration)
  <> "/s² p60="
  <> float.to_string(state.predicted_60s)
  <> " p300="
  <> float.to_string(state.predicted_300s)
  <> " alert:"
  <> alert_to_string(state.alert)
  <> " samples="
  <> int.to_string(list.length(state.samples))
}

/// Convert a DerivativeAlert to its string label.
pub fn alert_to_string(alert: DerivativeAlert) -> String {
  case alert {
    Stable -> "Stable"
    Declining -> "Declining"
    Accelerating -> "Accelerating"
    CriticalPredicted -> "CriticalPredicted"
    Critical -> "Critical"
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Compute the first derivative (velocity) d(H)/dt in units of health/second
/// from the most-recent samples (most-recent first).
///
///   n < 2  → 0.0
///   n = 2  → (h[0] - h[1]) / dt_s   (forward difference)
///   n >= 3 → (h[0] - h[2]) / (2 · avg_dt_s)   (central difference)
///
/// dt_s is derived from the timestamps of the relevant samples.
fn compute_velocity(samples: List(HealthSample)) -> Float {
  case samples {
    [] -> 0.0
    [_] -> 0.0
    [s0, s1] -> {
      let dt_ms = s0.timestamp_ms - s1.timestamp_ms
      case dt_ms <= 0 {
        True -> 0.0
        False -> { s0.value -. s1.value } /. ms_to_s(dt_ms)
      }
    }
    [s0, _, s2, ..] -> {
      let dt_ms = s0.timestamp_ms - s2.timestamp_ms
      case dt_ms <= 0 {
        True -> 0.0
        False -> { s0.value -. s2.value } /. ms_to_s(dt_ms)
      }
    }
  }
}

/// Compute the second derivative (acceleration) d²(H)/dt² in health/s².
///
///   n < 3  → 0.0
///   n >= 3 → (h[0] - 2·h[1] + h[2]) / avg_dt_s²
///
/// avg_dt_s = average of the two step intervals in the 3-point window.
fn compute_acceleration(samples: List(HealthSample)) -> Float {
  case samples {
    [] -> 0.0
    [_] -> 0.0
    [_, _] -> 0.0
    [s0, s1, s2, ..] -> {
      let dt1_ms = s1.timestamp_ms - s2.timestamp_ms
      let dt2_ms = s0.timestamp_ms - s1.timestamp_ms
      case dt1_ms <= 0 || dt2_ms <= 0 {
        True -> 0.0
        False -> {
          let avg_dt_s = { ms_to_s(dt1_ms) +. ms_to_s(dt2_ms) } /. 2.0
          let numerator = s0.value -. { 2.0 *. s1.value } +. s2.value
          numerator /. { avg_dt_s *. avg_dt_s }
        }
      }
    }
  }
}

/// Taylor expansion: H + v·Δ + 0.5·a·Δ²
fn predict_from(
  current: Float,
  velocity: Float,
  acceleration: Float,
  dt_s: Float,
) -> Float {
  current +. velocity *. dt_s +. 0.5 *. acceleration *. dt_s *. dt_s
}

/// Alert classification from raw derivative values (pure, no state needed).
fn classify_alert_from(
  current: Float,
  v: Float,
  a: Float,
  p60: Float,
) -> DerivativeAlert {
  case current <. critical_threshold {
    True -> Critical
    False ->
      case p60 <. critical_threshold {
        True -> CriticalPredicted
        False ->
          case v <. 0.0 && a <. 0.0 {
            True -> Accelerating
            False ->
              case v <. -0.01 {
                True -> Declining
                False -> Stable
              }
          }
      }
  }
}

/// Convert integer milliseconds to Float seconds.
fn ms_to_s(ms: Int) -> Float {
  int.to_float(ms) /. 1000.0
}

/// Clamp a Float value to [lo, hi].
fn clamp(value: Float, lo: Float, hi: Float) -> Float {
  float.max(lo, float.min(hi, value))
}

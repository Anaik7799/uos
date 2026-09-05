//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/health_calculus</module>
////     <fsharp-lineage>None — novel differential calculus on health time-series (F19)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       कालगणना — The calculus of time.
////       Full differential calculus on health time-series: first derivative
////       (rate of change), second derivative (acceleration), trend classification,
////       time-to-threshold extrapolation, and prediction confidence.
////       Integrates with truth_audit predictions for proactive OODA intervention.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-002, SC-HA-001, SC-OODA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Numerical differentiation via finite differences ↪ Gleam pure functions.
////       Central difference for interior points (2nd-order accurate, O(Δt²)).
////       Forward/backward difference at endpoints (1st-order accurate, O(Δt)).
////       All state passed by value — zero side-effects.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 calculus ↠ Erlang float arithmetic.
////       Mitigation: Results used for trend classification and operator alerting,
////       not safety actuation. Sub-percent precision is sufficient.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// HEALTH CALCULUS — DIFFERENTIAL ANALYSIS OF HEALTH TIME SERIES
//// कालगणना — The calculus of time (Sanskrit: kāla = time, gaṇanā = calculation)
////
//// Computes full calculus on a health history ring-buffer (most-recent first):
////
////   First derivative  d(H)/dt  — rate of change per unit time-step
////   Second derivative d²(H)/dt² — acceleration of change
////   Trend classification — Improving / Stable / Declining / AcceleratingDecline / Recovering
////   Time-to-threshold — linear extrapolation to breach at current rate
////   Prediction confidence — based on history length and derivative consistency
////
//// Finite difference schemes (Δt = 1 time-step, normalised):
////
////   Interior: d(H)/dt ≈ (H[i-1] − H[i+1]) / 2   (central difference)
////             d²(H)/dt² ≈ H[i-1] − 2·H[i] + H[i+1]  (second central)
////   Endpoint: forward/backward first-order difference
////
//// For a list `history` with most-recent element first:
////   index 0 = H_n  (newest)
////   index 1 = H_{n-1}
////   index 2 = H_{n-2}
////
//// Central difference at index 1 (middle of a 3-point window):
////   dH = (H[0] - H[2]) / 2
////   d2H = H[0] - 2*H[1] + H[2]
////
//// Time-to-threshold:  t = (threshold − current) / |dH/dt|
////   Returns max_int when rate ≈ 0 (never reaches threshold).
////
//// Confidence = min(length_factor, consistency_factor)
////   length_factor    = min(n / 10.0, 1.0)        saturates at 10 samples
////   consistency_factor = max(0.0, 1.0 − variance_of_derivatives)
////     where variance is sample variance of the derivative series
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-HA-001, SC-OODA-001

import gleam/float
import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Full differential calculus result over a health time series.
pub type HealthCalculus {
  HealthCalculus(
    /// Most-recent health value from the history (H_n)
    current: Float,
    /// d(H)/dt — rate of change per time-step (positive = improving)
    first_derivative: Float,
    /// d²(H)/dt² — acceleration of change (negative = worsening faster)
    second_derivative: Float,
    /// Qualitative classification derived from the two derivatives
    trend: HealthTrend,
    /// Estimated seconds (time-steps) until threshold breach at current rate.
    /// Returns 2_147_483_647 when the threshold will never be reached.
    time_to_threshold: Int,
    /// Prediction confidence in [0.0, 1.0] — combines history depth and
    /// derivative consistency.  Values < 0.3 = insufficient data.
    confidence: Float,
  )
}

/// Qualitative trend classification.
/// Derived purely from first and second derivatives.
pub type HealthTrend {
  /// d(H)/dt > 0.01 — health is improving at a meaningful rate
  Improving
  /// |d(H)/dt| <= 0.01 — health is essentially flat
  Stable
  /// d(H)/dt < -0.01 — health is declining
  Declining
  /// d(H)/dt < 0 AND d²(H)/dt² < 0 — declining AND accelerating downward
  AcceleratingDecline
  /// d(H)/dt > 0 AND second_derivative > 0 is NOT required;
  /// classified when dH_dt > 0.01 and the previous classification was Declining.
  /// For stateless single-call use: dH_dt > 0.01 AND d2H_dt2 > 0.0 signals recovery.
  Recovering
}

// ---------------------------------------------------------------------------
// Threshold constant
// ---------------------------------------------------------------------------

/// Default safety threshold below which a health breach is declared.
/// Operators may override by calling time_to_threshold/3 directly.
const default_threshold: Float = 0.5

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Compute full health calculus from a history list (most-recent first).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Health history ring-buffer ↪ HealthCalculus</morphism>
///   <formal-proof>
///     <P> Pre: history is a list of Float values in [0.0, 1.0], most-recent first.
///         May be empty or contain a single element. </P>
///     <C> compute(history) </C>
///     <Q> Post: Returns HealthCalculus with all fields populated.
///         Empty/singleton history yields zero derivatives and confidence 0.0.
///         Derivatives computed via finite differences; trend classified from them.
///         time_to_threshold uses default_threshold = 0.5. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn compute(history: List(Float)) -> HealthCalculus {
  let current = head_or(history, 1.0)
  let dh_dt = first_derivative(history)
  let d2h_dt2 = second_derivative(history)
  let trend = classify_trend(dh_dt, d2h_dt2)
  let ttt = time_to_threshold(current, dh_dt, default_threshold)
  let conf = prediction_confidence(history)

  HealthCalculus(
    current: current,
    first_derivative: dh_dt,
    second_derivative: d2h_dt2,
    trend: trend,
    time_to_threshold: ttt,
    confidence: conf,
  )
}

/// First derivative: d(H)/dt using finite differences.
///
/// Algorithm:
///   n = 0  → 0.0  (no data)
///   n = 1  → 0.0  (no change detectable)
///   n = 2  → (H[0] − H[1]) / 1.0  (forward/backward, Δt=1)
///   n >= 3 → central difference at index 1: (H[0] − H[2]) / 2.0
///
/// History is most-recent first: index 0 = H_n, index 1 = H_{n-1}, ...
pub fn first_derivative(history: List(Float)) -> Float {
  case history {
    [] -> 0.0
    [_] -> 0.0
    [h0, h1] -> h0 -. h1
    [h0, _, h2, ..] -> { h0 -. h2 } /. 2.0
  }
}

/// Second derivative: d²(H)/dt² using second-order central difference.
///
/// Algorithm:
///   n < 3  → 0.0  (insufficient data for second derivative)
///   n >= 3 → H[0] − 2·H[1] + H[2]   (second central difference, Δt=1)
pub fn second_derivative(history: List(Float)) -> Float {
  case history {
    [] -> 0.0
    [_] -> 0.0
    [_, _] -> 0.0
    [h0, h1, h2, ..] -> h0 -. { 2.0 *. h1 } +. h2
  }
}

/// Classify the health trend from first and second derivatives.
///
/// Classification rules (applied in priority order):
///   1. AcceleratingDecline: dH_dt < 0.0 AND d2H_dt2 < 0.0
///   2. Recovering:          dH_dt > 0.01 AND d2H_dt2 > 0.0
///   3. Improving:           dH_dt > 0.01
///   4. Declining:           dH_dt < -0.01
///   5. Stable:              |dH_dt| <= 0.01
pub fn classify_trend(dh_dt: Float, d2h_dt2: Float) -> HealthTrend {
  case dh_dt <. 0.0 && d2h_dt2 <. 0.0 {
    True -> AcceleratingDecline
    False ->
      case dh_dt >. 0.01 && d2h_dt2 >. 0.0 {
        True -> Recovering
        False ->
          case dh_dt >. 0.01 {
            True -> Improving
            False ->
              case dh_dt <. -0.01 {
                True -> Declining
                False -> Stable
              }
          }
      }
  }
}

/// Estimate time-steps until health reaches `threshold` at current `rate`.
///
/// Linear extrapolation: t = (threshold − current) / |rate|
///
/// Edge cases:
///   rate ≈ 0.0 (abs < 1e-9) → 2_147_483_647 (max int, "never")
///   already below threshold → 0
///   threshold above current and rate > 0 → positive estimate (improving toward threshold)
///   threshold below current and rate < 0 → positive estimate (declining toward threshold)
pub fn time_to_threshold(current: Float, rate: Float, threshold: Float) -> Int {
  let abs_rate = float.absolute_value(rate)
  case abs_rate <. 1.0e-9 {
    True -> 2_147_483_647
    False -> {
      let delta = threshold -. current
      let raw = delta /. rate
      case raw <. 0.0 {
        // Moving away from threshold (or already past it in safe direction)
        True -> 2_147_483_647
        False -> float.round(raw)
      }
    }
  }
}

/// Compute prediction confidence in [0.0, 1.0].
///
/// confidence = min(length_factor, consistency_factor)
///
///   length_factor     = min(n / 10.0, 1.0)
///     Saturates at 1.0 with 10 or more history points.
///
///   consistency_factor = max(0.0, 1.0 − sample_variance_of_derivatives)
///     Computed over the per-step first-differences of history.
///     High variance in derivatives → low consistency → low confidence.
///     Returns 0.0 when fewer than 2 history points exist.
pub fn prediction_confidence(history: List(Float)) -> Float {
  let n = list.length(history)
  let length_factor = float.min(int.to_float(n) /. 10.0, 1.0)
  let consistency = derivative_consistency(history)
  float.min(length_factor, consistency)
}

/// Serialise a HealthCalculus to a compact JSON string.
pub fn to_json(calc: HealthCalculus) -> String {
  "{"
  <> "\"current\":"
  <> float.to_string(calc.current)
  <> ","
  <> "\"first_derivative\":"
  <> float.to_string(calc.first_derivative)
  <> ","
  <> "\"second_derivative\":"
  <> float.to_string(calc.second_derivative)
  <> ","
  <> "\"trend\":\""
  <> trend_to_string(calc.trend)
  <> "\","
  <> "\"time_to_threshold\":"
  <> int.to_string(calc.time_to_threshold)
  <> ","
  <> "\"confidence\":"
  <> float.to_string(calc.confidence)
  <> "}"
}

/// Human-readable one-line summary of a HealthCalculus.
///
/// Example:
///   HEALTH-CALCULUS (H=0.72, dH/dt=-0.05, d²H/dt²=-0.01, trend:AcceleratingDecline,
///                    tti:4s, conf:0.80)
pub fn summary(calc: HealthCalculus) -> String {
  "HEALTH-CALCULUS"
  <> " (H="
  <> float.to_string(calc.current)
  <> ", dH/dt="
  <> float.to_string(calc.first_derivative)
  <> ", d²H/dt²="
  <> float.to_string(calc.second_derivative)
  <> ", trend:"
  <> trend_to_string(calc.trend)
  <> ", tti:"
  <> case calc.time_to_threshold == 2_147_483_647 {
    True -> "never"
    False -> int.to_string(calc.time_to_threshold) <> "s"
  }
  <> ", conf:"
  <> float.to_string(calc.confidence)
  <> ")"
}

/// Convert a HealthTrend to its string label.
pub fn trend_to_string(trend: HealthTrend) -> String {
  case trend {
    Improving -> "Improving"
    Stable -> "Stable"
    Declining -> "Declining"
    AcceleratingDecline -> "AcceleratingDecline"
    Recovering -> "Recovering"
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Compute derivative consistency as 1 − sample_variance(per_step_diffs).
///
/// Per-step differences are H[i] − H[i+1] for consecutive pairs (most-recent first).
/// Sample variance = sum((d − mean)²) / (m − 1)  for m >= 2.
/// Returns 1.0 for fewer than 2 history points (no variance to measure).
fn derivative_consistency(history: List(Float)) -> Float {
  let diffs = consecutive_diffs(history)
  let m = list.length(diffs)
  case m < 2 {
    True -> 1.0
    False -> {
      let mean_d = mean_of(diffs)
      let variance = sample_variance(diffs, mean_d)
      float.max(0.0, 1.0 -. variance)
    }
  }
}

/// Compute consecutive differences H[i] − H[i+1] for the history list.
/// Returns a list of length (n − 1).
fn consecutive_diffs(history: List(Float)) -> List(Float) {
  do_consecutive_diffs(history, [])
}

fn do_consecutive_diffs(items: List(Float), acc: List(Float)) -> List(Float) {
  case items {
    [] -> list.reverse(acc)
    [_] -> list.reverse(acc)
    [h0, h1, ..rest] -> do_consecutive_diffs([h1, ..rest], [h0 -. h1, ..acc])
  }
}

/// Arithmetic mean of a Float list. Returns 0.0 for empty list.
fn mean_of(values: List(Float)) -> Float {
  let n = list.length(values)
  case n == 0 {
    True -> 0.0
    False -> float.sum(values) /. int.to_float(n)
  }
}

/// Sample variance: sum((x − mean)²) / (n − 1).
/// Returns 0.0 for fewer than 2 elements.
fn sample_variance(values: List(Float), mean: Float) -> Float {
  let n = list.length(values)
  case n < 2 {
    True -> 0.0
    False -> {
      let sq_sum =
        list.fold(values, 0.0, fn(acc, v) {
          let diff = v -. mean
          acc +. diff *. diff
        })
      sq_sum /. int.to_float(n - 1)
    }
  }
}

/// Return the head of a list or a default value.
fn head_or(items: List(Float), default: Float) -> Float {
  case items {
    [] -> default
    [h, ..] -> h
  }
}

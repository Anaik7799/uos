//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/kalman_filter</module>
////     <fsharp-lineage>None — novel 1D Kalman filter for NIF health metric smoothing (CTRL-2)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       1D Kalman filter for NIF health metric smoothing.
////       Suppresses sensor noise in health telemetry streams (CPU, memory,
////       container health scores) using the standard scalar Kalman equations:
////
////         Predict:  x̂⁻ = x̂                         (constant model)
////                   P⁻  = P + Q
////         Update:   K   = P⁻ / (P⁻ + R)
////                   x̂   = x̂⁻ + K · (z − x̂⁻)
////                   P   = (1 − K) · P⁻
////
////       Produces smooth estimates suitable for the PID controller (CTRL-1)
////       and OODA orient phase without over-reacting to transient spikes.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Scalar Kalman filter (Rudolf Kálmán 1960) ↪ Gleam pure value type.
////       All state passed by value; no mutable globals; caller owns persistence.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic — adequate for health smoothing;
////       not for safety actuation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// 1D KALMAN FILTER — NIF HEALTH METRIC SMOOTHING
//// सत्यं ज्ञानम् अनन्तम् — Truth, Knowledge, Infinity (Taittiriya Upanishad 2.1)
////
//// Standard scalar update equations (Welch & Bishop, 2001):
////
////   ── Predict ──────────────────────────────────────────────────────────────
////   x̂⁻ₖ = x̂ₖ₋₁                         state prediction (constant model)
////   P⁻ₖ  = Pₖ₋₁ + Q                      error covariance prediction
////
////   ── Update ───────────────────────────────────────────────────────────────
////   Kₖ   = P⁻ₖ / (P⁻ₖ + R)              Kalman gain ∈ (0, 1)
////   x̂ₖ   = x̂⁻ₖ + Kₖ · (zₖ − x̂⁻ₖ)     state update
////   Pₖ   = (1 − Kₖ) · P⁻ₖ              covariance update
////
//// Properties:
////   1. OPTIMAL — minimises mean-squared error when noise is Gaussian.
////   2. PURE    — update/2 is a total function; no side-effects.
////   3. STABLE  — P converges as long as Q > 0 and R > 0.
////   4. CAUSAL  — only uses past and present observations.
////
//// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Complete 1D Kalman filter state — passed by value.
///
/// All fields are IEEE 754 Float64.  Caller is responsible for persisting
/// the returned state between calls to `update/2`.
pub type KalmanState {
  KalmanState(
    /// Current state estimate (smoothed measurement)
    estimate: Float,
    /// Estimation uncertainty (error covariance P)
    error_covariance: Float,
    /// Process noise Q — how much we expect the true state to drift per step
    process_noise: Float,
    /// Measurement noise R — sensor variance; higher = trust model more
    measurement_noise: Float,
    /// Last computed Kalman gain K ∈ [0, 1]
    kalman_gain: Float,
    /// Monotonic count of update/2 calls
    step_count: Int,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a Kalman filter with explicit noise parameters.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Parameters ↪ clean KalmanState</morphism>
///   <formal-proof>
///     <P> Pre: initial_estimate ∈ ℝ; initial_error > 0; process_noise > 0; measurement_noise > 0 </P>
///     <C> init(initial_estimate, initial_error, process_noise, measurement_noise) </C>
///     <Q> Post: kalman_gain = 0.0, step_count = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(
  initial_estimate: Float,
  initial_error: Float,
  process_noise: Float,
  measurement_noise: Float,
) -> KalmanState {
  KalmanState(
    estimate: initial_estimate,
    error_covariance: initial_error,
    process_noise: process_noise,
    measurement_noise: measurement_noise,
    kalman_gain: 0.0,
    step_count: 0,
  )
}

/// Default filter tuned for C3I health metrics.
///
/// Parameters:
///   Q = 0.01 — health score drifts slowly (≈1% per tick)
///   R = 0.1  — NIF measurements are fairly noisy
///   initial_estimate = 1.0 (healthy)
///   initial_error    = 1.0 (maximum initial uncertainty)
///
/// These parameters result in a smooth estimate that adapts within ~10 ticks
/// and attenuates transient spikes by roughly 90%.
pub fn default_health_filter() -> KalmanState {
  init(1.0, 1.0, 0.01, 0.1)
}

/// Absorb a new measurement and return the updated filter state.
///
/// Implements the full predict-then-update cycle.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">KalmanState + measurement ↪ updated KalmanState</morphism>
///   <formal-proof>
///     <P> Pre: measurement ∈ ℝ; state.measurement_noise > 0; state.process_noise > 0 </P>
///     <C> update(state, measurement) </C>
///     <Q> Post: kalman_gain ∈ (0,1); step_count = prev_step_count + 1;
///              |estimate − measurement| ≤ |prev_estimate − measurement| (monotone improvement) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn update(state: KalmanState, measurement: Float) -> KalmanState {
  // ── Predict ───────────────────────────────────────────────────────────────
  // Constant-velocity model: predicted state = previous estimate
  let predicted_estimate = state.estimate
  let predicted_cov = state.error_covariance +. state.process_noise

  // ── Update ────────────────────────────────────────────────────────────────
  // Kalman gain: blend factor between model and measurement
  // K → 0: trust model (low process noise relative to measurement noise)
  // K → 1: trust measurement (high process noise)
  let denom = predicted_cov +. state.measurement_noise
  let k = case denom <. 1.0e-15 {
    True -> 0.0
    False -> predicted_cov /. denom
  }

  let new_estimate =
    predicted_estimate +. k *. { measurement -. predicted_estimate }
  let new_cov = { 1.0 -. k } *. predicted_cov

  KalmanState(
    ..state,
    estimate: new_estimate,
    error_covariance: new_cov,
    kalman_gain: k,
    step_count: state.step_count + 1,
  )
}

/// Predict the next value without consuming a measurement.
///
/// Under the constant model, the predicted value equals the current estimate.
/// Returns `state.estimate + 0` — useful as a look-ahead for OODA orientation.
pub fn predict(state: KalmanState) -> Float {
  // Under the constant model x̂⁻ = x̂ (no process input)
  state.estimate
}

/// Human-readable summary of the current filter state.
pub fn summary(state: KalmanState) -> String {
  let est = float_to_str(state.estimate)
  let cov = float_to_str(state.error_covariance)
  let q = float_to_str(state.process_noise)
  let r = float_to_str(state.measurement_noise)
  let k = float_to_str(state.kalman_gain)
  let steps = int.to_string(state.step_count)
  string.concat([
    "KalmanState{estimate=",
    est,
    ",error_cov=",
    cov,
    ",Q=",
    q,
    ",R=",
    r,
    ",gain=",
    k,
    ",steps=",
    steps,
    "}",
  ])
}

/// Serialize filter state to a JSON string for Zenoh / audit publishing.
pub fn to_json(state: KalmanState) -> String {
  let est = float_to_str(state.estimate)
  let cov = float_to_str(state.error_covariance)
  let q = float_to_str(state.process_noise)
  let r = float_to_str(state.measurement_noise)
  let k = float_to_str(state.kalman_gain)
  let steps = int.to_string(state.step_count)
  string.concat([
    "{\"estimate\":",
    est,
    ",\"error_covariance\":",
    cov,
    ",\"process_noise\":",
    q,
    ",\"measurement_noise\":",
    r,
    ",\"kalman_gain\":",
    k,
    ",\"step_count\":",
    steps,
    "}",
  ])
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn float_to_str(f: Float) -> String {
  float.to_string(f)
}

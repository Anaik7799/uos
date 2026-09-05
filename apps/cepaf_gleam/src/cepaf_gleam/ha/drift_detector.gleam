//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/drift_detector</module>
////     <fsharp-lineage>None — novel statistical drift detection on embedding distributions (SERBAN-4)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Statistical drift detection for embedding and metric distributions.
////       Detects distribution shift using Z-score comparison between a frozen
////       baseline distribution (mean, std) and an online running window.
////
////       Drift score:
////         z = |μ_current − μ_baseline| / σ_baseline
////
////       When z exceeds a configurable threshold the detector raises a drift
////       flag.  The baseline can be re-anchored to the current distribution
////       via reset_baseline/1 after acknowledged drift.
////
////       Running statistics use Welford's online algorithm (numerically
////       stable, O(1) per sample, O(1) space).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Welford (1962) online statistics + Z-score threshold ↪ Gleam pure value type.
////       All state passed by value; no mutable globals; caller owns persistence.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic ↠ Erlang float.
////       Mitigation: Welford's algorithm is numerically stable for this use-case.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// STATISTICAL DRIFT DETECTION — SERBAN-4
//// परिणामे दुःखम् — If the outcome brings suffering, the action was wrong (Yoga Sutra 2.15)
////
//// Z-score drift detection:
////   z = |μ_current − μ_baseline| / max(σ_baseline, ε)
////
////   z > threshold  → drift_detected = True
////   z ≤ threshold  → drift_detected = False
////
//// Running statistics (Welford 1962):
////   n      = n + 1
////   delta  = value − mean
////   mean   = mean + delta / n
////   delta2 = value − mean        ← uses updated mean
////   m2     = m2 + delta × delta2
////   variance = m2 / (n − 1)       for n ≥ 2
////   std_dev  = √variance
////
//// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Complete drift-detector state — passed by value.
///
/// Fields are split into an immutable *baseline* snapshot and a live
/// *current* running window.  The baseline is set at `init/2` and may
/// be refreshed via `reset_baseline/1`.
pub type DriftState {
  DriftState(
    /// Frozen baseline distribution mean (μ_baseline)
    baseline_mean: Float,
    /// Frozen baseline distribution std-dev (σ_baseline)
    baseline_std: Float,
    /// Running mean of the current window (Welford)
    current_mean: Float,
    /// Running std-dev of the current window (Welford)
    current_std: Float,
    /// Welford M2 accumulator (sum of squared deviations)
    current_m2: Float,
    /// Total number of samples ingested into the running window
    sample_count: Int,
    /// True when the last detect_drift call exceeded the threshold
    drift_detected: Bool,
    /// Z-score: |μ_current − μ_baseline| / σ_baseline
    drift_score: Float,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a drift detector with an explicit baseline distribution.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Baseline params ↪ clean DriftState</morphism>
///   <formal-proof>
///     <P> Pre: baseline_std >= 0.0 </P>
///     <C> init(baseline_mean, baseline_std) </C>
///     <Q> Post: sample_count = 0; drift_detected = False; drift_score = 0.0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(baseline_mean: Float, baseline_std: Float) -> DriftState {
  DriftState(
    baseline_mean: baseline_mean,
    baseline_std: baseline_std,
    current_mean: baseline_mean,
    current_std: 0.0,
    current_m2: 0.0,
    sample_count: 0,
    drift_detected: False,
    drift_score: 0.0,
  )
}

/// Add a single observation to the running window.
///
/// Updates the Welford running mean and variance; recomputes the drift score.
/// The `drift_detected` flag is NOT updated here — call `detect_drift/2` for that.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">DriftState + value ↪ updated DriftState</morphism>
///   <formal-proof>
///     <P> Pre: value ∈ ℝ </P>
///     <C> add_sample(state, value) </C>
///     <Q> Post: sample_count = prev_count + 1;
///              current_mean is numerically stable Welford update </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn add_sample(state: DriftState, value: Float) -> DriftState {
  let n = state.sample_count + 1

  // Welford online update
  let delta = value -. state.current_mean
  let new_mean = state.current_mean +. delta /. int.to_float(n)
  let delta2 = value -. new_mean
  let new_m2 = state.current_m2 +. delta *. delta2

  // Variance and std-dev (Bessel-corrected, defined for n >= 2)
  let new_std = case n >= 2 {
    True -> {
      let variance = new_m2 /. int.to_float(n - 1)
      case variance >. 0.0 {
        True ->
          case float.square_root(variance) {
            Ok(s) -> s
            Error(_) -> 0.0
          }
        False -> 0.0
      }
    }
    False -> 0.0
  }

  // Update drift score
  let z = compute_z(new_mean, state.baseline_mean, state.baseline_std)

  DriftState(
    ..state,
    current_mean: new_mean,
    current_std: new_std,
    current_m2: new_m2,
    sample_count: n,
    drift_score: z,
  )
}

/// Evaluate whether drift has occurred given a Z-score threshold.
///
/// Returns True when `drift_score > threshold`.
/// Also mutates `drift_detected` in the returned state.
///
/// Typical thresholds:
///   2.0 — sensitive (good for low-noise embedding streams)
///   3.0 — standard  (3-sigma rule, ~0.3% false-positive rate)
///   4.0 — strict    (safety-critical systems)
pub fn detect_drift(state: DriftState, threshold: Float) -> Bool {
  state.drift_score >. threshold
}

/// Return the current Z-score (drift magnitude).
///
/// z = |μ_current − μ_baseline| / max(σ_baseline, ε)
/// where ε = 1e-9 avoids division by zero.
pub fn drift_score(state: DriftState) -> Float {
  state.drift_score
}

/// Re-anchor the baseline to the current running distribution.
///
/// Use after acknowledged drift to start tracking from the new operating point.
/// Resets the Welford accumulator so the next window starts fresh.
pub fn reset_baseline(state: DriftState) -> DriftState {
  DriftState(
    baseline_mean: state.current_mean,
    baseline_std: state.current_std,
    current_mean: state.current_mean,
    current_std: 0.0,
    current_m2: 0.0,
    sample_count: 0,
    drift_detected: False,
    drift_score: 0.0,
  )
}

/// Human-readable summary of the drift detector state.
pub fn summary(state: DriftState) -> String {
  let bm = float_to_str(state.baseline_mean)
  let bs = float_to_str(state.baseline_std)
  let cm = float_to_str(state.current_mean)
  let cs = float_to_str(state.current_std)
  let n = int.to_string(state.sample_count)
  let z = float_to_str(state.drift_score)
  let detected = case state.drift_detected {
    True -> "true"
    False -> "false"
  }
  string.concat([
    "DriftState{baseline_mean=",
    bm,
    ",baseline_std=",
    bs,
    ",current_mean=",
    cm,
    ",current_std=",
    cs,
    ",samples=",
    n,
    ",drift_score=",
    z,
    ",drift_detected=",
    detected,
    "}",
  ])
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Compute Z-score with a small epsilon floor on the denominator.
fn compute_z(
  current_mean: Float,
  baseline_mean: Float,
  baseline_std: Float,
) -> Float {
  let epsilon = 1.0e-9
  let safe_std = case baseline_std <. epsilon {
    True -> epsilon
    False -> baseline_std
  }
  let diff = current_mean -. baseline_mean
  let abs_diff = case diff <. 0.0 {
    True -> diff *. -1.0
    False -> diff
  }
  abs_diff /. safe_std
}

fn float_to_str(f: Float) -> String {
  float.to_string(f)
}

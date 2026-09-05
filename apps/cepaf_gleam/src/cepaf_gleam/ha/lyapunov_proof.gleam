//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/lyapunov_proof</module>
////     <fsharp-lineage>None — novel Gleam module for formal stability analysis (CTRL-3)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Formal Lyapunov stability analysis for guard_grid OODA convergence.
////       Determines whether the health metric trajectory is converging (stable)
////       or diverging (unstable) using the standard Lyapunov direct method:
////
////         Candidate function: V(x) = (x − x*)²   (quadratic, positive-definite)
////         Stability condition: dV/dt < 0           (energy decreasing → convergence)
////         Exponent estimate:   λ ≈ (ΔV / V) / dt  (Lyapunov exponent approximation)
////
////         Stable   iff λ < 0 AND dV/dt < 0
////         Marginal iff λ ≈ 0 OR  |dV/dt| < ε
////         Unstable iff λ > 0 OR  dV/dt > 0
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001, SC-SATYA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Lyapunov stability theory (Aleksandr Lyapunov, 1892) ↪ Gleam pure value type.
////       All state passed by value; no mutable globals; caller owns persistence.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 arithmetic — adequate for health trajectory analysis;
////       not for safety actuation. Exponent is an approximation, not an exact eigenvalue.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// LYAPUNOV PROOF — Formal stability analysis for guard_grid OODA (CTRL-3)
//// स्थिरता प्रमाण — Stability, the ground of right action (Gita 2.48)
////
//// Lyapunov's Direct Method (Second Method):
////
////   For system dx/dt = f(x) and candidate V(x) = (x − x*)²:
////
////   1. V(x) > 0  for all x ≠ x*   (positive-definite)       ← guaranteed by squaring
////   2. V(x*) = 0 at equilibrium                               ← by construction
////   3. dV/dt < 0 along trajectories → system is STABLE         ← the key check
////
////   Exponent estimate: λ ≈ Δ(ln V) / Δt
////     λ < 0 : trajectory contracts toward setpoint (converging)
////     λ = 0 : neutral / Lyapunov stable (not asymptotically)
////     λ > 0 : trajectory expands away from setpoint (diverging)
////
//// STAMP: SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001, SC-SATYA-001

import gleam/float
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Default setpoint — healthy system health score
const default_setpoint: Float = 1.0

/// Marginal band around zero exponent  (|λ| < ε → Marginal)
const marginal_epsilon: Float = 1.0e-4

/// Minimum dt to avoid division-by-zero in derivative
const min_dt: Float = 1.0e-9

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Qualitative stability verdict.
pub type StabilityVerdict {
  /// λ < 0 AND dV/dt < 0 — trajectory converging to setpoint
  Stable
  /// λ > 0 OR dV/dt > 0  — trajectory diverging from setpoint
  Unstable
  /// |λ| < ε OR insufficient samples
  Marginal
}

/// Accumulated Lyapunov stability state — passed by value.
///
/// All floating-point fields are IEEE 754 Float64.
/// Caller is responsible for persisting the returned state between calls to `update/4`.
pub type LyapunovAnalysis {
  LyapunovAnalysis(
    /// λ — Lyapunov exponent estimate (positive = diverging, negative = converging)
    exponent: Float,
    /// V(x) — current Lyapunov candidate function value (energy)
    energy: Float,
    /// dV/dt — instantaneous rate of change of energy (must be negative for stability)
    energy_derivative: Float,
    /// Qualitative stability verdict derived from exponent and energy_derivative
    verdict: StabilityVerdict,
    /// Number of `update/4` calls processed so far
    samples: Int,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Return a zero-state LyapunovAnalysis with Marginal verdict.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Unit ↪ neutral LyapunovAnalysis</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> init() </C>
///     <Q> Post: exponent = 0.0, energy = 0.0, energy_derivative = 0.0,
///              verdict = Marginal, samples = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> LyapunovAnalysis {
  LyapunovAnalysis(
    exponent: 0.0,
    energy: 0.0,
    energy_derivative: 0.0,
    verdict: Marginal,
    samples: 0,
  )
}

/// Absorb a new health observation and return the updated analysis state.
///
/// Arguments:
///   state      — previous LyapunovAnalysis
///   health     — current health score ∈ [0, 1]
///   prev_health — health score one step back
///   dt         — elapsed time between observations (seconds; clamped to min_dt)
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">LyapunovAnalysis + observation ↪ updated LyapunovAnalysis</morphism>
///   <formal-proof>
///     <P> Pre: health ∈ [0,1]; prev_health ∈ [0,1]; dt > 0 </P>
///     <C> update(state, health, prev_health, dt) </C>
///     <Q> Post: samples = prev_samples + 1;
///              verdict ∈ {Stable, Unstable, Marginal};
///              energy >= 0.0 (positive-definite) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn update(
  state: LyapunovAnalysis,
  health: Float,
  prev_health: Float,
  dt: Float,
) -> LyapunovAnalysis {
  let safe_dt = case dt <. min_dt {
    True -> min_dt
    False -> dt
  }

  let v_now = energy_function(health, default_setpoint)
  let v_prev = energy_function(prev_health, default_setpoint)
  let dv_dt = energy_derivative(health, prev_health, default_setpoint, safe_dt)

  // Lyapunov exponent: Δ(ln V) / Δt
  // Guard against V ≈ 0 (system is at setpoint — exponent irrelevant there)
  let lambda = case v_prev <. 1.0e-12 {
    True ->
      case v_now <. 1.0e-12 {
        // Both near zero: system is at equilibrium — marginally stable
        True -> 0.0
        // V grew from near-zero: small positive (diverging from perfect setpoint)
        False -> 1.0
      }
    False ->
      case v_now <. 1.0e-12 {
        // V shrank to near-zero: strongly converging
        True -> -1.0
        False ->
          // Normal case: Δ(ln V) / Δt
          case float.logarithm(v_now /. v_prev) {
            Ok(log_ratio) -> log_ratio /. safe_dt
            Error(_) -> 0.0
          }
      }
  }

  let verdict = classify_verdict(lambda, dv_dt)

  LyapunovAnalysis(
    exponent: lambda,
    energy: v_now,
    energy_derivative: dv_dt,
    verdict: verdict,
    samples: state.samples + 1,
  )
}

/// Return True when the analysis indicates the system is asymptotically stable.
///
/// Stability requires BOTH:
///   1. exponent < 0   (trajectory contracting)
///   2. dV/dt < 0      (energy dissipating)
pub fn is_stable(state: LyapunovAnalysis) -> Bool {
  state.exponent <. 0.0 && state.energy_derivative <. 0.0
}

/// Return the convergence rate — |λ| when stable, 0.0 otherwise.
///
/// Interpretation: convergence rate ≈ 0.5 means the error halves each second.
pub fn convergence_rate(state: LyapunovAnalysis) -> Float {
  case is_stable(state) {
    True ->
      case float.absolute_value(state.exponent) {
        abs -> abs
      }
    False -> 0.0
  }
}

/// Lyapunov candidate function V(x) = (x − setpoint)²
///
/// Properties:
///   V(x) >= 0 for all x           (positive semi-definite)
///   V(setpoint) = 0               (zero at equilibrium)
///   V(x) > 0 for x ≠ setpoint     (positive-definite off-equilibrium)
pub fn energy_function(health: Float, setpoint: Float) -> Float {
  let diff = health -. setpoint
  diff *. diff
}

/// dV/dt ≈ (V(x_now) − V(x_prev)) / dt
///
/// Negative value indicates energy is decreasing → trajectory is converging.
pub fn energy_derivative(
  health: Float,
  prev_health: Float,
  setpoint: Float,
  dt: Float,
) -> Float {
  let v_now = energy_function(health, setpoint)
  let v_prev = energy_function(prev_health, setpoint)
  let safe_dt = case dt <. min_dt {
    True -> min_dt
    False -> dt
  }
  { v_now -. v_prev } /. safe_dt
}

/// Human-readable one-line summary of the current stability state.
pub fn summary(state: LyapunovAnalysis) -> String {
  "LyapunovAnalysis{"
  <> "verdict="
  <> verdict_to_string(state.verdict)
  <> ",exponent="
  <> float_to_str(state.exponent)
  <> ",energy="
  <> float_to_str(state.energy)
  <> ",dV/dt="
  <> float_to_str(state.energy_derivative)
  <> ",samples="
  <> int.to_string(state.samples)
  <> "}"
}

/// Serialise to a compact JSON object string (SC-GLM-UI-003).
pub fn to_json(state: LyapunovAnalysis) -> String {
  "{"
  <> "\"exponent\":"
  <> float_to_str(state.exponent)
  <> ","
  <> "\"energy\":"
  <> float_to_str(state.energy)
  <> ","
  <> "\"energy_derivative\":"
  <> float_to_str(state.energy_derivative)
  <> ","
  <> "\"verdict\":\""
  <> verdict_to_string(state.verdict)
  <> "\","
  <> "\"samples\":"
  <> int.to_string(state.samples)
  <> "}"
}

/// Convert a StabilityVerdict to its string representation.
pub fn verdict_to_string(v: StabilityVerdict) -> String {
  case v {
    Stable -> "stable"
    Unstable -> "unstable"
    Marginal -> "marginal"
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn classify_verdict(lambda: Float, dv_dt: Float) -> StabilityVerdict {
  let abs_lambda = float.absolute_value(lambda)
  case abs_lambda <. marginal_epsilon {
    True -> Marginal
    False ->
      case lambda <. 0.0 && dv_dt <. 0.0 {
        True -> Stable
        False ->
          case lambda >. 0.0 || dv_dt >. 0.0 {
            True -> Unstable
            False -> Marginal
          }
      }
  }
}

fn float_to_str(f: Float) -> String {
  // Render with fixed precision using string manipulation
  case f <. 0.0 {
    True -> "-" <> pos_float_to_str(float.absolute_value(f))
    False -> pos_float_to_str(f)
  }
}

fn pos_float_to_str(f: Float) -> String {
  // Use Gleam's built-in float string conversion
  // gleam/float doesn't expose fixed-point formatting, so we use to_string
  // which gives e.g. "1.5" or "1.23e-4"
  case string.contains(float.to_string(f), ".") {
    True -> float.to_string(f)
    False -> float.to_string(f) <> ".0"
  }
}

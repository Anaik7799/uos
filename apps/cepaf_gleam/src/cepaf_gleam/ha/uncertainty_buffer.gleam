//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/uncertainty_buffer</module>
////     <fsharp-lineage>None — novel NIF output confidence wrapper (SERBAN-2)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Wraps NIF scalar outputs in confidence intervals so that the OODA
////       Orient phase can distinguish reliable measurements from noisy ones.
////
////       Two construction paths:
////         1. from_measurement(v, noise)  — symmetric ±noise interval,
////            confidence = 1 − 2·noise / (|v| + 1) clamped to [0, 1].
////         2. from_samples(xs)            — mean ± 2σ (95.45 % coverage),
////            confidence = 1 − CV where CV = σ/|mean| (coefficient of variation).
////
////       Merge strategy (weighted average by confidence):
////         merged_value = (a.value · a.confidence + b.value · b.confidence)
////                        / (a.confidence + b.confidence)
////         merged lower/upper = convex combination of intervals.
////         merged confidence = max(a.confidence, b.confidence).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-MATH-001, SC-OODA-001, SC-MUDA-001, SC-SIL4-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Classical interval arithmetic ↪ Gleam pure value type.
////       All operations are total functions; no division by zero guarded.
////     </morphism>
////     <morphism type="surjective" loss="distributional-shape">
////       Interval [lower, upper] captures extent, not full PDF shape.
////       Mitigation: Kalman filter module provides Gaussian refinement when
////       the full shape matters.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// UNCERTAINTY BUFFER — NIF Output Confidence Interval Wrapper
//// अनिश्चितता स्वीकारः ज्ञानस्य आरम्भः — Accepting uncertainty is the beginning of knowledge
////
//// Ultrathink alignment: Focus #5 (Continuous Formal Verification),
////                        Focus #6 (Embedded SLM Cognitive Kernels).

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Public types
// =============================================================================

/// A scalar value decorated with a symmetric confidence interval and a
/// confidence score in [0, 1].
pub type UncertainValue {
  UncertainValue(
    /// Point estimate (central tendency).
    value: Float,
    /// Lower bound of the interval.
    lower: Float,
    /// Upper bound of the interval.
    upper: Float,
    /// Confidence ∈ [0.0, 1.0]; 1.0 = perfectly certain.
    confidence: Float,
  )
}

// =============================================================================
// Constructors
// =============================================================================

/// Build from a single measurement with a known noise magnitude.
///
/// interval  = [value − noise, value + noise]
/// confidence = clamp(1 − 2·noise / (|value| + 1), 0, 1)
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">measurement + noise ↪ UncertainValue ADT</morphism>
///   <formal-proof>
///     <P>noise >= 0.0</P>
///     <C>from_measurement(value, noise)</C>
///     <Q>lower <= value <= upper, confidence in [0,1]; no panics</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn from_measurement(value: Float, noise: Float) -> UncertainValue {
  let safe_noise = float.absolute_value(noise)
  let denom = float.absolute_value(value) +. 1.0
  let raw_conf = 1.0 -. 2.0 *. safe_noise /. denom
  let confidence = clamp01(raw_conf)
  UncertainValue(
    value: value,
    lower: value -. safe_noise,
    upper: value +. safe_noise,
    confidence: confidence,
  )
}

/// Build from a list of samples using mean ± 2σ (95.45 % coverage).
///
/// If the list is empty or has a single element, confidence = 0.0.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">sample list ↪ UncertainValue ADT</morphism>
///   <formal-proof>
///     <P>samples is a finite list of floats (may be empty)</P>
///     <C>from_samples(samples)</C>
///     <Q>valid UncertainValue; confidence=0 for <=1 element; no panics</Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn from_samples(samples: List(Float)) -> UncertainValue {
  let n = list.length(samples)
  case n {
    0 -> UncertainValue(value: 0.0, lower: 0.0, upper: 0.0, confidence: 0.0)
    1 -> {
      let v = case samples {
        [x, ..] -> x
        [] -> 0.0
      }
      UncertainValue(value: v, lower: v, upper: v, confidence: 0.0)
    }
    _ -> {
      let sum = list.fold(samples, 0.0, fn(acc, x) { acc +. x })
      let mean = sum /. int.to_float(n)
      let variance =
        list.fold(samples, 0.0, fn(acc, x) {
          let diff = x -. mean
          acc +. diff *. diff
        })
        /. int.to_float(n)
      let sigma = sqrt_approx(variance)
      let two_sigma = 2.0 *. sigma
      let cv = case float.absolute_value(mean) <. 1.0e-12 {
        True -> 1.0
        False -> sigma /. float.absolute_value(mean)
      }
      let confidence = clamp01(1.0 -. cv)
      UncertainValue(
        value: mean,
        lower: mean -. two_sigma,
        upper: mean +. two_sigma,
        confidence: confidence,
      )
    }
  }
}

// =============================================================================
// Queries
// =============================================================================

/// True iff the value's confidence exceeds the supplied threshold.
pub fn is_reliable(uv: UncertainValue, threshold: Float) -> Bool {
  uv.confidence >. threshold
}

// =============================================================================
// Algebra
// =============================================================================

/// Merge two uncertain values via a confidence-weighted average.
///
/// merged.value     = weighted mean by confidence
/// merged.lower     = confidence-weighted lower bound
/// merged.upper     = confidence-weighted upper bound
/// merged.confidence = max(a.confidence, b.confidence)
pub fn merge(a: UncertainValue, b: UncertainValue) -> UncertainValue {
  let total_conf = a.confidence +. b.confidence
  case total_conf <. 1.0e-12 {
    True ->
      UncertainValue(
        value: { a.value +. b.value } /. 2.0,
        lower: float.min(a.lower, b.lower),
        upper: float.max(a.upper, b.upper),
        confidence: 0.0,
      )
    False -> {
      let wa = a.confidence /. total_conf
      let wb = b.confidence /. total_conf
      UncertainValue(
        value: wa *. a.value +. wb *. b.value,
        lower: wa *. a.lower +. wb *. b.lower,
        upper: wa *. a.upper +. wb *. b.upper,
        confidence: float.max(a.confidence, b.confidence),
      )
    }
  }
}

// =============================================================================
// Rendering helpers
// =============================================================================

/// One-line human-readable summary.
pub fn summary(uv: UncertainValue) -> String {
  float2(uv.value)
  <> " ["
  <> float2(uv.lower)
  <> ", "
  <> float2(uv.upper)
  <> "] conf="
  <> float2(uv.confidence)
}

/// Minimal JSON object.
pub fn to_json(uv: UncertainValue) -> String {
  "{"
  <> "\"value\":"
  <> float.to_string(uv.value)
  <> ","
  <> "\"lower\":"
  <> float.to_string(uv.lower)
  <> ","
  <> "\"upper\":"
  <> float.to_string(uv.upper)
  <> ","
  <> "\"confidence\":"
  <> float.to_string(uv.confidence)
  <> "}"
}

// =============================================================================
// Internal helpers
// =============================================================================

fn clamp01(x: Float) -> Float {
  case x <. 0.0 {
    True -> 0.0
    False ->
      case x >. 1.0 {
        True -> 1.0
        False -> x
      }
  }
}

/// Newton-Raphson square root approximation (converges in ~16 iterations for
/// typical health metric magnitudes).
fn sqrt_approx(x: Float) -> Float {
  case x <. 0.0 {
    True -> 0.0
    False ->
      case x <. 1.0e-14 {
        True -> 0.0
        False -> sqrt_nr(x, x /. 2.0, 0)
      }
  }
}

fn sqrt_nr(x: Float, guess: Float, iter: Int) -> Float {
  case iter >= 50 {
    True -> guess
    False -> {
      let next = { guess +. x /. guess } /. 2.0
      let diff = float.absolute_value(next -. guess)
      case diff <. 1.0e-10 {
        True -> next
        False -> sqrt_nr(x, next, iter + 1)
      }
    }
  }
}

fn float2(f: Float) -> String {
  // Round to 2 decimal places for human-readable output.
  let shifted = float.round(f *. 100.0)
  let int_part = shifted / 100
  let frac_part =
    float.absolute_value(int.to_float(shifted) -. int.to_float(int_part * 100))
  int.to_string(int_part)
  <> "."
  <> string.pad_end(int.to_string(float.round(frac_part)), 2, "0")
}

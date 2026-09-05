//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/failure_classifier</module>
////     <fsharp-lineage>None — novel statistical failure-pattern classification (F21)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Classifies failure event streams as Poisson (random, independent),
////       Bursty (correlated, clustered), Periodic (regular-interval), or Unknown
////       (insufficient data). Uses the coefficient of variation (CV = σ/μ) of
////       inter-arrival times as the primary discriminant statistic.
////       CV ≈ 1.0 ⟹ Poisson, CV >> 1.0 ⟹ Bursty, CV << 1.0 ⟹ Periodic.
////       All state passed by value — zero side-effects, pure functional.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-002, SC-HA-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Cox (1962) renewal-process theory ↪ Gleam pure functions.
////       CV of inter-arrival times is a classical identifier for renewal processes:
////       Exponential (Poisson) ↔ CV = 1, Hyper-exponential (Bursty) ↔ CV > 1,
////       Erlang/Deterministic (Periodic) ↔ CV < 1.
////     </morphism>
////     <morphism type="surjective" loss="floating-point-precision">
////       IEEE 754 Float64 ↠ Erlang float arithmetic.
////       Mitigation: Results used for classification and operator alerting,
////       not safety actuation. Sub-percent precision is sufficient.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// FAILURE PATTERN CLASSIFIER — POISSON VS BURST DISTRIBUTION
//// प्रतिक्रिया — Response to stimuli (Biomorphic property #5)
////
//// Identifies whether a failure event stream is:
////   Poisson  — CV ≈ 1.0: random, independent (exponential inter-arrivals)
////   Bursty   — CV > 1.5: correlated, clustered (cascade or common cause)
////   Periodic — CV < 0.5: regular interval (cron job or polling artifact)
////   Unknown  — insufficient data (< 5 events)
////
//// STAMP: SC-SIL4-001, SC-FUNC-002, SC-HA-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// External FFI — Erlang math:sqrt/1 for numerically stable square root
// ---------------------------------------------------------------------------

@external(erlang, "math", "sqrt")
fn erlang_sqrt(x: Float) -> Float

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/// A single failure event with millisecond timestamp, originating module, and
/// fractal layer. All three fields are informational; only timestamp_ms is used
/// by the classifier algorithm.
pub type FailureEvent {
  FailureEvent(timestamp_ms: Int, module: String, layer: String)
}

/// The classified failure pattern.
pub type FailurePattern {
  /// CV ≈ 1.0 — random, independent failures — normal operation
  Poisson
  /// CV > 1.5 — correlated failures — possible cascade or common cause
  Bursty
  /// CV < 0.5 — regular interval — likely a cron job or polling issue
  Periodic
  /// Insufficient data to classify (< 5 events ⟹ < 4 inter-arrival gaps)
  Unknown
}

/// Full result of a classification run.
pub type ClassifierResult {
  ClassifierResult(
    /// The classified pattern
    pattern: FailurePattern,
    /// CV = σ/μ of inter-arrival times (0.0 when Unknown)
    coefficient_of_variation: Float,
    /// Total number of events supplied
    event_count: Int,
    /// Confidence in [0.0, 1.0] (0.0 when Unknown)
    confidence: Float,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Classify a failure event stream.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pure function ↪ no I/O, no side-effects</morphism>
///   <formal-proof>
///     <P> Pre-condition: events is any List(FailureEvent), possibly empty. </P>
///     <C> classify(events) </C>
///     <Q> Post-condition: Returns ClassifierResult. Pattern = Unknown iff
///         len(events) < 5. Otherwise pattern ∈ {Poisson, Bursty, Periodic}
///         determined by CV of inter-arrival times. Confidence ∈ [0.0, 1.0]. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn classify(events: List(FailureEvent)) -> ClassifierResult {
  let count = list.length(events)
  case count < 5 {
    True ->
      ClassifierResult(
        pattern: Unknown,
        coefficient_of_variation: 0.0,
        event_count: count,
        confidence: 0.0,
      )
    False -> {
      let sorted =
        list.sort(events, fn(a, b) {
          int.compare(a.timestamp_ms, b.timestamp_ms)
        })
      let gaps = inter_arrival_times(sorted)
      let mu = mean(gaps)
      case mu <=. 0.0 {
        True ->
          // All events at the same timestamp — treat as maximally bursty
          ClassifierResult(
            pattern: Bursty,
            coefficient_of_variation: 0.0,
            event_count: count,
            confidence: 1.0,
          )
        False -> {
          let sigma = std_dev(gaps)
          let cv = sigma /. mu
          let #(pattern, confidence) = pattern_from_cv(cv)
          ClassifierResult(
            pattern: pattern,
            coefficient_of_variation: cv,
            event_count: count,
            confidence: confidence,
          )
        }
      }
    }
  }
}

/// Compute inter-arrival times (milliseconds) from a sorted event list.
/// Returns an empty list when the input has fewer than 2 events.
pub fn inter_arrival_times(events: List(FailureEvent)) -> List(Int) {
  case events {
    [] | [_] -> []
    [first, ..rest] -> do_gaps(rest, first.timestamp_ms, [])
  }
}

/// Compute the mean of a list of non-negative integers.
/// Returns 0.0 for an empty list.
pub fn mean(values: List(Int)) -> Float {
  case values {
    [] -> 0.0
    _ -> {
      let n = list.length(values)
      let total = list.fold(values, 0, fn(acc, v) { acc + v })
      int.to_float(total) /. int.to_float(n)
    }
  }
}

/// Compute the population standard deviation of a list of non-negative integers.
/// Uses a two-pass algorithm (mean first, then variance) for numerical stability.
/// Returns 0.0 for lists of fewer than 2 elements.
pub fn std_dev(values: List(Int)) -> Float {
  case values {
    [] | [_] -> 0.0
    _ -> {
      let mu = mean(values)
      let n = list.length(values)
      let sum_sq_dev =
        list.fold(values, 0.0, fn(acc, v) {
          let diff = int.to_float(v) -. mu
          acc +. diff *. diff
        })
      // Population std dev (divide by n, not n-1) — sufficient for classification
      let variance = sum_sq_dev /. int.to_float(n)
      erlang_sqrt(variance)
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Classify by CV and compute confidence.
///
/// Thresholds (from Cox (1962) renewal-process theory):
///   CV ∈ [0.8, 1.2] ⟹ Poisson  — confidence = 1 - |CV - 1.0| / 0.2
///   CV > 1.5         ⟹ Bursty   — confidence = min(1.0, (CV - 1.5) / 1.5 + 0.5)
///   CV < 0.5         ⟹ Periodic — confidence = min(1.0, (0.5 - CV) / 0.5 + 0.5)
///   else             ⟹ Unknown  — confidence = 0.2 (transition zone)
fn pattern_from_cv(cv: Float) -> #(FailurePattern, Float) {
  case cv >=. 0.8 && cv <=. 1.2 {
    True -> {
      // Distance from 1.0 scaled to [0,1]; closer to 1.0 ⟹ higher confidence
      let dist = float.absolute_value(cv -. 1.0)
      let confidence = clamp(1.0 -. dist /. 0.2, 0.0, 1.0)
      #(Poisson, confidence)
    }
    False ->
      case cv >. 1.5 {
        True -> {
          // Scales from 0.5 at CV=1.5 toward 1.0 as CV grows
          let confidence = clamp({ cv -. 1.5 } /. 1.5 +. 0.5, 0.0, 1.0)
          #(Bursty, confidence)
        }
        False ->
          case cv <. 0.5 {
            True -> {
              // Scales from 0.5 at CV=0.5 toward 1.0 as CV approaches 0
              let confidence = clamp({ 0.5 -. cv } /. 0.5 +. 0.5, 0.0, 1.0)
              #(Periodic, confidence)
            }
            False ->
              // Transition zone: 0.5 ≤ CV < 0.8  or  1.2 < CV ≤ 1.5
              #(Unknown, 0.2)
          }
      }
  }
}

/// Clamp a Float to [lo, hi].
fn clamp(v: Float, lo: Float, hi: Float) -> Float {
  case v <. lo {
    True -> lo
    False ->
      case v >. hi {
        True -> hi
        False -> v
      }
  }
}

/// Accumulate inter-arrival gap list (tail-recursive).
fn do_gaps(
  events: List(FailureEvent),
  prev_ts: Int,
  acc: List(Int),
) -> List(Int) {
  case events {
    [] -> list.reverse(acc)
    [ev, ..rest] -> {
      let gap = ev.timestamp_ms - prev_ts
      do_gaps(rest, ev.timestamp_ms, [gap, ..acc])
    }
  }
}

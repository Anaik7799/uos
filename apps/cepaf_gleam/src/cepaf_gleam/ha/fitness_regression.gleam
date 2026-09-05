//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/fitness_regression</module>
////     <fsharp-lineage>None — novel fitness regression tracker (विकास-गति)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Fitness Score History Tracker and Auto-Rollback Regression Detector.
////       Maintains a rolling window of the last 20 composite fitness scores,
////       computes a rolling baseline from scores[1..10], and emits typed
////       regression signals when the current score drops more than 5% below
////       the baseline (warn) or more than 10% below (rollback trigger).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-HA-001, SC-EVO-KPI-001, SC-EVO-KPI-002, SC-EVO-KPI-003,
////       SC-FUNC-003, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Ordered List(Float) × Float ↪ FitnessHistory ADT.
////       All arithmetic is pure; no panics; floats treated as [0.0, 1.0].
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// FITNESS REGRESSION TRACKER — विकास-गति (Evolution Momentum)
//// "परिणामे दुःखम्" — If the outcome brings suffering, the action was wrong
//// (Yoga Sutra 2.15)
////
//// Design principles:
////   1. PURE — All functions are side-effect free; callers own persistence.
////   2. WINDOWED — Keeps at most 20 scores; oldest are evicted automatically.
////   3. BASELINE-STABLE — Baseline computed from scores[1..10] (excludes
////      current), so a single bad reading cannot mask a persistent trend.
////   4. DUAL-THRESHOLD — 5% drop triggers warn (is_regressed); 10% drop
////      triggers rollback recommendation (should_rollback).
////   5. AUDIT-SAFE — summary/1 serialises state for Zenoh OTel publishing.
////
//// Regression thresholds:
////   WARN threshold     0.05   current < baseline * 0.95
////   ROLLBACK threshold 0.10   current < baseline * 0.90
////
//// STAMP: SC-HA-001, SC-EVO-KPI-001..003, SC-FUNC-003, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Rolling fitness history with regression detection.
///
/// Invariants (maintained by record/2):
///   |scores| <= 20
///   current = scores[0] (most recent, if any)
///   baseline = mean(scores[1..10]) or 0.0 when fewer than 2 scores exist
///   regression = current < baseline * 0.95
///   regression_depth = max(0.0, baseline - current)
pub type FitnessHistory {
  FitnessHistory(
    /// Most recent score first; capped at 20 entries.
    scores: List(Float),
    /// Rolling average of scores[1..10] (excluding current).
    baseline: Float,
    /// Latest recorded score (scores[0]).
    current: Float,
    /// True when current < baseline * 0.95 (5 % drop).
    regression: Bool,
    /// How far below baseline current sits; 0.0 when not regressed.
    regression_depth: Float,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Create an empty fitness history with neutral baseline.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Unit ↪ FitnessHistory (empty)</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> init() </C>
///     <Q> Post: scores = [], baseline = 0.0, current = 0.0,
///         regression = False, regression_depth = 0.0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> FitnessHistory {
  FitnessHistory(
    scores: [],
    baseline: 0.0,
    current: 0.0,
    regression: False,
    regression_depth: 0.0,
  )
}

/// Record a new fitness score, returning an updated FitnessHistory.
///
/// Steps:
///   1. Prepend score to history (newest first).
///   2. Evict oldest entries beyond the 20-entry window.
///   3. Recompute baseline from scores[1..10].
///   4. Recompute regression flags from the updated baseline.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">FitnessHistory × Float ↪ FitnessHistory</morphism>
///   <formal-proof>
///     <P> Pre: score is a finite Float; |history.scores| <= 20 </P>
///     <C> record(history, score) </C>
///     <Q> Post: result.current = score;
///         |result.scores| <= 20;
///         result.baseline = mean(result.scores[1..10]) </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn record(history: FitnessHistory, score: Float) -> FitnessHistory {
  // 1. Prepend and cap at 20 entries
  let updated = [score, ..history.scores] |> list.take(20)

  // 2. Baseline from positions [1..10] (skip index 0 = current)
  let baseline_window = updated |> list.drop(1) |> list.take(10)
  let new_baseline = mean(baseline_window)

  // 3. Regression flags
  let reg = is_below_threshold(score, new_baseline, 0.05)
  let depth = case reg {
    True -> float.max(0.0, new_baseline -. score)
    False -> 0.0
  }

  FitnessHistory(
    scores: updated,
    baseline: new_baseline,
    current: score,
    regression: reg,
    regression_depth: depth,
  )
}

/// Return True when the latest score is more than 5% below baseline.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">FitnessHistory ↪ Bool</morphism>
///   <formal-proof>
///     <P> Pre: history initialised via init() and/or record() </P>
///     <C> is_regressed(history) </C>
///     <Q> Post: True iff history.current < history.baseline * 0.95 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn is_regressed(history: FitnessHistory) -> Bool {
  history.regression
}

/// Return True when the latest score is more than 10% below baseline,
/// indicating that an automated rollback should be triggered.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">FitnessHistory ↪ Bool</morphism>
///   <formal-proof>
///     <P> Pre: history initialised via init() and/or record() </P>
///     <C> should_rollback(history) </C>
///     <Q> Post: True iff history.current < history.baseline * 0.90 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn should_rollback(history: FitnessHistory) -> Bool {
  is_below_threshold(history.current, history.baseline, 0.1)
}

/// Human-readable one-line summary suitable for Zenoh OTel publishing.
///
/// Format (example):
///   FitnessHistory[regressed] scores=5 current=0.7200 baseline=0.8100 depth=0.0900
pub fn summary(history: FitnessHistory) -> String {
  let tag = case history.regression {
    True ->
      case should_rollback(history) {
        True -> "rollback"
        False -> "regressed"
      }
    False -> "healthy"
  }
  "FitnessHistory["
  <> tag
  <> "] scores="
  <> int.to_string(list.length(history.scores))
  <> " current="
  <> float4(history.current)
  <> " baseline="
  <> float4(history.baseline)
  <> " depth="
  <> float4(history.regression_depth)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Compute the arithmetic mean of a list of floats.
/// Returns 0.0 for an empty list to avoid division by zero.
fn mean(values: List(Float)) -> Float {
  case values {
    [] -> 0.0
    _ -> {
      let total = list.fold(values, 0.0, fn(acc, v) { acc +. v })
      total /. int.to_float(list.length(values))
    }
  }
}

/// True when score < baseline * (1.0 - threshold).
/// Guards against a zero or near-zero baseline to avoid false positives
/// during system warm-up (fewer than 2 recorded scores).
fn is_below_threshold(score: Float, baseline: Float, threshold: Float) -> Bool {
  case baseline >. 0.001 {
    False -> False
    True -> score <. baseline *. { 1.0 -. threshold }
  }
}

/// Render a Float with exactly 4 decimal places using integer arithmetic
/// (avoids the non-determinism of float.to_string on different BEAM versions).
fn float4(v: Float) -> String {
  let tenths = float.round(v *. 10_000.0)
  let whole = tenths / 10_000
  let frac = int.absolute_value(tenths % 10_000)
  let frac_str = case frac < 10 {
    True -> "000" <> int.to_string(frac)
    False ->
      case frac < 100 {
        True -> "00" <> int.to_string(frac)
        False ->
          case frac < 1000 {
            True -> "0" <> int.to_string(frac)
            False -> int.to_string(frac)
          }
      }
  }
  int.to_string(whole) <> "." <> frac_str
}

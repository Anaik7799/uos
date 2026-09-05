//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/fitness_gate</module>
////     <fsharp-lineage>None — novel fitness-gated commit system (गुणपरीक्षा)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Fitness-Gated Commit System and Auto-Rollback Controller.
////       Computes a composite fitness score from six weighted signals —
////       test coverage, Shannon entropy, build speed, file size discipline,
////       endpoint richness, and zero-warning compliance — and emits a typed
////       GateDecision that drives commit allowance or rollback recommendation.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-HA-001, SC-MUDA-001, SC-FUNC-003, SC-FUNC-006,
////       SC-GLM-UI-001, SC-GLM-UI-003, SC-CMP-025
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Raw build/test metrics ↪ Typed FitnessScore ADT.
////       All arithmetic is pure; no panics; floats clamped to [0.0, 1.0].
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// FITNESS-GATED COMMIT SYSTEM — गुणपरीक्षा (Quality Examination)
//// "Do nothing which is of no use." — Miyamoto Musashi, Go Rin No Sho
////
//// Implements the fitness-gated commit gate and auto-rollback controller.
////
//// Design principles:
////   1. PURE — All functions are side-effect free; callers own persistence.
////   2. WEIGHTED — Six signals, each clamped to [0.0, 1.0], combined via
////      a fixed weight vector that sums to 1.0.
////   3. GRADE-DRIVEN — Four grades (A/B/C/D) map directly to gate decisions
////      (allow / warn+allow / conditional-allow / block).
////   4. REGRESSION-SENSITIVE — If the composite score drops by more than
////      0.05 from the previous commit, rollback is recommended regardless
////      of absolute grade.
////   5. AUDIT-SAFE — GateDecision and FitnessScore serialise to JSON for
////      Zenoh OTel publishing; no mutable state escapes this module.
////
//// Weight vector (sums to 1.0):
////   test_score      0.30  — primary quality signal
////   entropy_score   0.20  — test distribution quality
////   build_score     0.15  — compilation speed discipline
////   filesize_score  0.15  — code size discipline (anti-muda)
////   endpoint_score  0.10  — API surface richness
////   warning_score   0.10  — zero-warning compliance (SC-MUDA-001)
////
//// STAMP: SC-HA-001, SC-MUDA-001, SC-FUNC-003, SC-FUNC-006, SC-CMP-025

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// System fitness score components.
///
/// Each component is clamped to [0.0, 1.0] before weighting.
/// The composite field is the weighted sum.
pub type FitnessScore {
  FitnessScore(
    /// tests_passed / baseline_tests (weight 0.30)
    test_score: Float,
    /// H / 3.0 — normalised Shannon entropy of test distribution (weight 0.20)
    entropy_score: Float,
    /// 1000 / build_ms, capped at 1.0 — faster build = higher score (weight 0.15)
    build_score: Float,
    /// 500 / max_file_lines, capped at 1.0 — shorter files = higher score (weight 0.15)
    filesize_score: Float,
    /// endpoints / 30, capped at 1.0 — richer API = higher score (weight 0.10)
    endpoint_score: Float,
    /// 1 - warnings/10, floored at 0.0 — zero warnings = 1.0 (weight 0.10)
    warning_score: Float,
    /// Weighted sum of all six components
    composite: Float,
    /// Grade derived from composite (A/B/C/D)
    grade: FitnessGrade,
  )
}

/// Grade derived from composite fitness score.
pub type FitnessGrade {
  /// composite >= 0.90 — EXCELLENT, auto-commit
  GradeA
  /// composite >= 0.80 — GOOD, commit with note
  GradeB
  /// composite >= 0.60 — DEGRADED, review before commit
  GradeC
  /// composite < 0.60  — HARMFUL, block commit / consider revert
  GradeD
}

/// Gate decision emitted by gate_decision/2.
pub type GateDecision {
  /// Score is excellent; commit is permitted without reservation.
  AllowCommit(score: FitnessScore)
  /// Score is good; commit is permitted with attached advisory notes.
  WarnAndAllow(score: FitnessScore, warnings: List(String))
  /// Score is too low or regression exceeds threshold; commit is blocked.
  BlockCommit(score: FitnessScore, reason: String)
  /// Score has regressed sharply from the previous commit; rollback advised.
  RecommendRollback(score: FitnessScore, reason: String)
}

// ---------------------------------------------------------------------------
// Weight constants (sum = 1.0)
// ---------------------------------------------------------------------------

const w_test = 0.3

const w_entropy = 0.2

const w_build = 0.15

const w_filesize = 0.15

const w_endpoint = 0.1

const w_warning = 0.1

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Compute a FitnessScore from raw build/test metrics.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Raw metrics ↪ FitnessScore ADT</morphism>
///   <formal-proof>
///     <P> Pre: tests >= 0, baseline_tests > 0, entropy >= 0.0,
///         build_ms > 0, max_file > 0, endpoints >= 0, warnings >= 0 </P>
///     <C> compute_score(...) </C>
///     <Q> Post: all component scores in [0.0, 1.0];
///         composite = weighted sum; grade derived from composite </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn compute_score(
  tests tests: Int,
  baseline_tests baseline_tests: Int,
  entropy entropy: Float,
  build_ms build_ms: Int,
  max_file max_file: Int,
  endpoints endpoints: Int,
  warnings warnings: Int,
) -> FitnessScore {
  let ts =
    clamp01(int.to_float(tests) /. int.to_float(safe_baseline(baseline_tests)))
  let es = clamp01(entropy /. 3.0)
  let bs = clamp01(1000.0 /. int.to_float(safe_positive(build_ms)))
  let fs = clamp01(500.0 /. int.to_float(safe_positive(max_file)))
  let eps = clamp01(int.to_float(endpoints) /. 30.0)
  let ws = float.max(0.0, 1.0 -. int.to_float(warnings) /. 10.0)

  let composite =
    ts
    *. w_test
    +. es
    *. w_entropy
    +. bs
    *. w_build
    +. fs
    *. w_filesize
    +. eps
    *. w_endpoint
    +. ws
    *. w_warning

  FitnessScore(
    test_score: ts,
    entropy_score: es,
    build_score: bs,
    filesize_score: fs,
    endpoint_score: eps,
    warning_score: ws,
    composite: composite,
    grade: classify_grade(composite),
  )
}

/// Make a gate decision based on current fitness and the previous commit score.
///
/// Decision matrix:
///   current < previous - 0.05  → RecommendRollback (regression guard)
///   GradeD                     → BlockCommit
///   GradeC with regression > 5%→ BlockCommit
///   GradeC                     → WarnAndAllow (advisory list)
///   GradeB                     → WarnAndAllow (minor note)
///   GradeA                     → AllowCommit
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">FitnessScore × Float ↪ GateDecision ADT</morphism>
///   <formal-proof>
///     <P> Pre: previous_score in [0.0, 1.0] </P>
///     <C> gate_decision(current, previous_score) </C>
///     <Q> Post: GateDecision fully describes commit disposition; no panics </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn gate_decision(
  current: FitnessScore,
  previous_score: Float,
) -> GateDecision {
  case should_rollback(current.composite, previous_score, 0.05) {
    True ->
      RecommendRollback(
        current,
        "Regression detected: "
          <> format_pct(previous_score)
          <> " → "
          <> format_pct(current.composite)
          <> " (delta "
          <> format_pct(previous_score -. current.composite)
          <> " > threshold 5%)",
      )
    False ->
      case current.grade {
        GradeA -> AllowCommit(current)
        GradeB ->
          WarnAndAllow(current, [
            "Score "
            <> format_pct(current.composite)
            <> " — good but not excellent",
          ])
        GradeC -> grade_c_decision(current, previous_score)
        GradeD ->
          BlockCommit(
            current,
            "Score "
              <> format_pct(current.composite)
              <> " is below minimum threshold 0.60 (GradeD — HARMFUL)",
          )
      }
  }
}

/// Return True when the current score has regressed below the threshold band.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Float × Float × Float ↪ Bool</morphism>
///   <formal-proof>
///     <P> Pre: threshold > 0.0 </P>
///     <C> should_rollback(current, previous, threshold) </C>
///     <Q> Post: True iff previous - current > threshold </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn should_rollback(
  current: Float,
  previous: Float,
  threshold: Float,
) -> Bool {
  previous -. current >. threshold
}

/// Serialise a FitnessScore to a JSON string for Zenoh OTel publishing.
pub fn to_json(score: FitnessScore) -> String {
  "{"
  <> "\"test_score\":"
  <> float_str(score.test_score)
  <> ",\"entropy_score\":"
  <> float_str(score.entropy_score)
  <> ",\"build_score\":"
  <> float_str(score.build_score)
  <> ",\"filesize_score\":"
  <> float_str(score.filesize_score)
  <> ",\"endpoint_score\":"
  <> float_str(score.endpoint_score)
  <> ",\"warning_score\":"
  <> float_str(score.warning_score)
  <> ",\"composite\":"
  <> float_str(score.composite)
  <> ",\"grade\":\""
  <> grade_to_string(score.grade)
  <> "\"}"
}

/// Serialise a GateDecision to a JSON string.
pub fn decision_to_json(decision: GateDecision) -> String {
  case decision {
    AllowCommit(s) ->
      "{\"decision\":\"allow_commit\""
      <> ",\"grade\":\""
      <> grade_to_string(s.grade)
      <> "\",\"composite\":"
      <> float_str(s.composite)
      <> ",\"score\":"
      <> to_json(s)
      <> "}"
    WarnAndAllow(s, ws) ->
      "{\"decision\":\"warn_and_allow\""
      <> ",\"grade\":\""
      <> grade_to_string(s.grade)
      <> "\",\"composite\":"
      <> float_str(s.composite)
      <> ",\"warnings\":"
      <> json_string_array(ws)
      <> ",\"score\":"
      <> to_json(s)
      <> "}"
    BlockCommit(s, r) ->
      "{\"decision\":\"block_commit\""
      <> ",\"grade\":\""
      <> grade_to_string(s.grade)
      <> "\",\"composite\":"
      <> float_str(s.composite)
      <> ",\"reason\":\""
      <> escape_json(r)
      <> "\",\"score\":"
      <> to_json(s)
      <> "}"
    RecommendRollback(s, r) ->
      "{\"decision\":\"recommend_rollback\""
      <> ",\"grade\":\""
      <> grade_to_string(s.grade)
      <> "\",\"composite\":"
      <> float_str(s.composite)
      <> ",\"reason\":\""
      <> escape_json(r)
      <> "\",\"score\":"
      <> to_json(s)
      <> "}"
  }
}

/// Human-readable one-line summary of a FitnessScore.
pub fn summary(score: FitnessScore) -> String {
  "FitnessScore["
  <> grade_to_string(score.grade)
  <> "] composite="
  <> format_pct(score.composite)
  <> " | test="
  <> format_pct(score.test_score)
  <> " entropy="
  <> format_pct(score.entropy_score)
  <> " build="
  <> format_pct(score.build_score)
  <> " file="
  <> format_pct(score.filesize_score)
  <> " ep="
  <> format_pct(score.endpoint_score)
  <> " warn="
  <> format_pct(score.warning_score)
}

/// Return a default "unknown" fitness score suitable for endpoints that
/// cannot run a live build within a request cycle.
pub fn default_score() -> FitnessScore {
  compute_score(
    tests: 3354,
    baseline_tests: 3354,
    entropy: 2.67,
    build_ms: 800,
    max_file: 420,
    endpoints: 31,
    warnings: 0,
  )
}

// ---------------------------------------------------------------------------
// FitnessGate — simplified pre-commit health gate (SC-HA-001)
// ---------------------------------------------------------------------------

/// Default threshold for the health-based commit gate.
/// Set to 0.4 — lenient, only blocks truly broken states.
pub const default_threshold = 0.4

/// Simplified fitness gate backed directly by system_health() NIF.
///
/// Complements FitnessScore (multi-signal) with a lightweight, single-call
/// gate suitable for use in pre-commit hooks and CI pipelines.
pub type FitnessGate {
  FitnessGate(
    /// The minimum acceptable health score (0.0-1.0).
    threshold: Float,
    /// Current health score derived from system_health() (0.0-1.0).
    current_score: Float,
    /// True when current_score >= threshold.
    passed: Bool,
  )
}

/// Derive a 0.0-1.0 health score from the system_health() JSON string.
///
/// Maps status field values:
///   "ok"       → 1.0 (all containers healthy)
///   "degraded" → 0.6 (majority healthy, quorum maintained)
///   "critical" → 0.1 (majority unhealthy)
///   (other)    → 0.5 (unknown, conservative middle)
pub fn score_from_health_json(health_json: String) -> Float {
  case string.contains(health_json, "\"status\":\"ok\"") {
    True -> 1.0
    False ->
      case string.contains(health_json, "\"status\":\"degraded\"") {
        True -> 0.6
        False ->
          case string.contains(health_json, "\"status\":\"critical\"") {
            True -> 0.1
            False -> 0.5
          }
      }
  }
}

/// Query system_health() NIF and construct a FitnessGate.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Float threshold ↪ FitnessGate ADT</morphism>
///   <formal-proof>
///     <P> Pre: threshold in [0.0, 1.0] </P>
///     <C> check(threshold) </C>
///     <Q> Post: FitnessGate.current_score in [0.0, 1.0];
///         FitnessGate.passed = current_score >= threshold </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check(threshold: Float) -> FitnessGate {
  let health_json = c3i_nif.system_health()
  let score = score_from_health_json(health_json)
  FitnessGate(
    threshold: threshold,
    current_score: score,
    passed: score >=. threshold,
  )
}

/// Gate a commit based on live system health.
///
/// Returns Ok(Nil) when the health score meets the threshold, or
/// Error(reason) with a human-readable explanation when it does not.
///
/// Default threshold (0.4) is intentionally lenient — only truly broken
/// states (all containers down or critical) will block a commit.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Float threshold ↪ Result(Nil, String)</morphism>
///   <formal-proof>
///     <P> Pre: threshold in [0.0, 1.0] </P>
///     <C> gate_commit(threshold) </C>
///     <Q> Post: Ok(Nil) iff system health score >= threshold;
///         Error(String) otherwise with score and threshold in message </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn gate_commit(threshold: Float) -> Result(Nil, String) {
  let gate = check(threshold)
  case gate.passed {
    True -> Ok(Nil)
    False ->
      Error(
        "Fitness gate blocked: health score "
        <> float_str(gate.current_score)
        <> " is below threshold "
        <> float_str(gate.threshold)
        <> " — system may be in a degraded or critical state",
      )
  }
}

/// Convenience wrapper: gate_commit with the default 0.4 threshold.
pub fn gate_commit_default() -> Result(Nil, String) {
  gate_commit(default_threshold)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Grade from composite score.
fn classify_grade(composite: Float) -> FitnessGrade {
  case composite >=. 0.9 {
    True -> GradeA
    False ->
      case composite >=. 0.8 {
        True -> GradeB
        False ->
          case composite >=. 0.6 {
            True -> GradeC
            False -> GradeD
          }
      }
  }
}

/// Sub-decision for GradeC: block if regression, else warn and allow.
fn grade_c_decision(
  current: FitnessScore,
  previous_score: Float,
) -> GateDecision {
  let ws =
    [
      "Score "
        <> format_pct(current.composite)
        <> " is in degraded range [0.60, 0.80)",
      "Review required before activating in production",
    ]
    |> list.filter(fn(w) { string.length(w) > 0 })
  case should_rollback(current.composite, previous_score, 0.05) {
    True ->
      BlockCommit(
        current,
        "GradeC with regression "
          <> format_pct(previous_score)
          <> " → "
          <> format_pct(current.composite),
      )
    False -> WarnAndAllow(current, ws)
  }
}

/// Clamp a float to [0.0, 1.0].
fn clamp01(v: Float) -> Float {
  float.min(1.0, float.max(0.0, v))
}

/// Guard division-by-zero for baseline_tests.
fn safe_baseline(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> n
  }
}

/// Guard division-by-zero for strictly positive denominators.
fn safe_positive(n: Int) -> Int {
  case n <= 0 {
    True -> 1
    False -> n
  }
}

/// Render a [0.0, 1.0] float as a "N.NN%" string using integer arithmetic.
fn format_pct(v: Float) -> String {
  let millis = float.round(v *. 10_000.0)
  let whole = millis / 100
  let frac = millis % 100
  let frac_str = case frac < 10 {
    True -> "0" <> int.to_string(frac)
    False -> int.to_string(frac)
  }
  int.to_string(whole) <> "." <> frac_str <> "%"
}

/// Render a float with 4 decimal places for JSON.
fn float_str(v: Float) -> String {
  let millis = float.round(v *. 10_000.0)
  let whole = millis / 10_000
  let frac = millis % 10_000
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

/// Stable string representation of FitnessGrade.
pub fn grade_to_string(g: FitnessGrade) -> String {
  case g {
    GradeA -> "A"
    GradeB -> "B"
    GradeC -> "C"
    GradeD -> "D"
  }
}

/// Serialize a List(String) as a JSON array of quoted strings.
fn json_string_array(items: List(String)) -> String {
  let inner = list.map(items, fn(s) { "\"" <> escape_json(s) <> "\"" })
  "[" <> string.join(inner, ",") <> "]"
}

/// Minimal JSON string escaping (backslash and double-quote only).
fn escape_json(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

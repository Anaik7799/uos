//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/probabilistic_shield</module>
////     <fsharp-lineage>None — novel probabilistic safety shield for OODA decisions (SERBAN-1)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Formal safety verification of OODA action decisions using a
////       probabilistic shield.  The shield classifies each proposed action
////       as Safe, Unsafe, or Uncertain(confidence) based on:
////         - System health score [0.0, 1.0] (from NIF system_health())
////         - Action risk score [0.0, 1.0]  (caller-supplied domain estimate)
////
////       Decision logic:
////         combined = health × (1 − action_risk)
////         combined ≥ SAFE_THRESHOLD   → Safe
////         combined ≤ UNSAFE_THRESHOLD → Unsafe
////         otherwise                   → Uncertain(confidence = combined)
////
////       Keeps running statistics (decisions_checked, safe_count,
////       unsafe_count, uncertain_count) for dashboard display and
////       compliance reporting.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL4-001, SC-SIL4-006, SC-SAFETY-001, SC-FUNC-001,
////       SC-GUARD-001, SC-GLM-UI-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       (health, action_risk) ↪ ShieldVerdict ADT.
////       All arithmetic is pure; no panics; inputs clamped to [0.0, 1.0].
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// PROBABILISTIC SAFETY SHIELD — SERBAN-1
//// यत्र योगेश्वरः कृष्णः — Where there is formal safety, there is mastery (Gita 18.78)
////
//// Shields the OODA decide-phase against actions that are unsafe given the
//// current system health and the estimated risk of the proposed action.
////
//// Thresholds (tunable via module constants):
////   SAFE_THRESHOLD    = 0.70  — high confidence the action is safe
////   UNSAFE_THRESHOLD  = 0.30  — high confidence the action is unsafe
////   Zone [0.30, 0.70] = Uncertain — human review recommended
////
//// STAMP: SC-SIL4-001, SC-SIL4-006, SC-SAFETY-001, SC-FUNC-001,
////        SC-GUARD-001, SC-GLM-UI-001, SC-MUDA-001

import gleam/float
import gleam/int

// ---------------------------------------------------------------------------
// Thresholds
// ---------------------------------------------------------------------------

/// Combined score threshold above which an action is considered Safe.
pub const safe_threshold: Float = 0.7

/// Combined score threshold below which an action is considered Unsafe.
pub const unsafe_threshold: Float = 0.3

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// The shield's verdict for a proposed OODA action.
pub type ShieldVerdict {
  /// Action is safe to execute given current health and risk.
  Safe
  /// Action is unsafe — block execution, escalate to Guardian.
  Unsafe
  /// Confidence is too low to classify — human review recommended.
  Uncertain(confidence: Float)
}

/// Running statistics accumulated by the shield across all checked decisions.
pub type ShieldState {
  ShieldState(
    /// Total number of decisions checked
    decisions_checked: Int,
    /// Number of Safe verdicts
    safe_count: Int,
    /// Number of Unsafe verdicts
    unsafe_count: Int,
    /// Number of Uncertain verdicts
    uncertain_count: Int,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a fresh shield state with zero counters.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Unit ↪ zeroed ShieldState</morphism>
///   <formal-proof>
///     <P> (no precondition) </P>
///     <C> init() </C>
///     <Q> all counters = 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> ShieldState {
  ShieldState(
    decisions_checked: 0,
    safe_count: 0,
    unsafe_count: 0,
    uncertain_count: 0,
  )
}

/// Check a proposed action and return the updated state plus a verdict.
///
/// combined = clamp01(health) × (1.0 − clamp01(action_risk))
///
/// Thresholds:
///   combined ≥ safe_threshold    → Safe
///   combined ≤ unsafe_threshold  → Unsafe
///   otherwise                    → Uncertain(combined)
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">(ShieldState, health, risk) ↪ #(ShieldState, ShieldVerdict)</morphism>
///   <formal-proof>
///     <P> health ∈ ℝ; action_risk ∈ ℝ (both clamped internally) </P>
///     <C> check_decision(state, health, action_risk) </C>
///     <Q> new.decisions_checked = old.decisions_checked + 1;
///         exactly one of safe_count / unsafe_count / uncertain_count incremented;
///         verdict determined by combined score vs thresholds </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn check_decision(
  state: ShieldState,
  health: Float,
  action_risk: Float,
) -> #(ShieldState, ShieldVerdict) {
  let h = clamp01(health)
  let r = clamp01(action_risk)
  let combined = h *. { 1.0 -. r }
  let verdict = classify_verdict(combined)
  let new_state = increment_counter(state, verdict)
  #(new_state, verdict)
}

/// Fraction of decisions classified as Safe [0.0, 1.0].
///
/// Returns 1.0 when no decisions have been checked (vacuously safe).
pub fn safety_rate(state: ShieldState) -> Float {
  case state.decisions_checked == 0 {
    True -> 1.0
    False ->
      int.to_float(state.safe_count) /. int.to_float(state.decisions_checked)
  }
}

/// Human-readable one-line summary.
pub fn summary(state: ShieldState) -> String {
  "Shield["
  <> "checked="
  <> int.to_string(state.decisions_checked)
  <> " safe="
  <> int.to_string(state.safe_count)
  <> " unsafe="
  <> int.to_string(state.unsafe_count)
  <> " uncertain="
  <> int.to_string(state.uncertain_count)
  <> " rate="
  <> float4(safety_rate(state))
  <> "]"
}

/// Serialise ShieldState to a compact JSON string.
pub fn to_json(state: ShieldState) -> String {
  "{"
  <> "\"decisions_checked\":"
  <> int.to_string(state.decisions_checked)
  <> ",\"safe_count\":"
  <> int.to_string(state.safe_count)
  <> ",\"unsafe_count\":"
  <> int.to_string(state.unsafe_count)
  <> ",\"uncertain_count\":"
  <> int.to_string(state.uncertain_count)
  <> ",\"safety_rate\":"
  <> float4(safety_rate(state))
  <> "}"
}

/// Serialise a ShieldVerdict to a JSON string.
pub fn verdict_to_json(verdict: ShieldVerdict) -> String {
  case verdict {
    Safe -> "{\"verdict\":\"safe\"}"
    Unsafe -> "{\"verdict\":\"unsafe\"}"
    Uncertain(c) ->
      "{\"verdict\":\"uncertain\",\"confidence\":" <> float4(c) <> "}"
  }
}

/// Convert a verdict to a short display string.
pub fn verdict_to_string(verdict: ShieldVerdict) -> String {
  case verdict {
    Safe -> "Safe"
    Unsafe -> "Unsafe"
    Uncertain(c) -> "Uncertain(" <> float4(c) <> ")"
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Clamp a float to [0.0, 1.0].
fn clamp01(v: Float) -> Float {
  float.min(1.0, float.max(0.0, v))
}

/// Map a combined score to a ShieldVerdict.
fn classify_verdict(combined: Float) -> ShieldVerdict {
  case combined >=. safe_threshold {
    True -> Safe
    False ->
      case combined <=. unsafe_threshold {
        True -> Unsafe
        False -> Uncertain(combined)
      }
  }
}

/// Increment the appropriate counter for the given verdict.
fn increment_counter(state: ShieldState, verdict: ShieldVerdict) -> ShieldState {
  let new_checked = state.decisions_checked + 1
  case verdict {
    Safe ->
      ShieldState(
        ..state,
        decisions_checked: new_checked,
        safe_count: state.safe_count + 1,
      )
    Unsafe ->
      ShieldState(
        ..state,
        decisions_checked: new_checked,
        unsafe_count: state.unsafe_count + 1,
      )
    Uncertain(_) ->
      ShieldState(
        ..state,
        decisions_checked: new_checked,
        uncertain_count: state.uncertain_count + 1,
      )
  }
}

/// Render a float with 4 decimal places for JSON / summary output.
fn float4(v: Float) -> String {
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

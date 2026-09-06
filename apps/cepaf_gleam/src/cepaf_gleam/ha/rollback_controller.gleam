//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/rollback_controller</module>
////     <fsharp-lineage>None — novel SLO-driven automated rollback controller (F20)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       Automated Rollback on SLO Violation (F20).
////       Evaluates error budget consumption against a configurable threshold
////       and emits a typed RollbackDecision. When auto_rollback_enabled, the
////       execute_rollback function performs version swap and increments the
////       monotonic rollback counter.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-HA-001, SC-SIL4-001, SC-SIL4-007, SC-FUNC-003,
////       SC-GLM-UI-003, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Google SRE Error Budget model ↪ Gleam pure decision function.
////       error_budget_remaining: Float in [0.0, 1.0] — 1.0 = full, 0.0 = exhausted.
////       RollbackDecision is an ADT; never panics; caller owns persistence.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// AUTOMATED ROLLBACK CONTROLLER — SLO ERROR BUDGET GUARDIAN
//// यदा यदा हि धर्मस्य — Whenever dharma declines (Gita 4.7)
////
//// Implements F20: automated rollback when the SLO error budget is exhausted.
////
//// Design principles:
////   1. PURE — evaluate() and execute_rollback() have no side-effects; state
////      is passed by value; caller owns persistence and Zenoh publishing.
////   2. THRESHOLD-DRIVEN — rollback fires when budget_remaining < threshold.
////      The default threshold is 0.10 (10% budget left = danger zone).
////   3. URGENCY-GRADED — four urgency levels derived from the budget reading:
////      High  >= 0.10   rollback recommended, not yet automatic
////      Medium 0.05–0.10 rollback recommended at elevated urgency
////      High  0.01–0.05  rollback recommended, high urgency
////      Immediate < 0.01  execute immediately (if auto_rollback_enabled)
////   4. AUDIT-SAFE — execute_rollback returns a new RollbackState with the
////      versions swapped and rollback_count incremented; the old state is
////      preserved by the caller for audit/Zenoh publishing.
////   5. IDEMPOTENT — calling evaluate on a state where current == previous
////      returns NoRollback("versions_identical") — prevent infinite loops.
////
//// STAMP: SC-HA-001, SC-SIL4-001, SC-SIL4-007, SC-FUNC-003

import gleam/float
import gleam/int
import gleam/json

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Complete rollback controller state.
///
/// Fields are passed by value; no mutable shared state.
pub type RollbackState {
  RollbackState(
    /// The version currently serving traffic
    current_version: String,
    /// The version to roll back to
    previous_version: String,
    /// Monotonic counter of how many rollbacks have been executed
    rollback_count: Int,
    /// Human-readable reason for the most recent rollback (empty if none)
    last_rollback_reason: String,
    /// When True, execute_rollback may be called automatically by evaluate()
    auto_rollback_enabled: Bool,
    /// Trigger rollback when error_budget_remaining < this value (e.g. 0.10)
    error_budget_threshold: Float,
  )
}

/// Decision emitted by evaluate/1.
pub type RollbackDecision {
  /// Budget is healthy; no action needed.
  NoRollback(reason: String)
  /// Budget is low; operator or automation should prepare to roll back.
  RollbackRecommended(reason: String, urgency: RollbackUrgency)
  /// Rollback was executed immediately (auto_rollback_enabled = True).
  RollbackExecuted(from_version: String, to_version: String)
}

/// Urgency gradient for RollbackRecommended.
pub type RollbackUrgency {
  /// budget_remaining in (threshold, 0.20] — watch
  Low
  /// budget_remaining in (0.05, threshold] — alert
  Medium
  /// budget_remaining in (0.01, 0.05] — act soon
  High
  /// budget_remaining in [0.0, 0.01] — act now
  Immediate
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a rollback controller with sensible defaults.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Bootstrap ↪ RollbackState with clean audit trail</morphism>
///   <formal-proof>
///     <P> Pre: current_version and previous_version are non-empty strings </P>
///     <C> init(current_version, previous_version) </C>
///     <Q> Post: rollback_count = 0, auto_rollback_enabled = True,
///         error_budget_threshold = 0.10, last_rollback_reason = "" </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(
  current_version: String,
  previous_version: String,
) -> RollbackState {
  RollbackState(
    current_version: current_version,
    previous_version: previous_version,
    rollback_count: 0,
    last_rollback_reason: "",
    auto_rollback_enabled: True,
    error_budget_threshold: 0.1,
  )
}

/// Evaluate current error budget and produce a typed RollbackDecision.
///
/// Decision matrix:
///   versions identical          → NoRollback("versions_identical")
///   budget >= 0.20              → NoRollback("budget_healthy")
///   budget in (threshold, 0.20] → RollbackRecommended(Low)
///   budget in (0.05, threshold] → RollbackRecommended(Medium)
///   budget in (0.01, 0.05]      → RollbackRecommended(High)
///   budget in [0.0, 0.01)       → RollbackRecommended(Immediate) or RollbackExecuted
///
/// When auto_rollback_enabled = True AND urgency = Immediate, the function
/// returns RollbackExecuted — the caller MUST call execute_rollback(state)
/// to obtain the updated state.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Budget Float ↪ RollbackDecision ADT</morphism>
///   <formal-proof>
///     <P> Pre: error_budget_remaining in [0.0, 1.0] </P>
///     <C> evaluate(state, error_budget_remaining) </C>
///     <Q> Post: RollbackDecision is returned; state is unchanged </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn evaluate(
  state: RollbackState,
  error_budget_remaining: Float,
) -> RollbackDecision {
  // Guard: identical versions means rollback is a no-op
  case state.current_version == state.previous_version {
    True -> NoRollback("versions_identical")
    False -> evaluate_budget(state, error_budget_remaining)
  }
}

/// Execute the rollback — swap versions and increment the audit counter.
///
/// Returns a new RollbackState with:
///   current_version  := old previous_version
///   previous_version := old current_version
///   rollback_count   := rollback_count + 1
///   last_rollback_reason := "slo_budget_exhausted"
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">RollbackState ↪ RollbackState (swapped)</morphism>
///   <formal-proof>
///     <P> Pre: state.current_version != state.previous_version </P>
///     <C> execute_rollback(state) </C>
///     <Q> Post: new.current_version = state.previous_version AND
///         new.previous_version = state.current_version AND
///         new.rollback_count = state.rollback_count + 1 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn execute_rollback(state: RollbackState) -> RollbackState {
  RollbackState(
    ..state,
    current_version: state.previous_version,
    previous_version: state.current_version,
    rollback_count: state.rollback_count + 1,
    last_rollback_reason: "slo_budget_exhausted",
  )
}

/// Serialise the full rollback state to a JSON string.
///
/// Output shape:
///   {
///     "current_version": "...",
///     "previous_version": "...",
///     "rollback_count": N,
///     "last_rollback_reason": "...",
///     "auto_rollback_enabled": true/false,
///     "error_budget_threshold": 0.10
///   }
pub fn to_json(state: RollbackState) -> String {
  json.object([
    #("current_version", json.string(state.current_version)),
    #("previous_version", json.string(state.previous_version)),
    #("rollback_count", json.int(state.rollback_count)),
    #("last_rollback_reason", json.string(state.last_rollback_reason)),
    #("auto_rollback_enabled", json.bool(state.auto_rollback_enabled)),
    #("error_budget_threshold", json.float(state.error_budget_threshold)),
  ])
  |> json.to_string()
}

/// Serialise a RollbackDecision to a JSON string for Zenoh publishing.
pub fn decision_to_json(decision: RollbackDecision) -> String {
  case decision {
    NoRollback(reason) ->
      json.object([
        #("decision", json.string("no_rollback")),
        #("reason", json.string(reason)),
      ])
      |> json.to_string()
    RollbackRecommended(reason, urgency) ->
      json.object([
        #("decision", json.string("rollback_recommended")),
        #("reason", json.string(reason)),
        #("urgency", json.string(urgency_to_string(urgency))),
      ])
      |> json.to_string()
    RollbackExecuted(from_v, to_v) ->
      json.object([
        #("decision", json.string("rollback_executed")),
        #("from_version", json.string(from_v)),
        #("to_version", json.string(to_v)),
      ])
      |> json.to_string()
  }
}

/// Human-readable description of a RollbackDecision.
pub fn describe_decision(decision: RollbackDecision) -> String {
  case decision {
    NoRollback(reason) -> "NoRollback: " <> reason
    RollbackRecommended(reason, urgency) ->
      "RollbackRecommended [" <> urgency_to_string(urgency) <> "]: " <> reason
    RollbackExecuted(from_v, to_v) ->
      "RollbackExecuted: " <> from_v <> " → " <> to_v
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Core budget evaluation — assumes versions are not identical.
fn evaluate_budget(state: RollbackState, budget: Float) -> RollbackDecision {
  let threshold = state.error_budget_threshold
  case budget >=. 0.2 {
    True ->
      NoRollback("budget_healthy: " <> float_to_pct(budget) <> " remaining")
    False ->
      case budget >. threshold {
        True ->
          RollbackRecommended(
            "budget_low: " <> float_to_pct(budget) <> " remaining",
            Low,
          )
        False -> evaluate_critical(state, budget)
      }
  }
}

/// Evaluate budgets below the configured threshold.
fn evaluate_critical(state: RollbackState, budget: Float) -> RollbackDecision {
  let urgency = classify_urgency(budget)
  let reason =
    "budget_critical: "
    <> float_to_pct(budget)
    <> " remaining (threshold="
    <> float_to_pct(state.error_budget_threshold)
    <> ")"
  case urgency {
    Immediate ->
      case state.auto_rollback_enabled {
        True ->
          RollbackExecuted(
            from_version: state.current_version,
            to_version: state.previous_version,
          )
        False -> RollbackRecommended(reason, Immediate)
      }
    _ -> RollbackRecommended(reason, urgency)
  }
}

/// Classify urgency from raw budget fraction.
fn classify_urgency(budget: Float) -> RollbackUrgency {
  case budget <. 0.01 {
    True -> Immediate
    False ->
      case budget <. 0.05 {
        True -> High
        False -> Medium
      }
  }
}

/// Format a [0.0, 1.0] float as a percentage string.
fn float_to_pct(v: Float) -> String {
  let pct = float.round(v *. 1000.0)
  let whole = pct / 10
  let frac = pct % 10
  int.to_string(whole) <> "." <> int.to_string(frac) <> "%"
}

/// Stable string representation of urgency for JSON/logging.
fn urgency_to_string(u: RollbackUrgency) -> String {
  case u {
    Low -> "low"
    Medium -> "medium"
    High -> "high"
    Immediate -> "immediate"
  }
}

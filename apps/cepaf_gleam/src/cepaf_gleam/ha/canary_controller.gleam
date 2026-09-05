//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/canary_controller</module>
////     <fsharp-lineage>None — novel Zenoh-native canary deployment controller (F09)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       Canary Deployment via Zenoh (F09).
////       Progressive traffic shifting across six phases (5% → 25% → 50% →
////       75% → 100% → promote). Health checks drive advance or rollback.
////       The state machine is a pure ADT; Zenoh publishing and traffic
////       routing are the caller's responsibility.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-HA-001, SC-SIL4-011, SC-FUNC-003,
////       SC-GLM-UI-003, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Progressive delivery FSM ↪ Gleam pure state machine.
////       Traffic percentage is a discrete Int in [0, 100].
////       All transitions return a new CanaryState; no mutation.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CANARY DEPLOYMENT CONTROLLER — PROGRESSIVE TRAFFIC SHIFTING
//// यदा यदा हि धर्मस्य — Whenever dharma declines (Gita 4.7)
////
//// Implements F09: canary deployments via Zenoh-native progressive rollout.
////
//// Phase progression (healthy path):
////   Idle → Started(5%) → Expanding(25%) → Halfway(50%) →
////   Majority(75%) → Promoting(100%) → [caller promotes]
////
//// Unhealthy path:
////   Any phase → RollingBack → [caller restores stable]
////
//// Health check contract:
////   record_health(state, True)  — increment health_checks_passed
////   record_health(state, False) — increment health_checks_failed
////   should_rollback(state)      — True when failed / (passed + failed) > 0.01
////   should_promote(state)       — True when phase = Promoting AND
////                                  pass_rate >= promotion_threshold
////
//// Design principles:
////   1. PURE — all functions return new state; zero IO
////   2. FSM-EXPLICIT — CanaryPhase is a closed ADT; exhaustive match enforced
////   3. SAFE-DEFAULT — advance() on non-expandable phase is a no-op
////   4. AUDIT-READY — to_json serialises all fields for Zenoh span publishing
////
//// STAMP: SC-HA-001, SC-SIL4-011, SC-FUNC-003

import gleam/float
import gleam/int
import gleam/json

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Complete canary deployment state.
pub type CanaryState {
  CanaryState(
    /// Version under canary test
    canary_version: String,
    /// Version currently serving the majority of traffic
    stable_version: String,
    /// Traffic percentage routed to canary, 0–100
    traffic_pct: Int,
    /// Current phase of the canary FSM
    phase: CanaryPhase,
    /// Cumulative health checks that passed
    health_checks_passed: Int,
    /// Cumulative health checks that failed
    health_checks_failed: Int,
    /// Minimum pass rate required to promote (e.g. 0.99)
    promotion_threshold: Float,
  )
}

/// Six-phase canary FSM — ordered by traffic percentage.
pub type CanaryPhase {
  /// No canary active
  CanaryIdle
  /// 5% traffic to canary
  CanaryStarted
  /// 25% traffic to canary
  CanaryExpanding
  /// 50% traffic to canary
  CanaryHalfway
  /// 75% traffic to canary
  CanaryMajority
  /// 100% traffic to canary — awaiting promotion decision
  CanaryPromoting
  /// Health gate failed — rolling back to stable
  CanaryRollingBack
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a canary deployment in the Idle phase.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Bootstrap ↪ CanaryState at Idle phase</morphism>
///   <formal-proof>
///     <P> Pre: canary_version != stable_version (caller responsibility) </P>
///     <C> init(canary_version, stable_version) </C>
///     <Q> Post: phase = CanaryIdle, traffic_pct = 0, all counters = 0,
///         promotion_threshold = 0.99 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init(canary_version: String, stable_version: String) -> CanaryState {
  CanaryState(
    canary_version: canary_version,
    stable_version: stable_version,
    traffic_pct: 0,
    phase: CanaryIdle,
    health_checks_passed: 0,
    health_checks_failed: 0,
    promotion_threshold: 0.99,
  )
}

/// Advance the canary to the next phase if it is in a progressing state.
///
/// Phase transition table:
///   Idle        → Started   (0% → 5%)
///   Started     → Expanding (5% → 25%)
///   Expanding   → Halfway   (25% → 50%)
///   Halfway     → Majority  (50% → 75%)
///   Majority    → Promoting (75% → 100%)
///   Promoting   → no-op (caller calls should_promote then promotes)
///   RollingBack → no-op (caller handles restoration)
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">CanaryState ↪ CanaryState (next phase)</morphism>
///   <formal-proof>
///     <P> Pre: state is a valid CanaryState </P>
///     <C> advance(state) </C>
///     <Q> Post: phase transitions forward by one step OR is unchanged if
///         already at Promoting/RollingBack </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn advance(state: CanaryState) -> CanaryState {
  case state.phase {
    CanaryIdle -> CanaryState(..state, phase: CanaryStarted, traffic_pct: 5)
    CanaryStarted ->
      CanaryState(..state, phase: CanaryExpanding, traffic_pct: 25)
    CanaryExpanding ->
      CanaryState(..state, phase: CanaryHalfway, traffic_pct: 50)
    CanaryHalfway ->
      CanaryState(..state, phase: CanaryMajority, traffic_pct: 75)
    CanaryMajority ->
      CanaryState(..state, phase: CanaryPromoting, traffic_pct: 100)
    // Terminal / no-op phases
    CanaryPromoting -> state
    CanaryRollingBack -> state
  }
}

/// Record one health check result against the canary.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Bool ↪ updated counters</morphism>
///   <formal-proof>
///     <P> Pre: state is a valid CanaryState </P>
///     <C> record_health(state, passed) </C>
///     <Q> Post: if passed then health_checks_passed + 1
///         else health_checks_failed + 1; phase unchanged </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn record_health(state: CanaryState, passed: Bool) -> CanaryState {
  case passed {
    True ->
      CanaryState(..state, health_checks_passed: state.health_checks_passed + 1)
    False ->
      CanaryState(..state, health_checks_failed: state.health_checks_failed + 1)
  }
}

/// True when the canary is at Promoting phase AND the pass rate meets the
/// configured promotion_threshold.
///
/// pass_rate = passed / (passed + failed).  Returns False when no checks
/// have been recorded (no data → do not auto-promote).
pub fn should_promote(state: CanaryState) -> Bool {
  case state.phase {
    CanaryPromoting -> {
      let total = state.health_checks_passed + state.health_checks_failed
      case total {
        0 -> False
        _ -> pass_rate(state) >=. state.promotion_threshold
      }
    }
    _ -> False
  }
}

/// True when the canary failure rate exceeds 1% (fail_rate > 0.01).
///
/// A canary with zero checks is considered safe (returns False).
/// RollingBack phase always returns True so callers can detect it.
pub fn should_rollback(state: CanaryState) -> Bool {
  case state.phase {
    CanaryRollingBack -> True
    _ -> {
      let total = state.health_checks_passed + state.health_checks_failed
      case total {
        0 -> False
        _ -> fail_rate(state) >. 0.01
      }
    }
  }
}

/// Transition the canary into the RollingBack phase.
/// This is a pure state update; traffic routing is the caller's responsibility.
pub fn trigger_rollback(state: CanaryState) -> CanaryState {
  CanaryState(..state, phase: CanaryRollingBack, traffic_pct: 0)
}

/// Serialise the full canary state to a JSON string.
///
/// Output shape:
///   {
///     "canary_version": "...",
///     "stable_version": "...",
///     "traffic_pct": N,
///     "phase": "...",
///     "health_checks_passed": N,
///     "health_checks_failed": N,
///     "promotion_threshold": 0.99,
///     "pass_rate": 0.0
///   }
pub fn to_json(state: CanaryState) -> String {
  let total = state.health_checks_passed + state.health_checks_failed
  let computed_pass_rate = case total {
    0 -> 1.0
    _ -> pass_rate(state)
  }
  json.object([
    #("canary_version", json.string(state.canary_version)),
    #("stable_version", json.string(state.stable_version)),
    #("traffic_pct", json.int(state.traffic_pct)),
    #("phase", json.string(phase_to_string(state.phase))),
    #("health_checks_passed", json.int(state.health_checks_passed)),
    #("health_checks_failed", json.int(state.health_checks_failed)),
    #("promotion_threshold", json.float(state.promotion_threshold)),
    #("pass_rate", json.float(computed_pass_rate)),
  ])
  |> json.to_string()
}

/// Human-readable phase label.
pub fn describe_phase(state: CanaryState) -> String {
  phase_to_string(state.phase)
  <> " ("
  <> int.to_string(state.traffic_pct)
  <> "% canary traffic)"
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Compute pass rate as a fraction in [0.0, 1.0].
/// Caller MUST ensure total > 0 before calling.
fn pass_rate(state: CanaryState) -> Float {
  let total = state.health_checks_passed + state.health_checks_failed
  case total {
    0 -> 1.0
    _ ->
      float.divide(
        int.to_float(state.health_checks_passed),
        int.to_float(total),
      )
      |> result_to_float()
  }
}

/// Compute fail rate as a fraction in [0.0, 1.0].
/// Caller MUST ensure total > 0 before calling.
fn fail_rate(state: CanaryState) -> Float {
  let total = state.health_checks_passed + state.health_checks_failed
  case total {
    0 -> 0.0
    _ ->
      float.divide(
        int.to_float(state.health_checks_failed),
        int.to_float(total),
      )
      |> result_to_float()
  }
}

/// Stable string key for a CanaryPhase.
fn phase_to_string(phase: CanaryPhase) -> String {
  case phase {
    CanaryIdle -> "idle"
    CanaryStarted -> "started"
    CanaryExpanding -> "expanding"
    CanaryHalfway -> "halfway"
    CanaryMajority -> "majority"
    CanaryPromoting -> "promoting"
    CanaryRollingBack -> "rolling_back"
  }
}

/// Unwrap a Result(Float, _), returning 0.0 on Error.
fn result_to_float(r: Result(Float, _)) -> Float {
  case r {
    Ok(v) -> v
    Error(_) -> 0.0
  }
}

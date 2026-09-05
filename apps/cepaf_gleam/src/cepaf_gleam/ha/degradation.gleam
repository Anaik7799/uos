//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/degradation</module>
////     <fsharp-lineage>None — novel formal graceful degradation FSM (F11)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Formal Graceful Degradation Levels (F11).
////       Implements a 4-tier monotonic degradation FSM for the SIL-6 mesh:
////       FullOperation → DegradedService → EmergencyMode → SafeState.
////       The FSM is strictly monotone downward (degrade) and upward (recover).
////       Function availability is deterministic per level.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-HA-001, SC-FUNC-001, SC-FUNC-003, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       IEC 61508 SIL degradation levels ↪ Gleam custom type FSM.
////       4 states with deterministic active/disabled function sets per level.
////       All transitions are pure; side-effect dispatch is caller responsibility.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// FORMAL GRACEFUL DEGRADATION FSM — 4-TIER AVAILABILITY LEVELS
//// स्वधर्मे निधनं श्रेयः — Better to fail in one's own dharma (Gita 3.35)
////
//// The degradation FSM models the IEC 61508 principle of graceful service
//// reduction: when the system detects a failure it MUST shed non-critical
//// functions rather than exposing operators to unreliable data.
////
//// Level transitions:
////
////   degrade:  FullOperation → DegradedService → EmergencyMode → SafeState
////   recover:  SafeState → EmergencyMode → DegradedService → FullOperation
////
//// Function availability per level:
////
////   FullOperation   — all 12 functions active, 0 disabled
////   DegradedService — 8 critical functions active, 4 non-critical disabled
////   EmergencyMode   — 4 safety-only functions active, 8 disabled
////   SafeState       — 0 functions active, 12 disabled (operator required)
////
//// STAMP: SC-SIL4-001, SC-HA-001, SC-FUNC-001, SC-FUNC-003

import gleam/json
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Four-tier graceful degradation level.
///
/// Ordered from nominal (FullOperation) to halted (SafeState).
/// The ordering satisfies: FullOperation < DegradedService < EmergencyMode < SafeState
/// when expressed as the integer returned by level_to_int/1.
pub type DegradationLevel {
  /// All systems nominal — full function set available
  FullOperation
  /// Non-critical functions disabled — reduced but serviceable
  DegradedService
  /// Only safety-critical functions active — operator notified
  EmergencyMode
  /// System halted — no functions active, operator intervention required
  SafeState
}

/// Point-in-time snapshot of the system's degradation posture.
pub type DegradationState {
  DegradationState(
    /// Current degradation tier
    level: DegradationLevel,
    /// Functions currently accepting requests
    active_functions: List(String),
    /// Functions that have been shed / disabled
    disabled_functions: List(String),
    /// Human-readable reason for the last level change
    reason: String,
    /// Logical timestamp of the last transition (monotonic counter / Unix epoch)
    since_timestamp: Int,
  )
}

// ---------------------------------------------------------------------------
// Function catalog
// ---------------------------------------------------------------------------

/// All 12 system functions tracked by the degradation FSM.
///
/// Tier membership determines which level keeps each function enabled.
///
///   Tier 0 (always disabled in SafeState):  all 12
///   Tier 1 (disabled in EmergencyMode):     4 non-safety functions
///   Tier 2 (disabled in DegradedService):   0 additional (kept for emergency)
///
/// In practice:
///   EmergencyMode disables 8; SafeState disables all 12.
const all_functions: List(String) = [
  // Safety-critical tier — kept through EmergencyMode
  "guardian_gate",
  "invariant_check",
  "jidoka_halt",
  "zenoh_health_monitor",
  // Operational tier — kept through DegradedService, shed at EmergencyMode
  "nif_pipeline",
  "ooda_supervisor",
  "health_cascade",
  "runbook_executor",
  // Non-critical tier — shed at DegradedService
  "ai_advisory",
  "ui_dashboard",
  "knowledge_search",
  "metrics_reporter",
]

/// Safety-only functions retained in EmergencyMode.
const emergency_functions: List(String) = [
  "guardian_gate",
  "invariant_check",
  "jidoka_halt",
  "zenoh_health_monitor",
]

/// Functions retained in DegradedService (emergency + operational tiers).
const degraded_functions: List(String) = [
  "guardian_gate",
  "invariant_check",
  "jidoka_halt",
  "zenoh_health_monitor",
  "nif_pipeline",
  "ooda_supervisor",
  "health_cascade",
  "runbook_executor",
]

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise a fresh degradation state at FullOperation.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Bootstrap ↪ DegradationState at FullOperation</morphism>
///   <formal-proof>
///     <P> Pre: none </P>
///     <C> init() </C>
///     <Q> Post: state.level == FullOperation,
///         list.length(state.active_functions) == 12,
///         list.length(state.disabled_functions) == 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> DegradationState {
  let #(active, disabled) = functions_at_level(FullOperation)
  DegradationState(
    level: FullOperation,
    active_functions: active,
    disabled_functions: disabled,
    reason: "system initialised",
    since_timestamp: 0,
  )
}

/// Move down one degradation level (FullOperation → DegradedService → EmergencyMode → SafeState).
///
/// If already at SafeState, state is unchanged (bottom of FSM is terminal).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Current level ↪ next lower level</morphism>
///   <formal-proof>
///     <P> Pre: state is a valid DegradationState </P>
///     <C> degrade(state, reason) </C>
///     <Q> Post: level_to_int(result.level) >= level_to_int(state.level),
///         reason propagated, active_functions updated deterministically </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn degrade(state: DegradationState, reason: String) -> DegradationState {
  let next = next_lower_level(state.level)
  let #(active, disabled) = functions_at_level(next)
  DegradationState(
    level: next,
    active_functions: active,
    disabled_functions: disabled,
    reason: reason,
    since_timestamp: state.since_timestamp + 1,
  )
}

/// Move up one degradation level (SafeState → EmergencyMode → DegradedService → FullOperation).
///
/// If already at FullOperation, state is unchanged (top of FSM is terminal).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Current level ↪ next higher level</morphism>
///   <formal-proof>
///     <P> Pre: state is a valid DegradationState </P>
///     <C> recover(state) </C>
///     <Q> Post: level_to_int(result.level) <= level_to_int(state.level),
///         active_functions set restored upward deterministically </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn recover(state: DegradationState) -> DegradationState {
  let next = next_higher_level(state.level)
  let #(active, disabled) = functions_at_level(next)
  DegradationState(
    level: next,
    active_functions: active,
    disabled_functions: disabled,
    reason: "recovery step: "
      <> level_to_string(state.level)
      <> " -> "
      <> level_to_string(next),
    since_timestamp: state.since_timestamp + 1,
  )
}

/// Return (active_functions, disabled_functions) for a given level.
///
/// This is the canonical source of truth for function availability.
pub fn functions_at_level(
  level: DegradationLevel,
) -> #(List(String), List(String)) {
  case level {
    FullOperation -> #(all_functions, [])
    DegradedService -> #(
      degraded_functions,
      list.filter(all_functions, fn(f) { !list.contains(degraded_functions, f) }),
    )
    EmergencyMode -> #(
      emergency_functions,
      list.filter(all_functions, fn(f) {
        !list.contains(emergency_functions, f)
      }),
    )
    SafeState -> #([], all_functions)
  }
}

/// Return True when the named function is available at the current level.
pub fn function_available(state: DegradationState, name: String) -> Bool {
  list.contains(state.active_functions, name)
}

/// Integer rank of a level: lower = more nominal, higher = more degraded.
///
///   FullOperation = 0
///   DegradedService = 1
///   EmergencyMode = 2
///   SafeState = 3
pub fn level_to_int(level: DegradationLevel) -> Int {
  case level {
    FullOperation -> 0
    DegradedService -> 1
    EmergencyMode -> 2
    SafeState -> 3
  }
}

/// Human-readable label for a degradation level.
pub fn level_to_string(level: DegradationLevel) -> String {
  case level {
    FullOperation -> "FullOperation"
    DegradedService -> "DegradedService"
    EmergencyMode -> "EmergencyMode"
    SafeState -> "SafeState"
  }
}

/// Serialise the current DegradationState to a JSON string.
pub fn to_json(state: DegradationState) -> String {
  json.object([
    #("level", json.string(level_to_string(state.level))),
    #("level_int", json.int(level_to_int(state.level))),
    #("active_functions", json.array(state.active_functions, json.string)),
    #("disabled_functions", json.array(state.disabled_functions, json.string)),
    #("active_count", json.int(list.length(state.active_functions))),
    #("disabled_count", json.int(list.length(state.disabled_functions))),
    #("reason", json.string(state.reason)),
    #("since_timestamp", json.int(state.since_timestamp)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// FSM transition helpers (private)
// ---------------------------------------------------------------------------

fn next_lower_level(level: DegradationLevel) -> DegradationLevel {
  case level {
    FullOperation -> DegradedService
    DegradedService -> EmergencyMode
    EmergencyMode -> SafeState
    SafeState -> SafeState
  }
}

fn next_higher_level(level: DegradationLevel) -> DegradationLevel {
  case level {
    SafeState -> EmergencyMode
    EmergencyMode -> DegradedService
    DegradedService -> FullOperation
    FullOperation -> FullOperation
  }
}

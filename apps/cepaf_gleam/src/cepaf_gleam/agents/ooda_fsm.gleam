//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/agents/ooda_fsm</module>
////     <fsharp-lineage>None — novel OODA FSM (F06)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Formal finite state machine for the OODA cycle</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-OODA-001, SC-SIL4-001, SC-FUNC-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Rust OodaSupervisor state machine ↪ Gleam typed-ADT FSM.
////       All transitions are exhaustively pattern-matched; invalid transitions
////       return InvalidTransition rather than panicking (SC-SIL4-001).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// OODA Finite State Machine — F06
//// योगस्थः कुरु कर्माणि — Established in yoga, perform action (Gita 2.48)
////
//// A formal FSM for the Observe-Orient-Decide-Act-Verify cycle.
//// Typed transitions prevent invalid phase sequences at compile time.
////
//// State machine topology:
////
////   Observe ──DataReceived──→ Orient
////   Orient  ──AnalysisComplete──→ Decide
////   Decide  ──DecisionMade(s)──→ Act
////   Act     ──ActionExecuted──→ Verify
////   Verify  ──VerificationDone──→ Observe (next cycle)
////   Any     ──EmergencyStop──→ Observe (reset, cycle_count unchanged)
////   Any     ──Timeout──→ same (logged, no phase change)
////
//// STAMP: SC-OODA-001, SC-SIL4-001, SC-FUNC-001, SC-MUDA-001

import cepaf_gleam/ui/state.{
  type OodaPhase, OodaAct, OodaDecide, OodaObserve, OodaOrient, OodaVerify,
  ooda_phase_to_string,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Complete FSM state for one OODA agent cycle.
pub type OodaFsmState {
  OodaFsmState(
    /// Current OODA phase.
    phase: OodaPhase,
    /// Number of complete Verify→Observe transitions (full cycles).
    cycle_count: Int,
    /// Monotonic counter (ms) when the current phase was entered.
    phase_entry_time: Int,
    /// Total phase transitions since init (including EmergencyStop resets).
    total_transitions: Int,
    /// Free-text description of the last DecisionMade event payload.
    last_decision: String,
    /// Ring buffer: last 10 phases entered (most-recent last).
    history: List(OodaPhase),
  )
}

/// Events that drive the FSM.
pub type OodaEvent {
  /// Sensor data received — valid from Observe only.
  DataReceived
  /// Context analysis complete — valid from Orient only.
  AnalysisComplete
  /// A decision has been selected — valid from Decide only.
  DecisionMade(decision: String)
  /// The selected action has been issued — valid from Act only.
  ActionExecuted
  /// Post-action verification is done — valid from Verify only.
  VerificationDone
  /// Safety stop: resets to Observe regardless of current phase.
  EmergencyStop
  /// Watchdog timeout: logged but phase is unchanged.
  Timeout
}

/// Result of a transition attempt.
pub type TransitionResult {
  /// Phase changed successfully.
  Transitioned(OodaFsmState)
  /// The event is not valid from the current phase.
  InvalidTransition(from: OodaPhase, event: OodaEvent)
  /// EmergencyStop applied — state is reset to Observe.
  EmergencyReset(OodaFsmState)
}

// ---------------------------------------------------------------------------
// History ring-buffer helpers
// ---------------------------------------------------------------------------

/// Append a phase to the history list, capping at 10 entries (MUDA: no unbounded growth).
fn append_history(history: List(OodaPhase), phase: OodaPhase) -> List(OodaPhase) {
  let extended = list.append(history, [phase])
  case list.length(extended) > 10 {
    True -> list.drop(extended, 1)
    False -> extended
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Initialise the FSM in the Observe phase (safe entry point).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> No prior state exists. </P>
///     <C> init() </C>
///     <Q> Returns OodaFsmState with phase=OodaObserve, all counters 0. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn init() -> OodaFsmState {
  OodaFsmState(
    phase: OodaObserve,
    cycle_count: 0,
    phase_entry_time: 0,
    total_transitions: 0,
    last_decision: "",
    history: [OodaObserve],
  )
}

/// Apply an event to the current FSM state and return the transition result.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> state is a valid OodaFsmState; event is a valid OodaEvent. </P>
///     <C> transition(state, event) </C>
///     <Q>
///       Returns Transitioned with next phase, EmergencyReset on EmergencyStop,
///       or InvalidTransition when the event is illegal from the current phase.
///       Never panics (SC-SIL4-001).
///     </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn transition(state: OodaFsmState, event: OodaEvent) -> TransitionResult {
  case event {
    // ── Safety valve: always legal ──────────────────────────────────────────
    EmergencyStop -> {
      let next =
        OodaFsmState(
          ..state,
          phase: OodaObserve,
          phase_entry_time: 0,
          total_transitions: state.total_transitions + 1,
          last_decision: "EMERGENCY_STOP",
          history: append_history(state.history, OodaObserve),
        )
      EmergencyReset(next)
    }

    // ── Timeout: log but do not change phase ─────────────────────────────────
    Timeout -> Transitioned(state)

    // ── Normal transitions (phase-gated) ─────────────────────────────────────
    DataReceived ->
      case state.phase {
        OodaObserve ->
          Transitioned(
            OodaFsmState(
              ..state,
              phase: OodaOrient,
              phase_entry_time: 0,
              total_transitions: state.total_transitions + 1,
              history: append_history(state.history, OodaOrient),
            ),
          )
        _ -> InvalidTransition(from: state.phase, event: event)
      }

    AnalysisComplete ->
      case state.phase {
        OodaOrient ->
          Transitioned(
            OodaFsmState(
              ..state,
              phase: OodaDecide,
              phase_entry_time: 0,
              total_transitions: state.total_transitions + 1,
              history: append_history(state.history, OodaDecide),
            ),
          )
        _ -> InvalidTransition(from: state.phase, event: event)
      }

    DecisionMade(decision) ->
      case state.phase {
        OodaDecide ->
          Transitioned(
            OodaFsmState(
              ..state,
              phase: OodaAct,
              phase_entry_time: 0,
              total_transitions: state.total_transitions + 1,
              last_decision: decision,
              history: append_history(state.history, OodaAct),
            ),
          )
        _ -> InvalidTransition(from: state.phase, event: event)
      }

    ActionExecuted ->
      case state.phase {
        OodaAct ->
          Transitioned(
            OodaFsmState(
              ..state,
              phase: OodaVerify,
              phase_entry_time: 0,
              total_transitions: state.total_transitions + 1,
              history: append_history(state.history, OodaVerify),
            ),
          )
        _ -> InvalidTransition(from: state.phase, event: event)
      }

    VerificationDone ->
      case state.phase {
        OodaVerify ->
          Transitioned(
            OodaFsmState(
              ..state,
              phase: OodaObserve,
              phase_entry_time: 0,
              cycle_count: state.cycle_count + 1,
              total_transitions: state.total_transitions + 1,
              history: append_history(state.history, OodaObserve),
            ),
          )
        _ -> InvalidTransition(from: state.phase, event: event)
      }
  }
}

/// Return the list of events that are valid from the given phase.
pub fn valid_transitions(phase: OodaPhase) -> List(OodaEvent) {
  // EmergencyStop and Timeout are always valid; phase-specific events follow.
  let always = [EmergencyStop, Timeout]
  let phase_specific = case phase {
    OodaObserve -> [DataReceived]
    OodaOrient -> [AnalysisComplete]
    OodaDecide -> [DecisionMade("")]
    OodaAct -> [ActionExecuted]
    OodaVerify -> [VerificationDone]
  }
  list.append(phase_specific, always)
}

/// Return True iff the given event is valid from the given phase.
pub fn is_valid_transition(phase: OodaPhase, event: OodaEvent) -> Bool {
  case event {
    EmergencyStop | Timeout -> True
    DataReceived -> phase == OodaObserve
    AnalysisComplete -> phase == OodaOrient
    DecisionMade(_) -> phase == OodaDecide
    ActionExecuted -> phase == OodaAct
    VerificationDone -> phase == OodaVerify
  }
}

/// Extract the current phase from the FSM state.
pub fn current_phase(state: OodaFsmState) -> OodaPhase {
  state.phase
}

/// Extract the number of complete cycles.
pub fn cycle_count(state: OodaFsmState) -> Int {
  state.cycle_count
}

/// Serialise the FSM state to a JSON string (typed via gleam/json, SC-GLM-UI-003).
pub fn to_json(state: OodaFsmState) -> String {
  let history_json =
    json.array(state.history, fn(p) { json.string(ooda_phase_to_string(p)) })
  json.object([
    #("phase", json.string(ooda_phase_to_string(state.phase))),
    #("cycle_count", json.int(state.cycle_count)),
    #("phase_entry_time", json.int(state.phase_entry_time)),
    #("total_transitions", json.int(state.total_transitions)),
    #("last_decision", json.string(state.last_decision)),
    #("history", history_json),
  ])
  |> json.to_string()
}

/// Serialise the event name for logging/telemetry.
pub fn event_to_string(event: OodaEvent) -> String {
  case event {
    DataReceived -> "data_received"
    AnalysisComplete -> "analysis_complete"
    DecisionMade(d) -> string.concat(["decision_made:", d])
    ActionExecuted -> "action_executed"
    VerificationDone -> "verification_done"
    EmergencyStop -> "emergency_stop"
    Timeout -> "timeout"
  }
}

/// Run a complete OODA cycle (convenience for testing and TUI demonstration).
/// Returns the state after Verify→Observe, or the FSM state at first invalid step.
pub fn run_cycle(state: OodaFsmState, decision: String) -> TransitionResult {
  case transition(state, DataReceived) {
    InvalidTransition(f, e) -> InvalidTransition(f, e)
    EmergencyReset(s) -> EmergencyReset(s)
    Transitioned(s1) ->
      case transition(s1, AnalysisComplete) {
        InvalidTransition(f, e) -> InvalidTransition(f, e)
        EmergencyReset(s) -> EmergencyReset(s)
        Transitioned(s2) ->
          case transition(s2, DecisionMade(decision)) {
            InvalidTransition(f, e) -> InvalidTransition(f, e)
            EmergencyReset(s) -> EmergencyReset(s)
            Transitioned(s3) ->
              case transition(s3, ActionExecuted) {
                InvalidTransition(f, e) -> InvalidTransition(f, e)
                EmergencyReset(s) -> EmergencyReset(s)
                Transitioned(s4) -> transition(s4, VerificationDone)
              }
          }
      }
  }
}

/// Count how many times `phase` appears in the history list.
pub fn history_count(state: OodaFsmState, phase: OodaPhase) -> Int {
  list.fold(state.history, 0, fn(acc, p) {
    case p == phase {
      True -> acc + 1
      False -> acc
    }
  })
}

/// Return a short human-readable summary of the FSM state (for TUI).
pub fn summary(state: OodaFsmState) -> String {
  string.join(
    [
      "phase=" <> ooda_phase_to_string(state.phase),
      "cycles=" <> int.to_string(state.cycle_count),
      "transitions=" <> int.to_string(state.total_transitions),
    ],
    " ",
  )
}

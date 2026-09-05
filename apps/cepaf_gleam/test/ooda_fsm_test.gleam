/// OODA FSM tests — F06
/// SC-OODA-001, SC-SIL4-001
/// 15+ tests covering init, all valid transitions, invalid transitions,
/// EmergencyStop, Timeout, full cycle, history ring, JSON output.
import cepaf_gleam/agents/ooda_fsm.{
  ActionExecuted, AnalysisComplete, DataReceived, DecisionMade, EmergencyReset,
  EmergencyStop, InvalidTransition, Timeout, Transitioned, VerificationDone,
}
import cepaf_gleam/ui/state.{
  OodaAct, OodaDecide, OodaObserve, OodaOrient, OodaVerify,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

pub fn init_phase_is_observe_test() {
  ooda_fsm.init()
  |> ooda_fsm.current_phase()
  |> should.equal(OodaObserve)
}

pub fn init_cycle_count_is_zero_test() {
  ooda_fsm.init()
  |> ooda_fsm.cycle_count()
  |> should.equal(0)
}

pub fn init_total_transitions_zero_test() {
  ooda_fsm.init().total_transitions
  |> should.equal(0)
}

pub fn init_history_contains_observe_test() {
  let h = ooda_fsm.init().history
  h |> should.equal([OodaObserve])
}

// ---------------------------------------------------------------------------
// Single valid transitions
// ---------------------------------------------------------------------------

pub fn observe_to_orient_test() {
  let s = ooda_fsm.init()
  case ooda_fsm.transition(s, DataReceived) {
    Transitioned(next) -> next.phase |> should.equal(OodaOrient)
    _ -> should.fail()
  }
}

pub fn orient_to_decide_test() {
  let s = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(s, DataReceived) {
    Transitioned(n) -> n
    _ -> s
  }
  case ooda_fsm.transition(s1, AnalysisComplete) {
    Transitioned(next) -> next.phase |> should.equal(OodaDecide)
    _ -> should.fail()
  }
}

pub fn decide_to_act_test() {
  let s0 = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(s0, DataReceived) {
    Transitioned(n) -> n
    _ -> s0
  }
  let s2 = case ooda_fsm.transition(s1, AnalysisComplete) {
    Transitioned(n) -> n
    _ -> s1
  }
  case ooda_fsm.transition(s2, DecisionMade("restart_container")) {
    Transitioned(next) -> {
      next.phase |> should.equal(OodaAct)
      next.last_decision |> should.equal("restart_container")
    }
    _ -> should.fail()
  }
}

pub fn act_to_verify_test() {
  let s = run_to_act(ooda_fsm.init())
  case ooda_fsm.transition(s, ActionExecuted) {
    Transitioned(next) -> next.phase |> should.equal(OodaVerify)
    _ -> should.fail()
  }
}

pub fn verify_to_observe_increments_cycle_test() {
  let s = run_to_verify(ooda_fsm.init())
  case ooda_fsm.transition(s, VerificationDone) {
    Transitioned(next) -> {
      next.phase |> should.equal(OodaObserve)
      next.cycle_count |> should.equal(1)
    }
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Invalid transitions
// ---------------------------------------------------------------------------

pub fn invalid_from_observe_analysis_test() {
  let s = ooda_fsm.init()
  case ooda_fsm.transition(s, AnalysisComplete) {
    InvalidTransition(from, _) -> from |> should.equal(OodaObserve)
    _ -> should.fail()
  }
}

pub fn invalid_from_orient_data_received_test() {
  let s = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(s, DataReceived) {
    Transitioned(n) -> n
    _ -> s
  }
  case ooda_fsm.transition(s1, DataReceived) {
    InvalidTransition(from, _) -> from |> should.equal(OodaOrient)
    _ -> should.fail()
  }
}

pub fn invalid_from_act_analysis_complete_test() {
  let s = run_to_act(ooda_fsm.init())
  case ooda_fsm.transition(s, AnalysisComplete) {
    InvalidTransition(from, _) -> from |> should.equal(OodaAct)
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// EmergencyStop
// ---------------------------------------------------------------------------

pub fn emergency_stop_from_observe_resets_test() {
  let s = ooda_fsm.init()
  case ooda_fsm.transition(s, EmergencyStop) {
    EmergencyReset(next) -> {
      next.phase |> should.equal(OodaObserve)
      next.last_decision |> should.equal("EMERGENCY_STOP")
    }
    _ -> should.fail()
  }
}

pub fn emergency_stop_from_act_resets_test() {
  let s = run_to_act(ooda_fsm.init())
  case ooda_fsm.transition(s, EmergencyStop) {
    EmergencyReset(next) -> next.phase |> should.equal(OodaObserve)
    _ -> should.fail()
  }
}

pub fn emergency_stop_increments_total_transitions_test() {
  let s = ooda_fsm.init()
  case ooda_fsm.transition(s, EmergencyStop) {
    EmergencyReset(next) -> next.total_transitions |> should.equal(1)
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Timeout
// ---------------------------------------------------------------------------

pub fn timeout_does_not_change_phase_test() {
  let s = ooda_fsm.init()
  case ooda_fsm.transition(s, Timeout) {
    Transitioned(next) -> next.phase |> should.equal(OodaObserve)
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Full cycle
// ---------------------------------------------------------------------------

pub fn run_cycle_increments_cycle_count_test() {
  let s = ooda_fsm.init()
  case ooda_fsm.run_cycle(s, "scale_up") {
    Transitioned(next) -> {
      next.cycle_count |> should.equal(1)
      next.phase |> should.equal(OodaObserve)
    }
    _ -> should.fail()
  }
}

pub fn two_full_cycles_test() {
  let s0 = ooda_fsm.init()
  let s1 = case ooda_fsm.run_cycle(s0, "cycle_1") {
    Transitioned(n) -> n
    _ -> s0
  }
  case ooda_fsm.run_cycle(s1, "cycle_2") {
    Transitioned(next) -> {
      next.cycle_count |> should.equal(2)
      next.last_decision |> should.equal("cycle_2")
    }
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------------
// Valid transition guard
// ---------------------------------------------------------------------------

pub fn is_valid_data_received_from_observe_test() {
  ooda_fsm.is_valid_transition(OodaObserve, DataReceived)
  |> should.be_true()
}

pub fn is_invalid_data_received_from_orient_test() {
  ooda_fsm.is_valid_transition(OodaOrient, DataReceived)
  |> should.be_false()
}

pub fn emergency_stop_always_valid_test() {
  ooda_fsm.is_valid_transition(OodaAct, EmergencyStop)
  |> should.be_true()
}

pub fn timeout_always_valid_test() {
  ooda_fsm.is_valid_transition(OodaDecide, Timeout)
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// JSON output
// ---------------------------------------------------------------------------

pub fn to_json_contains_phase_test() {
  let j = ooda_fsm.init() |> ooda_fsm.to_json()
  j |> string.contains("observe") |> should.be_true()
}

pub fn to_json_contains_cycle_count_test() {
  let j = ooda_fsm.init() |> ooda_fsm.to_json()
  j |> string.contains("cycle_count") |> should.be_true()
}

// ---------------------------------------------------------------------------
// History ring buffer
// ---------------------------------------------------------------------------

pub fn history_capped_at_ten_test() {
  // Run 11 full cycles — history should not exceed 10 entries.
  let s = run_n_cycles(ooda_fsm.init(), 11)
  // History grows by 5 per cycle (orient,decide,act,verify,observe) + initial [observe].
  // The ring-buffer cap keeps it at most 10.
  let h_len = list.length(s.history)
  { h_len <= 10 } |> should.be_true()
}

pub fn history_count_observe_after_two_cycles_test() {
  let s = run_n_cycles(ooda_fsm.init(), 2)
  // Observe phase appears at the start and after each VerificationDone.
  { ooda_fsm.history_count(s, OodaObserve) >= 1 } |> should.be_true()
}

// ---------------------------------------------------------------------------
// Summary helper
// ---------------------------------------------------------------------------

pub fn summary_contains_phase_test() {
  let s = ooda_fsm.init()
  ooda_fsm.summary(s) |> string.contains("observe") |> should.be_true()
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn run_to_act(s: ooda_fsm.OodaFsmState) -> ooda_fsm.OodaFsmState {
  let s1 = case ooda_fsm.transition(s, DataReceived) {
    Transitioned(n) -> n
    _ -> s
  }
  let s2 = case ooda_fsm.transition(s1, AnalysisComplete) {
    Transitioned(n) -> n
    _ -> s1
  }
  case ooda_fsm.transition(s2, DecisionMade("test")) {
    Transitioned(n) -> n
    _ -> s2
  }
}

fn run_to_verify(s: ooda_fsm.OodaFsmState) -> ooda_fsm.OodaFsmState {
  case ooda_fsm.transition(run_to_act(s), ActionExecuted) {
    Transitioned(n) -> n
    _ -> run_to_act(s)
  }
}

fn run_n_cycles(s: ooda_fsm.OodaFsmState, n: Int) -> ooda_fsm.OodaFsmState {
  case n <= 0 {
    True -> s
    False ->
      case ooda_fsm.run_cycle(s, "auto") {
        Transitioned(next) -> run_n_cycles(next, n - 1)
        _ -> s
      }
  }
}

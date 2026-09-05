// Agents coverage test — SC-ARCH-SPLIT-002
// Tests ooda_fsm FSM transitions and cybernetic AgentLevel hierarchy
// using verified public API from each module.

import cepaf_gleam/agents/cybernetic
import cepaf_gleam/agents/ooda_fsm
import cepaf_gleam/ui/state.{
  OodaAct, OodaDecide, OodaObserve, OodaOrient, OodaVerify,
}
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── ooda_fsm init ─────────────────────────────────────────────────────────────

pub fn ooda_fsm_init_phase_observe_test() {
  let state = ooda_fsm.init()
  ooda_fsm.current_phase(state) |> should.equal(OodaObserve)
}

pub fn ooda_fsm_init_cycle_count_zero_test() {
  let state = ooda_fsm.init()
  ooda_fsm.cycle_count(state) |> should.equal(0)
}

pub fn ooda_fsm_init_total_transitions_zero_test() {
  let state = ooda_fsm.init()
  state.total_transitions |> should.equal(0)
}

pub fn ooda_fsm_init_last_decision_empty_test() {
  let state = ooda_fsm.init()
  state.last_decision |> should.equal("")
}

pub fn ooda_fsm_init_history_has_observe_test() {
  let state = ooda_fsm.init()
  ooda_fsm.history_count(state, OodaObserve) |> should.equal(1)
}

// ── ooda_fsm transitions ──────────────────────────────────────────────────────

pub fn ooda_fsm_data_received_from_observe_test() {
  let state = ooda_fsm.init()
  case ooda_fsm.transition(state, ooda_fsm.DataReceived) {
    ooda_fsm.Transitioned(s) ->
      ooda_fsm.current_phase(s) |> should.equal(OodaOrient)
    _ -> should.fail()
  }
}

pub fn ooda_fsm_analysis_complete_from_orient_test() {
  let state = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(state, ooda_fsm.DataReceived) {
    ooda_fsm.Transitioned(s) -> s
    _ -> state
  }
  case ooda_fsm.transition(s1, ooda_fsm.AnalysisComplete) {
    ooda_fsm.Transitioned(s) ->
      ooda_fsm.current_phase(s) |> should.equal(OodaDecide)
    _ -> should.fail()
  }
}

pub fn ooda_fsm_decision_made_from_decide_test() {
  let state = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(state, ooda_fsm.DataReceived) {
    ooda_fsm.Transitioned(s) -> s
    _ -> state
  }
  let s2 = case ooda_fsm.transition(s1, ooda_fsm.AnalysisComplete) {
    ooda_fsm.Transitioned(s) -> s
    _ -> s1
  }
  case ooda_fsm.transition(s2, ooda_fsm.DecisionMade("restart")) {
    ooda_fsm.Transitioned(s) -> {
      ooda_fsm.current_phase(s) |> should.equal(OodaAct)
      s.last_decision |> should.equal("restart")
    }
    _ -> should.fail()
  }
}

pub fn ooda_fsm_action_executed_from_act_test() {
  let state = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(state, ooda_fsm.DataReceived) {
    ooda_fsm.Transitioned(s) -> s
    _ -> state
  }
  let s2 = case ooda_fsm.transition(s1, ooda_fsm.AnalysisComplete) {
    ooda_fsm.Transitioned(s) -> s
    _ -> s1
  }
  let s3 = case ooda_fsm.transition(s2, ooda_fsm.DecisionMade("go")) {
    ooda_fsm.Transitioned(s) -> s
    _ -> s2
  }
  case ooda_fsm.transition(s3, ooda_fsm.ActionExecuted) {
    ooda_fsm.Transitioned(s) ->
      ooda_fsm.current_phase(s) |> should.equal(OodaVerify)
    _ -> should.fail()
  }
}

pub fn ooda_fsm_verification_done_increments_cycle_test() {
  let state = ooda_fsm.init()
  case ooda_fsm.run_cycle(state, "NoAction") {
    ooda_fsm.Transitioned(s) -> {
      ooda_fsm.cycle_count(s) |> should.equal(1)
      ooda_fsm.current_phase(s) |> should.equal(OodaObserve)
    }
    _ -> should.fail()
  }
}

pub fn ooda_fsm_two_cycles_test() {
  let state = ooda_fsm.init()
  let s1 = case ooda_fsm.run_cycle(state, "NoAction") {
    ooda_fsm.Transitioned(s) -> s
    _ -> state
  }
  case ooda_fsm.run_cycle(s1, "Restart") {
    ooda_fsm.Transitioned(s) -> ooda_fsm.cycle_count(s) |> should.equal(2)
    _ -> should.fail()
  }
}

// ── ooda_fsm invalid transitions ─────────────────────────────────────────────

pub fn ooda_fsm_analysis_complete_from_observe_invalid_test() {
  let state = ooda_fsm.init()
  case ooda_fsm.transition(state, ooda_fsm.AnalysisComplete) {
    ooda_fsm.InvalidTransition(from: OodaObserve, event: _) ->
      should.be_true(True)
    _ -> should.fail()
  }
}

pub fn ooda_fsm_data_received_from_orient_invalid_test() {
  let state = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(state, ooda_fsm.DataReceived) {
    ooda_fsm.Transitioned(s) -> s
    _ -> state
  }
  case ooda_fsm.transition(s1, ooda_fsm.DataReceived) {
    ooda_fsm.InvalidTransition(from: OodaOrient, event: _) ->
      should.be_true(True)
    _ -> should.fail()
  }
}

// ── ooda_fsm emergency stop ───────────────────────────────────────────────────

pub fn ooda_fsm_emergency_stop_from_orient_test() {
  let state = ooda_fsm.init()
  let s1 = case ooda_fsm.transition(state, ooda_fsm.DataReceived) {
    ooda_fsm.Transitioned(s) -> s
    _ -> state
  }
  case ooda_fsm.transition(s1, ooda_fsm.EmergencyStop) {
    ooda_fsm.EmergencyReset(s) -> {
      ooda_fsm.current_phase(s) |> should.equal(OodaObserve)
      s.last_decision |> should.equal("EMERGENCY_STOP")
    }
    _ -> should.fail()
  }
}

pub fn ooda_fsm_emergency_stop_from_observe_test() {
  let state = ooda_fsm.init()
  case ooda_fsm.transition(state, ooda_fsm.EmergencyStop) {
    ooda_fsm.EmergencyReset(s) ->
      ooda_fsm.current_phase(s) |> should.equal(OodaObserve)
    _ -> should.fail()
  }
}

// ── ooda_fsm timeout ──────────────────────────────────────────────────────────

pub fn ooda_fsm_timeout_does_not_change_phase_test() {
  let state = ooda_fsm.init()
  case ooda_fsm.transition(state, ooda_fsm.Timeout) {
    ooda_fsm.Transitioned(s) ->
      ooda_fsm.current_phase(s) |> should.equal(OodaObserve)
    _ -> should.fail()
  }
}

// ── ooda_fsm is_valid_transition ──────────────────────────────────────────────

pub fn ooda_fsm_is_valid_data_received_from_observe_test() {
  ooda_fsm.is_valid_transition(OodaObserve, ooda_fsm.DataReceived)
  |> should.equal(True)
}

pub fn ooda_fsm_is_valid_data_received_from_orient_false_test() {
  ooda_fsm.is_valid_transition(OodaOrient, ooda_fsm.DataReceived)
  |> should.equal(False)
}

pub fn ooda_fsm_is_valid_emergency_stop_always_test() {
  ooda_fsm.is_valid_transition(OodaDecide, ooda_fsm.EmergencyStop)
  |> should.equal(True)
}

pub fn ooda_fsm_is_valid_timeout_always_test() {
  ooda_fsm.is_valid_transition(OodaAct, ooda_fsm.Timeout)
  |> should.equal(True)
}

pub fn ooda_fsm_is_valid_analysis_from_orient_test() {
  ooda_fsm.is_valid_transition(OodaOrient, ooda_fsm.AnalysisComplete)
  |> should.equal(True)
}

pub fn ooda_fsm_is_valid_verification_done_from_verify_test() {
  ooda_fsm.is_valid_transition(OodaVerify, ooda_fsm.VerificationDone)
  |> should.equal(True)
}

// ── ooda_fsm event_to_string ─────────────────────────────────────────────────

pub fn ooda_fsm_event_to_string_data_received_test() {
  ooda_fsm.event_to_string(ooda_fsm.DataReceived)
  |> should.equal("data_received")
}

pub fn ooda_fsm_event_to_string_analysis_complete_test() {
  ooda_fsm.event_to_string(ooda_fsm.AnalysisComplete)
  |> should.equal("analysis_complete")
}

pub fn ooda_fsm_event_to_string_decision_made_test() {
  let s = ooda_fsm.event_to_string(ooda_fsm.DecisionMade("restart"))
  should.be_true(string.contains(s, "restart"))
}

pub fn ooda_fsm_event_to_string_action_executed_test() {
  ooda_fsm.event_to_string(ooda_fsm.ActionExecuted)
  |> should.equal("action_executed")
}

pub fn ooda_fsm_event_to_string_verification_done_test() {
  ooda_fsm.event_to_string(ooda_fsm.VerificationDone)
  |> should.equal("verification_done")
}

pub fn ooda_fsm_event_to_string_emergency_stop_test() {
  ooda_fsm.event_to_string(ooda_fsm.EmergencyStop)
  |> should.equal("emergency_stop")
}

pub fn ooda_fsm_event_to_string_timeout_test() {
  ooda_fsm.event_to_string(ooda_fsm.Timeout)
  |> should.equal("timeout")
}

// ── ooda_fsm to_json ──────────────────────────────────────────────────────────

pub fn ooda_fsm_to_json_contains_phase_test() {
  let state = ooda_fsm.init()
  let j = ooda_fsm.to_json(state)
  should.be_true(string.contains(j, "phase"))
}

pub fn ooda_fsm_to_json_contains_cycle_count_test() {
  let state = ooda_fsm.init()
  let j = ooda_fsm.to_json(state)
  should.be_true(string.contains(j, "cycle_count"))
}

// ── ooda_fsm summary ─────────────────────────────────────────────────────────

pub fn ooda_fsm_summary_contains_phase_test() {
  let state = ooda_fsm.init()
  let s = ooda_fsm.summary(state)
  should.be_true(string.contains(s, "phase="))
}

pub fn ooda_fsm_summary_contains_cycles_test() {
  let state = ooda_fsm.init()
  let s = ooda_fsm.summary(state)
  should.be_true(string.contains(s, "cycles="))
}

// ── cybernetic AgentLevel types ───────────────────────────────────────────────

pub fn cybernetic_agent_level_executive_test() {
  let level: cybernetic.AgentLevel = cybernetic.Executive
  level |> should.equal(cybernetic.Executive)
}

pub fn cybernetic_agent_level_domain_supervisor_test() {
  let level: cybernetic.AgentLevel = cybernetic.DomainSupervisor
  level |> should.equal(cybernetic.DomainSupervisor)
}

pub fn cybernetic_agent_level_functional_supervisor_test() {
  let level: cybernetic.AgentLevel = cybernetic.FunctionalSupervisor
  level |> should.equal(cybernetic.FunctionalSupervisor)
}

pub fn cybernetic_agent_level_worker_test() {
  let level: cybernetic.AgentLevel = cybernetic.Worker
  level |> should.equal(cybernetic.Worker)
}

// ── cybernetic ServiceRole types ──────────────────────────────────────────────

pub fn cybernetic_service_role_cortex_test() {
  let role: cybernetic.ServiceRole = cybernetic.Cortex
  role |> should.equal(cybernetic.Cortex)
}

pub fn cybernetic_service_role_prajna_test() {
  let role: cybernetic.ServiceRole = cybernetic.Prajna
  role |> should.equal(cybernetic.Prajna)
}

pub fn cybernetic_service_role_smriti_test() {
  let role: cybernetic.ServiceRole = cybernetic.Smriti
  role |> should.equal(cybernetic.Smriti)
}

pub fn cybernetic_service_role_guardian_test() {
  let role: cybernetic.ServiceRole = cybernetic.Guardian
  role |> should.equal(cybernetic.Guardian)
}

pub fn cybernetic_service_role_generic_worker_test() {
  let role: cybernetic.ServiceRole = cybernetic.GenericWorker
  role |> should.equal(cybernetic.GenericWorker)
}

// ── cybernetic AgentStatus types ─────────────────────────────────────────────

pub fn cybernetic_agent_status_idle_test() {
  let status: cybernetic.AgentStatus = cybernetic.Idle
  status |> should.equal(cybernetic.Idle)
}

pub fn cybernetic_agent_status_active_test() {
  let cybernetic.AgentActive(t) = cybernetic.AgentActive("compute task")
  t |> should.equal("compute task")
}

pub fn cybernetic_agent_status_blocked_test() {
  let cybernetic.AgentBlocked(r) = cybernetic.AgentBlocked("waiting for lock")
  r |> should.equal("waiting for lock")
}

// ── cybernetic AgentState construction ───────────────────────────────────────

pub fn cybernetic_agent_state_construction_test() {
  let state =
    cybernetic.AgentState(
      id: "agent-001",
      name: "Test Agent",
      level: cybernetic.Worker,
      role: cybernetic.GenericWorker,
      domain: "testing",
      status: cybernetic.Idle,
    )
  state.id |> should.equal("agent-001")
  state.name |> should.equal("Test Agent")
  state.domain |> should.equal("testing")
}

pub fn cybernetic_agent_state_level_test() {
  let state =
    cybernetic.AgentState(
      id: "exec-001",
      name: "Executive",
      level: cybernetic.Executive,
      role: cybernetic.Cortex,
      domain: "cognitive",
      status: cybernetic.Idle,
    )
  state.level |> should.equal(cybernetic.Executive)
}

// ── cybernetic AgentHierarchy ─────────────────────────────────────────────────

pub fn cybernetic_initialize_hierarchy_test() {
  let h = cybernetic.initialize_hierarchy()
  h.root_id |> should.equal("none")
}

pub fn cybernetic_get_all_agents_empty_test() {
  let h = cybernetic.initialize_hierarchy()
  cybernetic.get_all_agents(h) |> should.equal([])
}

pub fn cybernetic_verify_executive_authority_test() {
  let h = cybernetic.initialize_hierarchy()
  cybernetic.verify_executive_authority(h) |> should.equal(True)
}

pub fn cybernetic_check_efficiency_compliance_test() {
  let h = cybernetic.initialize_hierarchy()
  cybernetic.check_efficiency_compliance(h) |> should.equal(True)
}

pub fn cybernetic_detect_deadlock_test() {
  let h = cybernetic.initialize_hierarchy()
  cybernetic.detect_deadlock(h) |> should.equal(False)
}

pub fn cybernetic_get_count_by_level_zero_test() {
  let h = cybernetic.initialize_hierarchy()
  cybernetic.get_count_by_level(h, cybernetic.Worker) |> should.equal(0)
}

// ── cybernetic CyberAgent types ───────────────────────────────────────────────

pub fn cybernetic_cyber_agent_construction_test() {
  let agent =
    cybernetic.CyberAgent(
      id: "ca-001",
      name: "Test CyberAgent",
      level: cybernetic.DomainSupervisor,
      domain: "planning",
      status: cybernetic.Idle,
      efficiency: 0.92,
      parent_id: option.None,
    )
  agent.id |> should.equal("ca-001")
  agent.level |> should.equal(cybernetic.DomainSupervisor)
}

pub fn cybernetic_cyber_agent_with_parent_test() {
  let agent =
    cybernetic.CyberAgent(
      id: "ca-002",
      name: "Child Agent",
      level: cybernetic.Worker,
      domain: "cepaf",
      status: cybernetic.AgentActive("processing"),
      efficiency: 0.85,
      parent_id: option.Some("exec-001"),
    )
  agent.parent_id |> should.equal(option.Some("exec-001"))
}

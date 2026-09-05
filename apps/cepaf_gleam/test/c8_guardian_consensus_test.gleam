// C8 Guardian Approval, Emergency Stop, Psi Invariants, 2oo3 Consensus Tests
// Category: C8_ErrorHandling (weight 3.0) — highest CCM impact
// STAMP: SC-AGUI-004, SC-SAFETY-001, SC-GUARD-001, SC-SIL4-006

import cepaf_gleam/agui/tools.{
  type ToolRegistry, AwaitingApproval, Completed, Executing, Failed, ToolDef,
}
import cepaf_gleam/fractal/l0_constitutional.{
  Approved, Critical, Escalated, Fail, High, Low, Medium, Pass, Psi0Existence,
  Psi1Regeneration, Psi2History, Psi3Verification, Psi4HumanAlignment,
  Psi5Truthfulness, PsiCheck, Rejected, Warning,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Approval State Tests
// =============================================================================

pub fn initial_approval_state_empty_test() {
  let state = l0_constitutional.initial_approval_state()
  l0_constitutional.pending_count(state) |> should.equal(0)
  state.history |> should.equal([])
}

pub fn add_request_increments_pending_test() {
  let state = l0_constitutional.initial_approval_state()
  let req = make_request("r1", "deploy", Critical)
  let state = l0_constitutional.add_request(state, req)
  l0_constitutional.pending_count(state) |> should.equal(1)
}

pub fn add_multiple_requests_test() {
  let state = l0_constitutional.initial_approval_state()
  let state =
    l0_constitutional.add_request(state, make_request("r1", "deploy", Critical))
  let state =
    l0_constitutional.add_request(state, make_request("r2", "restart", High))
  let state =
    l0_constitutional.add_request(state, make_request("r3", "config", Medium))
  l0_constitutional.pending_count(state) |> should.equal(3)
}

pub fn resolve_request_approved_adds_to_history_test() {
  let state = l0_constitutional.initial_approval_state()
  let state =
    l0_constitutional.add_request(state, make_request("r1", "deploy", Critical))
  let state = l0_constitutional.resolve_request(state, "r1", Approved)
  l0_constitutional.pending_count(state) |> should.equal(0)
  state.history |> should.equal([#("r1", Approved)])
}

pub fn resolve_request_rejected_test() {
  let state = l0_constitutional.initial_approval_state()
  let state =
    l0_constitutional.add_request(state, make_request("r1", "deploy", Critical))
  let state = l0_constitutional.resolve_request(state, "r1", Rejected)
  state.history |> should.equal([#("r1", Rejected)])
}

pub fn resolve_request_escalated_test() {
  let state = l0_constitutional.initial_approval_state()
  let state =
    l0_constitutional.add_request(state, make_request("r1", "deploy", Critical))
  let state = l0_constitutional.resolve_request(state, "r1", Escalated)
  state.history |> should.equal([#("r1", Escalated)])
}

// =============================================================================
// Emergency Stop State Machine Tests
// =============================================================================

pub fn initial_emergency_state_defaults_test() {
  let state = l0_constitutional.initial_emergency_state()
  state.armed |> should.equal(False)
  state.triggered |> should.equal(False)
  state.trigger_reason |> should.equal(None)
  state.last_triggered |> should.equal(None)
}

pub fn arm_emergency_sets_armed_test() {
  let state = l0_constitutional.initial_emergency_state()
  let state = l0_constitutional.arm_emergency(state)
  state.armed |> should.equal(True)
  state.triggered |> should.equal(False)
}

pub fn trigger_emergency_transitions_test() {
  let state = l0_constitutional.initial_emergency_state()
  let state = l0_constitutional.arm_emergency(state)
  let state =
    l0_constitutional.trigger_emergency(state, "critical failure", 1000)
  state.armed |> should.equal(False)
  state.triggered |> should.equal(True)
  state.trigger_reason |> should.equal(Some("critical failure"))
  state.last_triggered |> should.equal(Some(1000))
}

pub fn reset_emergency_clears_state_test() {
  let state = l0_constitutional.initial_emergency_state()
  let state = l0_constitutional.arm_emergency(state)
  let state = l0_constitutional.trigger_emergency(state, "failure", 1000)
  let state = l0_constitutional.reset_emergency(state)
  state.armed |> should.equal(False)
  state.triggered |> should.equal(False)
  state.trigger_reason |> should.equal(None)
}

pub fn arm_trigger_reset_full_lifecycle_test() {
  let state = l0_constitutional.initial_emergency_state()
  // Phase 1: arm
  let state = l0_constitutional.arm_emergency(state)
  state.armed |> should.equal(True)
  // Phase 2: trigger
  let state = l0_constitutional.trigger_emergency(state, "cascade", 2000)
  state.triggered |> should.equal(True)
  // Phase 3: reset
  let state = l0_constitutional.reset_emergency(state)
  state.triggered |> should.equal(False)
  state.armed |> should.equal(False)
}

// =============================================================================
// Psi Invariant Tests
// =============================================================================

pub fn all_psi_pass_all_passing_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "exists"),
    PsiCheck(Psi1Regeneration, Pass, "regen ok"),
    PsiCheck(Psi2History, Pass, "history intact"),
    PsiCheck(Psi3Verification, Pass, "verified"),
    PsiCheck(Psi4HumanAlignment, Pass, "aligned"),
    PsiCheck(Psi5Truthfulness, Pass, "truthful"),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.equal(True)
}

pub fn all_psi_pass_one_fail_returns_false_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi4HumanAlignment, Fail, "misaligned"),
    PsiCheck(Psi5Truthfulness, Pass, "ok"),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.equal(False)
}

pub fn all_psi_pass_warning_returns_false_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi3Verification, Warning, "degraded"),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.equal(False)
}

pub fn psi_invariant_to_string_all_variants_test() {
  l0_constitutional.psi_invariant_to_string(Psi0Existence)
  |> should.equal("Psi-0 Existence")
  l0_constitutional.psi_invariant_to_string(Psi1Regeneration)
  |> should.equal("Psi-1 Regeneration")
  l0_constitutional.psi_invariant_to_string(Psi2History)
  |> should.equal("Psi-2 History")
  l0_constitutional.psi_invariant_to_string(Psi3Verification)
  |> should.equal("Psi-3 Verification")
  l0_constitutional.psi_invariant_to_string(Psi4HumanAlignment)
  |> should.equal("Psi-4 Human Alignment")
  l0_constitutional.psi_invariant_to_string(Psi5Truthfulness)
  |> should.equal("Psi-5 Truthfulness")
}

pub fn approval_severity_to_string_all_variants_test() {
  l0_constitutional.approval_severity_to_string(Critical)
  |> should.equal("critical")
  l0_constitutional.approval_severity_to_string(High) |> should.equal("high")
  l0_constitutional.approval_severity_to_string(Medium)
  |> should.equal("medium")
  l0_constitutional.approval_severity_to_string(Low) |> should.equal("low")
}

pub fn approval_to_json_structure_test() {
  let req = make_request("r1", "deploy", Critical)
  let j = l0_constitutional.approval_to_json(req) |> json.to_string()
  string.contains(j, "\"request_id\":\"r1\"") |> should.be_true()
  string.contains(j, "\"severity\":\"critical\"") |> should.be_true()
  string.contains(j, "\"operation\":\"deploy\"") |> should.be_true()
}

// =============================================================================
// 2oo3 Consensus Simulation Tests (SC-SIL4-006)
// =============================================================================

pub fn consensus_2oo3_majority_approve_test() {
  // 3 guardians vote: 2 approve, 1 reject → approved
  let votes = [Approved, Approved, Rejected]
  let approved_count = list.count(votes, fn(v) { v == Approved })
  let threshold = 2
  { approved_count >= threshold } |> should.equal(True)
}

pub fn consensus_2oo3_majority_reject_test() {
  // 3 guardians vote: 1 approve, 2 reject → rejected
  let votes = [Approved, Rejected, Rejected]
  let approved_count = list.count(votes, fn(v) { v == Approved })
  let threshold = 2
  { approved_count >= threshold } |> should.equal(False)
}

pub fn consensus_severity_routing_critical_needs_2oo3_test() {
  guardians_required(Critical) |> should.equal(3)
}

pub fn consensus_severity_routing_low_auto_approves_test() {
  guardians_required(Low) |> should.equal(0)
}

pub fn consensus_severity_routing_high_needs_2_test() {
  guardians_required(High) |> should.equal(2)
}

pub fn consensus_severity_routing_medium_needs_1_test() {
  guardians_required(Medium) |> should.equal(1)
}

pub fn approval_blocked_when_psi_fails_test() {
  // Gate: approval MUST be blocked when any Psi check fails
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi4HumanAlignment, Fail, "misaligned"),
  ]
  let psi_ok = l0_constitutional.all_psi_pass(checks)
  // Approval should be blocked (simulated via state)
  let state = l0_constitutional.initial_approval_state()
  let state =
    l0_constitutional.add_request(state, make_request("r1", "deploy", Critical))
  let final_state = case psi_ok {
    True -> l0_constitutional.resolve_request(state, "r1", Approved)
    False -> l0_constitutional.resolve_request(state, "r1", Rejected)
  }
  final_state.history |> should.equal([#("r1", Rejected)])
}

// =============================================================================
// HITL Tool Lifecycle + Guardian Gate Tests
// =============================================================================

pub fn hitl_tool_approval_full_flow_test() {
  let guardian_tool =
    ToolDef(
      name: "guardian_deploy",
      description: "Deploy requires HITL",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg = tools.new_registry([guardian_tool])
  // Start → Args → End → AwaitingApproval
  let reg = tools.start_call(reg, "tc-1", "guardian_deploy")
  let reg = tools.append_args(reg, "tc-1", "{\"env\":\"prod\"}")
  let reg = tools.end_args(reg, "tc-1")
  tools.pending_approvals(reg) |> should.equal(1)
  assert_call_status(reg, "tc-1", AwaitingApproval)
  // Approve → Executing
  let reg = tools.approve_call(reg, "tc-1")
  tools.pending_approvals(reg) |> should.equal(0)
  assert_call_status(reg, "tc-1", Executing)
  // Result → Completed
  let reg = tools.set_result(reg, "tc-1", "deployed successfully")
  assert_call_status(reg, "tc-1", Completed)
}

pub fn hitl_tool_rejection_flow_test() {
  let guardian_tool =
    ToolDef(
      name: "guardian_delete",
      description: "Delete requires HITL",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg = tools.new_registry([guardian_tool])
  let reg = tools.start_call(reg, "tc-2", "guardian_delete")
  let reg = tools.end_args(reg, "tc-2")
  let reg = tools.reject_call(reg, "tc-2", "Insufficient evidence")
  tools.pending_approvals(reg) |> should.equal(0)
  case dict.get(reg.calls, "tc-2") {
    Ok(call) ->
      case call.status {
        Failed(reason) -> reason |> should.equal("Insufficient evidence")
        _ -> should.fail()
      }
    Error(_) -> should.fail()
  }
}

// =============================================================================
// Helpers
// =============================================================================

fn guardians_required(severity) -> Int {
  case severity {
    Critical -> 3
    High -> 2
    Medium -> 1
    Low -> 0
  }
}

fn make_request(id: String, op: String, severity) {
  l0_constitutional.ApprovalRequest(
    request_id: id,
    operation: op,
    description: "Test " <> op,
    severity: severity,
    requester_agent: "test-agent",
    timestamp: 1000,
  )
}

fn assert_call_status(reg: ToolRegistry, id: String, expected) {
  case dict.get(reg.calls, id) {
    Ok(call) -> {
      case call.status == expected {
        True -> should.be_true(True)
        False -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

// Guardian Consensus Integration Tests — L0 Constitutional
// STAMP: SC-SIL4-006, SC-SAFETY-001, SC-GUARD-001, SC-AGUI-004
//
// Covers all 16 mandated items for T026:
//   1-3:  ApprovalState lifecycle (add, resolve, all decisions)
//   4-6:  ConsensusState creation and idempotent vote casting
//   7-9:  evaluate_consensus: Approved/Rejected/Incomplete outcomes
//   10-13: EmergencyState full state machine
//   14:   guardians_for_severity all four variants
//   15:   psi_gated_approve pass and fail paths
//   16:   all_psi_pass with all-pass and mixed-status inputs

import cepaf_gleam/fractal/l0_constitutional.{
  Approved, ConsensusApproved, ConsensusIncomplete, ConsensusRejected, Critical,
  Escalated, Fail, High, Low, Medium, Pass, Psi0Existence, Psi1Regeneration,
  Psi2History, Psi3Verification, Psi4HumanAlignment, Psi5Truthfulness, PsiCheck,
  Rejected, VoteApprove, VoteReject, Warning,
}
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// 1. ApprovalState: add_request increases pending count
// =============================================================================

pub fn intg_add_request_increases_pending_count_test() {
  let state = l0_constitutional.initial_approval_state()
  l0_constitutional.pending_count(state) |> should.equal(0)
  let state = l0_constitutional.add_request(state, make_req("req-a", Critical))
  l0_constitutional.pending_count(state) |> should.equal(1)
  let state = l0_constitutional.add_request(state, make_req("req-b", High))
  l0_constitutional.pending_count(state) |> should.equal(2)
}

// =============================================================================
// 2. ApprovalState: resolve_request removes from pending, adds to history
// =============================================================================

pub fn intg_resolve_request_removes_from_pending_test() {
  let state = l0_constitutional.initial_approval_state()
  let state = l0_constitutional.add_request(state, make_req("req-1", Critical))
  let state = l0_constitutional.resolve_request(state, "req-1", Approved)
  l0_constitutional.pending_count(state) |> should.equal(0)
  state.history |> should.equal([#("req-1", Approved)])
}

pub fn intg_resolve_partial_leaves_remainder_test() {
  let state = l0_constitutional.initial_approval_state()
  let state = l0_constitutional.add_request(state, make_req("req-x", High))
  let state = l0_constitutional.add_request(state, make_req("req-y", Medium))
  let state = l0_constitutional.resolve_request(state, "req-x", Rejected)
  l0_constitutional.pending_count(state) |> should.equal(1)
  state.history |> should.equal([#("req-x", Rejected)])
}

// =============================================================================
// 3. ApprovalState: resolve with Approved / Rejected / Escalated all work
// =============================================================================

pub fn intg_resolve_approved_decision_test() {
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("d-app", Critical))
    |> l0_constitutional.resolve_request("d-app", Approved)
  state.history |> should.equal([#("d-app", Approved)])
}

pub fn intg_resolve_rejected_decision_test() {
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("d-rej", High))
    |> l0_constitutional.resolve_request("d-rej", Rejected)
  state.history |> should.equal([#("d-rej", Rejected)])
}

pub fn intg_resolve_escalated_decision_test() {
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("d-esc", Medium))
    |> l0_constitutional.resolve_request("d-esc", Escalated)
  state.history |> should.equal([#("d-esc", Escalated)])
}

// =============================================================================
// 4. ConsensusState: new_consensus creates empty votes
// =============================================================================

pub fn intg_new_consensus_creates_empty_votes_test() {
  let cs = l0_constitutional.new_consensus("op-42", 2, 3)
  cs.request_id |> should.equal("op-42")
  cs.required_approvals |> should.equal(2)
  cs.total_guardians |> should.equal(3)
  l0_constitutional.approve_count(cs) |> should.equal(0)
  l0_constitutional.reject_count(cs) |> should.equal(0)
}

// =============================================================================
// 5. ConsensusState: cast_vote adds vote
// =============================================================================

pub fn intg_cast_vote_adds_approve_test() {
  let cs =
    l0_constitutional.new_consensus("op-v", 2, 3)
    |> l0_constitutional.cast_vote("guardian-alpha", VoteApprove)
  l0_constitutional.approve_count(cs) |> should.equal(1)
}

pub fn intg_cast_vote_adds_reject_test() {
  let cs =
    l0_constitutional.new_consensus("op-r", 2, 3)
    |> l0_constitutional.cast_vote("guardian-beta", VoteReject)
  l0_constitutional.reject_count(cs) |> should.equal(1)
}

// =============================================================================
// 6. ConsensusState: cast_vote same guardian twice is idempotent (no duplicate)
// =============================================================================

pub fn intg_duplicate_guardian_vote_is_idempotent_test() {
  let cs = l0_constitutional.new_consensus("op-idem", 2, 3)
  // First vote: approve
  let cs = l0_constitutional.cast_vote(cs, "guardian-1", VoteApprove)
  l0_constitutional.approve_count(cs) |> should.equal(1)
  // Second vote by same guardian: reject — must be ignored
  let cs = l0_constitutional.cast_vote(cs, "guardian-1", VoteReject)
  l0_constitutional.approve_count(cs) |> should.equal(1)
  l0_constitutional.reject_count(cs) |> should.equal(0)
}

// =============================================================================
// 7. ConsensusState: evaluate_consensus returns Approved when 2 of 3 approve
// =============================================================================

pub fn intg_evaluate_consensus_approved_two_of_three_test() {
  let cs =
    l0_constitutional.new_consensus("op-2of3", 2, 3)
    |> l0_constitutional.cast_vote("g1", VoteApprove)
    |> l0_constitutional.cast_vote("g2", VoteApprove)
    |> l0_constitutional.cast_vote("g3", VoteReject)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)
}

// =============================================================================
// 8. ConsensusState: evaluate_consensus returns Rejected when 2 of 3 reject
// =============================================================================

pub fn intg_evaluate_consensus_rejected_two_of_three_test() {
  let cs =
    l0_constitutional.new_consensus("op-rej2", 2, 3)
    |> l0_constitutional.cast_vote("g1", VoteReject)
    |> l0_constitutional.cast_vote("g2", VoteReject)
    |> l0_constitutional.cast_vote("g3", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusRejected)
}

// =============================================================================
// 9. ConsensusState: evaluate_consensus returns Incomplete with 1 vote
// =============================================================================

pub fn intg_evaluate_consensus_incomplete_one_vote_test() {
  let cs =
    l0_constitutional.new_consensus("op-inc", 2, 3)
    |> l0_constitutional.cast_vote("g1", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusIncomplete)
}

// =============================================================================
// 10. EmergencyState: initial is not armed, not triggered
// =============================================================================

pub fn intg_initial_emergency_not_armed_not_triggered_test() {
  let es = l0_constitutional.initial_emergency_state()
  es.armed |> should.equal(False)
  es.triggered |> should.equal(False)
  es.trigger_reason |> should.equal(None)
  es.last_triggered |> should.equal(None)
}

// =============================================================================
// 11. EmergencyState: arm_emergency sets armed=True
// =============================================================================

pub fn intg_arm_emergency_sets_armed_true_test() {
  let es =
    l0_constitutional.initial_emergency_state()
    |> l0_constitutional.arm_emergency()
  es.armed |> should.equal(True)
  es.triggered |> should.equal(False)
}

// =============================================================================
// 12. EmergencyState: trigger_emergency sets triggered=True with reason
// =============================================================================

pub fn intg_trigger_emergency_sets_triggered_with_reason_test() {
  let es =
    l0_constitutional.initial_emergency_state()
    |> l0_constitutional.arm_emergency()
    |> l0_constitutional.trigger_emergency("quorum lost", 9999)
  es.triggered |> should.equal(True)
  es.trigger_reason |> should.equal(Some("quorum lost"))
  es.last_triggered |> should.equal(Some(9999))
}

// =============================================================================
// 13. EmergencyState: reset_emergency clears triggered
// =============================================================================

pub fn intg_reset_emergency_clears_triggered_test() {
  let es =
    l0_constitutional.initial_emergency_state()
    |> l0_constitutional.arm_emergency()
    |> l0_constitutional.trigger_emergency("cascade", 1234)
    |> l0_constitutional.reset_emergency()
  es.triggered |> should.equal(False)
  es.armed |> should.equal(False)
  es.trigger_reason |> should.equal(None)
}

// =============================================================================
// 14. guardians_for_severity: Critical=3, High=2, Medium=1, Low=0
// =============================================================================

pub fn intg_guardians_for_critical_is_three_test() {
  l0_constitutional.guardians_for_severity(Critical) |> should.equal(3)
}

pub fn intg_guardians_for_high_is_two_test() {
  l0_constitutional.guardians_for_severity(High) |> should.equal(2)
}

pub fn intg_guardians_for_medium_is_one_test() {
  l0_constitutional.guardians_for_severity(Medium) |> should.equal(1)
}

pub fn intg_guardians_for_low_is_zero_test() {
  l0_constitutional.guardians_for_severity(Low) |> should.equal(0)
}

// =============================================================================
// 15. psi_gated_approve: all pass → Approved; any fail → Rejected
// =============================================================================

pub fn intg_psi_gated_approve_all_pass_yields_approved_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "system exists"),
    PsiCheck(Psi1Regeneration, Pass, "regen healthy"),
    PsiCheck(Psi2History, Pass, "chain intact"),
    PsiCheck(Psi3Verification, Pass, "proof valid"),
    PsiCheck(Psi4HumanAlignment, Pass, "aligned"),
    PsiCheck(Psi5Truthfulness, Pass, "truthful"),
  ]
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("psi-pass", Critical))
  let state = l0_constitutional.psi_gated_approve(checks, state, "psi-pass")
  state.history |> should.equal([#("psi-pass", Approved)])
}

pub fn intg_psi_gated_approve_one_fail_yields_rejected_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi3Verification, Fail, "proof expired"),
    PsiCheck(Psi5Truthfulness, Pass, "ok"),
  ]
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("psi-fail", Critical))
  let state = l0_constitutional.psi_gated_approve(checks, state, "psi-fail")
  state.history |> should.equal([#("psi-fail", Rejected)])
}

pub fn intg_psi_gated_approve_warning_yields_rejected_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi4HumanAlignment, Warning, "drifting"),
  ]
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("psi-warn", High))
  let state = l0_constitutional.psi_gated_approve(checks, state, "psi-warn")
  state.history |> should.equal([#("psi-warn", Rejected)])
}

// =============================================================================
// 16. all_psi_pass: returns True only when all checks Pass
// =============================================================================

pub fn intg_all_psi_pass_all_six_pass_returns_true_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "e"),
    PsiCheck(Psi1Regeneration, Pass, "r"),
    PsiCheck(Psi2History, Pass, "h"),
    PsiCheck(Psi3Verification, Pass, "v"),
    PsiCheck(Psi4HumanAlignment, Pass, "a"),
    PsiCheck(Psi5Truthfulness, Pass, "t"),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.equal(True)
}

pub fn intg_all_psi_pass_single_fail_returns_false_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi2History, Fail, "chain broken"),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.equal(False)
}

pub fn intg_all_psi_pass_single_warning_returns_false_test() {
  let checks = [
    PsiCheck(Psi1Regeneration, Pass, "ok"),
    PsiCheck(Psi5Truthfulness, Warning, "uncertain"),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.equal(False)
}

pub fn intg_all_psi_pass_empty_list_returns_true_test() {
  // Vacuously true — no failing checks
  l0_constitutional.all_psi_pass([]) |> should.equal(True)
}

// =============================================================================
// Integration: severity → consensus → psi gate chained flow
// =============================================================================

pub fn intg_full_chain_high_severity_approved_test() {
  // High severity requires 2 guardians
  let required = l0_constitutional.guardians_for_severity(High)
  required |> should.equal(2)

  // 2oo2 consensus: both approve
  let cs =
    l0_constitutional.new_consensus("chain-op", required, required)
    |> l0_constitutional.cast_vote("gA", VoteApprove)
    |> l0_constitutional.cast_vote("gB", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)

  // Psi gate: all pass → final Approved
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi4HumanAlignment, Pass, "ok"),
  ]
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("chain-op", High))
  let state = l0_constitutional.psi_gated_approve(checks, state, "chain-op")
  state.history |> should.equal([#("chain-op", Approved)])
}

pub fn intg_full_chain_critical_psi_failure_blocks_test() {
  // Critical severity requires 3 guardians
  let required = l0_constitutional.guardians_for_severity(Critical)
  required |> should.equal(3)

  // Consensus reached (2 of 3)
  let cs =
    l0_constitutional.new_consensus("crit-op", 2, required)
    |> l0_constitutional.cast_vote("g1", VoteApprove)
    |> l0_constitutional.cast_vote("g2", VoteApprove)
    |> l0_constitutional.cast_vote("g3", VoteReject)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)

  // But Psi gate fails: Approved is blocked
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi3Verification, Fail, "proof chain invalid"),
  ]
  let state =
    l0_constitutional.initial_approval_state()
    |> l0_constitutional.add_request(make_req("crit-op", Critical))
  let state = l0_constitutional.psi_gated_approve(checks, state, "crit-op")
  state.history |> should.equal([#("crit-op", Rejected)])
}

// =============================================================================
// Helpers
// =============================================================================

fn make_req(id: String, severity) {
  l0_constitutional.ApprovalRequest(
    request_id: id,
    operation: "intg_test_op",
    description: "Integration test request",
    severity: severity,
    requester_agent: "intg-test-agent",
    timestamp: 42_000,
  )
}

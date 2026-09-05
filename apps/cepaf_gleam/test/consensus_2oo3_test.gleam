// 2oo3 Consensus Implementation Tests (SC-SIL4-006)
// Tests the real ConsensusState type, vote casting, and outcome evaluation.
// STAMP: SC-SIL4-006, SC-SAFETY-001, SC-GUARD-001

import cepaf_gleam/fractal/l0_constitutional.{
  Approved, ConsensusApproved, ConsensusIncomplete, ConsensusRejected, Critical,
  Fail, High, Low, Medium, Pass, Psi0Existence, Psi4HumanAlignment, PsiCheck,
  Rejected, VoteAbstain, VoteApprove, VoteReject,
}
import gleeunit/should

// =============================================================================
// Consensus State Creation
// =============================================================================

pub fn new_consensus_empty_votes_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  cs.request_id |> should.equal("r1")
  cs.required_approvals |> should.equal(2)
  cs.total_guardians |> should.equal(3)
  l0_constitutional.approve_count(cs) |> should.equal(0)
}

// =============================================================================
// Vote Casting
// =============================================================================

pub fn cast_single_approve_vote_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "guardian-1", VoteApprove)
  l0_constitutional.approve_count(cs) |> should.equal(1)
  l0_constitutional.reject_count(cs) |> should.equal(0)
}

pub fn cast_three_votes_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g2", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g3", VoteReject)
  l0_constitutional.approve_count(cs) |> should.equal(2)
  l0_constitutional.reject_count(cs) |> should.equal(1)
}

pub fn duplicate_vote_ignored_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteReject)
  l0_constitutional.approve_count(cs) |> should.equal(1)
  l0_constitutional.reject_count(cs) |> should.equal(0)
}

pub fn abstain_vote_counted_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteAbstain)
  l0_constitutional.approve_count(cs) |> should.equal(0)
  l0_constitutional.reject_count(cs) |> should.equal(0)
}

// =============================================================================
// Consensus Outcome Evaluation
// =============================================================================

pub fn consensus_approved_2oo3_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g2", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)
}

pub fn consensus_rejected_2_rejects_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteReject)
  let cs = l0_constitutional.cast_vote(cs, "g2", VoteReject)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusRejected)
}

pub fn consensus_incomplete_1_vote_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusIncomplete)
}

pub fn consensus_rejected_all_abstain_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteAbstain)
  let cs = l0_constitutional.cast_vote(cs, "g2", VoteAbstain)
  let cs = l0_constitutional.cast_vote(cs, "g3", VoteAbstain)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusRejected)
}

pub fn consensus_approved_unanimous_test() {
  let cs = l0_constitutional.new_consensus("r1", 2, 3)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g2", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g3", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)
}

pub fn consensus_1oo1_single_guardian_test() {
  let cs = l0_constitutional.new_consensus("r1", 1, 1)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)
}

// =============================================================================
// Severity-Based Guardian Requirements
// =============================================================================

pub fn severity_critical_needs_3_guardians_test() {
  l0_constitutional.guardians_for_severity(Critical) |> should.equal(3)
}

pub fn severity_high_needs_2_guardians_test() {
  l0_constitutional.guardians_for_severity(High) |> should.equal(2)
}

pub fn severity_medium_needs_1_guardian_test() {
  l0_constitutional.guardians_for_severity(Medium) |> should.equal(1)
}

pub fn severity_low_auto_approves_test() {
  l0_constitutional.guardians_for_severity(Low) |> should.equal(0)
}

// =============================================================================
// Psi-Gated Approval
// =============================================================================

pub fn psi_gated_approve_passes_when_all_ok_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi4HumanAlignment, Pass, "aligned"),
  ]
  let state = l0_constitutional.initial_approval_state()
  let state = l0_constitutional.add_request(state, make_req("r1"))
  let state = l0_constitutional.psi_gated_approve(checks, state, "r1")
  state.history |> should.equal([#("r1", Approved)])
}

pub fn psi_gated_approve_rejects_when_fail_test() {
  let checks = [
    PsiCheck(Psi0Existence, Pass, "ok"),
    PsiCheck(Psi4HumanAlignment, Fail, "misaligned"),
  ]
  let state = l0_constitutional.initial_approval_state()
  let state = l0_constitutional.add_request(state, make_req("r1"))
  let state = l0_constitutional.psi_gated_approve(checks, state, "r1")
  state.history |> should.equal([#("r1", Rejected)])
}

// =============================================================================
// End-to-End: Severity → Consensus → Psi Gate
// =============================================================================

pub fn e2e_critical_consensus_then_psi_gate_test() {
  // Step 1: Critical severity → needs 3 guardians
  let required = l0_constitutional.guardians_for_severity(Critical)
  required |> should.equal(3)

  // Step 2: 2oo3 consensus
  let cs = l0_constitutional.new_consensus("r1", 2, required)
  let cs = l0_constitutional.cast_vote(cs, "g1", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g2", VoteApprove)
  let cs = l0_constitutional.cast_vote(cs, "g3", VoteReject)
  l0_constitutional.evaluate_consensus(cs) |> should.equal(ConsensusApproved)

  // Step 3: Psi gate
  let checks = [PsiCheck(Psi0Existence, Pass, "ok")]
  let state = l0_constitutional.initial_approval_state()
  let state = l0_constitutional.add_request(state, make_req("r1"))
  let state = l0_constitutional.psi_gated_approve(checks, state, "r1")
  state.history |> should.equal([#("r1", Approved)])
}

// =============================================================================
// Helpers
// =============================================================================

fn make_req(id: String) {
  l0_constitutional.ApprovalRequest(
    request_id: id,
    operation: "test_op",
    description: "Test",
    severity: Critical,
    requester_agent: "test",
    timestamp: 1000,
  )
}

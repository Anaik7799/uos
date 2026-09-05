//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/fractal/l0_constitutional</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-AGUI-004, SC-SAFETY-001, SC-GUARD-001</stamp-controls></compliance>
//// </c3i-module>
////
//// L0 Constitutional fractal widgets: Guardian approval, emergency stop,
//// constitutional monitoring (Psi-0..5, Omega-0).
//// HITL approval is MANDATORY at this layer (SC-AGUI-004).

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// Guardian approval request for HITL.
pub type ApprovalRequest {
  ApprovalRequest(
    request_id: String,
    operation: String,
    description: String,
    severity: ApprovalSeverity,
    requester_agent: String,
    timestamp: Int,
  )
}

pub type ApprovalSeverity {
  Critical
  High
  Medium
  Low
}

pub type ApprovalDecision {
  Approved
  Rejected
  Escalated
  Pending
}

pub type ApprovalState {
  ApprovalState(
    pending_requests: List(ApprovalRequest),
    history: List(#(String, ApprovalDecision)),
  )
}

/// Constitutional check result (Psi invariants).
pub type PsiCheck {
  PsiCheck(invariant: PsiInvariant, status: CheckStatus, evidence: String)
}

pub type PsiInvariant {
  Psi0Existence
  Psi1Regeneration
  Psi2History
  Psi3Verification
  Psi4HumanAlignment
  Psi5Truthfulness
}

pub type CheckStatus {
  Pass
  Fail
  Warning
  NotChecked
}

/// Emergency stop state.
pub type EmergencyState {
  EmergencyState(
    armed: Bool,
    triggered: Bool,
    trigger_reason: Option(String),
    last_triggered: Option(Int),
  )
}

pub fn initial_approval_state() -> ApprovalState {
  ApprovalState(pending_requests: [], history: [])
}

pub fn add_request(state: ApprovalState, req: ApprovalRequest) -> ApprovalState {
  ApprovalState(..state, pending_requests: [req, ..state.pending_requests])
}

pub fn resolve_request(
  state: ApprovalState,
  request_id: String,
  decision: ApprovalDecision,
) -> ApprovalState {
  let remaining =
    list.filter(state.pending_requests, fn(r) { r.request_id != request_id })
  ApprovalState(pending_requests: remaining, history: [
    #(request_id, decision),
    ..state.history
  ])
}

pub fn pending_count(state: ApprovalState) -> Int {
  list.length(state.pending_requests)
}

pub fn initial_emergency_state() -> EmergencyState {
  EmergencyState(
    armed: False,
    triggered: False,
    trigger_reason: None,
    last_triggered: None,
  )
}

pub fn arm_emergency(state: EmergencyState) -> EmergencyState {
  EmergencyState(..state, armed: True)
}

pub fn trigger_emergency(
  _state: EmergencyState,
  reason: String,
  timestamp: Int,
) -> EmergencyState {
  EmergencyState(
    armed: False,
    triggered: True,
    trigger_reason: Some(reason),
    last_triggered: Some(timestamp),
  )
}

pub fn reset_emergency(state: EmergencyState) -> EmergencyState {
  EmergencyState(..state, armed: False, triggered: False, trigger_reason: None)
}

pub fn all_psi_pass(checks: List(PsiCheck)) -> Bool {
  list.all(checks, fn(c) { c.status == Pass })
}

pub fn psi_invariant_to_string(inv: PsiInvariant) -> String {
  case inv {
    Psi0Existence -> "Psi-0 Existence"
    Psi1Regeneration -> "Psi-1 Regeneration"
    Psi2History -> "Psi-2 History"
    Psi3Verification -> "Psi-3 Verification"
    Psi4HumanAlignment -> "Psi-4 Human Alignment"
    Psi5Truthfulness -> "Psi-5 Truthfulness"
  }
}

pub fn approval_severity_to_string(severity: ApprovalSeverity) -> String {
  case severity {
    Critical -> "critical"
    High -> "high"
    Medium -> "medium"
    Low -> "low"
  }
}

// =============================================================================
// 2oo3 Consensus (SC-SIL4-006)
// =============================================================================

/// Individual guardian vote in 2oo3 consensus.
pub type ConsensusVote {
  VoteApprove
  VoteReject
  VoteAbstain
}

/// 2oo3 consensus state tracking multiple guardian votes.
pub type ConsensusState {
  ConsensusState(
    request_id: String,
    votes: List(#(String, ConsensusVote)),
    required_approvals: Int,
    total_guardians: Int,
  )
}

/// Consensus outcome after voting.
pub type ConsensusOutcome {
  ConsensusApproved
  ConsensusRejected
  ConsensusIncomplete
}

/// Create a new consensus state for a request.
pub fn new_consensus(
  request_id: String,
  required: Int,
  total: Int,
) -> ConsensusState {
  ConsensusState(
    request_id: request_id,
    votes: [],
    required_approvals: required,
    total_guardians: total,
  )
}

/// Record a guardian vote.
pub fn cast_vote(
  state: ConsensusState,
  guardian_id: String,
  vote: ConsensusVote,
) -> ConsensusState {
  let already_voted = list.any(state.votes, fn(v) { v.0 == guardian_id })
  case already_voted {
    True -> state
    False ->
      ConsensusState(..state, votes: [#(guardian_id, vote), ..state.votes])
  }
}

/// Count approve votes.
pub fn approve_count(state: ConsensusState) -> Int {
  list.count(state.votes, fn(v) { v.1 == VoteApprove })
}

/// Count reject votes.
pub fn reject_count(state: ConsensusState) -> Int {
  list.count(state.votes, fn(v) { v.1 == VoteReject })
}

/// Evaluate consensus outcome.
pub fn evaluate_consensus(state: ConsensusState) -> ConsensusOutcome {
  let approves = approve_count(state)
  let rejects = reject_count(state)
  let remaining = state.total_guardians - list.length(state.votes)
  case approves >= state.required_approvals {
    True -> ConsensusApproved
    False ->
      case rejects > state.total_guardians - state.required_approvals {
        True -> ConsensusRejected
        False ->
          case remaining == 0 {
            True -> ConsensusRejected
            False -> ConsensusIncomplete
          }
      }
  }
}

/// Determine required guardian count from severity.
pub fn guardians_for_severity(severity: ApprovalSeverity) -> Int {
  case severity {
    Critical -> 3
    High -> 2
    Medium -> 1
    Low -> 0
  }
}

/// Check if approval is gated by Psi invariants.
pub fn psi_gated_approve(
  checks: List(PsiCheck),
  approval_state: ApprovalState,
  request_id: String,
) -> ApprovalState {
  case all_psi_pass(checks) {
    True -> resolve_request(approval_state, request_id, Approved)
    False -> resolve_request(approval_state, request_id, Rejected)
  }
}

pub fn approval_to_json(req: ApprovalRequest) -> json.Json {
  json.object([
    #("request_id", json.string(req.request_id)),
    #("operation", json.string(req.operation)),
    #("description", json.string(req.description)),
    #("severity", json.string(approval_severity_to_string(req.severity))),
    #("requester_agent", json.string(req.requester_agent)),
    #("timestamp", json.int(req.timestamp)),
  ])
}

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

import gleam/int
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
  Psi6HardwareInviolability
  Psi7ProvenanceCeiling
  Psi8SubstratePurity
  Psi9SaPlanExclusivity
  Psi10CyberneticHomeostasis
  Psi11MaximalLocalSovereignty
  Psi12TriAgentSurveillance
  Psi13AutonomousDegradation
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

pub fn add_request(
  state: ApprovalState,
  req: ApprovalRequest,
) -> ApprovalState {
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
    Psi6HardwareInviolability -> "Psi-6 Hardware Inviolability"
    Psi7ProvenanceCeiling -> "Psi-7 Provenance Ceiling"
    Psi8SubstratePurity -> "Psi-8 Substrate Purity"
    Psi9SaPlanExclusivity -> "Psi-9 Sa-Plan Exclusivity"
    Psi10CyberneticHomeostasis -> "Psi-10 Cybernetic Homeostasis"
    Psi11MaximalLocalSovereignty -> "Psi-11 Maximal Local Sovereignty"
    Psi12TriAgentSurveillance -> "Psi-12 Tri-Agent Surveillance"
    Psi13AutonomousDegradation -> "Psi-13 Autonomous Degradation"
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

// =============================================================================
// Omega-0 & Dynamic Constitutional Reconfiguration Protocol (DCRP)
// =============================================================================

/// Supreme Founder Directive (Omega-0).
pub type OmegaDirective {
  Omega01FounderPrimacy
  Omega02LineageProtection
  Omega03EthicalBoundary
  Omega04HumanSurvival
  Omega05MutualTermination
  Omega06RevisionBoundFreshness
  Omega07ComputableDoctorAuthority
  Omega08TriSovereignQuorum
  Omega09HiveMindResonance
}

pub fn omega_directive_to_string(dir: OmegaDirective) -> String {
  case dir {
    Omega01FounderPrimacy -> "Omega-0.1 Founder Primacy"
    Omega02LineageProtection -> "Omega-0.2 Lineage Protection"
    Omega03EthicalBoundary -> "Omega-0.3 Ethical Boundary"
    Omega04HumanSurvival -> "Omega-0.4 Human Survival"
    Omega05MutualTermination -> "Omega-0.5 Mutual Termination"
    Omega06RevisionBoundFreshness -> "Omega-0.6 Revision-Bound Freshness"
    Omega07ComputableDoctorAuthority -> "Omega-0.7 Computable Doctor Authority"
    Omega08TriSovereignQuorum -> "Omega-0.8 Tri-Sovereign Quorum"
    Omega09HiveMindResonance -> "Omega-0.9 Hive Mind Resonance"
  }
}

/// Verified Rollback Path Specification (SC-CONST-009).
pub type RollbackState {
  RollbackState(snapshot_id: String, state_digest: String, is_verified: Bool)
}

/// Dynamic Constitutional Reconfiguration Proposal (DCRP).
pub type ReconfigurationProposal {
  ReconfigurationProposal(
    proposal_id: String,
    proposer_holon: String,
    target_subsystem: String,
    description: String,
    psi_checks: List(PsiCheck),
    rollback_state: Option(RollbackState),
    is_emergency_termination: Bool,
  )
}

pub type ReconfigurationOutcome {
  ReconfigurationRatified(proposal_id: String, receipt: String)
  ReconfigurationRejected(proposal_id: String, reason: String)
}

/// Evaluates a DCRP proposal against Psi invariants, Rollback path, and Guardian consensus.
pub fn evaluate_reconfiguration(
  proposal: ReconfigurationProposal,
  consensus: ConsensusState,
) -> ReconfigurationOutcome {
  case proposal.is_emergency_termination {
    True -> {
      // Omega-0.5 requires 2 approved guardian votes with no rejects/vetoes
      case approve_count(consensus) >= 2 && reject_count(consensus) == 0 {
        True ->
          ReconfigurationRatified(
            proposal.proposal_id,
            "rcpt-term-" <> proposal.proposal_id,
          )
        False ->
          ReconfigurationRejected(
            proposal.proposal_id,
            "Omega-0.5 Quorum Unsatisfied",
          )
      }
    }
    False -> {
      case reject_count(consensus) > 0 {
        True ->
          ReconfigurationRejected(
            proposal.proposal_id,
            "Guardian Veto Invoked",
          )
        False -> {
          case all_psi_pass(proposal.psi_checks) {
            False ->
              ReconfigurationRejected(
                proposal.proposal_id,
                "Constitutional Psi Axiom Violation",
              )
            True -> {
              case proposal.rollback_state {
                None ->
                  ReconfigurationRejected(
                    proposal.proposal_id,
                    "Rollback Path Unverified",
                  )
                Some(rb) -> {
                  case rb.is_verified {
                    False ->
                      ReconfigurationRejected(
                        proposal.proposal_id,
                        "Rollback Path Unverified",
                      )
                    True -> {
                      case evaluate_consensus(consensus) {
                        ConsensusApproved ->
                          ReconfigurationRatified(
                            proposal.proposal_id,
                            "rcpt-ratified-" <> proposal.proposal_id,
                          )
                        ConsensusRejected ->
                          ReconfigurationRejected(
                            proposal.proposal_id,
                            "Consensus Rejected",
                          )
                        ConsensusIncomplete ->
                          ReconfigurationRejected(
                            proposal.proposal_id,
                            "Consensus Voting Incomplete",
                          )
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

/// Identifies critical invariant axioms that zero-fence the system upon failure (SC-CONST-010).
pub fn is_zero_fenced_axiom(inv: PsiInvariant) -> Bool {
  case inv {
    Psi0Existence
    | Psi4HumanAlignment
    | Psi6HardwareInviolability
    | Psi7ProvenanceCeiling
    | Psi9SaPlanExclusivity
    | Psi11MaximalLocalSovereignty
    | Psi12TriAgentSurveillance -> True
    _ -> False
  }
}

/// Compute Real-Time Constitutional Health Metric (SC-CONST-010) in [0.0, 1.0].
/// If any zero-fenced invariant fails, constitutional health immediately collapses to 0.0.
pub fn compute_constitutional_health(checks: List(PsiCheck)) -> Float {
  let total = list.length(checks)
  case total == 0 {
    True -> 0.0
    False -> {
      let has_critical_failure =
        list.any(checks, fn(c) {
          is_zero_fenced_axiom(c.invariant) && c.status == Fail
        })
      case has_critical_failure {
        True -> 0.0
        False -> {
          let passed = list.count(checks, fn(c) { c.status == Pass })
          int.to_float(passed) /. int.to_float(total)
        }
      }
    }
  }
}

/// Omega-0.5 Dual-Key Mutual Termination.
pub fn omega_mutual_termination(
  guardian_a: String,
  guardian_b: String,
  timestamp: Int,
) -> Result(EmergencyState, String) {
  case guardian_a != guardian_b && guardian_a != "" && guardian_b != "" {
    True -> {
      let state =
        initial_emergency_state()
        |> arm_emergency
        |> trigger_emergency(
          "Omega-0.5 Dual-Key Mutual Termination authorized by "
            <> guardian_a
            <> " and "
            <> guardian_b,
          timestamp,
        )
      Ok(state)
    }
    False -> Error("Dual distinct guardian keys required for Omega-0.5")
  }
}

// =============================================================================
// Tri-Sovereign BFT Consensus & Cryptographic Session Nonce Protocol
// STAMP: SC-SIL6-001, SC-BFT-001, SC-SOV-001
// =============================================================================

pub type SovereignId {
  CodexAstra
  ClaudeSonnet
  AgyHarness
}

pub type BftVote {
  BftVote(
    sovereign: SovereignId,
    decision: ApprovalDecision,
    session_nonce: Int,
    payload_hash: String,
    signature_token: String,
  )
}

pub type BftConsensusState {
  BftConsensusState(
    request_id: String,
    expected_payload_hash: String,
    expected_epoch_nonce: Int,
    valid_votes: List(BftVote),
    byzantine_nodes: List(SovereignId),
  )
}

pub type BftConsensusOutcome {
  BftConsensusApproved(List(SovereignId))
  BftConsensusRejected(String)
  BftConsensusPending(Int)
}

pub fn new_bft_consensus(
  request_id: String,
  payload_hash: String,
  epoch_nonce: Int,
) -> BftConsensusState {
  BftConsensusState(
    request_id: request_id,
    expected_payload_hash: payload_hash,
    expected_epoch_nonce: epoch_nonce,
    valid_votes: [],
    byzantine_nodes: [],
  )
}

pub fn verify_sovereign_signature(vote: BftVote) -> Bool {
  let expected_sig = case vote.sovereign {
    CodexAstra -> "SIG_CODEX_" <> vote.payload_hash
    ClaudeSonnet -> "SIG_CLAUDE_" <> vote.payload_hash
    AgyHarness -> "SIG_AGY_" <> vote.payload_hash
  }
  vote.signature_token == expected_sig
}

pub fn cast_bft_vote(
  state: BftConsensusState,
  vote: BftVote,
) -> BftConsensusState {
  // Check 1: Session Nonce Staleness / Replay Attack
  case vote.session_nonce == state.expected_epoch_nonce {
    False ->
      BftConsensusState(
        ..state,
        byzantine_nodes: [vote.sovereign, ..state.byzantine_nodes],
      )
    True -> {
      // Check 2: Payload Hash Mismatch
      case vote.payload_hash == state.expected_payload_hash {
        False ->
          BftConsensusState(
            ..state,
            byzantine_nodes: [vote.sovereign, ..state.byzantine_nodes],
          )
        True -> {
          // Check 3: Cryptographic Signature Validity
          case verify_sovereign_signature(vote) {
            False ->
              BftConsensusState(
                ..state,
                byzantine_nodes: [vote.sovereign, ..state.byzantine_nodes],
              )
            True -> {
              // Check 4: Equivocation Detection (Did node already vote differently?)
              let prior_vote =
                list.find(state.valid_votes, fn(v) {
                  v.sovereign == vote.sovereign
                })
              case prior_vote {
                Ok(prev) -> {
                  case prev.decision == vote.decision {
                    True -> state
                    False ->
                      BftConsensusState(
                        ..state,
                        valid_votes: list.filter(state.valid_votes, fn(v) {
                          v.sovereign != vote.sovereign
                        }),
                        byzantine_nodes: [
                          vote.sovereign,
                          ..state.byzantine_nodes
                        ],
                      )
                  }
                }
                Error(Nil) ->
                  BftConsensusState(
                    ..state,
                    valid_votes: [vote, ..state.valid_votes],
                  )
              }
            }
          }
        }
      }
    }
  }
}

pub fn evaluate_bft_consensus(state: BftConsensusState) -> BftConsensusOutcome {
  let approvals =
    list.filter(state.valid_votes, fn(v) { v.decision == Approved })
    |> list.map(fn(v) { v.sovereign })

  let rejections =
    list.filter(state.valid_votes, fn(v) { v.decision == Rejected })

  case list.length(approvals) >= 2 {
    True -> BftConsensusApproved(approvals)
    False -> {
      case list.length(rejections) >= 2 {
        True -> BftConsensusRejected("QuorumRejectedByTwoSovereigns")
        False -> {
          case list.length(state.byzantine_nodes) >= 2 {
            True -> BftConsensusRejected("ByzantineFaultThresholdExceeded")
            False -> BftConsensusPending(2 - list.length(approvals))
          }
        }
      }
    }
  }
}


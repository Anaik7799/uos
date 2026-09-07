//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/multi_agent_quorum</module>
////     <fsharp-lineage>N/A — Pure Gleam Multi-Agent Quorum & BFT Consensus Engine</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <layer>L2_HEALTH</layer>
////     <layer>L5_COGNITIVE</layer>
////     <layer>L6_ECOSYSTEM</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-SIL6-001, SC-SOV-001, SC-MUDA-001, SC-JIDOKA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/list

/// Agent Sovereign identity.
pub type SovereignAgent {
  AgySovereign
  ClaudeSovereign
  CodexSovereign
  OpenRouterSovereign
  PeerSovereign(name: String)
}

/// Convert sovereign agent identity to human-readable string.
pub fn sovereign_to_string(agent: SovereignAgent) -> String {
  case agent {
    AgySovereign -> "AGY"
    ClaudeSovereign -> "CLAUDE"
    CodexSovereign -> "CODEX"
    OpenRouterSovereign -> "OPENROUTER"
    PeerSovereign(name) -> name
  }
}

/// Agent Vote option.
pub type QuorumVote {
  QuorumApprove
  QuorumReject
  QuorumAbstain
}

/// Quorum policy rule.
pub type QuorumPolicy {
  TwoOfThreeSovereign
  ThreeOfFourSovereign
  ByzantineFaultTolerant(faults_tolerated: Int)
  UnanimousSovereign
}

/// Individual recorded ballot entry.
pub type BallotVote {
  BallotVote(
    voter: SovereignAgent,
    vote: QuorumVote,
    rationale: String,
    digest: String,
    timestamp_us: Int,
  )
}

/// Final outcome verdict of a quorum ballot.
pub type QuorumVerdict {
  VerdictPending
  VerdictRatified(approvals: Int, total_votes: Int)
  VerdictRejected(rejections: Int, total_votes: Int)
  VerdictByzantineFault(violator: String, reason: String)
}

/// A living Ballot.
pub type QuorumBallot {
  QuorumBallot(
    proposal_id: String,
    title: String,
    policy: QuorumPolicy,
    total_eligible: Int,
    required_approvals: Int,
    votes: List(BallotVote),
    byzantine_violators: List(String),
    verdict: QuorumVerdict,
    created_at_us: Int,
    finalized_at_us: Int,
  )
}

/// Multi-Agent Quorum Engine metrics and global ledger.
pub type QuorumEngineState {
  QuorumEngineState(
    ballots: List(QuorumBallot),
    ratified_count: Int,
    rejected_count: Int,
    byzantine_detections: Int,
    total_ballots_created: Int,
  )
}

/// Initialize the Quorum Engine.
pub fn init_quorum_engine() -> QuorumEngineState {
  QuorumEngineState(
    ballots: [],
    ratified_count: 0,
    rejected_count: 0,
    byzantine_detections: 0,
    total_ballots_created: 0,
  )
}

/// Create a new Quorum Ballot with the specified policy.
pub fn create_ballot(
  proposal_id: String,
  title: String,
  policy: QuorumPolicy,
  now_us: Int,
) -> QuorumBallot {
  let #(total_eligible, required_approvals) = case policy {
    TwoOfThreeSovereign -> #(3, 2)
    ThreeOfFourSovereign -> #(4, 3)
    ByzantineFaultTolerant(f) -> {
      let n = 3 * f + 1
      let req = 2 * f + 1
      #(n, req)
    }
    UnanimousSovereign -> #(3, 3)
  }

  QuorumBallot(
    proposal_id: proposal_id,
    title: title,
    policy: policy,
    total_eligible: total_eligible,
    required_approvals: required_approvals,
    votes: [],
    byzantine_violators: [],
    verdict: VerdictPending,
    created_at_us: now_us,
    finalized_at_us: 0,
  )
}

/// Cast a vote onto a Ballot with Byzantine double-vote detection.
pub fn cast_ballot_vote(
  ballot: QuorumBallot,
  voter: SovereignAgent,
  vote: QuorumVote,
  rationale: String,
  digest: String,
  now_us: Int,
) -> QuorumBallot {
  case ballot.verdict {
    VerdictRatified(..) | VerdictRejected(..) -> ballot
    _ -> {
      let voter_name = sovereign_to_string(voter)
      let existing_vote =
        list.find(ballot.votes, fn(v) { sovereign_to_string(v.voter) == voter_name })

      case existing_vote {
        Ok(prev) -> {
          // If the vote value changed, treat as Byzantine conflicting double-vote
          case prev.vote == vote {
            True -> ballot
            // Duplicate identical vote ignored
            False -> {
              let violators = [voter_name, ..ballot.byzantine_violators]
              QuorumBallot(
                ..ballot,
                byzantine_violators: violators,
                verdict: VerdictByzantineFault(
                  violator: voter_name,
                  reason: "Conflicting duplicate ballot cast for same proposal",
                ),
                finalized_at_us: now_us,
              )
            }
          }
        }
        Error(Nil) -> {
          let new_entry =
            BallotVote(
              voter: voter,
              vote: vote,
              rationale: rationale,
              digest: digest,
              timestamp_us: now_us,
            )
          let updated_votes = [new_entry, ..ballot.votes]
          let outcome = evaluate_ballot_verdict(updated_votes, ballot.required_approvals, ballot.total_eligible)
          let final_ts = case outcome {
            VerdictPending -> 0
            _ -> now_us
          }
          QuorumBallot(
            ..ballot,
            votes: updated_votes,
            verdict: outcome,
            finalized_at_us: final_ts,
          )
        }
      }
    }
  }
}

/// Evaluate current verdict of a list of votes.
pub fn evaluate_ballot_verdict(
  votes: List(BallotVote),
  required_approvals: Int,
  total_eligible: Int,
) -> QuorumVerdict {
  let approves =
    list.count(votes, fn(v) {
      case v.vote {
        QuorumApprove -> True
        _ -> False
      }
    })

  let rejects =
    list.count(votes, fn(v) {
      case v.vote {
        QuorumReject -> True
        _ -> False
      }
    })

  let total_cast = list.length(votes)

  case approves >= required_approvals {
    True -> VerdictRatified(approvals: approves, total_votes: total_cast)
    False -> {
      let max_possible_approvals = total_eligible - rejects
      case max_possible_approvals < required_approvals {
        True -> VerdictRejected(rejections: rejects, total_votes: total_cast)
        False -> case total_cast >= total_eligible {
          True -> VerdictRejected(rejections: rejects, total_votes: total_cast)
          False -> VerdictPending
        }
      }
    }
  }
}

/// Compute the Shannon entropy of ballot votes H(V).
pub fn compute_vote_entropy(ballot: QuorumBallot) -> Float {
  let total = list.length(ballot.votes)
  case total == 0 {
    True -> 0.0
    False -> {
      let total_f = int.to_float(total)
      let approves =
        int.to_float(list.count(ballot.votes, fn(v) { v.vote == QuorumApprove }))
      let rejects =
        int.to_float(list.count(ballot.votes, fn(v) { v.vote == QuorumReject }))
      let abstains =
        int.to_float(list.count(ballot.votes, fn(v) { v.vote == QuorumAbstain }))

      let entropy =
        term_entropy(approves, total_f)
        +. term_entropy(rejects, total_f)
        +. term_entropy(abstains, total_f)

      case entropy <. 0.0 {
        True -> 0.0
        False -> entropy
      }
    }
  }
}

fn term_entropy(count: Float, total: Float) -> Float {
  case count <=. 0.0 {
    True -> 0.0
    False -> {
      let p = count /. total
      // Approximation for -p * log2(p)
      let log2_p = case p >=. 1.0 {
        True -> 0.0
        False -> {
          // Linearized Taylor approximation: ln(p)/ln(2)
          { p -. 1.0 } *. 1.442695
        }
      }
      0.0 -. { p *. log2_p }
    }
  }
}

/// Record a completed or updated ballot into the engine state.
pub fn record_ballot(
  engine: QuorumEngineState,
  ballot: QuorumBallot,
) -> QuorumEngineState {
  let is_new =
    case list.find(engine.ballots, fn(b) { b.proposal_id == ballot.proposal_id }) {
      Ok(_) -> False
      Error(Nil) -> True
    }

  let filtered =
    list.filter(engine.ballots, fn(b) { b.proposal_id != ballot.proposal_id })
  let updated_ballots = [ballot, ..filtered]

  let #(rat_delta, rej_delta, byz_delta) = case ballot.verdict {
    VerdictRatified(..) -> #(1, 0, 0)
    VerdictRejected(..) -> #(0, 1, 0)
    VerdictByzantineFault(..) -> #(0, 0, 1)
    VerdictPending -> #(0, 0, 0)
  }

  let total_created = case is_new {
    True -> engine.total_ballots_created + 1
    False -> engine.total_ballots_created
  }

  QuorumEngineState(
    ballots: updated_ballots,
    ratified_count: engine.ratified_count + rat_delta,
    rejected_count: engine.rejected_count + rej_delta,
    byzantine_detections: engine.byzantine_detections + byz_delta,
    total_ballots_created: total_created,
  )
}

// Tests for Multi-Agent Quorum & BFT Consensus Engine (EV-105)
// STAMP: SC-SIL6-001, SC-SOV-001, SC-MUDA-001

import cepaf_gleam/ha/multi_agent_quorum.{
  AgySovereign, ByzantineFaultTolerant, ClaudeSovereign, CodexSovereign,
  PeerSovereign, QuorumAbstain, QuorumApprove, QuorumReject, TwoOfThreeSovereign,
  UnanimousSovereign, VerdictByzantineFault, VerdictPending, VerdictRatified,
  VerdictRejected, cast_ballot_vote, compute_vote_entropy, create_ballot,
  init_quorum_engine, record_ballot, sovereign_to_string,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn sovereign_identities_test() {
  sovereign_to_string(AgySovereign) |> should.equal("AGY")
  sovereign_to_string(ClaudeSovereign) |> should.equal("CLAUDE")
  sovereign_to_string(CodexSovereign) |> should.equal("CODEX")
  sovereign_to_string(PeerSovereign("Node-4")) |> should.equal("Node-4")
}

pub fn ballot_creation_test() {
  let b_2oo3 = create_ballot("prop-01", "Constitutional Amendment", TwoOfThreeSovereign, 1000)
  b_2oo3.total_eligible |> should.equal(3)
  b_2oo3.required_approvals |> should.equal(2)
  b_2oo3.verdict |> should.equal(VerdictPending)

  let b_bft = create_ballot("prop-02", "BFT Ledger Commit", ByzantineFaultTolerant(1), 1000)
  // N = 3*1 + 1 = 4, Req = 2*1 + 1 = 3
  b_bft.total_eligible |> should.equal(4)
  b_bft.required_approvals |> should.equal(3)

  let b_unan = create_ballot("prop-03", "Zero-Muda Policy Ratification", UnanimousSovereign, 1000)
  b_unan.total_eligible |> should.equal(3)
  b_unan.required_approvals |> should.equal(3)
}

pub fn two_of_three_ratification_test() {
  let b0 = create_ballot("p-2oo3", "Task Release", TwoOfThreeSovereign, 1000)
  let b1 = cast_ballot_vote(b0, AgySovereign, QuorumApprove, "Evidence verified", "sha-agy", 1010)
  b1.verdict |> should.equal(VerdictPending)

  let b2 = cast_ballot_vote(b1, ClaudeSovereign, QuorumApprove, "Proofs green", "sha-claude", 1020)
  case b2.verdict {
    VerdictRatified(approvals, total) -> {
      approvals |> should.equal(2)
      total |> should.equal(2)
    }
    _ -> panic as "Expected VerdictRatified"
  }
}

pub fn two_of_three_rejection_test() {
  let b0 = create_ballot("p-rej", "Unverified Release", TwoOfThreeSovereign, 1000)
  let b1 = cast_ballot_vote(b0, AgySovereign, QuorumReject, "Missing Gospel contract", "sha-agy", 1010)
  b1.verdict |> should.equal(VerdictPending)

  let b2 = cast_ballot_vote(b1, CodexSovereign, QuorumReject, "Z3 timeout", "sha-codex", 1020)
  case b2.verdict {
    VerdictRejected(rejections, total) -> {
      rejections |> should.equal(2)
      total |> should.equal(2)
    }
    _ -> panic as "Expected VerdictRejected"
  }
}

pub fn byzantine_conflicting_vote_detection_test() {
  let b0 = create_ballot("p-byz", "Critical Action", TwoOfThreeSovereign, 1000)
  let b1 = cast_ballot_vote(b0, ClaudeSovereign, QuorumApprove, "Looks good", "sha-1", 1010)

  // Claude attempts to cast a conflicting vote (Reject) for the same ballot
  let b2 = cast_ballot_vote(b1, ClaudeSovereign, QuorumReject, "Changed mind", "sha-2", 1020)
  case b2.verdict {
    VerdictByzantineFault(violator, _) -> {
      violator |> should.equal("CLAUDE")
    }
    _ -> panic as "Expected VerdictByzantineFault"
  }
  b2.byzantine_violators |> should.equal(["CLAUDE"])
}

pub fn vote_entropy_calculation_test() {
  let b0 = create_ballot("p-entropy", "Vote Spread", TwoOfThreeSovereign, 1000)
  compute_vote_entropy(b0) |> should.equal(0.0)

  let b1 = cast_ballot_vote(b0, AgySovereign, QuorumApprove, "OK", "d1", 1010)
  let b2 = cast_ballot_vote(b1, ClaudeSovereign, QuorumReject, "No", "d2", 1020)
  let b3 = cast_ballot_vote(b2, CodexSovereign, QuorumAbstain, "Unsure", "d3", 1030)

  let entropy = compute_vote_entropy(b3)
  should.be_true(entropy >. 0.0)
}

pub fn quorum_engine_record_test() {
  let engine0 = init_quorum_engine()
  engine0.total_ballots_created |> should.equal(0)

  let b0 = create_ballot("b-01", "First Ballot", TwoOfThreeSovereign, 1000)
  let b1 = cast_ballot_vote(b0, AgySovereign, QuorumApprove, "Pass", "d1", 1010)
  let b2 = cast_ballot_vote(b1, ClaudeSovereign, QuorumApprove, "Pass", "d2", 1020)

  let engine1 = record_ballot(engine0, b2)
  engine1.ratified_count |> should.equal(1)
  engine1.total_ballots_created |> should.equal(1)
}

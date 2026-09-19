// =============================================================================
// bft_sovereign_consensus_test.gleam — Tri-Sovereign BFT Consensus & Cryptographic Nonce Tests
// STAMP: SC-SIL6-001, SC-BFT-001, SC-SOV-001
// =============================================================================

import cepaf_gleam/fractal/l0_constitutional.{
  Approved, AgyHarness, BftConsensusApproved, BftConsensusPending,
  BftConsensusRejected, BftVote, ClaudeSonnet, CodexAstra, Rejected,
  cast_bft_vote, evaluate_bft_consensus, new_bft_consensus,
}
import gleeunit/should

pub fn bft_nominal_2_out_of_3_ratification_test() {
  let epoch = 1789809000
  let payload = "SHA256:7e8b8c8d9e0f1a2b"
  let c0 = new_bft_consensus("req-001", payload, epoch)

  // Vote 1: Codex approves with valid signature
  let v1 =
    BftVote(
      sovereign: CodexAstra,
      decision: Approved,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "SIG_CODEX_" <> payload,
    )
  let c1 = cast_bft_vote(c0, v1)
  evaluate_bft_consensus(c1) |> should.equal(BftConsensusPending(1))

  // Vote 2: Claude approves with valid signature
  let v2 =
    BftVote(
      sovereign: ClaudeSonnet,
      decision: Approved,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "SIG_CLAUDE_" <> payload,
    )
  let c2 = cast_bft_vote(c1, v2)
  
  // 2oo3 threshold met!
  case evaluate_bft_consensus(c2) {
    BftConsensusApproved(approvers) -> {
      should.be_true(approvers == [ClaudeSonnet, CodexAstra])
    }
    _ -> should.fail()
  }
}

pub fn bft_stale_nonce_replay_attack_rejected_test() {
  let epoch = 1789809000
  let stale_epoch = 1789808000
  let payload = "SHA256:7e8b8c8d9e0f1a2b"
  let c0 = new_bft_consensus("req-002", payload, epoch)

  // Attack: Replay vote with old epoch nonce
  let v_stale =
    BftVote(
      sovereign: AgyHarness,
      decision: Approved,
      session_nonce: stale_epoch,
      payload_hash: payload,
      signature_token: "SIG_AGY_" <> payload,
    )
  let c1 = cast_bft_vote(c0, v_stale)

  // AgyHarness must be flagged as byzantine and vote discarded
  c1.valid_votes |> should.equal([])
  c1.byzantine_nodes |> should.equal([AgyHarness])
  evaluate_bft_consensus(c1) |> should.equal(BftConsensusPending(2))
}

pub fn bft_forged_signature_attack_rejected_test() {
  let epoch = 1789809000
  let payload = "SHA256:7e8b8c8d9e0f1a2b"
  let c0 = new_bft_consensus("req-003", payload, epoch)

  // Attack: Forged signature token
  let v_forged =
    BftVote(
      sovereign: CodexAstra,
      decision: Approved,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "FORGED_SIGNATURE_BAD_SECRET",
    )
  let c1 = cast_bft_vote(c0, v_forged)

  c1.valid_votes |> should.equal([])
  c1.byzantine_nodes |> should.equal([CodexAstra])
}

pub fn bft_byzantine_equivocation_detected_test() {
  let epoch = 1789809000
  let payload = "SHA256:7e8b8c8d9e0f1a2b"
  let c0 = new_bft_consensus("req-004", payload, epoch)

  // Honest initial vote: Approved
  let v_app =
    BftVote(
      sovereign: ClaudeSonnet,
      decision: Approved,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "SIG_CLAUDE_" <> payload,
    )
  let c1 = cast_bft_vote(c0, v_app)
  should.equal(c1.valid_votes, [v_app])

  // Malicious equivocation: same sovereign sends Rejected for same request
  let v_rej =
    BftVote(
      sovereign: ClaudeSonnet,
      decision: Rejected,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "SIG_CLAUDE_" <> payload,
    )
  let c2 = cast_bft_vote(c1, v_rej)

  // Prior vote must be purged and node marked byzantine
  c2.valid_votes |> should.equal([])
  c2.byzantine_nodes |> should.equal([ClaudeSonnet])
}

pub fn bft_two_sovereigns_reject_consensus_test() {
  let epoch = 1789809000
  let payload = "SHA256:7e8b8c8d9e0f1a2b"
  let c0 = new_bft_consensus("req-005", payload, epoch)

  let v1 =
    BftVote(
      sovereign: CodexAstra,
      decision: Rejected,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "SIG_CODEX_" <> payload,
    )
  let c1 = cast_bft_vote(c0, v1)

  let v2 =
    BftVote(
      sovereign: ClaudeSonnet,
      decision: Rejected,
      session_nonce: epoch,
      payload_hash: payload,
      signature_token: "SIG_CLAUDE_" <> payload,
    )
  let c2 = cast_bft_vote(c1, v2)

  evaluate_bft_consensus(c2)
  |> should.equal(BftConsensusRejected("QuorumRejectedByTwoSovereigns"))
}


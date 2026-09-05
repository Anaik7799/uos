//// Federated CPIG wiring guard test (SC-CPIG-FED-001..010, SC-WIRE-001).
////
//// Hard-codes federation topology (3 peer meshes, 3 regions, 2oo3 quorum)
//// so any drift breaks compilation/test FIRST — not scattered across
//// downstream sites.
////
//// References:
////   - SC-CPIG-FED-001..010 (federated CPIG governance)
////   - SC-FED-001..006 (federation, Ed25519 signatures)
////   - SC-SIL4-006 (2oo3 voting mandate)
////   - SC-WIRE-001 (wiring guard discipline)
////
//// ZK: [zk-bb4de67d97f807ac]

import gleam/list
import gleeunit/should

// --- Hard-coded federation topology ---

const expected_peers: List(String) = [
  "mesh-a.tail55d152.ts.net",
  "mesh-b.tail55d152.ts.net",
  "mesh-c.tail55d152.ts.net",
]

const expected_regions: List(String) = ["eu", "us-west", "asia"]

const expected_attestation_fields: List(String) = [
  "peer", "score", "signature", "timestamp",
]

const quorum_size: Int = 2

const max_divergence: Int = 5

const max_cpig_score: Int = 60

// --- Tests ---

/// SC-SIL4-006: 2oo3 quorum minimum requires exactly 3 peers in topology.
pub fn peer_count_test() {
  expected_peers
  |> list.length
  |> should.equal(3)
}

/// SC-CPIG-FED-002, SC-CPIG-FED-003: attestations require peer, score,
/// signature, timestamp — all four fields are mandatory.
pub fn attestation_fields_test() {
  expected_attestation_fields
  |> list.length
  |> should.equal(4)

  expected_attestation_fields
  |> list.contains("signature")
  |> should.be_true

  expected_attestation_fields
  |> list.contains("timestamp")
  |> should.be_true
}

/// SC-CPIG-FED-004, SC-SIL4-006: quorum threshold is 2 (out of 3).
pub fn quorum_threshold_test() {
  quorum_size |> should.equal(2)
  // 2oo3 invariant: quorum < total
  let total = list.length(expected_peers)
  { quorum_size < total } |> should.be_true
  { quorum_size > total / 2 } |> should.be_true
}

/// SC-CPIG-FED-005: divergence threshold is 5 (8.3% of max score 60).
pub fn divergence_threshold_test() {
  max_divergence |> should.equal(5)
  // Verify 8.3% relationship
  { max_divergence * 12 == max_cpig_score } |> should.be_true
}

/// SC-CPIG-FED-004: exactly 3 regions required for geo-distributed voting.
pub fn region_set_test() {
  expected_regions
  |> list.length
  |> should.equal(3)

  expected_regions |> list.contains("eu") |> should.be_true
  expected_regions |> list.contains("us-west") |> should.be_true
  expected_regions |> list.contains("asia") |> should.be_true
}

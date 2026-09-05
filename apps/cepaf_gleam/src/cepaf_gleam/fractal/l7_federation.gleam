//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/fractal/l7_federation</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-FED-001, SC-FED-006</stamp-controls></compliance></c3i-module>
////
//// L7 Federation: peer discovery, version vectors, attestation, remote agents.

import gleam/json
import gleam/list

/// SC-MUDA-001: bound peer list to prevent unbounded growth.
const max_peers = 50

/// Federation peer.
pub type FederationPeer {
  FederationPeer(
    peer_id: String,
    endpoint: String,
    status: PeerStatus,
    version_vector: List(#(String, Int)),
    attestation_valid: Bool,
    last_seen: Int,
  )
}

pub type PeerStatus {
  PeerConnected
  PeerDisconnected
  PeerSuspected
}

/// Federation state.
pub type FederationState {
  FederationState(
    local_id: String,
    peers: List(FederationPeer),
    local_version: List(#(String, Int)),
  )
}

pub fn initial_federation(local_id: String) -> FederationState {
  FederationState(local_id: local_id, peers: [], local_version: [#(local_id, 0)])
}

pub fn add_peer(state: FederationState, peer: FederationPeer) -> FederationState {
  let existing = list.filter(state.peers, fn(p) { p.peer_id != peer.peer_id })
  FederationState(..state, peers: [peer, ..existing] |> list.take(max_peers))
}

pub fn remove_peer(state: FederationState, peer_id: String) -> FederationState {
  FederationState(
    ..state,
    peers: list.filter(state.peers, fn(p) { p.peer_id != peer_id }),
  )
}

pub fn increment_version(state: FederationState) -> FederationState {
  let new_version =
    list.map(state.local_version, fn(entry) {
      let #(id, ver) = entry
      case id == state.local_id {
        True -> #(id, ver + 1)
        False -> entry
      }
    })
  FederationState(..state, local_version: new_version)
}

pub fn connected_peers(state: FederationState) -> List(FederationPeer) {
  list.filter(state.peers, fn(p) { p.status == PeerConnected })
}

pub fn peer_count(state: FederationState) -> Int {
  list.length(state.peers)
}

pub fn all_attested(state: FederationState) -> Bool {
  list.all(state.peers, fn(p) { p.attestation_valid })
}

pub fn peer_to_json(peer: FederationPeer) -> json.Json {
  json.object([
    #("peer_id", json.string(peer.peer_id)),
    #("endpoint", json.string(peer.endpoint)),
    #(
      "status",
      json.string(case peer.status {
        PeerConnected -> "connected"
        PeerDisconnected -> "disconnected"
        PeerSuspected -> "suspected"
      }),
    ),
    #("attestation_valid", json.bool(peer.attestation_valid)),
    #("last_seen", json.int(peer.last_seen)),
  ])
}

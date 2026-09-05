//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/wisp/federation_api</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-003, SC-FED-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Typed JSON serialisation for the L7 Federation plane.
//// All JSON produced via gleam/json — no raw string concatenation (SC-GLM-UI-003).
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-FED-001

import cepaf_gleam/fractal/l7_federation.{
  type FederationPeer, type FederationState, all_attested, connected_peers,
  peer_count, peer_to_json,
}
import gleam/json
import gleam/list

/// Serialise a full FederationState to a JSON string.
pub fn federation_status_json(state: FederationState) -> String {
  json.object([
    #("plane", json.string("federation")),
    #("local_id", json.string(state.local_id)),
    #("peer_count", json.int(peer_count(state))),
    #("connected_count", json.int(list.length(connected_peers(state)))),
    #("all_attested", json.bool(all_attested(state))),
    #("peers", json.array(state.peers, encode_peer)),
    #("version_vector", json.array(state.local_version, encode_version_entry)),
  ])
  |> json.to_string()
}

/// Serialise a list of FederationPeer values to a JSON string.
pub fn peer_list_json(peers: List(FederationPeer)) -> String {
  json.object([
    #("plane", json.string("federation")),
    #("peer_count", json.int(list.length(peers))),
    #("peers", json.array(peers, encode_peer)),
  ])
  |> json.to_string()
}

/// Encode a single peer using the canonical encoder from l7_federation.
fn encode_peer(peer: FederationPeer) -> json.Json {
  peer_to_json(peer)
}

/// Encode a version-vector entry #(node_id, clock) as a JSON object.
fn encode_version_entry(entry: #(String, Int)) -> json.Json {
  let #(id, version) = entry
  json.object([
    #("id", json.string(id)),
    #("version", json.int(version)),
  ])
}

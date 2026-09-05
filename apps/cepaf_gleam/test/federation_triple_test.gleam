/// Federation triple-interface tests — Lustre MVU, Wisp API, TUI renderer.
///
/// Covers the L7 Federation plane across all three Gleam interfaces as
/// mandated by SC-GLM-UI-001 (Triple-Interface) and SC-FED-001.
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-007, SC-FED-001, SC-FED-006,
///        SC-UIGT-003, SC-UIGT-007, SC-UIGT-008, SC-UIGT-009
import cepaf_gleam/fractal/l7_federation.{
  FederationPeer, PeerConnected, PeerDisconnected, PeerSuspected, add_peer,
  increment_version, initial_federation,
}
import cepaf_gleam/ui/domain
import cepaf_gleam/ui/lustre/federation.{
  ErrorReceived, FederationModel, HaStatus, PeerAdded, PeerRemoved,
  RefreshFederation, Standby, StateReceived, VersionIncremented,
  all_attested_check, connected_count, init, update,
}
import cepaf_gleam/ui/tui/federation_view
import cepaf_gleam/ui/wisp/federation_api
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Domain: page_to_path, page_to_label, page_fractal_layer
// =============================================================================

pub fn federation_page_to_path_test() {
  domain.page_to_path(domain.Federation)
  |> should.equal("/federation")
}

pub fn federation_page_to_label_test() {
  domain.page_to_label(domain.Federation)
  |> should.equal("Federation (L7)")
}

pub fn federation_page_fractal_layer_test() {
  domain.page_fractal_layer(domain.Federation)
  |> should.equal(domain.L7Federation)
}

// =============================================================================
// Lustre MVU — init
// =============================================================================

pub fn federation_init_has_no_state_test() {
  init().state
  |> should.equal(None)
}

pub fn federation_init_not_loading_test() {
  init().loading
  |> should.equal(False)
}

pub fn federation_init_no_error_test() {
  init().error
  |> should.equal(None)
}

// =============================================================================
// Lustre MVU — update / StateReceived
// =============================================================================

pub fn federation_state_received_sets_state_test() {
  let state = initial_federation("node-a")
  let model = update(init(), StateReceived(state))
  model.state |> should.equal(Some(state))
}

pub fn federation_state_received_clears_loading_test() {
  let m0 =
    FederationModel(
      state: None,
      loading: True,
      error: None,
      ha: HaStatus(Standby, 0, 0, 0, 0),
    )
  let state = initial_federation("node-a")
  let m1 = update(m0, StateReceived(state))
  m1.loading |> should.equal(False)
}

pub fn federation_state_received_clears_error_test() {
  let m0 =
    FederationModel(
      state: None,
      loading: False,
      error: Some("prior"),
      ha: HaStatus(Standby, 0, 0, 0, 0),
    )
  let state = initial_federation("node-a")
  let m1 = update(m0, StateReceived(state))
  m1.error |> should.equal(None)
}

// =============================================================================
// Lustre MVU — update / PeerAdded, PeerRemoved
// =============================================================================

pub fn federation_peer_added_increases_count_test() {
  let state = initial_federation("node-a")
  let m0 = update(init(), StateReceived(state))
  let peer =
    FederationPeer(
      peer_id: "node-b",
      endpoint: "tcp/node-b:4001",
      status: PeerConnected,
      version_vector: [#("node-a", 0), #("node-b", 1)],
      attestation_valid: True,
      last_seen: 1_000_000,
    )
  let m1 = update(m0, PeerAdded(peer))
  let count = case m1.state {
    None -> 0
    Some(s) -> l7_federation.peer_count(s)
  }
  count |> should.equal(1)
}

pub fn federation_peer_removed_decreases_count_test() {
  let state = initial_federation("node-a")
  let peer =
    FederationPeer(
      peer_id: "node-b",
      endpoint: "tcp/node-b:4001",
      status: PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1_000_000,
    )
  let state_with_peer = add_peer(state, peer)
  let m0 = update(init(), StateReceived(state_with_peer))
  let m1 = update(m0, PeerRemoved("node-b"))
  let count = case m1.state {
    None -> 0
    Some(s) -> l7_federation.peer_count(s)
  }
  count |> should.equal(0)
}

pub fn federation_peer_added_no_state_is_noop_test() {
  let peer =
    FederationPeer(
      peer_id: "orphan",
      endpoint: "tcp/orphan:4001",
      status: PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 0,
    )
  let m = update(init(), PeerAdded(peer))
  m.state |> should.equal(None)
}

// =============================================================================
// Lustre MVU — update / VersionIncremented
// =============================================================================

pub fn federation_version_incremented_test() {
  let state = initial_federation("node-a")
  let m0 = update(init(), StateReceived(state))
  let m1 = update(m0, VersionIncremented)
  let before_version = case m0.state {
    Some(s) -> s.local_version
    None -> []
  }
  let after_version = case m1.state {
    Some(s) -> s.local_version
    None -> []
  }
  // After increment the versions must differ
  { before_version != after_version } |> should.be_true()
}

// =============================================================================
// Lustre MVU — update / RefreshFederation
// =============================================================================

pub fn federation_refresh_sets_loading_test() {
  let m = update(init(), RefreshFederation)
  m.loading |> should.equal(True)
}

// =============================================================================
// Lustre MVU — update / ErrorReceived
// =============================================================================

pub fn federation_error_received_sets_error_test() {
  let m = update(init(), ErrorReceived("oops"))
  m.error |> should.equal(Some("oops"))
}

pub fn federation_error_received_clears_loading_test() {
  let m0 =
    FederationModel(
      state: None,
      loading: True,
      error: None,
      ha: HaStatus(Standby, 0, 0, 0, 0),
    )
  let m1 = update(m0, ErrorReceived("timeout"))
  m1.loading |> should.equal(False)
}

// =============================================================================
// Lustre MVU — connected_count, all_attested_check
// =============================================================================

pub fn federation_connected_count_test() {
  let state = initial_federation("node-a")
  let peer_conn =
    FederationPeer(
      peer_id: "node-b",
      endpoint: "tcp/node-b:4001",
      status: PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 0,
    )
  let peer_disc =
    FederationPeer(
      peer_id: "node-c",
      endpoint: "tcp/node-c:4002",
      status: PeerDisconnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 0,
    )
  let s2 = add_peer(add_peer(state, peer_conn), peer_disc)
  let m = update(init(), StateReceived(s2))
  connected_count(m) |> should.equal(1)
}

pub fn federation_connected_count_no_state_is_zero_test() {
  connected_count(init()) |> should.equal(0)
}

pub fn federation_all_attested_true_test() {
  let state = initial_federation("node-a")
  let peer =
    FederationPeer(
      peer_id: "node-b",
      endpoint: "tcp/node-b:4001",
      status: PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 0,
    )
  let m = update(init(), StateReceived(add_peer(state, peer)))
  all_attested_check(m) |> should.be_true()
}

pub fn federation_all_attested_false_test() {
  let state = initial_federation("node-a")
  let peer_ok =
    FederationPeer(
      peer_id: "node-b",
      endpoint: "tcp/node-b:4001",
      status: PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 0,
    )
  let peer_bad =
    FederationPeer(
      peer_id: "node-c",
      endpoint: "tcp/node-c:4002",
      status: PeerSuspected,
      version_vector: [],
      attestation_valid: False,
      last_seen: 0,
    )
  let s2 = add_peer(add_peer(state, peer_ok), peer_bad)
  let m = update(init(), StateReceived(s2))
  all_attested_check(m) |> should.be_false()
}

pub fn federation_all_attested_no_state_is_false_test() {
  all_attested_check(init()) |> should.be_false()
}

// =============================================================================
// Wisp API — federation_status_json
// =============================================================================

fn fixture_state() {
  let local = "test-local-federation"
  let peer1 =
    FederationPeer(
      peer_id: "test-peer-a",
      endpoint: "tcp/test-peer-a:4001",
      status: PeerConnected,
      version_vector: [#(local, 1), #("test-peer-a", 3)],
      attestation_valid: True,
      last_seen: 1_712_120_000,
    )
  let peer2 =
    FederationPeer(
      peer_id: "test-peer-b",
      endpoint: "tcp/test-peer-b:4002",
      status: PeerSuspected,
      version_vector: [#(local, 0), #("test-peer-b", 1)],
      attestation_valid: False,
      last_seen: 1_712_119_000,
    )

  initial_federation(local)
  |> add_peer(peer1)
  |> add_peer(peer2)
  |> increment_version()
}

pub fn federation_status_json_contains_plane_test() {
  let state = fixture_state()
  let j = federation_api.federation_status_json(state)
  string.contains(j, "\"federation\"") |> should.be_true()
}

pub fn federation_status_json_contains_local_id_test() {
  let state = fixture_state()
  let j = federation_api.federation_status_json(state)
  string.contains(j, state.local_id) |> should.be_true()
}

pub fn federation_status_json_contains_peer_count_test() {
  let state = fixture_state()
  let j = federation_api.federation_status_json(state)
  string.contains(j, "peer_count") |> should.be_true()
}

// =============================================================================
// Wisp API — peer_list_json
// =============================================================================

pub fn federation_peer_list_json_encodes_test() {
  let state = fixture_state()
  let j = federation_api.peer_list_json(state.peers)
  string.contains(j, "peer_id") |> should.be_true()
}

pub fn federation_peer_list_json_contains_plane_test() {
  let j = federation_api.peer_list_json([])
  string.contains(j, "\"federation\"") |> should.be_true()
}

pub fn federation_peer_list_json_empty_has_zero_count_test() {
  let j = federation_api.peer_list_json([])
  string.contains(j, "\"peer_count\":0") |> should.be_true()
}

// =============================================================================
// TUI view — render
// =============================================================================

pub fn federation_render_contains_header_test() {
  let output = federation_view.render(init())
  string.contains(output, "FEDERATION") |> should.be_true()
}

pub fn federation_render_no_state_message_test() {
  let output = federation_view.render(init())
  string.contains(output, "No federation") |> should.be_true()
}

pub fn federation_render_with_state_contains_local_id_test() {
  let state = fixture_state()
  let m = update(init(), StateReceived(state))
  let output = federation_view.render(m)
  string.contains(output, state.local_id) |> should.be_true()
}

pub fn federation_render_with_state_contains_peers_label_test() {
  let state = fixture_state()
  let m = update(init(), StateReceived(state))
  let output = federation_view.render(m)
  string.contains(output, "Peers:") |> should.be_true()
}

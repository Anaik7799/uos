//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/federation_view</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-FED-001</stamp-controls></compliance>
//// </c3i-module>
////
//// TUI ANSI renderer for the L7 Federation plane.
//// Produces terminal output matching the dark-cockpit 5-mode pattern.
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-FED-001

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/fractal/l7_federation.{
  type FederationPeer, type PeerStatus, PeerConnected, PeerDisconnected,
  PeerSuspected,
}
import cepaf_gleam/ui/lustre/federation.{type FederationModel}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

/// Render the full federation TUI panel to an ANSI string.
pub fn render(model: FederationModel) -> String {
  let header = visuals.with_color("  FEDERATION (L7)", "cyan")
  let body = case model.state {
    None -> "  No federation state loaded"
    Some(state) -> render_state(state, model)
  }
  string.join([header, body], "\n")
}

fn render_state(
  state: l7_federation.FederationState,
  model: FederationModel,
) -> String {
  let local_line = "  Local ID: " <> visuals.with_color(state.local_id, "white")

  let total = federation.total_peer_count(model)
  let connected = federation.connected_count(model)
  let peer_line =
    "  Peers: "
    <> int.to_string(total)
    <> " total, "
    <> visuals.with_color(int.to_string(connected) <> " connected", "green")

  let attest_line = case federation.all_attested_check(model) {
    True -> "  Attestation: " <> visuals.with_color("ALL ATTESTED", "green")
    False ->
      "  Attestation: " <> visuals.with_color("ATTESTATION INCOMPLETE", "red")
  }

  let peers_header = "  Peers:"
  let peer_rows =
    state.peers
    |> list.map(render_peer)
    |> string.join("\n")

  let version_header = "  Version Vector:"
  let version_rows =
    state.local_version
    |> list.map(fn(entry) {
      let #(id, ver) = entry
      "    " <> id <> " = " <> int.to_string(ver)
    })
    |> string.join("\n")

  string.join(
    [
      local_line, peer_line, attest_line, "", peers_header, peer_rows, "",
      version_header, version_rows,
    ],
    "\n",
  )
}

/// Render a single federation peer as one terminal line.
fn render_peer(peer: FederationPeer) -> String {
  let status_str = peer_status_string(peer.status)
  let status_col = peer_status_color(peer.status)
  let att = case peer.attestation_valid {
    True -> visuals.with_color("att:ok", "green")
    False -> visuals.with_color("att:NO", "red")
  }
  "    "
  <> visuals.with_color(peer.peer_id, "white")
  <> " @ "
  <> peer.endpoint
  <> " ["
  <> visuals.with_color(status_str, status_col)
  <> "] "
  <> att
  <> " seen:"
  <> int.to_string(peer.last_seen)
}

/// Convert a PeerStatus to its display label.
fn peer_status_string(status: PeerStatus) -> String {
  case status {
    PeerConnected -> "connected"
    PeerDisconnected -> "disconnected"
    PeerSuspected -> "suspected"
  }
}

/// Map a PeerStatus to an ANSI colour name for visuals.with_color.
fn peer_status_color(status: PeerStatus) -> String {
  case status {
    PeerConnected -> "green"
    PeerDisconnected -> "red"
    PeerSuspected -> "yellow"
  }
}

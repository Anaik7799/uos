//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/federation</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-FED-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the L7 Federation plane.
//// Tracks peer discovery, version vectors, and attestation state.
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009, SC-FED-001, SC-FED-006

import cepaf_gleam/fractal/l7_federation.{
  type FederationPeer, type FederationState, add_peer, all_attested,
  connected_peers, increment_version, peer_count, remove_peer,
}
import gleam/option.{type Option, None, Some}

/// HA election role (P2-5: SC-HA-001)
pub type HaRole {
  Primary
  Backup
  Standby
  Draining
}

/// HA election status widget (P2-5)
pub type HaStatus {
  HaStatus(
    role: HaRole,
    lease_ttl_ms: Int,
    last_heartbeat_ms: Int,
    missed_heartbeats: Int,
    peer_count: Int,
  )
}

/// Lustre model for the Federation page.
pub type FederationModel {
  FederationModel(
    state: Option(FederationState),
    loading: Bool,
    error: Option(String),
    // P2-5: HA election status
    ha: HaStatus,
  )
}

/// Messages for the Federation Lustre component.
pub type FederationMsg {
  StateReceived(FederationState)
  PeerAdded(FederationPeer)
  PeerRemoved(String)
  VersionIncremented
  RefreshFederation
  ErrorReceived(String)
  // P2-5: HA status update
  HaStatusUpdated(HaStatus)
}

/// Initial model — no state loaded yet.
pub fn init() -> FederationModel {
  FederationModel(
    state: None,
    loading: False,
    error: None,
    ha: HaStatus(Standby, 0, 0, 0, 0),
  )
}

/// Pure update function — deterministic, no side effects.
pub fn update(model: FederationModel, msg: FederationMsg) -> FederationModel {
  case msg {
    StateReceived(s) ->
      FederationModel(..model, state: Some(s), loading: False, error: None)

    PeerAdded(peer) ->
      case model.state {
        None -> model
        Some(s) -> FederationModel(..model, state: Some(add_peer(s, peer)))
      }

    PeerRemoved(id) ->
      case model.state {
        None -> model
        Some(s) -> FederationModel(..model, state: Some(remove_peer(s, id)))
      }

    VersionIncremented ->
      case model.state {
        None -> model
        Some(s) -> FederationModel(..model, state: Some(increment_version(s)))
      }

    RefreshFederation -> FederationModel(..model, loading: True)

    ErrorReceived(err) ->
      FederationModel(..model, error: Some(err), loading: False)
    HaStatusUpdated(ha) -> FederationModel(..model, ha: ha)
  }
}

pub fn ha_role_label(role: HaRole) -> String {
  case role {
    Primary -> "PRIMARY"
    Backup -> "BACKUP"
    Standby -> "STANDBY"
    Draining -> "DRAINING"
  }
}

/// Count connected peers in the current model state.
pub fn connected_count(model: FederationModel) -> Int {
  case model.state {
    None -> 0
    Some(s) -> connected_peers(s) |> list_length()
  }
}

/// Check whether all peers in the current model are attested.
pub fn all_attested_check(model: FederationModel) -> Bool {
  case model.state {
    None -> False
    Some(s) -> all_attested(s)
  }
}

/// Total peer count from the current model state.
pub fn total_peer_count(model: FederationModel) -> Int {
  case model.state {
    None -> 0
    Some(s) -> peer_count(s)
  }
}

// Internal helper — avoids importing gleam/list just for length.
fn list_length(lst: List(a)) -> Int {
  list_length_acc(lst, 0)
}

fn list_length_acc(lst: List(a), acc: Int) -> Int {
  case lst {
    [] -> acc
    [_, ..rest] -> list_length_acc(rest, acc + 1)
  }
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real HA status from NIF → Rust → UserPreferences
pub fn load_ha_from_nif() -> HaStatus {
  let raw = nif.ha_status()
  let decoder = {
    use role <- decode.field("role", decode.string)
    use missed <- decode.field("missed_heartbeats", decode.int)
    use ttl <- decode.field("lease_ttl_ms", decode.int)
    decode.success(#(role, missed, ttl))
  }
  case json.parse(raw, decoder) {
    Ok(#(role_str, missed, ttl)) -> {
      let role = case role_str {
        "primary" -> Primary
        "backup" -> Backup
        "draining" -> Draining
        _ -> Standby
      }
      HaStatus(role, ttl, 0, missed, 0)
    }
    Error(_) -> HaStatus(Standby, 0, 0, 0, 0)
  }
}

/// Load real OODA phase from NIF
pub fn load_ooda_from_nif() -> String {
  nif.ooda_phase()
}

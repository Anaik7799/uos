// UOS MCP Transport-Bound Principal
// Construct Principal only from admitted launcher environment, HTTP auth middleware,
// or signed Zenoh envelope. Payload actor/clientInfo/unverified headers cannot escalate.

import cepaf_gleam/mcp/types.{type ClientProfile, type TransportKind, HttpStreamable, Stdio, Zenoh}
import gleam/option.{type Option, None}

pub opaque type Principal {
  Principal(
    actor_id: String,
    client_profile: ClientProfile,
    transport: TransportKind,
    workspace_root: String,
    session_id: String,
    untrusted_actor_label: Option(String),
    untrusted_client_label: Option(String),
    untrusted_header_actor: Option(String),
  )
}

pub fn from_launcher_env(
  actor actor_id: String,
  client client_profile: ClientProfile,
  workspace_root workspace_root: String,
  session_id session_id: String,
) -> Principal {
  Principal(
    actor_id: actor_id,
    client_profile: client_profile,
    transport: Stdio,
    workspace_root: workspace_root,
    session_id: session_id,
    untrusted_actor_label: None,
    untrusted_client_label: None,
    untrusted_header_actor: None,
  )
}

pub fn from_http_auth_middleware(
  actor actor_id: String,
  client client_profile: ClientProfile,
  workspace_root workspace_root: String,
  session_id session_id: String,
) -> Principal {
  Principal(
    actor_id: actor_id,
    client_profile: client_profile,
    transport: HttpStreamable,
    workspace_root: workspace_root,
    session_id: session_id,
    untrusted_actor_label: None,
    untrusted_client_label: None,
    untrusted_header_actor: None,
  )
}

pub fn from_signed_zenoh_envelope(
  actor actor_id: String,
  client client_profile: ClientProfile,
  workspace_root workspace_root: String,
  session_id session_id: String,
) -> Principal {
  Principal(
    actor_id: actor_id,
    client_profile: client_profile,
    transport: Zenoh,
    workspace_root: workspace_root,
    session_id: session_id,
    untrusted_actor_label: None,
    untrusted_client_label: None,
    untrusted_header_actor: None,
  )
}

/// Records untrusted labels from payload `arguments.actor`, `clientInfo.name`,
/// or unverified headers for audit telemetry ONLY without mutating the authoritative
/// actor_id or client_profile.
pub fn apply_untrusted_payload_labels(
  principal: Principal,
  payload_actor payload_actor: Option(String),
  client_info_name client_info_name: Option(String),
  unverified_header_actor unverified_header_actor: Option(String),
) -> Principal {
  Principal(
    ..principal,
    untrusted_actor_label: payload_actor,
    untrusted_client_label: client_info_name,
    untrusted_header_actor: unverified_header_actor,
  )
}

pub fn actor_id(principal: Principal) -> String {
  principal.actor_id
}

pub fn client_profile(principal: Principal) -> ClientProfile {
  principal.client_profile
}

pub fn transport(principal: Principal) -> TransportKind {
  principal.transport
}

pub fn workspace_root(principal: Principal) -> String {
  principal.workspace_root
}

pub fn session_id(principal: Principal) -> String {
  principal.session_id
}

pub fn untrusted_actor_label(principal: Principal) -> Option(String) {
  principal.untrusted_actor_label
}

pub fn untrusted_client_label(principal: Principal) -> Option(String) {
  principal.untrusted_client_label
}

pub fn untrusted_header_actor(principal: Principal) -> Option(String) {
  principal.untrusted_header_actor
}

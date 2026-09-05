/// Wisp API for Podman plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Typed JSON via gleam/json — no raw strings (SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/podman/domain.{
  type ContainerSummary, type PortMapping, status_to_string,
}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}

// ---------------------------------------------------------------------------
// Mutation request/response codecs (T006)
// STAMP: SC-GLM-UI-003 — typed JSON via gleam/json, no string concatenation
// ---------------------------------------------------------------------------

/// A typed mutation request: verb + target container + audit reason.
pub type MutationRequest {
  MutationRequest(verb: String, container: String, reason: String)
}

/// Decode a JSON body string into a MutationRequest.
/// Returns Ok(MutationRequest) or Error(description).
///
/// Expected JSON shape:
///   {"verb": "start", "container": "ex-app-1", "reason": "operator restart"}
pub fn mutation_request_decode(body: String) -> Result(MutationRequest, String) {
  let decoder = {
    use verb <- decode.field("verb", decode.string)
    use container <- decode.field("container", decode.string)
    use reason <- decode.field("reason", decode.string)
    decode.success(MutationRequest(verb:, container:, reason:))
  }

  case json.parse(body, decoder) {
    Ok(req) -> Ok(req)
    Error(_) ->
      Error("invalid_body: expected {verb, container, reason} JSON object")
  }
}

/// Encode a successful mutation response as a JSON string.
/// All fields produced via gleam/json — no raw string concatenation (SC-GLM-UI-003).
pub fn mutation_response_json(
  status: String,
  container: String,
  details: String,
) -> String {
  json.object([
    #("status", json.string(status)),
    #("container", json.string(container)),
    #("details", json.string(details)),
    #("stamp", json.string("SC-GLM-UI-003")),
  ])
  |> json.to_string()
}

/// Encode an error response as a JSON string.
/// All fields produced via gleam/json — no raw string concatenation (SC-GLM-UI-003).
pub fn error_response_json(error: String, code: String, stamp: String) -> String {
  json.object([
    #("error", json.string(error)),
    #("code", json.string(code)),
    #("stamp", json.string(stamp)),
  ])
  |> json.to_string()
}

/// Encode a port mapping to a display string like "8080:80/tcp".
fn port_mapping_to_string(pm: PortMapping) -> String {
  let host = case pm.host_port {
    Some(p) -> int.to_string(p) <> ":"
    None -> ""
  }
  let proto = case pm.protocol {
    domain.Tcp -> "/tcp"
    domain.Udp -> "/udp"
    domain.Sctp -> "/sctp"
  }
  host <> int.to_string(pm.container_port) <> proto
}

/// Full containers list JSON with name, status, image, ports.
pub fn containers_json(containers: List(ContainerSummary)) -> String {
  json.object([
    #("plane", json.string("podman")),
    #("container_count", json.int(list.length(containers))),
    #("containers", json.array(containers, encode_container)),
  ])
  |> json.to_string()
}

/// System info and disk usage summary.
pub fn system_info_json(
  api_version: String,
  rootless: Bool,
  disk_usage_mb: Int,
  container_count: Int,
) -> String {
  json.object([
    #("plane", json.string("podman")),
    #("api_version", json.string(api_version)),
    #("rootless", json.bool(rootless)),
    #("disk_usage_mb", json.int(disk_usage_mb)),
    #("container_count", json.int(container_count)),
  ])
  |> json.to_string()
}

fn encode_container(c: ContainerSummary) -> json.Json {
  let name = case c.names {
    [first, ..] -> first
    [] -> c.id
  }
  json.object([
    #("id", json.string(c.id)),
    #("name", json.string(name)),
    #("image", json.string(c.image)),
    #("status", json.string(status_to_string(c.state))),
    #(
      "ports",
      json.array(c.ports, fn(pm) { json.string(port_mapping_to_string(pm)) }),
    ),
  ])
}

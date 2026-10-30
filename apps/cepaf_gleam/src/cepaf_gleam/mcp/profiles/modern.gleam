//// T15 Modern 2025/2026 revisions: initialize handshake, discovery metadata,
//// structured result/error envelopes, and cache/capability separation.
//// Legacy-only unversioned mix-ins are refused with PROFILE_METHOD_MISMATCH.

import cepaf_gleam/mcp/types.{
  type ToolError, Legacy20241105, Modern20260728, NonRetryable, ToolError,
}
import cepaf_gleam/mcp/version
import gleam/dict.{type Dict}
import gleam/json
import gleam/result

pub const protocol_version = "2026-07-28"

pub const legacy_only_methods = [
  "initialize_legacy",
  "legacy/initialize",
  "resources/list_unversioned",
]

pub type CachePolicy {
  Cacheable
  Uncacheable
}

pub fn initialize(
  client_name: String,
  client_version: String,
  requested_version: String,
) -> Result(String, ToolError) {
  use profile <- result.try(version.negotiate(requested_version))
  case profile {
    Modern20260728 ->
      Ok(
        json.to_string(
          json.object([
            #("protocolVersion", json.string(requested_version)),
            #(
              "capabilities",
              json.object([
                #("tools", json.object([#("listChanged", json.bool(True))])),
                #("discovery", json.object([])),
                #("tasks", json.object([])),
              ]),
            ),
            #(
              "serverInfo",
              json.object([
                #("name", json.string("uos-cepaf-mcp")),
                #("version", json.string("1.0.0")),
              ]),
            ),
            #(
              "clientInfo",
              json.object([
                #("name", json.string(client_name)),
                #("version", json.string(client_version)),
              ]),
            ),
          ]),
        ),
      )
    Legacy20241105 -> Error(profile_mismatch("initialize"))
  }
}

pub fn cache_policy(method: String) -> CachePolicy {
  case method {
    "discovery/list" | "tools/list" -> Cacheable
    _ -> Uncacheable
  }
}

pub fn discovery_metadata() -> String {
  json.to_string(
    json.object([
      #(
        "discovery",
        json.object([
          #("protocolVersion", json.string(protocol_version)),
          #(
            "capabilities",
            json.preprocessed_array([json.string("tools"), json.string("tasks")]),
          ),
          #(
            "cache",
            json.object([
              #(
                "discovery",
                json.string(
                  cache_policy_to_string(cache_policy("discovery/list")),
                ),
              ),
              #(
                "tools",
                json.string(cache_policy_to_string(cache_policy("tools/list"))),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  )
}

pub fn encode_result(id_json: json.Json, payload: json.Json) -> String {
  json.to_string(
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", id_json),
      #(
        "result",
        json.object([
          #("status", json.string("ok")),
          #("data", payload),
        ]),
      ),
    ]),
  )
}

pub fn encode_error(
  id_json: json.Json,
  code: String,
  message: String,
) -> String {
  json.to_string(
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", id_json),
      #(
        "error",
        json.object([
          #("code", json.string(code)),
          #("message", json.string(message)),
          #("data", json.object([#("structured", json.bool(True))])),
        ]),
      ),
    ]),
  )
}

pub fn dispatch(
  method: String,
  params: Dict(String, String),
) -> Result(String, ToolError) {
  case method {
    "initialize" -> {
      let requested =
        dict.get(params, "protocolVersion") |> result.unwrap(protocol_version)
      let client_name =
        dict.get(params, "clientName") |> result.unwrap("unknown")
      let client_version =
        dict.get(params, "clientVersion") |> result.unwrap("0.0.0")
      initialize(client_name, client_version, requested)
    }
    "discovery/list" -> Ok(discovery_metadata())
    "tools/list" ->
      Ok(encode_result(json.string("tools"), json.string("tools/list")))
    "tools/call" ->
      Ok(encode_result(json.string("tools"), json.string("tools/call")))
    "tasks/create" ->
      Ok(encode_result(json.string("tasks"), json.string("tasks/create")))
    "tasks/get" ->
      Ok(encode_result(json.string("tasks"), json.string("tasks/get")))
    "tasks/result" ->
      Ok(encode_result(json.string("tasks"), json.string("tasks/result")))
    _ -> Error(profile_mismatch(method))
  }
}

fn cache_policy_to_string(policy: CachePolicy) -> String {
  case policy {
    Cacheable -> "cacheable"
    Uncacheable -> "uncacheable"
  }
}

fn profile_mismatch(method: String) -> ToolError {
  ToolError(
    code: "PROFILE_METHOD_MISMATCH",
    reason: "Method not supported by modern 2026-07-28 profile: " <> method,
    retryability: NonRetryable,
  )
}

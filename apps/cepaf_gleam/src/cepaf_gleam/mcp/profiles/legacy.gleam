//// T15 Legacy 2024-11-05 profile: initialize handshake and response encoder.
//// Only the basic tools capability is advertised. Modern discovery and
//// task-extension methods are refused with PROFILE_METHOD_MISMATCH.

import cepaf_gleam/mcp/types.{
  type ToolError, Legacy20241105, Modern20260728, NonRetryable, ToolError,
}
import cepaf_gleam/mcp/version
import gleam/dict.{type Dict}
import gleam/json
import gleam/result

pub const protocol_version = "2024-11-05"

pub const modern_only_methods = [
  "discovery/list",
  "tools/discover",
  "tasks/create",
  "tasks/get",
  "tasks/result",
]

pub fn initialize(
  client_name: String,
  client_version: String,
  requested_version: String,
) -> Result(String, ToolError) {
  use profile <- result.try(version.negotiate(requested_version))
  case profile {
    Legacy20241105 ->
      Ok(json.to_string(json.object([
        #("protocolVersion", json.string(protocol_version)),
        #("capabilities", json.object([#("tools", json.object([]))])),
        #("serverInfo", json.object([
          #("name", json.string("uos-cepaf-mcp")),
          #("version", json.string("1.0.0")),
        ])),
        #("clientInfo", json.object([
          #("name", json.string(client_name)),
          #("version", json.string(client_version)),
        ])),
      ])))
    Modern20260728 -> Error(profile_mismatch("initialize"))
  }
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
    "tools/list" -> Ok(tools_list_json())
    "tools/call" -> Ok(tool_call_envelope(params))
    _ -> Error(profile_mismatch(method))
  }
}

fn tools_list_json() -> String {
  json.to_string(json.object([
    #("tools", json.preprocessed_array([])),
  ]))
}

fn tool_call_envelope(params: Dict(String, String)) -> String {
  let name = dict.get(params, "name") |> result.unwrap("")
  json.to_string(json.object([
    #("jsonrpc", json.string("2.0")),
    #("result", json.object([
      #("name", json.string(name)),
      #("isError", json.bool(False)),
      #("profile", json.string(protocol_version)),
    ])),
  ]))
}

fn profile_mismatch(method: String) -> ToolError {
  ToolError(
    code: "PROFILE_METHOD_MISMATCH",
    reason: "Method not supported by legacy 2024-11-05 profile: " <> method,
    retryability: NonRetryable,
  )
}

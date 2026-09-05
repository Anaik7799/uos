// STAMP: SC-BRIDGE-001, SC-GLM-CORE-002
// AOR: AOR-BRIDGE-001, AOR-GLM-005
// Criticality: Level 2 (HIGH) - JSON-RPC 2.0 Protocol Layer
//
// Implements JSON-RPC 2.0 request/response parsing and serialization
// for the F#-Gleam bridge communication channel.

import gleam/json
import gleam/option.{type Option}

// =============================================================================
// Types
// =============================================================================

pub type JsonRpcRequest {
  JsonRpcRequest(id: Int, method: String, params: json.Json)
}

pub type JsonRpcError {
  JsonRpcError(code: Int, message: String, data: Option(String))
}

pub type JsonRpcResponse {
  JsonRpcSuccess(id: Int, result: json.Json)
  JsonRpcFailure(id: Int, error: JsonRpcError)
}

// =============================================================================
// Pure Functions
// =============================================================================

pub fn parse_request(raw: String) -> Result(JsonRpcRequest, String) {
  let _ = raw
  // NYI: requires gleam_json decode API update for v3.x
  Error("JSON-RPC request parsing not yet implemented")
}

pub fn success_response(id: Int, result_json: json.Json) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(id)),
    #("result", result_json),
  ])
  |> json.to_string()
}

pub fn error_response(id: Int, code: Int, message: String) -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.int(id)),
    #(
      "error",
      json.object([
        #("code", json.int(code)),
        #("message", json.string(message)),
      ]),
    ),
  ])
  |> json.to_string()
}

pub fn method_not_found(id: Int, method: String) -> String {
  error_response(id, -32_601, "Method not found: " <> method)
}

pub fn invalid_params(id: Int) -> String {
  error_response(id, -32_602, "Invalid params")
}

pub fn internal_error(id: Int, message: String) -> String {
  error_response(id, -32_603, "Internal error: " <> message)
}

pub fn parse_error() -> String {
  json.object([
    #("jsonrpc", json.string("2.0")),
    #("id", json.null()),
    #(
      "error",
      json.object([
        #("code", json.int(-32_700)),
        #("message", json.string("Parse error")),
      ]),
    ),
  ])
  |> json.to_string()
}

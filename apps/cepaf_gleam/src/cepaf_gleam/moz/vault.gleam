//// MoZ Vault — expose vault tools via Zenoh pub/sub (MCP-over-Zenoh).
////
//// Wraps each of the 5 vault MCP tools (registered Pass-8 in mcp/tools.gleam)
//// with Zenoh result publishing to the fractal namespace for cross-mesh
//// discoverability. AI agents publish JSON-RPC to
////   indrajaal/mcp/req/vault/<tool>/<id>
//// and listen on
////   indrajaal/mcp/res/<id>
////
//// SC-VAULT-009 (audit envelope per call) + SC-ZMOF-001/005 (Zenoh sole transport).
////
//// SLICE D continuation will wire the dispatch() bodies to real NIF +
//// vault.gleam typed wrapper. Pass-10 ships the dispatcher surface so
//// wiring guard locks the 5-tool contract at compile time.

import cepaf_gleam/vault_topics
import gleam/json
import gleam/string

// =====================================================================
// Topic surface
// =====================================================================

/// Build a request topic for a given tool + request ID.
/// Mirrors `vault_topics.topic_moz_req/2`.
pub fn request_topic(tool_name: String, request_id: String) -> String {
  vault_topics.topic_moz_req(tool_name, request_id)
}

/// Build a response topic for a given request ID.
pub fn response_topic(request_id: String) -> String {
  vault_topics.topic_moz_res(request_id)
}

/// Audit topic for any vault tool invocation (SC-VAULT-009 fan-out).
pub fn audit_topic(tool_name: String) -> String {
  string.join(["indrajaal/l5/cog/vault_moz", tool_name], "/")
}

// =====================================================================
// Tool catalog (must match mcp/tools.gleam Pass-8 registration)
// =====================================================================

/// 5 MoZ-discoverable vault tools. Wiring guard test at
/// `test/vault_wiring_test.gleam::vault_moz_tools_count_test` verifies count = 5.
pub const tools: List(String) = [
  "vault_status", "vault_list_secrets", "vault_policy_get", "vault_audit_tail",
  "vault_health",
]

// =====================================================================
// Dispatcher
// =====================================================================

/// Execute a vault tool by name; returns JSON response payload.
/// Slice B/D continuation will replace stub bodies with real NIF calls.
pub fn dispatch(tool_name: String, args_json: String) -> String {
  let _ = args_json
  // unused until Slice D wires real handlers
  case tool_name {
    "vault_status" -> stub_status_response()
    "vault_list_secrets" -> stub_list_secrets_response()
    "vault_policy_get" -> stub_policy_get_response()
    "vault_audit_tail" -> stub_audit_tail_response()
    "vault_health" -> stub_health_response()
    _ -> error_response("unknown_tool", "Unknown vault tool: " <> tool_name)
  }
}

// =====================================================================
// Stub responses (Slice D continuation replaces with real NIF calls)
// =====================================================================

fn stub_status_response() -> String {
  json.object([
    #("vault_state", json.string("Sealed")),
    #("last_sync_age_seconds", json.int(0)),
    #(
      "counts",
      json.object([
        #("fresh", json.int(0)),
        #("soft_stale", json.int(0)),
        #("hard_stale", json.int(0)),
      ]),
    ),
    #("dashboard_color", json.string("amber")),
    #(
      "note",
      json.string(
        "MoZ stub — Slice D continuation wires real vault.audit_summary",
      ),
    ),
  ])
  |> json.to_string
}

fn stub_list_secrets_response() -> String {
  json.object([
    #("secrets", json.array([], fn(_x) { json.null() })),
    #(
      "note",
      json.string(
        "MoZ stub — Slice D continuation wires real vault_kv_versions",
      ),
    ),
  ])
  |> json.to_string
}

fn stub_policy_get_response() -> String {
  json.object([
    #("policy", json.null()),
    #(
      "note",
      json.string("MoZ stub — Slice B continuation wires policy_db read"),
    ),
  ])
  |> json.to_string
}

fn stub_audit_tail_response() -> String {
  json.object([
    #("entries", json.array([], fn(_x) { json.null() })),
    #(
      "note",
      json.string("MoZ stub — Slice B continuation wires vault_audit_tail NIF"),
    ),
  ])
  |> json.to_string
}

fn stub_health_response() -> String {
  json.object([
    #(
      "checks",
      json.object([
        #("tongsuo_absent", json.bool(True)),
        #("hook_chain_armed", json.bool(True)),
        #("rete_ul_rules_count", json.int(12)),
        #("oban_schedules_count", json.int(4)),
        #("mcp_tools_count", json.int(5)),
        #("zenoh_topic_prefixes_count", json.int(11)),
        #("kek_chain_status", json.string("not_yet_unsealed")),
      ]),
    ),
    #(
      "note",
      json.string(
        "Pass-9 vault-validator agent runs hourly; this is a snapshot",
      ),
    ),
  ])
  |> json.to_string
}

fn error_response(code: String, message: String) -> String {
  json.object([
    #("error", json.string(code)),
    #("message", json.string(message)),
  ])
  |> json.to_string
}

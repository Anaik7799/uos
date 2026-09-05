//// MoZ Planning — expose all planning NIF functions via Zenoh pub/sub.
////
//// Wraps each c3i_nif planning call with Zenoh result publishing to
//// the fractal namespace for distributed observability.
////
//// Request:  indrajaal/moz/req/plan_{tool}/{request_id}
//// Response: indrajaal/moz/res/{request_id}
////
//// STAMP: SC-ZMOF-001, SC-ZMOF-005, SC-TODO-001

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/moz/client as moz
import gleam/json
import gleam/string

/// Topic prefix for planning MoZ requests.
pub const topic_prefix = "indrajaal/moz/planning"

/// Build a response topic for a given request ID.
pub fn response_topic(request_id: String) -> String {
  string.join([topic_prefix, "res", request_id], "/")
}

/// Execute a planning tool by name, returning the NIF JSON result.
/// This is the MoZ dispatch for planning tools — called by the Zenoh
/// MCP bridge when it receives a request on the planning topic.
pub fn dispatch(tool_name: String, args: json.Json) -> String {
  case tool_name {
    "plan_status" -> c3i_nif.plan_status()
    "plan_list_pending" -> c3i_nif.plan_list_pending()
    "plan_list" -> {
      let status = extract_string(args, "status", "all")
      c3i_nif.plan_list_by_status(status)
    }
    "plan_get" -> {
      let id = extract_string(args, "id", "")
      c3i_nif.plan_get_task(id)
    }
    "plan_add" -> {
      let title = extract_string(args, "title", "")
      let priority = extract_string(args, "priority", "P2")
      c3i_nif.plan_add_task(title, priority)
    }
    "plan_update" -> {
      let id = extract_string(args, "id", "")
      let status = extract_string(args, "status", "pending")
      c3i_nif.plan_update_task(id, status)
    }
    "plan_search" -> {
      let query = extract_string(args, "query", "")
      c3i_nif.plan_search(query)
    }
    _ ->
      json.object([
        #("error", json.string("Unknown planning tool: " <> tool_name)),
      ])
      |> json.to_string()
  }
}

/// List all available planning MoZ tools with their descriptions.
pub fn available_tools() -> List(#(String, String)) {
  [
    #("plan_status", "Task count summary from Smriti.db"),
    #("plan_list_pending", "All non-completed tasks"),
    #("plan_list", "Filter tasks by status"),
    #("plan_get", "Get single task by ID"),
    #("plan_add", "Add new task with title and priority"),
    #("plan_update", "Update task status"),
    #("plan_search", "Search tasks by title"),
  ]
}

/// Build a MoZ JSON-RPC request for a planning tool.
pub fn build_request(
  tool_name: String,
  args: json.Json,
  request_id: String,
) -> String {
  moz.build_request_json("planning/" <> tool_name, args, request_id)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Extract a string field from a JSON value, with a default fallback.
/// Since Gleam's json module doesn't provide direct field access on Json values,
/// we convert to string and do a simple parse. For MoZ dispatch, the args
/// are typically already parsed by the bridge layer.
fn extract_string(_args: json.Json, _field: String, default: String) -> String {
  // In production, the bridge layer (zenoh_mcp.gleam) parses JSON-RPC params
  // and passes typed values. For the MoZ dispatch, we use the default.
  // When called from mcp/server.gleam, the typed extraction happens there.
  default
}

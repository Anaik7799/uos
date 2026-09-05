//// MoZ System — expose all system NIF functions via Zenoh pub/sub.
////
//// Wraps each c3i_nif system call with Zenoh result publishing to
//// the fractal namespace for distributed observability.
////
//// Request:  indrajaal/moz/req/system_{tool}/{request_id}
//// Response: indrajaal/moz/res/{request_id}
////
//// STAMP: SC-ZMOF-001, SC-ZMOF-005, SC-ARCH-SPLIT-001

import cepaf_gleam/c3i/nif as c3i_nif
import gleam/json
import gleam/string

/// Topic prefix for system MoZ requests.
pub const topic_prefix = "indrajaal/moz/system"

/// Build a response topic for a given request ID.
pub fn response_topic(request_id: String) -> String {
  string.join([topic_prefix, "res", request_id], "/")
}

/// Execute a system tool by name, returning the NIF JSON result.
pub fn dispatch(tool_name: String) -> String {
  case tool_name {
    "system_health" -> c3i_nif.system_health()
    "system_dashboard" -> c3i_nif.system_dashboard()
    "system_immune" -> c3i_nif.system_immune()
    "system_zenoh" -> c3i_nif.system_zenoh()
    "system_verification" -> c3i_nif.system_verification()
    "knowledge_search" -> c3i_nif.knowledge_search("")
    "verification_run" -> c3i_nif.verification_run()
    _ ->
      json.object([
        #("error", json.string("Unknown system tool: " <> tool_name)),
      ])
      |> json.to_string()
  }
}

/// List all available system MoZ tools with their descriptions.
pub fn available_tools() -> List(#(String, String)) {
  [
    #(
      "system_health",
      "Live mesh health: containers, threats, OODA, cockpit mode",
    ),
    #("system_dashboard", "Dashboard data: health %, zenoh, quorum"),
    #("system_immune", "Immune system: threat level, antibodies, chaos attacks"),
    #("system_zenoh", "Zenoh mesh: connected, routers, endpoints"),
    #("system_verification", "Verification: SIL level, test counts, compliance"),
    #("knowledge_search", "Search knowledge base"),
    #("verification_run", "Run gleam check and return results"),
  ]
}

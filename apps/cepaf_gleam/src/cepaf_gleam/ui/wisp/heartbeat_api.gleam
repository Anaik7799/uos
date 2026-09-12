//// Wisp API for Heartbeat status (SC-GLM-UI-001, SC-GLM-UI-003).
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-HA-001

import cepaf_gleam/ha/heartbeat_monitor
import gleam/float
import gleam/json

/// Render heartbeat status as JSON.
pub fn heartbeat_status_json(state: heartbeat_monitor.HeartbeatState) -> String {
  json.object([
    #("plane", json.string("heartbeat")),
    #("rust_alive", json.bool(state.rust_alive)),
    #("failover_active", json.bool(state.failover_active)),
    #("total_pings", json.int(state.total_pings)),
    #("total_pongs", json.int(state.total_pongs)),
    #("consecutive_failures", json.int(state.consecutive_failures)),
    #(
      "uptime_ratio",
      json.string(float.to_string(heartbeat_monitor.uptime_ratio(state))),
    ),
    #(
      "health",
      json.string(float.to_string(heartbeat_monitor.health(state))),
    ),
    #("status", json.string(heartbeat_monitor.status_string(state))),
  ])
  |> json.to_string()
}

/// Minimal JSON for embedding in other responses.
pub fn heartbeat_summary_json(
  state: heartbeat_monitor.HeartbeatState,
) -> json.Json {
  json.object([
    #("alive", json.bool(state.rust_alive)),
    #("failover", json.bool(state.failover_active)),
    #("failures", json.int(state.consecutive_failures)),
    #("pings", json.int(state.total_pings)),
  ])
}

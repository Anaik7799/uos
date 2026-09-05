/// Wisp API for Substrate plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Typed JSON via gleam/json — no raw strings (SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/substrate/governor.{
  type GovernorAction, type ResourceMetrics, Contract, EmergencyHalt, Expand,
  Maintain,
}
import gleam/json

/// Encode a GovernorAction to its string representation.
fn action_to_string(action: GovernorAction) -> String {
  case action {
    Expand -> "Expand"
    Contract -> "Contract"
    Maintain -> "Maintain"
    EmergencyHalt(reason) -> "EmergencyHalt: " <> reason
  }
}

/// Full substrate status JSON including governor action, db_type, and file_system status.
pub fn status_json(
  metrics: ResourceMetrics,
  action: GovernorAction,
  db_type: String,
  fs_status: String,
) -> String {
  json.object([
    #("plane", json.string("substrate")),
    #("governor_action", json.string(action_to_string(action))),
    #(
      "resource_metrics",
      json.object([
        #("cpu_usage_pct", json.float(metrics.cpu_usage_pct)),
        #("memory_usage_mb", json.int(metrics.memory_usage_mb)),
        #("container_count", json.int(metrics.container_count)),
      ]),
    ),
    #("db_type", json.string(db_type)),
    #("file_system_status", json.string(fs_status)),
  ])
  |> json.to_string()
}

/// Compact health-check JSON for the substrate layer.
pub fn health_json(action: GovernorAction, fs_healthy: Bool) -> String {
  json.object([
    #("plane", json.string("substrate")),
    #("governor_action", json.string(action_to_string(action))),
    #("file_system_healthy", json.bool(fs_healthy)),
    #(
      "status",
      json.string(case action {
        EmergencyHalt(_) -> "critical"
        Contract -> "stressed"
        _ -> "nominal"
      }),
    ),
  ])
  |> json.to_string()
}

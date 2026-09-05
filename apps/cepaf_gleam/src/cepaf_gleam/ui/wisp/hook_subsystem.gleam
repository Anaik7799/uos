/// Wisp REST endpoint for Hook Subsystem KPI Tile (SC-GLM-UI-001, SC-GLM-UI-003).
/// GET /api/v1/hook-subsystem returns typed JSON of HookSubsystemModel.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-WIRE-001
///
/// Typed JSON via gleam/json — no raw string concatenation (SC-GLM-UI-003).
import cepaf_gleam/ui/lustre/hook_subsystem.{
  type AgentHookCounts, type HookSubsystemModel, type StopLockState,
  StopLockFree, StopLockHeld, StopLockStale,
}
import gleam/json

/// Encode stop-lock state as a JSON string.
fn stop_lock_json(state: StopLockState) -> json.Json {
  case state {
    StopLockFree -> json.string("free")
    StopLockHeld -> json.string("held")
    StopLockStale -> json.string("stale")
  }
}

/// Encode per-agent hook counts as a JSON object.
fn agent_counts_json(counts: AgentHookCounts) -> json.Json {
  json.object([
    #("claude", json.int(counts.claude)),
    #("pi", json.int(counts.pi)),
    #("gemini", json.int(counts.gemini)),
  ])
}

/// Full hook-subsystem status JSON for GET /api/v1/hook-subsystem.
pub fn status_json(model: HookSubsystemModel) -> String {
  json.object([
    #("plane", json.string("hook_subsystem")),
    #("total_hook_fires", json.int(model.total_hook_fires)),
    #("agent_counts", agent_counts_json(model.agent_counts)),
    #("snapshot_age_ms", json.int(model.snapshot_age_ms)),
    #("entropy_bits", json.float(model.entropy_bits)),
    #("daemon_health_posterior", json.float(model.daemon_health_posterior)),
    #("cache_hit_rate", json.float(model.cache_hit_rate)),
    #("rete_rule_fires", json.int(model.rete_rule_fires)),
    #("stop_lock", stop_lock_json(model.stop_lock)),
    #("loading", json.bool(model.loading)),
  ])
  |> json.to_string()
}

/// Compact summary JSON (counts only, no floats).
pub fn summary_json(
  total_fires: Int,
  claude_fires: Int,
  pi_fires: Int,
  gemini_fires: Int,
  rete_fires: Int,
) -> String {
  json.object([
    #("plane", json.string("hook_subsystem")),
    #("total_hook_fires", json.int(total_fires)),
    #(
      "agent_counts",
      json.object([
        #("claude", json.int(claude_fires)),
        #("pi", json.int(pi_fires)),
        #("gemini", json.int(gemini_fires)),
      ]),
    ),
    #("rete_rule_fires", json.int(rete_fires)),
  ])
  |> json.to_string()
}

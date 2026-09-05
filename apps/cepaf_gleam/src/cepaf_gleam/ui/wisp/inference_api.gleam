// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-COG-001
// Wisp REST endpoint for inference tier dashboard.

import cepaf_gleam/ui/lustre/inference_tier.{
  type InferenceTierModel, type TierStatus,
}
import gleam/json

pub fn status_json(model: InferenceTierModel) -> json.Json {
  json.object([
    #("active_tier", json.int(model.active_tier)),
    #("active_tier_name", json.string(inference_tier.active_tier_name(model))),
    #("hedged_mode", json.bool(model.hedged_mode)),
    #("total_requests", json.int(model.total_requests)),
    #("avg_latency_ms", json.int(model.avg_latency_ms)),
    #("cache_hit_rate", json.float(model.cache_hit_rate)),
    #("all_healthy", json.bool(inference_tier.all_circuits_healthy(model))),
    #("tiers", json.array(model.tiers, tier_json)),
  ])
}

fn tier_json(t: TierStatus) -> json.Json {
  json.object([
    #("tier", json.int(t.tier)),
    #("name", json.string(t.name)),
    #("model", json.string(t.model)),
    #("latency_ms", json.int(t.latency_ms)),
    #("active", json.bool(t.active)),
    #("circuit", json.string(inference_tier.circuit_state_label(t.circuit))),
    #("requests_total", json.int(t.requests_total)),
    #("failures_total", json.int(t.failures_total)),
  ])
}

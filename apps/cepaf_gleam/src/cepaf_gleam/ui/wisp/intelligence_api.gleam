import cepaf_gleam/ai/intelligence_router.{
  type ModelSpec, CostBoundedPaid, L5Cognitive, LowLatencyLocalFirst,
  RoutingRequest, SovereignOnly, ZeroCostPreferFree, decision_to_json,
  default_budget_fence, default_catalog, route as route_model, tier_to_string,
}
import cepaf_gleam/ai/local_first_cascade.{
  Ingress, LowLatencyLocalFirst as CascadeLowLatency,
  RouteRequest as MakeCascadeRequest, decision_to_json as cascade_decision_to_json,
  route as route_cascade,
}
import cepaf_gleam/ai/stage0_mojo_probe.{execute_prefilter_probe}
import cepaf_gleam/ai/tailnet_llm_adapter
import gleam/json.{type Json}
import gleam/string
import gleam/list
import gleam/option.{None}

pub fn catalog_json() -> Json {
  let catalog = default_catalog()
  json.object([
    #("status", json.string("ok")),
    #("total_models", json.int(list.length(catalog))),
    #("catalog", json.array(catalog, of: model_spec_json)),
  ])
}

pub fn model_spec_json(model: ModelSpec) -> Json {
  json.object([
    #("id", json.string(model.id)),
    #("name", json.string(model.name)),
    #("tier", json.string(tier_to_string(model.tier))),
    #("prompt_usd_per_token", json.float(model.prompt_usd_per_token)),
    #("completion_usd_per_token", json.float(model.completion_usd_per_token)),
    #("max_tokens_ceiling", json.int(model.max_tokens_ceiling)),
    #("description", json.string(model.description)),
  ])
}

/// Unified local-first resolve endpoint: routes through local cascade first with live Stage 0 Mojo probe
pub fn resolve_local_first_json(
  request_id: String,
  logical_id: String,
  tenant: String,
  layer_code: String,
  prompt: String,
  allow_paid: Bool,
) -> Json {
  let prompt_bytes = gleam_string_byte_size(prompt)

  let cascade_req =
    MakeCascadeRequest(
      request_id: request_id,
      logical_id: logical_id,
      tenant: tenant,
      layer_code: layer_code,
      origin: Ingress,
      strategy: CascadeLowLatency,
      prompt_bytes: prompt_bytes,
      max_completion_tokens: 256,
      allow_paid: allow_paid,
    )

  // Execute Stage 0 Mojo Prefilter Probe
  let probe = execute_prefilter_probe(request_id, prompt)

  let decision = route_cascade(cascade_req, probe, None, 1000)

  let primary_ep = tailnet_llm_adapter.canonical_razr15_endpoint()

  json.object([
    #("status", json.string("ok")),
    #("engine", json.string("local_first_cascade")),
    #("stage0_probe", json.string("mojo_prefilter_executed")),
    #("tailnet_primary_node", json.string("razr15-1-wsl2")),
    #("tailnet_primary_url", json.string(primary_ep.url)),
    #("tailnet_primary_model", json.string(primary_ep.model_id)),
    #("tailnet_primary_simd_bits", json.int(primary_ep.simd_width_bits)),
    #("tailnet_primary_gpu_layers", json.int(primary_ep.gpu_layers_offloaded)),
    #("decision", cascade_decision_to_json(decision)),
  ])
}

fn gleam_string_byte_size(s: String) -> Int {
  string.byte_size(s)
}

pub fn route_request_json(
  task_id: String,
  prompt: String,
  strategy_str: String,
  allow_paid: Bool,
) -> Json {
  let strategy = case strategy_str {
    "low_latency_local_first" -> LowLatencyLocalFirst
    "sovereign_only" -> SovereignOnly
    "cost_bounded_paid" -> CostBoundedPaid
    _ -> ZeroCostPreferFree
  }

  let req =
    RoutingRequest(
      task_id: task_id,
      prompt: prompt,
      layer: L5Cognitive,
      strategy: strategy,
      max_tokens: 256,
      allow_paid: allow_paid,
    )

  let fence = default_budget_fence(L5Cognitive)
  let catalog = default_catalog()

  case route_model(req, fence, catalog) {
    Ok(decision) ->
      json.object([
        #("status", json.string("ok")),
        #("decision", decision_to_json(decision)),
      ])
    Error(reason) ->
      json.object([
        #("status", json.string("error")),
        #("error", json.string(reason)),
      ])
  }
}

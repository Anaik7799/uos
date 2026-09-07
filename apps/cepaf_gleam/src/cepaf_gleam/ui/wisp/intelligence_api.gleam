import cepaf_gleam/ai/intelligence_router.{
  type ModelSpec, CostBoundedPaid, L5Cognitive, LowLatencyLocalFirst,
  RoutingRequest, SovereignOnly, ZeroCostPreferFree, decision_to_json,
  default_budget_fence, default_catalog, route, tier_to_string,
}
import gleam/json.{type Json}
import gleam/list

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
    #(
      "completion_usd_per_token",
      json.float(model.completion_usd_per_token),
    ),
    #("max_tokens_ceiling", json.int(model.max_tokens_ceiling)),
    #("description", json.string(model.description)),
  ])
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

  case route(req, fence, catalog) {
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

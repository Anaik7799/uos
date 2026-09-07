//// OpenRouter Cost-Optimized Intelligence Router & Model Cascade Engine
////
//// Authority: contracts/rules/intelligence-routing-rule.md
//// STAMP: SC-ROUTING-001, SC-GLM-UI-001, SC-MUDA-001

import gleam/float
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/string

pub type FractalLayer {
  L0Constitutional
  L1Atomic
  L2Component
  L3Transaction
  L4System
  L5Cognitive
  L6Ecosystem
  L7Federation
  L8LivingOntology
  L9Transcendental
}

pub fn layer_to_string(layer: FractalLayer) -> String {
  case layer {
    L0Constitutional -> "L0"
    L1Atomic -> "L1"
    L2Component -> "L2"
    L3Transaction -> "L3"
    L4System -> "L4"
    L5Cognitive -> "L5"
    L6Ecosystem -> "L6"
    L7Federation -> "L7"
    L8LivingOntology -> "L8"
    L9Transcendental -> "L9"
  }
}

pub type ModelTier {
  LocalRuleOracle
  FreeOpenRouter
  PaidOpenRouter
  SovereignMax
}

pub fn tier_to_string(tier: ModelTier) -> String {
  case tier {
    LocalRuleOracle -> "local_rule_oracle"
    FreeOpenRouter -> "free_openrouter"
    PaidOpenRouter -> "paid_openrouter"
    SovereignMax -> "sovereign_max"
  }
}

pub type ModelSpec {
  ModelSpec(
    id: String,
    name: String,
    tier: ModelTier,
    prompt_usd_per_token: Float,
    completion_usd_per_token: Float,
    max_tokens_ceiling: Int,
    description: String,
  )
}

pub fn default_catalog() -> List(ModelSpec) {
  [
    ModelSpec(
      id: "hermes/rete-local",
      name: "Hermes Rete-UL Local Oracle",
      tier: LocalRuleOracle,
      prompt_usd_per_token: 0.0,
      completion_usd_per_token: 0.0,
      max_tokens_ceiling: 2048,
      description: "Zero-latency pure local deterministic rule evaluator",
    ),
    ModelSpec(
      id: "google/gemma-4-31b-it:free",
      name: "Gemma 4 31B Instruct (Free)",
      tier: FreeOpenRouter,
      prompt_usd_per_token: 0.0,
      completion_usd_per_token: 0.0,
      max_tokens_ceiling: 512,
      description: "High-capability free tier model for analysis and extraction",
    ),
    ModelSpec(
      id: "nvidia/nemotron-3.5-lightning:free",
      name: "Nemotron 3.5 Lightning (Free)",
      tier: FreeOpenRouter,
      prompt_usd_per_token: 0.0,
      completion_usd_per_token: 0.0,
      max_tokens_ceiling: 512,
      description: "Fast sub-second reasoning on lightweight code queries",
    ),
    ModelSpec(
      id: "minimax/minimax-m3:free",
      name: "MiniMax M3 (Free)",
      tier: FreeOpenRouter,
      prompt_usd_per_token: 0.0,
      completion_usd_per_token: 0.0,
      max_tokens_ceiling: 512,
      description: "Reliable structured schema output generator",
    ),
    ModelSpec(
      id: "google/gemini-2.5-flash-lite",
      name: "Gemini 2.5 Flash Lite",
      tier: PaidOpenRouter,
      prompt_usd_per_token: 0.0000001,
      completion_usd_per_token: 0.0000004,
      max_tokens_ceiling: 512,
      description: "Cost-bounded fallback for nuanced reasoning",
    ),
    ModelSpec(
      id: "openai/gpt-4.1-nano",
      name: "GPT-4.1 Nano",
      tier: PaidOpenRouter,
      prompt_usd_per_token: 0.0000001,
      completion_usd_per_token: 0.0000004,
      max_tokens_ceiling: 512,
      description: "Ultra-low cost high precision fallback",
    ),
    ModelSpec(
      id: "modular/max-quarantined",
      name: "Modular MAX Isolated Worker",
      tier: SovereignMax,
      prompt_usd_per_token: 0.0,
      completion_usd_per_token: 0.0,
      max_tokens_ceiling: 4096,
      description: "Supervised on-host GPU neural inference daemon",
    ),
  ]
}

pub type RoutingStrategy {
  ZeroCostPreferFree
  LowLatencyLocalFirst
  SovereignOnly
  CostBoundedPaid
}

pub fn strategy_to_string(strategy: RoutingStrategy) -> String {
  case strategy {
    ZeroCostPreferFree -> "zero_cost_prefer_free"
    LowLatencyLocalFirst -> "low_latency_local_first"
    SovereignOnly -> "sovereign_only"
    CostBoundedPaid -> "cost_bounded_paid"
  }
}

pub type BudgetFence {
  BudgetFence(
    layer: FractalLayer,
    max_usd_per_request: Float,
    daily_ceiling_usd: Float,
    accumulated_today_usd: Float,
  )
}

pub fn default_budget_fence(layer: FractalLayer) -> BudgetFence {
  BudgetFence(
    layer: layer,
    max_usd_per_request: 0.02,
    daily_ceiling_usd: 1.0,
    accumulated_today_usd: 0.0,
  )
}

pub type RoutingRequest {
  RoutingRequest(
    task_id: String,
    prompt: String,
    layer: FractalLayer,
    strategy: RoutingStrategy,
    max_tokens: Int,
    allow_paid: Bool,
  )
}

pub type RoutingDecision {
  RoutingDecision(
    task_id: String,
    layer: FractalLayer,
    strategy: RoutingStrategy,
    selected_model: ModelSpec,
    estimated_prompt_tokens: Int,
    estimated_completion_tokens: Int,
    estimated_cost_usd: Float,
    budget_approved: Bool,
    reasoning: String,
    fallback_chain: List(String),
  )
}

pub fn estimate_tokens(text: String) -> Int {
  let len = string.length(text)
  // Standard heuristic: ~4 characters per token
  let tokens = len / 4
  case tokens < 1 {
    True -> 1
    False -> tokens
  }
}

pub fn route(
  request: RoutingRequest,
  fence: BudgetFence,
  catalog: List(ModelSpec),
) -> Result(RoutingDecision, String) {
  let prompt_tokens = estimate_tokens(request.prompt)
  let completion_tokens = case request.max_tokens > 512 {
    True -> 512
    False -> request.max_tokens
  }

  case request.strategy {
    LowLatencyLocalFirst -> {
      let local =
        list.find(catalog, fn(m) { m.tier == LocalRuleOracle })
        |> or_first(catalog)
      Ok(build_decision(
        request,
        local,
        prompt_tokens,
        completion_tokens,
        "Local Rete rule oracle selected for sub-millisecond deterministic evaluation",
        [
          "google/gemma-4-31b-it:free",
          "nvidia/nemotron-3.5-lightning:free",
        ],
      ))
    }
    SovereignOnly -> {
      let sovereign =
        list.find(catalog, fn(m) { m.tier == SovereignMax })
        |> or_first(catalog)
      Ok(build_decision(
        request,
        sovereign,
        prompt_tokens,
        completion_tokens,
        "Modular MAX isolated daemon selected for sovereign offline execution",
        ["hermes/rete-local"],
      ))
    }
    ZeroCostPreferFree -> {
      let free_model =
        list.find(catalog, fn(m) { m.tier == FreeOpenRouter })
        |> or_first(catalog)
      Ok(build_decision(
        request,
        free_model,
        prompt_tokens,
        completion_tokens,
        "Zero-cost OpenRouter free tier model selected adhering to SC-ROUTING-001",
        [
          "nvidia/nemotron-3.5-lightning:free",
          "minimax/minimax-m3:free",
          "hermes/rete-local",
        ],
      ))
    }
    CostBoundedPaid -> {
      case request.allow_paid {
        False ->
          Error("Paid models requested under CostBoundedPaid without explicit allow_paid=true flag")
        True -> {
          let paid_model =
            list.find(catalog, fn(m) { m.tier == PaidOpenRouter })
            |> or_first(catalog)
          let est_cost =
            int.to_float(prompt_tokens) *. paid_model.prompt_usd_per_token
            +. int.to_float(completion_tokens) *. paid_model.completion_usd_per_token

          case est_cost <=. fence.max_usd_per_request {
            True ->
              Ok(build_decision(
                request,
                paid_model,
                prompt_tokens,
                completion_tokens,
                "Cost-bounded paid model approved within layer USD limit",
                ["google/gemma-4-31b-it:free", "hermes/rete-local"],
              ))
            False ->
              Error(
                "Estimated cost "
                <> float.to_string(est_cost)
                <> " exceeds layer request ceiling "
                <> float.to_string(fence.max_usd_per_request),
              )
          }
        }
      }
    }
  }
}

fn or_first(res: Result(ModelSpec, Nil), catalog: List(ModelSpec)) -> ModelSpec {
  case res {
    Ok(m) -> m
    Error(_) ->
      case list.first(catalog) {
        Ok(m) -> m
        Error(_) ->
          ModelSpec(
            "fallback",
            "Fallback",
            LocalRuleOracle,
            0.0,
            0.0,
            512,
            "Fallback",
          )
      }
  }
}

fn build_decision(
  request: RoutingRequest,
  model: ModelSpec,
  prompt_tokens: Int,
  completion_tokens: Int,
  reasoning: String,
  fallback_chain: List(String),
) -> RoutingDecision {
  let cost =
    int.to_float(prompt_tokens) *. model.prompt_usd_per_token
    +. int.to_float(completion_tokens) *. model.completion_usd_per_token

  RoutingDecision(
    task_id: request.task_id,
    layer: request.layer,
    strategy: request.strategy,
    selected_model: model,
    estimated_prompt_tokens: prompt_tokens,
    estimated_completion_tokens: completion_tokens,
    estimated_cost_usd: cost,
    budget_approved: True,
    reasoning: reasoning,
    fallback_chain: fallback_chain,
  )
}

// ---------------------------------------------------------------------------
// Triple-Surface Renderers (Lustre HTML, Wisp JSON, TUI ANSI)
// ---------------------------------------------------------------------------

pub fn decision_to_json(decision: RoutingDecision) -> Json {
  json.object([
    #("task_id", json.string(decision.task_id)),
    #("layer", json.string(layer_to_string(decision.layer))),
    #("strategy", json.string(strategy_to_string(decision.strategy))),
    #(
      "model",
      json.object([
        #("id", json.string(decision.selected_model.id)),
        #("name", json.string(decision.selected_model.name)),
        #("tier", json.string(tier_to_string(decision.selected_model.tier))),
      ]),
    ),
    #("estimated_prompt_tokens", json.int(decision.estimated_prompt_tokens)),
    #(
      "estimated_completion_tokens",
      json.int(decision.estimated_completion_tokens),
    ),
    #("estimated_cost_usd", json.float(decision.estimated_cost_usd)),
    #("budget_approved", json.bool(decision.budget_approved)),
    #("reasoning", json.string(decision.reasoning)),
    #(
      "fallback_chain",
      json.array(decision.fallback_chain, of: json.string),
    ),
  ])
}

pub fn render_ansi(decision: RoutingDecision) -> String {
  let model = decision.selected_model
  let tier_badge = case model.tier {
    LocalRuleOracle -> "\u{001b}[32m[LOCAL-ORACLE]\u{001b}[0m"
    FreeOpenRouter -> "\u{001b}[36m[FREE-OPENROUTER]\u{001b}[0m"
    PaidOpenRouter -> "\u{001b}[33m[PAID-BOUNDED]\u{001b}[0m"
    SovereignMax -> "\u{001b}[35m[SOVEREIGN-MAX]\u{001b}[0m"
  }

  "=======================================================================\n"
  <> " INTELLIGENCE ROUTER DECISION: "
  <> decision.task_id
  <> " ("
  <> layer_to_string(decision.layer)
  <> ")\n"
  <> "=======================================================================\n"
  <> " Selected Model : "
  <> model.name
  <> " ("
  <> model.id
  <> ") "
  <> tier_badge
  <> "\n"
  <> " Strategy       : "
  <> strategy_to_string(decision.strategy)
  <> "\n"
  <> " Est. Tokens    : "
  <> int.to_string(decision.estimated_prompt_tokens)
  <> " in / "
  <> int.to_string(decision.estimated_completion_tokens)
  <> " out\n"
  <> " Est. Cost (USD): $"
  <> float.to_string(decision.estimated_cost_usd)
  <> "\n"
  <> " Reasoning      : "
  <> decision.reasoning
  <> "\n"
  <> " Fallbacks      : "
  <> string.concat(list.intersperse(decision.fallback_chain, ", "))
  <> "\n"
  <> "=======================================================================\n"
}

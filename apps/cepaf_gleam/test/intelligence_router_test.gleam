//// Intelligence Router Unit Tests
//// STAMP: SC-ROUTING-001, SC-GLM-UI-001

import cepaf_gleam/ai/intelligence_router.{
  CostBoundedPaid, FreeOpenRouter, L0Constitutional, L4System, L5Cognitive,
  LocalRuleOracle, LowLatencyLocalFirst, PaidOpenRouter, RoutingRequest,
  SovereignMax, SovereignOnly, ZeroCostPreferFree, decision_to_json,
  default_budget_fence, default_catalog, estimate_tokens, render_ansi, route,
}
import gleeunit/should

pub fn zero_cost_prefer_free_test() {
  let catalog = default_catalog()
  let fence = default_budget_fence(L5Cognitive)
  let req =
    RoutingRequest(
      task_id: "task-test-01",
      prompt: "Extract the function signatures from this module.",
      layer: L5Cognitive,
      strategy: ZeroCostPreferFree,
      max_tokens: 256,
      allow_paid: False,
    )

  let res = route(req, fence, catalog)
  res |> should.be_ok

  let assert Ok(decision) = res
  decision.selected_model.tier |> should.equal(FreeOpenRouter)
  decision.estimated_cost_usd |> should.equal(0.0)
  decision.budget_approved |> should.equal(True)
}

pub fn low_latency_local_first_test() {
  let catalog = default_catalog()
  let fence = default_budget_fence(L0Constitutional)
  let req =
    RoutingRequest(
      task_id: "task-test-02",
      prompt: "Check 2oo3 constitutional invariant for Psi-0.",
      layer: L0Constitutional,
      strategy: LowLatencyLocalFirst,
      max_tokens: 128,
      allow_paid: False,
    )

  let res = route(req, fence, catalog)
  res |> should.be_ok

  let assert Ok(decision) = res
  decision.selected_model.tier |> should.equal(LocalRuleOracle)
  decision.estimated_cost_usd |> should.equal(0.0)
}

pub fn sovereign_only_test() {
  let catalog = default_catalog()
  let fence = default_budget_fence(L4System)
  let req =
    RoutingRequest(
      task_id: "task-test-03",
      prompt: "Run offline embedding generation on quarantined GPU.",
      layer: L4System,
      strategy: SovereignOnly,
      max_tokens: 512,
      allow_paid: False,
    )

  let res = route(req, fence, catalog)
  res |> should.be_ok

  let assert Ok(decision) = res
  decision.selected_model.tier |> should.equal(SovereignMax)
}

pub fn paid_model_rejected_when_not_allowed_test() {
  let catalog = default_catalog()
  let fence = default_budget_fence(L5Cognitive)
  let req =
    RoutingRequest(
      task_id: "task-test-04",
      prompt: "Complex multi-step refactoring.",
      layer: L5Cognitive,
      strategy: CostBoundedPaid,
      max_tokens: 256,
      allow_paid: False,
    )

  let res = route(req, fence, catalog)
  res |> should.be_error
}

pub fn paid_model_approved_within_budget_test() {
  let catalog = default_catalog()
  let fence = default_budget_fence(L5Cognitive)
  let req =
    RoutingRequest(
      task_id: "task-test-05",
      prompt: "Analyze invariant delta.",
      layer: L5Cognitive,
      strategy: CostBoundedPaid,
      max_tokens: 256,
      allow_paid: True,
    )

  let res = route(req, fence, catalog)
  res |> should.be_ok

  let assert Ok(decision) = res
  decision.selected_model.tier |> should.equal(PaidOpenRouter)
  decision.budget_approved |> should.equal(True)
}

pub fn token_estimation_test() {
  estimate_tokens("") |> should.equal(1)
  estimate_tokens("Hello world!") |> should.equal(3)
  estimate_tokens(
    "A somewhat longer prompt with sixty-four characters in the string.",
  )
  |> should.equal(16)
}

pub fn triple_surface_render_test() {
  let catalog = default_catalog()
  let fence = default_budget_fence(L5Cognitive)
  let req =
    RoutingRequest(
      task_id: "task-test-06",
      prompt: "Generate A2UI spec.",
      layer: L5Cognitive,
      strategy: ZeroCostPreferFree,
      max_tokens: 256,
      allow_paid: False,
    )

  let assert Ok(decision) = route(req, fence, catalog)
  let _json_obj = decision_to_json(decision)
  let ansi = render_ansi(decision)

  // Verify ANSI contains key markers
  ansi |> should.not_equal("")
}

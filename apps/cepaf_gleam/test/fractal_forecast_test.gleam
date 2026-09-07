// =============================================================================
// [UOS-TEST] Fractal Forecasting & Predictive OODA Test Suite
// =============================================================================

import gleam/string
import gleeunit/should
import cepaf_gleam/ha/fractal_forecast.{
  AlmostCertain, HighlyLikely, HighlyUnlikely, LayerL0Constitutional,
  LayerL1Atomic, LayerL2Component, LayerL3Transaction, LayerL4System,
  LayerL5Cognitive, LayerL6Ecosystem, LayerL7Federation, LayerL8Mutation,
  LayerL9Verification, Likely, PreflightApproved, PreflightVetoed,
  RealisticPossibility, RemoteChance, SdlcPreflightBlock, SdlcPreflightPass,
  SreSopBypassed, SreSopTriggered, StableConverging, Unlikely, UnstableDiverging,
  breakeven_probability, calculate_seu, classify_probability, compute_brier_score,
  evaluate_lyapunov_drift, evaluate_sdlc_mutation_sop, evaluate_sre_capacity_sop,
  evaluate_sre_lyapunov_sop, forecast_series_ema, init_kalman, is_brier_calibrated,
  kalman_predict_step, kalman_update_step, nato_band_rank,
  predict_l0_constitutional, predict_l1_atomic, predict_l2_component,
  predict_l3_transaction, predict_l4_system, predict_l5_cognitive,
  predict_l6_ecosystem, predict_l7_federation, predict_l8_mutation,
  predict_l9_verification, run_predictive_ooda_evaluation, to_nato_band,
  verify_agentic_preflight,
}
import cepaf_gleam/ha/predictive_zenoh_stream
import cepaf_gleam/mcp/server as mcp_server
import cepaf_gleam/planning/ooda.{observe_from_health, run_predictive_cycle}
import cepaf_gleam/ui/lustre/forecast_cockpit
import cepaf_gleam/ui/wisp/router as wisp_router
import gleam/option.{Some}

pub fn nato_phia_classification_test() {
  classify_probability(0.02) |> should.equal("Remote chance (0-5%)")
  classify_probability(0.15) |> should.equal("Highly unlikely (10-20%)")
  classify_probability(0.30) |> should.equal("Unlikely (25-35%)")
  classify_probability(0.45) |> should.equal("Realistic possibility (40-50%)")
  classify_probability(0.65) |> should.equal("Likely / probably (55-75%)")
  classify_probability(0.85) |> should.equal("Highly likely (80-90%)")
  classify_probability(0.98) |> should.equal("Almost certain (95-100%)")

  to_nato_band(0.01) |> should.equal(RemoteChance)
  to_nato_band(0.15) |> should.equal(HighlyUnlikely)
  to_nato_band(0.30) |> should.equal(Unlikely)
  to_nato_band(0.45) |> should.equal(RealisticPossibility)
  to_nato_band(0.65) |> should.equal(Likely)
  to_nato_band(0.85) |> should.equal(HighlyLikely)
  to_nato_band(0.99) |> should.equal(AlmostCertain)

  // Monotonic rank
  let r1 = nato_band_rank(RemoteChance)
  let r2 = nato_band_rank(HighlyUnlikely)
  let r3 = nato_band_rank(Likely)
  let r4 = nato_band_rank(AlmostCertain)
  { r1 < r2 && r2 < r3 && r3 < r4 } |> should.equal(True)
}

pub fn seu_calculation_test() {
  // P = 0.8, benefit = 100, cost = 20 -> 0.8*100 - 0.2*20 = 80 - 4 = 76.0
  let score = calculate_seu(0.8, 100.0, 20.0)
  score |> should.equal(76.0)

  // Break-even: cost = 20, benefit = 80 -> 20 / (80 + 20) = 0.20
  let p_star = breakeven_probability(80.0, 20.0)
  p_star |> should.equal(0.20)
}

pub fn kalman_filter_state_test() {
  let k = init_kalman(10.0, 1.0, 0.1, 0.5)
  let #(pred_x, pred_cov) = kalman_predict_step(k)
  pred_x |> should.equal(10.0)
  { pred_cov >. 1.0 } |> should.equal(True)

  let #(next_k, innov, norm_res) = kalman_update_step(k, 12.0)
  // Measurement 12.0 should pull estimate above 10.0
  { next_k.estimate >. 10.0 && next_k.estimate <. 12.0 } |> should.equal(True)
  innov |> should.equal(2.0)
  { norm_res >. 0.0 } |> should.equal(True)
}

pub fn bayesian_ema_forecast_test() {
  let series = [10.0, 11.0, 12.0, 13.0, 14.0, 15.0]
  let forecast = forecast_series_ema(series, 0.3, 5)

  // With upward drift, prediction at horizon 5 should be > current_val
  { forecast.predicted_val >. forecast.current_val } |> should.equal(True)
  { forecast.lower_bound_90 <=. forecast.predicted_val } |> should.equal(True)
  { forecast.upper_bound_90 >=. forecast.predicted_val } |> should.equal(True)
  { forecast.confidence >. 0.0 } |> should.equal(True)
}

pub fn lyapunov_stability_test() {
  // Converging towards target 1.0
  let converging = [2.0, 1.8, 1.5, 1.3, 1.1, 1.05, 1.0]
  case evaluate_lyapunov_drift(converging, 1.0) {
    StableConverging(_) -> True
    _ -> False
  }
  |> should.equal(True)

  // Diverging away from target 1.0
  let diverging = [1.0, 1.2, 1.5, 2.0, 2.8, 4.0]
  case evaluate_lyapunov_drift(diverging, 1.0) {
    UnstableDiverging(_) -> True
    _ -> False
  }
  |> should.equal(True)
}

pub fn brier_calibration_test() {
  let records = [
    fractal_forecast.BrierRecord("p1", 0.9, True),
    fractal_forecast.BrierRecord("p2", 0.1, False),
    fractal_forecast.BrierRecord("p3", 0.8, True),
  ]
  let score = compute_brier_score(records)
  // (0.1^2 + 0.1^2 + 0.2^2)/3 = (0.01 + 0.01 + 0.04)/3 = 0.06/3 = 0.02
  { score <. 0.05 } |> should.equal(True)
  is_brier_calibrated(score) |> should.equal(True)
}

pub fn fractal_10_layers_forecast_test() {
  // L0 Constitutional
  let l0 = predict_l0_constitutional([0.98, 0.95, 0.92, 0.88], 10)
  l0.layer |> should.equal(LayerL0Constitutional)

  // L1 Atomic
  let l1 = predict_l1_atomic([1.0, 1.01, 0.99, 1.0], 10)
  l1.layer |> should.equal(LayerL1Atomic)

  // L2 Component - high resource triggers scale up
  let l2 = predict_l2_component([0.70, 0.75, 0.82, 0.89], 10)
  l2.layer |> should.equal(LayerL2Component)
  { l2.risk_score >. 0.0 } |> should.equal(True)

  // L3 Transaction
  let l3 = predict_l3_transaction([0.1, 0.15, 0.2], 10)
  l3.layer |> should.equal(LayerL3Transaction)

  // L4 System
  let l4 = predict_l4_system([0.01, 0.02, 0.02], 10)
  l4.layer |> should.equal(LayerL4System)

  // L5 Cognitive
  let l5 = predict_l5_cognitive([0.2, 0.3, 0.4], 10)
  l5.layer |> should.equal(LayerL5Cognitive)

  // L6 Ecosystem
  let l6 = predict_l6_ecosystem([0.99, 0.98, 0.97], 10)
  l6.layer |> should.equal(LayerL6Ecosystem)

  // L7 Federation
  let l7 = predict_l7_federation([0.1, 0.2, 0.15], 10)
  l7.layer |> should.equal(LayerL7Federation)

  // L8 Mutation
  let l8 = predict_l8_mutation([0.95, 0.94, 0.96], 10)
  l8.layer |> should.equal(LayerL8Mutation)

  // L9 Verification
  let l9 = predict_l9_verification([1.2, 1.5, 1.3], 10)
  l9.layer |> should.equal(LayerL9Verification)
}

pub fn predictive_ooda_evaluation_test() {
  let low_risk_forecast = predict_l2_component([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 10)
  let cycle = run_predictive_ooda_evaluation(
    "CYCLE-01",
    low_risk_forecast,
    "DeployTask",
    100.0,
    10.0,
  )
  cycle.action_decision |> should.equal("DeployTask")
  cycle.mitigation_scheduled |> should.equal(False)

  // High risk forecast triggers mitigation
  let high_risk_forecast = predict_l0_constitutional([0.65, 0.60, 0.50], 10)
  let cycle_high_risk = run_predictive_ooda_evaluation(
    "CYCLE-02",
    high_risk_forecast,
    "ApplyStateMutation",
    50.0,
    100.0,
  )
  cycle_high_risk.mitigation_scheduled |> should.equal(True)
}

pub fn sre_sdlc_predictive_sop_test() {
  // SRE capacity SOP
  let high_usage_forecast = predict_l2_component(
    [0.80, 0.82, 0.84, 0.86, 0.88, 0.90, 0.92, 0.94, 0.96, 0.98],
    30,
  )
  case evaluate_sre_capacity_sop(high_usage_forecast) {
    SreSopTriggered(sop, _, _) -> sop |> should.equal("SOP-SRE-01")
    SreSopBypassed(_, _) -> panic as "Expected SOP-SRE-01 to be triggered"
  }

  // SRE Lyapunov SOP
  let unstable = UnstableDiverging(0.12)
  case evaluate_sre_lyapunov_sop(unstable) {
    SreSopTriggered(sop, _, _) -> sop |> should.equal("SOP-SRE-02")
    SreSopBypassed(_, _) -> panic as "Expected SOP-SRE-02 to be triggered"
  }

  // SDLC Mutation SOP pass
  let good_mutation_forecast = predict_l8_mutation([0.94, 0.95, 0.96], 10)
  case evaluate_sdlc_mutation_sop(good_mutation_forecast) {
    SdlcPreflightPass(gate, _) -> gate |> should.equal("G-MUTATION-PREDICT")
    SdlcPreflightBlock(_, _) -> panic as "Expected mutation preflight to pass"
  }

  // SDLC Mutation SOP block
  let bad_mutation_forecast = predict_l8_mutation([0.80, 0.75, 0.70], 10)
  case evaluate_sdlc_mutation_sop(bad_mutation_forecast) {
    SdlcPreflightBlock(gate, _) -> gate |> should.equal("G-MUTATION-PREDICT")
    SdlcPreflightPass(_, _) -> panic as "Expected mutation preflight to block"
  }
}

pub fn agentic_preflight_certificate_test() {
  let safe_forecast = predict_l2_component([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 10)
  case verify_agentic_preflight("AGY", "OptimizeIndex", safe_forecast, 80.0, 10.0) {
    PreflightApproved(_, actor, action, seu, _) -> {
      actor |> should.equal("AGY")
      action |> should.equal("OptimizeIndex")
      { seu >. 0.0 } |> should.equal(True)
    }
    PreflightVetoed(_, _, _, reason, _) ->
      panic as string.append("Unexpected veto: ", reason)
  }

  // High risk forecast gets vetoed
  let danger_forecast = predict_l0_constitutional([0.75, 0.65, 0.55], 10)
  case verify_agentic_preflight("Codex", "PurgeStore", danger_forecast, 20.0, 100.0) {
    PreflightVetoed(_, actor, action, _, risk) -> {
      actor |> should.equal("Codex")
      action |> should.equal("PurgeStore")
      { risk >. 0.15 } |> should.equal(True)
    }
    PreflightApproved(_, _, _, _, _) ->
      panic as "High risk operation must be vetoed"
  }
}

pub fn planning_ooda_predictive_cycle_test() {
  let obs = [observe_from_health("unhealthy")]
  let forecast = predict_l2_component([0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5], 10)
  let cycle = run_predictive_cycle(obs, forecast)

  cycle.observations |> should.equal(obs)
  cycle.forecast.layer |> should.equal(LayerL2Component)
  { cycle.decision.score >. 0.0 } |> should.equal(True)
}

pub fn mcp_forecast_predict_tool_test() {
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"forecast_predict\",\"arguments\":{\"layer\":\"all\",\"horizon_seconds\":60}}}"
  let resp = mcp_server.handle_request_raw(req)
  case resp {
    Some(s) -> {
      string.contains(s, "UOS-FRACTAL-FORECAST") |> should.equal(True)
      string.contains(s, "L0_Constitutional") |> should.equal(True)
    }
    _ -> panic as "Expected MCP forecast_predict tool response"
  }
}

pub fn mcp_preflight_check_tool_test() {
  let req =
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"preflight_check\",\"arguments\":{\"actor\":\"AGY\",\"action\":\"MigrateTable\",\"benefit\":100.0,\"cost\":10.0}}}"
  let resp = mcp_server.handle_request_raw(req)
  case resp {
    Some(s) -> {
      string.contains(s, "approved") |> should.equal(True)
      string.contains(s, "CERT-PRED-") |> should.equal(True)
    }
    _ -> panic as "Expected MCP preflight_check tool response"
  }
}

pub fn wisp_forecast_router_endpoints_test() {
  let layers_resp = wisp_router.route("/api/v1/forecast/layers")
  string.contains(layers_resp, "UOS-FRACTAL-FORECAST") |> should.equal(True)
  string.contains(layers_resp, "L0_Constitutional") |> should.equal(True)
  string.contains(layers_resp, "L9_Verification") |> should.equal(True)

  let health_resp = wisp_router.route("/api/v1/forecast/health")
  string.contains(health_resp, "nominal") |> should.equal(True)
  string.contains(health_resp, "10/10 layers") |> should.equal(True)
}

pub fn forecast_cockpit_html_page_test() {
  let html = forecast_cockpit.view()
  string.contains(html, "Unified Fractal Forecasting &amp; Predictive POODAVR Cockpit") |> should.equal(True)
  string.contains(html, "POODAVR ACTIVE") |> should.equal(True)
  string.contains(html, "KALMAN FILTER 1D") |> should.equal(True)
  string.contains(html, "LYAPUNOV STABILITY") |> should.equal(True)
  string.contains(html, "SC-CHECKLIST-001") |> should.equal(True)
}

pub fn predictive_zenoh_stream_test() {
  // Topic mapping to fractal layers
  predictive_zenoh_stream.map_topic_to_layer("indrajaal/l0/const/quorum")
  |> should.equal(Some(LayerL0Constitutional))

  predictive_zenoh_stream.map_topic_to_layer("indrajaal/l1/atomic/nif")
  |> should.equal(Some(LayerL1Atomic))

  predictive_zenoh_stream.map_topic_to_layer("indrajaal/l2/health/pod")
  |> should.equal(Some(LayerL2Component))

  predictive_zenoh_stream.map_topic_to_layer("indrajaal/l4/system/mem")
  |> should.equal(Some(LayerL4System))

  // State ingestion
  let state = predictive_zenoh_stream.initial_state()
  let msg =
    predictive_zenoh_stream.IngestTelemetry(
      "indrajaal/l2/health/pod",
      "0.85",
    )
  let next_state = predictive_zenoh_stream.update_state(state, msg)

  next_state.total_messages |> should.equal(1)
  let f =
    predictive_zenoh_stream.compute_forecast_for_layer(
      next_state,
      LayerL2Component,
      60,
    )
  f.layer |> should.equal(LayerL2Component)
  { f.confidence >. 0.0 } |> should.equal(True)
}


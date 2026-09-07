// =============================================================================
// [C3I-SIL6-MSTS] UOS MODULAR MAX / MOJO INFERENCE DAEMON TEST SUITE
// =============================================================================
// Tests wire protocol serialization, response decoders, mathematical invariants,
// and Tier 1 cascade promotion for Modular MAX and Mojo.
// =============================================================================

import cepaf_gleam/services/max_inference_daemon as max
import cepaf_gleam/ui/lustre/inference_tier
import cepaf_gleam/ui/wisp/inference_api
import cepaf_gleam/ui/wisp/router
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

pub fn max_health_request_build_test() {
  let req = max.build_health_request("h-1")
  req |> string.contains("\"id\":\"h-1\"") |> should.be_true
  req |> string.contains("\"method\":\"health\"") |> should.be_true
}

pub fn max_health_decode_test() {
  let raw =
    "{\"id\":\"h-1\",\"status\":\"ok\",\"engine\":\"Modular MAX / Mojo\",\"version\":\"max/v26.5.0\",\"mojo_version\":\"mojo/v1.0.0\",\"device\":\"cpu/simd\",\"ready\":true,\"modalities\":[\"text\",\"image\",\"audio\",\"video\",\"embedding\"],\"latency_us\":12}"
  let res = max.decode_health_response(raw)
  res |> should.be_ok
  let assert Ok(h) = res
  h.status |> should.equal("ok")
  h.engine |> should.equal("Modular MAX / Mojo")
  h.version |> should.equal("max/v26.5.0")
  h.ready |> should.be_true
  list.contains(h.modalities, "audio") |> should.be_true
  list.contains(h.modalities, "embedding") |> should.be_true
}

pub fn max_metrics_request_build_and_decode_test() {
  let req = max.build_metrics_request("m-1")
  req |> string.contains("\"method\":\"metrics\"") |> should.be_true

  let raw =
    "{\"id\":\"m-1\",\"status\":\"ok\",\"total_requests\":45000,\"qps\":49559.8,\"avg_latency_us\":20,\"p99_latency_us\":85,\"uptime_s\":3600,\"cache_hit_rate\":0.942,\"latency_us\":15}"
  let res = max.decode_metrics_response(raw)
  res |> should.be_ok
  let assert Ok(m) = res
  m.total_requests |> should.equal(45000)
  m.avg_latency_us |> should.equal(20)
  m.cache_hit_rate |> should.equal(0.942)
}

pub fn max_infer_text_request_and_decode_test() {
  let req =
    max.build_infer_text_request("t-1", "analyze plan conflicts", "max-v26", 256)
  req |> string.contains("\"method\":\"infer_text\"") |> should.be_true
  req |> string.contains("analyze plan conflicts") |> should.be_true

  let raw =
    "{\"id\":\"t-1\",\"status\":\"ok\",\"model\":\"max-v26\",\"text\":\"Zero conflicts detected\",\"prompt_tokens\":3,\"completion_tokens\":12,\"latency_us\":18}"
  let res = max.decode_infer_text_response(raw)
  res |> should.be_ok
  let assert Ok(t) = res
  t.text |> should.equal("Zero conflicts detected")
  t.prompt_tokens |> should.equal(3)
}

pub fn max_infer_audio_raga_durga_test() {
  let req = max.build_infer_audio_request("a-1", "Durga", 4.0)
  req |> string.contains("\"method\":\"infer_audio\"") |> should.be_true
  req |> string.contains("\"raga\":\"Durga\"") |> should.be_true

  let raw =
    "{\"id\":\"a-1\",\"status\":\"ok\",\"raga\":\"Durga\",\"taal\":\"Teentaal\",\"duration_s\":4.0,\"harmony_index\":0.528,\"shannon_entropy\":2.541,\"swara_sequence\":[\"Sa\",\"Re\",\"Ma\",\"Pa\",\"Dha\",\"Sa'\"],\"pitch_contour_samples\":200,\"latency_us\":135}"
  let res = max.decode_infer_audio_response(raw)
  res |> should.be_ok
  let assert Ok(audio) = res
  audio.raga |> should.equal("Durga")
  audio.harmony_index |> should.equal(0.528)
  audio.shannon_entropy |> should.equal(2.541)
  max.is_harmony_pass(audio) |> should.be_true
  max.is_entropy_rich(audio) |> should.be_true
}

pub fn max_embed_request_and_cosine_similarity_test() {
  let req = max.build_embed_request("e-1", ["doc1", "doc2"], 4)
  req |> string.contains("\"method\":\"embed\"") |> should.be_true
  req |> string.contains("\"dimension\":4") |> should.be_true

  let v1 = [0.5, 0.5, 0.5, 0.5]
  let v2 = [0.5, 0.5, 0.5, 0.5]
  let sim = max.cosine_similarity(v1, v2)
  sim |> should.equal(1.0)

  let v_orth1 = [1.0, 0.0]
  let v_orth2 = [0.0, 1.0]
  let sim_orth = max.cosine_similarity(v_orth1, v_orth2)
  sim_orth |> should.equal(0.0)
}

pub fn max_tier1_promotion_invariants_test() {
  let model = inference_tier.init()
  let assert Ok(tier1) = list.first(model.tiers)
  tier1.tier |> should.equal(1)
  tier1.name |> should.equal("Modular MAX / Mojo")
  tier1.latency_ms |> should.equal(25)
  tier1.active |> should.be_true
}

pub fn max_ast_anomaly_request_and_decode_test() {
  let req =
    max.build_detect_ast_anomaly_request(
      "ast-1",
      "pub fn test() { Nil }",
      "gleam",
      True,
    )
  req |> string.contains("\"method\":\"detect_ast_anomaly\"") |> should.be_true
  req |> string.contains("\"strict_mode\":true") |> should.be_true

  let raw =
    "{\"id\":\"ast-1\",\"status\":\"ok\",\"language\":\"gleam\",\"code_length\":21,\"lines\":1,\"anomaly_score\":0.02,\"risk_level\":\"NOMINAL\",\"violations\":[],\"passed\":true,\"structural_similarity\":0.96,\"recommendations\":[\"Clean\"],\"centroid_dimension\":128,\"latency_us\":250}"
  let res = max.decode_detect_ast_anomaly_response(raw)
  res |> should.be_ok
  let assert Ok(report) = res
  report.passed |> should.be_true
  report.risk_level |> should.equal("NOMINAL")
  max.is_ast_safe(report) |> should.be_true
}

pub fn max_zk_transclusion_request_and_decode_test() {
  let req =
    max.build_match_zk_transclusion_request(
      "zk-1",
      "sa-plan jidoka tps",
      3,
      Some("L0"),
    )
  req |> string.contains("\"method\":\"match_zk_transclusion\"") |> should.be_true
  req |> string.contains("\"layer_filter\":\"L0\"") |> should.be_true

  let raw =
    "{\"id\":\"zk-1\",\"status\":\"ok\",\"query\":\"sa-plan\",\"total_corpus_notes\":68,\"match_count\":1,\"matches\":[{\"id\":\"ADR-066\",\"title\":\"Sa-Plan Fractal Jidoka\",\"layer\":\"L0\",\"score\":1.85,\"relevance\":\"exact\",\"transclusion\":\"[[zk:ADR-066]]\",\"tailscale_url\":\"http://nas-1.tail55d152.ts.net:4100/zk/ADR-066\",\"summary\":\"Sa-Plan authority.\"}],\"latency_us\":450}"
  let res = max.decode_match_zk_transclusion_response(raw)
  res |> should.be_ok
  let assert Ok(zk) = res
  zk.match_count |> should.equal(1)
  let top = max.top_zk_transclusion(zk)
  top |> should.equal(Some("[[zk:ADR-066]]"))
}

pub fn max_lyapunov_trend_request_and_decode_test() {
  let req =
    max.build_predict_lyapunov_trend_request(
      "lyap-1",
      [1.0, 1.02, 1.01],
      1.0,
      60.0,
      100.0,
    )
  req
  |> string.contains("\"method\":\"predict_lyapunov_trend\"")
  |> should.be_true
  req |> string.contains("\"critical_threshold\":100.0") |> should.be_true

  let raw =
    "{\"id\":\"lyap-1\",\"status\":\"ok\",\"samples_count\":3,\"dt_seconds\":1.0,\"horizon_seconds\":60.0,\"current_value\":1.01,\"critical_threshold\":100.0,\"lyapunov_exponent\":-0.35,\"stability_state\":\"strongly_stable\",\"time_to_cascade_s\":null,\"forecast_trajectory\":[1.01, 1.0],\"seu_preflight_passed\":true,\"preflight_status\":\"PASSED\",\"recommended_poodavr_phase\":\"ACT\",\"latency_us\":20}"
  let res = max.decode_predict_lyapunov_trend_response(raw)
  res |> should.be_ok
  let assert Ok(trend) = res
  trend.stability_state |> should.equal("strongly_stable")
  trend.seu_preflight_passed |> should.be_true
  max.is_seu_certified(trend) |> should.be_true
}

pub fn max_inference_api_evaluations_test() {
  // Test Model 1: Clean code vs violation
  let clean_report =
    inference_api.evaluate_ast_anomaly(
      "pub fn valid() -> Result(Int, Nil) { Ok(42) }",
      "gleam",
      True,
    )
  clean_report.passed |> should.be_true
  clean_report.risk_level |> should.equal("NOMINAL")

  let bad_report =
    inference_api.evaluate_ast_anomaly(
      "fn bypass() { bypass_sa_plan(); }",
      "rust",
      True,
    )
  bad_report.passed |> should.be_false
  bad_report.risk_level |> should.equal("BLOCKED")
  list.contains(bad_report.violations, "JIDOKA_BYPASS_ATTEMPT")
  |> should.be_true

  // Test Model 2: ZK Transclusion
  let zk_res =
    inference_api.evaluate_zk_transclusion(
      "ADR-066 sa-plan fractal jidoka tps",
      3,
    )
  zk_res.match_count |> should.equal(3)
  let assert [top, ..] = zk_res.matches
  top.id |> should.equal("ADR-066")
  top.relevance |> should.equal("exact")
  string.starts_with(top.transclusion, "[[zk:") |> should.be_true
  string.contains(top.tailscale_url, "tail55d152.ts.net") |> should.be_true

  // Test Model 3: Lyapunov Trend
  let stable_trend =
    inference_api.evaluate_lyapunov_trend(
      [10.0, 10.02, 10.01, 10.03],
      1.0,
      60.0,
      50.0,
    )
  stable_trend.stability_state |> should.equal("strongly_stable")
  stable_trend.seu_preflight_passed |> should.be_true

  let divergent_trend =
    inference_api.evaluate_lyapunov_trend(
      [5.0, 12.0, 25.0, 60.0],
      1.0,
      60.0,
      100.0,
    )
  divergent_trend.stability_state |> should.equal("unstable_divergent")
  divergent_trend.seu_preflight_passed |> should.be_false
}

pub fn max_inference_router_endpoints_test() {
  let status_body = router.route("/api/v1/inference/status")
  status_body |> string.contains("Modular MAX / Mojo") |> should.be_true
  status_body |> string.contains("ast_anomaly") |> should.be_true
  status_body |> string.contains("zk_transclusion") |> should.be_true
  status_body |> string.contains("lyapunov_trend") |> should.be_true

  let modalities_body = router.route("/api/v1/inference/modalities")
  modalities_body |> string.contains("Modular MAX Mojo SIMD") |> should.be_true
  modalities_body |> string.contains("ast_anomaly") |> should.be_true

  let ast_body = router.route("/api/v1/inference/ast-anomaly")
  ast_body |> string.contains("NOMINAL") |> should.be_true

  let zk_body = router.route("/api/v1/inference/zk-transclude")
  zk_body |> string.contains("[[zk:") |> should.be_true
  zk_body |> string.contains("tail55d152.ts.net") |> should.be_true

  let lyap_body = router.route("/api/v1/inference/lyapunov-trend")
  lyap_body |> string.contains("strongly_stable") |> should.be_true
}

pub fn max_stpa_fmea_request_and_decode_test() {
  let req =
    max.build_infer_stpa_fmea_request(
      "stpa-1",
      "sa_plan_execution_bypass",
      "actuator",
      "execution_context",
      5,
      "ready",
      5,
    )
  req |> string.contains("\"method\":\"infer_stpa_fmea_hazard\"") |> should.be_true
  req |> string.contains("sa_plan_execution_bypass") |> should.be_true

  let raw =
    "{\"id\":\"stpa-1\",\"status\":\"ok\",\"action\":\"sa_plan_execution_bypass\",\"component\":\"actuator\",\"uca_count\":1,\"ucas\":[{\"uca_type\":\"UCA-2\",\"name\":\"providing_causes_hazard\",\"hazard\":\"Direct bypass\"}],\"severity\":10,\"occurrence\":3,\"detection\":2,\"rpn\":60,\"rpn_band\":4,\"fmea_factor\":10,\"composite_score\":1500,\"gate_decision\":\"ANDON_STOP_BLOCKED\",\"sil_rating\":\"SIL-6\",\"latency_us\":18}"
  let res = max.decode_infer_stpa_fmea_response(raw)
  res |> should.be_ok
  let assert Ok(rep) = res
  rep.gate_decision |> should.equal("ANDON_STOP_BLOCKED")
  rep.rpn |> should.equal(60)
  rep.sil_rating |> should.equal("SIL-6")
  max.is_stpa_safe(rep) |> should.be_false

  let json = max.stpa_fmea_report_to_json(rep)
  json |> string.contains("ANDON_STOP_BLOCKED") |> should.be_true
}

pub fn max_rete_conflict_request_and_decode_test() {
  let rule_json = json.object([#("id", json.string("rule_a"))])
  let req =
    max.build_eval_rete_rule_conflict_request("rete-1", [rule_json], ["fact1"])
  req |> string.contains("\"method\":\"eval_rete_rule_conflict\"") |> should.be_true

  let raw =
    "{\"id\":\"rete-1\",\"status\":\"ok\",\"rules_evaluated\":2,\"winner\":{\"id\":\"rule_a\",\"name\":\"Safety Rule\",\"layer\":\"L0\",\"score\":150.0,\"layer_rank\":10,\"salience\":100.0,\"specificity\":5,\"matched_conditions\":3,\"action\":\"halt\"},\"suppressed_count\":1,\"suppressed\":[\"rule_b\"],\"firing_strategy\":\"lexicographic_constitutional_dominance\",\"constitutional_layer\":\"L0\",\"latency_us\":16}"
  let res = max.decode_eval_rete_conflict_response(raw)
  res |> should.be_ok
  let assert Ok(rep) = res
  let assert Some(w) = rep.winner
  w.id |> should.equal("rule_a")
  rep.constitutional_layer |> should.equal("L0")
  max.is_rete_l0_winner(rep) |> should.be_true

  let json = max.rete_conflict_report_to_json(rep)
  json |> string.contains("rule_a") |> should.be_true
}

pub fn max_ruliad_branch_request_and_decode_test() {
  let req =
    max.build_evaluate_ruliad_branch_request(
      "rul-1",
      "integration/main",
      "feature/max-expansion",
      ["review_diff"],
      ["AGY"],
    )
  req |> string.contains("\"method\":\"evaluate_ruliad_branch\"") |> should.be_true

  let raw =
    "{\"id\":\"rul-1\",\"status\":\"ok\",\"source_branch\":\"integration/main\",\"target_branch\":\"feature/max-expansion\",\"branchial_distance\":0.15,\"branchial_similarity\":0.98,\"branchial_entropy\":1.585,\"conflict_probability\":0.10,\"convergence_status\":\"NOMINAL_MERGE_READY\",\"participating_agents\":[\"AGY\",\"Claude\",\"Codex\"],\"optimal_collapse_path\":[\"review_diff\",\"run_eunit\",\"fast_forward_merge\"],\"latency_us\":685}"
  let res = max.decode_evaluate_ruliad_branch_response(raw)
  res |> should.be_ok
  let assert Ok(rep) = res
  rep.convergence_status |> should.equal("NOMINAL_MERGE_READY")
  rep.branchial_distance |> should.equal(0.15)
  max.is_ruliad_mergeable(rep) |> should.be_true

  let json = max.ruliad_branch_report_to_json(rep)
  json |> string.contains("NOMINAL_MERGE_READY") |> should.be_true
}

pub fn max_shruti_harmonics_request_and_decode_test() {
  let req =
    max.build_synthesize_shruti_harmonics_request(
      "shr-1",
      [1.0, 1.25, 1.5],
      "Durga",
      136.1,
    )
  req |> string.contains("\"method\":\"synthesize_biomorphic_harmonics\"") |> should.be_true

  let raw =
    "{\"id\":\"shr-1\",\"status\":\"ok\",\"raga\":\"Durga\",\"fundamental_hz\":136.1,\"swara_count\":1,\"harmonics\":[{\"swara_index\":1,\"shruti_ratio\":1.0,\"frequency_hz\":136.1,\"amplitude\":0.85}],\"spectral_entropy\":2.585,\"consonance_index\":0.88,\"acoustic_health\":\"HARMONIC_RESONANCE_OPTIMAL\",\"jawari_shimmer_active\":true,\"latency_us\":55}"
  let res = max.decode_synthesize_shruti_harmonics_response(raw)
  res |> should.be_ok
  let assert Ok(rep) = res
  rep.raga |> should.equal("Durga")
  rep.acoustic_health |> should.equal("HARMONIC_RESONANCE_OPTIMAL")
  rep.jawari_shimmer_active |> should.be_true
  max.is_acoustic_healthy(rep) |> should.be_true

  let json = max.shruti_harmonic_report_to_json(rep)
  json |> string.contains("Durga") |> should.be_true
}

pub fn max_models_4_to_7_api_and_router_test() {
  // STPA-FMEA evaluation
  let safe_rep =
    inference_api.evaluate_stpa_fmea("read_status", "sensor", "nominal", 1, "ready", 1)
  safe_rep.gate_decision |> should.equal("PERMITTED")
  max.is_stpa_safe(safe_rep) |> should.be_true

  let danger_rep =
    inference_api.evaluate_stpa_fmea("bypass_sa_plan", "core", "test", 5, "blocked", 5)
  danger_rep.gate_decision |> should.equal("ANDON_STOP_BLOCKED")
  max.is_stpa_safe(danger_rep) |> should.be_false

  // Rete conflict evaluation
  let r1 = max.ReteRuleScore("r1", "rule1", "L0", 150.0, 10, 100.0, 5, 2, "halt")
  let r2 = max.ReteRuleScore("r2", "rule2", "L5", 50.0, 5, 30.0, 2, 1, "log")
  let rete_rep = inference_api.evaluate_rete_conflict([r1, r2])
  let assert Some(w) = rete_rep.winner
  w.id |> should.equal("r1")
  rete_rep.constitutional_layer |> should.equal("L0")

  // Ruliad branch evaluation
  let rul_rep =
    inference_api.evaluate_ruliad_branch("b1", "b2", ["minor_edit"], ["AGY"])
  rul_rep.convergence_status |> should.equal("NOMINAL_MERGE_READY")
  max.is_ruliad_mergeable(rul_rep) |> should.be_true

  // Shruti harmonics evaluation
  let shr_rep =
    inference_api.evaluate_shruti_harmonics([0.1, 0.2], "Durga", 136.1)
  shr_rep.acoustic_health |> should.equal("HARMONIC_RESONANCE_OPTIMAL")
  shr_rep.jawari_shimmer_active |> should.be_true
  max.is_acoustic_healthy(shr_rep) |> should.be_true

  // Router endpoints
  let stpa_route = router.route("/api/v1/inference/stpa-fmea")
  stpa_route |> string.contains("gate_decision") |> should.be_true

  let rul_route = router.route("/api/v1/inference/ruliad-branch")
  rul_route |> string.contains("convergence_status") |> should.be_true

  let shr_route = router.route("/api/v1/inference/shruti-harmonics")
  shr_route |> string.contains("acoustic_health") |> should.be_true
}



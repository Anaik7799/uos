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

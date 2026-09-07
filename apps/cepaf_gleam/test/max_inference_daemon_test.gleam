// =============================================================================
// [C3I-SIL6-MSTS] UOS MODULAR MAX / MOJO INFERENCE DAEMON TEST SUITE
// =============================================================================
// Tests wire protocol serialization, response decoders, mathematical invariants,
// and Tier 1 cascade promotion for Modular MAX and Mojo.
// =============================================================================

import cepaf_gleam/services/max_inference_daemon as max
import cepaf_gleam/ui/lustre/inference_tier
import gleam/list
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

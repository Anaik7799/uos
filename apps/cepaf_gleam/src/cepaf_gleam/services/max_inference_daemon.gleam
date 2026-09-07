//// =============================================================================
//// [C3I-SIL6-MSTS] UOS MODULAR MAX / MOJO INFERENCE SERVICE PROTOCOL & CLIENT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/services/max_inference_daemon</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Modular MAX / Mojo Isolated Inference Tier</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-INF-001, SC-GLM-UI-001, SC-BIO-HARMONY-001, SC-ZERO-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Pure Gleam protocol encoder, decoder, and algebraic client for the
//// Modular MAX and Mojo isolated AI/ML inference tier.
////
//// Transports typed JSON-RPC requests across 4-byte big-endian length-delimited
//// stdio pipes supervised by Gleam/OTP.
//// =============================================================================

import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/list
import gleam/result

// -----------------------------------------------------------------------------
// Public Data Types
// -----------------------------------------------------------------------------

pub type MaxHealth {
  MaxHealth(
    id: String,
    status: String,
    engine: String,
    version: String,
    mojo_version: String,
    device: String,
    ready: Bool,
    modalities: List(String),
  )
}

pub type MaxMetrics {
  MaxMetrics(
    id: String,
    status: String,
    total_requests: Int,
    qps: Float,
    avg_latency_us: Int,
    p99_latency_us: Int,
    uptime_s: Int,
    cache_hit_rate: Float,
  )
}

pub type MaxTextResult {
  MaxTextResult(
    id: String,
    status: String,
    model: String,
    text: String,
    prompt_tokens: Int,
    completion_tokens: Int,
    latency_us: Int,
  )
}

pub type MaxAudioResult {
  MaxAudioResult(
    id: String,
    status: String,
    raga: String,
    taal: String,
    duration_s: Float,
    harmony_index: Float,
    shannon_entropy: Float,
    swara_sequence: List(String),
    pitch_samples: Int,
    latency_us: Int,
  )
}

pub type MaxEmbedResult {
  MaxEmbedResult(
    id: String,
    status: String,
    dimension: Int,
    count: Int,
    embeddings: List(List(Float)),
    latency_us: Int,
  )
}

// -----------------------------------------------------------------------------
// Request Encoders (Conforming to contracts/inference/max_inference_contract.json)
// -----------------------------------------------------------------------------

pub fn build_health_request(id: String) -> String {
  json.object([#("id", json.string(id)), #("method", json.string("health"))])
  |> json.to_string
}

pub fn build_metrics_request(id: String) -> String {
  json.object([#("id", json.string(id)), #("method", json.string("metrics"))])
  |> json.to_string
}

pub fn build_modalities_request(id: String) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("modalities")),
  ])
  |> json.to_string
}

pub fn build_infer_text_request(
  id: String,
  prompt: String,
  model: String,
  max_tokens: Int,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("infer_text")),
    #(
      "params",
      json.object([
        #("prompt", json.string(prompt)),
        #("model", json.string(model)),
        #("max_tokens", json.int(max_tokens)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn build_infer_audio_request(
  id: String,
  raga: String,
  duration_s: Float,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("infer_audio")),
    #(
      "params",
      json.object([
        #("raga", json.string(raga)),
        #("duration_s", json.float(duration_s)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn build_embed_request(
  id: String,
  texts: List(String),
  dimension: Int,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("embed")),
    #(
      "params",
      json.object([
        #("texts", json.array(texts, json.string)),
        #("dimension", json.int(dimension)),
        #("normalize", json.bool(True)),
      ]),
    ),
  ])
  |> json.to_string
}

// -----------------------------------------------------------------------------
// Response Decoders
// -----------------------------------------------------------------------------

pub fn decode_health_response(raw_json: String) -> Result(MaxHealth, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use engine <- decode.field("engine", decode.string)
    use version <- decode.field("version", decode.string)
    use mojo_version <- decode.field("mojo_version", decode.string)
    use device <- decode.field("device", decode.string)
    use ready <- decode.field("ready", decode.bool)
    use modalities <- decode.field("modalities", decode.list(decode.string))
    decode.success(MaxHealth(
      id: id,
      status: status,
      engine: engine,
      version: version,
      mojo_version: mojo_version,
      device: device,
      ready: ready,
      modalities: modalities,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) { "failed_to_decode_health_response" })
}

pub fn decode_metrics_response(raw_json: String) -> Result(MaxMetrics, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use total_requests <- decode.field("total_requests", decode.int)
    use qps <- decode.field("qps", decode.float)
    use avg_latency_us <- decode.field("avg_latency_us", decode.int)
    use p99_latency_us <- decode.field("p99_latency_us", decode.int)
    use uptime_s <- decode.field("uptime_s", decode.int)
    use cache_hit_rate <- decode.field("cache_hit_rate", decode.float)
    decode.success(MaxMetrics(
      id: id,
      status: status,
      total_requests: total_requests,
      qps: qps,
      avg_latency_us: avg_latency_us,
      p99_latency_us: p99_latency_us,
      uptime_s: uptime_s,
      cache_hit_rate: cache_hit_rate,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) { "failed_to_decode_metrics_response" })
}

pub fn decode_infer_text_response(
  raw_json: String,
) -> Result(MaxTextResult, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use model <- decode.field("model", decode.string)
    use text <- decode.field("text", decode.string)
    use prompt_tokens <- decode.field("prompt_tokens", decode.int)
    use completion_tokens <- decode.field("completion_tokens", decode.int)
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(MaxTextResult(
      id: id,
      status: status,
      model: model,
      text: text,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) { "failed_to_decode_infer_text_response" })
}

pub fn decode_infer_audio_response(
  raw_json: String,
) -> Result(MaxAudioResult, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use raga <- decode.field("raga", decode.string)
    use taal <- decode.field("taal", decode.string)
    use duration_s <- decode.field("duration_s", decode.float)
    use harmony_index <- decode.field("harmony_index", decode.float)
    use shannon_entropy <- decode.field("shannon_entropy", decode.float)
    use swara_sequence <- decode.field(
      "swara_sequence",
      decode.list(decode.string),
    )
    use pitch_samples <- decode.field("pitch_contour_samples", decode.int)
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(MaxAudioResult(
      id: id,
      status: status,
      raga: raga,
      taal: taal,
      duration_s: duration_s,
      harmony_index: harmony_index,
      shannon_entropy: shannon_entropy,
      swara_sequence: swara_sequence,
      pitch_samples: pitch_samples,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) { "failed_to_decode_infer_audio_response" })
}

pub fn decode_embed_response(raw_json: String) -> Result(MaxEmbedResult, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use dimension <- decode.field("dimension", decode.int)
    use count <- decode.field("count", decode.int)
    use embeddings <- decode.field(
      "embeddings",
      decode.list(decode.list(decode.float)),
    )
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(MaxEmbedResult(
      id: id,
      status: status,
      dimension: dimension,
      count: count,
      embeddings: embeddings,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) { "failed_to_decode_embed_response" })
}

// -----------------------------------------------------------------------------
// Mathematical Validation Functions
// -----------------------------------------------------------------------------

pub fn vector_norm(v: List(Float)) -> Float {
  let sum_sq = list.fold(v, 0.0, fn(acc, x) { acc +. { x *. x } })
  case float.square_root(sum_sq) {
    Ok(n) -> n
    Error(_) -> 0.0
  }
}

pub fn cosine_similarity(a: List(Float), b: List(Float)) -> Float {
  let norm_a = vector_norm(a)
  let norm_b = vector_norm(b)
  case norm_a == 0.0 || norm_b == 0.0 {
    True -> 0.0
    False -> {
      let dot =
        list.zip(a, b)
        |> list.fold(0.0, fn(acc, pair) { acc +. { pair.0 *. pair.1 } })
      dot /. { norm_a *. norm_b }
    }
  }
}

pub fn is_harmony_pass(result: MaxAudioResult) -> Bool {
  result.harmony_index >=. 0.45
}

pub fn is_entropy_rich(result: MaxAudioResult) -> Bool {
  result.shannon_entropy >=. 2.50
}

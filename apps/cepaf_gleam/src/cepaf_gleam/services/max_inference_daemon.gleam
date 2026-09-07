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
import gleam/option.{type Option, None, Some}
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

pub type AstAnomalyReport {
  AstAnomalyReport(
    id: String,
    status: String,
    language: String,
    code_length: Int,
    lines: Int,
    anomaly_score: Float,
    risk_level: String,
    violations: List(String),
    passed: Bool,
    structural_similarity: Float,
    recommendations: List(String),
    centroid_dimension: Int,
    latency_us: Int,
  )
}

pub type ZkMatch {
  ZkMatch(
    id: String,
    title: String,
    layer: String,
    score: Float,
    relevance: String,
    transclusion: String,
    tailscale_url: String,
    summary: String,
  )
}

pub type ZkTransclusionResult {
  ZkTransclusionResult(
    id: String,
    status: String,
    query: String,
    total_corpus_notes: Int,
    match_count: Int,
    matches: List(ZkMatch),
    latency_us: Int,
  )
}

pub type LyapunovTrendResult {
  LyapunovTrendResult(
    id: String,
    status: String,
    samples_count: Int,
    dt_seconds: Float,
    horizon_seconds: Float,
    current_value: Float,
    critical_threshold: Float,
    lyapunov_exponent: Float,
    stability_state: String,
    time_to_cascade_s: Option(Float),
    forecast_trajectory: List(Float),
    seu_preflight_passed: Bool,
    preflight_status: String,
    recommended_poodavr_phase: String,
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

pub fn build_detect_ast_anomaly_request(
  id: String,
  code: String,
  language: String,
  strict_mode: Bool,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("detect_ast_anomaly")),
    #(
      "params",
      json.object([
        #("code", json.string(code)),
        #("language", json.string(language)),
        #("strict_mode", json.bool(strict_mode)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn build_match_zk_transclusion_request(
  id: String,
  query: String,
  limit: Int,
  layer_filter: Option(String),
) -> String {
  let params_fields = [
    #("query", json.string(query)),
    #("limit", json.int(limit)),
  ]
  let params = case layer_filter {
    Some(l) -> list.append(params_fields, [#("layer_filter", json.string(l))])
    None -> params_fields
  }
  json.object([
    #("id", json.string(id)),
    #("method", json.string("match_zk_transclusion")),
    #("params", json.object(params)),
  ])
  |> json.to_string
}

pub fn build_predict_lyapunov_trend_request(
  id: String,
  telemetry: List(Float),
  dt: Float,
  horizon_s: Float,
  critical_threshold: Float,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("predict_lyapunov_trend")),
    #(
      "params",
      json.object([
        #("telemetry", json.array(telemetry, json.float)),
        #("dt", json.float(dt)),
        #("horizon_s", json.float(horizon_s)),
        #("critical_threshold", json.float(critical_threshold)),
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

pub fn decode_detect_ast_anomaly_response(
  raw_json: String,
) -> Result(AstAnomalyReport, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use language <- decode.field("language", decode.string)
    use code_length <- decode.field("code_length", decode.int)
    use lines <- decode.field("lines", decode.int)
    use anomaly_score <- decode.field("anomaly_score", decode.float)
    use risk_level <- decode.field("risk_level", decode.string)
    use violations <- decode.field("violations", decode.list(decode.string))
    use passed <- decode.field("passed", decode.bool)
    use structural_similarity <- decode.field(
      "structural_similarity",
      decode.float,
    )
    use recommendations <- decode.field(
      "recommendations",
      decode.list(decode.string),
    )
    use centroid_dimension <- decode.field("centroid_dimension", decode.int)
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(AstAnomalyReport(
      id: id,
      status: status,
      language: language,
      code_length: code_length,
      lines: lines,
      anomaly_score: anomaly_score,
      risk_level: risk_level,
      violations: violations,
      passed: passed,
      structural_similarity: structural_similarity,
      recommendations: recommendations,
      centroid_dimension: centroid_dimension,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) { "failed_to_decode_detect_ast_anomaly_response" })
}

pub fn decode_match_zk_transclusion_response(
  raw_json: String,
) -> Result(ZkTransclusionResult, String) {
  let match_decoder = {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    use layer <- decode.field("layer", decode.string)
    use score <- decode.field("score", decode.float)
    use relevance <- decode.field("relevance", decode.string)
    use transclusion <- decode.field("transclusion", decode.string)
    use tailscale_url <- decode.field("tailscale_url", decode.string)
    use summary <- decode.field("summary", decode.string)
    decode.success(ZkMatch(
      id: id,
      title: title,
      layer: layer,
      score: score,
      relevance: relevance,
      transclusion: transclusion,
      tailscale_url: tailscale_url,
      summary: summary,
    ))
  }

  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use query <- decode.field("query", decode.string)
    use total_corpus_notes <- decode.field("total_corpus_notes", decode.int)
    use match_count <- decode.field("match_count", decode.int)
    use matches <- decode.field("matches", decode.list(match_decoder))
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(ZkTransclusionResult(
      id: id,
      status: status,
      query: query,
      total_corpus_notes: total_corpus_notes,
      match_count: match_count,
      matches: matches,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) {
    "failed_to_decode_match_zk_transclusion_response"
  })
}

pub fn decode_predict_lyapunov_trend_response(
  raw_json: String,
) -> Result(LyapunovTrendResult, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use samples_count <- decode.field("samples_count", decode.int)
    use dt_seconds <- decode.field("dt_seconds", decode.float)
    use horizon_seconds <- decode.field("horizon_seconds", decode.float)
    use current_value <- decode.field("current_value", decode.float)
    use critical_threshold <- decode.field("critical_threshold", decode.float)
    use lyapunov_exponent <- decode.field("lyapunov_exponent", decode.float)
    use stability_state <- decode.field("stability_state", decode.string)
    use time_to_cascade_s <- decode.field(
      "time_to_cascade_s",
      decode.optional(decode.float),
    )
    use forecast_trajectory <- decode.field(
      "forecast_trajectory",
      decode.list(decode.float),
    )
    use seu_preflight_passed <- decode.field(
      "seu_preflight_passed",
      decode.bool,
    )
    use preflight_status <- decode.field("preflight_status", decode.string)
    use recommended_poodavr_phase <- decode.field(
      "recommended_poodavr_phase",
      decode.string,
    )
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(LyapunovTrendResult(
      id: id,
      status: status,
      samples_count: samples_count,
      dt_seconds: dt_seconds,
      horizon_seconds: horizon_seconds,
      current_value: current_value,
      critical_threshold: critical_threshold,
      lyapunov_exponent: lyapunov_exponent,
      stability_state: stability_state,
      time_to_cascade_s: time_to_cascade_s,
      forecast_trajectory: forecast_trajectory,
      seu_preflight_passed: seu_preflight_passed,
      preflight_status: preflight_status,
      recommended_poodavr_phase: recommended_poodavr_phase,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) {
    "failed_to_decode_predict_lyapunov_trend_response"
  })
}

// -----------------------------------------------------------------------------
// JSON Serializers for Wisp Endpoints
// -----------------------------------------------------------------------------

pub fn ast_report_to_json(report: AstAnomalyReport) -> String {
  json.object([
    #("id", json.string(report.id)),
    #("status", json.string(report.status)),
    #("language", json.string(report.language)),
    #("code_length", json.int(report.code_length)),
    #("lines", json.int(report.lines)),
    #("anomaly_score", json.float(report.anomaly_score)),
    #("risk_level", json.string(report.risk_level)),
    #("violations", json.array(report.violations, json.string)),
    #("passed", json.bool(report.passed)),
    #("structural_similarity", json.float(report.structural_similarity)),
    #("recommendations", json.array(report.recommendations, json.string)),
    #("centroid_dimension", json.int(report.centroid_dimension)),
    #("latency_us", json.int(report.latency_us)),
  ])
  |> json.to_string
}

pub fn zk_result_to_json(result: ZkTransclusionResult) -> String {
  json.object([
    #("id", json.string(result.id)),
    #("status", json.string(result.status)),
    #("query", json.string(result.query)),
    #("total_corpus_notes", json.int(result.total_corpus_notes)),
    #("match_count", json.int(result.match_count)),
    #(
      "matches",
      json.array(result.matches, fn(m) {
        json.object([
          #("id", json.string(m.id)),
          #("title", json.string(m.title)),
          #("layer", json.string(m.layer)),
          #("score", json.float(m.score)),
          #("relevance", json.string(m.relevance)),
          #("transclusion", json.string(m.transclusion)),
          #("tailscale_url", json.string(m.tailscale_url)),
          #("summary", json.string(m.summary)),
        ])
      }),
    ),
    #("latency_us", json.int(result.latency_us)),
  ])
  |> json.to_string
}

pub fn lyapunov_result_to_json(result: LyapunovTrendResult) -> String {
  let cascade_json = case result.time_to_cascade_s {
    Some(s) -> json.float(s)
    None -> json.null()
  }
  json.object([
    #("id", json.string(result.id)),
    #("status", json.string(result.status)),
    #("samples_count", json.int(result.samples_count)),
    #("dt_seconds", json.float(result.dt_seconds)),
    #("horizon_seconds", json.float(result.horizon_seconds)),
    #("current_value", json.float(result.current_value)),
    #("critical_threshold", json.float(result.critical_threshold)),
    #("lyapunov_exponent", json.float(result.lyapunov_exponent)),
    #("stability_state", json.string(result.stability_state)),
    #("time_to_cascade_s", cascade_json),
    #(
      "forecast_trajectory",
      json.array(result.forecast_trajectory, json.float),
    ),
    #("seu_preflight_passed", json.bool(result.seu_preflight_passed)),
    #("preflight_status", json.string(result.preflight_status)),
    #(
      "recommended_poodavr_phase",
      json.string(result.recommended_poodavr_phase),
    ),
    #("latency_us", json.int(result.latency_us)),
  ])
  |> json.to_string
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

pub fn is_ast_safe(report: AstAnomalyReport) -> Bool {
  report.passed && report.risk_level == "NOMINAL"
}

pub fn is_seu_certified(trend: LyapunovTrendResult) -> Bool {
  trend.seu_preflight_passed
}

pub fn top_zk_transclusion(result: ZkTransclusionResult) -> Option(String) {
  case result.matches {
    [first, ..] -> Some(first.transclusion)
    [] -> None
  }
}

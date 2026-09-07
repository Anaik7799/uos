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

pub type StpaUca {
  StpaUca(uca_type: String, name: String, hazard: String)
}

pub type StpaFmeaReport {
  StpaFmeaReport(
    id: String,
    status: String,
    action: String,
    component: String,
    uca_count: Int,
    ucas: List(StpaUca),
    severity: Int,
    occurrence: Int,
    detection: Int,
    rpn: Int,
    rpn_band: Int,
    fmea_factor: Int,
    composite_score: Int,
    gate_decision: String,
    sil_rating: String,
    latency_us: Int,
  )
}

pub type ReteRuleScore {
  ReteRuleScore(
    id: String,
    name: String,
    layer: String,
    score: Float,
    layer_rank: Int,
    salience: Float,
    specificity: Int,
    matched_conditions: Int,
    action: String,
  )
}

pub type ReteConflictReport {
  ReteConflictReport(
    id: String,
    status: String,
    rules_evaluated: Int,
    winner: Option(ReteRuleScore),
    suppressed_count: Int,
    suppressed: List(String),
    firing_strategy: String,
    constitutional_layer: String,
    latency_us: Int,
  )
}

pub type RuliadBranchReport {
  RuliadBranchReport(
    id: String,
    status: String,
    source_branch: String,
    target_branch: String,
    branchial_distance: Float,
    branchial_similarity: Float,
    branchial_entropy: Float,
    conflict_probability: Float,
    convergence_status: String,
    participating_agents: List(String),
    optimal_collapse_path: List(String),
    latency_us: Int,
  )
}

pub type ShrutiHarmonic {
  ShrutiHarmonic(
    swara_index: Int,
    shruti_ratio: Float,
    frequency_hz: Float,
    amplitude: Float,
  )
}

pub type ShrutiHarmonicReport {
  ShrutiHarmonicReport(
    id: String,
    status: String,
    raga: String,
    fundamental_hz: Float,
    swara_count: Int,
    harmonics: List(ShrutiHarmonic),
    spectral_entropy: Float,
    consonance_index: Float,
    acoustic_health: String,
    jawari_shimmer_active: Bool,
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

pub fn build_infer_stpa_fmea_request(
  id: String,
  action: String,
  component: String,
  context: String,
  criticality: Int,
  dependency_readiness: String,
  impact: Int,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("infer_stpa_fmea_hazard")),
    #(
      "params",
      json.object([
        #("action", json.string(action)),
        #("component", json.string(component)),
        #("context", json.string(context)),
        #("criticality", json.int(criticality)),
        #("dependency_readiness", json.string(dependency_readiness)),
        #("impact", json.int(impact)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn build_eval_rete_rule_conflict_request(
  id: String,
  active_rules: List(json.Json),
  facts: List(String),
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("eval_rete_rule_conflict")),
    #(
      "params",
      json.object([
        #("active_rules", json.array(active_rules, fn(x) { x })),
        #("facts", json.array(facts, json.string)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn build_evaluate_ruliad_branch_request(
  id: String,
  source_branch: String,
  target_branch: String,
  candidate_changes: List(String),
  agents: List(String),
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("evaluate_ruliad_branch")),
    #(
      "params",
      json.object([
        #("source_branch", json.string(source_branch)),
        #("target_branch", json.string(target_branch)),
        #("candidate_changes", json.array(candidate_changes, json.string)),
        #("agents", json.array(agents, json.string)),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn build_synthesize_shruti_harmonics_request(
  id: String,
  telemetry_vector: List(Float),
  raga: String,
  fundamental_hz: Float,
) -> String {
  json.object([
    #("id", json.string(id)),
    #("method", json.string("synthesize_biomorphic_harmonics")),
    #(
      "params",
      json.object([
        #("telemetry_vector", json.array(telemetry_vector, json.float)),
        #("raga", json.string(raga)),
        #("fundamental_hz", json.float(fundamental_hz)),
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

pub fn decode_infer_stpa_fmea_response(
  raw_json: String,
) -> Result(StpaFmeaReport, String) {
  let uca_decoder = {
    use uca_type <- decode.field("type", decode.string)
    use name <- decode.field("name", decode.string)
    use hazard <- decode.field("hazard", decode.string)
    decode.success(StpaUca(uca_type: uca_type, name: name, hazard: hazard))
  }

  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use action <- decode.field("action", decode.string)
    use component <- decode.field("component", decode.string)
    use uca_count <- decode.field("uca_count", decode.int)
    use ucas <- decode.field("ucas", decode.list(uca_decoder))
    use severity <- decode.field("severity", decode.int)
    use occurrence <- decode.field("occurrence", decode.int)
    use detection <- decode.field("detection", decode.int)
    use rpn <- decode.field("rpn", decode.int)
    use rpn_band <- decode.field("rpn_band", decode.int)
    use fmea_factor <- decode.field("fmea_factor", decode.int)
    use composite_score <- decode.field("composite_score", decode.int)
    use gate_decision <- decode.field("gate_decision", decode.string)
    use sil_rating <- decode.field("sil_rating", decode.string)
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(StpaFmeaReport(
      id: id,
      status: status,
      action: action,
      component: component,
      uca_count: uca_count,
      ucas: ucas,
      severity: severity,
      occurrence: occurrence,
      detection: detection,
      rpn: rpn,
      rpn_band: rpn_band,
      fmea_factor: fmea_factor,
      composite_score: composite_score,
      gate_decision: gate_decision,
      sil_rating: sil_rating,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) {
    "failed_to_decode_infer_stpa_fmea_response"
  })
}

pub fn decode_eval_rete_conflict_response(
  raw_json: String,
) -> Result(ReteConflictReport, String) {
  let rule_decoder = {
    use id <- decode.field("id", decode.string)
    use name <- decode.field("name", decode.string)
    use layer <- decode.field("layer", decode.string)
    use score <- decode.field("score", decode.float)
    use layer_rank <- decode.field("layer_rank", decode.int)
    use salience <- decode.field("salience", decode.float)
    use specificity <- decode.field("specificity", decode.int)
    use matched_conditions <- decode.field("matched_conditions", decode.int)
    use action <- decode.field("action", decode.string)
    decode.success(ReteRuleScore(
      id: id,
      name: name,
      layer: layer,
      score: score,
      layer_rank: layer_rank,
      salience: salience,
      specificity: specificity,
      matched_conditions: matched_conditions,
      action: action,
    ))
  }

  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use rules_evaluated <- decode.field("rules_evaluated", decode.int)
    use winner <- decode.field("winner", decode.optional(rule_decoder))
    use suppressed_count <- decode.field("suppressed_count", decode.int)
    use suppressed <- decode.field("suppressed", decode.list(decode.string))
    use firing_strategy <- decode.field("firing_strategy", decode.string)
    use constitutional_layer <- decode.field(
      "constitutional_layer",
      decode.string,
    )
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(ReteConflictReport(
      id: id,
      status: status,
      rules_evaluated: rules_evaluated,
      winner: winner,
      suppressed_count: suppressed_count,
      suppressed: suppressed,
      firing_strategy: firing_strategy,
      constitutional_layer: constitutional_layer,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) {
    "failed_to_decode_eval_rete_conflict_response"
  })
}

pub fn decode_evaluate_ruliad_branch_response(
  raw_json: String,
) -> Result(RuliadBranchReport, String) {
  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use source_branch <- decode.field("source_branch", decode.string)
    use target_branch <- decode.field("target_branch", decode.string)
    use branchial_distance <- decode.field("branchial_distance", decode.float)
    use branchial_similarity <- decode.field(
      "branchial_similarity",
      decode.float,
    )
    use branchial_entropy <- decode.field("branchial_entropy", decode.float)
    use conflict_probability <- decode.field(
      "conflict_probability",
      decode.float,
    )
    use convergence_status <- decode.field("convergence_status", decode.string)
    use participating_agents <- decode.field(
      "participating_agents",
      decode.list(decode.string),
    )
    use optimal_collapse_path <- decode.field(
      "optimal_collapse_path",
      decode.list(decode.string),
    )
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(RuliadBranchReport(
      id: id,
      status: status,
      source_branch: source_branch,
      target_branch: target_branch,
      branchial_distance: branchial_distance,
      branchial_similarity: branchial_similarity,
      branchial_entropy: branchial_entropy,
      conflict_probability: conflict_probability,
      convergence_status: convergence_status,
      participating_agents: participating_agents,
      optimal_collapse_path: optimal_collapse_path,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) {
    "failed_to_decode_evaluate_ruliad_branch_response"
  })
}

pub fn decode_synthesize_shruti_harmonics_response(
  raw_json: String,
) -> Result(ShrutiHarmonicReport, String) {
  let harmonic_decoder = {
    use swara_index <- decode.field("swara_index", decode.int)
    use shruti_ratio <- decode.field("shruti_ratio", decode.float)
    use frequency_hz <- decode.field("frequency_hz", decode.float)
    use amplitude <- decode.field("amplitude", decode.float)
    decode.success(ShrutiHarmonic(
      swara_index: swara_index,
      shruti_ratio: shruti_ratio,
      frequency_hz: frequency_hz,
      amplitude: amplitude,
    ))
  }

  let decoder = {
    use id <- decode.field("id", decode.string)
    use status <- decode.field("status", decode.string)
    use raga <- decode.field("raga", decode.string)
    use fundamental_hz <- decode.field("fundamental_hz", decode.float)
    use swara_count <- decode.field("swara_count", decode.int)
    use harmonics <- decode.field("harmonics", decode.list(harmonic_decoder))
    use spectral_entropy <- decode.field("spectral_entropy", decode.float)
    use consonance_index <- decode.field("consonance_index", decode.float)
    use acoustic_health <- decode.field("acoustic_health", decode.string)
    use jawari_shimmer_active <- decode.field(
      "jawari_shimmer_active",
      decode.bool,
    )
    use latency_us <- decode.field("latency_us", decode.int)
    decode.success(ShrutiHarmonicReport(
      id: id,
      status: status,
      raga: raga,
      fundamental_hz: fundamental_hz,
      swara_count: swara_count,
      harmonics: harmonics,
      spectral_entropy: spectral_entropy,
      consonance_index: consonance_index,
      acoustic_health: acoustic_health,
      jawari_shimmer_active: jawari_shimmer_active,
      latency_us: latency_us,
    ))
  }
  json.parse(raw_json, decoder)
  |> result.map_error(fn(_) {
    "failed_to_decode_synthesize_shruti_harmonics_response"
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

pub fn stpa_fmea_report_to_json(report: StpaFmeaReport) -> String {
  json.object([
    #("id", json.string(report.id)),
    #("status", json.string(report.status)),
    #("action", json.string(report.action)),
    #("component", json.string(report.component)),
    #("uca_count", json.int(report.uca_count)),
    #(
      "ucas",
      json.array(report.ucas, fn(u) {
        json.object([
          #("type", json.string(u.uca_type)),
          #("name", json.string(u.name)),
          #("hazard", json.string(u.hazard)),
        ])
      }),
    ),
    #("severity", json.int(report.severity)),
    #("occurrence", json.int(report.occurrence)),
    #("detection", json.int(report.detection)),
    #("rpn", json.int(report.rpn)),
    #("rpn_band", json.int(report.rpn_band)),
    #("fmea_factor", json.int(report.fmea_factor)),
    #("composite_score", json.int(report.composite_score)),
    #("gate_decision", json.string(report.gate_decision)),
    #("sil_rating", json.string(report.sil_rating)),
    #("latency_us", json.int(report.latency_us)),
  ])
  |> json.to_string
}

pub fn rete_conflict_report_to_json(report: ReteConflictReport) -> String {
  let winner_json = case report.winner {
    Some(w) ->
      json.object([
        #("id", json.string(w.id)),
        #("name", json.string(w.name)),
        #("layer", json.string(w.layer)),
        #("score", json.float(w.score)),
        #("layer_rank", json.int(w.layer_rank)),
        #("salience", json.float(w.salience)),
        #("specificity", json.int(w.specificity)),
        #("matched_conditions", json.int(w.matched_conditions)),
        #("action", json.string(w.action)),
      ])
    None -> json.null()
  }

  json.object([
    #("id", json.string(report.id)),
    #("status", json.string(report.status)),
    #("rules_evaluated", json.int(report.rules_evaluated)),
    #("winner", winner_json),
    #("suppressed_count", json.int(report.suppressed_count)),
    #("suppressed", json.array(report.suppressed, json.string)),
    #("firing_strategy", json.string(report.firing_strategy)),
    #("constitutional_layer", json.string(report.constitutional_layer)),
    #("latency_us", json.int(report.latency_us)),
  ])
  |> json.to_string
}

pub fn ruliad_branch_report_to_json(report: RuliadBranchReport) -> String {
  json.object([
    #("id", json.string(report.id)),
    #("status", json.string(report.status)),
    #("source_branch", json.string(report.source_branch)),
    #("target_branch", json.string(report.target_branch)),
    #("branchial_distance", json.float(report.branchial_distance)),
    #("branchial_similarity", json.float(report.branchial_similarity)),
    #("branchial_entropy", json.float(report.branchial_entropy)),
    #("conflict_probability", json.float(report.conflict_probability)),
    #("convergence_status", json.string(report.convergence_status)),
    #(
      "participating_agents",
      json.array(report.participating_agents, json.string),
    ),
    #(
      "optimal_collapse_path",
      json.array(report.optimal_collapse_path, json.string),
    ),
    #("latency_us", json.int(report.latency_us)),
  ])
  |> json.to_string
}

pub fn shruti_harmonic_report_to_json(report: ShrutiHarmonicReport) -> String {
  json.object([
    #("id", json.string(report.id)),
    #("status", json.string(report.status)),
    #("raga", json.string(report.raga)),
    #("fundamental_hz", json.float(report.fundamental_hz)),
    #("swara_count", json.int(report.swara_count)),
    #(
      "harmonics",
      json.array(report.harmonics, fn(h) {
        json.object([
          #("swara_index", json.int(h.swara_index)),
          #("shruti_ratio", json.float(h.shruti_ratio)),
          #("frequency_hz", json.float(h.frequency_hz)),
          #("amplitude", json.float(h.amplitude)),
        ])
      }),
    ),
    #("spectral_entropy", json.float(report.spectral_entropy)),
    #("consonance_index", json.float(report.consonance_index)),
    #("acoustic_health", json.string(report.acoustic_health)),
    #("jawari_shimmer_active", json.bool(report.jawari_shimmer_active)),
    #("latency_us", json.int(report.latency_us)),
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

pub fn is_stpa_safe(report: StpaFmeaReport) -> Bool {
  report.gate_decision == "PERMITTED" && report.severity < 9
}

pub fn is_rete_l0_winner(report: ReteConflictReport) -> Bool {
  case report.winner {
    Some(w) -> w.layer == "L0"
    None -> False
  }
}

pub fn is_ruliad_mergeable(report: RuliadBranchReport) -> Bool {
  report.conflict_probability <. 0.50
}

pub fn is_acoustic_healthy(report: ShrutiHarmonicReport) -> Bool {
  report.acoustic_health == "HARMONIC_RESONANCE_OPTIMAL"
}

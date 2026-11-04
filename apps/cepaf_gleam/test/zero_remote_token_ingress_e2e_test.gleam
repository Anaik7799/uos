import cepaf_gleam/ai/remote_circuit_breaker.{
  RateLimitConfig, check_admission, new as new_cb, record_success,
}
import cepaf_gleam/observability/c3i_token_telemetry.{
  C3IInferenceSpan, OriginPrefilterSimd, is_local, span_to_json,
}
import cepaf_gleam/ui/wisp/intelligence_api.{resolve_local_first_json}
import gleam/json
import gleam/string
import gleeunit/should

pub fn full_e2e_zero_remote_token_ingress_pipeline_test() {
  // 1. Ingress Request arrives
  let request_id = "req-e2e-zero-remote-001"
  let prompt =
    "Explain UOS formal verification for local AI/ML inference cascade and SIMD prefiltering"

  // 2. Cascade Resolution via intelligence_api
  let res_json =
    resolve_local_first_json(
      request_id,
      request_id,
      // logical_id
      "tenant-e2e",
      // tenant
      "L5_COGNITIVE",
      // layer_code
      prompt,
      // prompt
      True,
      // allow_paid
    )
  let res_str = json.to_string(res_json)

  // Verify Stage 0 prefilter executed and result resolved locally
  string.contains(res_str, "\"engine\":\"local_first_cascade\"")
  |> should.equal(True)
  string.contains(res_str, "\"stage0_probe\":\"mojo_prefilter_executed\"")
  |> should.equal(True)
  string.contains(res_str, "\"kind\":\"local\"")
  |> should.equal(True)
  string.contains(res_str, "\"remote_authorized\":false")
  |> should.equal(True)

  // 3. Rate-Limiting Circuit Breaker Admission Verification
  // Under zero remote tokens, remote cost is 0
  let cb =
    new_cb(RateLimitConfig(
      max_usd_milli_per_hour: 2000,
      max_requests_per_window: 100,
      window_seconds: 300,
    ))

  // Local request has 0 remote cost
  let assert Ok(cb_admitted) = check_admission(cb, 0)
  let _cb_final = record_success(cb_admitted, 0)

  // 4. C3I OTel Telemetry Emission
  let span =
    C3IInferenceSpan(
      trace_id: "0123456789abcdef0123456789abcdef",
      span_id: "abcdef0123456789",
      parent_span_id: "0000000000000000",
      request_id: request_id,
      tenant_id: "tenant-uos-e2e",
      origin: OriginPrefilterSimd,
      prompt_tokens: 18,
      completion_tokens: 64,
      remote_tokens_billed: 0,
      latency_us: 1850,
    )

  let span_json = span_to_json(span) |> json.to_string()

  // Invariants verified
  string.contains(span_json, "\"is_local\":true")
  |> should.equal(True)
  string.contains(span_json, "\"token_origin\":\"local_prefilter_simd\"")
  |> should.equal(True)
  string.contains(span_json, "\"remote_tokens_billed\":0")
  |> should.equal(True)
  is_local(span.origin)
  |> should.equal(True)
}

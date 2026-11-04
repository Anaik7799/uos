import cepaf_gleam/observability/c3i_token_telemetry.{
  C3IInferenceSpan, OriginMaxWorkerCtypes, OriginPrefilterSimd,
  OriginRemoteGrant, is_local, span_to_json,
}
import gleam/json
import gleam/string
import gleeunit/should

pub fn c3i_telemetry_origin_and_zero_remote_tokens_test() {
  let local_span =
    C3IInferenceSpan(
      trace_id: "0123456789abcdef0123456789abcdef",
      span_id: "abcdef0123456789",
      parent_span_id: "0000000000000000",
      request_id: "req-otel-01",
      tenant_id: "tenant-otel",
      origin: OriginPrefilterSimd,
      prompt_tokens: 150,
      completion_tokens: 50,
      remote_tokens_billed: 999,
      // Attempted bug: local span claiming remote tokens
      latency_us: 120,
    )

  let rendered_local = span_to_json(local_span) |> json.to_string()

  // Invariant: remote_tokens_billed is strictly overridden to 0 for local origin
  string.contains(rendered_local, "\"remote_tokens_billed\":0")
  |> should.equal(True)

  string.contains(rendered_local, "\"token_origin\":\"local_prefilter_simd\"")
  |> should.equal(True)

  string.contains(rendered_local, "\"is_local\":true")
  |> should.equal(True)

  // Remote span retains billed tokens
  let remote_span =
    C3IInferenceSpan(
      trace_id: "0123456789abcdef0123456789abcdef",
      span_id: "abcdef0123456789",
      parent_span_id: "0000000000000000",
      request_id: "req-otel-02",
      tenant_id: "tenant-otel",
      origin: OriginRemoteGrant("anthropic", 4),
      prompt_tokens: 150,
      completion_tokens: 50,
      remote_tokens_billed: 200,
      latency_us: 150_000,
    )

  let rendered_remote = span_to_json(remote_span) |> json.to_string()
  string.contains(rendered_remote, "\"remote_tokens_billed\":200")
  |> should.equal(True)

  string.contains(
    rendered_remote,
    "\"token_origin\":\"remote_grant:anthropic:tier4\"",
  )
  |> should.equal(True)

  string.contains(rendered_remote, "\"is_local\":false")
  |> should.equal(True)
}

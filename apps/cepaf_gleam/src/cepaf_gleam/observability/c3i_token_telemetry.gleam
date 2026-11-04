import gleam/json.{type Json}

pub type TokenOrigin {
  OriginPrefilterSimd
  OriginMaxWorkerCtypes
  OriginLocalCache
  OriginRemoteGrant(provider: String, tier: Int)
}

pub fn origin_to_string(origin: TokenOrigin) -> String {
  case origin {
    OriginPrefilterSimd -> "local_prefilter_simd"
    OriginMaxWorkerCtypes -> "local_max_worker_ctypes"
    OriginLocalCache -> "local_cache"
    OriginRemoteGrant(provider, tier) ->
      "remote_grant:" <> provider <> ":tier" <> gleam_int_to_string(tier)
  }
}

pub fn is_local(origin: TokenOrigin) -> Bool {
  case origin {
    OriginPrefilterSimd -> True
    OriginMaxWorkerCtypes -> True
    OriginLocalCache -> True
    OriginRemoteGrant(_, _) -> False
  }
}

pub type C3IInferenceSpan {
  C3IInferenceSpan(
    trace_id: String,
    span_id: String,
    parent_span_id: String,
    request_id: String,
    tenant_id: String,
    origin: TokenOrigin,
    prompt_tokens: Int,
    completion_tokens: Int,
    remote_tokens_billed: Int,
    latency_us: Int,
  )
}

pub fn span_to_json(span: C3IInferenceSpan) -> Json {
  let is_loc = is_local(span.origin)
  // Hard invariant: if is_loc, remote_tokens_billed must be 0
  let remote_tokens = case is_loc {
    True -> 0
    False -> span.remote_tokens_billed
  }

  json.object([
    #("trace_id", json.string(span.trace_id)),
    #("span_id", json.string(span.span_id)),
    #("parent_span_id", json.string(span.parent_span_id)),
    #("request_id", json.string(span.request_id)),
    #("tenant_id", json.string(span.tenant_id)),
    #("token_origin", json.string(origin_to_string(span.origin))),
    #("is_local", json.bool(is_loc)),
    #("prompt_tokens", json.int(span.prompt_tokens)),
    #("completion_tokens", json.int(span.completion_tokens)),
    #("remote_tokens_billed", json.int(remote_tokens)),
    #("latency_us", json.int(span.latency_us)),
  ])
}

fn gleam_int_to_string(i: Int) -> String {
  case i {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    _ -> "x"
  }
}

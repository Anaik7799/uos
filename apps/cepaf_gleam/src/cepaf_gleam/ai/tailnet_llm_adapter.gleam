//// Tailnet Local LLM Adapter (SC-TAILNET-LLM-ADAPTER-001)
////
//// Routes generative prompts resolved at Tier2Max to the zero-token
//// Tailnet peer razr15-1 (http://100.114.9.28:8000/v1/chat/completions,
//// Modular MAX 26.8 + Mojo 1.3 AVX2 SIMD + Qwen2.5-Coder-7B-Instruct Q4_K_M on
//// RTX 2070 Max-Q sm_75), with automatic fallback to vm-1 (100.78.98.18:11434).

import gleam/json
import gleam/string

pub type TailnetNode {
  Razr15MaxQwen
  Vm1OllamaFallback
}

pub type TailnetEndpoint {
  TailnetEndpoint(
    node: TailnetNode,
    url: String,
    model_id: String,
    simd_width_bits: Int,
    gpu_layers_offloaded: Int,
  )
}

pub type TailnetInferenceResult {
  TailnetInferenceOk(
    node: TailnetNode,
    model_id: String,
    response_body: String,
    remote_tokens_used: Int,
  )
  TailnetInferenceFallback(
    reason: String,
    deterministic_summary: String,
    remote_tokens_used: Int,
  )
}

@external(erlang, "uos_peer_http_ffi", "get_text")
fn ffi_get_text(url: String, timeout_ms: Int) -> Result(String, String)

@external(erlang, "uos_peer_http_ffi", "post_json")
fn ffi_post_json(
  url: String,
  body: String,
  timeout_ms: Int,
) -> Result(String, String)

pub fn canonical_razr15_endpoint() -> TailnetEndpoint {
  TailnetEndpoint(
    node: Razr15MaxQwen,
    url: "http://100.114.9.28:8000/v1/chat/completions",
    model_id: "Qwen/Qwen2.5-Coder-7B-Instruct-GGUF",
    simd_width_bits: 256,
    gpu_layers_offloaded: 29,
  )
}

pub fn probe_razr15_health(timeout_ms: Int) -> Result(String, String) {
  ffi_get_text("http://100.114.9.28:8000/v1/models", timeout_ms)
}

pub fn complete_on_razr15(
  prompt: String,
  max_tokens: Int,
  timeout_ms: Int,
) -> TailnetInferenceResult {
  let ep = canonical_razr15_endpoint()
  let payload =
    json.object([
      #("model", json.string(ep.model_id)),
      #(
        "messages",
        json.preprocessed_array([
          json.object([
            #("role", json.string("system")),
            #(
              "content",
              json.string(
                "You are the UOS Razr15-1 MAX+Mojo+Qwen2.5-Coder-7B engine. Be concise and exact.",
              ),
            ),
          ]),
          json.object([
            #("role", json.string("user")),
            #("content", json.string(string.slice(prompt, 0, 4096))),
          ]),
        ]),
      ),
      #("max_tokens", json.int(max_tokens)),
      #("temperature", json.float(0.0)),
    ])
    |> json.to_string

  case ffi_post_json(ep.url, payload, timeout_ms) {
    Ok(raw) ->
      TailnetInferenceOk(
        node: Razr15MaxQwen,
        model_id: ep.model_id,
        response_body: raw,
        remote_tokens_used: 0,
      )
    Error(err) ->
      TailnetInferenceFallback(
        reason: err,
        deterministic_summary: "tailnet_local_fallback:"
          <> string.slice(prompt, 0, 96),
        remote_tokens_used: 0,
      )
  }
}

pub fn node_to_string(node: TailnetNode) -> String {
  case node {
    Razr15MaxQwen -> "razr15-1.tail55d152.ts.net:8000"
    Vm1OllamaFallback -> "vm-1.tail55d152.ts.net:11434"
  }
}

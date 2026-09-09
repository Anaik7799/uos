//// Bounded free-only advisory adapter; results never authorize effects.
//// Reuses the shared router's live prices, allowlist and prompt hygiene.
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/result
import gleam/string
import uos_swarm/openrouter_worker as worker

@external(erlang, "uos_openrouter_ffi", "api_key")
fn api_key() -> Result(String, Nil)

@external(erlang, "uos_openrouter_ffi", "https_get")
fn https_get(url: String, timeout: Int) -> Result(#(Int, String), String)

@external(erlang, "uos_openrouter_ffi", "https_post_json")
fn https_post(url: String, key: String, body: String, timeout: Int) -> Result(#(Int, String), String)

@external(erlang, "uos_swarm_ffi", "system_time_us")
fn now_us() -> Int

pub fn decode_request(input: String) -> Result(worker.Request, String) {
  let decoder = {
    use model <- decode.field("model", decode.string)
    use prompt <- decode.field("prompt", decode.string)
    use tokens <- decode.field("max_tokens", decode.int)
    decode.success(worker.Request(
      model: model,
      system: "Provide bounded advisory analysis for a software holon. Return observations and testable proposals. Advice grants no task, execution, deployment or admission authority.",
      user: prompt,
      max_tokens: tokens,
    ))
  }
  use request <- result.try(json.parse(input, decoder) |> result.replace_error("invalid_advisory_request"))
  case string.length(request.user) > 4096 || request.max_tokens < 1 || request.max_tokens > 512 {
    True -> Error("advisory_input_or_token_bound")
    False -> Ok(request)
  }
}

pub fn free_policy() -> worker.Policy {
  worker.Policy(max_tokens: 512, budget_usd: 0.0, timeout_ms: 12_000, free_only: True)
}

pub fn openrouter_with(input: String, io: worker.Io) -> Result(String, String) {
  use request <- result.try(decode_request(input))
  use outcome <- result.try(worker.run(free_policy(), io, request)
    |> result.map_error(worker.refusal_label))
  // A provider reporting a charge violates this service contract even when
  // live prices were zero. Preserve the failed request; never silently retry.
  case outcome.cost_usd == 0.0 && outcome.reply.reported_cost_usd == option.Some(0.0)
    && outcome.reply.completion_tokens <= request.max_tokens {
    True -> Ok(worker.outcome_json(outcome) |> json.to_string)
    False -> Error("provider_violated_free_or_token_ceiling")
  }
}

pub fn openrouter(input: String) -> Result(String, String) {
  openrouter_with(input, worker.Io(
    credential: fn() { option.from_result(api_key()) },
    fetch_prices: fn(timeout) { https_get(worker.models_url, timeout) },
    post: fn(key, body, timeout) { https_post(worker.chat_url, key, body, timeout) },
    now_ms: fn() { now_us() / 1000 },
  ))
}

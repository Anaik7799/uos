//// A persisted request reservation is required before any model transport.
//// Model text remains data; no tool dispatcher exists in this module.
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_store as store
import gleam/int
import gleam/option
import gleam/result
import uos_swarm/openrouter_worker as model

pub type Execution {
  Execution(reply: String)
}

type TimeUnit { Millisecond }

@external(erlang, "erlang", "monotonic_time")
fn monotonic_ms(unit: TimeUnit) -> Int

@external(erlang, "uos_openrouter_ffi", "api_key")
fn api_key() -> Result(String, Nil)

@external(erlang, "uos_openrouter_ffi", "https_get")
fn https_get(url: String, timeout_ms: Int) -> Result(#(Int, String), String)

@external(erlang, "uos_openrouter_ffi", "https_post_json")
fn https_post_json(url: String, key: String, body: String, timeout_ms: Int)
  -> Result(#(Int, String), String)

pub fn live_io() -> model.Io {
  model.Io(
    credential: fn() { option.from_result(api_key()) },
    fetch_prices: fn(t) { https_get(model.models_url, t) },
    post: fn(key, body, t) { https_post_json(model.chat_url, key, body, t) },
    now_ms: fn() { monotonic_ms(Millisecond) },
  )
}

fn remaining(
  io: model.Io, authorize: fn() -> Result(Int, String),
  started: Int, deadline: Int,
) -> Result(Int, String) {
  use lease <- result.try(authorize() |> result.replace_error("conversation_authority_refused"))
  let now = io.now_ms()
  case now >= started && now < deadline && lease > 0 {
    True -> Ok(int.min(deadline - now, lease))
    False -> Error("conversation_deadline_or_clock_refused")
  }
}

fn transport(
  io: model.Io, authorize: fn() -> Result(Int, String),
  started: Int, deadline: Int, requested_ms: Int,
  call: fn(Int) -> Result(#(Int, String), String),
) -> Result(#(Int, String), String) {
  use available <- result.try(remaining(io, authorize, started, deadline))
  use _ <- result.try(case requested_ms > 0 {
    True -> Ok(Nil)
    False -> Error("conversation_invalid_timeout")
  })
  let response = call(int.min(available, requested_ms))
  use _ <- result.try(remaining(io, authorize, started, deadline))
  response |> result.replace_error("conversation_transport_failed")
}

pub fn run(
  reservation: store.ConversationReservation,
  io: model.Io,
  authorize: fn() -> Result(Int, String),
  budget_ms: Int,
) -> Result(Execution, String) {
  use _ <- result.try(case budget_ms >= 100 && budget_ms <= 15_000 {
    True -> Ok(Nil)
    False -> Error("conversation_invalid_budget")
  })
  let context = store.conversation_context(reservation)
  let prompt = store.conversation_prompt(reservation)
  use request <- result.try(conv.prepare_request(context, prompt))
  let started = io.now_ms()
  let deadline = started + budget_ms
  use _ <- result.try(remaining(io, authorize, started, deadline))
  let fenced_io = model.Io(
    credential: io.credential,
    fetch_prices: fn(t) {
      transport(io, authorize, started, deadline, t, io.fetch_prices)
    },
    post: fn(key, body, t) {
      transport(io, authorize, started, deadline, t,
        fn(bound) { io.post(key, body, bound) })
    },
    now_ms: io.now_ms,
  )
  // Provider body and raw refusals are never returned to Telegram.
  use outcome <- result.try(
    model.run(model.Policy(512, 0.0, budget_ms, True), fenced_io, request)
    |> result.replace_error("conversation_model_request_failed"),
  )
  use _ <- result.try(remaining(io, authorize, started, deadline))
  use _ <- result.try(conv.append(
    conv.Context(context.scope, []), conv.Turn(1, prompt, outcome.reply.content),
  ) |> result.replace_error("conversation_invalid_reply"))
  Ok(Execution(outcome.reply.content))
}

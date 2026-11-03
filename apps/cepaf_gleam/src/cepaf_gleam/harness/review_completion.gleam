//// One completion/advice contract shared by existing harness adapters. This is
//// not an agent/tool loop. Claude/AGY stay unavailable here until integrated.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/value
import cepaf_gleam/mcp/json_guard
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/openrouter_worker as egress

pub type Backend {
  PiOpenRouterArgon
  Claude
  Agy
  Codex
}

pub type Cleanup {
  Reaped
  CleanupUnconfirmed
}

pub type Exchange {
  Exchange(body: String, cleanup: Cleanup)
}

pub type Io {
  Io(
    authorize: fn() -> Result(Nil, String),
    reserve: fn(String) -> Result(String, String),
    invoke: fn(String) -> Result(Exchange, String),
  )
}

pub opaque type Prepared {
  Prepared(
    call_id: String,
    body: String,
    tokens: Int,
    input_bytes: Int,
    worst_case_nanodollars: Int,
  )
}

pub const model = "google/gemini-4-argon"

pub const request_limit_nanodollars = 20_000_000

pub const daily_limit_nanodollars = 10_000_000_000

// The existing canonical ledger reserves $0.25 conservatively for EACH call.
// This is a distinct liability, never the $0.02 request price ceiling or spend.
pub const retained_reservation_nanodollars = 250_000_000

pub const system_prompt = "Give concise advisory findings and unverified items. No tools or actions."

fn require(b: Bool, e: String) -> Result(Nil, String) {
  case b {
    True -> Ok(Nil)
    False -> Error(e)
  }
}

pub fn prepare(
  backend: Backend,
  call_id: String,
  prompt: String,
  tokens: Int,
) -> Result(Prepared, String) {
  use _ <- result.try(require(
    backend == PiOpenRouterArgon,
    "review_backend_unavailable",
  ))
  use _ <- result.try(require(
    string.byte_size(call_id) > 0
      && string.byte_size(call_id) <= 128
      && list.all(string.to_graphemes(call_id), fn(c) {
      string.byte_size(c) == 1
      && string.contains(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-",
        c,
      )
    }),
    "review_call_id",
  ))
  use _ <- result.try(require(
    tokens > 0
      && tokens <= 512
      && string.byte_size(prompt) > 0
      && string.byte_size(prompt) <= 16_384
      && !string.contains(prompt, "\u{0}"),
    "review_input_bound",
  ))
  let input_bytes = string.byte_size(system_prompt) + string.byte_size(prompt)
  // Existing bounded prose-only egress hygiene; not a complete DLP proof.
  use _ <- result.try(
    egress.sanitize_check(prompt)
    |> result.map_error(egress.refusal_label),
  )
  // Explicit served-tokenizer/template assumption inherited from daily_budget:
  // billed input tokens <= actual UTF8 bytes + 2048; text only, no tool context.
  let worst = { input_bytes + 2048 } * 4000 + tokens * 20_000
  use _ <- result.try(require(
    worst < request_limit_nanodollars,
    "review_price_bound",
  ))
  let body =
    json.object([
      #("model", json.string(model)),
      #(
        "messages",
        json.array(
          [
            json.object([
              #("role", json.string("system")),
              #("content", json.string(system_prompt)),
            ]),
            json.object([
              #("role", json.string("user")),
              #("content", json.string(prompt)),
            ]),
          ],
          fn(x) { x },
        ),
      ),
      #("max_tokens", json.int(tokens)),
      #("temperature", json.int(0)),
      #("stream", json.bool(True)),
      #("stream_options", json.object([#("include_usage", json.bool(True))])),
      #("reasoning", json.object([#("enabled", json.bool(False))])),
      #(
        "provider",
        json.object([
          #("only", json.array(["google-ai-studio"], json.string)),
          #("allow_fallbacks", json.bool(False)),
          #("data_collection", json.string("deny")),
          #("zdr", json.bool(True)),
          #("require_parameters", json.bool(True)),
          #(
            "max_price",
            json.object([
              #("prompt", json.int(4)),
              #("completion", json.int(20)),
              #("request", json.int(0)),
            ]),
          ),
        ]),
      ),
    ])
    |> json.to_string
  Ok(Prepared(call_id, body, tokens, input_bytes, worst))
}

pub fn body(p: Prepared) -> String {
  p.body
}

pub fn worst_case(p: Prepared) -> Int {
  p.worst_case_nanodollars
}

pub fn ledger_request(p: Prepared) -> String {
  json.object([
    #("call_id", json.string(p.call_id)),
    #("model", json.string(model)),
    #("max_tokens", json.int(p.tokens)),
    #("input_bytes", json.int(p.input_bytes)),
    #("body_bytes", json.int(string.byte_size(p.body))),
  ])
  |> json.to_string
}

fn field(v: value.Value, k: String) -> Result(value.Value, String) {
  value.get(v, k)
}

fn text(v: value.Value, k: String) -> Result(String, String) {
  use x <- result.try(field(v, k))
  case x {
    value.Text(s) -> Ok(s)
    _ -> Error("review_receipt_field:" <> k)
  }
}

pub fn execute(p: Prepared, io: Io) -> Result(String, String) {
  use _ <- result.try(io.authorize())
  use reservation <- result.try(io.reserve(ledger_request(p)))
  use receipt <- result.try(
    json_guard.native_inspect(reservation, 8)
    |> result.map_error(fn(_) { "review_reservation_unknown" }),
  )
  use _ <- result.try(require(
    field(receipt, "status") == Ok(value.Text("reserved"))
      && field(receipt, "dispatch_authorized") == Ok(value.Boolean(True))
      && field(receipt, "call_id") == Ok(value.Text(p.call_id))
      && field(receipt, "reservation_nanodollars")
      == Ok(value.Integer(retained_reservation_nanodollars))
      && field(receipt, "daily_limit_nanodollars")
      == Ok(value.Integer(daily_limit_nanodollars)),
    "review_reservation_not_fresh",
  ))
  use _ <- result.try(io.authorize())
  use exchange <- result.try(io.invoke(p.body))
  use _ <- result.try(require(
    exchange.cleanup == Reaped,
    "review_cleanup_unknown_no_retry",
  ))
  use raw <- result.try(
    json_guard.native_inspect(exchange.body, 12)
    |> result.map_error(fn(_) { "review_response_unknown_no_retry" }),
  )
  use _ <- result.try(case raw {
    value.Object(fields) ->
      require(
        list.length(fields) == 15
          && list.all(fields, fn(p) {
          list.contains(
            [
              "schema", "status", "model", "provider", "text", "generation_id",
              "input_tokens", "output_tokens", "reported_model", "stop_reason",
              "completion_posts", "catalog_gets", "tools_executed",
              "body_sha256", "actual_provider_cost",
            ],
            p.0,
          )
        }),
        "review_closed_response",
      )
    _ -> Error("review_closed_response")
  })
  use _ <- result.try(require(
    field(raw, "schema") == Ok(value.Text("uos.pi-single-completion.v1"))
      && field(raw, "model") == Ok(value.Text(model))
      && field(raw, "provider") == Ok(value.Text("openrouter"))
      && field(raw, "reported_model") == Ok(value.Text(model))
      && field(raw, "body_sha256") == Ok(value.Text(files.digest(p.body)))
      && field(raw, "actual_provider_cost") == Ok(value.Null)
      && field(raw, "completion_posts") == Ok(value.Integer(1))
      && field(raw, "tools_executed") == Ok(value.Integer(0)),
    "review_response_identity_unknown",
  ))
  use status <- result.try(text(raw, "status"))
  use _ <- result.try(require(
    status == "ADVICE_COST_UNKNOWN",
    "review_completion_unavailable_no_retry",
  ))
  use advice <- result.try(text(raw, "text"))
  use _ <- result.try(require(
    string.byte_size(advice) > 0 && string.byte_size(advice) <= 16_384,
    "review_output_bound",
  ))
  use _ <- result.try(
    case field(raw, "input_tokens"), field(raw, "output_tokens") {
      Ok(value.Integer(input)), Ok(value.Integer(output)) ->
        require(
          input >= 0
            && input <= p.input_bytes + 2048
            && output >= 0
            && output <= p.tokens,
          "review_usage_bound",
        )
      _, _ -> Error("review_usage_unknown")
    },
  )
  let result =
    json.object([
      #("status", json.string("ADVICE_OBSERVED_COST_UNKNOWN")),
      #("backend", json.string("pi_openrouter_argon")),
      #("model", json.string(model)),
      #("provider", json.string("openrouter")),
      #("requested_backend_provider", json.string("google-ai-studio")),
      #("reported_backend_provider", json.null()),
      #("call_id", json.string(p.call_id)),
      #("body_sha256", json.string(files.digest(p.body))),
      #("request_worst_case_nanodollars", json.int(p.worst_case_nanodollars)),
      #(
        "retained_liability_nanodollars",
        json.int(retained_reservation_nanodollars),
      ),
      #("actual_provider_cost", json.null()),
      #("cleanup", json.string("REAPED")),
      #("advice", json.string(advice)),
      #("provider_receipt", value.encode(raw)),
      #("authority", json.string("NONE")),
      #("effect_admission", json.bool(False)),
      #("automatic_retry", json.bool(False)),
    ])
    |> json.to_string
  Ok(result)
}

pub fn token_count(raw: String) -> Result(Int, String) {
  use n <- result.try(
    int.parse(raw) |> result.map_error(fn(_) { "review_tokens" }),
  )
  use _ <- result.try(require(
    int.to_string(n) == raw && n > 0 && n <= 512,
    "review_tokens",
  ))
  Ok(n)
}

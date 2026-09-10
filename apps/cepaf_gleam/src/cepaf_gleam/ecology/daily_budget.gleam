//// Pure paid-request admission. Persistence and atomic reservation belong to
//// the OCaml ledger; this value grants neither dispatch nor Sa-plan authority.

import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const daily_limit_nanodollars = 10_000_000_000

pub const reservation_nanodollars = 250_000_000

pub const max_input_bytes = 16_384

pub const max_body_bytes = 65_536

pub const max_completion_tokens = 4096

pub const template_token_allowance = 2048

pub type Price {
  Price(
    prompt_nanodollars: Int,
    completion_nanodollars: Int,
    request_nanodollars: Int,
  )
}

pub opaque type Reservation {
  Reservation(
    call_id: String,
    model: String,
    tokens: Int,
    input_bytes: Int,
    body_bytes: Int,
    worst_case: Int,
  )
}

/// Root-approved provider ceilings; a model catalog minimum is insufficient.
pub fn provider_ceiling(model: String) -> Result(Price, String) {
  case model {
    "z-ai/glm-5.3" -> Ok(Price(1400, 4400, 0))
    "moonshotai/kimi-k3" -> Ok(Price(3000, 15_000, 0))
    "deepseek/deepseek-v4-pro-0813" -> Ok(Price(1320, 3960, 0))
    "deepseek/deepseek-v4-flash-0731" -> Ok(Price(65, 180, 0))
    "google/gemma-4-31b-it" -> Ok(Price(90, 340, 0))
    _ -> Error("invalid_request: paid_model")
  }
}

fn valid_call_id(id: String) -> Bool {
  string.byte_size(id) >= 1
  && string.byte_size(id) <= 128
  && list.all(string.to_graphemes(id), fn(c) {
    string.byte_size(c) == 1
    && string.contains(
      "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-",
      c,
    )
  })
}

/// The caller passes actual input and serialized body strings, never asserted
/// byte counts. The same immutable body/model/token values must be dispatched.
pub fn admit(
  call_id: String,
  model: String,
  max_tokens: Int,
  input: String,
  body: String,
  live_price: Price,
) -> Result(Reservation, String) {
  use ceiling <- result.try(provider_ceiling(model))
  let input_size = string.byte_size(input)
  let body_size = string.byte_size(body)
  case valid_call_id(call_id) {
    False -> Error("invalid_request: call_id")
    True ->
      case max_tokens >= 1 && max_tokens <= max_completion_tokens {
        False -> Error("invalid_request: max_tokens")
        True ->
          case
            input_size <= max_input_bytes
            && body_size >= 1
            && body_size >= input_size
            && body_size <= max_body_bytes
          {
            False -> Error("invalid_request: byte_bound")
            True ->
              case
                live_price.prompt_nanodollars >= 0
                && live_price.prompt_nanodollars <= ceiling.prompt_nanodollars
                && live_price.completion_nanodollars >= 0
                && live_price.completion_nanodollars
                <= ceiling.completion_nanodollars
                && live_price.request_nanodollars == 0
              {
                False -> Error("invalid_request: provider_price")
                True -> {
                  // `input_size` is BYTES and `prompt_nanodollars` is a
                  // per-TOKEN price, which reads like a unit conflation and was
                  // filed as a defect on 2026-09-10 before being withdrawn. It
                  // deliberate. It is NOT, however, the theorem the first
                  // version of this comment claimed. Codex corrected it on
                  // 2026-09-10: "a token is never fewer than one byte" is not a
                  // universal proof, because automatically inserted BOS and
                  // turn-delimiter tokens consume ZERO input bytes. The
                  // inequality actually required is
                  //     billed_prompt_tokens <= input_utf8_bytes + template_token_allowance
                  // which is exactly what the allowance below is for. For Gemma
                  // text that holds -- byte-fallback BPE, a dedicated whitespace
                  // token, and merges that only reduce counts -- but it is an
                  // assumption about the SERVED tokenizer and template, not a
                  // proof, and the provider bills on its own reported usage.
                  // It also FAILS for multimodal: an image reference is a few
                  // dozen bytes and bills hundreds of vision tokens, so this
                  // becomes an UNDERestimate the moment such a payload is
                  // admitted. Any multimodal support must bring its own cost
                  // model first. The cost is that the bound is roughly
                  // 4x conservative at typical byte-per-token ratios, so the
                  // reservation ceiling binds about 4x earlier than a
                  // token-accurate estimate would. That is a deliberate
                  // fail-safe, not an accident; stated here so the next reader
                  // does not file the same false defect.
                  let worst_case =
                    { input_size + template_token_allowance }
                    * ceiling.prompt_nanodollars
                    + max_tokens
                    * ceiling.completion_nanodollars
                  case worst_case <= reservation_nanodollars {
                    False -> Error("invalid_request: price_bound")
                    True ->
                      Ok(Reservation(
                        call_id,
                        model,
                        max_tokens,
                        input_size,
                        body_size,
                        worst_case,
                      ))
                  }
                }
              }
          }
      }
  }
}

/// Exact finite OCaml CLI input schema. No clock, amount or day override.
pub fn ledger_request_json(reservation: Reservation) -> String {
  json.object([
    #("call_id", json.string(reservation.call_id)),
    #("model", json.string(reservation.model)),
    #("max_tokens", json.int(reservation.tokens)),
    #("input_bytes", json.int(reservation.input_bytes)),
    #("body_bytes", json.int(reservation.body_bytes)),
  ])
  |> json.to_string
}

pub fn worst_case_nanodollars(reservation: Reservation) -> Int {
  reservation.worst_case
}

/// An invoice does not reduce reserved liability. This rejects measurements
/// outside the admitted bound; the adapter additionally requires real usage,
/// finite nonnegative cost, a valid completion and exact provider/model binding.
pub fn validate_usage(
  reservation: Reservation,
  prompt_tokens: Int,
  completion_tokens: Int,
  cost_nanodollars: Int,
) -> Result(Nil, String) {
  case
    prompt_tokens >= 0
    && prompt_tokens <= reservation.input_bytes + template_token_allowance
    && completion_tokens >= 0
    && completion_tokens <= reservation.tokens
    && cost_nanodollars >= 0
    && cost_nanodollars <= reservation_nanodollars
  {
    True -> Ok(Nil)
    False -> Error("provider_violated_reservation_bound")
  }
}

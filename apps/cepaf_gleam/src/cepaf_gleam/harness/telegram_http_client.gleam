//// Pure Bounded Telegram HTTP Client & Response Decoder
////
//// Implements safe HTTP interactions with the Telegram Bot API (or private test fixture).
//// Enforces strict response verification, bounds checking, and failure taxonomy:
////   - Delivered: HTTP 200 OK with ok=true, positive message_id, and verified chat_id match.
////   - ProvenRejection: Structured 4xx refusal (400, 403, 404) with ok=false and bounded reason.
////   - AmbiguousOutcome: Network drops, timeouts, 429, 5xx, or malformed bodies (quarantined).

import cepaf_gleam/harness/telegram_ingress_guard as guard
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const default_timeout_ms = 10_000

pub const default_max_response_bytes = 65_536

pub type TelegramHttpConfiguration {
  TelegramHttpConfiguration(
    base_url: String,
    bot_token: String,
    timeout_ms: Int,
    max_response_bytes: Int,
  )
}

pub type TelegramDeliveryOutcome {
  Delivered(message_id: Int, chat_id: Int)
  ProvenRejection(error_code: Int, description: String)
  AmbiguousOutcome(reason: String)
}

@external(erlang, "telegram_http_ffi", "request")
fn ffi_http_request(
  method: http.Method,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
  timeout_ms: Int,
  max_bytes: Int,
) -> Result(#(Int, List(#(String, String)), BitArray), String)

pub fn default_configuration(
  base_url: String,
  bot_token: String,
) -> TelegramHttpConfiguration {
  TelegramHttpConfiguration(
    base_url: base_url,
    bot_token: bot_token,
    timeout_ms: default_timeout_ms,
    max_response_bytes: default_max_response_bytes,
  )
}

// -----------------------------------------------------------------------------
// sendMessage
// -----------------------------------------------------------------------------

pub fn send_message(
  config: TelegramHttpConfiguration,
  chat_id: Int,
  text: String,
  parse_mode: Option(String),
) -> TelegramDeliveryOutcome {
  let url = config.base_url <> "/bot" <> config.bot_token <> "/sendMessage"
  let body_fields = [
    #("chat_id", json.int(chat_id)),
    #("text", json.string(text)),
  ]
  let body_fields = case parse_mode {
    Some(pm) -> [#("parse_mode", json.string(pm)), ..body_fields]
    None -> body_fields
  }
  let req_body = bit_array.from_string(json.to_string(json.object(body_fields)))
  let headers = [
    #("content-type", "application/json; charset=utf-8"),
    #("accept", "application/json"),
  ]

  case
    ffi_http_request(
      http.Post,
      url,
      headers,
      req_body,
      config.timeout_ms,
      config.max_response_bytes,
    )
  {
    Error(err) -> AmbiguousOutcome(err)
    Ok(#(status_code, _resp_headers, body_bytes)) -> {
      case bit_array.byte_size(body_bytes) > config.max_response_bytes {
        True -> AmbiguousOutcome("response_payload_exceeds_bound")
        False -> {
          case bit_array.to_string(body_bytes) {
            Error(_) -> AmbiguousOutcome("invalid_utf8_response_body")
            Ok(body_str) ->
              decode_send_response(status_code, body_str, chat_id)
          }
        }
      }
    }
  }
}

fn decode_send_response(
  status_code: Int,
  body_str: String,
  expected_chat_id: Int,
) -> TelegramDeliveryOutcome {
  case status_code {
    200 -> decode_200_ok(body_str, expected_chat_id)
    400 | 403 | 404 -> decode_proven_rejection(status_code, body_str)
    429 -> AmbiguousOutcome("rate_limited_429")
    code if code >= 500 && code < 600 ->
      AmbiguousOutcome("server_error_" <> int.to_string(code))
    code -> AmbiguousOutcome("unexpected_status_code_" <> int.to_string(code))
  }
}

type SuccessPayload {
  SuccessPayload(ok: Bool, message_id: Int, chat_id: Int)
}

fn decode_200_ok(
  body_str: String,
  expected_chat_id: Int,
) -> TelegramDeliveryOutcome {
  let decoder = {
    use ok <- decode.field("ok", decode.bool)
    use message_id <- decode.subfield(["result", "message_id"], decode.int)
    use chat_id <- decode.subfield(["result", "chat", "id"], decode.int)
    decode.success(SuccessPayload(ok: ok, message_id: message_id, chat_id: chat_id))
  }

  case json.parse(body_str, decoder) {
    Error(_) -> AmbiguousOutcome("malformed_200_ok_payload")
    Ok(payload) -> {
      case
        payload.ok
        && guard.valid_positive_id(payload.message_id)
        && guard.valid_chat_id(payload.chat_id)
      {
        True -> {
          case payload.chat_id == expected_chat_id {
            True ->
              Delivered(
                message_id: payload.message_id,
                chat_id: payload.chat_id,
              )
            False ->
              AmbiguousOutcome(
                "chat_id_mismatch: expected "
                <> int.to_string(expected_chat_id)
                <> " got "
                <> int.to_string(payload.chat_id),
              )
          }
        }
        False -> AmbiguousOutcome("invalid_success_fields_in_200_ok")
      }
    }
  }
}

type ErrorPayload {
  ErrorPayload(ok: Bool, error_code: Int, description: String)
}

fn decode_proven_rejection(
  expected_status: Int,
  body_str: String,
) -> TelegramDeliveryOutcome {
  let decoder = {
    use ok <- decode.field("ok", decode.bool)
    use error_code <- decode.field("error_code", decode.int)
    use description <- decode.field("description", decode.string)
    decode.success(ErrorPayload(
      ok: ok,
      error_code: error_code,
      description: description,
    ))
  }

  case json.parse(body_str, decoder) {
    Error(_) -> AmbiguousOutcome("malformed_rejection_payload")
    Ok(payload) -> {
      case !payload.ok && payload.error_code == expected_status {
        True ->
          ProvenRejection(
            error_code: payload.error_code,
            description: sanitize_rejection_description(
              payload.error_code,
              payload.description,
            ),
          )
        False -> AmbiguousOutcome("inconsistent_error_payload")
      }
    }
  }
}

fn sanitize_rejection_description(error_code: Int, raw_desc: String) -> String {
  let lower = string.lowercase(raw_desc)
  case string.contains(lower, "chat not found") {
    True -> "chat_not_found"
    False -> {
      case string.contains(lower, "blocked by the user") {
        True -> "bot_blocked_by_user"
        False -> {
          case string.contains(lower, "user is deactivated") {
            True -> "user_deactivated"
            False -> {
              case string.contains(lower, "message is not modified") {
                True -> "message_not_modified"
                False -> {
                  case string.contains(lower, "message text is empty") {
                    True -> "message_empty"
                    False -> {
                      case string.contains(lower, "message is too long") {
                        True -> "message_too_long"
                        False -> {
                          case error_code {
                            400 -> "bad_request"
                            403 -> "forbidden"
                            404 -> "not_found"
                            _ -> "client_error_" <> int.to_string(error_code)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// getUpdates
// -----------------------------------------------------------------------------

@external(erlang, "telegram_http_ffi", "extract_telegram_updates")
fn extract_telegram_updates(body: BitArray) -> Result(List(String), String)

pub fn poll_updates(
  config: TelegramHttpConfiguration,
  offset: Int,
  limit: Int,
  timeout_seconds: Int,
) -> Result(List(String), String) {
  let url = config.base_url <> "/bot" <> config.bot_token <> "/getUpdates"
  let body_fields = [
    #("offset", json.int(offset)),
    #("limit", json.int(limit)),
    #("timeout", json.int(timeout_seconds)),
  ]
  let req_body = bit_array.from_string(json.to_string(json.object(body_fields)))
  let headers = [
    #("content-type", "application/json; charset=utf-8"),
    #("accept", "application/json"),
  ]

  use #(status_code, _headers, body_bytes) <- result.try(
    ffi_http_request(
      http.Post,
      url,
      headers,
      req_body,
      config.timeout_ms,
      config.max_response_bytes,
    )
    |> result.map_error(fn(e) { "http_poll_network_error: " <> e }),
  )

  case bit_array.byte_size(body_bytes) > config.max_response_bytes {
    True -> Error("response_payload_exceeds_bound")
    False -> {
      case status_code {
        200 -> extract_telegram_updates(body_bytes)
        code ->
          Error("getUpdates returned non-200 status: " <> int.to_string(code))
      }
    }
  }
}

// -----------------------------------------------------------------------------
// answerCallbackQuery (Internal SLO: 3000ms)
// -----------------------------------------------------------------------------

pub fn answer_callback_query(
  config: TelegramHttpConfiguration,
  callback_query_id: String,
  text: Option(String),
) -> Result(Bool, String) {
  let url =
    config.base_url <> "/bot" <> config.bot_token <> "/answerCallbackQuery"
  let body_fields = [#("callback_query_id", json.string(callback_query_id))]
  let body_fields = case text {
    Some(t) -> [#("text", json.string(t)), ..body_fields]
    None -> body_fields
  }
  let req_body = bit_array.from_string(json.to_string(json.object(body_fields)))
  let headers = [
    #("content-type", "application/json; charset=utf-8"),
    #("accept", "application/json"),
  ]

  case
    ffi_http_request(
      http.Post,
      url,
      headers,
      req_body,
      config.timeout_ms,
      config.max_response_bytes,
    )
  {
    Error(e) -> Error("answerCallbackQuery failed: " <> e)
    Ok(#(200, _headers, body_bytes)) -> {
      case bit_array.byte_size(body_bytes) > config.max_response_bytes {
        True -> Error("response_payload_exceeds_bound")
        False -> {
          case bit_array.to_string(body_bytes) {
            Error(_) -> Error("invalid_utf8_callback_body")
            Ok(body_str) -> {
              let decoder = {
                use ok <- decode.field("ok", decode.bool)
                use res <- decode.field("result", decode.bool)
                decode.success(#(ok, res))
              }
              case json.parse(body_str, decoder) {
                Ok(#(True, True)) -> Ok(True)
                Ok(#(True, False)) -> Error("callback_query_result_false")
                _ -> Error("answer_callback_query_failed")
              }
            }
          }
        }
      }
    }
    Ok(#(code, _, _)) ->
      Error("answerCallbackQuery status: " <> int.to_string(code))
  }
}

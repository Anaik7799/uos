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

pub const max_http_timeout_ms = 60_000

pub const max_allowed_response_bytes = 10_485_760

/// Declared local transport margin (in milliseconds) required between
/// `timeout_seconds * 1000` and the HTTP client timeout (`timeout_ms`).
/// This is a local client transport invariant, not a Telegram Bot API upper-limit claim.
pub const local_poll_transport_margin_ms = 1000

pub fn validate_poll_configuration(
  config: TelegramHttpConfiguration,
  limit: Int,
  timeout_seconds: Int,
) -> Result(Nil, String) {
  case config.timeout_ms < 1 {
    True -> Error("invalid_poll_config: timeout_ms_below_min")
    False ->
      case config.timeout_ms > max_http_timeout_ms {
        True -> Error("invalid_poll_config: timeout_ms_exceeds_max")
        False ->
          case config.max_response_bytes < 1 {
            True -> Error("invalid_poll_config: max_response_bytes_below_min")
            False ->
              case config.max_response_bytes > max_allowed_response_bytes {
                True ->
                  Error("invalid_poll_config: max_response_bytes_exceeds_max")
                False ->
                  case limit < 1 {
                    True -> Error("invalid_poll_config: limit_below_min")
                    False ->
                      case timeout_seconds < 0 {
                        True ->
                          Error(
                            "invalid_poll_config: poll_timeout_seconds_negative",
                          )
                        False ->
                          case
                            timeout_seconds
                            * 1000
                            + local_poll_transport_margin_ms
                            <= config.timeout_ms
                          {
                            True -> Ok(Nil)
                            False ->
                              Error(
                                "invalid_poll_config: http_timeout_ms_insufficient_for_poll_margin",
                              )
                          }
                      }
                  }
              }
          }
      }
  }
}

pub fn poll_updates(
  config: TelegramHttpConfiguration,
  offset: Int,
  limit: Int,
  timeout_seconds: Int,
) -> Result(List(String), String) {
  use _ <- result.try(validate_poll_configuration(
    config,
    limit,
    timeout_seconds,
  ))
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

// -----------------------------------------------------------------------------
// getFile and bounded file body (wave 6i, media transport)
// -----------------------------------------------------------------------------

/// What `getFile` declared for a file id. `file_path` is joined into a URL by
/// the download adapter and is validated there as well; it is validated here
/// first so a hostile path never leaves this module.
pub type FileLocator {
  FileLocator(file_path: String, declared_size_bytes: Option(Int))
}

/// Largest file body this client reads in one bounded request: the HTTP FFI
/// policy ceiling. Media whose cap exceeds it cannot be fetched by this
/// transport and is reported, never truncated.
pub const max_file_body_bytes = 10_485_760

/// Bot API `getFile`. Errors carry no URL and no token.
pub fn get_file(
  config: TelegramHttpConfiguration,
  file_id: String,
  deadline_ms: Int,
) -> Result(FileLocator, String) {
  case file_id != "" && string.byte_size(file_id) <= 256 {
    False -> Error("invalid_file_id")
    True -> {
      let url = config.base_url <> "/bot" <> config.bot_token <> "/getFile"
      let req_body =
        bit_array.from_string(
          json.to_string(json.object([#("file_id", json.string(file_id))])),
        )
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
          bounded_deadline(config, deadline_ms),
          config.max_response_bytes,
        )
      {
        Error(err) -> Error("get_file_transport: " <> err)
        Ok(#(200, _, body_bytes)) ->
          case bit_array.to_string(body_bytes) {
            Error(_) -> Error("get_file_invalid_utf8")
            Ok(body_str) -> decode_get_file(body_str)
          }
        Ok(#(code, _, _)) -> Error("get_file_status_" <> int.to_string(code))
      }
    }
  }
}

fn decode_get_file(body_str: String) -> Result(FileLocator, String) {
  let decoder = {
    use ok <- decode.field("ok", decode.bool)
    use path <- decode.subfield(["result", "file_path"], decode.string)
    use size <- decode.optional_field(
      "result",
      None,
      decode.optional({
        use s <- decode.optional_field(
          "file_size",
          None,
          decode.optional(decode.int),
        )
        decode.success(s)
      }),
    )
    decode.success(#(ok, path, option.flatten(size)))
  }
  case json.parse(body_str, decoder) {
    Error(_) -> Error("get_file_malformed_payload")
    Ok(#(False, _, _)) -> Error("get_file_not_ok")
    Ok(#(True, path, size)) ->
      case valid_file_path(path) {
        False -> Error("get_file_invalid_file_path")
        True ->
          case size {
            Some(n) if n < 0 -> Error("get_file_negative_size")
            _ -> Ok(FileLocator(file_path: path, declared_size_bytes: size))
          }
      }
  }
}

/// A file_path is joined into a URL: refuse empty, absolute, traversal, query,
/// fragment, NUL and anything over 256 bytes.
pub fn valid_file_path(path: String) -> Bool {
  path != ""
  && string.byte_size(path) <= 256
  && !string.starts_with(path, "/")
  && !string.contains(path, "..")
  && !string.contains(path, "?")
  && !string.contains(path, "#")
  && !string.contains(path, "\u{0}")
}

/// GET the file body at `<base_url>/file/bot<token>/<file_path>` with a hard
/// byte bound (at most `max_file_body_bytes`). Oversize bodies are an error
/// from the FFI, never a truncated success. The URL exists only inside this
/// function; errors carry none of it.
pub fn fetch_file_bytes(
  config: TelegramHttpConfiguration,
  file_path: String,
  max_bytes: Int,
  deadline_ms: Int,
) -> Result(BitArray, String) {
  case valid_file_path(file_path) {
    False -> Error("fetch_file_invalid_file_path")
    True -> {
      let bound = case max_bytes < 1, max_bytes > max_file_body_bytes {
        True, _ -> 1
        _, True -> max_file_body_bytes
        _, _ -> max_bytes
      }
      let url =
        config.base_url <> "/file/bot" <> config.bot_token <> "/" <> file_path
      case
        ffi_http_request(
          http.Get,
          url,
          [#("accept", "application/octet-stream")],
          <<>>,
          bounded_deadline(config, deadline_ms),
          bound,
        )
      {
        Error(err) -> Error("fetch_file_transport: " <> err)
        Ok(#(200, _, body)) ->
          case bit_array.byte_size(body) > bound {
            True -> Error("fetch_file_body_exceeds_bound")
            False -> Ok(body)
          }
        Ok(#(code, _, _)) -> Error("fetch_file_status_" <> int.to_string(code))
      }
    }
  }
}

/// The smaller of the caller's deadline and the configured timeout, never
/// below one millisecond.
fn bounded_deadline(config: TelegramHttpConfiguration, deadline_ms: Int) -> Int {
  case deadline_ms < 1 {
    True -> 1
    False ->
      case deadline_ms > config.timeout_ms {
        True -> config.timeout_ms
        False -> deadline_ms
      }
  }
}

// -----------------------------------------------------------------------------
// Ranged file body (wave 6j): bounded chunks instead of one bounded read
// -----------------------------------------------------------------------------

/// Bytes of one HTTP range request on a file body. `last` is true when the
/// server's `Content-Range` total is reached, when the server answered the
/// whole body to a request from offset zero, or when a non-zero offset is not
/// satisfiable (the body ended exactly at the previous chunk).
pub type RangeChunk {
  RangeChunk(bytes: BitArray, total: Option(Int), last: Bool)
}

/// Chunk size the media transport asks for per request: well inside the FFI
/// ceiling, so no single response is ever larger than this plus headers.
pub const file_range_chunk_bytes = 4_194_304

/// GET `<base_url>/file/bot<token>/<file_path>` with `Range: bytes=offset-end`.
/// A 206 answer yields the partial body and its `Content-Range`; a 200 answer
/// means the server ignored the range and is accepted only from offset zero and
/// only when the whole body fits the chunk bound (then it is the last chunk);
/// 416 at a non-zero offset is the end of the body. Every response is bounded
/// by the FFI to `chunk_bytes` plus nothing: an oversize body is an error.
pub fn fetch_file_range(
  config: TelegramHttpConfiguration,
  file_path: String,
  offset: Int,
  chunk_bytes: Int,
  deadline_ms: Int,
) -> Result(RangeChunk, String) {
  case valid_file_path(file_path), offset >= 0, chunk_bytes >= 1 {
    False, _, _ -> Error("fetch_file_invalid_file_path")
    _, False, _ -> Error("fetch_file_invalid_offset")
    _, _, False -> Error("fetch_file_invalid_chunk")
    True, True, True -> {
      let bound = case chunk_bytes > max_file_body_bytes {
        True -> max_file_body_bytes
        False -> chunk_bytes
      }
      let url =
        config.base_url <> "/file/bot" <> config.bot_token <> "/" <> file_path
      let range =
        "bytes="
        <> int.to_string(offset)
        <> "-"
        <> int.to_string(offset + bound - 1)
      case
        ffi_http_request(
          http.Get,
          url,
          [#("accept", "application/octet-stream"), #("range", range)],
          <<>>,
          bounded_deadline(config, deadline_ms),
          bound,
        )
      {
        Error(err) -> Error("fetch_file_transport: " <> err)
        Ok(#(206, resp_headers, body)) ->
          case parse_content_range(resp_headers) {
            Error(reason) -> Error(reason)
            Ok(#(first, last_byte, total)) ->
              case
                first == offset
                && bit_array.byte_size(body) == last_byte - first + 1
                && bit_array.byte_size(body) <= bound
              {
                False -> Error("fetch_file_range_mismatch")
                True ->
                  Ok(RangeChunk(
                    bytes: body,
                    total: total,
                    last: case total {
                      Some(t) -> last_byte + 1 >= t
                      None -> bit_array.byte_size(body) < bound
                    },
                  ))
              }
          }
        Ok(#(200, _, body)) ->
          case offset == 0 && bit_array.byte_size(body) <= bound {
            True ->
              Ok(RangeChunk(
                bytes: body,
                total: Some(bit_array.byte_size(body)),
                last: True,
              ))
            False -> Error("fetch_file_range_not_supported")
          }
        Ok(#(416, _, _)) ->
          case offset > 0 {
            True -> Ok(RangeChunk(bytes: <<>>, total: None, last: True))
            False -> Error("fetch_file_status_416")
          }
        Ok(#(code, _, _)) -> Error("fetch_file_status_" <> int.to_string(code))
      }
    }
  }
}

/// `Content-Range: bytes first-last/total` with `total` possibly `*`.
pub fn parse_content_range(
  headers: List(#(String, String)),
) -> Result(#(Int, Int, Option(Int)), String) {
  let found =
    list_find_header(headers, "content-range")
  case found {
    Error(_) -> Error("fetch_file_missing_content_range")
    Ok(value) ->
      case string.split(string.trim(value), " ") {
        ["bytes", spec] ->
          case string.split(spec, "/") {
            [range, total_text] ->
              case string.split(range, "-") {
                [first_text, last_text] ->
                  case
                    int.parse(first_text),
                    int.parse(last_text),
                    total_text
                  {
                    Ok(first), Ok(last_byte), "*" if first <= last_byte ->
                      Ok(#(first, last_byte, None))
                    Ok(first), Ok(last_byte), t if first <= last_byte ->
                      case int.parse(t) {
                        Ok(total) if total > last_byte ->
                          Ok(#(first, last_byte, Some(total)))
                        _ -> Error("fetch_file_invalid_content_range")
                      }
                    _, _, _ -> Error("fetch_file_invalid_content_range")
                  }
                _ -> Error("fetch_file_invalid_content_range")
              }
            _ -> Error("fetch_file_invalid_content_range")
          }
        _ -> Error("fetch_file_invalid_content_range")
      }
  }
}

fn list_find_header(
  headers: List(#(String, String)),
  name: String,
) -> Result(String, Nil) {
  case headers {
    [] -> Error(Nil)
    [#(k, v), ..rest] ->
      case string.lowercase(k) == name {
        True -> Ok(v)
        False -> list_find_header(rest, name)
      }
  }
}

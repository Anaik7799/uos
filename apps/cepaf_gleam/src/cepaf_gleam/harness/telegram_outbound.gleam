//// =============================================================================
//// [C3I-SIL6-MSTS] UOS Pure Gleam Telegram Outbound Delivery Engine
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/harness/telegram_outbound</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Native BEAM OTP 29 Telegram Outbound Delivery Substrate</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TELEGRAM-001, SC-OUTBOUND-001, SC-MUDA-001, SC-ZMOF-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub const max_message_length: Int = 4096
pub const default_lookback_window: Int = 512

pub type OutboundDeliveryResult {
  OutboundDeliveryResult(
    chat_id: String,
    chunks_sent: Int,
    total_bytes: Int,
    last_message_id: Int,
  )
}

pub type TelegramApiResponse {
  TelegramApiResponse(
    ok: Bool,
    message_id: Option(Int),
    error_description: Option(String),
  )
}

@external(erlang, "cepaf_gleam_ffi", "http_post")
fn ffi_http_post(
  url: String,
  headers: List(#(String, String)),
  content_type: String,
  body: String,
  timeout_ms: Int,
) -> Result(#(Int, BitArray), String)

@external(erlang, "cepaf_gleam_ffi", "get_preference")
fn ffi_get_preference(key: String) -> Result(String, String)

/// Resolves the Telegram bot token from environment or canonical state database.
pub fn get_telegram_token() -> Result(String, String) {
  case ffi_get_preference("telegram_token") {
    Ok(token) -> {
      let trimmed = string.trim(token)
      case trimmed {
        "" -> Error("telegram_token is empty in preference store")
        _ -> Ok(trimmed)
      }
    }
    Error(_) -> Error("telegram_token not found in environment or database")
  }
}

/// Resolves the default target Telegram chat ID from environment or state database.
pub fn get_default_chat_id() -> Result(String, String) {
  case ffi_get_preference("telegram_chat_id") {
    Ok(cid) -> {
      let trimmed = string.trim(cid)
      case trimmed {
        "" -> Error("telegram_chat_id is empty in preference store")
        _ -> Ok(trimmed)
      }
    }
    Error(_) -> Error("telegram_chat_id not found in environment or database")
  }
}

/// Chunks text into slices no larger than max_len (default 4096), preserving
/// newline or whitespace boundaries within a 512-character lookback window.
pub fn chunk_text(text: String, max_len: Int) -> List(String) {
  let len = string.length(text)
  case len <= max_len {
    True -> [text]
    False -> do_chunk_text(text, max_len, [])
  }
}

fn do_chunk_text(remaining: String, max_len: Int, acc: List(String)) -> List(String) {
  let len = string.length(remaining)
  case len <= max_len {
    True -> list.reverse([remaining, ..acc])
    False -> {
      let cut_index = find_cut_index(remaining, max_len)
      let chunk = string.slice(remaining, 0, cut_index)
      let rest = string.slice(remaining, cut_index, len - cut_index)
      do_chunk_text(rest, max_len, [chunk, ..acc])
    }
  }
}

/// Finds the optimal cut index within max_len:
/// Searches backwards up to 512 characters for newline, then for space,
/// and falls back to a hard cut at max_len if no delimiter is present.
pub fn find_cut_index(text: String, max_len: Int) -> Int {
  let lookback = int.min(default_lookback_window, max_len)
  let start_pos = max_len - lookback
  let lookback_slice = string.slice(text, start_pos, lookback)
  case find_last_char_offset(lookback_slice, "\n") {
    Some(offset) -> start_pos + offset + 1
    None ->
      case find_last_char_offset(lookback_slice, " ") {
        Some(offset) -> start_pos + offset + 1
        None -> max_len
      }
  }
}

/// Finds the 0-indexed offset of the last occurrence of target delimiter in str.
pub fn find_last_char_offset(str: String, target: String) -> Option(Int) {
  case string.split(str, target) {
    [] | [_] -> None
    parts -> {
      let all_but_last = list.take(parts, list.length(parts) - 1)
      let chars_before =
        list.fold(all_but_last, 0, fn(acc, part) { acc + string.length(part) })
      let target_occurrences = list.length(all_but_last) - 1
      let target_len = string.length(target)
      let offset = chars_before + { target_occurrences * target_len }
      Some(offset)
    }
  }
}

/// Decoder for Telegram Bot API JSON responses.
fn telegram_api_decoder() -> decode.Decoder(TelegramApiResponse) {
  use ok <- decode.field("ok", decode.bool)
  use result_val <- decode.optional_field(
    "result",
    None,
    decode.optional({
      use msg_id <- decode.field("message_id", decode.int)
      decode.success(msg_id)
    }),
  )
  use description <- decode.optional_field(
    "description",
    None,
    decode.optional(decode.string),
  )

  decode.success(TelegramApiResponse(
    ok: ok,
    message_id: result_val,
    error_description: description,
  ))
}

/// Sends a single raw message to Telegram Bot API over native BEAM TLS.
/// If sending with Markdown fails due to entity parsing errors, automatically
/// falls back to unformatted plaintext so the message is never lost.
pub fn send_single_message(
  token: String,
  chat_id: String,
  text: String,
  parse_mode: Option(String),
) -> Result(Int, String) {
  let url = "https://api.telegram.org/bot" <> token <> "/sendMessage"
  let headers = [#("content-type", "application/json; charset=utf-8")]
  let content_type = "application/json; charset=utf-8"

  let payload = build_send_payload(chat_id, text, parse_mode)
  case ffi_http_post(url, headers, content_type, payload, 10_000) {
    Ok(#(200, res_bytes)) -> parse_api_success(res_bytes)
    Ok(#(_status, res_bytes)) -> {
      case parse_api_response(res_bytes) {
        Ok(api_res) -> {
          // If parse mode was specified and failed, retry as plaintext fallback
          case parse_mode {
            Some(_) -> {
              let fallback_payload = build_send_payload(chat_id, text, None)
              case ffi_http_post(url, headers, content_type, fallback_payload, 10_000) {
                Ok(#(200, fb_bytes)) -> parse_api_success(fb_bytes)
                Ok(#(fb_status, fb_bytes)) ->
                  Error(
                    "Telegram fallback failed with status "
                    <> int.to_string(fb_status)
                    <> ": "
                    <> extract_error_detail(fb_bytes),
                  )
                Error(err) -> Error("Telegram fallback network error: " <> err)
              }
            }
            None ->
              Error(
                "Telegram API error: "
                <> option.unwrap(api_res.error_description, "unknown"),
              )
          }
        }
        Error(err) -> Error("Failed to decode Telegram error response: " <> err)
      }
    }
    Error(err) -> Error("HTTP network failure connecting to Telegram: " <> err)
  }
}

fn build_send_payload(chat_id: String, text: String, parse_mode: Option(String)) -> String {
  let base_fields = [
    #("chat_id", json.string(chat_id)),
    #("text", json.string(text)),
  ]
  let fields = case parse_mode {
    Some(pm) if pm != "" -> [#("parse_mode", json.string(pm)), ..base_fields]
    _ -> base_fields
  }
  json.object(fields)
  |> json.to_string
}

fn parse_api_response(raw_bytes: BitArray) -> Result(TelegramApiResponse, String) {
  case bit_array.to_string(raw_bytes) {
    Ok(json_str) ->
      json.parse(json_str, telegram_api_decoder())
      |> result.map_error(fn(e) { "json_parse_error: " <> string.inspect(e) })
    Error(_) -> Error("Non-UTF8 response from Telegram")
  }
}

fn parse_api_success(raw_bytes: BitArray) -> Result(Int, String) {
  case parse_api_response(raw_bytes) {
    Ok(TelegramApiResponse(ok: True, message_id: Some(id), ..)) -> Ok(id)
    Ok(TelegramApiResponse(ok: True, message_id: None, ..)) -> Ok(0)
    Ok(TelegramApiResponse(ok: False, error_description: Some(desc), ..)) ->
      Error("Telegram rejected: " <> desc)
    Ok(TelegramApiResponse(ok: False, ..)) -> Error("Telegram rejected with ok=false")
    Error(err) -> Error(err)
  }
}

fn extract_error_detail(raw_bytes: BitArray) -> String {
  case parse_api_response(raw_bytes) {
    Ok(res) -> option.unwrap(res.error_description, "unspecified")
    Error(_) ->
      case bit_array.to_string(raw_bytes) {
        Ok(s) -> s
        Error(_) -> "binary error payload"
      }
  }
}

/// Delivers a full outbound response to Telegram:
/// Automatically chunks long messages (<= 4096 chars), sends each chunk sequentially,
/// falls back to plaintext if Markdown formatting fails, and returns summary metrics.
pub fn deliver_outbound_response(
  token: String,
  chat_id: String,
  text: String,
  parse_mode: String,
) -> Result(OutboundDeliveryResult, String) {
  let chunks = chunk_text(text, max_message_length)
  let opt_pm = case parse_mode {
    "" -> None
    pm -> Some(pm)
  }

  deliver_chunks(token, chat_id, chunks, opt_pm, 0, 0, 0)
}

fn deliver_chunks(
  token: String,
  chat_id: String,
  remaining_chunks: List(String),
  parse_mode: Option(String),
  sent_count: Int,
  total_bytes: Int,
  last_msg_id: Int,
) -> Result(OutboundDeliveryResult, String) {
  case remaining_chunks {
    [] ->
      Ok(OutboundDeliveryResult(
        chat_id: chat_id,
        chunks_sent: sent_count,
        total_bytes: total_bytes,
        last_message_id: last_msg_id,
      ))
    [chunk, ..rest] -> {
      let chunk_bytes = string.length(chunk)
      case send_single_message(token, chat_id, chunk, parse_mode) {
        Ok(msg_id) ->
          deliver_chunks(
            token,
            chat_id,
            rest,
            parse_mode,
            sent_count + 1,
            total_bytes + chunk_bytes,
            msg_id,
          )
        Error(err) ->
          Error(
            "Failed delivering chunk "
            <> int.to_string(sent_count + 1)
            <> ": "
            <> err,
          )
      }
    }
  }
}

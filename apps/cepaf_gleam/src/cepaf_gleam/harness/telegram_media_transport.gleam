//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_transport</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T2, SC-SEC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// The HTTP fetch transport for media intake (waves 6i and 6j): a
//// `telegram_media_download.Transport` built on the bounded Telegram HTTP
//// client, so a deployment can bind intake through
//// `telegram_service.configure_media`.
////
//// The download adapter builds the credential-bearing file URL itself, always
//// on `https://api.telegram.org`. This transport accepts ONLY that prefix with
//// the configured token, takes the file path after it, re-validates it, and
//// fetches from the CONFIGURED base host. The configured host is therefore the
//// only host this transport ever contacts: production configures the real API
//// host, a staged service configures the local HTTP fixture, and nothing in
//// between can redirect a fetch elsewhere.
////
//// Bodies are fetched as HTTP ranges of `chunk_bytes` (4 MiB) each, one
//// guarded request per range, so no single response exceeds the FFI ceiling
//// and the download adapter's per-kind cap law runs across chunks: the full
//// design caps (up to 52 MiB for video) are reachable while the process never
//// holds more than one chunk from the transport at a time. A server that
//// ignores `Range` is accepted only when the whole body fits one chunk.
////
//// Honest limits:
//// * One stream deadline covers every range of a file; a slow server fails
////   the stream as `stream_deadline_exceeded`, never a partial success.
//// * No retry, no redirect following, no streaming to disk.
//// * The download adapter still holds the concatenated body in memory up to
////   the per-kind cap; the chunking bounds the transport, not the adapter.

import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_media_download as download
import gleam/erlang/process
import gleam/int
import gleam/option.{None, Some}
import gleam/string

/// Bytes requested per range.
pub const chunk_bytes = http_client.file_range_chunk_bytes

/// Historical name of the single-read ceiling (wave 6i); kept for callers that
/// read it, now the per-chunk bound rather than a per-file limit.
pub const max_body_bytes = http_client.max_file_body_bytes

const api_file_prefix = "https://api.telegram.org/file/bot"

/// Erlang time unit atom for `erlang:monotonic_time/1`.
type TimeUnit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: TimeUnit) -> Int

fn now_ms() -> Int {
  monotonic_time(Millisecond)
}

/// Build the transport for a client configuration. The token lives only in
/// the configuration captured by the closures.
pub fn from_http(
  config: http_client.TelegramHttpConfiguration,
) -> download.Transport {
  download.Transport(
    get_file: fn(file_id, deadline_ms) {
      case http_client.get_file(config, file_id, deadline_ms) {
        Error(reason) -> Error(reason)
        Ok(locator) ->
          Ok(download.FileMeta(
            file_path: locator.file_path,
            declared_size_bytes: locator.declared_size_bytes,
          ))
      }
    },
    open_stream: fn(full_url, deadline_ms) {
      case file_path_of(config, full_url) {
        Error(reason) -> Error(reason)
        Ok(file_path) -> Ok(ranged_reader(config, file_path, deadline_ms))
      }
    },
  )
}

/// The file path after the exact `https://api.telegram.org/file/bot<token>/`
/// prefix for THIS configuration; any other URL is refused by name.
pub fn file_path_of(
  config: http_client.TelegramHttpConfiguration,
  full_url: String,
) -> Result(String, String) {
  let expected = api_file_prefix <> config.bot_token <> "/"
  case string.starts_with(full_url, expected) {
    False -> Error("file_url_not_for_this_bot")
    True -> {
      let path = string.drop_start(full_url, string.length(expected))
      case http_client.valid_file_path(path) {
        False -> Error("file_url_invalid_path")
        True -> Ok(path)
      }
    }
  }
}

type Cursor {
  Cursor(offset: Int, total: option.Option(Int), done: Bool)
}

/// The largest per-kind cap (video). A chunk whose `Content-Range` total
/// exceeds it can never fit any kind, so the stream is refused as
/// `range_total_over_limit:<total>` before another range is fetched; the
/// download adapter maps that reason onto its over-cap `Aborted` outcome.
pub const max_total_bytes = 52_428_800

/// Prefix of the over-limit reason the download adapter recognises.
pub const over_limit_prefix = download.range_total_over_limit_prefix

/// A reader that fetches one range per call, advancing an offset held in a
/// private subject, until the server reports the last chunk. The first total a
/// server advertises is kept in the cursor and every later chunk must agree.
/// The stream deadline is absolute from the moment the stream opened.
fn ranged_reader(
  config: http_client.TelegramHttpConfiguration,
  file_path: String,
  deadline_ms: Int,
) -> fn() -> Result(option.Option(BitArray), String) {
  let cursor = process.new_subject()
  process.send(cursor, Cursor(offset: 0, total: None, done: False))
  let absolute_deadline = now_ms() + deadline_ms
  fn() {
    let state = case process.receive(cursor, 0) {
      Ok(c) -> c
      Error(_) -> Cursor(offset: 0, total: None, done: True)
    }
    case state.done {
      True -> {
        process.send(cursor, state)
        Ok(None)
      }
      False -> {
        let remaining = absolute_deadline - now_ms()
        case remaining <= 0 {
          True -> {
            process.send(cursor, Cursor(..state, done: True))
            Error("stream_deadline_exceeded")
          }
          False ->
            case
              http_client.fetch_file_range_checked(
                config,
                file_path,
                state.offset,
                chunk_bytes,
                remaining,
                state.total,
              )
            {
              Error(reason) -> {
                process.send(cursor, Cursor(..state, done: True))
                Error(reason)
              }
              Ok(http_client.RangeChunk(bytes: bytes, total: total, last: last)) -> {
                let size = bit_size_bytes(bytes)
                let first_total = case state.total {
                  None -> total
                  kept -> kept
                }
                case first_total {
                  Some(t) if t > max_total_bytes -> {
                    process.send(cursor, Cursor(..state, done: True))
                    Error(over_limit_prefix <> int.to_string(t))
                  }
                  _ -> {
                    process.send(
                      cursor,
                      Cursor(
                        offset: state.offset + size,
                        total: first_total,
                        done: last,
                      ),
                    )
                    case size == 0 {
                      True -> Ok(None)
                      False -> Ok(Some(bytes))
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

@external(erlang, "erlang", "byte_size")
fn bit_size_bytes(bytes: BitArray) -> Int

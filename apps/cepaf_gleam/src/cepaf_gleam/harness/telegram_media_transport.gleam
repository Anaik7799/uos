//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_transport</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T2, SC-SEC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// The HTTP fetch transport for media intake (wave 6i): a
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
//// Honest limits:
//// * One bounded read per file, at most `max_body_bytes` (the HTTP FFI policy
////   ceiling, 10 MiB). Media above that cannot be fetched by this transport and
////   is refused, never truncated; the per-kind caps above it (audio, document,
////   video) are unreachable here and the download adapter reports the abort.
//// * The reader yields the whole body once, then end of stream; the download
////   adapter's chunk bound and cap law still apply to that one chunk.
//// * No retry, no redirect following, no streaming to disk.

import cepaf_gleam/harness/telegram_http_client as http_client
import cepaf_gleam/harness/telegram_media_download as download
import gleam/erlang/process
import gleam/option.{None, Some}
import gleam/string

/// The HTTP FFI policy ceiling, restated so callers can reason about it.
pub const max_body_bytes = http_client.max_file_body_bytes

const api_file_prefix = "https://api.telegram.org/file/bot"

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
        Ok(file_path) ->
          case
            http_client.fetch_file_bytes(
              config,
              file_path,
              max_body_bytes,
              deadline_ms,
            )
          {
            Error(reason) -> Error(reason)
            Ok(body) -> Ok(one_shot_reader(body))
          }
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

/// A reader that yields `body` exactly once and then end of stream.
fn one_shot_reader(
  body: BitArray,
) -> fn() -> Result(option.Option(BitArray), String) {
  let queue = process.new_subject()
  process.send(queue, body)
  fn() {
    case process.receive(queue, 0) {
      Ok(chunk) -> Ok(Some(chunk))
      Error(_) -> Ok(None)
    }
  }
}

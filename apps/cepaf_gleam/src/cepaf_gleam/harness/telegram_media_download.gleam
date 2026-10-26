//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_download</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T2, SC-SEC-001, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Media design T2: bounded download adapter. PURE: every effect (getFile, the
//// streamed GET, the token read) is injected. This module performs no HTTP,
//// reads no token source, logs nothing and touches no file.
////
//// Every bound is enforced twice where the sender controls the input: once on
//// the declared size before any request, once on the observed byte count while
//// streaming. The download URL embeds the bot token in its path, so the URL is
//// built in one private function, handed only to `open_stream`, and never
//// stored in any returned value. Every string forwarded from the transport is
//// redacted before it leaves this module.

import cepaf_gleam/harness/telegram_media_ref.{
  type MediaKind, type MediaRef, Animation, Audio, Document, Photo, Sticker,
  Unsupported, Video, Voice,
}
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Result of Telegram `getFile`. `declared_size_bytes` is what Telegram (and
/// transitively the sender) declared; it is never trusted as the final bound.
pub type FileMeta {
  FileMeta(file_path: String, declared_size_bytes: Option(Int))
}

/// Injected effects. `get_file(file_id, deadline_ms)` performs getFile.
/// `open_stream(full_url, deadline_ms)` returns a chunk reader:
/// `Ok(Some(chunk))` next chunk, `Ok(None)` end of stream, `Error(reason)`.
pub type Transport {
  Transport(
    get_file: fn(String, Int) -> Result(FileMeta, String),
    open_stream: fn(String, Int) ->
      Result(fn() -> Result(Option(BitArray), String), String),
  )
}

pub type Outcome {
  Rejected(RejectReason)
  Aborted(observed_bytes: Int, cap_bytes: Int)
  Fetched(
    kind: MediaKind,
    file_unique_id: String,
    bytes: Int,
    sha256_hex: String,
    content: BitArray,
  )
}

pub type RejectReason {
  UnsupportedKind(String)
  AlreadyFetched(file_unique_id: String)
  DeclaredOverCap(declared: Int, cap: Int)
  TokenUnavailable(String)
  GetFileFailed(String)
  StreamOpenFailed(String)
  StreamReadFailed(String)
}

pub const get_file_deadline_ms = 3000

pub const stream_deadline_ms = 15_000

/// The reader is invoked at most this many times per download.
pub const max_chunks = 4096

const url_marker = "/file/bot"

const redacted_marker = "[REDACTED]"

/// UOS policy size cap per kind. `Unsupported(_)` is 0: nothing is fetched.
pub fn cap_for(kind: MediaKind) -> Int {
  case kind {
    Photo -> 10_485_760
    Voice -> 5_242_880
    Audio -> 26_214_400
    Document -> 26_214_400
    Video -> 52_428_800
    Sticker -> 1_048_576
    Animation -> 10_485_760
    Unsupported(_) -> 0
  }
}

/// Download one media unit within its bounds. See the module header.
pub fn download(
  ref: MediaRef,
  already_fetched: List(String),
  token: fn() -> Result(String, String),
  transport: Transport,
) -> Outcome {
  case ref.kind {
    Unsupported(k) -> Rejected(UnsupportedKind(k))
    kind ->
      case list.contains(already_fetched, ref.file_unique_id) {
        True -> Rejected(AlreadyFetched(ref.file_unique_id))
        False -> {
          let cap = cap_for(kind)
          case over_cap(ref.declared_size_bytes, cap) {
            Some(declared) -> Rejected(DeclaredOverCap(declared, cap))
            None -> fetch_meta(ref, kind, cap, token, transport)
          }
        }
      }
  }
}

fn over_cap(declared: Option(Int), cap: Int) -> Option(Int) {
  case declared {
    Some(n) if n > cap -> Some(n)
    _ -> None
  }
}

fn fetch_meta(
  ref: MediaRef,
  kind: MediaKind,
  cap: Int,
  token: fn() -> Result(String, String),
  transport: Transport,
) -> Outcome {
  case transport.get_file(ref.file_id, get_file_deadline_ms) {
    Error(reason) -> Rejected(GetFileFailed(redact_file_url(reason)))
    Ok(meta) ->
      case over_cap(meta.declared_size_bytes, cap) {
        Some(declared) -> Rejected(DeclaredOverCap(declared, cap))
        None ->
          case valid_file_path(meta.file_path) {
            False -> Rejected(GetFileFailed("invalid_file_path"))
            True -> open(ref, kind, cap, meta.file_path, token, transport)
          }
      }
  }
}

/// A file_path is joined into a URL, so refuse anything that could change the
/// request target: empty, absolute, traversal, query or fragment.
fn valid_file_path(path: String) -> Bool {
  path != ""
  && !string.starts_with(path, "/")
  && !string.contains(path, "..")
  && !string.contains(path, "?")
  && !string.contains(path, "#")
}

fn open(
  ref: MediaRef,
  kind: MediaKind,
  cap: Int,
  file_path: String,
  token: fn() -> Result(String, String),
  transport: Transport,
) -> Outcome {
  case token() {
    Error(reason) -> Rejected(TokenUnavailable(redact_file_url(reason)))
    Ok(secret) -> {
      let scrub = fn(text: String) { scrub_secret(text, secret) }
      case
        transport.open_stream(build_url(secret, file_path), stream_deadline_ms)
      {
        Error(reason) -> Rejected(StreamOpenFailed(scrub(reason)))
        Ok(reader) ->
          case read_loop(reader, cap, 0, 0, [], scrub) {
            ReadAborted(observed) -> Aborted(observed, cap)
            ReadFailed(reason) -> Rejected(StreamReadFailed(reason))
            ReadDone(total, chunks) -> {
              let content = bit_array.concat(list.reverse(chunks))
              Fetched(
                kind: kind,
                file_unique_id: ref.file_unique_id,
                bytes: total,
                sha256_hex: sha256_hex(content),
                content: content,
              )
            }
          }
      }
    }
  }
}

/// The ONLY place the credential-bearing URL exists.
fn build_url(secret: String, file_path: String) -> String {
  "https://api.telegram.org/file/bot" <> secret <> "/" <> file_path
}

type ReadResult {
  ReadDone(total: Int, chunks: List(BitArray))
  ReadAborted(observed: Int)
  ReadFailed(String)
}

fn read_loop(
  reader: fn() -> Result(Option(BitArray), String),
  cap: Int,
  reads: Int,
  total: Int,
  acc: List(BitArray),
  scrub: fn(String) -> String,
) -> ReadResult {
  case reads >= max_chunks {
    True -> ReadFailed("chunk_bound")
    False ->
      case reader() {
        Error(reason) -> ReadFailed(scrub(reason))
        Ok(None) -> ReadDone(total, acc)
        Ok(Some(chunk)) -> {
          let new_total = total + bit_array.byte_size(chunk)
          case new_total > cap {
            True -> ReadAborted(new_total)
            False ->
              read_loop(
                reader,
                cap,
                reads + 1,
                new_total,
                [chunk, ..acc],
                scrub,
              )
          }
        }
      }
  }
}

fn sha256_hex(content: BitArray) -> String {
  crypto.hash(crypto.Sha256, content)
  |> bit_array.base16_encode
  |> string.lowercase
}

/// Remove URL credentials, then the literal secret as defence in depth.
fn scrub_secret(text: String, secret: String) -> String {
  let redacted = redact_file_url(text)
  case secret {
    "" -> redacted
    _ -> string.replace(redacted, secret, redacted_marker)
  }
}

/// Replace every `/file/bot<anything up to the next />` with
/// `/file/bot[REDACTED]`. Total, single pass, idempotent.
pub fn redact_file_url(text: String) -> String {
  case string.split(text, url_marker) {
    [] -> text
    [head, ..tails] ->
      list.fold(tails, head, fn(acc, tail) {
        acc <> url_marker <> redacted_marker <> after_first_slash(tail)
      })
  }
}

fn after_first_slash(tail: String) -> String {
  case string.split_once(tail, "/") {
    Ok(#(_, rest)) -> "/" <> rest
    Error(_) -> ""
  }
}

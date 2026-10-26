//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_inspect</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T3, SC-SEC-001, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Media design T3: bounded content inspection by magic bytes.
////
//// This module identifies a fetched object's container type from the first
//// `prefix_bytes` bytes and checks it against the allowlist for the declared
//// media kind. It is PURE and deliberately weak: it does not decode, execute,
//// open, decompress or analyse content, calls no NIF, spawns no process and
//// never reads `declared_mime` or a file name. A ZIP is recognised by its
//// first four bytes and is never opened. Nothing here claims to measure
//// anything about the payload, so no function is named after a transform.
////
//// Honest limits (recorded by the wave 6c independent review, M-12, M-13):
//// * `Mp4` means "ISO-BMFF `ftyp` container", so HEIC, AVIF, M4A and 3GP
////   also sniff as `Mp4`; the allowlist admits them for Video and Animation.
//// * `Mp3` covers the ID3 tag and the frame syncs FF FB, FF F3 and FF F2;
////   FF FA and FF FD frames sniff `Unknown` and are rejected (false negative,
////   never a false acceptance).
//// * A prefix sniff cannot detect a polyglot: a file that starts with one
////   signature may be something else after byte 64. `Accepted` narrows the
////   container type for a later bounded stage; it never means safe to open.
//// * The design's N-3 obligation to RECORD a declared-mime mismatch is not met
////   here: this module has no mime parameter by design, so a caller that wants
////   the mismatch recorded compares `Accepted(sniffed)` with the ref's
////   `declared_mime` itself.

import cepaf_gleam/harness/telegram_media_download as download
import cepaf_gleam/harness/telegram_media_ref.{
  type MediaKind, Animation, Audio, Document, Photo, Sticker, Unsupported, Video,
  Voice,
}
import gleam/bit_array
import gleam/list
import gleam/string

/// Only this many leading bytes are ever examined.
pub const prefix_bytes = 64

pub type Sniffed {
  Jpeg
  Png
  Gif
  Webp
  Ogg
  Mp3
  Mp4
  Pdf
  Zip
  Unknown
}

pub type Verdict {
  /// The sniffed type is allowlisted for the declared kind. `sniffed` is an
  /// observation of the bytes, distinct from any declared mime.
  Accepted(sniffed: Sniffed)
  Rejected(reason: String, sniffed: Sniffed)
}

/// The bounded prefix that `sniff` reads: at most `prefix_bytes` bytes.
pub fn examined_prefix(content: BitArray) -> BitArray {
  let size = bit_array.byte_size(content)
  case size <= prefix_bytes {
    True -> content
    False ->
      case bit_array.slice(content, 0, prefix_bytes) {
        Ok(prefix) -> prefix
        Error(_) -> <<>>
      }
  }
}

/// Magic bytes only, over `examined_prefix`. Anything unrecognised, or shorter
/// than its signature, is `Unknown`.
pub fn sniff(content: BitArray) -> Sniffed {
  case examined_prefix(content) {
    <<0xFF, 0xD8, 0xFF, _:bits>> -> Jpeg
    <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _:bits>> -> Png
    <<0x47, 0x49, 0x46, 0x38, _:bits>> -> Gif
    <<0x52, 0x49, 0x46, 0x46, _, _, _, _, 0x57, 0x45, 0x42, 0x50, _:bits>> ->
      Webp
    <<0x4F, 0x67, 0x67, 0x53, _:bits>> -> Ogg
    <<0x49, 0x44, 0x33, _:bits>> -> Mp3
    <<0xFF, 0xFB, _:bits>> -> Mp3
    <<0xFF, 0xF3, _:bits>> -> Mp3
    <<0xFF, 0xF2, _:bits>> -> Mp3
    <<_, _, _, _, 0x66, 0x74, 0x79, 0x70, _:bits>> -> Mp4
    <<0x25, 0x50, 0x44, 0x46, 0x2D, _:bits>> -> Pdf
    <<0x50, 0x4B, 0x03, 0x04, _:bits>> -> Zip
    _ -> Unknown
  }
}

/// Allowed container types per declared kind. Gif is allowed nowhere
/// (Telegram animations arrive as MP4); Zip only for Document.
pub fn allowlist(kind: MediaKind) -> List(Sniffed) {
  case kind {
    Photo -> [Jpeg, Png, Webp]
    Sticker -> [Webp, Png]
    Voice -> [Ogg]
    Audio -> [Mp3, Ogg]
    Video -> [Mp4]
    Animation -> [Mp4]
    Document -> [Pdf, Png, Jpeg, Zip]
    Unsupported(_) -> []
  }
}

pub fn inspect(kind: MediaKind, content: BitArray) -> Verdict {
  let sniffed = sniff(content)
  case kind {
    Unsupported(_) -> Rejected("unsupported_kind", sniffed)
    _ ->
      case sniffed {
        Unknown -> Rejected("unknown_content_type", Unknown)
        _ ->
          case list.contains(allowlist(kind), sniffed) {
            True -> Accepted(sniffed)
            False -> Rejected("sniffed_type_not_allowed_for_kind", sniffed)
          }
      }
  }
}

/// Inspect a download outcome. Only `Fetched` carries content; the other
/// outcomes return an Error naming them and are never accepted.
pub fn inspect_fetched(outcome: download.Outcome) -> Result(Verdict, String) {
  case outcome {
    download.Fetched(kind: kind, content: content, ..) ->
      Ok(inspect(kind, content))
    download.Aborted(..) -> Error("download_aborted")
    download.Rejected(reason) ->
      Error("download_rejected:" <> reject_label(reason))
  }
}

fn reject_label(reason: download.RejectReason) -> String {
  string.lowercase(case reason {
    download.UnsupportedKind(_) -> "unsupported_kind"
    download.AlreadyFetched(_) -> "already_fetched"
    download.DeclaredOverCap(..) -> "declared_over_cap"
    download.TokenUnavailable(_) -> "token_unavailable"
    download.GetFileFailed(_) -> "get_file_failed"
    download.StreamOpenFailed(_) -> "stream_open_failed"
    download.StreamReadFailed(_) -> "stream_read_failed"
  })
}

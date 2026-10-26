//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_media_store</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-TELEGRAM-MEDIA-T4, SC-SEC-001, SC-ERGONOMIC-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Media design T4: bounded content-addressed store. One root directory, one
//// `base` subdirectory below it, and for every object two files:
////
////   root/<base>/<first 2 hex of sha256>/<sha256>.bin   the bytes
////   root/<base>/<first 2 hex of sha256>/<sha256>.json  the index record
////
//// Names derive ONLY from the SHA-256 recomputed over the content here. A
//// caption, a file name, a `file_unique_id` or any other sender string never
//// reaches a path; `file_unique_id` is recorded inside the index and nowhere
//// else. Path bounds come from `files.checked_path` (no `..`, no empty or
//// absolute segments, no symlinked parent directory).
////
//// Honest limits:
//// * NO DELETION. Retention is a horizon (`expires_at_ms`) that the caller
////   enforces by listing `expired` and acting on it elsewhere. An expired
////   object is never served by `get`, but its bytes remain on disk.
//// * The ceiling check is pure: the caller supplies `usage_bytes` (measure it
////   with `usage`). Two concurrent callers may both pass the check against the
////   same measurement; the ceiling is a guard, not a quota lock.
//// * An object whose index already exists is reported `AlreadyStored` before
////   the ceiling is consulted, because that call writes nothing new.
//// * `put` is synchronous. The design's `store_write` deadline is a caller
////   concern (run `put` under a supervised, time-bounded process); this module
////   observes no clock of its own and `now_ms` is supplied by the caller.
//// * Parent-directory rename races still need a cooperative workspace lease
////   (same limit as `files`); this is not a descriptor-relative VFS.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_media_ref.{
  type MediaKind, Animation, Audio, Document, Photo, Sticker, Unsupported, Video,
  Voice,
}
import gleam/bit_array
import gleam/crypto
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import uos_swarm/clock_guard

pub const schema = "uos.telegram.media-object.v1"

/// Smallest accepted retention: one minute.
pub const min_retention_ms = 60_000

/// `base` is relative to `root`: no `..`, no leading `/`, no empty segment.
pub type Policy {
  Policy(
    root: String,
    base: String,
    retention_ms: Int,
    total_ceiling_bytes: Int,
  )
}

pub type Stored {
  Stored(
    sha256_hex: String,
    bytes: Int,
    kind: MediaKind,
    file_unique_id: String,
    stored_at_ms: Int,
    expires_at_ms: Int,
  )
}

pub type Outcome {
  Written(Stored)
  /// Same digest already present: idempotent, no second write.
  AlreadyStored(Stored)
  /// Reasons: `ceiling_reached`, `policy_invalid`, `usage_invalid`,
  /// `kind_unsupported`, `content_digest_mismatch`, `write_failed:<reason>`.
  Refused(reason: String)
}

type WriteMode {
  Exclusive
  Binary
  Sync
}

@external(erlang, "file", "write_file")
fn write_file(
  path: String,
  bytes: BitArray,
  modes: List(WriteMode),
) -> dynamic.Dynamic

fn write_exclusive(path: String, bytes: BitArray) -> Result(Nil, String) {
  let raw = write_file(path, bytes, [Exclusive, Binary, Sync])
  case raw == atom.to_dynamic(atom.create("ok")) {
    True -> Ok(Nil)
    False -> {
      let reason = {
        use tag <- decode.field(0, atom.decoder())
        use why <- decode.field(1, atom.decoder())
        decode.success(#(tag, why))
      }
      case decode.run(raw, reason) {
        Ok(#(_, why)) -> Error(atom.to_string(why))
        Error(_) -> Error("write_failed")
      }
    }
  }
}

// ---------------------------------------------------------------- validation

fn valid_policy(policy: Policy) -> Result(Nil, String) {
  case
    policy.retention_ms >= min_retention_ms
    && policy.total_ceiling_bytes >= 1
    && policy.root != ""
    && !string.contains(policy.root, "\u{0}")
  {
    False -> Error("policy_invalid")
    True ->
      case files.relative_path(policy.base) {
        Ok(_) -> Ok(Nil)
        Error(_) -> Error("policy_invalid")
      }
  }
}

fn is_hex_digest(text: String) -> Bool {
  string.length(text) == 64
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

fn sha256_of(content: BitArray) -> String {
  crypto.hash(crypto.Sha256, content)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn rel_dir(policy: Policy, sha: String) -> String {
  policy.base <> "/" <> string.slice(sha, 0, 2)
}

fn rel_bin(policy: Policy, sha: String) -> String {
  rel_dir(policy, sha) <> "/" <> sha <> ".bin"
}

fn rel_index(policy: Policy, sha: String) -> String {
  rel_dir(policy, sha) <> "/" <> sha <> ".json"
}

/// Absolute path of the `.bin` object, bounded through `files.checked_path`.
/// Fails (`parent_unavailable`) while the shard directory does not exist yet.
pub fn object_path(
  policy: Policy,
  sha256_hex: String,
) -> Result(String, String) {
  use _ <- result.try(valid_policy(policy))
  case is_hex_digest(sha256_hex) {
    False -> Error("sha256_invalid")
    True -> files.checked_path(policy.root, rel_bin(policy, sha256_hex))
  }
}

// -------------------------------------------------------------- index record

fn kind_from_label(label: String) -> Result(MediaKind, Nil) {
  case label {
    "photo" -> Ok(Photo)
    "document" -> Ok(Document)
    "audio" -> Ok(Audio)
    "voice" -> Ok(Voice)
    "video" -> Ok(Video)
    "sticker" -> Ok(Sticker)
    "animation" -> Ok(Animation)
    _ ->
      case string.starts_with(label, "unsupported:") {
        True -> Ok(Unsupported(string.drop_start(label, 12)))
        False -> Error(Nil)
      }
  }
}

/// Canonical JSON, fixed key order.
pub fn encode_record(stored: Stored) -> String {
  json.object([
    #("schema", json.string(schema)),
    #("sha256_hex", json.string(stored.sha256_hex)),
    #("bytes", json.int(stored.bytes)),
    #("kind", json.string(telegram_media_ref.kind_label(stored.kind))),
    #("file_unique_id", json.string(stored.file_unique_id)),
    #("stored_at_ms", json.int(stored.stored_at_ms)),
    #("expires_at_ms", json.int(stored.expires_at_ms)),
  ])
  |> json.to_string
}

fn record_decoder() -> decode.Decoder(#(String, Stored)) {
  use s <- decode.field("schema", decode.string)
  use sha <- decode.field("sha256_hex", decode.string)
  use bytes <- decode.field("bytes", decode.int)
  use kind_text <- decode.field("kind", decode.string)
  use unique <- decode.field("file_unique_id", decode.string)
  use stored_at <- decode.field("stored_at_ms", decode.int)
  use expires_at <- decode.field("expires_at_ms", decode.int)
  case kind_from_label(kind_text) {
    Ok(kind) ->
      decode.success(#(
        s,
        Stored(sha, bytes, kind, unique, stored_at, expires_at),
      ))
    Error(_) ->
      decode.failure(
        #(s, Stored(sha, bytes, Photo, unique, stored_at, expires_at)),
        "MediaKind",
      )
  }
}

/// Parse one index record; its digest must equal the name it was read under.
pub fn decode_record(text: String, name_sha: String) -> Result(Stored, String) {
  case json.parse(text, record_decoder()) {
    Ok(#(s, stored)) ->
      case
        s == schema
        && stored.sha256_hex == name_sha
        && is_hex_digest(stored.sha256_hex)
        && stored.bytes >= 0
        && stored.expires_at_ms >= stored.stored_at_ms
      {
        True -> Ok(stored)
        False -> Error("index_invalid")
      }
    Error(_) -> Error("index_invalid")
  }
}

/// Ok(None-equivalent) is expressed as Error("not_found") so callers can tell an
/// absent record from an unreadable or malformed one.
fn load_record(policy: Policy, sha: String) -> Result(Stored, String) {
  case files.checked_path(policy.root, rel_index(policy, sha)) {
    Error(_) -> Error("not_found")
    Ok(path) ->
      case simplifile.is_file(path) {
        Ok(True) ->
          case files.read(policy.root, rel_index(policy, sha)) {
            Ok(text) -> decode_record(text, sha)
            Error(_) -> Error("index_invalid")
          }
        _ -> Error("not_found")
      }
  }
}

// ----------------------------------------------------------------------- put

/// Store `content` under its recomputed SHA-256. `expected_sha256` is only a
/// cross-check against the digest the downloader reported; it never names a
/// file. `usage_bytes` is the caller's measured current usage.
pub fn put(
  policy: Policy,
  kind: MediaKind,
  file_unique_id: String,
  content: BitArray,
  expected_sha256: String,
  now_ms: Int,
  usage_bytes: Int,
) -> Outcome {
  case valid_policy(policy) {
    Error(reason) -> Refused(reason)
    Ok(Nil) ->
      case kind {
        Unsupported(_) -> Refused("kind_unsupported")
        _ ->
          case usage_bytes < 0 {
            True -> Refused("usage_invalid")
            False -> {
              let sha = sha256_of(content)
              case sha == string.lowercase(expected_sha256) {
                False -> Refused("content_digest_mismatch")
                True ->
                  put_verified(
                    policy,
                    Stored(
                      sha256_hex: sha,
                      bytes: bit_array.byte_size(content),
                      kind: kind,
                      file_unique_id: file_unique_id,
                      stored_at_ms: now_ms,
                      expires_at_ms: now_ms + policy.retention_ms,
                    ),
                    content,
                    usage_bytes,
                  )
              }
            }
          }
      }
  }
}

fn put_verified(
  policy: Policy,
  stored: Stored,
  content: BitArray,
  usage_bytes: Int,
) -> Outcome {
  case load_record(policy, stored.sha256_hex) {
    Ok(existing) -> AlreadyStored(existing)
    Error("not_found") ->
      case usage_bytes + stored.bytes > policy.total_ceiling_bytes {
        True -> Refused("ceiling_reached")
        False -> write_object(policy, stored, content)
      }
    Error(reason) -> Refused("write_failed:" <> reason)
  }
}

fn prepare_directory(policy: Policy, sha: String) -> Result(Nil, String) {
  case simplifile.is_directory(policy.root) {
    Ok(True) ->
      simplifile.create_directory_all(
        policy.root <> "/" <> rel_dir(policy, sha),
      )
      |> result.map_error(fn(_) { "directory_unavailable" })
    _ -> Error("root_unavailable")
  }
}

fn write_object(policy: Policy, stored: Stored, content: BitArray) -> Outcome {
  let sha = stored.sha256_hex
  let written = {
    use _ <- result.try(prepare_directory(policy, sha))
    use bin_path <- result.try(files.checked_path(
      policy.root,
      rel_bin(policy, sha),
    ))
    use _ <- result.try(case write_exclusive(bin_path, content) {
      Ok(Nil) -> Ok(Nil)
      Error("eexist") -> adopt_orphan(bin_path, sha, stored.bytes)
      Error(reason) -> Error(reason)
    })
    use _ <- result.try(clock_guard.verify_durable_directory(
      policy.root <> "/" <> rel_dir(policy, sha),
    ))
    Ok(Nil)
  }
  case written {
    Error(reason) -> Refused("write_failed:" <> reason)
    Ok(Nil) ->
      case
        files.create(policy.root, rel_index(policy, sha), encode_record(stored))
      {
        Ok(Nil) -> Written(stored)
        Error(created) ->
          // A concurrent put may have won the index; replay its record.
          case load_record(policy, sha) {
            Ok(existing) -> AlreadyStored(existing)
            Error(_) -> Refused("write_failed:index:" <> created)
          }
      }
  }
}

/// A `.bin` without an index is the residue of an interrupted put. It is
/// adopted only if its bytes already hash to its own name.
fn adopt_orphan(path: String, sha: String, bytes: Int) -> Result(Nil, String) {
  case simplifile.read_bits(path) {
    Ok(existing) ->
      case
        bit_array.byte_size(existing) == bytes && sha256_of(existing) == sha
      {
        True -> Ok(Nil)
        False -> Error("orphan_object_mismatch")
      }
    Error(_) -> Error("orphan_object_unreadable")
  }
}

// ----------------------------------------------------------------------- get

/// Serve an object. Expired objects are reported `expired` and never served;
/// bytes whose digest no longer equals the name are `content_tampered`.
pub fn get(
  policy: Policy,
  sha256_hex: String,
  now_ms: Int,
) -> Result(#(Stored, BitArray), String) {
  use _ <- result.try(valid_policy(policy))
  use _ <- result.try(case is_hex_digest(sha256_hex) {
    True -> Ok(Nil)
    False -> Error("sha256_invalid")
  })
  use stored <- result.try(load_record(policy, sha256_hex))
  use _ <- result.try(case now_ms >= stored.expires_at_ms {
    True -> Error("expired")
    False -> Ok(Nil)
  })
  use path <- result.try(
    files.checked_path(policy.root, rel_bin(policy, sha256_hex))
    |> result.map_error(fn(_) { "content_missing" }),
  )
  use info <- result.try(
    simplifile.link_info(path) |> result.map_error(fn(_) { "content_missing" }),
  )
  use _ <- result.try(
    case
      simplifile.file_info_type(info) == simplifile.File
      && info.nlinks == 1
      && info.size == stored.bytes
    {
      True -> Ok(Nil)
      False -> Error("content_tampered")
    },
  )
  use content <- result.try(
    simplifile.read_bits(path) |> result.map_error(fn(_) { "content_missing" }),
  )
  case
    bit_array.byte_size(content) == stored.bytes
    && sha256_of(content) == sha256_hex
  {
    True -> Ok(#(stored, content))
    False -> Error("content_tampered")
  }
}

// ------------------------------------------------------------------- listing

fn all_records(policy: Policy) -> Result(List(Result(Stored, String)), String) {
  use _ <- result.try(valid_policy(policy))
  let base_dir = policy.root <> "/" <> policy.base
  case simplifile.read_directory(base_dir) {
    Error(simplifile.Enoent) -> Ok([])
    Error(_) -> Error("store_unavailable")
    Ok(shards) -> {
      let names =
        shards
        |> list.sort(string.compare)
        |> list.filter(fn(s) { string.length(s) == 2 })
        |> list.flat_map(fn(shard) {
          case simplifile.read_directory(base_dir <> "/" <> shard) {
            Ok(entries) ->
              entries
              |> list.sort(string.compare)
              |> list.filter_map(fn(entry) {
                case string.ends_with(entry, ".json") {
                  True -> {
                    let sha = string.drop_end(entry, 5)
                    case is_hex_digest(sha) && string.starts_with(sha, shard) {
                      True -> Ok(sha)
                      False -> Error(Nil)
                    }
                  }
                  False -> Error(Nil)
                }
              })
            Error(_) -> []
          }
        })
      Ok(list.map(names, fn(sha) { load_record(policy, sha) }))
    }
  }
}

/// Index records whose horizon has passed (`now_ms >= expires_at_ms`), oldest
/// shard order. Read-only: nothing is deleted. Malformed records are skipped.
pub fn expired(policy: Policy, now_ms: Int) -> List(Stored) {
  case all_records(policy) {
    Error(_) -> []
    Ok(records) ->
      list.filter_map(records, fn(r) {
        case r {
          Ok(stored) ->
            case now_ms >= stored.expires_at_ms {
              True -> Ok(stored)
              False -> Error(Nil)
            }
          Error(_) -> Error(Nil)
        }
      })
  }
}

/// Sum of index-recorded bytes under `base`. An absent store is zero. A
/// malformed record fails closed: an unreadable index must not under-count.
pub fn usage(policy: Policy) -> Result(Int, String) {
  use records <- result.try(all_records(policy))
  list.try_fold(records, 0, fn(total, r) {
    case r {
      Ok(stored) -> Ok(total + stored.bytes)
      Error(reason) -> Error(reason)
    }
  })
}

/// Test and diagnostics helper: decimal text of a byte count.
pub fn bytes_label(n: Int) -> String {
  int.to_string(n) <> "B"
}

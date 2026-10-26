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
//// * Deletion exists and is bounded. `delete` removes one named object (index
////   first, then the `.bin`; symlinks and hard links are refused untouched).
////   `reclaim_expired` deletes at most N expired objects per call and reports
////   what it removed and refused. Retention is enforced only when a caller runs
////   `reclaim_expired` on a schedule: until then an expired object is never
////   served by `get`, but its bytes remain on disk and still count toward the
////   ceiling. Neither function deletes a `.tmp-` file or anything outside
////   `root/base`, and bytes that no longer hash to their name are garbage that
////   `delete` removes like any other. Deletion is not wiped or shredded: it is
////   an unlink.
//// * The ceiling check is pure: the caller supplies `usage_bytes` (measure it
////   with `usage`). Two concurrent callers may both pass the check against the
////   same measurement; the ceiling is a guard, not a quota lock.
//// * An object whose index already exists is reported `AlreadyStored` before
////   the ceiling is consulted, because that call writes nothing new.
//// * `put` is synchronous. The design's `store_write` deadline is a caller
////   concern (run `put` under a supervised, time-bounded process); this module
////   observes no clock of its own and `now_ms` is supplied by the caller.
//// * Bytes are written to a unique `.tmp-<random>` file in the shard, synced and
////   renamed onto `<sha>.bin`, so the digest name never holds partial bytes.
////   A failed attempt deletes only its own temporary file. A truncated or
////   wrong-content regular file already at the digest name is replaced the
////   same way; a symlink or hard link there is refused and never read.
//// * An existing index whose horizon has passed makes `put` return
////   `Refused("expired_present")`, not `AlreadyStored`: the caller disposes of
////   `expired` objects first. An existing, unexpired index is `AlreadyStored`
////   only after its `.bin` is re-checked (regular, single link, size, hash);
////   otherwise `Refused("stored_object_unverified:<reason>")`.
//// * `usage` counts per digest the larger of the index bytes and the `.bin`
////   size, orphan `.bin` files and leftover `.tmp-` files included.
//// * `put` takes no media-inspection verdict: running `telegram_media_inspect`
////   before `put` is a caller convention, not something this module enforces.
//// * Index fields other than the digest (kind, `file_unique_id`, timestamps,
////   horizon) are unauthenticated: anyone who can write the store directory can
////   alter them. Only the byte content is bound to its name by the hash.
//// * A put interrupted while writing the index leaves a truncated index that
////   reads as `index_invalid` and is not auto-repaired (known residual).
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
  /// `kind_unsupported`, `file_unique_id_too_long`, `content_digest_mismatch`,
  /// `expired_present`, `stored_object_unverified:<reason>`,
  /// `write_failed:<reason>`.
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

/// Largest accepted `file_unique_id`. It is only recorded in the index, so the
/// bound keeps the index record far below `files.max_bytes`.
pub const max_unique_id_bytes = 128

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
          case
            usage_bytes < 0,
            string.byte_size(file_unique_id) > max_unique_id_bytes
          {
            True, _ -> Refused("usage_invalid")
            _, True -> Refused("file_unique_id_too_long")
            False, False -> {
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
    Ok(existing) ->
      case stored.stored_at_ms >= existing.expires_at_ms {
        // The horizon has passed: the caller must act on `expired` first.
        True -> Refused("expired_present")
        False ->
          case verify_stored(policy, existing) {
            Ok(Nil) -> AlreadyStored(existing)
            Error(reason) -> Refused("stored_object_unverified:" <> reason)
          }
      }
    Error("not_found") ->
      case usage_bytes + stored.bytes > policy.total_ceiling_bytes {
        True -> Refused("ceiling_reached")
        False -> write_object(policy, stored, content)
      }
    Error(reason) -> Refused("write_failed:" <> reason)
  }
}

/// Bytes of an already-indexed object must still be there and still hash to
/// their name before `put` may call the object stored.
fn verify_stored(policy: Policy, existing: Stored) -> Result(Nil, String) {
  use path <- result.try(
    files.checked_path(policy.root, rel_bin(policy, existing.sha256_hex))
    |> result.map_error(fn(_) { "bin_missing" }),
  )
  verify_bin(path, existing.sha256_hex, existing.bytes)
}

/// `link_info` first (regular file, single link, exact size: a symlink or a
/// huge file is never read), then a full re-hash.
fn verify_bin(path: String, sha: String, bytes: Int) -> Result(Nil, String) {
  case simplifile.link_info(path) {
    Error(simplifile.Enoent) -> Error("bin_missing")
    Error(_) -> Error("bin_unreadable")
    Ok(info) ->
      case
        simplifile.file_info_type(info) == simplifile.File && info.nlinks == 1
      {
        False -> Error("bin_not_regular_single_link")
        True ->
          case info.size == bytes {
            False -> Error("bin_size_mismatch")
            True ->
              case simplifile.read_bits(path) {
                Error(_) -> Error("bin_unreadable")
                Ok(existing) ->
                  case
                    bit_array.byte_size(existing) == bytes
                    && sha256_of(existing) == sha
                  {
                    True -> Ok(Nil)
                    False -> Error("bin_hash_mismatch")
                  }
              }
          }
      }
  }
}

/// Create every missing directory one level at a time, refusing any existing
/// ancestor that is not a plain directory (a symlink is never followed and
/// nothing is created through it).
fn prepare_directory(policy: Policy, sha: String) -> Result(Nil, String) {
  case simplifile.is_directory(policy.root) {
    Ok(True) -> {
      use parts <- result.try(files.relative_path(rel_dir(policy, sha)))
      walk_directories(policy.root, parts)
    }
    _ -> Error("root_unavailable")
  }
}

fn walk_directories(dir: String, parts: List(String)) -> Result(Nil, String) {
  case parts {
    [] -> Ok(Nil)
    [part, ..rest] -> {
      let next = dir <> "/" <> part
      case plain_directory(next) {
        Ok(True) -> walk_directories(next, rest)
        Ok(False) ->
          case simplifile.create_directory(next) {
            Ok(Nil) -> walk_directories(next, rest)
            // lost a creation race: the winner's directory must still be plain
            Error(simplifile.Eexist) ->
              case plain_directory(next) {
                Ok(True) -> walk_directories(next, rest)
                _ -> Error("parent_not_regular_directory")
              }
            Error(_) -> Error("directory_unavailable")
          }
        Error(reason) -> Error(reason)
      }
    }
  }
}

/// Ok(True) plain directory, Ok(False) absent, Error otherwise.
fn plain_directory(path: String) -> Result(Bool, String) {
  case simplifile.link_info(path) {
    Ok(info) ->
      case simplifile.file_info_type(info) == simplifile.Directory {
        True -> Ok(True)
        False -> Error("parent_not_regular_directory")
      }
    Error(simplifile.Enoent) -> Ok(False)
    Error(_) -> Error("directory_unavailable")
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
    use _ <- result.try(ensure_bin(policy, sha, content, bin_path))
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

/// Leave a complete `.bin` under the digest name. An existing file that hashes
/// to its own name is adopted. A regular single-link file of the wrong size or
/// hash is the residue of an interrupted write: it is replaced by renaming a
/// fully written, synced temporary file over it. Anything that is not a plain
/// file (symlink, hard link) is refused and never read or replaced.
fn ensure_bin(
  policy: Policy,
  sha: String,
  content: BitArray,
  bin_path: String,
) -> Result(Nil, String) {
  case simplifile.link_info(bin_path) {
    Error(simplifile.Enoent) -> write_bin(policy, sha, content, bin_path)
    Error(_) -> Error("bin_unreadable")
    Ok(_) ->
      case verify_bin(bin_path, sha, bit_array.byte_size(content)) {
        Ok(Nil) -> Ok(Nil)
        Error("bin_size_mismatch") | Error("bin_hash_mismatch") ->
          write_bin(policy, sha, content, bin_path)
        Error(reason) -> Error(reason)
      }
  }
}

/// Write to a unique temporary name in the shard, sync, then rename onto the
/// final name, so the digest name is only ever bound to complete bytes. A
/// failed attempt removes its own temporary file (never an object).
fn write_bin(
  policy: Policy,
  sha: String,
  content: BitArray,
  bin_path: String,
) -> Result(Nil, String) {
  let nonce =
    crypto.strong_random_bytes(8) |> bit_array.base16_encode |> string.lowercase
  let tmp_rel = rel_dir(policy, sha) <> "/.tmp-" <> nonce
  use tmp_path <- result.try(files.checked_path(policy.root, tmp_rel))
  case write_exclusive(tmp_path, content) {
    Error(reason) -> {
      let _ = simplifile.delete(tmp_path)
      Error(reason)
    }
    Ok(Nil) ->
      case simplifile.rename(tmp_path, bin_path) {
        Ok(Nil) -> Ok(Nil)
        Error(_) -> {
          let _ = simplifile.delete(tmp_path)
          Error("rename_failed")
        }
      }
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

/// One digest found on disk: its index record (or why there is none) and the
/// size of its `.bin` (0 when absent).
type Entry {
  Entry(sha: String, record: Result(Stored, String), bin_bytes: Int)
}

fn is_shard(name: String) -> Bool {
  string.length(name) == 2
  && list.all(string.to_graphemes(name), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

fn digest_of(entry: String, shard: String) -> Result(String, Nil) {
  let sha = case string.ends_with(entry, ".json") {
    True -> string.drop_end(entry, 5)
    False ->
      case string.ends_with(entry, ".bin") {
        True -> string.drop_end(entry, 4)
        False -> ""
      }
  }
  case is_hex_digest(sha) && string.starts_with(sha, shard) {
    True -> Ok(sha)
    False -> Error(Nil)
  }
}

fn size_of(path: String) -> Result(Int, String) {
  case simplifile.link_info(path) {
    Ok(info) -> Ok(info.size)
    Error(simplifile.Enoent) -> Ok(0)
    Error(_) -> Error("store_unavailable")
  }
}

/// Every digest under `base`, whether it has an index, a `.bin` or both, plus
/// the bytes held by leftover `.tmp-` files. Any unreadable directory fails the
/// scan: a listing that cannot see part of the store must not look complete.
fn scan(policy: Policy) -> Result(#(List(Entry), Int), String) {
  use _ <- result.try(valid_policy(policy))
  let base_dir = policy.root <> "/" <> policy.base
  case simplifile.read_directory(base_dir) {
    Error(simplifile.Enoent) -> Ok(#([], 0))
    Error(_) -> Error("store_unavailable")
    Ok(names) ->
      names
      |> list.filter(is_shard)
      |> list.sort(string.compare)
      |> list.try_fold(#([], 0), fn(acc, shard) {
        let dir = base_dir <> "/" <> shard
        use entries <- result.try(
          simplifile.read_directory(dir)
          |> result.map_error(fn(_) { "store_unavailable" }),
        )
        let shas =
          entries
          |> list.filter_map(fn(e) { digest_of(e, shard) })
          |> list.unique
          |> list.sort(string.compare)
        use found <- result.try(
          list.try_map(shas, fn(sha) {
            use bin_bytes <- result.try(size_of(dir <> "/" <> sha <> ".bin"))
            Ok(Entry(sha, load_record(policy, sha), bin_bytes))
          }),
        )
        use tmp_bytes <- result.try(
          entries
          |> list.filter(fn(e) { string.starts_with(e, ".tmp-") })
          |> list.try_fold(0, fn(total, e) {
            use size <- result.try(size_of(dir <> "/" <> e))
            Ok(total + size)
          }),
        )
        Ok(#(list.append(acc.0, found), acc.1 + tmp_bytes))
      })
  }
}

/// Index records whose horizon has passed (`now_ms >= expires_at_ms`), in
/// digest order. Read-only: nothing is deleted. A malformed record or an
/// unreadable store is an error, never an empty list. A `.bin` with no index
/// has no horizon and is not listed (`usage` still counts it).
pub fn expired(policy: Policy, now_ms: Int) -> Result(List(Stored), String) {
  use #(entries, _) <- result.try(scan(policy))
  list.try_fold(entries, [], fn(acc, entry) {
    case entry.record {
      Ok(stored) ->
        case now_ms >= stored.expires_at_ms {
          True -> Ok(list.append(acc, [stored]))
          False -> Ok(acc)
        }
      Error("not_found") -> Ok(acc)
      Error(reason) -> Error(reason)
    }
  })
}

/// Bytes held under `base`: per digest the larger of the index-recorded bytes
/// and the `.bin` size, orphan `.bin` files (no index) and leftover `.tmp-`
/// files included. An absent store is zero. A malformed record or an
/// unreadable directory fails closed: usage must not under-count.
pub fn usage(policy: Policy) -> Result(Int, String) {
  use #(entries, tmp_bytes) <- result.try(scan(policy))
  list.try_fold(entries, tmp_bytes, fn(total, entry) {
    case entry.record {
      Ok(stored) -> Ok(total + int.max(stored.bytes, entry.bin_bytes))
      Error("not_found") -> Ok(total + entry.bin_bytes)
      Error(reason) -> Error(reason)
    }
  })
}

/// Test and diagnostics helper: decimal text of a byte count.
pub fn bytes_label(n: Int) -> String {
  int.to_string(n) <> "B"
}

// ------------------------------------------------------------------- delete

/// What `delete` removed. `bytes_freed` is what `usage` stopped counting for
/// this digest: the larger of the index-recorded bytes and the `.bin` size
/// (the `.bin` size alone when the index is unreadable).
pub type Removed {
  Removed(
    sha256_hex: String,
    bytes_freed: Int,
    removed_bin: Bool,
    removed_index: Bool,
  )
}

type Half {
  Absent
  Present(size: Int)
}

/// A half must be absent, or a regular file with a single link. A symlink or a
/// hard link is refused untouched.
fn probe_half(path: String) -> Result(Half, String) {
  case simplifile.link_info(path) {
    Error(simplifile.Enoent) -> Ok(Absent)
    Error(_) -> Error("store_unavailable")
    Ok(info) ->
      case
        simplifile.file_info_type(info) == simplifile.File && info.nlinks == 1
      {
        True -> Ok(Present(info.size))
        False -> Error("not_regular_single_link")
      }
  }
}

/// Resolve a path through `files.checked_path`. A shard that does not exist
/// means the half is absent; any other refusal (a symlinked ancestor) stays a
/// refusal.
fn resolve_half(
  policy: Policy,
  relative: String,
) -> Result(Result(String, Nil), String) {
  case files.checked_path(policy.root, relative) {
    Ok(path) -> Ok(Ok(path))
    Error("parent_unavailable") -> Ok(Error(Nil))
    Error(reason) -> Error(reason)
  }
}

fn probe(policy: Policy, relative: String) -> Result(#(String, Half), String) {
  use resolved <- result.try(resolve_half(policy, relative))
  case resolved {
    Error(Nil) -> Ok(#("", Absent))
    Ok(path) -> {
      use half <- result.try(probe_half(path))
      Ok(#(path, half))
    }
  }
}

/// Remove one object from disk. Both halves are checked (`checked_path`, then
/// `link_info`: regular file, single link) BEFORE either is touched, so a
/// symlink or hard link refuses the whole delete and nothing changes. The index
/// is removed first and the shard directory synced, then the `.bin`: a crash
/// in between leaves an orphan `.bin` (counted by `usage`, adopted or replaced
/// by a later `put`), never an index that points at nothing. An object with
/// only one half present has that half removed and `Removed` says which.
/// Bytes that no longer hash to their name are garbage; deleting them is still
/// a deletion. `delete` does not look at expiry: it is the caller's decision,
/// and `reclaim_expired` is the expiry-checked wrapper. It never touches a
/// `.tmp-` file or anything outside `root/base`.
pub fn delete(policy: Policy, sha256_hex: String) -> Result(Removed, String) {
  use _ <- result.try(valid_policy(policy))
  use _ <- result.try(case is_hex_digest(sha256_hex) {
    True -> Ok(Nil)
    False -> Error("sha256_invalid")
  })
  use #(index_path, index_half) <- result.try(probe(
    policy,
    rel_index(policy, sha256_hex),
  ))
  use #(bin_path, bin_half) <- result.try(probe(
    policy,
    rel_bin(policy, sha256_hex),
  ))
  case index_half, bin_half {
    Absent, Absent -> Error("not_found")
    _, _ -> {
      let recorded = case index_half {
        Present(_) ->
          case load_record(policy, sha256_hex) {
            Ok(stored) -> stored.bytes
            Error(_) -> 0
          }
        Absent -> 0
      }
      let bin_size = case bin_half {
        Present(size) -> size
        Absent -> 0
      }
      use removed_index <- result.try(case index_half {
        Present(_) ->
          simplifile.delete(index_path)
          |> result.map(fn(_) { True })
          |> result.map_error(fn(_) { "delete_failed:index" })
        Absent -> Ok(False)
      })
      use _ <- result.try(case removed_index {
        True ->
          clock_guard.verify_durable_directory(
            policy.root <> "/" <> rel_dir(policy, sha256_hex),
          )
          |> result.map_error(fn(_) { "delete_failed:sync" })
        False -> Ok(Nil)
      })
      use removed_bin <- result.try(case bin_half {
        Present(_) ->
          simplifile.delete(bin_path)
          |> result.map(fn(_) { True })
          |> result.map_error(fn(_) { "delete_failed:bin" })
        Absent -> Ok(False)
      })
      Ok(Removed(
        sha256_hex: sha256_hex,
        bytes_freed: int.max(recorded, bin_size),
        removed_bin: removed_bin,
        removed_index: removed_index,
      ))
    }
  }
}

// ------------------------------------------------------------------ reclaim

/// `examined` objects were attempted (at most `max_objects`); `removed` lists
/// what was deleted; `refused` holds `#(sha, reason)` for every object that
/// could not be deleted or whose index is unreadable; `truncated` is True when
/// more expired objects remain beyond the bound.
pub type ReclaimReceipt {
  ReclaimReceipt(
    examined: Int,
    removed: List(Removed),
    refused: List(#(String, String)),
    bytes_freed: Int,
    truncated: Bool,
  )
}

/// Delete at most `max_objects` expired objects (`now_ms >= expires_at_ms`), in
/// digest order. An unexpired object is never deleted: expiry is re-read from
/// the index immediately before each delete. A refusal (symlinked half, failed
/// removal) is collected and the run continues. A malformed index is reported
/// in `refused` as `index_invalid`, does not count toward `max_objects` and is
/// left alone (its expiry is unknown; remove it with an explicit `delete`).
/// Retention enforcement is this function run by a caller on a schedule; the
/// ceiling keeps counting an expired object's bytes until it has run.
pub fn reclaim_expired(
  policy: Policy,
  now_ms: Int,
  max_objects: Int,
) -> Result(ReclaimReceipt, String) {
  case max_objects < 1 {
    True -> Error("bound_invalid")
    False -> {
      use #(entries, _) <- result.try(scan(policy))
      let #(candidates, malformed) =
        list.fold(entries, #([], []), fn(acc, entry) {
          case entry.record {
            Ok(stored) ->
              case now_ms >= stored.expires_at_ms {
                True -> #(list.append(acc.0, [stored]), acc.1)
                False -> acc
              }
            Error("not_found") -> acc
            Error(reason) -> #(
              acc.0,
              list.append(acc.1, [#(entry.sha, reason)]),
            )
          }
        })
      let batch = list.take(candidates, max_objects)
      let #(removed, refused) =
        list.fold(batch, #([], malformed), fn(acc, stored) {
          let sha = stored.sha256_hex
          case load_record(policy, sha) {
            Ok(now_stored) if now_ms >= now_stored.expires_at_ms ->
              case delete(policy, sha) {
                Ok(gone) -> #(list.append(acc.0, [gone]), acc.1)
                Error(reason) -> #(acc.0, list.append(acc.1, [#(sha, reason)]))
              }
            _ -> #(acc.0, list.append(acc.1, [#(sha, "no_longer_expired")]))
          }
        })
      Ok(ReclaimReceipt(
        examined: list.length(batch),
        removed: removed,
        refused: refused,
        bytes_freed: list.fold(removed, 0, fn(total, r) {
          total + r.bytes_freed
        }),
        truncated: list.length(candidates) > max_objects,
      ))
    }
  }
}

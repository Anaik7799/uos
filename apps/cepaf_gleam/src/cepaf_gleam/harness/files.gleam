//// Bounded development file primitives. Path checks + open-descriptor identity
//// prevent reading a substituted final target. Parent rename races still require
//// a cooperative workspace lease; this is not a descriptor-relative VFS.

import gleam/bit_array
import gleam/crypto
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import uos_swarm/clock_guard

pub const max_bytes = 262_144

pub type Device

type Mode {
  Read
  Write
  Binary
  Raw
  Exclusive
  Sync
}

@external(erlang, "file", "open")
fn open(path: String, modes: List(Mode)) -> Result(Device, atom.Atom)

@external(erlang, "file", "close")
fn close(device: Device) -> dynamic.Dynamic

@external(erlang, "file", "pread")
fn pread(device: Device, position: Int, length: Int) -> dynamic.Dynamic

@external(erlang, "file", "read")
fn stream_read(device: Device, length: Int) -> dynamic.Dynamic

@external(erlang, "file", "write")
fn write(device: Device, bytes: BitArray) -> dynamic.Dynamic

@external(erlang, "file", "sync")
fn sync(device: Device) -> dynamic.Dynamic

@external(erlang, "simplifile_erl", "file_info")
fn descriptor_info(
  device: Device,
) -> Result(simplifile.FileInfo, simplifile.FileError)

pub fn stdin() -> Result(Device, String) {
  open("/dev/stdin", [Read, Binary, Raw])
  |> result.map_error(fn(_) { "stdin_unavailable" })
}

pub fn next_byte(device: Device) -> Result(Option(BitArray), String) {
  let raw = stream_read(device, 1)
  case raw == atom.to_dynamic(atom.create("eof")) {
    True -> Ok(None)
    False -> {
      let decoder = {
        use tag <- decode.field(0, atom.decoder())
        use bytes <- decode.field(1, decode.bit_array)
        decode.success(#(tag, bytes))
      }
      case decode.run(raw, decoder) {
        Ok(#(tag, bytes)) ->
          case atom.to_string(tag) == "ok" && bit_array.byte_size(bytes) == 1 {
            True -> Ok(Some(bytes))
            False -> Error("stdin_read_failed")
          }
        Error(_) -> Error("stdin_read_failed")
      }
    }
  }
}

pub fn digest(text: String) -> String {
  text
  |> bit_array.from_string
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn relative_path(path: String) -> Result(List(String), String) {
  let parts = string.split(path, "/")
  case
    string.byte_size(path) > 0
    && string.byte_size(path) <= 512
    && !string.contains(path, "\u{0}")
    && !string.contains(path, "\\")
    && list.all(parts, fn(p) { p != "" && p != "." && p != ".." })
  {
    True -> Ok(parts)
    False -> Error("relative_path_required")
  }
}

fn ancestors(root: String, parts: List(String)) -> Result(Nil, String) {
  case parts {
    [] -> Ok(Nil)
    [_] -> Ok(Nil)
    [part, ..rest] -> {
      let next = root <> "/" <> part
      case simplifile.link_info(next) {
        Ok(info) ->
          case simplifile.file_info_type(info) {
            simplifile.Directory -> ancestors(next, rest)
            _ -> Error("parent_not_regular_directory")
          }
        Error(_) -> Error("parent_unavailable")
      }
    }
  }
}

pub fn checked_path(root: String, relative: String) -> Result(String, String) {
  use parts <- result.try(relative_path(relative))
  use _ <- result.try(ancestors(root, parts))
  Ok(root <> "/" <> relative)
}

pub fn read(root: String, relative: String) -> Result(String, String) {
  use path <- result.try(checked_path(root, relative))
  use before <- result.try(
    simplifile.link_info(path) |> result.map_error(fn(_) { "file_unavailable" }),
  )
  case
    simplifile.file_info_type(before) == simplifile.File
    && before.nlinks == 1
    && before.size <= max_bytes
  {
    False -> Error("regular_single_link_file_bound")
    True -> {
      use fd <- result.try(
        open(path, [Read, Binary, Raw])
        |> result.map_error(fn(_) { "file_open_failed" }),
      )
      let outcome = case descriptor_info(fd) {
        Ok(actual)
          if actual.inode == before.inode
          && actual.dev == before.dev
          && actual.size <= max_bytes
        -> {
          let raw = pread(fd, 0, max_bytes + 1)
          case raw == atom.to_dynamic(atom.create("eof")) {
            True -> Ok("")
            False -> {
              let decoder = {
                use tag <- decode.field(0, atom.decoder())
                use bytes <- decode.field(1, decode.bit_array)
                decode.success(#(tag, bytes))
              }
              case decode.run(raw, decoder) {
                Ok(#(tag, bytes)) ->
                  case
                    atom.to_string(tag) == "ok"
                    && bit_array.byte_size(bytes) <= max_bytes
                  {
                    True ->
                      bit_array.to_string(bytes)
                      |> result.map_error(fn(_) { "invalid_utf8" })
                    False -> Error("read_bound")
                  }
                Error(_) -> Error("file_read_failed")
              }
            }
          }
        }
        _ -> Error("file_changed_before_read")
      }
      let _ = close(fd)
      outcome
    }
  }
}

fn status(raw: dynamic.Dynamic) -> Result(Nil, String) {
  case raw == atom.to_dynamic(atom.create("ok")) {
    True -> Ok(Nil)
    False -> Error("file_write_or_sync_failed")
  }
}

/// No overwrite. Used for proposal artifacts and durable receipts.
pub fn create(
  root: String,
  relative: String,
  content: String,
) -> Result(Nil, String) {
  use path <- result.try(checked_path(root, relative))
  case string.byte_size(content) <= max_bytes {
    False -> Error("content_bound")
    True -> {
      use fd <- result.try(
        open(path, [Write, Binary, Raw, Exclusive, Sync])
        |> result.map_error(fn(_) { "exclusive_create_failed" }),
      )
      let outcome = {
        use _ <- result.try(status(write(fd, bit_array.from_string(content))))
        status(sync(fd))
      }
      let _ = close(fd)
      use _ <- result.try(outcome)
      sync_parent(path)
    }
  }
}

fn sync_parent(path: String) -> Result(Nil, String) {
  let parent =
    path
    |> string.split("/")
    |> list.reverse
    |> list.drop(1)
    |> list.reverse
    |> string.join("/")
  clock_guard.verify_durable_directory(parent)
}

/// Cooperative CAS: both bytes and path are checked again before atomic rename.
/// Does not claim cross-process atomic compare-and-swap against an uncooperative
/// writer. Source ownership is an additional required fence.
pub fn replace(
  root: String,
  relative: String,
  expected: String,
  content: String,
) -> Result(Nil, String) {
  use current <- result.try(read(root, relative))
  case digest(current) == expected {
    False -> Error("source_digest_conflict")
    True -> {
      let nonce = crypto.strong_random_bytes(16) |> bit_array.base16_encode
      let pending = relative <> ".harness-" <> nonce
      use _ <- result.try(create(root, pending, content))
      let outcome = {
        use second <- result.try(read(root, relative))
        case digest(second) == expected {
          False -> Error("source_digest_conflict")
          True -> {
            use path <- result.try(checked_path(root, relative))
            use _ <- result.try(
              simplifile.rename(root <> "/" <> pending, path)
              |> result.map_error(fn(_) { "rename_failed" }),
            )
            sync_parent(path)
          }
        }
      }
      case outcome {
        Ok(_) -> Ok(Nil)
        Error(reason) -> {
          let _ = simplifile.delete(root <> "/" <> pending)
          Error(reason)
        }
      }
    }
  }
}

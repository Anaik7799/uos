//// Bounded transient markdown prefetch, executed outside the gateway mailbox.
//// Directory metadata inspection is bounded; OTP list_dir materializes names.
//// Descriptor identity guards cover final-target substitution. A cooperative
//// source lease is still required for ancestor-rename/content-writer races.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/adapters/knowledge
import cepaf_gleam/ui/lustre/live_corpus
import gleam/int
import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

pub const max_entries = 64

pub const max_total_bytes = 4_194_304

pub const max_file_bytes = 1_048_576

pub const max_directory_entries = 512

pub const max_directory_depth = 4

const seed_paths = ["AGENTS.md", "CLAUDE.md", "GEMINI.md"]

const roots = ["docs/zk", "docs/wiki"]

type Budget {
  Budget(
    entries: List(knowledge.CorpusEntry),
    count: Int,
    bytes: Int,
    inspected: Int,
  )
}

type Device

type FileMode {
  Read
  Binary
  Raw
}

@external(erlang, "file", "open")
fn open(path: String, modes: List(FileMode)) -> Result(Device, atom.Atom)

@external(erlang, "file", "close")
fn close(fd: Device) -> dynamic.Dynamic

@external(erlang, "file", "pread")
fn pread(fd: Device, offset: Int, count: Int) -> dynamic.Dynamic

@external(erlang, "simplifile_erl", "file_info")
fn descriptor_info(
  fd: Device,
) -> Result(simplifile.FileInfo, simplifile.FileError)

@external(erlang, "simplifile_erl", "read_directory")
fn directory_names(path: String) -> dynamic.Dynamic

/// The result includes each safe seed before matching discovered documents.
/// No result is retained globally. Invalid roots or path-like escape queries
/// fail closed; unavailable individual documents are omitted without invention.
pub fn prefetch(root: String, query: String) -> List(knowledge.CorpusEntry) {
  case valid_root(root) && valid_query(root, query) {
    False -> []
    True -> {
      let seeded =
        list.fold(seed_paths, Budget([], 0, 0, 0), fn(state, path) {
          add(state, read_document(root, path))
        })
      let relative_query = case string.starts_with(query, root <> "/") {
        True -> string.drop_start(query, string.length(root) + 1)
        False -> query
      }
      let exact = case allowed_document_path(relative_query) {
        True -> read_document(root, relative_query)
        False -> None
      }
      case exact {
        Some(_) -> list.reverse(add(seeded, exact).entries)
        None -> {
          let completed =
            list.fold(roots, seeded, fn(state, path) {
              walk(root, path, 0, query, state)
            })
          list.reverse(completed.entries)
        }
      }
    }
  }
}

fn valid_root(root: String) -> Bool {
  case
    string.starts_with(root, "/")
    && string.byte_size(root) <= 512
    && !string.contains(root, "\u{0000}")
    && !string.contains(root, "\\")
  {
    False -> False
    True ->
      case string.split(root, "/") {
        ["", ..parts] -> parts != [] && root_components("", parts)
        _ -> False
      }
  }
}

fn root_components(parent: String, parts: List(String)) -> Bool {
  case parts {
    [] -> True
    [part, ..rest] ->
      case part == "" || part == "." || part == ".." {
        True -> False
        False -> {
          let path = parent <> "/" <> part
          case simplifile.link_info(path) {
            Ok(info) ->
              simplifile.file_info_type(info) == simplifile.Directory
              && root_components(path, rest)
            Error(_) -> False
          }
        }
      }
  }
}

fn valid_query(root: String, query: String) -> Bool {
  string.byte_size(query) <= 512
  && !string.contains(query, "\u{0000}")
  && !string.contains(query, "\\")
  && !list.contains(string.split(query, "/"), "..")
  && {
    !string.starts_with(query, "/") || string.starts_with(query, root <> "/")
  }
}

fn markdown(path: String) -> Bool {
  let lowered = string.lowercase(path)
  string.ends_with(lowered, ".md") || string.ends_with(lowered, ".markdown")
}

fn allowed_document_path(relative: String) -> Bool {
  markdown(relative)
  && {
    list.contains(seed_paths, relative)
    || list.any(roots, fn(root) { string.starts_with(relative, root <> "/") })
  }
}

fn room(state: Budget) -> Bool {
  state.count < max_entries
  && state.bytes < max_total_bytes
  && state.inspected < max_directory_entries
}

fn add(state: Budget, entry: Option(knowledge.CorpusEntry)) -> Budget {
  case entry {
    None -> state
    Some(entry) -> {
      let size = string.byte_size(entry.content)
      case
        state.count < max_entries
        && state.bytes + size <= max_total_bytes
        && !list.any(state.entries, fn(old) { old.rel_path == entry.rel_path })
      {
        False -> state
        True ->
          Budget(
            ..state,
            entries: [entry, ..state.entries],
            count: state.count + 1,
            bytes: state.bytes + size,
          )
      }
    }
  }
}

fn walk(
  root: String,
  relative: String,
  depth: Int,
  query: String,
  state: Budget,
) -> Budget {
  case room(state) && depth <= max_directory_depth {
    False -> state
    True ->
      case files.checked_path(root, relative) {
        Error(_) -> state
        Ok(path) ->
          case simplifile.link_info(path) {
            Ok(info) ->
              case simplifile.file_info_type(info) == simplifile.Directory {
                False -> state
                True -> {
                  let names =
                    safe_directory_names(path) |> list.sort(string.compare)
                  visit(root, relative, names, depth, query, state)
                }
              }
            Error(_) -> state
          }
      }
  }
}

fn safe_directory_names(path: String) -> List(String) {
  let decoder = {
    use tag <- decode.field(0, atom.decoder())
    use names <- decode.field(1, decode.list(decode.dynamic))
    decode.success(#(tag, names))
  }
  case decode.run(directory_names(path), decoder) {
    Ok(#(tag, names)) ->
      case atom.to_string(tag) == "ok" {
        False -> []
        True ->
          list.filter_map(names, fn(raw) {
            use name <- result.try(
              decode.run(raw, decode.string) |> result.map_error(fn(_) { Nil }),
            )
            use _ <- result.try(
              bit_array.from_string(name)
              |> bit_array.to_string
              |> result.map_error(fn(_) { Nil }),
            )
            case
              files.relative_path(name),
              string.split(name, "/"),
              string.starts_with(name, ".")
            {
              Ok(_), [_], False -> Ok(name)
              _, _, _ -> Error(Nil)
            }
          })
      }
    Error(_) -> []
  }
}

fn visit(
  root: String,
  parent: String,
  names: List(String),
  depth: Int,
  query: String,
  state: Budget,
) -> Budget {
  case names, room(state) {
    [], _ | _, False -> state
    [name, ..rest], True -> {
      let relative = parent <> "/" <> name
      let counted = Budget(..state, inspected: state.inspected + 1)
      let next = case knowledge.path_security_violation(relative, root) {
        Some(_) -> counted
        None ->
          case files.checked_path(root, relative) {
            Error(_) -> counted
            Ok(path) ->
              case simplifile.link_info(path) {
                Error(_) -> counted
                Ok(info) ->
                  case simplifile.file_info_type(info) {
                    simplifile.Directory ->
                      walk(root, relative, depth + 1, query, counted)
                    simplifile.File ->
                      case markdown(relative) {
                        False -> counted
                        True ->
                          case read_document(root, relative) {
                            None -> counted
                            Some(entry) ->
                              case matches(entry, query) {
                                False -> counted
                                True -> add(counted, Some(entry))
                              }
                          }
                      }
                    _ -> counted
                  }
              }
          }
      }
      visit(root, parent, rest, depth, query, next)
    }
  }
}

fn matches(entry: knowledge.CorpusEntry, query: String) -> Bool {
  let lowered = string.lowercase(entry.rel_path <> " " <> entry.content)
  let words =
    query
    |> string.lowercase
    |> string.replace("\t", " ")
    |> string.replace("\n", " ")
    |> string.split(" ")
  list.all(words, fn(word) { string.contains(lowered, word) })
}

fn read_document(
  root: String,
  relative: String,
) -> Option(knowledge.CorpusEntry) {
  case
    allowed_document_path(relative),
    knowledge.path_security_violation(relative, root),
    files.checked_path(root, relative)
  {
    True, None, Ok(path) ->
      case simplifile.link_info(path) {
        Ok(before) ->
          case safe_file(before) {
            False -> None
            True ->
              case open(path, [Read, Binary, Raw]) {
                Error(_) -> None
                Ok(fd) -> {
                  let content = read_descriptor(fd, path, before)
                  let _ = close(fd)
                  case content {
                    Ok(content) ->
                      Some(knowledge.CorpusEntry(
                        relative,
                        knowledge.RegularFile,
                        "public",
                        content,
                      ))
                    Error(_) -> None
                  }
                }
              }
          }
        Error(_) -> None
      }
    _, _, _ -> None
  }
}

fn safe_file(info: simplifile.FileInfo) -> Bool {
  simplifile.file_info_type(info) == simplifile.File
  && info.nlinks == 1
  && info.size >= 0
  && info.size <= max_file_bytes
}

fn same_identity(
  before: simplifile.FileInfo,
  actual: simplifile.FileInfo,
) -> Bool {
  safe_file(actual)
  && before.inode == actual.inode
  && before.dev == actual.dev
  && before.size == actual.size
  && before.mtime_seconds == actual.mtime_seconds
  && before.ctime_seconds == actual.ctime_seconds
}

fn read_descriptor(
  fd: Device,
  path: String,
  before: simplifile.FileInfo,
) -> Result(String, Nil) {
  use actual <- result.try(
    descriptor_info(fd) |> result.map_error(fn(_) { Nil }),
  )
  use _ <- result.try(case same_identity(before, actual) {
    True -> Ok(Nil)
    False -> Error(Nil)
  })
  let raw = pread(fd, 0, max_file_bytes + 1)
  let bytes = case raw == atom.to_dynamic(atom.create("eof")) {
    True -> Ok(<<>>)
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
            && bit_array.byte_size(bytes) <= max_file_bytes
          {
            True -> Ok(bytes)
            False -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    }
  }
  use bytes <- result.try(bytes)
  use final_fd <- result.try(
    descriptor_info(fd) |> result.map_error(fn(_) { Nil }),
  )
  use final_path <- result.try(
    simplifile.link_info(path) |> result.map_error(fn(_) { Nil }),
  )
  use _ <- result.try(
    case same_identity(before, final_fd) && same_identity(before, final_path) {
      True -> Ok(Nil)
      False -> Error(Nil)
    },
  )
  use content <- result.try(
    bit_array.to_string(bytes) |> result.map_error(fn(_) { Nil }),
  )
  case string.contains(content, "\u{0000}") {
    True -> Error(Nil)
    False -> Ok(content)
  }
}

/// Expanded transient Brain Memory. Legacy prefetch above remains byte-for-byte.
/// Retains descriptor identity/size/link checks and byte budget; the expanded
/// path also anchors open directories to prevent ancestor substitution.
pub fn prefetch_brain_memory(root: String, query: String) -> List(knowledge.CorpusEntry) {
  case valid_root(root) && valid_query(root, query) {
    False -> []
    True -> {
      let initial = list.fold(seed_paths, Budget([], 0, 0, 0), fn(b, p) { add(b, brain_document(root, p)) })
      let available = brain_disk_catalog(root)
      let q = query |> string.split("|") |> list.first |> result.unwrap(query) |> string.replace("[[wiki:", "") |> string.replace("[[zk:", "") |> string.replace("]]", "")
      let q = case string.starts_with(q, root <> "/") { True -> string.drop_start(q, string.length(root) + 1) False -> q }
      let words = query |> string.lowercase |> string.replace("\t", " ") |> string.replace("\n", " ") |> string.split(" ") |> list.filter(fn(w) { w != "" })
      let direct = live_corpus.resolve(available, q)
      let ranked = available
        |> list.filter(fn(e) { !list.contains(direct, e) })
        |> list.map(fn(e) {
          let path = string.lowercase(e.path)
          #(e, list.count(words, fn(w) { string.contains(path, w) }))
        })
        // Stable sorting retains the catalog's newest-first order on ties.
        |> list.sort(fn(a, b) { int.compare(b.1, a.1) })
        |> list.map(fn(scored) { scored.0 })
      let selected = list.append(direct, ranked |> list.take(64 - int.min(64, list.length(direct)))) |> list.take(64)
      let loaded = list.fold(selected, initial, fn(b, e) {
        case brain_document(root, e.path) {
          Some(entry) -> case list.contains(direct, e) || matches(entry, q) { True -> add(b, Some(entry)) False -> b }
          None -> b
        }
      })
      let completed = case q {
        "" -> loaded
        _ -> brain_references(root, available, loaded, 0)
      }
      list.reverse(completed.entries)
    }
  }
}

fn brain_disk_catalog(root: String) -> List(live_corpus.Entry) {
  live_corpus.brain_catalog(root)
}

fn brain_document(root: String, path: String) -> Option(knowledge.CorpusEntry) {
  case live_corpus.brain_file(path) {
    False -> None
    True -> case live_corpus.read(root, path, max_file_bytes) {
      Ok(content) -> case string.contains(content, "\u{0000}") { True -> None False -> Some(knowledge.CorpusEntry(path, knowledge.RegularFile, "public", content)) }
      Error(_) -> None
    }
  }
}

fn brain_references(root: String, available: List(live_corpus.Entry), state: Budget, depth: Int) -> Budget {
  case depth >= 3 || !room(state) { True -> state False -> {
    let targets = list.flat_map(state.entries, fn(e) { string.split(e.content, "[[") |> list.drop(1) |> list.filter_map(fn(part) {
      case string.split_once(part, "]]") { Ok(#(tag, _)) -> case string.split_once(tag, ":") { Ok(#("wiki", t)) | Ok(#("zk", t)) -> Ok(t |> string.split("|") |> list.first |> result.unwrap(t)) _ -> Error(Nil) } _ -> Error(Nil) }
    }) }) |> list.unique |> list.take(24)
    let next = list.fold(targets, state, fn(b, target) {
      case room(b) {
        False -> b
        True -> case live_corpus.resolve(available, target) { [e] -> add(b, brain_document(root, e.path)) _ -> b }
      }
    })
    case next.count == state.count { True -> next False -> brain_references(root, available, next, depth + 1) }
  } }
}

pub fn brain_memory_health_metrics(root: String) -> List(#(String, String)) {
  let intact = live_corpus.canonical_intact(root)
  [#("km_brain_memory_status", case intact { True -> "healthy" False -> "degraded" }),
   #("km_canonical_triad_intact", case intact { True -> "true" False -> "false" }),
   #("km_wiki_docs", int.to_string(live_corpus.count(root, "docs/wiki"))),
   #("km_zk_docs", int.to_string(live_corpus.count(root, "docs/zk"))),
   #("km_sop_docs", int.to_string(live_corpus.count(root, "docs/sop"))),
   #("km_contracts_docs", int.to_string(live_corpus.count(root, "contracts/rules"))),
   #("km_tailscale_cockpit_url", live_corpus.base_url <> "/km")]
}

//// Read-only Telegram knowledge and mesh observations: /mesh /adr /pacing /postmortem /retro.
//// Every "ok" reply is computed from a real backend read; a missing backend is reported
//// as backend_unavailable instead of a canned success. No network, no shell, no effects.

import cepaf_gleam/config/mesh_source
import cepaf_gleam/harness/files
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

const repo_root = "/home/an/NAS-setup/uos"

const max_reply_bytes = 3500

const max_args_bytes = 128

const max_directory_entries = 20_000

const max_listed = 20

const default_listed = 10

pub fn literals() -> List(String) {
  ["/mesh", "/adr", "/pacing", "/postmortem", "/retro"]
}

/// Handle one literal against the canonical repository root.
pub fn handle(literal: String, args: String) -> String {
  handle_at(repo_root, literal, args)
}

/// Same as handle, with an explicit repository root (used by tests and the integrator).
pub fn handle_at(root: String, literal: String, args: String) -> String {
  case list.contains(literals(), literal) {
    False -> denied(literal, "not handled by telegram_knowledge_read_command")
    True ->
      case string.byte_size(args) > max_args_bytes {
        True -> denied(literal, usage(literal))
        False -> bound(literal, dispatch(root, literal, string.trim(args)))
      }
  }
}

fn dispatch(root: String, literal: String, args: String) -> String {
  case literal {
    "/mesh" ->
      case args {
        "" -> mesh_reply(mesh_source.load())
        _ -> denied(literal, usage(literal))
      }
    "/adr" -> adr_reply(root, args)
    "/pacing" ->
      case args {
        "" | "nap" -> pacing_unavailable()
        _ -> denied(literal, usage(literal))
      }
    _ -> journal_reply(root, literal, args)
  }
}

fn usage(literal: String) -> String {
  case literal {
    "/mesh" -> "Usage: /mesh"
    "/adr" -> "Usage: /adr [number 1-999]"
    "/pacing" -> "Usage: /pacing [nap]"
    _ -> "Usage: " <> literal <> " [count 1-20]"
  }
}

// ---- reply encoders -------------------------------------------------------

fn denied(command: String, reason: String) -> String {
  json.object([
    #("status", json.string("denied")),
    #("command", json.string(command)),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

fn unavailable(command: String, backend: String, reason: String) -> String {
  json.object([
    #("status", json.string("backend_unavailable")),
    #("command", json.string(command)),
    #("backend", json.string(backend)),
    #("reason", json.string(reason)),
  ])
  |> json.to_string
}

fn ok(command: String, backend: String, observation: json.Json) -> String {
  json.object([
    #("status", json.string("ok")),
    #("command", json.string(command)),
    #("backend", json.string(backend)),
    #("observation", observation),
  ])
  |> json.to_string
}

fn bound(literal: String, reply: String) -> String {
  case string.byte_size(reply) <= max_reply_bytes {
    True -> reply
    False ->
      unavailable(
        literal,
        "none",
        "reply exceeded the 3500 byte bound and was withheld.",
      )
  }
}

// ---- /mesh ----------------------------------------------------------------

const mesh_backend = "cepaf_gleam/config/mesh_source"

/// Declared mesh configuration only; deployment is never confirmed by this read.
pub fn mesh_reply(
  declaration: Result(mesh_source.Declaration, String),
) -> String {
  case declaration {
    Error(_) ->
      unavailable(
        "/mesh",
        mesh_backend,
        "the declared mesh configuration (UOS_MESH_CONFIG_JSON) is invalid, so nothing can be reported.",
      )
    Ok(_) -> ok("/mesh", mesh_backend, mesh_source.summary(declaration))
  }
}

// ---- /pacing --------------------------------------------------------------

fn pacing_unavailable() -> String {
  unavailable(
    "/pacing",
    "cepaf_gleam/harness/telegram_creative",
    "no typing-cadence or session telemetry source exists; the only /pacing handler returns a static canned text, which is refused.",
  )
}

// ---- directory helpers ----------------------------------------------------

fn list_directory(
  root: String,
  relative: String,
) -> Result(List(String), String) {
  use path <- result.try(files.checked_path(root, relative))
  use info <- result.try(
    simplifile.link_info(path) |> result.replace_error("directory_unavailable"),
  )
  use _ <- result.try(case simplifile.file_info_type(info) {
    simplifile.Directory -> Ok(Nil)
    _ -> Error("not_a_regular_directory")
  })
  use names <- result.try(
    simplifile.read_directory(path)
    |> result.replace_error("directory_unreadable"),
  )
  case list.length(names) <= max_directory_entries {
    True -> Ok(list.filter(names, safe_name))
    False -> Error("directory_bound")
  }
}

fn safe_name(name: String) -> Bool {
  string.ends_with(name, ".md")
  && string.byte_size(name) <= 160
  && result.is_ok(files.relative_path(name))
}

fn all_digits(text: String) -> Bool {
  text != ""
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789", c)
  })
}

fn parse_count(args: String, low: Int, high: Int) -> Option(Int) {
  case string.byte_size(args) <= 4 && all_digits(args) {
    False -> None
    True ->
      case int.parse(args) {
        Ok(n) if n >= low && n <= high -> Some(n)
        _ -> None
      }
  }
}

// ---- /adr -----------------------------------------------------------------

const adr_backend = "cepaf_gleam/harness/files (docs/zk)"

fn adr_number(name: String) -> Option(Int) {
  case string.split_once(name, "-adr-") {
    Ok(#(_, rest)) ->
      case
        all_digits(string.slice(rest, 0, 3)) && string.slice(rest, 3, 1) == "-"
      {
        True -> option.from_result(int.parse(string.slice(rest, 0, 3)))
        False -> None
      }
    Error(_) -> None
  }
}

fn adr_reply(root: String, args: String) -> String {
  case list_directory(root, "docs/zk") {
    Error(reason) ->
      unavailable(
        "/adr",
        adr_backend,
        "docs/zk could not be read: " <> reason <> ".",
      )
    Ok(names) -> {
      let numbered =
        list.filter_map(names, fn(name) {
          case adr_number(name) {
            Some(n) -> Ok(#(n, name))
            None -> Error(Nil)
          }
        })
      case args {
        "" -> {
          let highest = list.fold(numbered, 0, fn(acc, p) { int.max(acc, p.0) })
          ok(
            "/adr",
            adr_backend,
            json.object([
              #("directory", json.string("docs/zk")),
              #("adr_files", json.int(list.length(numbered))),
              #("highest_number", json.int(highest)),
              #(
                "usage",
                json.string("/adr <number> shows one title and first lines"),
              ),
            ]),
          )
        }
        _ ->
          case parse_count(args, 1, 999) {
            None -> denied("/adr", usage("/adr"))
            Some(n) -> adr_detail(root, n, numbered)
          }
      }
    }
  }
}

fn clip(text: String, size: Int) -> String {
  string.slice(text, 0, size)
}

fn adr_detail(root: String, n: Int, numbered: List(#(Int, String))) -> String {
  let matches =
    numbered
    |> list.filter(fn(p) { p.0 == n })
    |> list.map(fn(p) { p.1 })
    |> list.sort(string.compare)
  case matches {
    [] ->
      ok(
        "/adr",
        adr_backend,
        json.object([
          #("number", json.int(n)),
          #("found", json.bool(False)),
        ]),
      )
    [name, ..] ->
      case files.read(root, "docs/zk/" <> name) {
        Error(reason) ->
          unavailable(
            "/adr",
            adr_backend,
            "the ADR file could not be read: " <> reason <> ".",
          )
        Ok(body) -> {
          let lines =
            body
            |> string.split("\n")
            |> list.map(string.trim)
            |> list.filter(fn(l) { l != "" })
          let title = case
            list.find(lines, fn(l) { string.starts_with(l, "# ") })
          {
            Ok(l) -> l
            Error(_) -> result.unwrap(list.first(lines), "")
          }
          ok(
            "/adr",
            adr_backend,
            json.object([
              #("number", json.int(n)),
              #("found", json.bool(True)),
              #("file", json.string(name)),
              #("title", json.string(clip(title, 160))),
              #(
                "first_lines",
                json.array(list.take(lines, 5), fn(l) {
                  json.string(clip(l, 160))
                }),
              ),
            ]),
          )
        }
      }
  }
}

// ---- /postmortem and /retro ----------------------------------------------

const journal_backend = "cepaf_gleam/harness/files (docs/journal)"

fn dated(name: String) -> Bool {
  all_digits(string.slice(name, 0, 8)) && string.slice(name, 8, 1) == "-"
}

fn journal_reply(root: String, literal: String, args: String) -> String {
  let keyword = string.drop_start(literal, 1)
  let count = case args {
    "" -> Some(default_listed)
    _ -> parse_count(args, 1, max_listed)
  }
  case count {
    None -> denied(literal, usage(literal))
    Some(limit) ->
      case list_directory(root, "docs/journal") {
        Error(reason) ->
          unavailable(
            literal,
            journal_backend,
            "docs/journal could not be listed: " <> reason <> ".",
          )
        Ok(names) -> {
          let newest =
            names
            |> list.filter(dated)
            |> list.sort(string.compare)
            |> list.reverse
          ok(
            literal,
            journal_backend,
            json.object([
              #("directory", json.string("docs/journal")),
              #(
                "note",
                json.string(
                  "recent journal filenames only; no postmortem or retro registry exists",
                ),
              ),
              #("dated_journals", json.int(list.length(newest))),
              #("keyword", json.string(keyword)),
              #(
                "keyword_matches",
                json.int(
                  list.length(
                    list.filter(newest, fn(n) {
                      string.contains(string.lowercase(n), keyword)
                    }),
                  ),
                ),
              ),
              #("newest", json.array(list.take(newest, limit), json.string)),
            ]),
          )
        }
      }
  }
}

//// Telegram /repro adapter (controlled-action contract, wave 3).
//// Builds a reproduction packet descriptor for a task or dated journal reference.
//// parse and preview never mutate: preview lists docs/journal through bounded reads.
//// execute writes a receipt-only packet (metadata and digests; NO command is run)
//// with an exclusive create under the supplied evidence directory. Grants no authority.

import cepaf_gleam/harness/files
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const repo_root = "/home/an/NAS-setup/uos"

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_directory_entries = 20_000

const max_listed = 5

const backend = "cepaf_gleam/harness/files (docs/journal)"

pub type Request {
  Request(kind: String, reference: String)
}

pub fn literal() -> String {
  "/repro"
}

const usage = "Usage: /repro <task-id | dated-journal-ref> (letters, digits, '.', '_', '-'; max 128 bytes)."

fn ref_char(c: String) -> Bool {
  string.contains(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-",
    c,
  )
}

fn all_digits(s: String) -> Bool {
  s != ""
  && list.all(string.to_graphemes(s), fn(c) { string.contains("0123456789", c) })
}

pub fn parse(args: String) -> Result(Request, String) {
  let text = string.trim(args)
  case
    text != ""
    && string.byte_size(args) <= max_args_bytes
    && string.byte_size(text) <= 128
    && list.all(string.to_graphemes(text), ref_char)
    && !string.starts_with(text, ".")
  {
    False -> Error(usage)
    True -> {
      let stem = case string.ends_with(text, ".md") {
        True -> string.drop_end(text, 3)
        False -> text
      }
      case stem {
        "" -> Error(usage)
        _ ->
          case
            all_digits(string.slice(stem, 0, 8))
            && string.slice(stem, 8, 1) == "-"
          {
            True -> Ok(Request("journal", stem))
            False -> Ok(Request("task", text))
          }
      }
    }
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("/repro\n" <> r.kind <> "\n" <> r.reference)
}

fn list_journals() -> Result(List(String), String) {
  use path <- result.try(files.checked_path(repo_root, "docs/journal"))
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
    True ->
      Ok(
        list.filter(names, fn(n) {
          string.ends_with(n, ".md")
          && string.byte_size(n) <= 160
          && result.is_ok(files.relative_path(n))
        }),
      )
    False -> Error("directory_bound")
  }
}

/// Returns confidence and the observation object. Only a successful directory
/// listing yields "observed"; a task reference is declared (no task store read here).
fn observe(r: Request) -> #(String, json.Json) {
  case r.kind {
    "journal" ->
      case list_journals() {
        Error(reason) -> #(
          "declared",
          json.object([
            #("journal_listing", json.string("unavailable")),
            #("reason", json.string(reason)),
          ]),
        )
        Ok(names) -> {
          let matches =
            names
            |> list.filter(fn(n) { string.starts_with(n, r.reference) })
            |> list.sort(string.compare)
          let exact = list.contains(matches, r.reference <> ".md")
          let digest = case exact {
            False -> json.null()
            True ->
              case
                files.read(repo_root, "docs/journal/" <> r.reference <> ".md")
              {
                Ok(text) -> json.string(files.digest(text))
                Error(_) -> json.string("unreadable")
              }
          }
          #(
            "observed",
            json.object([
              #("journal_listing", json.string("read")),
              #("journal_exists", json.bool(exact)),
              #("prefix_matches", json.int(list.length(matches))),
              #(
                "matches",
                json.array(list.take(matches, max_listed), json.string),
              ),
              #("file_sha256", digest),
            ]),
          )
        }
      }
    _ -> #(
      "declared",
      json.object([
        #("task_state", json.string("not_observed")),
        #(
          "note",
          json.string(
            "task references are recorded as given; no task store was read",
          ),
        ),
      ]),
    )
  }
}

fn bound(text: String, status: String) -> String {
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False ->
      json.object([
        #("literal", json.string(literal())),
        #("status", json.string(status)),
        #("reason", json.string("reply_bound")),
      ])
      |> json.to_string
  }
}

fn render(
  status: String,
  effect: String,
  r: Request,
  extra: List(#(String, json.Json)),
) -> String {
  let #(confidence, observation) = observe(r)
  json.object(list.append(
    [
      #("literal", json.string(literal())),
      #("status", json.string(status)),
      #("confidence", json.string(confidence)),
      #("effect_id", json.string(effect_id(r))),
      #("effect", json.string(effect)),
      #("backend", json.string(backend)),
      #(
        "request",
        json.object([
          #("kind", json.string(r.kind)),
          #("ref", json.string(r.reference)),
        ]),
      ),
      #("observation", observation),
      #(
        "packet_contains",
        json.array(
          [
            "reference and kind",
            "journal existence and sha256 digest when observed",
            "acceptance and rollback prompts (declared, no commands)",
          ],
          json.string,
        ),
      ),
      #("executes_commands", json.bool(False)),
    ],
    extra,
  ))
  |> json.to_string
  |> bound(status)
}

pub fn preview(r: Request) -> String {
  render("preview", "none", r, [])
}

fn check_dir(dir: String) -> Result(Nil, String) {
  case string.starts_with(dir, "/") && string.byte_size(dir) <= 1024 {
    False -> Error("evidence_dir_required")
    True ->
      case simplifile.link_info(dir) {
        Ok(info) ->
          case simplifile.file_info_type(info) {
            simplifile.Directory -> Ok(Nil)
            _ -> Error("evidence_dir_unavailable")
          }
        Error(_) -> Error("evidence_dir_unavailable")
      }
  }
}

fn duplicate(r: Request, stored: String) -> String {
  json.object([
    #("literal", json.string(literal())),
    #("status", json.string("duplicate")),
    #("effect_id", json.string(effect_id(r))),
    #("receipt_sha256", json.string(files.digest(stored))),
  ])
  |> json.to_string
}

pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  use _ <- result.try(check_dir(evidence_dir))
  let name = effect_id(r) <> ".json"
  case files.read(evidence_dir, name) {
    Ok(stored) -> Ok(duplicate(r, stored))
    Error(_) -> {
      let receipt = render("executed", "receipt_only", r, [])
      case string.contains(receipt, "\"reply_bound\"") {
        True -> Error("reply_bound")
        False ->
          case files.create(evidence_dir, name, receipt) {
            Ok(_) -> Ok(receipt)
            Error(reason) ->
              case files.read(evidence_dir, name) {
                Ok(stored) -> Ok(duplicate(r, stored))
                Error(_) -> Error(reason)
              }
          }
      }
    }
  }
}

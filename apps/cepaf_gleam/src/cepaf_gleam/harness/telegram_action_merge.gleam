//// Telegram /merge adapter (controlled-action contract, wave 3).
//// NEVER performs a VCS mutation and never writes anything. parse validates the
//// change-id shape; preview declares the preconditions (integration/main lease and a
//// green suite). execute always returns Error("backend_unavailable:integration_lease")
//// in development: only a held lease plus a green tip may move the main bookmark, and
//// that authority is outside this adapter. Grants no authority.

import cepaf_gleam/harness/files
import gleam/json
import gleam/list
import gleam/string

const max_args_bytes = 256

const max_reply_bytes = 3500

pub type Request {
  Request(change_id: String, shape: String)
}

pub fn literal() -> String {
  "/merge"
}

const usage = "Usage: /merge <change-id> (8-32 letters k-z as printed by jj, or 8-40 lowercase hex commit id)."

fn all_in(s: String, alphabet: String) -> Bool {
  s != ""
  && list.all(string.to_graphemes(s), fn(c) { string.contains(alphabet, c) })
}

pub fn parse(args: String) -> Result(Request, String) {
  let text = string.trim(args)
  let n = string.byte_size(text)
  case string.byte_size(args) <= max_args_bytes {
    False -> Error(usage)
    True ->
      case all_in(text, "klmnopqrstuvwxyz") && n >= 8 && n <= 32 {
        True -> Ok(Request(text, "change_id"))
        False ->
          case all_in(text, "0123456789abcdef") && n >= 8 && n <= 40 {
            True -> Ok(Request(text, "commit_id"))
            False -> Error(usage)
          }
      }
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest("/merge\n" <> r.shape <> "\n" <> r.change_id)
}

pub fn preview(r: Request) -> String {
  let text =
    json.object([
      #("literal", json.string(literal())),
      #("status", json.string("backend_unavailable")),
      #("confidence", json.string("declared")),
      #("effect_id", json.string(effect_id(r))),
      #("effect", json.string("none")),
      #("backend", json.string("integration_lease")),
      #(
        "request",
        json.object([
          #("change_id", json.string(r.change_id)),
          #("shape", json.string(r.shape)),
        ]),
      ),
      #(
        "requires",
        json.array(
          [
            "held integration/main lease",
            "green build and test suite at the new tip",
          ],
          json.string,
        ),
      ),
      #("vcs_mutation", json.bool(False)),
      #("execute", json.string("backend_unavailable:integration_lease")),
    ])
    |> json.to_string
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False ->
      "{\"literal\":\"/merge\",\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

/// Always unavailable in development. Writes nothing, touches no directory.
pub fn execute(_r: Request, _evidence_dir: String) -> Result(String, String) {
  Error("backend_unavailable:integration_lease")
}

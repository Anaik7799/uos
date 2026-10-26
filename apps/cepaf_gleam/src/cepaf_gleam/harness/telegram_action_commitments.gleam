//// Telegram /commitments adapter (controlled-action contract, wave 3).
//// The canonical read path for open tasks is the pinned Sa-plan observer
//// (harness/telegram_task_command.observe_task over harness/observer_policy), which
//// needs a service-held ObserveRequest (guardian/observer executables, pinned digests,
//// database path). A unit-testable adapter cannot construct that, so preview reports the
//// DECLARED plan ids it would observe and execute returns an exact unavailable error
//// naming the module. Nothing is read or written. Grants no authority.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/observer_policy as observer
import gleam/json
import gleam/list
import gleam/string

const max_args_bytes = 256

const max_reply_bytes = 3500

const backend = "cepaf_gleam/harness/telegram_task_command"

const declared_plans = [
  "uos/telegram-runtime/20261001-1150",
  "uos/km-index-refresh/20260908-0912",
]

pub type Request {
  Request
}

pub fn literal() -> String {
  "/commitments"
}

const usage = "Usage: /commitments (no arguments)."

pub fn parse(args: String) -> Result(Request, String) {
  case string.trim(args) == "" && string.byte_size(args) <= max_args_bytes {
    True -> Ok(Request)
    False -> Error(usage)
  }
}

pub fn effect_id(_r: Request) -> String {
  files.digest("/commitments\n" <> string.join(declared_plans, "\n"))
}

pub fn preview(r: Request) -> String {
  let text =
    json.object([
      #("literal", json.string(literal())),
      #("status", json.string("preview")),
      #("confidence", json.string("declared")),
      #("effect_id", json.string(effect_id(r))),
      #("effect", json.string("none")),
      #("backend", json.string(backend)),
      #(
        "plans",
        json.array(list.filter(declared_plans, observer.valid_id), json.string),
      ),
      #("tasks_observed", json.int(0)),
      #(
        "note",
        json.string(
          "open tasks need the pinned Sa-plan observer configuration held by the service; none was read",
        ),
      ),
      #("execute", json.string("backend_unavailable:" <> backend)),
    ])
    |> json.to_string
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False ->
      "{\"literal\":\"/commitments\",\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

/// Unavailable in development: writes nothing and reads nothing.
pub fn execute(_r: Request, _evidence_dir: String) -> Result(String, String) {
  Error("backend_unavailable:" <> backend)
}

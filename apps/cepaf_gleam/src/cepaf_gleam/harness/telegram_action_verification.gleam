//// ControlledAction adapter for `/verification [scope]` (contract 20261026-0115).
//// A READ of the candidate-bound verification catalog used by `/aspects`.
//// The live reader (`telegram_verification_reader.observe`) needs a pinned
//// Source and launches a guardian child process; this adapter never does that
//// and never runs a verifier binary. It uses the reader's pure half
//// (`telegram_verification_report` catalog and scope check) and reports every
//// row as UNKNOWN with `record_source: not_configured`, confidence `declared`.
//// Execute writes the same summary as an exclusive-create receipt only. Grants
//// no authority and no admission credit.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_verification_report as report
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(view: String, selector: String)
}

const literal_text = "/verification"

const max_args = 256

const max_reply = 3500

const backend = "telegram_verification_report"

const usage = "usage: /verification [checklist|aspects|A01..A17]"

pub fn literal() -> String {
  literal_text
}

/// Pure: reads nothing.
pub fn parse(args: String) -> Result(Request, String) {
  let tokens =
    args
    |> string.split(" ")
    |> list.map(string.trim)
    |> list.filter(fn(t) { t != "" })
  let scope = case tokens {
    [] | ["checklist"] -> Ok(#("checklist", ""))
    ["aspects"] -> Ok(#("aspects", ""))
    [id] -> Ok(#("aspects", id))
    _ -> Error(usage)
  }
  case string.byte_size(args) <= max_args, scope {
    True, Ok(#(view, selector)) ->
      case report.valid_scope(view, selector) {
        True -> Ok(Request(view, selector))
        False -> Error(usage)
      }
    _, _ -> Error(usage)
  }
}

pub fn effect_id(r: Request) -> String {
  files.digest(
    "uos.telegram.action.verification.v1|view="
    <> r.view
    <> "|selector="
    <> r.selector,
  )
}

fn reply(fields: List(#(String, json.Json))) -> String {
  let text = json.object(fields) |> json.to_string
  case string.byte_size(text) <= max_reply {
    True -> text
    False ->
      json.object([
        #("status", json.string("denied")),
        #("literal", json.string(literal_text)),
        #("reason", json.string("reply_bound")),
      ])
      |> json.to_string
  }
}

fn head(status: String, r: Request) -> List(#(String, json.Json)) {
  [
    #("status", json.string(status)),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
  ]
}

fn catalog(r: Request) -> List(#(String, String)) {
  let all = case r.view {
    "checklist" -> report.checkpoints
    _ -> report.aspects
  }
  list.filter(all, fn(p) { r.selector == "" || p.0 == r.selector })
}

fn summary_fields(r: Request) -> List(#(String, json.Json)) {
  let rows = catalog(r)
  [
    #("view", json.string(r.view)),
    #("selector", json.string(r.selector)),
    #("selected_count", json.int(list.length(rows))),
    #("recorded_count", json.int(0)),
    #("missing_count", json.int(list.length(rows))),
    #("current_recorded_pass_count", json.int(0)),
    #("record_source", json.string("not_configured")),
    #(
      "rows",
      json.array(rows, fn(p) {
        json.object([
          #("id", json.string(p.0)),
          #("name", json.string(p.1)),
          #("state", json.string("UNKNOWN")),
          #("admission_credit", json.bool(False)),
        ])
      }),
    ),
    #("evidence_bytes_verified", json.bool(False)),
    #("gates_executed", json.bool(False)),
    #("runtime_admission", json.string("NOT_GRANTED")),
    #("backend", json.string(backend)),
    #("authority", json.string("NONE")),
  ]
}

/// Read-only: the declared catalog with no recorded outcome bound.
pub fn preview(r: Request) -> String {
  reply(
    list.flatten([
      head("preview", r),
      [
        #("confidence", json.string("declared")),
        #(
          "effect",
          json.string("record verification summary receipt; no gate is run"),
        ),
      ],
      summary_fields(r),
    ]),
  )
}

fn stored_decoder() -> decode.Decoder(String) {
  use effect <- decode.field("effect_id", decode.string)
  decode.success(effect)
}

fn duplicate(r: Request, dir: String) -> Result(String, String) {
  use raw <- result.try(files.read(dir, effect_id(r) <> ".json"))
  use stored <- result.try(
    json.parse(raw, stored_decoder())
    |> result.replace_error("receipt_unreadable"),
  )
  case stored == effect_id(r) {
    False -> Error("receipt_identity_mismatch")
    True ->
      Ok(
        reply(
          list.flatten([
            head("duplicate", r),
            [
              #("receipt_sha256", json.string(files.digest(raw))),
              #("authority", json.string("NONE")),
            ],
          ]),
        ),
      )
  }
}

/// Receipt-only and idempotent by `effect_id` (exclusive create).
pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> record(r, evidence_dir)
    _ -> Error("evidence_dir_unavailable")
  }
}

fn record(r: Request, dir: String) -> Result(String, String) {
  let body =
    reply(
      list.flatten([
        head("executed", r),
        [#("confidence", json.string("declared"))],
        summary_fields(r),
      ]),
    )
  let name = effect_id(r) <> ".json"
  case files.create(dir, name, body) {
    Ok(_) -> Ok(body)
    Error(reason) ->
      case simplifile.is_file(dir <> "/" <> name) {
        Ok(True) -> duplicate(r, dir)
        _ -> Error(reason)
      }
  }
}

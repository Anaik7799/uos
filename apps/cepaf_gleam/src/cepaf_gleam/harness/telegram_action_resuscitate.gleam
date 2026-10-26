//// Telegram /resuscitate controlled-action adapter (wave 3, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backend: ecology/andon. The bounded development effect is a recovery PLAN
//// RECORD: the pure andon.begin_recovery transition applied to the module's
//// declared startup table (andon.initial), written as an exclusive-create
//// receipt. No process, actor or daemon is restarted and no backend probe is
//// made; finishing a recovery needs an engaged backend receipt that this
//// module never fabricates. This module grants no authority; the service
//// calls execute only after approval and fences.
////
//// Decision state is one of: parse (pure), preview (pure), execute (one
//// exclusive file create, idempotent by effect_id).

import cepaf_gleam/ecology/andon
import cepaf_gleam/harness/files
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_receipt_bytes = 3000

pub opaque type Request {
  Request(capability: String)
}

pub fn literal() -> String {
  "/resuscitate"
}

fn usage() -> String {
  "usage: /resuscitate <modular_max|openrouter_free>"
}

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error("args_bound: " <> usage())
    True ->
      case
        string.split(string.trim(args), " ")
        |> list.filter(fn(part) { part != "" })
      {
        [capability] ->
          case andon.shared(capability) {
            True -> Ok(Request(capability))
            False -> Error(usage())
          }
        _ -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  "resuscitate-"
  <> files.digest("telegram_action_resuscitate/v1\n" <> r.capability)
}

fn declared(r: Request) -> Result(andon.Service, String) {
  andon.find(andon.initial(), r.capability)
  |> result.replace_error("backend_unavailable:ecology/andon")
}

fn recover(r: Request) -> Result(andon.Service, String) {
  use services <- result.try(
    andon.begin_recovery(andon.initial(), r.capability)
    |> result.replace_error("backend_unavailable:ecology/andon"),
  )
  andon.find(services, r.capability)
  |> result.replace_error("backend_unavailable:ecology/andon")
}

fn unavailable_json(r: Request) -> String {
  json.object([
    #("status", json.string("backend_unavailable")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("backend", json.string("ecology/andon")),
    #("authority", json.string("NONE")),
  ])
  |> json.to_string
}

/// Read-only. Reads andon.initial() (the declared startup table) and computes
/// the pure begin_recovery transition; the live actor's table is NOT read,
/// hence "simulated".
pub fn preview(r: Request) -> String {
  case declared(r), recover(r) {
    Ok(before), Ok(after) ->
      json.object([
        #("status", json.string("preview")),
        #("literal", json.string(literal())),
        #("effect_id", json.string(effect_id(r))),
        #("capability", json.string(r.capability)),
        #("confidence", json.string("simulated")),
        #(
          "state_source",
          json.string(
            "andon.initial declared startup table; live actor state not read",
          ),
        ),
        #("declared_before_phase", json.string(andon.phase_label(before.phase))),
        #("predicted_after_phase", json.string(andon.phase_label(after.phase))),
        #("predicted_recovery_attempts", json.int(after.recovery_attempts)),
        #("completion_requires", json.string("engaged_backend_probe_receipt")),
        #("effect", json.string("recovery_plan_record_only")),
        #("process_restarted", json.bool(False)),
        #("approval_required", json.bool(True)),
        #("authority", json.string("NONE")),
      ])
      |> json.to_string
      |> bound
    _, _ -> bound(unavailable_json(r))
  }
}

fn receipt_json(r: Request) -> Result(String, String) {
  use before <- result.try(declared(r))
  use after <- result.try(recover(r))
  Ok(
    json.object([
      #("status", json.string("executed")),
      #("literal", json.string(literal())),
      #("effect_id", json.string(effect_id(r))),
      #("capability", json.string(r.capability)),
      #("confidence", json.string("simulated")),
      #("before_phase", json.string(andon.phase_label(before.phase))),
      #("after_phase", json.string(andon.phase_label(after.phase))),
      #("service", andon.to_json(after)),
      #("completion_requires", json.string("engaged_backend_probe_receipt")),
      #("effect", json.string("recovery_plan_record_only")),
      #("process_restarted", json.bool(False)),
      #("clock", json.string("not_sampled")),
      #("authority", json.string("NONE")),
    ])
    |> json.to_string,
  )
}

fn bound(text: String) -> String {
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False -> "{\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

fn stored_decoder(id: String) -> decode.Decoder(Nil) {
  use status <- decode.field("status", decode.string)
  use stored_id <- decode.field("effect_id", decode.string)
  use stored_literal <- decode.field("literal", decode.string)
  case status == "executed" && stored_id == id && stored_literal == literal() {
    True -> decode.success(Nil)
    False -> decode.failure(Nil, "stored_receipt_mismatch")
  }
}

fn duplicate(id: String, stored: String) -> Result(String, String) {
  case json.parse(stored, stored_decoder(id)) {
    Error(_) -> Error("stored_receipt_invalid")
    Ok(_) ->
      Ok(bound(
        "{\"status\":\"duplicate\",\"literal\":\""
        <> literal()
        <> "\",\"effect_id\":\""
        <> id
        <> "\",\"stored_receipt\":"
        <> stored
        <> "}",
      ))
  }
}

/// Idempotent by effect_id: exclusive create of <evidence_dir>/<effect_id>.json.
/// A missing evidence_dir is an Error; nothing is created implicitly.
pub fn execute(r: Request, evidence_dir: String) -> Result(String, String) {
  use receipt <- result.try(receipt_json(r))
  let id = effect_id(r)
  let name = id <> ".json"
  use _ <- result.try(case string.byte_size(receipt) <= max_receipt_bytes {
    True -> Ok(Nil)
    False -> Error("receipt_bound")
  })
  use _ <- result.try(case string.trim(evidence_dir) != "" {
    True -> Ok(Nil)
    False -> Error("evidence_dir_missing")
  })
  use _ <- result.try(case simplifile.is_directory(evidence_dir) {
    Ok(True) -> Ok(Nil)
    _ -> Error("evidence_dir_missing")
  })
  case files.read(evidence_dir, name) {
    Ok(stored) -> duplicate(id, stored)
    Error(_) ->
      case files.create(evidence_dir, name, receipt) {
        Ok(_) -> Ok(bound(receipt))
        Error(reason) ->
          case files.read(evidence_dir, name) {
            Ok(stored) -> duplicate(id, stored)
            Error(_) -> Error(reason)
          }
      }
  }
}

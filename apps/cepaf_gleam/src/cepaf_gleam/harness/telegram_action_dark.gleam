//// Telegram /dark controlled-action adapter (wave 2, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backend: prajna/dark_cockpit. Cockpit mode is a pure function of the alert
//// list (determine_mode), so a requested mode is realised by the minimal
//// synthetic alert set that yields it, folded through add_alert from
//// initial_state. The result is a state-transition RECORD (exclusive-create
//// receipt); no global cockpit state is mutated. Reversible: "/dark dark"
//// maps to the empty alert set. This module grants no authority.

import cepaf_gleam/harness/files
import cepaf_gleam/prajna/dark_cockpit as cockpit
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
  Request(target: String)
}

pub fn literal() -> String {
  "/dark"
}

fn usage() -> String {
  "usage: /dark <dark|dim|normal|bright|emergency>"
}

const targets = ["dark", "dim", "normal", "bright", "emergency"]

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error("args_bound: " <> usage())
    True -> {
      let target = string.trim(args)
      case list.contains(targets, target) {
        True -> Ok(Request(target))
        False -> Error(usage())
      }
    }
  }
}

pub fn effect_id(r: Request) -> String {
  "dark-" <> files.digest("telegram_action_dark/v1\n" <> r.target)
}

fn mode_label(mode: cockpit.CockpitMode) -> String {
  case mode {
    cockpit.Dark -> "dark"
    cockpit.Dim -> "dim"
    cockpit.NormalMode -> "normal"
    cockpit.Bright -> "bright"
    cockpit.EmergencyMode -> "emergency"
  }
}

fn alert(index: Int, severity: cockpit.AlertSeverity) -> cockpit.Alert {
  cockpit.Alert(
    id: "telegram-dark-" <> string.inspect(index),
    severity: severity,
    message: "operator requested cockpit mode",
    source: "telegram_action_dark",
    timestamp: "",
    acknowledged: False,
  )
}

/// Minimal synthetic alert set whose determine_mode is the requested target.
fn alerts_for(target: String) -> List(cockpit.Alert) {
  case target {
    "dim" -> [alert(1, cockpit.WarningSeverity)]
    "normal" -> [alert(1, cockpit.ErrorSeverity)]
    "bright" -> [
      alert(1, cockpit.ErrorSeverity),
      alert(2, cockpit.ErrorSeverity),
      alert(3, cockpit.ErrorSeverity),
    ]
    "emergency" -> [alert(1, cockpit.CriticalSeverity)]
    _ -> []
  }
}

/// Fold the synthetic alerts through the real transition functions and check
/// the resulting mode equals the request; a mismatch means the backend's
/// mode rule changed under us and the adapter fails closed.
fn transition(r: Request) -> Result(cockpit.CockpitState, String) {
  let after =
    alerts_for(r.target)
    |> list.fold(cockpit.initial_state(), cockpit.add_alert)
    |> cockpit.update("")
  case mode_label(after.mode) == r.target {
    True -> Ok(after)
    False -> Error("backend_unavailable:prajna/dark_cockpit")
  }
}

fn bound(text: String) -> String {
  case string.byte_size(text) <= max_reply_bytes {
    True -> text
    False -> "{\"status\":\"denied\",\"reason\":\"reply_bound\"}"
  }
}

fn unavailable_json(r: Request) -> String {
  json.object([
    #("status", json.string("backend_unavailable")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("backend", json.string("prajna/dark_cockpit")),
    #("authority", json.string("NONE")),
  ])
  |> json.to_string
}

fn alert_ids(state: cockpit.CockpitState) -> json.Json {
  json.array(list.reverse(state.alerts), fn(a) { json.string(a.id) })
}

/// Read-only. Before-state is cockpit.initial_state() (declared module default;
/// the running cockpit is not read); after-state is the pure transition.
pub fn preview(r: Request) -> String {
  case transition(r) {
    Error(_) -> bound(unavailable_json(r))
    Ok(after) -> {
      let before = cockpit.initial_state()
      json.object([
        #("status", json.string("preview")),
        #("literal", json.string(literal())),
        #("effect_id", json.string(effect_id(r))),
        #("target_mode", json.string(r.target)),
        #("confidence", json.string("declared")),
        #(
          "state_source",
          json.string(
            "dark_cockpit.initial_state declared default; running cockpit not read",
          ),
        ),
        #("before_mode", json.string(mode_label(before.mode))),
        #("predicted_after_mode", json.string(mode_label(after.mode))),
        #("synthetic_alerts", alert_ids(after)),
        #("reversible_by", json.string("/dark dark")),
        #("effect", json.string("cockpit_mode_transition_record_only")),
        #("global_state_mutated", json.bool(False)),
        #("approval_required", json.bool(True)),
        #("authority", json.string("NONE")),
      ])
      |> json.to_string
      |> bound
    }
  }
}

fn receipt_json(r: Request, after: cockpit.CockpitState) -> String {
  json.object([
    #("status", json.string("executed")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("target_mode", json.string(r.target)),
    #("confidence", json.string("declared")),
    #("before_mode", json.string(mode_label(cockpit.initial_state().mode))),
    #("after_mode", json.string(mode_label(after.mode))),
    #("synthetic_alerts", alert_ids(after)),
    #("alert_count", json.int(list.length(after.alerts))),
    #("effect", json.string("cockpit_mode_transition_record_only")),
    #("global_state_mutated", json.bool(False)),
    #("clock", json.string("not_sampled")),
    #("authority", json.string("NONE")),
  ])
  |> json.to_string
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
  use after <- result.try(transition(r))
  let id = effect_id(r)
  let name = id <> ".json"
  let receipt = receipt_json(r, after)
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

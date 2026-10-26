//// Telegram /escalate controlled-action adapter (wave 3, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backends: iam/freshness_monitor.classify (the Fresh/Stale/Degraded/Dead
//// escalation ladder) and ha/runbooks (RB-009 staleness, RB-010 Jidoka halt).
//// The bounded development effect is an escalation RECORD computed from a
//// DECLARED staleness age: no notification is sent, no cockpit mode is set,
//// no runbook step is executed. This module grants no authority; the service
//// calls execute only after approval and fences.
////
//// Decision state is one of: parse (pure), preview (pure), execute (one
//// exclusive file create, idempotent by effect_id).

import cepaf_gleam/ha/runbooks
import cepaf_gleam/harness/files
import cepaf_gleam/iam/freshness_monitor as ladder
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_receipt_bytes = 3000

const max_age_seconds = 86_400

pub opaque type Request {
  Request(age_seconds: Int)
}

type Plan {
  Plan(
    level: String,
    mode: String,
    runbook_id: String,
    runbook_name: String,
    severity: String,
    steps: Int,
    duration_ms: Int,
    jidoka_halt: Bool,
  )
}

pub fn literal() -> String {
  "/escalate"
}

fn usage() -> String {
  "usage: /escalate <declared_staleness_age_seconds 0..86400>"
}

fn digits_ok(text: String) -> Bool {
  let size = string.byte_size(text)
  size >= 1
  && size <= 5
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("0123456789", c)
  })
}

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error("args_bound: " <> usage())
    True ->
      case
        string.split(string.trim(args), " ")
        |> list.filter(fn(part) { part != "" })
      {
        [age] ->
          case digits_ok(age) {
            False -> Error(usage())
            True ->
              case int.parse(age) {
                Ok(n) if n <= max_age_seconds -> Ok(Request(n))
                _ -> Error("age_out_of_range: " <> usage())
              }
          }
        _ -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  "escalate-"
  <> files.digest(
    "telegram_action_escalate/v1\n" <> int.to_string(r.age_seconds),
  )
}

fn plan(r: Request) -> Result(Plan, String) {
  let #(level, mode, trigger) = case ladder.classify(r.age_seconds * 1000) {
    ladder.Fresh -> #("fresh", "normal", Error(Nil))
    ladder.Stale -> #(
      "stale",
      "dim",
      Ok(runbooks.StalenessDetected(r.age_seconds)),
    )
    ladder.Degraded -> #(
      "degraded",
      "bright",
      Ok(runbooks.StalenessDetected(r.age_seconds)),
    )
    ladder.Dead -> #("dead", "emergency", Ok(runbooks.ManualTrigger))
  }
  case trigger {
    Error(_) -> Ok(Plan(level, mode, "none", "none", "NONE", 0, 0, False))
    Ok(t) ->
      case runbooks.runbook_for_trigger(t) {
        Error(_) -> Error("backend_unavailable:ha/runbooks")
        Ok(rb) ->
          Ok(Plan(
            level,
            mode,
            rb.id,
            rb.name,
            rb.severity,
            list.length(rb.steps),
            rb.estimated_duration_ms,
            list.any(rb.steps, fn(step) { step.action == runbooks.JidokaHalt }),
          ))
      }
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
    #("backend", json.string("ha/runbooks")),
    #("authority", json.string("NONE")),
  ])
  |> json.to_string
}

/// Read-only. The staleness age is DECLARED by the caller; no live freshness
/// monitor is read, hence "simulated".
pub fn preview(r: Request) -> String {
  case plan(r) {
    Error(_) -> bound(unavailable_json(r))
    Ok(p) ->
      json.object([
        #("status", json.string("preview")),
        #("literal", json.string(literal())),
        #("effect_id", json.string(effect_id(r))),
        #("confidence", json.string("simulated")),
        #(
          "state_source",
          json.string(
            "declared age input through iam/freshness_monitor.classify; live freshness not read",
          ),
        ),
        #("age_seconds", json.int(r.age_seconds)),
        #("staleness_level", json.string(p.level)),
        #("cockpit_mode", json.string(p.mode)),
        #("runbook_id", json.string(p.runbook_id)),
        #("runbook_severity", json.string(p.severity)),
        #("runbook_steps", json.int(p.steps)),
        #("jidoka_halt_in_plan", json.bool(p.jidoka_halt)),
        #("effect", json.string("escalation_record_only")),
        #("notification_sent", json.bool(False)),
        #("approval_required", json.bool(True)),
        #("authority", json.string("NONE")),
      ])
      |> json.to_string
      |> bound
  }
}

fn receipt_json(r: Request) -> Result(String, String) {
  use p <- result.try(plan(r))
  Ok(
    json.object([
      #("status", json.string("executed")),
      #("literal", json.string(literal())),
      #("effect_id", json.string(effect_id(r))),
      #("confidence", json.string("simulated")),
      #("age_seconds", json.int(r.age_seconds)),
      #("staleness_level", json.string(p.level)),
      #("cockpit_mode", json.string(p.mode)),
      #("runbook_id", json.string(p.runbook_id)),
      #("runbook_name", json.string(p.runbook_name)),
      #("runbook_severity", json.string(p.severity)),
      #("runbook_steps", json.int(p.steps)),
      #("runbook_estimated_ms", json.int(p.duration_ms)),
      #("jidoka_halt_in_plan", json.bool(p.jidoka_halt)),
      #("effect", json.string("escalation_record_only")),
      #("notification_sent", json.bool(False)),
      #("clock", json.string("not_sampled")),
      #("authority", json.string("NONE")),
    ])
    |> json.to_string,
  )
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

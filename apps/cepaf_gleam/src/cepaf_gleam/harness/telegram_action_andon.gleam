//// Telegram /andon controlled-action adapter (wave 2, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backend: ecology/andon. The bounded development effect is an Andon trip
//// RECORD: the pure andon.finish transition applied to a hypothetical Ready
//// service, written as an exclusive-create receipt. No service, process or
//// actor is stopped or signalled. This module grants no authority; the service
//// calls execute only after approval and fences.
////
//// Decision state is one of: parse (pure), preview (pure), execute (one
//// exclusive file create, idempotent by effect_id).

import cepaf_gleam/ecology/andon
import cepaf_gleam/ecology/capability_port
import cepaf_gleam/harness/files
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import simplifile

const max_args_bytes = 256

const max_reply_bytes = 3500

const max_receipt_bytes = 3000

const holon = "telegram_action_andon"

pub opaque type Request {
  Request(capability: String, reason: String)
}

pub fn literal() -> String {
  "/andon"
}

fn usage() -> String {
  "usage: /andon <modular_max|openrouter_free> <reason_token a-z0-9_ max 64, a serious failure reason>"
}

fn token_ok(text: String) -> Bool {
  let size = string.byte_size(text)
  size >= 1
  && size <= 64
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyz0123456789_", c)
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
        [capability, reason] ->
          case andon.shared(capability), token_ok(reason) {
            True, True ->
              case andon.serious_failure(reason) {
                True -> Ok(Request(capability, reason))
                False -> Error("reason_not_a_serious_failure: " <> usage())
              }
            _, _ -> Error(usage())
          }
        _ -> Error(usage())
      }
  }
}

pub fn effect_id(r: Request) -> String {
  "andon-"
  <> files.digest(
    "telegram_action_andon/v1\n" <> r.capability <> "\n" <> r.reason,
  )
}

fn trip(r: Request) -> Result(andon.Service, String) {
  let baseline =
    andon.Service(
      capability: r.capability,
      phase: andon.Ready,
      reason: "",
      failure_count: 0,
      recovery_attempts: 0,
      recovery_count: 0,
      last_failure: None,
      last_recovery: None,
    )
  let receipt =
    andon.Receipt(
      sequence: 1,
      cycle: 0,
      observed_at_us: 0,
      holon_id: holon,
      outcome: capability_port.Unavailable(r.capability, r.reason),
    )
  andon.finish([baseline], r.capability, False, receipt)
  |> andon.find(r.capability)
  |> result.replace_error("backend_unavailable:ecology/andon")
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
    #("backend", json.string("ecology/andon")),
    #("authority", json.string("NONE")),
  ])
  |> json.to_string
}

/// Read-only. Reads andon.initial() (the module's declared startup state) and
/// computes the pure trip transition against a hypothetical Ready baseline;
/// the live actor's service table is NOT read, hence "simulated".
pub fn preview(r: Request) -> String {
  case trip(r) {
    Error(_) -> bound(unavailable_json(r))
    Ok(after) -> {
      let startup = case andon.find(andon.initial(), r.capability) {
        Ok(service) -> andon.phase_label(service.phase)
        Error(_) -> "unknown"
      }
      json.object([
        #("status", json.string("preview")),
        #("literal", json.string(literal())),
        #("effect_id", json.string(effect_id(r))),
        #("capability", json.string(r.capability)),
        #("reason", json.string(r.reason)),
        #("confidence", json.string("simulated")),
        #(
          "state_source",
          json.string(
            "andon.initial declared startup phase; live actor state not read",
          ),
        ),
        #("declared_startup_phase", json.string(startup)),
        #("hypothetical_before_phase", json.string("ready")),
        #("predicted_after_phase", json.string(andon.phase_label(after.phase))),
        #("predicted_failure_count", json.int(after.failure_count)),
        #("effect", json.string("andon_trip_record_only")),
        #("process_signalled", json.bool(False)),
        #("approval_required", json.bool(True)),
        #("authority", json.string("NONE")),
      ])
      |> json.to_string
      |> bound
    }
  }
}

fn receipt_json(r: Request, after: andon.Service) -> String {
  json.object([
    #("status", json.string("executed")),
    #("literal", json.string(literal())),
    #("effect_id", json.string(effect_id(r))),
    #("capability", json.string(r.capability)),
    #("reason", json.string(r.reason)),
    #("confidence", json.string("simulated")),
    #("before_phase", json.string("ready")),
    #("after_phase", json.string(andon.phase_label(after.phase))),
    #("service", andon.to_json(after)),
    #("effect", json.string("andon_trip_record_only")),
    #("process_signalled", json.bool(False)),
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
  use after <- result.try(trip(r))
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

//// Telegram /migrate controlled-action adapter (wave 3, contract
//// 20261026-0115-telegram-controlled-action-adapter-contract).
////
//// Backend: services/mirage_migration_engine. The bounded development effect
//// is a migration stage-transition RECORD: the pure advance_candidate /
//// advance_stage function and the non-negotiable boundary screen, applied to a
//// catalog candidate (optionally from a hypothetical starting stage) and
//// written as an exclusive-create receipt. Nothing is migrated, deployed,
//// benchmarked or admitted; every figure is the catalog's configured
//// projection. This module grants no authority; the service calls execute
//// only after approval and fences.
////
//// Decision state is one of: parse (pure), preview (pure), execute (one
//// exclusive file create, idempotent by effect_id).

import cepaf_gleam/harness/files
import cepaf_gleam/services/mirage_migration_engine as engine
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
  Request(candidate: String, from: String)
}

type Plan {
  Plan(
    candidate: engine.MigrationCandidate,
    from: engine.MigrationStage,
    to: engine.MigrationStage,
  )
}

pub fn literal() -> String {
  "/migrate"
}

fn usage() -> String {
  "usage: /migrate <candidate_id e.g. MIG-01-INGRESS> [from_stage discovered|classified|mapped]"
}

fn id_ok(text: String) -> Bool {
  let size = string.byte_size(text)
  size >= 1
  && size <= 32
  && list.all(string.to_graphemes(text), fn(c) {
    string.contains("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-", c)
  })
}

fn stage_of(label: String) -> Result(engine.MigrationStage, Nil) {
  case label {
    "discovered" -> Ok(engine.Discovered)
    "classified" -> Ok(engine.Classified)
    "mapped" -> Ok(engine.Mapped)
    _ -> Error(Nil)
  }
}

fn known(id: String) -> Bool {
  case engine.find_candidate(engine.get_migration_candidates(), id) {
    Ok(_) -> True
    Error(_) -> False
  }
}

pub fn parse(args: String) -> Result(Request, String) {
  case string.byte_size(args) <= max_args_bytes {
    False -> Error("args_bound: " <> usage())
    True ->
      case
        string.split(string.trim(args), " ")
        |> list.filter(fn(part) { part != "" })
      {
        [id] -> candidate_request(id, "declared")
        [id, from] ->
          case stage_of(from) {
            Ok(_) -> candidate_request(id, from)
            Error(_) -> Error(usage())
          }
        _ -> Error(usage())
      }
  }
}

fn candidate_request(id: String, from: String) -> Result(Request, String) {
  case id_ok(id) && known(id) {
    True -> Ok(Request(id, from))
    False -> Error("unknown_candidate: " <> usage())
  }
}

pub fn effect_id(r: Request) -> String {
  "migrate-"
  <> files.digest(
    "telegram_action_migrate/v1\n" <> r.candidate <> "\n" <> r.from,
  )
}

fn plan(r: Request) -> Result(Plan, String) {
  use candidate <- result.try(
    engine.find_candidate(engine.get_migration_candidates(), r.candidate)
    |> result.replace_error("backend_unavailable:mirage_migration_engine"),
  )
  use _ <- result.try(
    engine.evaluate_non_negotiable_safety(candidate.name)
    |> result.map_error(fn(_) { "denied:non_negotiable_boundary" })
    |> result.replace(Nil),
  )
  let from = case stage_of(r.from) {
    Ok(stage) -> stage
    Error(_) -> candidate.status
  }
  let moved =
    engine.advance_candidate(
      engine.MigrationCandidate(..candidate, status: from),
    )
  Ok(Plan(candidate, from, moved.status))
}

fn candidate_fields(p: Plan) -> List(#(String, json.Json)) {
  [
    #("candidate", json.string(p.candidate.id)),
    #("name", json.string(p.candidate.name)),
    #("layer", json.string(p.candidate.layer)),
    #("from_stage", json.string(engine.stage_to_string(p.from))),
    #("to_stage", json.string(engine.stage_to_string(p.to))),
    #("stage_changed", json.bool(p.from != p.to)),
    #("projected_ram_saving_mb", json.int(p.candidate.projected_ram_saving_mb)),
    #("projected_speedup_pct", json.float(p.candidate.projected_speedup_pct)),
    #(
      "estimate_basis",
      json.string(engine.estimate_basis_to_string(p.candidate.estimate_basis)),
    ),
    #(
      "admission",
      json.string(engine.admission_status_to_string(p.candidate.admission)),
    ),
  ]
}

fn refusal_json(r: Request, reason: String) -> String {
  case string.starts_with(reason, "denied:") {
    True ->
      json.object([
        #("status", json.string("denied")),
        #("literal", json.string(literal())),
        #("effect_id", json.string(effect_id(r))),
        #("reason", json.string(reason)),
        #("authority", json.string("NONE")),
      ])
    False ->
      json.object([
        #("status", json.string("backend_unavailable")),
        #("literal", json.string(literal())),
        #("effect_id", json.string(effect_id(r))),
        #("backend", json.string("services/mirage_migration_engine")),
        #("authority", json.string("NONE")),
      ])
  }
  |> json.to_string
}

/// Read-only. Reads the engine's built-in catalog (configured projections) and
/// computes the pure stage transition; no benchmark or live state is read,
/// hence "simulated".
pub fn preview(r: Request) -> String {
  case plan(r) {
    Error(reason) -> bound(refusal_json(r, reason))
    Ok(p) ->
      json.object(
        list.flatten([
          [
            #("status", json.string("preview")),
            #("literal", json.string(literal())),
            #("effect_id", json.string(effect_id(r))),
            #("confidence", json.string("simulated")),
            #(
              "state_source",
              json.string(
                "mirage_migration_engine catalog projection; no benchmark or live state read",
              ),
            ),
          ],
          candidate_fields(p),
          [
            #("effect", json.string("stage_transition_record_only")),
            #("migrated", json.bool(False)),
            #("approval_required", json.bool(True)),
            #("authority", json.string("NONE")),
          ],
        ]),
      )
      |> json.to_string
      |> bound
  }
}

fn receipt_json(r: Request) -> Result(String, String) {
  use p <- result.try(plan(r))
  Ok(
    json.object(
      list.flatten([
        [
          #("status", json.string("executed")),
          #("literal", json.string(literal())),
          #("effect_id", json.string(effect_id(r))),
          #("confidence", json.string("simulated")),
        ],
        candidate_fields(p),
        [
          #("effect", json.string("stage_transition_record_only")),
          #("migrated", json.bool(False)),
          #("clock", json.string("not_sampled")),
          #("authority", json.string("NONE")),
        ],
      ]),
    )
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

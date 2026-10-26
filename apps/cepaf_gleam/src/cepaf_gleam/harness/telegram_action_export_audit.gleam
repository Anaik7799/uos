//// ControlledAction adapter for `/export-audit` (contract 20261026-0115).
//// Effect: write ONE bounded audit-METADATA export (counts, observed ts window,
//// per-entry SHA-256 digests; never secret names, callers or secret bytes) into
//// the caller-supplied evidence directory, plus an exclusive-create receipt.
////
//// The live audit source is the `rusty_vault_nif` `vault_audit_tail` NIF, which
//// needs an opened vault handle. Opening a vault is not boundable in
//// development, so `execute` returns `backend_unavailable:rusty_vault_nif`.
//// The real write path is `execute_with`, driven by entries a future vetted
//// reader supplies; it is tested here with in-memory entries. This module
//// grants no authority and is never a reader of vault state.

import cepaf_gleam/harness/files
import cepaf_gleam/vault_audit_query as audit
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import simplifile

pub opaque type Request {
  Request(event: option.Option(String), limit: Int)
}

const literal_text = "/export-audit"

const max_args = 256

const max_reply = 3500

const default_limit = 50

const max_limit = 200

const backend = "rusty_vault_nif"

const events = [
  "put", "get", "destroy", "lease_renew", "unseal", "seal", "get_failed_stale",
]

const usage = "usage: /export-audit [event=<put|get|destroy|lease_renew|unseal|seal|get_failed_stale>] [limit=1..200]"

pub fn literal() -> String {
  literal_text
}

fn parse_limit(text: String) -> Result(Int, Nil) {
  case
    string.byte_size(text) >= 1
    && string.byte_size(text) <= 3
    && list.all(string.to_graphemes(text), fn(c) {
      string.contains("0123456789", c)
    })
  {
    False -> Error(Nil)
    True ->
      case int.parse(text) {
        Ok(n) if n >= 1 && n <= max_limit -> Ok(n)
        _ -> Error(Nil)
      }
  }
}

/// Pure: no vault, no filesystem.
pub fn parse(args: String) -> Result(Request, String) {
  let tokens =
    args
    |> string.split(" ")
    |> list.map(string.trim)
    |> list.filter(fn(t) { t != "" })
  case string.byte_size(args) <= max_args && list.length(tokens) <= 2 {
    False -> Error(usage)
    True ->
      list.try_fold(tokens, Request(option.None, default_limit), fn(acc, t) {
        case t {
          "event=" <> name ->
            case acc.event == option.None && list.contains(events, name) {
              True -> Ok(Request(..acc, event: option.Some(name)))
              False -> Error(usage)
            }
          "limit=" <> n ->
            case parse_limit(n), acc.limit == default_limit {
              Ok(v), True -> Ok(Request(..acc, limit: v))
              _, _ -> Error(usage)
            }
          _ -> Error(usage)
        }
      })
  }
}

fn event_text(r: Request) -> String {
  option.unwrap(r.event, "*")
}

pub fn effect_id(r: Request) -> String {
  files.digest(
    "uos.telegram.action.export_audit.v1|event="
    <> event_text(r)
    <> "|limit="
    <> int.to_string(r.limit),
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

/// Read-only and offline: reads no vault state, so the confidence is
/// `declared` (what the export would contain), not `observed`.
pub fn preview(r: Request) -> String {
  reply([
    #("status", json.string("preview")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("confidence", json.string("declared")),
    #("effect", json.string("write audit-metadata export into evidence_dir")),
    #("event_filter", json.string(event_text(r))),
    #("limit", json.int(r.limit)),
    #(
      "would_export",
      json.array(
        ["counts", "ts_window", "histogram", "entry_sha256_digests"],
        json.string,
      ),
    ),
    #(
      "never_exported",
      json.array(["secret_bytes", "secret_names", "callers"], json.string),
    ),
    #("backend", json.string("unavailable:" <> backend)),
    #("authority", json.string("NONE")),
  ])
}

/// Typed `backend_unavailable` reply for the service to relay.
pub fn unavailable_reply(r: Request) -> String {
  reply([
    #("status", json.string("backend_unavailable")),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect_id(r))),
    #("backend", json.string(backend)),
    #(
      "reason",
      json.string(
        "vault_audit_tail needs an opened vault handle; not boundable in development",
      ),
    ),
    #("authority", json.string("NONE")),
  ])
}

pub fn execute(_r: Request, evidence_dir: String) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> Error("backend_unavailable:" <> backend)
    _ -> Error("evidence_dir_unavailable")
  }
}

fn entry_digest(e: audit.AuditEntry) -> String {
  files.digest(
    int.to_string(e.ts)
    <> "|"
    <> e.event
    <> "|"
    <> e.name
    <> "|"
    <> int.to_string(e.version)
    <> "|"
    <> e.caller,
  )
}

fn export_body(
  r: Request,
  effect: String,
  all: List(audit.AuditEntry),
) -> String {
  let filter =
    audit.AuditFilter(..audit.match_all(), event: case r.event {
      option.Some(e) -> audit.Some(e)
      option.None -> audit.None
    })
  let matched = audit.query(all, filter)
  let chosen = audit.most_recent(matched, r.limit)
  let stamps = list.map(chosen, fn(e) { e.ts })
  let window = case stamps {
    [] -> json.null()
    [first, ..rest] ->
      json.object([
        #("min_ts", json.int(list.fold(rest, first, int.min))),
        #("max_ts", json.int(list.fold(rest, first, int.max))),
      ])
  }
  let h = audit.histogram(chosen)
  json.object([
    #("schema", json.string("uos.vault_audit_export.v1")),
    #("metadata_only", json.bool(True)),
    #("source", json.string(backend <> ".vault_audit_tail")),
    #("effect_id", json.string(effect)),
    #("event_filter", json.string(event_text(r))),
    #("limit", json.int(r.limit)),
    #("source_entries_total", json.int(audit.total(all))),
    #("matched_total", json.int(list.length(matched))),
    #("exported", json.int(list.length(chosen))),
    #("orphan_gets", json.int(list.length(audit.orphan_gets(all)))),
    #("window", window),
    #(
      "histogram",
      json.object([
        #("put", json.int(h.put_count)),
        #("get", json.int(h.get_count)),
        #("destroy", json.int(h.destroy_count)),
        #("lease_renew", json.int(h.lease_renew_count)),
        #("unseal", json.int(h.unseal_count)),
        #("seal", json.int(h.seal_count)),
        #("get_failed_stale", json.int(h.failed_get_count)),
        #("other", json.int(h.other_count)),
      ]),
    ),
    #(
      "entries",
      json.array(chosen, fn(e) {
        json.object([
          #("ts", json.int(e.ts)),
          #("event", json.string(e.event)),
          #("entry_sha256", json.string(entry_digest(e))),
        ])
      }),
    ),
  ])
  |> json.to_string
}

fn receipt_fields(
  status: String,
  effect: String,
  artifact: String,
  artifact_sha: String,
  bytes: Int,
) -> String {
  reply([
    #("status", json.string(status)),
    #("literal", json.string(literal_text)),
    #("effect_id", json.string(effect)),
    #("artifact", json.string(artifact)),
    #("artifact_sha256", json.string(artifact_sha)),
    #("artifact_bytes", json.int(bytes)),
    #("authority", json.string("NONE")),
  ])
}

type Stored {
  Stored(effect: String, artifact: String, sha: String, bytes: Int)
}

fn stored_decoder() -> decode.Decoder(Stored) {
  use effect <- decode.field("effect_id", decode.string)
  use artifact <- decode.field("artifact", decode.string)
  use sha <- decode.field("artifact_sha256", decode.string)
  use bytes <- decode.field("artifact_bytes", decode.int)
  decode.success(Stored(effect, artifact, sha, bytes))
}

fn duplicate(r: Request, dir: String) -> Result(String, String) {
  use raw <- result.try(files.read(dir, effect_id(r) <> ".json"))
  use stored <- result.try(
    json.parse(raw, stored_decoder())
    |> result.replace_error("receipt_unreadable"),
  )
  case stored.effect == effect_id(r) {
    True ->
      Ok(receipt_fields(
        "duplicate",
        stored.effect,
        stored.artifact,
        stored.sha,
        stored.bytes,
      ))
    False -> Error("receipt_identity_mismatch")
  }
}

/// The real, idempotent write path over caller-supplied audit entries.
pub fn execute_with(
  r: Request,
  evidence_dir: String,
  entries: List(audit.AuditEntry),
) -> Result(String, String) {
  case simplifile.is_directory(evidence_dir) {
    Ok(True) -> run(r, evidence_dir, entries)
    _ -> Error("evidence_dir_unavailable")
  }
}

fn run(
  r: Request,
  dir: String,
  entries: List(audit.AuditEntry),
) -> Result(String, String) {
  case duplicate(r, dir) {
    Ok(text) -> Ok(text)
    Error(_) ->
      case simplifile.is_file(dir <> "/" <> effect_id(r) <> ".json") {
        Ok(True) -> Error("receipt_unreadable")
        _ -> create(r, dir, entries)
      }
  }
}

fn create(
  r: Request,
  dir: String,
  entries: List(audit.AuditEntry),
) -> Result(String, String) {
  let name = effect_id(r) <> "-audit-export.json"
  let content = export_body(r, effect_id(r), entries)
  use _ <- result.try(files.create(dir, name, content))
  let body =
    receipt_fields(
      "executed",
      effect_id(r),
      name,
      files.digest(content),
      string.byte_size(content),
    )
  case files.create(dir, effect_id(r) <> ".json", body) {
    Ok(_) -> Ok(body)
    Error(_) -> duplicate(r, dir)
  }
}

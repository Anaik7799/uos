//// Bounded disk ingress for public signed Telegram cancellation action packets.
////
//// The caller supplies a trusted active `telegram_action_profile.Profile`, a
//// bounded root/relative path pair, and a service-measured
//// `telegram_cancellation.Observation`. This module uses the existing bounded file reader, then limits the packet to 64 KiB through
//// single-link safe file ingress and parses the closed
//// `uos.telegram.action-packet.v1` JSON envelope carrying an encoded recovery
//// record plus public signed approval receipts (not raw Telegram update JSON).
////
//// Producing `telegram_cancellation.Prepared` grants no execution or file-data
//// authority. The supervised service must independently bind the measured
//// machine fingerprint to `Context.machine_id` before constructing `observed`
//// and must separately recheck the active profile, canonical store inbox
//// authority (chat/user/update), live host/boot/time, native bridge lease and
//// fencing token, and cancellation target immediately before any effect.
//// No auto-provisioning, retries, or fresh I/O authority claims occur here, and
//// all failures redact to `"action_packet_invalid"`.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_bridge as bridge
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_cancellation_record as record
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/list
import gleam/result
import gleam/string

const invalid_error = "action_packet_invalid"

const expected_schema = "uos.telegram.action-packet.v1"

const max_packet_bytes = 65_536

const min_receipts = 3

const max_receipts = 4

const max_token_bytes = 8192

const ns_per_ms = 1_000_000

pub fn load(
  p: profile.Profile,
  root: String,
  relative: String,
  observed: cancel.Observation,
) -> Result(cancel.Prepared, String) {
  use raw <- result.try(redact(files.read(root, relative)))
  let raw_bytes = string.byte_size(raw)
  use _ <- result.try(check(raw_bytes > 0 && raw_bytes <= max_packet_bytes))
  use #(recovery_json, receipts) <- result.try(parse_packet_envelope(raw))
  use rec <- result.try(redact(record.decode(recovery_json)))
  use _ <- result.try(validate_context_and_binding(p, rec, observed))
  let intent = record.intent(rec)
  let roster = profile.roster(p)
  use evidence <- result.try(
    redact(approval.verify(
      roster,
      intent,
      observed.host,
      observed.boot,
      observed.utc_ms,
      observed.boot_ms,
      receipts,
    )),
  )
  use prepared <- result.try(
    redact(cancel.prepare(
      intent,
      evidence,
      roster,
      record.binding(rec),
      record.target(rec),
      observed,
    )),
  )
  use _ <- result.try(
    check(record.same_request(rec, cancel.recovery_record(prepared))),
  )
  Ok(prepared)
}

fn parse_packet_envelope(
  raw: String,
) -> Result(#(String, List(approval.Receipt)), String) {
  use parsed <- result.try(redact(codec.parse_strict_json(raw)))
  case parsed {
    codec.JsonObject(fields) -> {
      use _ <- result.try(check(list.length(fields) == 3))
      use _ <- result.try(check(closed_unique_keys(fields, [])))
      use schema_value <- result.try(require_field(fields, "schema"))
      use recovery_value <- result.try(require_field(fields, "recovery_json"))
      use receipts_value <- result.try(require_field(fields, "receipts"))
      use schema <- result.try(expect_string(schema_value))
      use _ <- result.try(check(schema == expected_schema))
      use recovery_json <- result.try(expect_string(recovery_value))
      use _ <- result.try(check(string.byte_size(recovery_json) > 0))
      use receipts <- result.try(parse_receipts(receipts_value))
      Ok(#(recovery_json, receipts))
    }
    _ -> fail()
  }
}

fn closed_unique_keys(
  fields: List(#(String, codec.StrictJsonValue)),
  seen: List(String),
) -> Bool {
  case fields {
    [] -> list.length(seen) == 3
    [#(key, _), ..rest] ->
      case key {
        "schema" | "recovery_json" | "receipts" ->
          case list.contains(seen, key) {
            True -> False
            False -> closed_unique_keys(rest, [key, ..seen])
          }
        _ -> False
      }
  }
}

fn require_field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(codec.StrictJsonValue, String) {
  case list.filter(fields, fn(entry) { entry.0 == key }) {
    [#(_, value)] -> Ok(value)
    _ -> fail()
  }
}

fn expect_string(value: codec.StrictJsonValue) -> Result(String, String) {
  case value {
    codec.JsonString(text) -> Ok(text)
    _ -> fail()
  }
}

fn parse_receipts(
  value: codec.StrictJsonValue,
) -> Result(List(approval.Receipt), String) {
  case value {
    codec.JsonArray(items) -> {
      let count = list.length(items)
      use _ <- result.try(check(count >= min_receipts && count <= max_receipts))
      list.try_map(items, parse_receipt)
    }
    _ -> fail()
  }
}

fn parse_receipt(
  item: codec.StrictJsonValue,
) -> Result(approval.Receipt, String) {
  case item {
    codec.JsonArray([codec.JsonString(role), codec.JsonString(token)]) -> {
      let token_bytes = string.byte_size(token)
      use role <- result.try(parse_role(role))
      use _ <- result.try(check(
        token_bytes >= 1 && token_bytes <= max_token_bytes,
      ))
      Ok(approval.Receipt(role, token))
    }
    _ -> fail()
  }
}

fn parse_role(role: String) -> Result(approval.Role, String) {
  case role {
    "codex" -> Ok(approval.Codex)
    "agy" -> Ok(approval.Agy)
    "claude" -> Ok(approval.Claude)
    "operator" -> Ok(approval.Operator)
    _ -> fail()
  }
}

fn validate_context_and_binding(
  p: profile.Profile,
  rec: record.RecoveryRecord,
  observed: cancel.Observation,
) -> Result(Nil, String) {
  let ctx = profile.context(p)
  let binding = record.binding(rec)
  let execution = binding.execution
  use _ <- result.try(
    check(profile.active_at(p, ctx, observed.utc_ms * ns_per_ms)),
  )
  use _ <- result.try(check(
    observed.host == ctx.host && observed.boot == ctx.boot,
  ))
  use _ <- result.try(check(
    binding.bot_id == ctx.bot
    && binding.plan == ctx.plan
    && binding.task == ctx.task
    && binding.worker == ctx.worker
    && binding.attempt == ctx.attempt
    && binding.epoch == ctx.epoch
    && binding.candidate_sha256 == ctx.candidate
    && binding.host == ctx.host
    && binding.boot_id == ctx.boot
    && execution.profile_sha256 == profile.digest(p)
    && bridge.matches_execution(
      profile.request(p),
      execution.mapping_id,
      execution.lease_id,
    ),
  ))
  Ok(Nil)
}

fn check(condition: Bool) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> fail()
  }
}

fn redact(res: Result(a, e)) -> Result(a, String) {
  result.map_error(res, fn(_) { invalid_error })
}

fn fail() -> Result(a, String) {
  Error(invalid_error)
}

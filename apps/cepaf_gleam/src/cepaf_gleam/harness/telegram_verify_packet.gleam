//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_verify_packet</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-JIDOKA-001, SC-TELEGRAM-JOURNEY-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Bounded disk ingress for public signed /verify packets. Same envelope
//// discipline as `telegram_action_packet` (64 KiB, closed three-key JSON,
//// three to four public receipts), but a distinct schema
//// `uos.telegram.verify-packet.v1`, a distinct record schema and the
//// `VerifyProfile` intent kind. A cancellation packet presented here fails on
//// schema before any receipt is examined; a verify packet presented to the
//// cancellation loader fails the same way. Every failure redacts to
//// `verify_packet_invalid`. Producing a `Prepared` grants no execution.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_packet as action_packet
import cepaf_gleam/harness/telegram_action_profile as profile
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_verify_action as verify_action
import cepaf_gleam/harness/telegram_verify_contract as v
import gleam/result
import gleam/string

pub const invalid_error = "verify_packet_invalid"

pub const expected_schema = "uos.telegram.verify-packet.v1"

pub const max_packet_bytes = 65_536

fn redact(res: Result(a, e)) -> Result(a, String) {
  result.map_error(res, fn(_) { invalid_error })
}

fn check(condition: Bool) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(invalid_error)
  }
}

/// Loads and verifies one packet for the reservation `expected`. The record's
/// reservation binding must equal the service's own reservation for the inbox
/// request, so a packet approved for one request cannot run another.
pub fn load(
  p: profile.Profile,
  root: String,
  relative: String,
  observed: cancel.Observation,
  expected: v.Binding,
) -> Result(verify_action.Prepared, String) {
  use raw <- result.try(redact(files.read(root, relative)))
  let raw_bytes = string.byte_size(raw)
  use _ <- result.try(check(raw_bytes > 0 && raw_bytes <= max_packet_bytes))
  use #(record_json, receipts) <- result.try(
    redact(action_packet.parse_envelope(raw, expected_schema, "record_json")),
  )
  use decoded <- result.try(redact(verify_action.decode_record(record_json)))
  use _ <- result.try(check(decoded.verify == expected))
  use _ <- result.try(
    redact(action_packet.validate_binding(p, decoded.binding, observed)),
  )
  let roster = profile.roster(p)
  use evidence <- result.try(
    redact(approval.verify(
      roster,
      decoded.intent,
      observed.host,
      observed.boot,
      observed.utc_ms,
      observed.boot_ms,
      receipts,
    )),
  )
  use prepared <- result.try(
    redact(verify_action.prepare(
      decoded.intent,
      evidence,
      roster,
      decoded.binding,
      decoded.verify,
      observed,
    )),
  )
  // The stored deadline is informational; the receipts decide. They must agree.
  use _ <- result.try(check(
    verify_action.deadline_ms(prepared) == decoded.deadline_ms,
  ))
  Ok(prepared)
}

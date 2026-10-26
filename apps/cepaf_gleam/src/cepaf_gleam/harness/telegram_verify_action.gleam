//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/harness/telegram_verify_action</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-JIDOKA-001, SC-TELEGRAM-JOURNEY-001</stamp-controls></compliance>
//// </c3i-module>
////
//// An approved /verify action: the same signed-approval evidence that a lease
//// cancellation needs, bound to a different effect, namely running the pinned
//// verify guardian for one reserved Sa-plan job. The kind is part of the signed
//// intent (`telegram_action_intent.VerifyProfile`) and of every approval
//// receipt's `purpose`, so a cancellation approval can never be presented as a
//// verification approval or the reverse.
////
//// Producing a `Prepared` grants nothing. The supervised service must still
//// reload the verify profile, re-hash every artifact (`loader.recheck`), check
//// the reservation, the allowlisted chat/user pair and the live clock, and
//// reconcile durable state immediately before any execution.

import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_cancellation_record as record
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_verify_contract as v
import cepaf_gleam/harness/telegram_verify_reservation as reservation
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const record_schema = "uos.telegram.verify-record.v1"

pub const max_record_bytes = 16_384

pub opaque type Prepared {
  Prepared(
    intent: action.Intent,
    binding: action.Binding,
    target: action.Target,
    deadline_ms: Int,
    approval: approval.Verified,
    verify: v.Binding,
  )
}

/// The intent target job: the reservation's Sa-plan job id placed inside the
/// service plan's namespace, because a signed intent may only target jobs of
/// its own plan. The bare `verify.job_id` is what Sa-plan stores.
pub fn target_job(plan: String, verify: v.Binding) -> String {
  plan <> "/" <> verify.job_id
}

/// The Sa-plan job a verify intent must target: the reservation's job (in
/// the plan namespace) and attempt, owned by the worker that will run it.
pub fn target_for(
  plan: String,
  verify: v.Binding,
  worker: String,
  lease_until_ns: Int,
) -> action.Target {
  action.Target(
    job: target_job(plan, verify),
    worker: worker,
    attempt: verify.attempt,
    lease_until_ns: lease_until_ns,
  )
}

fn require(condition: Bool, reason: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn targets(
  intent: action.Intent,
  binding: action.Binding,
  verify: v.Binding,
) -> Bool {
  let t = action.target(intent)
  t.job == target_job(binding.plan, verify) && t.attempt == verify.attempt
}

/// Validates kind, binding, target and approval validity against observed
/// fences. The execution deadline is the approval's (minimum of receipt and
/// roster expiry); nothing here renews it.
pub fn prepare(
  intent: action.Intent,
  evidence: approval.Verified,
  roster: approval.Roster,
  binding: action.Binding,
  verify: v.Binding,
  observed: cancel.Observation,
) -> Result(Prepared, String) {
  use _ <- result.try(require(
    action.kind(intent) == action.VerifyProfile,
    "verify_intent_kind_mismatch",
  ))
  use _ <- result.try(require(
    action.matches_binding(intent, binding),
    "intent_binding_mismatch",
  ))
  use _ <- result.try(require(
    targets(intent, binding, verify),
    "verify_target_mismatch",
  ))
  use _ <- result.try(require(
    approval.still_valid(
      evidence,
      roster,
      intent,
      observed.host,
      observed.boot,
      observed.utc_ms,
      observed.boot_ms,
    ),
    "approval_not_valid",
  ))
  let deadline = approval.execution_deadline_ms(evidence)
  use _ <- result.try(require(
    observed.utc_ms < deadline,
    "approval_deadline_expired",
  ))
  Ok(Prepared(
    intent: intent,
    binding: binding,
    target: action.target(intent),
    deadline_ms: deadline,
    approval: evidence,
    verify: verify,
  ))
}

/// Pure readiness predicate over fresh observed fences. Not an execution
/// grant; durable reconciliation and the artifact recheck remain required.
pub fn ready(
  prepared: Prepared,
  roster: approval.Roster,
  binding: action.Binding,
  verify: v.Binding,
  observed: cancel.Observation,
) -> Bool {
  binding == prepared.binding
  && verify == prepared.verify
  && action.kind(prepared.intent) == action.VerifyProfile
  && action.matches_binding(prepared.intent, binding)
  && targets(prepared.intent, binding, verify)
  && approval.still_valid(
    prepared.approval,
    roster,
    prepared.intent,
    observed.host,
    observed.boot,
    observed.utc_ms,
    observed.boot_ms,
  )
  && observed.utc_ms < prepared.deadline_ms
}

pub fn intent(prepared: Prepared) -> action.Intent {
  prepared.intent
}

pub fn verify_binding(prepared: Prepared) -> v.Binding {
  prepared.verify
}

pub fn deadline_ms(prepared: Prepared) -> Int {
  prepared.deadline_ms
}

pub fn effect_id(prepared: Prepared) -> String {
  action.effect_id(prepared.intent)
}

pub fn receipt_digests(prepared: Prepared) -> List(String) {
  approval.receipt_digests(prepared.approval)
}

/// Closed four-key record: schema, canonical intent bytes, deadline and the
/// reservation binding in its canonical encoding.
pub fn encode_record(prepared: Prepared) -> String {
  encode_parts(prepared.intent, prepared.deadline_ms, prepared.verify)
}

pub fn encode_parts(
  intent: action.Intent,
  deadline_ms: Int,
  verify: v.Binding,
) -> String {
  json.object([
    #("schema", json.string(record_schema)),
    #("intent_json", json.string(action.canonical_json(intent))),
    #("deadline_ms", json.int(deadline_ms)),
    #("verify_json", json.string(reservation.encode(verify))),
  ])
  |> json.to_string
}

pub type Decoded {
  Decoded(
    intent: action.Intent,
    binding: action.Binding,
    target: action.Target,
    deadline_ms: Int,
    verify: v.Binding,
  )
}

fn field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(codec.StrictJsonValue, String) {
  case list.filter(fields, fn(entry) { entry.0 == key }) {
    [#(_, value)] -> Ok(value)
    _ -> Error("verify_record_invalid")
  }
}

fn text(value: codec.StrictJsonValue) -> Result(String, String) {
  case value {
    codec.JsonString(s) -> Ok(s)
    _ -> Error("verify_record_invalid")
  }
}

/// Strict decode of `encode_record` output. The intent is rebuilt through the
/// constructor, so only a byte-identical canonical intent is accepted, and the
/// kind must be VerifyProfile. A cancellation record is refused here by schema
/// and by kind.
pub fn decode_record(raw: String) -> Result(Decoded, String) {
  let size = string.byte_size(raw)
  use _ <- result.try(require(
    size >= 1 && size <= max_record_bytes,
    "verify_record_invalid",
  ))
  use parsed <- result.try(
    codec.parse_strict_json(raw)
    |> result.map_error(fn(_) { "verify_record_invalid" }),
  )
  use fields <- result.try(case parsed {
    codec.JsonObject(fields) -> Ok(fields)
    _ -> Error("verify_record_invalid")
  })
  use _ <- result.try(require(list.length(fields) == 4, "verify_record_invalid"))
  use schema <- result.try(field(fields, "schema") |> result.try(text))
  use intent_json <- result.try(
    field(fields, "intent_json") |> result.try(text),
  )
  use deadline <- result.try(case field(fields, "deadline_ms") {
    Ok(codec.JsonInt(n)) if n > 0 -> Ok(n)
    _ -> Error("verify_record_invalid")
  })
  use verify_json <- result.try(
    field(fields, "verify_json") |> result.try(text),
  )
  use _ <- result.try(require(schema == record_schema, "verify_record_schema"))
  use #(intent, binding, target) <- result.try(
    record.decode_intent_json(intent_json)
    |> result.map_error(fn(_) { "verify_record_invalid" }),
  )
  use _ <- result.try(require(
    action.kind(intent) == action.VerifyProfile,
    "verify_intent_kind_mismatch",
  ))
  use verify <- result.try(
    reservation.decode(verify_json)
    |> result.map_error(fn(_) { "verify_record_invalid" }),
  )
  use _ <- result.try(require(
    targets(intent, binding, verify),
    "verify_target_mismatch",
  ))
  use _ <- result.try(require(
    encode_parts(intent, deadline, verify) == raw,
    "verify_record_not_canonical",
  ))
  Ok(Decoded(intent, binding, target, deadline, verify))
}

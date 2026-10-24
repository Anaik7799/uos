//// Pure Telegram job-lease cancellation preparation, transport envelope
//// construction, and strict transport response decoding.
////
//// IMPORTANT INTEGRATION CONSTRAINTS:
//// - The prepared request (`request_json` and `request_hash`) MUST be durably
////   stored before any cancellation effect is dispatched or executed.
//// - Source-of-truth current-fence checks in the supervisor are still required
////   at execution time; `ready` is a pure predicate requiring fresh caller-
////   supplied observed fences and is not an execution grant.
//// - Pure preparation and decoding in this module do not by themselves satisfy
////   production service integration requirements.
//// - `LeaseRevoked` only attests that the job lease was revoked/cleared
////   (`job_lease_cleared: true`); no process quiescence or task cancellation is
////   claimed (`task_cancelled: false`, `process_quiesced: false`).

import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/telegram_cancellation_record as record
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/json
import gleam/list
import gleam/result
import gleam/string

const transport_request_schema = "uos.telegram.cancel-transport.v1"

const transport_response_schema = "uos.telegram.cancel-transport-response.v1"

const cancel_job_response_schema = "uos.sa-plan.cancel-job-response.v1"

const cancel_receipt_schema = "uos.sa-plan.cancel-job-once.receipt.v1"

const invalid_response = "invalid_cancellation_response"

const max_response_bytes = 16_384

const max_safe_utc_ms = 9_007_199_254_740_991

const ns_per_ms = 1_000_000

pub opaque type Prepared {
  Prepared(
    intent: action.Intent,
    binding: action.Binding,
    target: action.Target,
    deadline_ms: Int,
    request_json: String,
    request_hash: String,
    approval: approval.Verified,
    recovery: record.RecoveryRecord,
  )
}

pub type Observation {
  Observation(host: String, boot: String, utc_ms: Int, boot_ms: Int)
}

pub type Operation {
  Cancel
  Lookup
}

/// Cancellation transport outcome.
/// `LeaseRevoked` attests only that the job lease was revoked; it makes no
/// claim that any task was cancelled or that any process was quiesced.
pub type Outcome {
  LeaseRevoked(recorded_at_ns: Int, replayed: Bool, historical: Bool)
  Absent
  Rejected
}

/// Validates intent/binding/target alignment and approval validity against
/// observed fences, then snapshots the native cancellation request and hash
/// using the approval execution deadline (minimum of receipt and roster expiry)
/// without implicit expiry renewal.
///
/// The resulting request and hash must be durably stored before effect
/// execution, and supervisor source-of-truth current-fence checks remain
/// required.
pub fn prepare(
  intent: action.Intent,
  evidence: approval.Verified,
  roster: approval.Roster,
  binding: action.Binding,
  target: action.Target,
  observed: Observation,
) -> Result(Prepared, String) {
  use _ <- result.try(require(
    action.matches_binding(intent, binding),
    "intent_binding_mismatch",
  ))
  use _ <- result.try(require(
    action.matches_target(intent, target),
    "intent_target_mismatch",
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
  use saved <- result.try(record.new(intent, binding, target, deadline))
  let req_json = record.request_json(saved)
  let req_hash = record.request_hash(saved)
  Ok(Prepared(
    intent: intent,
    binding: binding,
    target: target,
    deadline_ms: deadline,
    request_json: req_json,
    request_hash: req_hash,
    approval: evidence,
    recovery: saved,
  ))
}

/// Pure readiness predicate over a prepared cancellation and caller-supplied
/// fresh observed fences. Does not grant execution authority or replace
/// durable storage before effect and supervisor current-fence verification.
pub fn ready(
  prepared: Prepared,
  roster: approval.Roster,
  binding: action.Binding,
  target: action.Target,
  observed: Observation,
) -> Bool {
  binding == prepared.binding
  && target == prepared.target
  && action.matches_binding(prepared.intent, binding)
  && action.matches_target(prepared.intent, target)
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

/// Builds the closed 3-key transport envelope embedding the exact stored native
/// request JSON without re-serialization drift.
pub fn envelope(prepared: Prepared, operation: Operation) -> String {
  build_envelope(prepared.request_json, operation)
}

fn build_envelope(native_json: String, operation: Operation) -> String {
  let operation_name = case operation {
    Cancel -> "cancel-once"
    Lookup -> "cancellation-result"
  }
  let schema_json = json.to_string(json.string(transport_request_schema))
  let operation_json = json.to_string(json.string(operation_name))
  "{\"schema\":"
  <> schema_json
  <> ",\"operation\":"
  <> operation_json
  <> ",\"request\":"
  <> native_json
  <> "}"
}

pub fn request_json(prepared: Prepared) -> String {
  prepared.request_json
}

pub fn request_hash(prepared: Prepared) -> String {
  prepared.request_hash
}

pub fn deadline_ms(prepared: Prepared) -> Int {
  prepared.deadline_ms
}

/// Strictly decodes and validates a cancellation transport response.
///
/// Historical lookup (`Lookup`) may occur after approval expiry; expiry is not
/// revalidated against `now_utc_ms` to read history, and reading history never
/// grants effect authority. Every receipt must still have been recorded prior
/// to the prepared execution deadline and no later than `now_utc_ms`.
pub fn recovery_record(prepared: Prepared) -> record.RecoveryRecord {
  prepared.recovery
}

/// Read-only lookup envelope; no API accepts a restored record for Cancel.
pub fn recovery_envelope(saved: record.RecoveryRecord) -> String {
  build_envelope(record.request_json(saved), Lookup)
}

pub fn decode_response(
  prepared: Prepared,
  op: Operation,
  raw: String,
  now_utc_ms: Int,
) -> Result(Outcome, String) {
  decode(prepared.recovery, op, raw, now_utc_ms)
}

pub fn decode_recovery_response(
  saved: record.RecoveryRecord,
  raw: String,
  now_utc_ms: Int,
) -> Result(Outcome, String) {
  decode(saved, Lookup, raw, now_utc_ms)
}

fn decode(
  prepared: record.RecoveryRecord,
  op: Operation,
  raw: String,
  now_utc_ms: Int,
) -> Result(Outcome, String) {
  let raw_bytes = string.byte_size(raw)
  let size_ok = raw_bytes >= 1 && raw_bytes <= max_response_bytes
  use _ <- result.try(require(size_ok, invalid_response))

  let now_ok = now_utc_ms >= 0 && now_utc_ms <= max_safe_utc_ms
  use _ <- result.try(require(now_ok, invalid_response))

  use root <- result.try(case codec.parse_strict_json(raw) {
    Ok(value) -> Ok(value)
    Error(_) -> Error(invalid_response)
  })

  use outer <- result.try(
    expect_exact_object(root, [
      "schema",
      "status",
      "result",
      "error",
    ]),
  )
  use outer_schema <- result.try(get_string(outer, "schema"))
  use _ <- result.try(require(
    outer_schema == transport_response_schema,
    invalid_response,
  ))
  use outer_status <- result.try(get_string(outer, "status"))

  case outer_status {
    "rejected" -> {
      use _ <- result.try(expect_null(outer, "result"))
      use error_code <- result.try(get_string(outer, "error"))
      use _ <- result.try(require(
        error_code == "cancel_request_rejected",
        invalid_response,
      ))
      Ok(Rejected)
    }
    "ok" -> {
      use _ <- result.try(expect_null(outer, "error"))
      use result_value <- result.try(get_field(outer, "result"))
      decode_ok_result(prepared, op, result_value, now_utc_ms)
    }
    _ -> Error(invalid_response)
  }
}

fn decode_ok_result(
  prepared: record.RecoveryRecord,
  op: Operation,
  result_value: codec.StrictJsonValue,
  now_utc_ms: Int,
) -> Result(Outcome, String) {
  use inner <- result.try(
    expect_exact_object(result_value, [
      "schema",
      "found",
      "historical",
      "receipt",
    ]),
  )
  use inner_schema <- result.try(get_string(inner, "schema"))
  use _ <- result.try(require(
    inner_schema == cancel_job_response_schema,
    invalid_response,
  ))
  use found <- result.try(get_bool(inner, "found"))
  use historical <- result.try(get_bool(inner, "historical"))

  let expected_historical = case op {
    Cancel -> False
    Lookup -> True
  }
  use _ <- result.try(require(
    historical == expected_historical,
    invalid_response,
  ))

  case found {
    False -> {
      let is_lookup = case op {
        Lookup -> True
        Cancel -> False
      }
      use _ <- result.try(require(is_lookup, invalid_response))
      use _ <- result.try(expect_null(inner, "receipt"))
      Ok(Absent)
    }
    True -> {
      use receipt_value <- result.try(get_field(inner, "receipt"))
      decode_receipt(prepared, receipt_value, now_utc_ms, historical)
    }
  }
}

fn decode_receipt(
  prepared: record.RecoveryRecord,
  receipt_value: codec.StrictJsonValue,
  now_utc_ms: Int,
  historical: Bool,
) -> Result(Outcome, String) {
  use receipt <- result.try(
    expect_exact_object(receipt_value, [
      "mapping_id",
      "command_id",
      "request_hash",
      "recorded_at_ns",
      "replayed",
      "result",
    ]),
  )
  use mapping_id <- result.try(get_string(receipt, "mapping_id"))
  use _ <- result.try(require(
    mapping_id == record.binding(prepared).execution.mapping_id,
    invalid_response,
  ))

  let expected_effect_id = action.effect_id(record.intent(prepared))
  let expected_command_id = "cancel-job:" <> expected_effect_id
  use command_id <- result.try(get_string(receipt, "command_id"))
  use _ <- result.try(require(
    command_id == expected_command_id,
    invalid_response,
  ))

  use receipt_hash <- result.try(get_string(receipt, "request_hash"))
  use _ <- result.try(require(
    receipt_hash == record.request_hash(prepared),
    invalid_response,
  ))

  use recorded_at_ns <- result.try(get_int(receipt, "recorded_at_ns"))
  let max_now_ns = now_utc_ms * ns_per_ms
  let deadline_ns = record.deadline_ms(prepared) * ns_per_ms
  let recorded_ok =
    recorded_at_ns >= 0
    && recorded_at_ns <= max_now_ns
    && recorded_at_ns < deadline_ns
  use _ <- result.try(require(recorded_ok, invalid_response))

  use replayed <- result.try(get_bool(receipt, "replayed"))
  use nested_value <- result.try(get_field(receipt, "result"))
  use _ <- result.try(validate_nested_receipt_result(
    prepared,
    expected_effect_id,
    nested_value,
  ))

  Ok(LeaseRevoked(
    recorded_at_ns: recorded_at_ns,
    replayed: replayed,
    historical: historical,
  ))
}

fn validate_nested_receipt_result(
  prepared: record.RecoveryRecord,
  expected_effect_id: String,
  nested_value: codec.StrictJsonValue,
) -> Result(Nil, String) {
  use nested <- result.try(
    expect_exact_object(nested_value, [
      "schema",
      "operation",
      "status",
      "effect_id",
      "intent_sha256",
      "job_id",
      "matched_attempt",
      "job_lease_cleared",
      "task_cancelled",
      "process_quiesced",
    ]),
  )
  use nested_schema <- result.try(get_string(nested, "schema"))
  use _ <- result.try(require(
    nested_schema == cancel_receipt_schema,
    invalid_response,
  ))

  use operation <- result.try(get_string(nested, "operation"))
  use _ <- result.try(require(operation == "cancel_job_lease", invalid_response))

  use status <- result.try(get_string(nested, "status"))
  use _ <- result.try(require(status == "job_lease_revoked", invalid_response))

  use effect_id <- result.try(get_string(nested, "effect_id"))
  use _ <- result.try(require(effect_id == expected_effect_id, invalid_response))

  let expected_intent_sha256 = action.digest(record.intent(prepared))
  use intent_sha256 <- result.try(get_string(nested, "intent_sha256"))
  use _ <- result.try(require(
    intent_sha256 == expected_intent_sha256,
    invalid_response,
  ))

  use job_id <- result.try(get_string(nested, "job_id"))
  use _ <- result.try(require(
    job_id == record.target(prepared).job,
    invalid_response,
  ))

  use matched_attempt <- result.try(get_int(nested, "matched_attempt"))
  use _ <- result.try(require(
    matched_attempt == record.target(prepared).attempt,
    invalid_response,
  ))

  use job_lease_cleared <- result.try(get_bool(nested, "job_lease_cleared"))
  use _ <- result.try(require(job_lease_cleared, invalid_response))

  use task_cancelled <- result.try(get_bool(nested, "task_cancelled"))
  use _ <- result.try(require(!task_cancelled, invalid_response))

  use process_quiesced <- result.try(get_bool(nested, "process_quiesced"))
  use _ <- result.try(require(!process_quiesced, invalid_response))

  Ok(Nil)
}

fn expect_exact_object(
  value: codec.StrictJsonValue,
  expected_keys: List(String),
) -> Result(List(#(String, codec.StrictJsonValue)), String) {
  case value {
    codec.JsonObject(fields) -> {
      let same_length = list.length(fields) == list.length(expected_keys)
      let all_present =
        list.all(expected_keys, fn(key) { has_key(fields, key) })
      use _ <- result.try(require(same_length && all_present, invalid_response))
      Ok(fields)
    }
    _ -> Error(invalid_response)
  }
}

fn has_key(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Bool {
  case list.find(fields, fn(entry) { entry.0 == key }) {
    Ok(_) -> True
    Error(_) -> False
  }
}

fn get_field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(codec.StrictJsonValue, String) {
  case list.find(fields, fn(entry) { entry.0 == key }) {
    Ok(#(_, value)) -> Ok(value)
    Error(_) -> Error(invalid_response)
  }
}

fn get_string(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(String, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonString(text) -> Ok(text)
    _ -> Error(invalid_response)
  }
}

fn get_int(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Int, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonInt(number) -> Ok(number)
    _ -> Error(invalid_response)
  }
}

fn get_bool(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Bool, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonBool(flag) -> Ok(flag)
    _ -> Error(invalid_response)
  }
}

fn expect_null(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Nil, String) {
  use value <- result.try(get_field(fields, key))
  case value {
    codec.JsonNull -> Ok(Nil)
    _ -> Error(invalid_response)
  }
}

fn require(condition: Bool, message: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(message)
  }
}

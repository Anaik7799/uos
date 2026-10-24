//// Durable recovery data only: no approval or effect authority.
//// Restored records may query history after expiry; they cannot recreate Prepared.
//// The trusted store must bind bot/chat/user/update and exact original input.

import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/json
import gleam/list
import gleam/result
import gleam/string

const record_schema = "uos.telegram.cancellation-record.v1"

const intent_schema = "uos.telegram.action-intent.v2"

const cancel_action = "cancel_job_lease"

const max_record_bytes = 16_384

const max_intent_bytes = 8192

const invalid_record_error = "invalid_cancellation_record"

pub opaque type RecoveryRecord {
  RecoveryRecord(
    intent: action.Intent,
    binding: action.Binding,
    target: action.Target,
    deadline_ms: Int,
    request_json: String,
    request_hash: String,
  )
}

pub fn new(
  intent: action.Intent,
  binding: action.Binding,
  target: action.Target,
  deadline_ms: Int,
) -> Result(RecoveryRecord, String) {
  let matches =
    action.matches_binding(intent, binding)
    && action.matches_target(intent, target)
  case matches {
    False -> Error(invalid_record_error)
    True -> {
      use request_json <- result.try(
        action.native_request(intent, deadline_ms)
        |> result.map_error(fn(_) { invalid_record_error }),
      )
      use request_hash <- result.try(
        action.native_request_hash(intent, deadline_ms)
        |> result.map_error(fn(_) { invalid_record_error }),
      )
      let record =
        RecoveryRecord(
          intent: intent,
          binding: binding,
          target: target,
          deadline_ms: deadline_ms,
          request_json: request_json,
          request_hash: request_hash,
        )
      let encoded_size = string.byte_size(encode(record))
      case encoded_size >= 1 && encoded_size <= max_record_bytes {
        True -> Ok(record)
        False -> Error(invalid_record_error)
      }
    }
  }
}

pub fn intent(record: RecoveryRecord) -> action.Intent {
  record.intent
}

pub fn binding(record: RecoveryRecord) -> action.Binding {
  record.binding
}

pub fn target(record: RecoveryRecord) -> action.Target {
  record.target
}

pub fn deadline_ms(record: RecoveryRecord) -> Int {
  record.deadline_ms
}

pub fn request_json(record: RecoveryRecord) -> String {
  record.request_json
}

pub fn request_hash(record: RecoveryRecord) -> String {
  record.request_hash
}

pub fn same_request(a: RecoveryRecord, b: RecoveryRecord) -> Bool {
  a.deadline_ms == b.deadline_ms
  && a.request_hash == b.request_hash
  && a.request_json == b.request_json
  && a.binding == b.binding
  && a.target == b.target
  && encode(a) == encode(b)
}

pub fn encode(record: RecoveryRecord) -> String {
  json.object([
    #("schema", json.string(record_schema)),
    #("intent_json", json.string(action.canonical_json(record.intent))),
    #("deadline_ms", json.int(record.deadline_ms)),
    #("request_json", json.string(record.request_json)),
    #("request_hash", json.string(record.request_hash)),
  ])
  |> json.to_string
}

pub fn decode(raw: String) -> Result(RecoveryRecord, String) {
  let raw_size = string.byte_size(raw)
  case raw_size >= 1 && raw_size <= max_record_bytes {
    False -> Error(invalid_record_error)
    True ->
      case codec.parse_strict_json(raw) {
        Ok(codec.JsonObject(fields)) -> decode_outer_fields(fields)
        _ -> Error(invalid_record_error)
      }
  }
}

fn decode_outer_fields(
  fields: List(#(String, codec.StrictJsonValue)),
) -> Result(RecoveryRecord, String) {
  case list.length(fields) == 5 {
    False -> Error(invalid_record_error)
    True -> {
      use schema <- result.try(require_string_field(fields, "schema"))
      use intent_json <- result.try(require_string_field(fields, "intent_json"))
      use deadline_ms <- result.try(require_int_field(fields, "deadline_ms"))
      use request_json <- result.try(require_string_field(
        fields,
        "request_json",
      ))
      use request_hash <- result.try(require_string_field(
        fields,
        "request_hash",
      ))
      case schema == record_schema {
        False -> Error(invalid_record_error)
        True -> {
          use #(recreated_intent, binding, target) <- result.try(
            decode_intent_json(intent_json),
          )
          use record <- result.try(new(
            recreated_intent,
            binding,
            target,
            deadline_ms,
          ))
          let matches_stored =
            record.request_json == request_json
            && record.request_hash == request_hash
          case matches_stored {
            True -> Ok(record)
            False -> Error(invalid_record_error)
          }
        }
      }
    }
  }
}

fn decode_intent_json(
  raw_intent_json: String,
) -> Result(#(action.Intent, action.Binding, action.Target), String) {
  let size = string.byte_size(raw_intent_json)
  case size >= 1 && size <= max_intent_bytes {
    False -> Error(invalid_record_error)
    True ->
      case codec.parse_strict_json(raw_intent_json) {
        Ok(codec.JsonArray([
          codec.JsonString(schema),
          codec.JsonString(action_kind),
          codec.JsonInt(bot_id),
          codec.JsonInt(chat_id),
          codec.JsonInt(user_id),
          codec.JsonInt(update_id),
          codec.JsonString(plan_id),
          codec.JsonString(task_id),
          codec.JsonString(worker_id),
          codec.JsonInt(attempt),
          codec.JsonInt(epoch),
          codec.JsonString(candidate_sha256),
          codec.JsonString(host_id),
          codec.JsonString(boot_id),
          codec.JsonString(mapping_id),
          codec.JsonString(lease_id),
          codec.JsonInt(fence_token),
          codec.JsonString(profile_sha256),
          codec.JsonString(job_id),
          codec.JsonString(target_worker_id),
          codec.JsonInt(target_attempt),
          codec.JsonInt(target_lease_ns),
          codec.JsonInt(created_utc_ms),
          codec.JsonInt(created_boot_ms),
          codec.JsonInt(deadline_utc_ms),
          codec.JsonInt(deadline_boot_ms),
          codec.JsonString(reason),
          codec.JsonString(nonce),
        ])) -> {
          case schema == intent_schema && action_kind == cancel_action {
            False -> Error(invalid_record_error)
            True -> {
              let execution =
                action.Execution(
                  mapping_id,
                  lease_id,
                  fence_token,
                  profile_sha256,
                )
              let binding =
                action.Binding(
                  bot_id,
                  chat_id,
                  user_id,
                  update_id,
                  plan_id,
                  task_id,
                  worker_id,
                  attempt,
                  epoch,
                  candidate_sha256,
                  host_id,
                  boot_id,
                  execution,
                )
              let target =
                action.Target(
                  job_id,
                  target_worker_id,
                  target_attempt,
                  target_lease_ns,
                )
              let window =
                action.Window(
                  created_utc_ms,
                  created_boot_ms,
                  deadline_utc_ms,
                  deadline_boot_ms,
                )
              use recreated <- result.try(
                action.new(binding, target, window, reason, nonce)
                |> result.map_error(fn(_) { invalid_record_error }),
              )
              case action.canonical_json(recreated) == raw_intent_json {
                True -> Ok(#(recreated, binding, target))
                False -> Error(invalid_record_error)
              }
            }
          }
        }
        _ -> Error(invalid_record_error)
      }
  }
}

fn require_string_field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(String, String) {
  case list.key_find(fields, key) {
    Ok(codec.JsonString(value)) -> Ok(value)
    _ -> Error(invalid_record_error)
  }
}

fn require_int_field(
  fields: List(#(String, codec.StrictJsonValue)),
  key: String,
) -> Result(Int, String) {
  case list.key_find(fields, key) {
    Ok(codec.JsonInt(value)) -> Ok(value)
    _ -> Error(invalid_record_error)
  }
}

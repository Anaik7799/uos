//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Authority Protocol & Argv Builders
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/harness/telegram_authority_protocol</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Pure Exact Argv Builders & Strict Response Decoders</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HARNESS-MCP-001, SC-JIDOKA-001, SC-RISK-CHECK-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// -----------------------------------------------------------------------------
// Identifier & Bounds Validation (No NUL Bytes, Strict Bounds)
// -----------------------------------------------------------------------------

pub fn validate_identifier(name: String, max_len: Int) -> Result(String, String) {
  let trimmed = string.trim(name)
  case trimmed == "" {
    True -> Error("identifier_must_not_be_empty")
    False -> {
      case string.byte_size(trimmed) > max_len {
        True -> Error("identifier_exceeds_max_length_" <> int.to_string(max_len))
        False -> {
          case string.contains(trimmed, "\u{0000}") {
            True -> Error("identifier_must_not_contain_nul_byte")
            False -> Ok(trimmed)
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Coordinator Exact Argv Builders
// -----------------------------------------------------------------------------

pub fn build_coordinator_register_argv(
  session: String,
  workspace: String,
  revision: String,
  tags: String,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use w <- result.try(validate_identifier(workspace, 1024))
  use r <- result.try(validate_identifier(revision, 128))
  use t <- result.try(validate_identifier(tags, 512))
  use op <- result.try(validate_identifier(op_id, 128))
  Ok(["register", s, "service", w, r, t, op])
}

pub fn build_coordinator_claim_runtime_argv(
  session: String,
  ttl_seconds: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use op <- result.try(validate_identifier(op_id, 128))
  case ttl_seconds <= 0 {
    True -> Error("ttl_seconds_must_be_positive")
    False ->
      Ok(["claim", s, "runtime:telegram-bridge", int.to_string(ttl_seconds), op])
  }
}

pub fn build_coordinator_claim_task_argv(
  session: String,
  task_resource: String,
  ttl_seconds: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use res <- result.try(validate_identifier(task_resource, 256))
  use op <- result.try(validate_identifier(op_id, 128))
  case ttl_seconds <= 0 {
    True -> Error("ttl_seconds_must_be_positive")
    False ->
      Ok(["claim", s, res, int.to_string(ttl_seconds), op])
  }
}

pub fn build_coordinator_renew_argv(
  session: String,
  resource: String,
  epoch: Int,
  ttl_seconds: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use res <- result.try(validate_identifier(resource, 256))
  use op <- result.try(validate_identifier(op_id, 128))
  case epoch <= 0 {
    True -> Error("epoch_must_be_positive")
    False -> {
      case ttl_seconds <= 0 {
        True -> Error("ttl_seconds_must_be_positive")
        False ->
          Ok([
            "renew",
            s,
            res,
            int.to_string(epoch),
            int.to_string(ttl_seconds),
            op,
          ])
      }
    }
  }
}

pub fn build_coordinator_release_argv(
  session: String,
  resource: String,
  epoch: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use res <- result.try(validate_identifier(resource, 256))
  use op <- result.try(validate_identifier(op_id, 128))
  case epoch <= 0 {
    True -> Error("epoch_must_be_positive")
    False -> Ok(["release", s, res, int.to_string(epoch), op])
  }
}

pub fn build_coordinator_heartbeat_argv(
  session: String,
  revision: String,
  tags: String,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use r <- result.try(validate_identifier(revision, 128))
  use t <- result.try(validate_identifier(tags, 512))
  use op <- result.try(validate_identifier(op_id, 128))
  Ok(["heartbeat", s, r, t, op])
}

pub fn build_coordinator_retire_argv(
  session: String,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_identifier(session, 128))
  use op <- result.try(validate_identifier(op_id, 128))
  Ok(["retire", s, op])
}

// -----------------------------------------------------------------------------
// Coordinator Strict Response Decoder
// -----------------------------------------------------------------------------

pub type CoordinatorReceipt {
  CoordinatorReceipt(
    ok: Bool,
    operation_id: String,
    operation: String,
    epoch: Int,
    expires_us: Int,
  )
}

fn coordinator_receipt_decoder() -> decode.Decoder(CoordinatorReceipt) {
  use ok <- decode.field("ok", decode.bool)
  use op_id <- decode.field("operation_id", decode.string)
  use op <- decode.field("operation", decode.string)
  use epoch <- decode.optional_field("epoch", 0, decode.int)
  use expires <- decode.optional_field("expires_us", 0, decode.int)
  decode.success(CoordinatorReceipt(
    ok: ok,
    operation_id: op_id,
    operation: op,
    epoch: epoch,
    expires_us: expires,
  ))
}

pub fn decode_coordinator_response(
  raw_json: String,
  expected_op_id: String,
  expected_op: String,
  current_boot_us: Int,
) -> Result(CoordinatorReceipt, String) {
  case json.parse(raw_json, coordinator_receipt_decoder()) {
    Error(err) -> Error("malformed_coordinator_response_json: " <> string.inspect(err))
    Ok(receipt) -> {
      case receipt.ok {
        False -> Error("coordinator_response_ok_false")
        True -> {
          case receipt.operation_id == expected_op_id {
            False ->
              Error("operation_id_mismatch: expected " <> expected_op_id <> " but got " <> receipt.operation_id)
            True -> {
              case receipt.operation == expected_op {
                False ->
                  Error("operation_mismatch: expected " <> expected_op <> " but got " <> receipt.operation)
                True -> {
                  case receipt.operation {
                    "claim" | "renew" | "release" -> {
                      case receipt.epoch <= 0 {
                        True -> Error("coordinator_epoch_must_be_positive")
                        False -> {
                          case receipt.operation == "release" {
                            True -> Ok(receipt)
                            False -> {
                              case receipt.expires_us <= current_boot_us {
                                True -> Error("coordinator_lease_expiration_must_be_in_future")
                                False -> Ok(receipt)
                              }
                            }
                          }
                        }
                      }
                    }
                    _ -> Ok(receipt)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Sa-Plan Exact Argv Builders
// -----------------------------------------------------------------------------

pub fn build_saplan_create_plan_argv(
  request_plan: String,
) -> Result(List(String), String) {
  use p <- result.try(validate_identifier(request_plan, 256))
  Ok(["--format", "json", "plan", "create", p, p, "Bounded Telegram request"])
}

pub fn build_saplan_create_task_argv(
  request_plan: String,
  request_name: String,
) -> Result(List(String), String) {
  use p <- result.try(validate_identifier(request_plan, 256))
  use n <- result.try(validate_identifier(request_name, 256))
  Ok([
    "--format",
    "json",
    "task",
    "create",
    p,
    "EXECUTE",
    n,
    "Bounded Telegram read and delivery",
    "-",
    "-",
    "10",
  ])
}

pub fn build_saplan_claim_argv(
  service_worker: String,
  request_plan: String,
) -> Result(List(String), String) {
  use w <- result.try(validate_identifier(service_worker, 128))
  use p <- result.try(validate_identifier(request_plan, 256))
  Ok([
    "--format",
    "json",
    "task",
    "claim",
    w,
    p,
    "120000000000",
    "EXECUTE",
  ])
}

pub fn build_saplan_release_argv(
  service_worker: String,
  request_plan: String,
  attempt: Int,
) -> Result(List(String), String) {
  use w <- result.try(validate_identifier(service_worker, 128))
  use p <- result.try(validate_identifier(request_plan, 256))
  case attempt <= 0 {
    True -> Error("attempt_must_be_positive")
    False ->
      Ok(["task", "release", p, "EXECUTE", w, int.to_string(attempt)])
  }
}

// -----------------------------------------------------------------------------
// Sa-Plan Claim Response Decoder (String-Valued Strict Schema)
// -----------------------------------------------------------------------------

pub type SaPlanClaimReceipt {
  SaPlanClaimReceipt(
    claimed: Bool,
    task: String,
    attempt: Int,
    lease_until_ns: Int,
  )
}

type RawClaimStrings {
  RawClaimStrings(
    claimed_str: String,
    task_str: String,
    attempt_str: String,
    lease_until_str: String,
  )
}

fn raw_claim_decoder() -> decode.Decoder(RawClaimStrings) {
  use claimed <- decode.field("claimed", decode.string)
  use task <- decode.field("task", decode.string)
  use attempt <- decode.field("attempt", decode.string)
  use lease_until <- decode.field("lease_until_ns", decode.string)
  decode.success(RawClaimStrings(
    claimed_str: claimed,
    task_str: task,
    attempt_str: attempt,
    lease_until_str: lease_until,
  ))
}

pub fn decode_saplan_claim_response(
  raw_json: String,
  expected_task: String,
  current_ns: Int,
) -> Result(SaPlanClaimReceipt, String) {
  case json.parse(raw_json, raw_claim_decoder()) {
    Error(err) -> Error("malformed_saplan_claim_json: " <> string.inspect(err))
    Ok(raw) -> {
      case raw.claimed_str {
        "true" -> {
          case raw.task_str == expected_task {
            False ->
              Error("task_mismatch: expected " <> expected_task <> " but got " <> raw.task_str)
            True -> {
              case int.parse(raw.attempt_str) {
                Error(Nil) -> Error("attempt_is_not_a_valid_decimal_integer")
                Ok(attempt) -> {
                  case attempt <= 0 {
                    True -> Error("attempt_must_be_positive")
                    False -> {
                      case int.parse(raw.lease_until_str) {
                        Error(Nil) -> Error("lease_until_ns_is_not_a_valid_decimal_integer")
                        Ok(lease_ns) -> {
                          case lease_ns <= current_ns {
                            True -> Error("lease_until_ns_must_be_in_future")
                            False ->
                              Ok(SaPlanClaimReceipt(
                                claimed: True,
                                task: raw.task_str,
                                attempt: attempt,
                                lease_until_ns: lease_ns,
                              ))
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        "false" -> Error("task_claim_refused_claimed_false")
        other -> Error("unrecognized_claimed_value: " <> other)
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Risk Adapter Protocol (Fail Closed: Missing -> Error, No Forged Pass)
// -----------------------------------------------------------------------------

pub type RiskAdapter =
  fn(String, String) -> Result(String, String)

pub fn evaluate_request_risk(
  adapter: Option(RiskAdapter),
  plan: String,
  task: String,
) -> Result(String, String) {
  case adapter {
    None -> Error("missing_risk_adapter_refused_no_forged_pass")
    Some(eval_fn) -> eval_fn(plan, task)
  }
}

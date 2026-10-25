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
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

// -----------------------------------------------------------------------------
// Constants & Bounds
// -----------------------------------------------------------------------------

pub const max_payload_bytes = 65_536
pub const max_coordinator_ttl_seconds = 3600
pub const min_coordinator_ttl_seconds = 1

// -----------------------------------------------------------------------------
// Exact Downstream Identifier & Argument Validators (No Silent Normalization)
// -----------------------------------------------------------------------------

/// Exact coordinator identifier validation matching downstream coordinator:
/// Non-empty, length <= 128, characters in [a-zA-Z0-9-_.:] only.
/// Absolutely NO trimming: leading/trailing/embedded whitespace fails closed.
pub fn validate_coordinator_identifier(name: String) -> Result(String, String) {
  case name == "" {
    True -> Error("invalid_coordinator_identifier")
    False -> {
      case string.length(name) > 128 {
        True -> Error("invalid_coordinator_identifier")
        False -> {
          let chars_ok =
            string.to_graphemes(name)
            |> list.all(fn(c) {
              string.contains(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:",
                c,
              )
            })
          case chars_ok {
            True -> Ok(name)
            False -> Error("invalid_coordinator_identifier")
          }
        }
      }
    }
  }
}

/// Generic backwards-compatible identifier validator:
/// Non-empty, byte_size <= max_len, no NUL byte, characters in [a-zA-Z0-9-_.:].
/// NO trimming.
pub fn validate_identifier(name: String, max_len: Int) -> Result(String, String) {
  case name == "" {
    True -> Error("identifier_must_not_be_empty")
    False -> {
      case string.byte_size(name) > max_len {
        True -> Error("identifier_exceeds_max_length_" <> int.to_string(max_len))
        False -> {
          case string.contains(name, "\u{0000}") {
            True -> Error("identifier_must_not_contain_nul_byte")
            False -> {
              let chars_ok =
                string.to_graphemes(name)
                |> list.all(fn(c) {
                  string.contains(
                    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:",
                    c,
                  )
                })
              case chars_ok {
                True -> Ok(name)
                False -> Error("identifier_contains_invalid_characters")
              }
            }
          }
        }
      }
    }
  }
}

/// Workspace path must be an absolute path without lexical aliases ('..'),
/// without NUL bytes, length <= 1024, no spaces.
pub fn validate_workspace(path: String) -> Result(String, String) {
  case string.starts_with(path, "/") {
    False -> Error("invalid_workspace_path")
    True -> {
      case string.length(path) > 1024 || string.contains(path, "\u{0000}") || string.contains(path, " ") {
        True -> Error("invalid_workspace_path")
        False -> {
          case list.contains(string.split(path, "/"), "..") {
            True -> Error("invalid_workspace_path")
            False -> Ok(path)
          }
        }
      }
    }
  }
}

/// Revision validator: non-empty, length <= 128, characters in [a-zA-Z0-9-_.:@]
pub fn validate_revision(rev: String) -> Result(String, String) {
  case rev == "" || string.length(rev) > 128 {
    True -> Error("invalid_revision")
    False -> {
      let chars_ok =
        string.to_graphemes(rev)
        |> list.all(fn(c) {
          string.contains(
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:@",
            c,
          )
        })
      case chars_ok {
        True -> Ok(rev)
        False -> Error("invalid_revision")
      }
    }
  }
}

/// Tags validator: either "-" or comma-separated tokens without whitespace or NUL, length <= 512
pub fn validate_tags(tags: String) -> Result(String, String) {
  case tags == "-" {
    True -> Ok("-")
    False -> {
      case tags == "" || string.length(tags) > 512 || string.contains(tags, "\u{0000}") || string.contains(tags, " ") {
        True -> Error("invalid_tags")
        False -> {
          let chars_ok =
            string.to_graphemes(tags)
            |> list.all(fn(c) {
              string.contains(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:,/",
                c,
              )
            })
          case chars_ok {
            True -> Ok(tags)
            False -> Error("invalid_tags")
          }
        }
      }
    }
  }
}

/// Coordinator TTL bounds: 1 <= seconds <= 3600
pub fn validate_coordinator_ttl(ttl_seconds: Int) -> Result(Int, String) {
  case ttl_seconds >= min_coordinator_ttl_seconds && ttl_seconds <= max_coordinator_ttl_seconds {
    True -> Ok(ttl_seconds)
    False -> Error("ttl_seconds_out_of_bounds_1_to_3600")
  }
}

/// Coordinator epoch: strictly positive integer
pub fn validate_coordinator_epoch(epoch: Int) -> Result(Int, String) {
  case epoch > 0 {
    True -> Ok(epoch)
    False -> Error("epoch_must_be_positive")
  }
}

/// Coordinator resource:
/// "integration/main", "runtime:telegram-bridge", "task:<id>", "runtime:<id>", "workspace:<path>"
pub fn validate_coordinator_resource(res: String) -> Result(String, String) {
  case res {
    "integration/main" -> Ok(res)
    "runtime:telegram-bridge" -> Ok(res)
    "task:" <> id -> {
      case validate_coordinator_identifier(id) {
        Ok(_) -> Ok(res)
        Error(_) -> Error("invalid_coordinator_resource")
      }
    }
    "runtime:" <> id -> {
      case validate_coordinator_identifier(id) {
        Ok(_) -> Ok(res)
        Error(_) -> Error("invalid_coordinator_resource")
      }
    }
    "workspace:" <> path -> {
      case validate_workspace(path) {
        Ok(_) -> Ok(res)
        Error(_) -> Error("invalid_coordinator_resource")
      }
    }
    _ -> Error("invalid_coordinator_resource")
  }
}

/// Sa-Plan naming: plan and task identifiers, non-empty, length <= 256, [a-zA-Z0-9-_./:]
pub fn validate_saplan_name(name: String) -> Result(String, String) {
  case name == "" || string.length(name) > 256 || string.contains(name, "\u{0000}") || string.contains(name, " ") {
    True -> Error("invalid_saplan_name")
    False -> {
      case list.contains(string.split(name, "/"), "..") {
        True -> Error("invalid_saplan_name")
        False -> {
          let chars_ok =
            string.to_graphemes(name)
            |> list.all(fn(c) {
              string.contains(
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:",
                c,
              )
            })
          case chars_ok {
            True -> Ok(name)
            False -> Error("invalid_saplan_name")
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Strict Positive Decimal Parser (No Signs, No Leading Zeros, No Whitespace)
// -----------------------------------------------------------------------------

/// Parses a strictly positive decimal integer string with canonical representation:
/// - Rejects signs ('+', '-')
/// - Rejects leading zeros ('01', '0')
/// - Rejects whitespace (' 1', '1 ')
/// - Rejects non-digits
/// - Rejects strings longer than 20 digits
/// - Ensures int.to_string(n) == str and n > 0
pub fn parse_strict_positive_decimal(str: String) -> Result(Int, Nil) {
  case str == "" || string.length(str) > 20 {
    True -> Error(Nil)
    False -> {
      case string.starts_with(str, "0") {
        True -> Error(Nil)
        False -> {
          let all_digits =
            string.to_graphemes(str)
            |> list.all(fn(c) { string.contains("0123456789", c) })
          case all_digits {
            False -> Error(Nil)
            True -> {
              case int.parse(str) {
                Ok(n) if n > 0 -> {
                  case int.to_string(n) == str {
                    True -> Ok(n)
                    False -> Error(Nil)
                  }
                }
                _ -> Error(Nil)
              }
            }
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
  use s <- result.try(validate_coordinator_identifier(session))
  use w <- result.try(validate_workspace(workspace))
  use r <- result.try(validate_revision(revision))
  use t <- result.try(validate_tags(tags))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["register", s, "service", w, r, t, op])
}

pub fn build_coordinator_claim_runtime_argv(
  session: String,
  ttl_seconds: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_coordinator_identifier(session))
  use ttl <- result.try(validate_coordinator_ttl(ttl_seconds))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["claim", s, "runtime:telegram-bridge", int.to_string(ttl), op])
}

pub fn build_coordinator_claim_task_argv(
  session: String,
  task_resource: String,
  ttl_seconds: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_coordinator_identifier(session))
  use res <- result.try(validate_coordinator_resource(task_resource))
  use ttl <- result.try(validate_coordinator_ttl(ttl_seconds))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["claim", s, res, int.to_string(ttl), op])
}

pub fn build_coordinator_renew_argv(
  session: String,
  resource: String,
  epoch: Int,
  ttl_seconds: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_coordinator_identifier(session))
  use res <- result.try(validate_coordinator_resource(resource))
  use ep <- result.try(validate_coordinator_epoch(epoch))
  use ttl <- result.try(validate_coordinator_ttl(ttl_seconds))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["renew", s, res, int.to_string(ep), int.to_string(ttl), op])
}

pub fn build_coordinator_release_argv(
  session: String,
  resource: String,
  epoch: Int,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_coordinator_identifier(session))
  use res <- result.try(validate_coordinator_resource(resource))
  use ep <- result.try(validate_coordinator_epoch(epoch))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["release", s, res, int.to_string(ep), op])
}

pub fn build_coordinator_heartbeat_argv(
  session: String,
  revision: String,
  tags: String,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_coordinator_identifier(session))
  use r <- result.try(validate_revision(revision))
  use t <- result.try(validate_tags(tags))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["heartbeat", s, r, t, op])
}

pub fn build_coordinator_retire_argv(
  session: String,
  op_id: String,
) -> Result(List(String), String) {
  use s <- result.try(validate_coordinator_identifier(session))
  use op <- result.try(validate_coordinator_identifier(op_id))
  Ok(["retire", s, op])
}

// -----------------------------------------------------------------------------
// Coordinator Strict Response Decoder (Redacted Errors, expires_boot_us)
// -----------------------------------------------------------------------------

pub type CoordinatorReceipt {
  CoordinatorReceipt(
    ok: Bool,
    operation_id: String,
    operation: String,
    epoch: Int,
    expires_boot_us: Int,
  )
}

fn coordinator_receipt_decoder() -> decode.Decoder(CoordinatorReceipt) {
  use ok <- decode.field("ok", decode.bool)
  use op_id <- decode.field("operation_id", decode.string)
  use op <- decode.field("operation", decode.string)
  use epoch <- decode.field("epoch", decode.int)
  use expires_boot_us <- decode.field("expires_boot_us", decode.int)
  decode.success(CoordinatorReceipt(
    ok: ok,
    operation_id: op_id,
    operation: op,
    epoch: epoch,
    expires_boot_us: expires_boot_us,
  ))
}

pub fn decode_coordinator_response(
  raw_json: String,
  expected_op_id: String,
  expected_op: String,
  current_boot_us: Int,
) -> Result(CoordinatorReceipt, String) {
  case string.byte_size(raw_json) > max_payload_bytes {
    True -> Error("response_payload_exceeds_max_bytes")
    False -> {
      case json.parse(raw_json, coordinator_receipt_decoder()) {
        Error(_) -> Error("malformed_coordinator_response_json")
        Ok(receipt) -> {
          case receipt.ok {
            False -> Error("coordinator_response_ok_false")
            True -> {
              case receipt.operation_id == expected_op_id {
                False -> Error("operation_id_mismatch")
                True -> {
                  case receipt.operation == expected_op {
                    False -> Error("operation_mismatch")
                    True -> {
                      case receipt.operation {
                        "claim" | "renew" -> {
                          case receipt.epoch <= 0 {
                            True -> Error("coordinator_epoch_must_be_positive")
                            False -> {
                              case receipt.expires_boot_us <= current_boot_us {
                                True -> Error("coordinator_lease_expiration_must_be_in_future")
                                False -> Ok(receipt)
                              }
                            }
                          }
                        }
                        "release" -> {
                          case receipt.epoch <= 0 {
                            True -> Error("coordinator_epoch_must_be_positive")
                            False -> Ok(receipt)
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
  }
}

// -----------------------------------------------------------------------------
// Sa-Plan Exact Argv Builders
// -----------------------------------------------------------------------------

pub fn build_saplan_create_plan_argv(
  request_plan: String,
) -> Result(List(String), String) {
  use p <- result.try(validate_saplan_name(request_plan))
  Ok(["--format", "json", "plan", "create", p, p, "Bounded Telegram request"])
}

pub fn build_saplan_create_task_argv(
  request_plan: String,
  request_name: String,
) -> Result(List(String), String) {
  use p <- result.try(validate_saplan_name(request_plan))
  use n <- result.try(validate_saplan_name(request_name))
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
  use w <- result.try(validate_coordinator_identifier(service_worker))
  use p <- result.try(validate_saplan_name(request_plan))
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
  use w <- result.try(validate_coordinator_identifier(service_worker))
  use p <- result.try(validate_saplan_name(request_plan))
  use a <- result.try(validate_coordinator_epoch(attempt))
  Ok(["task", "release", p, "EXECUTE", w, int.to_string(a)])
}

// -----------------------------------------------------------------------------
// Sa-Plan Claim Response Decoder (Strict Decimal, Redacted Errors)
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
  case string.byte_size(raw_json) > max_payload_bytes {
    True -> Error("response_payload_exceeds_max_bytes")
    False -> {
      case json.parse(raw_json, raw_claim_decoder()) {
        Error(_) -> Error("malformed_saplan_claim_json")
        Ok(raw) -> {
          case raw.claimed_str {
            "true" -> {
              case raw.task_str == expected_task {
                False -> Error("task_mismatch")
                True -> {
                  case parse_strict_positive_decimal(raw.attempt_str) {
                    Error(Nil) -> Error("attempt_is_not_a_valid_decimal_integer")
                    Ok(attempt) -> {
                      case parse_strict_positive_decimal(raw.lease_until_str) {
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
            "false" -> Error("task_claim_refused_claimed_false")
            _ -> Error("unrecognized_claimed_value")
          }
        }
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

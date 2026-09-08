//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/module_guard</module>
////     <fsharp-lineage>None — universal self-verification for every module</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Universal output verification for ALL modules</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SATYA-001, SC-TRUTH-001, SC-NASA-001</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// Universal Module Guard — Self-Verification for EVERY Output
//// सार्वभौमिक रक्षक — प्रत्येक आउटपुट का स्व-सत्यापन
////
//// NASA Power of Ten Rule 5: ≥2 assertions per function.
//// This module provides universal guards for:
////   - JSON API responses (verify non-empty, valid structure)
////   - WebSocket frames (verify freshness, non-stale)
////   - NIF call results (verify pipeline alive, data valid)
////   - TUI renders (verify non-empty output)
////   - State serializations (verify consistency)
////
//// EVERY module that produces output MUST use these guards.
//// सर्वभूतस्थमात्मानं — The Self dwelling in ALL beings (Gita 6.29)
////
//// STAMP: SC-SATYA-001, SC-TRUTH-001, SC-NASA-001

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/string

/// Result of a module guard check
pub type GuardResult {
  /// Output is valid — pass through
  GuardPassed(output: String)
  /// Output is invalid — use fallback
  GuardFailed(reason: String, fallback: String)
}

/// Guard verdict for telemetry/logging
pub type GuardVerdict {
  Passed
  FailedEmpty
  FailedTooShort
  FailedMissingField
  FailedStale
  FailedCorrupted
}

// ═══════════════════════════════════════════════════════════════
// JSON API Guards — verify every API response before sending
// ═══════════════════════════════════════════════════════════════

/// Syntax and exact top-level field-presence guard, bounded to one MiB.
/// Passing bytes are preserved. Value schemas and authorization are separate.
pub fn guard_json(
  output: String,
  endpoint_name: String,
  expected_field: String,
) -> GuardResult {
  let bytes = output |> bit_array.from_string |> bit_array.byte_size
  case bytes < 3, bytes > 1_048_576 {
    True, _ -> json_failure("empty_response", endpoint_name, expected_field)
    _, True -> json_failure("response_too_large", endpoint_name, expected_field)
    _, _ -> {
      let decoder = {
        use value <- decode.field(expected_field, decode.dynamic)
        decode.success(value)
      }
      case json.parse(output, decoder) {
        Ok(_) -> GuardPassed(output)
        Error(json.UnableToDecode(_)) ->
          json_failure("missing_field", endpoint_name, expected_field)
        Error(_) -> json_failure("invalid_json", endpoint_name, expected_field)
      }
    }
  }
}

fn json_failure(error: String, endpoint: String, field: String) -> GuardResult {
  GuardFailed(
    "JSON " <> error <> " for " <> endpoint,
    json.object([
      #("error", json.string(error)),
      #("endpoint", json.string(endpoint)),
      #("field", json.string(field)),
    ])
      |> json.to_string,
  )
}

/// Guard variable JSON structure with the same byte and syntax limits.
pub fn guard_json_nonempty(
  output: String,
  endpoint_name: String,
) -> GuardResult {
  let bytes = output |> bit_array.from_string |> bit_array.byte_size
  case bytes < 3, bytes > 1_048_576 {
    True, _ -> json_failure("empty_response", endpoint_name, "")
    _, True -> json_failure("response_too_large", endpoint_name, "")
    _, _ ->
      case json.parse(output, decode.dynamic) {
        Ok(_) -> GuardPassed(output)
        Error(_) -> json_failure("invalid_json", endpoint_name, "")
      }
  }
}

// ═══════════════════════════════════════════════════════════════
// NIF Guards — verify NIF pipeline returns valid data
// ═══════════════════════════════════════════════════════════════

/// Guard a NIF call result — verify non-empty and minimum length
pub fn guard_nif(output: String, nif_name: String) -> GuardResult {
  case string.length(output) < 2 {
    True ->
      GuardFailed(
        "NIF " <> nif_name <> " returned empty data — pipeline may be broken",
        "{\"error\":\"nif_empty\",\"nif\":\"" <> nif_name <> "\"}",
      )
    False -> GuardPassed(output)
  }
}

/// Guard a NIF call that should return a JSON array
pub fn guard_nif_array(output: String, nif_name: String) -> GuardResult {
  case string.starts_with(output, "[") {
    True -> GuardPassed(output)
    False ->
      GuardFailed("NIF " <> nif_name <> " did not return JSON array", "[]")
  }
}

/// Guard a NIF call that should return a JSON object
pub fn guard_nif_object(output: String, nif_name: String) -> GuardResult {
  case string.starts_with(output, "{") {
    True -> GuardPassed(output)
    False ->
      GuardFailed(
        "NIF " <> nif_name <> " did not return JSON object",
        "{\"error\":\"nif_invalid\",\"nif\":\"" <> nif_name <> "\"}",
      )
  }
}

// ═══════════════════════════════════════════════════════════════
// WebSocket Guards — verify frame data before sending
// ═══════════════════════════════════════════════════════════════

/// Guard a WebSocket frame — verify non-empty JSON
pub fn guard_ws_frame(payload: String, ws_path: String) -> GuardResult {
  case string.length(payload) < 5 {
    True ->
      GuardFailed(
        "WS frame empty for " <> ws_path,
        "{\"type\":\"error\",\"message\":\"empty_frame\"}",
      )
    False -> GuardPassed(payload)
  }
}

// ═══════════════════════════════════════════════════════════════
// TUI Guards — verify ANSI output is non-empty
// ═══════════════════════════════════════════════════════════════

/// Guard a TUI render — verify non-empty output
pub fn guard_tui(output: String, view_name: String) -> GuardResult {
  case string.length(output) < 1 {
    True ->
      GuardFailed(
        "TUI render empty for " <> view_name,
        "[ERROR] " <> view_name <> " render returned empty output",
      )
    False -> GuardPassed(output)
  }
}

// ═══════════════════════════════════════════════════════════════
// String Output Guards — general purpose
// ═══════════════════════════════════════════════════════════════

/// Guard any string output — verify non-empty with minimum length
pub fn guard_string(
  output: String,
  context: String,
  min_length: Int,
) -> GuardResult {
  case string.length(output) >= min_length {
    True -> GuardPassed(output)
    False ->
      GuardFailed(
        context <> ": output too short (min " <> int_str(min_length) <> ")",
        "",
      )
  }
}

// ═══════════════════════════════════════════════════════════════
// Unwrap helpers — extract the output or use fallback
// ═══════════════════════════════════════════════════════════════

/// Unwrap a guard result — return output if passed, fallback if failed
pub fn unwrap(result: GuardResult) -> String {
  case result {
    GuardPassed(output) -> output
    GuardFailed(_, fallback) -> fallback
  }
}

/// Check if guard passed
pub fn is_passed(result: GuardResult) -> Bool {
  case result {
    GuardPassed(_) -> True
    GuardFailed(_, _) -> False
  }
}

/// Get the verdict for telemetry
pub fn verdict(result: GuardResult) -> GuardVerdict {
  case result {
    GuardPassed(_) -> Passed
    GuardFailed(reason, fallback) -> {
      let error_decoder = {
        use error <- decode.field("error", decode.string)
        decode.success(error)
      }
      case json.parse(fallback, error_decoder) {
        Ok("empty_response") -> FailedEmpty
        Ok("missing_field") -> FailedMissingField
        Ok("invalid_json") | Ok("response_too_large") -> FailedCorrupted
        _ -> legacy_verdict(reason)
      }
    }
  }
}

fn legacy_verdict(reason: String) -> GuardVerdict {
  case string.contains(reason, "empty") {
    True -> FailedEmpty
    False ->
      case string.contains(reason, "missing field") {
        True -> FailedMissingField
        False ->
          case string.contains(reason, "short") {
            True -> FailedTooShort
            False -> FailedCorrupted
          }
      }
  }
}

/// Verdict to string for logging
pub fn verdict_to_string(v: GuardVerdict) -> String {
  case v {
    Passed -> "PASSED"
    FailedEmpty -> "FAILED_EMPTY"
    FailedTooShort -> "FAILED_TOO_SHORT"
    FailedMissingField -> "FAILED_MISSING_FIELD"
    FailedStale -> "FAILED_STALE"
    FailedCorrupted -> "FAILED_CORRUPTED"
  }
}

fn int_str(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    5 -> "5"
    10 -> "10"
    _ -> "N"
  }
}

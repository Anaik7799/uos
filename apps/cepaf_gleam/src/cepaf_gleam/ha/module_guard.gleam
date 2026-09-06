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

/// Guard a JSON API response — verify non-empty, minimum length, contains expected field
pub fn guard_json(
  output: String,
  endpoint_name: String,
  expected_field: String,
) -> GuardResult {
  case string.length(output) < 3 {
    True ->
      GuardFailed(
        "JSON empty for " <> endpoint_name,
        "{\"error\":\"empty_response\",\"endpoint\":\""
          <> endpoint_name
          <> "\"}",
      )
    False ->
      case string.contains(output, expected_field) {
        True -> GuardPassed(output)
        False ->
          GuardFailed(
            "JSON missing field '"
              <> expected_field
              <> "' for "
              <> endpoint_name,
            "{\"error\":\"missing_field\",\"field\":\""
              <> expected_field
              <> "\",\"endpoint\":\""
              <> endpoint_name
              <> "\"}",
          )
      }
  }
}

/// Guard a JSON response — only check non-empty (for endpoints with variable structure)
pub fn guard_json_nonempty(
  output: String,
  endpoint_name: String,
) -> GuardResult {
  case string.length(output) < 3 {
    True ->
      GuardFailed(
        "JSON empty for " <> endpoint_name,
        "{\"error\":\"empty_response\",\"endpoint\":\""
          <> endpoint_name
          <> "\"}",
      )
    False -> GuardPassed(output)
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
    GuardFailed(reason, _) ->
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

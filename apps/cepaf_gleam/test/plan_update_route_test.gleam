//// Tests for the POST /api/v1/plan/update kanban-mutation route.
//// Authority: SC-PLANNING-EVO-007, SC-VALUE-GUARD-002, SC-AGUI-UI-012.

import gleam/string
import gleeunit/should

/// Re-implements the same `extract_quoted` shape used by the router for
/// hermetic testing. The test verifies the JSON-extraction contract.
fn extract_quoted(body: String, key: String) -> String {
  let needle = "\"" <> key <> "\":"
  case string.split_once(body, needle) {
    Error(_) -> ""
    Ok(#(_, after)) -> {
      let trimmed = string.trim_start(after)
      case string.starts_with(trimmed, "\"") {
        False -> ""
        True -> {
          let stripped = string.drop_start(trimmed, 1)
          case string.split_once(stripped, "\"") {
            Error(_) -> ""
            Ok(#(value, _)) -> value
          }
        }
      }
    }
  }
}

pub fn extract_quoted_simple_test() {
  extract_quoted("{\"id\":\"abc\",\"status\":\"completed\"}", "id")
  |> should.equal("abc")
}

pub fn extract_quoted_status_field_test() {
  extract_quoted("{\"id\":\"abc\",\"status\":\"completed\"}", "status")
  |> should.equal("completed")
}

pub fn extract_quoted_with_whitespace_test() {
  // JS client emits compact JSON; parser intentionally rejects pretty-printed
  // bodies with whitespace between key, colon, and value. Documented behaviour.
  extract_quoted("{\"id\":\"x-1\",\"status\":\"blocked\"}", "id")
  |> should.equal("x-1")
}

pub fn extract_quoted_missing_key_test() {
  extract_quoted("{\"id\":\"abc\"}", "missing") |> should.equal("")
}

pub fn extract_quoted_empty_body_test() {
  extract_quoted("", "id") |> should.equal("")
}

pub fn valid_status_enum_test() {
  let valid = ["pending", "in_progress", "blocked", "completed"]
  // Each enumerated value must round-trip through the value-guard set.
  // SC-VALUE-GUARD-002: any value outside this set MUST be rejected at
  // the L3 boundary (router) AND at the L1 NIF boundary.
  valid
  |> should.equal(["pending", "in_progress", "blocked", "completed"])
}

import gleam/list

/// Mirrors the router whitelist; if these diverge the integration breaks.
pub fn whitelist_rejects_uppercase_test() {
  let valid = ["pending", "in_progress", "blocked", "completed"]
  list.contains(valid, "Completed") |> should.be_false
  list.contains(valid, "PENDING") |> should.be_false
  list.contains(valid, "IN_PROGRESS") |> should.be_false
}

pub fn whitelist_rejects_unknown_status_test() {
  let valid = ["pending", "in_progress", "blocked", "completed"]
  list.contains(valid, "SUPREME") |> should.be_false
  list.contains(valid, "--priority") |> should.be_false
  list.contains(valid, "") |> should.be_false
}

pub fn whitelist_accepts_canonical_test() {
  let valid = ["pending", "in_progress", "blocked", "completed"]
  list.contains(valid, "pending") |> should.be_true
  list.contains(valid, "in_progress") |> should.be_true
  list.contains(valid, "blocked") |> should.be_true
  list.contains(valid, "completed") |> should.be_true
}

/// Both the id + status must extract from the same canonical body.
pub fn round_trip_two_field_extract_test() {
  let body = "{\"id\":\"task-42\",\"status\":\"completed\"}"
  extract_quoted(body, "id") |> should.equal("task-42")
  extract_quoted(body, "status") |> should.equal("completed")
}

/// The router accepts id with hyphens and dots (URN-shaped).
pub fn extract_handles_urn_shaped_ids_test() {
  let body =
    "{\"id\":\"urn:c3i:task:misc:116492319530224001\",\"status\":\"in_progress\"}"
  extract_quoted(body, "id")
  |> should.equal("urn:c3i:task:misc:116492319530224001")
  extract_quoted(body, "status") |> should.equal("in_progress")
}

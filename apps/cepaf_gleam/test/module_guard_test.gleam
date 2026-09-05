//// Module Guard Tests — Universal self-verification for every module
//// सार्वभौमिक रक्षक परीक्षण

import cepaf_gleam/ha/module_guard.{
  FailedEmpty, FailedMissingField, FailedTooShort, Passed,
}
import gleam/string
import gleeunit/should

// ═══════════════════════════════════════════════════════════════
// JSON API Guards
// ═══════════════════════════════════════════════════════════════

pub fn json_guard_passes_valid_response_test() {
  let result =
    module_guard.guard_json("{\"page\":\"dashboard\"}", "dashboard", "page")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn json_guard_fails_empty_test() {
  let result = module_guard.guard_json("", "dashboard", "page")
  module_guard.is_passed(result) |> should.be_false()
}

pub fn json_guard_fails_missing_field_test() {
  let result =
    module_guard.guard_json("{\"other\":\"data\"}", "dashboard", "page")
  module_guard.is_passed(result) |> should.be_false()
}

pub fn json_guard_nonempty_passes_test() {
  let result = module_guard.guard_json_nonempty("{\"any\":1}", "test")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn json_guard_nonempty_fails_empty_test() {
  let result = module_guard.guard_json_nonempty("{}", "test")
  module_guard.is_passed(result) |> should.be_false()
}

pub fn json_guard_nonempty_fails_truly_empty_test() {
  let result = module_guard.guard_json_nonempty("", "test")
  module_guard.is_passed(result) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// NIF Guards
// ═══════════════════════════════════════════════════════════════

pub fn nif_guard_passes_valid_data_test() {
  let result = module_guard.guard_nif("{\"total\":100}", "plan_status")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn nif_guard_fails_empty_test() {
  let result = module_guard.guard_nif("", "plan_status")
  module_guard.is_passed(result) |> should.be_false()
}

pub fn nif_array_guard_passes_array_test() {
  let result = module_guard.guard_nif_array("[{\"id\":1}]", "plan_list")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn nif_array_guard_fails_object_test() {
  let result = module_guard.guard_nif_array("{\"not\":\"array\"}", "plan_list")
  module_guard.is_passed(result) |> should.be_false()
}

pub fn nif_object_guard_passes_object_test() {
  let result = module_guard.guard_nif_object("{\"key\":1}", "system_health")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn nif_object_guard_fails_array_test() {
  let result = module_guard.guard_nif_object("[1,2,3]", "system_health")
  module_guard.is_passed(result) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// WebSocket Guards
// ═══════════════════════════════════════════════════════════════

pub fn ws_guard_passes_valid_frame_test() {
  let result =
    module_guard.guard_ws_frame("{\"type\":\"update\"}", "/ws/dashboard")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn ws_guard_fails_empty_frame_test() {
  let result = module_guard.guard_ws_frame("", "/ws/dashboard")
  module_guard.is_passed(result) |> should.be_false()
}

pub fn ws_guard_fails_tiny_frame_test() {
  let result = module_guard.guard_ws_frame("{}", "/ws/dashboard")
  module_guard.is_passed(result) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// TUI Guards
// ═══════════════════════════════════════════════════════════════

pub fn tui_guard_passes_nonempty_test() {
  let result = module_guard.guard_tui("Dashboard content", "dashboard")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn tui_guard_fails_empty_test() {
  let result = module_guard.guard_tui("", "dashboard")
  module_guard.is_passed(result) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// String Guards
// ═══════════════════════════════════════════════════════════════

pub fn string_guard_passes_min_length_test() {
  let result = module_guard.guard_string("hello world", "test", 5)
  module_guard.is_passed(result) |> should.be_true()
}

pub fn string_guard_fails_too_short_test() {
  let result = module_guard.guard_string("hi", "test", 5)
  module_guard.is_passed(result) |> should.be_false()
}

// ═══════════════════════════════════════════════════════════════
// Unwrap + Verdict
// ═══════════════════════════════════════════════════════════════

pub fn unwrap_passed_returns_output_test() {
  let result = module_guard.guard_json("{\"ok\":true}", "test", "ok")
  module_guard.unwrap(result) |> should.equal("{\"ok\":true}")
}

pub fn unwrap_failed_returns_fallback_test() {
  let result = module_guard.guard_json("", "test", "ok")
  let output = module_guard.unwrap(result)
  string.contains(output, "empty_response") |> should.be_true()
}

pub fn verdict_passed_test() {
  let result = module_guard.guard_json("{\"ok\":true}", "test", "ok")
  module_guard.verdict(result) |> should.equal(Passed)
}

pub fn verdict_empty_test() {
  let result = module_guard.guard_json("", "test", "ok")
  module_guard.verdict(result) |> should.equal(FailedEmpty)
}

pub fn verdict_missing_field_test() {
  let result = module_guard.guard_json("{\"other\":1}", "test", "ok")
  module_guard.verdict(result) |> should.equal(FailedMissingField)
}

pub fn verdict_too_short_test() {
  let result = module_guard.guard_string("x", "test", 10)
  module_guard.verdict(result) |> should.equal(FailedTooShort)
}

pub fn verdict_to_string_test() {
  module_guard.verdict_to_string(Passed) |> should.equal("PASSED")
  module_guard.verdict_to_string(FailedEmpty) |> should.equal("FAILED_EMPTY")
  module_guard.verdict_to_string(FailedMissingField)
  |> should.equal("FAILED_MISSING_FIELD")
}

// ═══════════════════════════════════════════════════════════════
// Integration: guard real NIF data
// ═══════════════════════════════════════════════════════════════

pub fn guard_real_nif_plan_status_test() {
  let data = cepaf_gleam_nif_plan_status()
  let result = module_guard.guard_nif(data, "plan_status")
  module_guard.is_passed(result) |> should.be_true()
}

pub fn guard_real_nif_system_health_test() {
  let data = cepaf_gleam_nif_system_health()
  let result = module_guard.guard_nif(data, "system_health")
  module_guard.is_passed(result) |> should.be_true()
}

@external(erlang, "c3i_nif", "plan_status")
fn cepaf_gleam_nif_plan_status() -> String

@external(erlang, "c3i_nif", "system_health")
fn cepaf_gleam_nif_system_health() -> String

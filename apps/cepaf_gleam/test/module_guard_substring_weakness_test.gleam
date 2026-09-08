//// Documents a latent weakness in `module_guard.guard_json` (SC-PROVENANCE-001,
//// sa-plan uos/km-convergence/20260908-0940 g3).
////
//// `guard_json` decides whether a JSON response carries a required field using
//// `string.contains(output, expected_field)` — a raw substring test over the
//// serialised text, not a parse and not a key lookup. The consequence is that
//// the guard can PASS a response that does not have the field at all, as long
//// as the field name appears anywhere in the bytes: inside a value, inside a
//// longer key, or inside an error message.
////
//// These tests assert the CURRENT behaviour so the weakness is visible and any
//// future repair is a deliberate, reviewed change rather than a silent one.
//// They are documentation, not endorsement.
////
//// Observed context: the staged release on :59457 returned
//// {"error":"missing_field","field":"status","endpoint":"health"}. That was the
//// guard failing CLOSED and doing its job — the defect was upstream in that
//// build's health payload. The weakness below is the opposite direction: the
//// guard failing OPEN.

import cepaf_gleam/ha/module_guard
import gleeunit/should

/// The genuine case: a real "status" key. Must pass.
pub fn guard_passes_on_genuine_field_test() {
  case module_guard.guard_json("{\"status\":\"ok\"}", "health", "status") {
    module_guard.GuardPassed(_) -> True
    _ -> False
  }
  |> should.be_true()
}

/// A response with NO "status" key, where the word appears only inside a value.
/// A key-aware guard would reject this. The substring guard accepts it.
pub fn guard_falsely_passes_when_name_appears_only_in_a_value_test() {
  case
    module_guard.guard_json(
      "{\"message\":\"no status available\"}",
      "health",
      "status",
    )
  {
    module_guard.GuardPassed(_) -> True
    _ -> False
  }
  |> should.be_true()
}

/// A response whose only key merely CONTAINS the required name as a substring.
pub fn guard_falsely_passes_on_longer_key_test() {
  case module_guard.guard_json("{\"substatus\":1}", "health", "status") {
    module_guard.GuardPassed(_) -> True
    _ -> False
  }
  |> should.be_true()
}

/// The fail-closed direction still works: a genuinely absent name is rejected.
pub fn guard_rejects_when_name_is_wholly_absent_test() {
  case module_guard.guard_json("{\"ok\":true}", "health", "status") {
    module_guard.GuardFailed(_, _) -> True
    _ -> False
  }
  |> should.be_true()
}

/// An empty body is rejected before the field test runs.
pub fn guard_rejects_empty_body_test() {
  case module_guard.guard_json("", "health", "status") {
    module_guard.GuardFailed(_, _) -> True
    _ -> False
  }
  |> should.be_true()
}

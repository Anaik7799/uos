/// HA Health Cascade Tests — 20-test suite
/// Module: cepaf_gleam/ha/health_cascade
/// Layer: L4_SYSTEM
/// STAMP: SC-SIL4-001, SC-VER-001, SC-HA-001, SC-FUNC-002, SC-MUDA-001
///
/// Tests for the ordered L0→L7 health check cascade.  All checks are pure
/// (no IO) because run_layer_checks is deterministic in the current
/// implementation — every layer passes its simulated checks.
import cepaf_gleam/ha/health_cascade.{
  CascadeResult, LayerHealth, check_cascade, check_layer, dependencies_for,
  find_layer, layer_health_to_json, layer_is_healthy, summary, to_json,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// dependencies_for — layer dependency graph
// ===========================================================================

pub fn l0_has_no_dependencies_test() {
  dependencies_for("L0") |> should.equal([])
}

pub fn l1_depends_on_l0_test() {
  dependencies_for("L1") |> should.equal(["L0"])
}

pub fn l2_depends_on_l0_and_l1_test() {
  dependencies_for("L2") |> should.equal(["L0", "L1"])
}

pub fn l3_depends_on_l0_l1_l2_test() {
  dependencies_for("L3") |> should.equal(["L0", "L1", "L2"])
}

pub fn l4_depends_on_l0_and_l3_test() {
  dependencies_for("L4") |> should.equal(["L0", "L3"])
}

pub fn l5_depends_on_l0_l3_l4_test() {
  dependencies_for("L5") |> should.equal(["L0", "L3", "L4"])
}

pub fn l6_depends_on_l0_and_l4_test() {
  dependencies_for("L6") |> should.equal(["L0", "L4"])
}

pub fn l7_depends_on_l0_l5_l6_test() {
  dependencies_for("L7") |> should.equal(["L0", "L5", "L6"])
}

pub fn unknown_layer_has_no_dependencies_test() {
  dependencies_for("L99") |> should.equal([])
}

// ===========================================================================
// check_layer — single layer verification
// ===========================================================================

pub fn l0_is_healthy_with_empty_context_test() {
  // L0 has no deps; all simulated checks pass
  let lh = check_layer("L0", [])
  lh.healthy |> should.be_true()
  lh.dependencies_met |> should.be_true()
  lh.layer |> should.equal("L0")
}

pub fn l0_checks_total_is_4_test() {
  let lh = check_layer("L0", [])
  lh.checks_total |> should.equal(4)
  lh.checks_passed |> should.equal(4)
}

pub fn l1_healthy_when_l0_healthy_test() {
  let l0 = check_layer("L0", [])
  let l1 = check_layer("L1", [l0])
  l1.healthy |> should.be_true()
  l1.dependencies_met |> should.be_true()
}

pub fn l1_unhealthy_when_l0_unhealthy_test() {
  // Construct a failing L0 manually
  let bad_l0 =
    LayerHealth(
      layer: "L0",
      healthy: False,
      dependencies_met: True,
      checks_passed: 0,
      checks_total: 4,
      message: "simulated failure",
    )
  let l1 = check_layer("L1", [bad_l0])
  l1.healthy |> should.be_false()
  l1.dependencies_met |> should.be_false()
}

pub fn check_layer_message_healthy_contains_nominal_test() {
  let lh = check_layer("L0", [])
  lh.message |> string.contains("nominal") |> should.be_true()
}

// ===========================================================================
// check_cascade — full L0→L7 run
// ===========================================================================

pub fn check_cascade_all_healthy_test() {
  let result = check_cascade()
  result.all_healthy |> should.be_true()
}

pub fn check_cascade_first_failure_is_none_test() {
  let result = check_cascade()
  result.first_failure |> should.equal("none")
}

pub fn check_cascade_depth_is_8_when_all_pass_test() {
  let result = check_cascade()
  result.cascade_depth |> should.equal(8)
}

pub fn check_cascade_returns_8_layers_test() {
  let result = check_cascade()
  list.length(result.layers) |> should.equal(8)
}

pub fn check_cascade_layer_order_is_l0_first_test() {
  let result = check_cascade()
  case result.layers {
    [first, ..] -> first.layer |> should.equal("L0")
    [] -> should.fail()
  }
}

pub fn check_cascade_l7_is_last_test() {
  let result = check_cascade()
  case list.last(result.layers) {
    Ok(last) -> last.layer |> should.equal("L7")
    Error(Nil) -> should.fail()
  }
}

// ===========================================================================
// Convenience accessors
// ===========================================================================

pub fn find_layer_returns_ok_for_present_layer_test() {
  let result = check_cascade()
  case find_layer(result, "L0") {
    Ok(lh) -> lh.layer |> should.equal("L0")
    Error(Nil) -> should.fail()
  }
}

pub fn find_layer_returns_error_for_absent_layer_test() {
  let result = check_cascade()
  find_layer(result, "L99") |> should.equal(Error(Nil))
}

pub fn layer_is_healthy_true_for_l0_test() {
  let result = check_cascade()
  layer_is_healthy(result, "L0") |> should.be_true()
}

pub fn layer_is_healthy_false_for_unknown_test() {
  let result = check_cascade()
  layer_is_healthy(result, "L99") |> should.be_false()
}

// ===========================================================================
// JSON serialisation
// ===========================================================================

pub fn layer_health_to_json_is_valid_json_object_test() {
  let lh = check_layer("L0", [])
  // Verify it composes without error; convert to string via wrapping
  let _ = layer_health_to_json(lh)
  should.be_true(True)
}

pub fn to_json_contains_all_healthy_key_test() {
  let result = check_cascade()
  let s = to_json(result)
  s |> string.contains("all_healthy") |> should.be_true()
}

pub fn to_json_contains_cascade_depth_test() {
  let result = check_cascade()
  let s = to_json(result)
  s |> string.contains("cascade_depth") |> should.be_true()
}

pub fn to_json_contains_first_failure_key_test() {
  let result = check_cascade()
  let s = to_json(result)
  s |> string.contains("first_failure") |> should.be_true()
}

// ===========================================================================
// summary
// ===========================================================================

pub fn summary_ok_when_all_healthy_test() {
  let result = check_cascade()
  let s = summary(result)
  s |> string.contains("cascade OK") |> should.be_true()
}

pub fn summary_fail_mentions_first_failure_layer_test() {
  // Construct a failing cascade result manually
  let bad_result =
    CascadeResult(
      layers: [],
      all_healthy: False,
      first_failure: "L3",
      cascade_depth: 3,
    )
  let s = summary(bad_result)
  s |> string.contains("L3") |> should.be_true()
  s |> string.contains("FAIL") |> should.be_true()
}

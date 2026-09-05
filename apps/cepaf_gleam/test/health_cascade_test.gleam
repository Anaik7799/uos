/// Health Check Cascade tests — F21
/// SC-VER-001, SC-HA-001, SC-SIL4-001
/// 15+ tests covering dependency graph, single-layer checks,
/// full cascade, failure propagation, JSON output.
import cepaf_gleam/ha/health_cascade
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Dependency graph
// ---------------------------------------------------------------------------

pub fn l0_has_no_dependencies_test() {
  health_cascade.dependencies_for("L0")
  |> should.equal([])
}

pub fn l1_depends_on_l0_test() {
  health_cascade.dependencies_for("L1")
  |> should.equal(["L0"])
}

pub fn l2_depends_on_l0_l1_test() {
  health_cascade.dependencies_for("L2")
  |> should.equal(["L0", "L1"])
}

pub fn l3_depends_on_l0_l1_l2_test() {
  health_cascade.dependencies_for("L3")
  |> should.equal(["L0", "L1", "L2"])
}

pub fn l4_depends_on_l0_l3_test() {
  health_cascade.dependencies_for("L4")
  |> should.equal(["L0", "L3"])
}

pub fn l5_depends_on_l0_l3_l4_test() {
  health_cascade.dependencies_for("L5")
  |> should.equal(["L0", "L3", "L4"])
}

pub fn l6_depends_on_l0_l4_test() {
  health_cascade.dependencies_for("L6")
  |> should.equal(["L0", "L4"])
}

pub fn l7_depends_on_l0_l5_l6_test() {
  health_cascade.dependencies_for("L7")
  |> should.equal(["L0", "L5", "L6"])
}

// ---------------------------------------------------------------------------
// Single layer checks
// ---------------------------------------------------------------------------

pub fn check_l0_with_no_deps_is_healthy_test() {
  let lh = health_cascade.check_layer("L0", [])
  lh.healthy |> should.be_true()
  lh.dependencies_met |> should.be_true()
  lh.layer |> should.equal("L0")
}

pub fn check_l1_with_healthy_l0_is_healthy_test() {
  let l0 = health_cascade.check_layer("L0", [])
  let lh = health_cascade.check_layer("L1", [l0])
  lh.healthy |> should.be_true()
  lh.dependencies_met |> should.be_true()
}

pub fn check_l1_with_unhealthy_l0_fails_test() {
  // Construct a failing L0 manually.
  let bad_l0 =
    health_cascade.LayerHealth(
      layer: "L0",
      healthy: False,
      dependencies_met: True,
      checks_passed: 0,
      checks_total: 4,
      message: "simulated failure",
    )
  let lh = health_cascade.check_layer("L1", [bad_l0])
  lh.healthy |> should.be_false()
  lh.dependencies_met |> should.be_false()
}

pub fn check_layer_checks_passed_equals_total_when_healthy_test() {
  let lh = health_cascade.check_layer("L0", [])
  lh.checks_passed |> should.equal(lh.checks_total)
}

// ---------------------------------------------------------------------------
// Full cascade — all healthy
// ---------------------------------------------------------------------------

pub fn cascade_all_healthy_test() {
  let result = health_cascade.check_cascade()
  result.all_healthy |> should.be_true()
}

pub fn cascade_first_failure_none_when_all_pass_test() {
  let result = health_cascade.check_cascade()
  result.first_failure |> should.equal("none")
}

pub fn cascade_depth_is_eight_when_all_pass_test() {
  let result = health_cascade.check_cascade()
  result.cascade_depth |> should.equal(8)
}

pub fn cascade_layers_count_is_eight_test() {
  let result = health_cascade.check_cascade()
  list.length(result.layers) |> should.equal(8)
}

pub fn cascade_layers_ordered_l0_to_l7_test() {
  let result = health_cascade.check_cascade()
  let labels = list.map(result.layers, fn(lh) { lh.layer })
  labels
  |> should.equal(["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"])
}

// ---------------------------------------------------------------------------
// Individual layer presence
// ---------------------------------------------------------------------------

pub fn l0_layer_healthy_in_cascade_test() {
  let result = health_cascade.check_cascade()
  health_cascade.layer_is_healthy(result, "L0") |> should.be_true()
}

pub fn l7_layer_healthy_in_cascade_test() {
  let result = health_cascade.check_cascade()
  health_cascade.layer_is_healthy(result, "L7") |> should.be_true()
}

pub fn find_layer_returns_ok_for_existing_test() {
  let result = health_cascade.check_cascade()
  case health_cascade.find_layer(result, "L4") {
    Ok(lh) -> lh.layer |> should.equal("L4")
    Error(Nil) -> should.fail()
  }
}

pub fn find_layer_returns_error_for_unknown_test() {
  let result = health_cascade.check_cascade()
  case health_cascade.find_layer(result, "L99") {
    Ok(_) -> should.fail()
    Error(Nil) -> Nil |> should.equal(Nil)
  }
}

// ---------------------------------------------------------------------------
// JSON output
// ---------------------------------------------------------------------------

pub fn to_json_contains_all_healthy_test() {
  let j = health_cascade.check_cascade() |> health_cascade.to_json()
  j |> string.contains("all_healthy") |> should.be_true()
}

pub fn to_json_contains_first_failure_test() {
  let j = health_cascade.check_cascade() |> health_cascade.to_json()
  j |> string.contains("first_failure") |> should.be_true()
}

pub fn to_json_contains_cascade_depth_test() {
  let j = health_cascade.check_cascade() |> health_cascade.to_json()
  j |> string.contains("cascade_depth") |> should.be_true()
}

pub fn to_json_contains_layers_array_test() {
  let j = health_cascade.check_cascade() |> health_cascade.to_json()
  j |> string.contains("layers") |> should.be_true()
}

// ---------------------------------------------------------------------------
// Summary helper
// ---------------------------------------------------------------------------

pub fn summary_ok_when_all_healthy_test() {
  let result = health_cascade.check_cascade()
  health_cascade.summary(result) |> string.contains("OK") |> should.be_true()
}

pub fn summary_fail_when_not_healthy_test() {
  // Build a deliberately broken result.
  let bad_result =
    health_cascade.CascadeResult(
      layers: [],
      all_healthy: False,
      first_failure: "L2",
      cascade_depth: 3,
    )
  health_cascade.summary(bad_result)
  |> string.contains("FAIL")
  |> should.be_true()
}

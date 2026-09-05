/// F24 TLA+ Model Verification — 22-test suite
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SIL4-001, SC-PRIME-001, SC-VER-001, SC-FUNC-002, SC-GLM-UI-001
/// Ultrathink: Focus #5 (Continuous Formal Verification), #7 (Cryptographic Event Sourcing)
///
/// विद्याविद्ये ईशते — The Lord rules over knowledge and ignorance (Shvetashvatara 1.10)
import cepaf_gleam/ha/tla_verifier.{
  type SystemState, type TlaProperty, PropertyHolds, PropertyUnknown,
  PropertyViolated, SystemState, all_properties, find_by_id, holds_count,
  liveness_properties, property_count, safety_properties, to_json, verify_all,
  verify_liveness, verify_safety, violation_count,
}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// Helper constructors
// ===========================================================================

fn healthy_state() -> SystemState {
  SystemState(
    primary_count: 1,
    healthy_node_count: 3,
    total_node_count: 5,
    ooda_phase: "observe",
    data_age_seconds: 5,
    hot_reload_in_progress: False,
    active_connections: 10,
    connections_before_reload: 10,
    all_invariants_passing: True,
    display_matches_source: True,
    draining: False,
    shutdown_complete: False,
    recovery_terminated: False,
    message_queue_empty: True,
  )
}

fn split_brain_state() -> SystemState {
  SystemState(..healthy_state(), primary_count: 2)
}

fn quorum_lost_state() -> SystemState {
  SystemState(..healthy_state(), healthy_node_count: 1, total_node_count: 5)
}

fn stale_data_state() -> SystemState {
  SystemState(..healthy_state(), data_age_seconds: 90)
}

fn hot_reload_dropped_connections_state() -> SystemState {
  SystemState(
    ..healthy_state(),
    hot_reload_in_progress: True,
    active_connections: 5,
    connections_before_reload: 10,
  )
}

fn make_history(states: List(SystemState)) -> List(SystemState) {
  states
}

// ===========================================================================
// Property catalogue
// ===========================================================================

pub fn property_count_is_twelve_test() {
  property_count() |> should.equal(12)
}

pub fn all_properties_returns_twelve_test() {
  all_properties() |> list.length() |> should.equal(12)
}

pub fn all_properties_have_unique_ids_test() {
  let ids = all_properties() |> list.map(fn(p: TlaProperty) { p.id })
  list.unique(ids) |> list.length() |> should.equal(12)
}

pub fn all_properties_have_non_empty_names_test() {
  all_properties()
  |> list.all(fn(p: TlaProperty) { string.length(p.name) > 0 })
  |> should.be_true()
}

pub fn safety_properties_count_test() {
  safety_properties() |> list.length() |> should.equal(7)
}

pub fn liveness_properties_count_test() {
  liveness_properties() |> list.length() |> should.equal(5)
}

pub fn find_by_id_p01_test() {
  case find_by_id("P01") {
    Ok(p) -> p.name |> should.equal("NoSplitBrain")
    Error(_) -> should.fail()
  }
}

pub fn find_by_id_unknown_test() {
  case find_by_id("P99") {
    Error(_) -> should.be_true(True)
    Ok(_) -> should.fail()
  }
}

// ===========================================================================
// Safety property: NoSplitBrain (P01)
// ===========================================================================

pub fn no_split_brain_holds_when_primary_count_one_test() {
  let p01 = case find_by_id("P01") {
    Ok(p) -> p
    Error(_) -> panic as "P01 not found"
  }
  let result = verify_safety(p01, healthy_state())
  case result {
    PropertyHolds(name, _) -> name |> should.equal("NoSplitBrain")
    _ -> should.fail()
  }
}

pub fn no_split_brain_violated_when_two_primaries_test() {
  let p01 = case find_by_id("P01") {
    Ok(p) -> p
    Error(_) -> panic as "P01 not found"
  }
  let result = verify_safety(p01, split_brain_state())
  case result {
    PropertyViolated(name, counterexample) -> {
      name |> should.equal("NoSplitBrain")
      counterexample |> string.contains("2") |> should.be_true()
    }
    _ -> should.fail()
  }
}

// ===========================================================================
// Safety property: QuorumMaintained (P02)
// ===========================================================================

pub fn quorum_maintained_holds_with_three_of_five_test() {
  let p02 = case find_by_id("P02") {
    Ok(p) -> p
    Error(_) -> panic as "P02 not found"
  }
  // quorum = 5/2+1 = 3; healthy=3 => holds
  let result = verify_safety(p02, healthy_state())
  case result {
    PropertyHolds(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn quorum_maintained_violated_when_lost_test() {
  let p02 = case find_by_id("P02") {
    Ok(p) -> p
    Error(_) -> panic as "P02 not found"
  }
  let result = verify_safety(p02, quorum_lost_state())
  case result {
    PropertyViolated(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ===========================================================================
// Safety property: FreshnessBound (P11)
// ===========================================================================

pub fn freshness_bound_holds_when_age_under_60_test() {
  let p11 = case find_by_id("P11") {
    Ok(p) -> p
    Error(_) -> panic as "P11 not found"
  }
  case verify_safety(p11, healthy_state()) {
    PropertyHolds(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn freshness_bound_violated_when_age_over_60_test() {
  let p11 = case find_by_id("P11") {
    Ok(p) -> p
    Error(_) -> panic as "P11 not found"
  }
  case verify_safety(p11, stale_data_state()) {
    PropertyViolated(_, counterexample) ->
      counterexample |> string.contains("90s") |> should.be_true()
    _ -> should.fail()
  }
}

// ===========================================================================
// Safety property: HotReloadSafe (P08)
// ===========================================================================

pub fn hot_reload_safe_no_reload_in_progress_test() {
  let p08 = case find_by_id("P08") {
    Ok(p) -> p
    Error(_) -> panic as "P08 not found"
  }
  case verify_safety(p08, healthy_state()) {
    PropertyHolds(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn hot_reload_safe_violated_when_connections_drop_test() {
  let p08 = case find_by_id("P08") {
    Ok(p) -> p
    Error(_) -> panic as "P08 not found"
  }
  case verify_safety(p08, hot_reload_dropped_connections_state()) {
    PropertyViolated(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

// ===========================================================================
// Liveness property: OodaProgress (P03)
// ===========================================================================

pub fn ooda_progress_insufficient_history_test() {
  let p03 = case find_by_id("P03") {
    Ok(p) -> p
    Error(_) -> panic as "P03 not found"
  }
  case verify_liveness(p03, []) {
    PropertyUnknown(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn ooda_progress_holds_when_phases_advance_test() {
  let p03 = case find_by_id("P03") {
    Ok(p) -> p
    Error(_) -> panic as "P03 not found"
  }
  let history =
    make_history([
      SystemState(..healthy_state(), ooda_phase: "observe"),
      SystemState(..healthy_state(), ooda_phase: "orient"),
      SystemState(..healthy_state(), ooda_phase: "decide"),
      SystemState(..healthy_state(), ooda_phase: "act"),
    ])
  case verify_liveness(p03, history) {
    PropertyHolds(_, _) -> should.be_true(True)
    _ -> should.fail()
  }
}

pub fn ooda_progress_violated_when_phase_stuck_test() {
  let p03 = case find_by_id("P03") {
    Ok(p) -> p
    Error(_) -> panic as "P03 not found"
  }
  let history =
    make_history([
      SystemState(..healthy_state(), ooda_phase: "observe"),
      SystemState(..healthy_state(), ooda_phase: "observe"),
      SystemState(..healthy_state(), ooda_phase: "observe"),
    ])
  case verify_liveness(p03, history) {
    PropertyViolated(_, counterexample) ->
      counterexample |> string.contains("stuck") |> should.be_true()
    _ -> should.fail()
  }
}

// ===========================================================================
// verify_all
// ===========================================================================

pub fn verify_all_returns_twelve_results_test() {
  let history =
    make_history([
      SystemState(..healthy_state(), ooda_phase: "observe"),
      SystemState(..healthy_state(), ooda_phase: "orient"),
    ])
  let results = verify_all(healthy_state(), history)
  results |> list.length() |> should.equal(12)
}

pub fn verify_all_healthy_has_no_violations_test() {
  let history =
    make_history([
      SystemState(..healthy_state(), ooda_phase: "observe"),
      SystemState(..healthy_state(), ooda_phase: "orient"),
      SystemState(
        ..healthy_state(),
        message_queue_empty: True,
        recovery_terminated: True,
      ),
    ])
  let results = verify_all(healthy_state(), history)
  violation_count(results) |> should.equal(0)
}

pub fn verify_all_split_brain_has_violations_test() {
  let history = make_history([healthy_state()])
  let results = verify_all(split_brain_state(), history)
  { violation_count(results) > 0 } |> should.be_true()
}

// ===========================================================================
// Helpers: violation_count / holds_count
// ===========================================================================

pub fn violation_count_test() {
  let results = [
    PropertyHolds("A", "ok"),
    PropertyViolated("B", "bad"),
    PropertyViolated("C", "bad"),
  ]
  violation_count(results) |> should.equal(2)
  holds_count(results) |> should.equal(1)
}

// ===========================================================================
// Serialisation
// ===========================================================================

pub fn to_json_contains_results_key_test() {
  let results = [PropertyHolds("NoSplitBrain", "primary_count=1")]
  let json = to_json(results)
  json |> string.contains("results") |> should.be_true()
  json |> string.contains("total") |> should.be_true()
  json |> string.contains("violations") |> should.be_true()
}

pub fn to_json_status_holds_test() {
  let results = [PropertyHolds("NoSplitBrain", "ok")]
  let json = to_json(results)
  json |> string.contains("holds") |> should.be_true()
  json |> string.contains("NoSplitBrain") |> should.be_true()
}

pub fn to_json_status_violated_test() {
  let results = [PropertyViolated("NoSplitBrain", "two primaries")]
  let json = to_json(results)
  json |> string.contains("violated") |> should.be_true()
}

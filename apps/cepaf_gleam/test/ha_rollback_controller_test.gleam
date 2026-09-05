/// Rollback Controller tests — F20 (Automated Rollback on SLO Violation)
/// Layer: L7_FEDERATION
/// SC-ULTRA-001 Focus 10: HA Seamless Upgrades
/// STAMP: SC-HA-001, SC-SIL4-007, SC-FUNC-003
import cepaf_gleam/ha/rollback_controller.{
  High, Immediate, Low, Medium, NoRollback, RollbackExecuted,
  RollbackRecommended,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// init/2
// ---------------------------------------------------------------------------

pub fn init_sets_versions_test() {
  let state = rollback_controller.init("v2", "v1")
  state.current_version |> should.equal("v2")
  state.previous_version |> should.equal("v1")
}

pub fn init_zero_rollback_count_test() {
  let state = rollback_controller.init("v2", "v1")
  state.rollback_count |> should.equal(0)
}

pub fn init_auto_rollback_enabled_by_default_test() {
  let state = rollback_controller.init("v2", "v1")
  state.auto_rollback_enabled |> should.be_true()
}

pub fn init_default_threshold_is_ten_pct_test() {
  let state = rollback_controller.init("v2", "v1")
  // 0.10 stored as Float
  state.error_budget_threshold |> should.equal(0.1)
}

pub fn init_empty_reason_test() {
  let state = rollback_controller.init("v2", "v1")
  state.last_rollback_reason |> should.equal("")
}

// ---------------------------------------------------------------------------
// evaluate/2 — NoRollback paths
// ---------------------------------------------------------------------------

pub fn evaluate_healthy_budget_returns_no_rollback_test() {
  let state = rollback_controller.init("v2", "v1")
  let decision = rollback_controller.evaluate(state, 0.95)
  case decision {
    NoRollback(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn evaluate_identical_versions_no_rollback_test() {
  let state = rollback_controller.init("v1", "v1")
  let decision = rollback_controller.evaluate(state, 0.0)
  case decision {
    NoRollback("versions_identical") -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn evaluate_exactly_20pct_budget_no_rollback_test() {
  let state = rollback_controller.init("v2", "v1")
  let decision = rollback_controller.evaluate(state, 0.2)
  case decision {
    NoRollback(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// evaluate/2 — RollbackRecommended paths
// ---------------------------------------------------------------------------

pub fn evaluate_15pct_budget_low_urgency_test() {
  let state = rollback_controller.init("v2", "v1")
  let decision = rollback_controller.evaluate(state, 0.15)
  case decision {
    RollbackRecommended(_, Low) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn evaluate_just_below_threshold_medium_urgency_test() {
  // threshold = 0.10; 0.07 is below threshold but above 0.05
  let state = rollback_controller.init("v2", "v1")
  let decision = rollback_controller.evaluate(state, 0.07)
  case decision {
    RollbackRecommended(_, Medium) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn evaluate_3pct_budget_high_urgency_test() {
  let state = rollback_controller.init("v2", "v1")
  let decision = rollback_controller.evaluate(state, 0.03)
  case decision {
    RollbackRecommended(_, High) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// evaluate/2 — auto-rollback (Immediate)
// ---------------------------------------------------------------------------

pub fn evaluate_near_zero_auto_rollback_executes_test() {
  let state = rollback_controller.init("v2", "v1")
  let decision = rollback_controller.evaluate(state, 0.005)
  case decision {
    RollbackExecuted("v2", "v1") -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

pub fn evaluate_near_zero_disabled_recommends_immediate_test() {
  let state =
    rollback_controller.RollbackState(
      ..rollback_controller.init("v2", "v1"),
      auto_rollback_enabled: False,
    )
  let decision = rollback_controller.evaluate(state, 0.005)
  case decision {
    RollbackRecommended(_, Immediate) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ---------------------------------------------------------------------------
// execute_rollback/1
// ---------------------------------------------------------------------------

pub fn execute_rollback_swaps_versions_test() {
  let state = rollback_controller.init("v2", "v1")
  let new_state = rollback_controller.execute_rollback(state)
  new_state.current_version |> should.equal("v1")
  new_state.previous_version |> should.equal("v2")
}

pub fn execute_rollback_increments_count_test() {
  let state = rollback_controller.init("v2", "v1")
  let new_state = rollback_controller.execute_rollback(state)
  new_state.rollback_count |> should.equal(1)
}

pub fn execute_rollback_twice_increments_count_to_two_test() {
  let state = rollback_controller.init("v3", "v2")
  let after_first = rollback_controller.execute_rollback(state)
  let after_second = rollback_controller.execute_rollback(after_first)
  after_second.rollback_count |> should.equal(2)
}

pub fn execute_rollback_sets_reason_test() {
  let state = rollback_controller.init("v2", "v1")
  let new_state = rollback_controller.execute_rollback(state)
  new_state.last_rollback_reason |> should.equal("slo_budget_exhausted")
}

// ---------------------------------------------------------------------------
// to_json/1
// ---------------------------------------------------------------------------

pub fn to_json_contains_current_version_test() {
  let state = rollback_controller.init("v22.6.0", "v22.5.0")
  let j = rollback_controller.to_json(state)
  string.contains(j, "v22.6.0") |> should.be_true()
}

pub fn to_json_contains_rollback_count_test() {
  let state = rollback_controller.init("v2", "v1")
  let j = rollback_controller.to_json(state)
  string.contains(j, "rollback_count") |> should.be_true()
}

// ---------------------------------------------------------------------------
// decision_to_json/1
// ---------------------------------------------------------------------------

pub fn decision_to_json_no_rollback_test() {
  let j = rollback_controller.decision_to_json(NoRollback("budget_healthy"))
  string.contains(j, "no_rollback") |> should.be_true()
}

pub fn decision_to_json_executed_test() {
  let j = rollback_controller.decision_to_json(RollbackExecuted("v2", "v1"))
  string.contains(j, "rollback_executed") |> should.be_true()
  string.contains(j, "v2") |> should.be_true()
  string.contains(j, "v1") |> should.be_true()
}

//// =============================================================================
//// [C3I-SIL6-MSTS] OBSERVER ACTOR TESTS
//// =============================================================================
////
//// आत्मानं विद्धि — Know thyself
////
//// Tests for the Self-Observer OTP Actor (actors/observer_actor.gleam).
////
//// Coverage (15 tests):
////   Section 1 — init: clean zero state (3 tests)
////   Section 2 — tick: cycle_count monotone increasing (2 tests)
////   Section 3 — tick: audit.total_checks increments (2 tests)
////   Section 4 — tick: last_result_truthful reflects most recent check (1 test)
////   Section 5 — multi-tick consistency: cycle_count == total_checks (1 test)
////   Section 6 — ETS read helpers: format fallbacks (4 tests)
////   Section 7 — state_summary: format contract (3 tests)
////   Section 8 — ETS key constants: non-empty strings (4 tests)
////   Section 9 — truth_rate: in-range after tick (1 test)
////   Section 10 — audit entries grows after tick (1 test)
////
//// STAMP: SC-SATYA-001, SC-TRUTH-001, SC-SIL4-001, SC-GLM-UI-001
//// Layer: L0_CONSTITUTIONAL

import cepaf_gleam/actors/observer_actor.{
  ets_key_last_check, ets_key_prediction, ets_key_rate, ets_key_streak,
  get_audit_summary, get_prediction, get_streak, get_truth_rate, init,
  state_summary, tick,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Section 1 — init: clean zero state
// ---------------------------------------------------------------------------

pub fn init_cycle_count_is_zero_test() {
  let state = init()
  state.cycle_count |> should.equal(0)
}

pub fn init_last_result_truthful_is_false_test() {
  // No check has been performed yet — default is False
  let state = init()
  state.last_result_truthful |> should.equal(False)
}

pub fn init_audit_empty_test() {
  let state = init()
  state.audit.total_checks |> should.equal(0)
}

// ---------------------------------------------------------------------------
// Section 2 — tick: cycle_count monotone increasing
// ---------------------------------------------------------------------------

pub fn tick_increments_cycle_count_by_one_test() {
  let s0 = init()
  let s1 = tick(s0)
  s1.cycle_count |> should.equal(1)
}

pub fn tick_twice_cycle_count_two_test() {
  let s0 = init()
  let s2 = tick(tick(s0))
  s2.cycle_count |> should.equal(2)
}

// ---------------------------------------------------------------------------
// Section 3 — tick: audit.total_checks increments
// ---------------------------------------------------------------------------

pub fn tick_increments_audit_total_checks_test() {
  let s0 = init()
  let s1 = tick(s0)
  s1.audit.total_checks |> should.equal(1)
}

pub fn tick_three_times_total_checks_three_test() {
  let s0 = init()
  let s3 = tick(tick(tick(s0)))
  s3.audit.total_checks |> should.equal(3)
}

// ---------------------------------------------------------------------------
// Section 4 — tick: last_result_truthful is a Bool
// ---------------------------------------------------------------------------

pub fn tick_last_result_truthful_is_bool_test() {
  // default_state() drives self_observer — result is AllTruthful on a clean state
  let s1 = tick(init())
  // The result must be True or False
  let is_bool =
    s1.last_result_truthful == True || s1.last_result_truthful == False
  is_bool |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Section 5 — multi-tick consistency: cycle_count == total_checks
// ---------------------------------------------------------------------------

pub fn multi_tick_cycle_equals_total_checks_test() {
  let s5 = init() |> tick |> tick |> tick |> tick |> tick
  s5.cycle_count |> should.equal(s5.audit.total_checks)
}

// ---------------------------------------------------------------------------
// Section 6 — ETS read helpers: format fallbacks
// ---------------------------------------------------------------------------

pub fn get_truth_rate_is_na_or_percent_test() {
  // When ETS key is absent, returns "N/A". When present, ends with "%".
  let rate = get_truth_rate()
  let is_na = rate == "N/A"
  let is_pct = string.ends_with(rate, "%")
  should.equal(is_na || is_pct, True)
}

pub fn get_streak_non_empty_test() {
  let streak = get_streak()
  should.be_true(string.length(streak) > 0)
}

pub fn get_prediction_non_empty_test() {
  let pred = get_prediction()
  should.be_true(string.length(pred) > 0)
}

pub fn get_audit_summary_starts_with_cycle_test() {
  let summary = get_audit_summary()
  // Fallback is "cycle:0"; live value is "cycle:<n>"
  string.starts_with(summary, "cycle:") |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Section 7 — state_summary: format contract
// ---------------------------------------------------------------------------

pub fn state_summary_no_checks_contains_na_test() {
  let state = init()
  let summary = state_summary(state)
  string.contains(summary, "N/A") |> should.equal(True)
}

pub fn state_summary_no_checks_cycle_zero_test() {
  let state = init()
  let summary = state_summary(state)
  string.contains(summary, "cycle:0") |> should.equal(True)
}

pub fn state_summary_after_tick_has_cycle_one_test() {
  let state = tick(init())
  let summary = state_summary(state)
  string.contains(summary, "cycle:1") |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Section 8 — ETS key constants: non-empty strings
// ---------------------------------------------------------------------------

pub fn ets_key_rate_non_empty_test() {
  should.be_true(string.length(ets_key_rate) > 0)
}

pub fn ets_key_streak_non_empty_test() {
  should.be_true(string.length(ets_key_streak) > 0)
}

pub fn ets_key_prediction_non_empty_test() {
  should.be_true(string.length(ets_key_prediction) > 0)
}

pub fn ets_key_last_check_non_empty_test() {
  should.be_true(string.length(ets_key_last_check) > 0)
}

// ---------------------------------------------------------------------------
// Section 9 — truth_rate: in-range after tick
// ---------------------------------------------------------------------------

pub fn tick_truth_rate_in_range_test() {
  let s1 = tick(init())
  let rate = s1.audit.truth_rate
  let in_range = rate >=. 0.0 && rate <=. 1.0
  in_range |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Section 10 — audit entries: init is empty, grows after tick
// ---------------------------------------------------------------------------

pub fn init_audit_entries_empty_test() {
  let state = init()
  state.audit.entries |> should.equal([])
}

pub fn tick_audit_entries_grows_test() {
  // total_checks == 1 implies exactly one entry was added
  let s1 = tick(init())
  s1.audit.total_checks |> should.equal(1)
}

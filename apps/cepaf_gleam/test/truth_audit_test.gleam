//// =============================================================================
//// [C3I-SIL6-MSTS] TRUTH AUDIT TESTS — Satya Plan Sprint 4
//// =============================================================================
////
//// मत्तः स्मृतिर्ज्ञानमपोहनं च
//// From Me come memory, knowledge, and their removal (Gita 15.15)
////
//// Tests for the truth audit trail module (ha/truth_audit.gleam).
////
//// Coverage (24 tests):
////   Section 1 — init: empty / zero state
////   Section 2 — record: single entry accumulation
////   Section 3 — truth_rate: edge cases (0/0, all-pass, 50-50)
////   Section 4 — most_failing: frequency ranking
////   Section 5 — predict_next_failure: mirrors most_failing
////   Section 6 — failure_count_for: specific invariant lookup
////   Section 7 — recent: last-N slicing
////   Section 8 — truthful_streak: consecutive pass/fail window
////   Section 9 — to_json: structure and key presence
////   Section 10 — summary: non-empty, rate formatting
////   Section 11 — accumulation across multiple entries
////   Section 12 — edge cases (empty state, zero count queries)
////
//// STAMP: SC-SATYA-001, SC-TRUTH-001, SC-SIL4-001, SC-GLM-UI-001
//// Layer: L5_COGNITIVE

import cepaf_gleam/ha/truth_audit.{
  type TruthAuditEntry, TruthAuditEntry, failure_count_for, init, most_failing,
  predict_next_failure, recent, record, summary, to_json, truth_rate,
  truthful_streak,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a passing entry at the given check_id.
fn pass_entry(id: Int) -> TruthAuditEntry {
  TruthAuditEntry(
    check_id: id,
    page: "planning",
    all_truthful: True,
    passed_count: 12,
    failed_count: 0,
    failed_ids: [],
    timestamp: id,
  )
}

/// Build a failing entry with the given failed invariant IDs.
fn fail_entry(id: Int, failed_ids: List(String)) -> TruthAuditEntry {
  TruthAuditEntry(
    check_id: id,
    page: "planning",
    all_truthful: False,
    passed_count: 12 - list.length(failed_ids),
    failed_count: list.length(failed_ids),
    failed_ids: failed_ids,
    timestamp: id,
  )
}

// =============================================================================
// Section 1 — init: empty / zero state
// =============================================================================

pub fn init_total_checks_zero_test() {
  init().total_checks |> should.equal(0)
}

pub fn init_truthful_checks_zero_test() {
  init().truthful_checks |> should.equal(0)
}

pub fn init_lying_checks_zero_test() {
  init().lying_checks |> should.equal(0)
}

pub fn init_truth_rate_zero_test() {
  init().truth_rate |> should.equal(0.0)
}

pub fn init_entries_empty_test() {
  init().entries |> should.equal([])
}

pub fn init_failure_counts_empty_test() {
  init().failure_counts |> should.equal([])
}

pub fn init_most_failing_invariant_none_test() {
  init().most_failing_invariant |> should.equal("none")
}

// =============================================================================
// Section 2 — record: single entry accumulation
// =============================================================================

pub fn record_pass_increments_total_checks_test() {
  let s = record(init(), pass_entry(1))
  s.total_checks |> should.equal(1)
}

pub fn record_pass_increments_truthful_checks_test() {
  let s = record(init(), pass_entry(1))
  s.truthful_checks |> should.equal(1)
}

pub fn record_pass_does_not_increment_lying_test() {
  let s = record(init(), pass_entry(1))
  s.lying_checks |> should.equal(0)
}

pub fn record_fail_increments_lying_checks_test() {
  let s = record(init(), fail_entry(1, ["I-04"]))
  s.lying_checks |> should.equal(1)
}

pub fn record_fail_does_not_increment_truthful_test() {
  let s = record(init(), fail_entry(1, ["I-04"]))
  s.truthful_checks |> should.equal(0)
}

pub fn record_adds_entry_most_recent_first_test() {
  let s0 = init()
  let s1 = record(s0, pass_entry(1))
  let s2 = record(s1, pass_entry(2))
  // Most recent (id=2) should be at head
  case s2.entries {
    [e, ..] -> e.check_id |> should.equal(2)
    [] -> should.fail()
  }
}

// =============================================================================
// Section 3 — truth_rate edge cases
// =============================================================================

pub fn truth_rate_empty_state_is_zero_test() {
  truth_rate(init()) |> should.equal(0.0)
}

pub fn truth_rate_all_pass_is_one_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
    |> record(pass_entry(3))
  truth_rate(s) |> should.equal(1.0)
}

pub fn truth_rate_no_pass_is_zero_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-01"]))
    |> record(fail_entry(2, ["I-01"]))
  truth_rate(s) |> should.equal(0.0)
}

pub fn truth_rate_half_pass_is_half_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(fail_entry(2, ["I-04"]))
  // 1 truthful / 2 total = 0.5
  { truth_rate(s) >. 0.49 && truth_rate(s) <. 0.51 } |> should.be_true()
}

// =============================================================================
// Section 4 — most_failing frequency ranking
// =============================================================================

pub fn most_failing_empty_state_is_none_test() {
  most_failing(init()) |> should.equal("none")
}

pub fn most_failing_single_failure_returns_that_id_test() {
  let s = record(init(), fail_entry(1, ["I-07"]))
  most_failing(s) |> should.equal("I-07")
}

pub fn most_failing_returns_most_frequent_id_test() {
  // I-04 fails 3 times, I-01 fails 1 time — I-04 should win
  let s =
    init()
    |> record(fail_entry(1, ["I-04"]))
    |> record(fail_entry(2, ["I-04", "I-01"]))
    |> record(fail_entry(3, ["I-04"]))
  most_failing(s) |> should.equal("I-04")
}

pub fn most_failing_not_changed_by_pass_entry_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-09"]))
    |> record(pass_entry(2))
    |> record(pass_entry(3))
  most_failing(s) |> should.equal("I-09")
}

// =============================================================================
// Section 5 — predict_next_failure mirrors most_failing
// =============================================================================

pub fn predict_next_failure_empty_is_none_test() {
  predict_next_failure(init()) |> should.equal("none")
}

pub fn predict_next_failure_matches_most_failing_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-03"]))
    |> record(fail_entry(2, ["I-03"]))
    |> record(fail_entry(3, ["I-11"]))
  // I-03 has count 2, I-11 has count 1
  predict_next_failure(s) |> should.equal(most_failing(s))
}

pub fn predict_next_failure_is_most_frequent_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-06"]))
    |> record(fail_entry(2, ["I-06"]))
    |> record(fail_entry(3, ["I-06"]))
    |> record(fail_entry(4, ["I-01"]))
  predict_next_failure(s) |> should.equal("I-06")
}

// =============================================================================
// Section 6 — failure_count_for specific invariant
// =============================================================================

pub fn failure_count_for_absent_id_is_zero_test() {
  failure_count_for(init(), "I-99") |> should.equal(0)
}

pub fn failure_count_for_present_id_is_correct_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-04"]))
    |> record(fail_entry(2, ["I-04"]))
    |> record(fail_entry(3, ["I-01"]))
  failure_count_for(s, "I-04") |> should.equal(2)
}

pub fn failure_count_for_another_id_correct_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-04"]))
    |> record(fail_entry(2, ["I-04"]))
    |> record(fail_entry(3, ["I-01"]))
  failure_count_for(s, "I-01") |> should.equal(1)
}

pub fn failure_count_for_never_failed_id_zero_test() {
  let s =
    init()
    |> record(fail_entry(1, ["I-04"]))
  failure_count_for(s, "I-07") |> should.equal(0)
}

// =============================================================================
// Section 7 — recent: last-N slicing
// =============================================================================

pub fn recent_zero_count_returns_empty_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
  recent(s, 0) |> should.equal([])
}

pub fn recent_negative_count_returns_empty_test() {
  let s = record(init(), pass_entry(1))
  recent(s, -5) |> should.equal([])
}

pub fn recent_more_than_total_returns_all_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
  list.length(recent(s, 100)) |> should.equal(2)
}

pub fn recent_returns_correct_count_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
    |> record(pass_entry(3))
    |> record(pass_entry(4))
    |> record(pass_entry(5))
  list.length(recent(s, 3)) |> should.equal(3)
}

pub fn recent_returns_most_recent_first_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
    |> record(pass_entry(3))
  case recent(s, 2) {
    [first, _second] -> first.check_id |> should.equal(3)
    _ -> should.fail()
  }
}

// =============================================================================
// Section 8 — truthful_streak
// =============================================================================

pub fn truthful_streak_zero_n_is_true_test() {
  truthful_streak(init(), 0) |> should.be_true()
}

pub fn truthful_streak_negative_n_is_true_test() {
  truthful_streak(init(), -1) |> should.be_true()
}

pub fn truthful_streak_empty_state_n1_is_false_test() {
  // No entries yet — streak of 1 cannot be established
  truthful_streak(init(), 1) |> should.be_false()
}

pub fn truthful_streak_insufficient_entries_is_false_test() {
  // Only 2 entries, asking for streak of 5
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
  truthful_streak(s, 5) |> should.be_false()
}

pub fn truthful_streak_all_pass_is_true_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
    |> record(pass_entry(3))
  truthful_streak(s, 3) |> should.be_true()
}

pub fn truthful_streak_recent_failure_breaks_streak_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
    |> record(fail_entry(3, ["I-04"]))
  // Most recent entry is a failure → streak of 3 broken
  truthful_streak(s, 3) |> should.be_false()
}

pub fn truthful_streak_older_failure_outside_window_is_true_test() {
  // Failure at check 1, then 3 consecutive passes — streak of 3 should be true
  let s =
    init()
    |> record(fail_entry(1, ["I-04"]))
    |> record(pass_entry(2))
    |> record(pass_entry(3))
    |> record(pass_entry(4))
  truthful_streak(s, 3) |> should.be_true()
}

// =============================================================================
// Section 9 — to_json structure
// =============================================================================

pub fn to_json_contains_total_checks_test() {
  let s = record(init(), pass_entry(1))
  string.contains(to_json(s), "\"total_checks\"") |> should.be_true()
}

pub fn to_json_contains_truth_rate_test() {
  let s = record(init(), pass_entry(1))
  string.contains(to_json(s), "\"truth_rate\"") |> should.be_true()
}

pub fn to_json_contains_most_failing_invariant_test() {
  let s = record(init(), fail_entry(1, ["I-04"]))
  string.contains(to_json(s), "\"most_failing_invariant\"") |> should.be_true()
}

pub fn to_json_contains_failure_counts_test() {
  let s = record(init(), fail_entry(1, ["I-03"]))
  string.contains(to_json(s), "\"failure_counts\"") |> should.be_true()
}

pub fn to_json_contains_recent_entries_test() {
  let s = record(init(), pass_entry(1))
  string.contains(to_json(s), "\"recent_entries\"") |> should.be_true()
}

pub fn to_json_is_valid_json_structure_test() {
  let s = record(init(), fail_entry(1, ["I-04"]))
  let j = to_json(s)
  // Minimal structural validation: starts with { ends with }
  string.starts_with(j, "{") |> should.be_true()
  string.ends_with(j, "}") |> should.be_true()
}

pub fn to_json_empty_state_is_valid_test() {
  let j = to_json(init())
  string.starts_with(j, "{") |> should.be_true()
  string.contains(j, "\"total_checks\":0") |> should.be_true()
}

// =============================================================================
// Section 10 — summary
// =============================================================================

pub fn summary_is_non_empty_test() {
  { string.length(summary(init())) > 0 } |> should.be_true()
}

pub fn summary_contains_truth_audit_test() {
  string.contains(summary(init()), "TRUTH-AUDIT") |> should.be_true()
}

pub fn summary_contains_checks_count_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
  string.contains(summary(s), "checks:2") |> should.be_true()
}

pub fn summary_contains_rate_when_checks_exist_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(pass_entry(2))
  // 2/2 = 100%
  string.contains(summary(s), "rate:100%") |> should.be_true()
}

pub fn summary_shows_na_for_empty_state_test() {
  string.contains(summary(init()), "rate:N/A") |> should.be_true()
}

pub fn summary_contains_most_failing_test() {
  let s = record(init(), fail_entry(1, ["I-08"]))
  string.contains(summary(s), "most_failing:I-08") |> should.be_true()
}

// =============================================================================
// Section 11 — accumulation across multiple entries
// =============================================================================

pub fn multiple_entries_accumulate_correctly_test() {
  let s =
    init()
    |> record(pass_entry(1))
    |> record(fail_entry(2, ["I-04"]))
    |> record(fail_entry(3, ["I-04", "I-01"]))
    |> record(pass_entry(4))
    |> record(pass_entry(5))
  s.total_checks |> should.equal(5)
  s.truthful_checks |> should.equal(3)
  s.lying_checks |> should.equal(2)
  // I-04 failed 2 times, I-01 failed 1 time
  failure_count_for(s, "I-04") |> should.equal(2)
  failure_count_for(s, "I-01") |> should.equal(1)
  most_failing(s) |> should.equal("I-04")
}

pub fn failure_counts_sorted_descending_test() {
  // I-03 fails 3×, I-01 fails 1×, I-09 fails 2×
  let s =
    init()
    |> record(fail_entry(1, ["I-03"]))
    |> record(fail_entry(2, ["I-09", "I-01"]))
    |> record(fail_entry(3, ["I-03"]))
    |> record(fail_entry(4, ["I-09"]))
    |> record(fail_entry(5, ["I-03"]))
  // Counts should be: I-03=3, I-09=2, I-01=1
  failure_count_for(s, "I-03") |> should.equal(3)
  failure_count_for(s, "I-09") |> should.equal(2)
  failure_count_for(s, "I-01") |> should.equal(1)
  most_failing(s) |> should.equal("I-03")
}

// =============================================================================
// Section 12 — edge cases
// =============================================================================

pub fn single_pass_truth_rate_is_one_test() {
  let s = record(init(), pass_entry(1))
  truth_rate(s) |> should.equal(1.0)
}

pub fn single_fail_truth_rate_is_zero_test() {
  let s = record(init(), fail_entry(1, ["I-04"]))
  truth_rate(s) |> should.equal(0.0)
}

pub fn audit_entry_fields_accessible_test() {
  let e =
    TruthAuditEntry(
      check_id: 42,
      page: "cockpit",
      all_truthful: False,
      passed_count: 10,
      failed_count: 2,
      failed_ids: ["I-01", "I-04"],
      timestamp: 42,
    )
  e.check_id |> should.equal(42)
  e.page |> should.equal("cockpit")
  e.all_truthful |> should.be_false()
  e.passed_count |> should.equal(10)
  e.failed_count |> should.equal(2)
  list.length(e.failed_ids) |> should.equal(2)
}

pub fn audit_trail_state_fields_accessible_test() {
  let s = init()
  s.total_checks |> should.equal(0)
  s.truthful_checks |> should.equal(0)
  s.lying_checks |> should.equal(0)
  s.truth_rate |> should.equal(0.0)
  s.most_failing_invariant |> should.equal("none")
  s.failure_counts |> should.equal([])
  s.entries |> should.equal([])
}

pub fn record_entry_with_multiple_failed_ids_test() {
  let e = fail_entry(1, ["I-01", "I-04", "I-08"])
  let s = record(init(), e)
  failure_count_for(s, "I-01") |> should.equal(1)
  failure_count_for(s, "I-04") |> should.equal(1)
  failure_count_for(s, "I-08") |> should.equal(1)
  s.lying_checks |> should.equal(1)
}

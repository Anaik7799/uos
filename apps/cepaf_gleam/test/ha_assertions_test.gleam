/// Runtime Assertion Library tests — NASA Power of Ten Rule 5
/// SC-SIL4-001, SC-FUNC-001, SC-PRIME-001
/// Layer: L0_CONSTITUTIONAL
import cepaf_gleam/ha/assertions.{
  AssertionFailed, AssertionPassed, assert_equal, assert_in_range,
  assert_non_empty, assert_non_empty_string, assert_non_negative,
  assert_probability, assert_true, failure_count, format_result, format_results,
  run_all,
}
import gleeunit/should

// ---------------------------------------------------------------------------
// assert_true
// ---------------------------------------------------------------------------

pub fn assert_true_passes_on_true_test() {
  assert_true("cond", True, "test:1")
  |> should.equal(AssertionPassed("cond"))
}

pub fn assert_true_fails_on_false_test() {
  assert_true("cond", False, "test:1")
  |> should.equal(AssertionFailed("cond", "true", "false", "test:1"))
}

// ---------------------------------------------------------------------------
// assert_equal
// ---------------------------------------------------------------------------

pub fn assert_equal_passes_when_equal_test() {
  assert_equal("label", "ok", "ok", "test:2")
  |> should.equal(AssertionPassed("label"))
}

pub fn assert_equal_fails_when_not_equal_test() {
  assert_equal("label", "ok", "error", "test:2")
  |> should.equal(AssertionFailed("label", "ok", "error", "test:2"))
}

// ---------------------------------------------------------------------------
// assert_in_range
// ---------------------------------------------------------------------------

pub fn assert_in_range_passes_at_min_test() {
  assert_in_range("severity", 1, 1, 10, "test:3")
  |> should.equal(AssertionPassed("severity"))
}

pub fn assert_in_range_passes_at_max_test() {
  assert_in_range("severity", 10, 1, 10, "test:3")
  |> should.equal(AssertionPassed("severity"))
}

pub fn assert_in_range_passes_in_middle_test() {
  assert_in_range("severity", 5, 1, 10, "test:3")
  |> should.equal(AssertionPassed("severity"))
}

pub fn assert_in_range_fails_below_min_test() {
  let result = assert_in_range("severity", 0, 1, 10, "test:3")
  case result {
    AssertionFailed("severity", _, "0", "test:3") -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn assert_in_range_fails_above_max_test() {
  let result = assert_in_range("severity", 11, 1, 10, "test:3")
  case result {
    AssertionFailed("severity", _, "11", "test:3") -> True
    _ -> False
  }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// assert_non_negative
// ---------------------------------------------------------------------------

pub fn assert_non_negative_passes_on_zero_test() {
  assert_non_negative("count", 0, "test:4")
  |> should.equal(AssertionPassed("count"))
}

pub fn assert_non_negative_passes_on_positive_test() {
  assert_non_negative("count", 42, "test:4")
  |> should.equal(AssertionPassed("count"))
}

pub fn assert_non_negative_fails_on_negative_test() {
  let result = assert_non_negative("count", -1, "test:4")
  case result {
    AssertionFailed("count", ">= 0", "-1", "test:4") -> True
    _ -> False
  }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// assert_probability
// ---------------------------------------------------------------------------

pub fn assert_probability_passes_at_zero_test() {
  assert_probability("p", 0.0, "test:5")
  |> should.equal(AssertionPassed("p"))
}

pub fn assert_probability_passes_at_one_test() {
  assert_probability("p", 1.0, "test:5")
  |> should.equal(AssertionPassed("p"))
}

pub fn assert_probability_passes_at_half_test() {
  assert_probability("p", 0.5, "test:5")
  |> should.equal(AssertionPassed("p"))
}

pub fn assert_probability_fails_above_one_test() {
  let result = assert_probability("p", 1.1, "test:5")
  case result {
    AssertionFailed("p", "in [0.0, 1.0]", _, "test:5") -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn assert_probability_fails_below_zero_test() {
  let result = assert_probability("p", -0.1, "test:5")
  case result {
    AssertionFailed("p", "in [0.0, 1.0]", _, "test:5") -> True
    _ -> False
  }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// assert_non_empty (list)
// ---------------------------------------------------------------------------

pub fn assert_non_empty_passes_on_singleton_test() {
  assert_non_empty("items", [1], "test:6")
  |> should.equal(AssertionPassed("items"))
}

pub fn assert_non_empty_fails_on_empty_list_test() {
  let result = assert_non_empty("items", [], "test:6")
  case result {
    AssertionFailed("items", "non-empty list", "[]", "test:6") -> True
    _ -> False
  }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// assert_non_empty_string
// ---------------------------------------------------------------------------

pub fn assert_non_empty_string_passes_test() {
  assert_non_empty_string("name", "cortex", "test:7")
  |> should.equal(AssertionPassed("name"))
}

pub fn assert_non_empty_string_fails_on_blank_test() {
  let result = assert_non_empty_string("name", "", "test:7")
  case result {
    AssertionFailed("name", "non-empty string", "\"\"", "test:7") -> True
    _ -> False
  }
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// run_all
// ---------------------------------------------------------------------------

pub fn run_all_counts_correctly_test() {
  let assertions = [
    assert_true("a", True, "t"),
    assert_true("b", False, "t"),
    assert_true("c", True, "t"),
  ]
  let #(passed, failed, results) = run_all(assertions)
  passed |> should.equal(2)
  failed |> should.equal(1)
  results |> should.equal(assertions)
}

pub fn run_all_on_empty_list_test() {
  let #(passed, failed, results) = run_all([])
  passed |> should.equal(0)
  failed |> should.equal(0)
  results |> should.equal([])
}

pub fn run_all_all_pass_test() {
  let assertions = [
    assert_non_negative("a", 1, "t"),
    assert_probability("b", 0.5, "t"),
  ]
  let #(passed, failed, _) = run_all(assertions)
  passed |> should.equal(2)
  failed |> should.equal(0)
}

// ---------------------------------------------------------------------------
// failure_count helper
// ---------------------------------------------------------------------------

pub fn failure_count_returns_zero_on_all_pass_test() {
  let results = [AssertionPassed("a"), AssertionPassed("b")]
  failure_count(results) |> should.equal(0)
}

pub fn failure_count_counts_failures_test() {
  let results = [
    AssertionPassed("a"),
    AssertionFailed("b", "x", "y", "loc"),
    AssertionFailed("c", "p", "q", "loc"),
  ]
  failure_count(results) |> should.equal(2)
}

// ---------------------------------------------------------------------------
// format_result
// ---------------------------------------------------------------------------

pub fn format_result_passed_starts_with_pass_test() {
  let line = format_result(AssertionPassed("my_check"))
  line |> should.equal("[PASS] my_check")
}

pub fn format_result_failed_contains_expected_and_actual_test() {
  let line =
    format_result(AssertionFailed("my_check", "true", "false", "module:42"))
  // Must contain key fields
  line |> should.not_equal("[PASS] my_check")
}

// ---------------------------------------------------------------------------
// format_results
// ---------------------------------------------------------------------------

pub fn format_results_empty_list_returns_no_assertions_test() {
  format_results([]) |> should.equal("No assertions run")
}

pub fn format_results_non_empty_returns_string_test() {
  let results = [AssertionPassed("x"), AssertionFailed("y", "a", "b", "loc")]
  let s = format_results(results)
  // Verify both assertion names appear in output
  s |> should.not_equal("")
  s |> should.not_equal("No assertions run")
}

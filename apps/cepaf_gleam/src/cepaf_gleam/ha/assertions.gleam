//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/assertions</module>
////     <fsharp-lineage>None — novel NASA Power-of-Ten runtime assertion library (F01)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Runtime Assertion Library (F01). NASA Power of Ten Rule 5 compliance:
////       assertion density >= 2 per function. Provides typed assertion helpers
////       for safety-critical code paths across all fractal layers. Assertions
////       are pure functions — they never panic, they return typed results.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>SC-SIL4-001, SC-FUNC-001, SC-FUNC-002, SC-MUDA-001, SC-PRIME-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       NASA Power-of-Ten assert() macro ↪ Gleam typed Result.
////       No panic — every failure is a typed AssertionFailed value.
////       Caller decides whether to halt, log, or continue.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// RUNTIME ASSERTION LIBRARY — NASA POWER OF TEN RULE 5
//// धर्मक्षेत्रे — The field of dharma (Gita 1.1)
////
//// NASA Power of Ten (JPL-2004) Rule 5:
////   "Use of assertion macros should average at minimum two assertions per function."
////
//// Design principles:
////   1. NEVER PANIC — assertions return AssertionResult, not exceptions
////   2. TYPED — all failures carry name + expected + actual + location
////   3. PURE — zero side effects; caller owns the response to failures
////   4. COMPOSABLE — run_all/1 gathers N assertions into a single pass/fail summary
////   5. OBSERVABLE — format_results/1 produces human-readable output for Zenoh telemetry
////
//// Usage pattern (two assertions per function, Rule 5 compliance):
////
////   pub fn update_health(count: Int, max: Int) -> Result(Int, String) {
////     let a1 = assertions.assert_non_negative("count", count, "update_health:1")
////     let a2 = assertions.assert_in_range("count_le_max", count, 0, max, "update_health:2")
////     case assertions.run_all([a1, a2]) {
////       #(_, 0, _) -> Ok(count)
////       #(_, _, results) -> Error(assertions.format_results(results))
////     }
////   }
////
//// STAMP: SC-SIL4-001, SC-FUNC-001, SC-FUNC-002, SC-MUDA-001, SC-PRIME-001

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Result of a single named assertion check.
/// Carries structured information so failures can be routed to Zenoh telemetry.
pub type AssertionResult {
  AssertionPassed(name: String)
  AssertionFailed(
    name: String,
    expected: String,
    actual: String,
    location: String,
  )
}

// ---------------------------------------------------------------------------
// Core assertion constructors
// ---------------------------------------------------------------------------

/// Assert that a boolean condition holds.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">assert(cond) ↪ AssertionPassed | AssertionFailed</morphism>
///   <formal-proof>
///     <P> Pre: name, location are non-empty strings; condition is Bool </P>
///     <C> assert_true(name, condition, location) </C>
///     <Q> Post: AssertionPassed iff condition == True; never panics </Q>
///   </formal-proof>
/// </c3i-atomic>
///
/// NASA Rule 5: use at least twice per function (pre- and post-condition).
pub fn assert_true(
  name: String,
  condition: Bool,
  location: String,
) -> AssertionResult {
  case condition {
    True -> AssertionPassed(name)
    False ->
      AssertionFailed(
        name: name,
        expected: "true",
        actual: "false",
        location: location,
      )
  }
}

/// Assert that two string representations are equal.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: name, expected, actual, location are well-formed strings </P>
///     <C> assert_equal(name, expected, actual, location) </C>
///     <Q> Post: AssertionPassed iff expected == actual </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn assert_equal(
  name: String,
  expected: String,
  actual: String,
  location: String,
) -> AssertionResult {
  case expected == actual {
    True -> AssertionPassed(name)
    False ->
      AssertionFailed(
        name: name,
        expected: expected,
        actual: actual,
        location: location,
      )
  }
}

/// Assert that an integer is in the closed interval [min, max].
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: min <= max (caller responsibility); value is Int </P>
///     <C> assert_in_range(name, value, min, max, location) </C>
///     <Q> Post: AssertionPassed iff min <= value <= max </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn assert_in_range(
  name: String,
  value: Int,
  min: Int,
  max: Int,
  location: String,
) -> AssertionResult {
  case value >= min && value <= max {
    True -> AssertionPassed(name)
    False ->
      AssertionFailed(
        name: name,
        expected: "in ["
          <> int.to_string(min)
          <> ", "
          <> int.to_string(max)
          <> "]",
        actual: int.to_string(value),
        location: location,
      )
  }
}

/// Assert that an integer is non-negative (>= 0).
/// Prerequisite for counts, indices, and durations.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: value is Int </P>
///     <C> assert_non_negative(name, value, location) </C>
///     <Q> Post: AssertionPassed iff value >= 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn assert_non_negative(
  name: String,
  value: Int,
  location: String,
) -> AssertionResult {
  case value >= 0 {
    True -> AssertionPassed(name)
    False ->
      AssertionFailed(
        name: name,
        expected: ">= 0",
        actual: int.to_string(value),
        location: location,
      )
  }
}

/// Assert that a float is a valid probability: in [0.0, 1.0].
/// Used for RPN-derived scores, SLO targets, confidence values.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: value is Float </P>
///     <C> assert_probability(name, value, location) </C>
///     <Q> Post: AssertionPassed iff 0.0 <= value <= 1.0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn assert_probability(
  name: String,
  value: Float,
  location: String,
) -> AssertionResult {
  case value >=. 0.0 && value <=. 1.0 {
    True -> AssertionPassed(name)
    False ->
      AssertionFailed(
        name: name,
        expected: "in [0.0, 1.0]",
        actual: float.to_string(value),
        location: location,
      )
  }
}

/// Assert that a list is non-empty.
/// Guards against empty slices propagating into render functions.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: items is List(a) </P>
///     <C> assert_non_empty(name, items, location) </C>
///     <Q> Post: AssertionPassed iff list.length(items) > 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn assert_non_empty(
  name: String,
  items: List(a),
  location: String,
) -> AssertionResult {
  case items {
    [_, ..] -> AssertionPassed(name)
    [] ->
      AssertionFailed(
        name: name,
        expected: "non-empty list",
        actual: "[]",
        location: location,
      )
  }
}

/// Assert that a string is non-empty (length > 0).
/// Guards against blank identifiers or component names reaching the system.
pub fn assert_non_empty_string(
  name: String,
  value: String,
  location: String,
) -> AssertionResult {
  case string.length(value) > 0 {
    True -> AssertionPassed(name)
    False ->
      AssertionFailed(
        name: name,
        expected: "non-empty string",
        actual: "\"\"",
        location: location,
      )
  }
}

// ---------------------------------------------------------------------------
// Batch runner
// ---------------------------------------------------------------------------

/// Run a list of assertions and return a summary triple.
///
/// Returns #(passed_count, failed_count, all_results).
/// The all_results list preserves original order for structured reporting.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: assertions is a finite List(AssertionResult) </P>
///     <C> run_all(assertions) </C>
///     <Q> Post: passed + failed == list.length(assertions); all_results == assertions </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn run_all(
  assertions: List(AssertionResult),
) -> #(Int, Int, List(AssertionResult)) {
  let passed =
    list.count(assertions, fn(r) {
      case r {
        AssertionPassed(_) -> True
        AssertionFailed(_, _, _, _) -> False
      }
    })
  let failed = list.length(assertions) - passed
  #(passed, failed, assertions)
}

/// Return True if every assertion in the list passed.
pub fn all_passed(assertions: List(AssertionResult)) -> Bool {
  list.all(assertions, fn(r) {
    case r {
      AssertionPassed(_) -> True
      AssertionFailed(_, _, _, _) -> False
    }
  })
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/// Format a single assertion result as a human-readable line.
pub fn format_result(result: AssertionResult) -> String {
  case result {
    AssertionPassed(name) -> "[PASS] " <> name
    AssertionFailed(name, expected, actual, location) ->
      "[FAIL] "
      <> name
      <> " at "
      <> location
      <> " — expected: "
      <> expected
      <> ", actual: "
      <> actual
  }
}

/// Format a list of assertion results as a newline-separated report string.
/// Suitable for Zenoh OTel span payloads and log entries.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre: results is List(AssertionResult) </P>
///     <C> format_results(results) </C>
///     <Q> Post: Returns a non-empty String even for empty input ("No assertions run") </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn format_results(results: List(AssertionResult)) -> String {
  case results {
    [] -> "No assertions run"
    _ ->
      results
      |> list.map(format_result)
      |> string.join("\n")
  }
}

/// Count failures in a result list.
pub fn failure_count(results: List(AssertionResult)) -> Int {
  list.count(results, fn(r) {
    case r {
      AssertionFailed(_, _, _, _) -> True
      AssertionPassed(_) -> False
    }
  })
}

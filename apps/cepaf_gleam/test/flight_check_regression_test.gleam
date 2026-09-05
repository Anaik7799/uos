//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/test/flight_check_regression_test</module>
////     <fsharp-lineage>Cepaf.Testing.FlightCheck</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>Flight Check Preflight Regression Tests</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-TPS-001, SC-FUNC-001, SC-VER-001, SC-GLM-TST-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// 20 regression tests for cepaf_gleam/testing/flight_check.gleam.
//// Covers: FlightResult, CheckStatus helpers, fractal RCA, Jidoka halt,
//// format output, FlightDecision, and individual check functions.

import cepaf_gleam/testing/flight_check.{
  type FlightResult, type RcaReport, CheckFailed, CheckPassed, CheckSkipped,
  FlightCheck, GoForLaunch, check_count, check_federation, check_gleam_build,
  check_passed, check_zenoh_reachable, format_flight_result, fractal_rca,
  jidoka_halt, passed_count, run_preflight,
}
import cepaf_gleam/ui/domain.{
  L0Constitutional, L1AtomicDebug, L3Transaction, L6Ecosystem,
}
import gleam/list
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Test 1: run_preflight returns a FlightResult (usable as typed value)
// ---------------------------------------------------------------------------

pub fn run_preflight_returns_flight_result_test() {
  let result: FlightResult = run_preflight()
  check_count(result) |> should.equal(10)
}

// ---------------------------------------------------------------------------
// Test 2: run_preflight default — all checks pass
// ---------------------------------------------------------------------------

pub fn run_preflight_default_all_pass_test() {
  let result = run_preflight()
  result.passed |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 3: check_passed returns True for CheckPassed
// ---------------------------------------------------------------------------

pub fn check_passed_for_check_passed_test() {
  let fc =
    FlightCheck(
      name: "test",
      layer: L1AtomicDebug,
      status: CheckPassed,
      duration_ms: 0,
    )
  check_passed(fc) |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 4: check_passed returns False for CheckFailed
// ---------------------------------------------------------------------------

pub fn check_passed_for_check_failed_test() {
  let fc =
    FlightCheck(
      name: "test",
      layer: L1AtomicDebug,
      status: CheckFailed("build error"),
      duration_ms: 0,
    )
  check_passed(fc) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// Test 5: check_passed returns False for CheckSkipped
// ---------------------------------------------------------------------------

pub fn check_passed_for_check_skipped_test() {
  let fc =
    FlightCheck(
      name: "test",
      layer: L1AtomicDebug,
      status: CheckSkipped("not applicable"),
      duration_ms: 0,
    )
  check_passed(fc) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// Test 6: passed_count on full-pass result — 9 checks truly pass
//         (federation is CheckSkipped, not CheckPassed, so passed_count is 9)
// ---------------------------------------------------------------------------

pub fn passed_count_on_full_pass_result_test() {
  let result = run_preflight()
  passed_count(result) |> should.equal(9)
}

// ---------------------------------------------------------------------------
// Test 7: check_count returns 8
// ---------------------------------------------------------------------------

pub fn check_count_returns_eight_test() {
  let result = run_preflight()
  check_count(result) |> should.equal(10)
}

// ---------------------------------------------------------------------------
// Test 8: fractal_rca on L0 failure → jidoka_halt = True
// ---------------------------------------------------------------------------

pub fn fractal_rca_l0_failure_jidoka_halt_true_test() {
  let fc =
    FlightCheck(
      name: "Guardian",
      layer: L0Constitutional,
      status: CheckFailed("guardian unavailable"),
      duration_ms: 0,
    )
  let report: RcaReport = fractal_rca(fc)
  report.jidoka_halt |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 9: fractal_rca on L1 failure → jidoka_halt = True
// ---------------------------------------------------------------------------

pub fn fractal_rca_l1_failure_jidoka_halt_true_test() {
  let fc =
    FlightCheck(
      name: "Gleam Build",
      layer: L1AtomicDebug,
      status: CheckFailed("compilation errors"),
      duration_ms: 0,
    )
  let report = fractal_rca(fc)
  report.jidoka_halt |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 10: fractal_rca on L3 failure → jidoka_halt = False
// ---------------------------------------------------------------------------

pub fn fractal_rca_l3_failure_jidoka_halt_false_test() {
  let fc =
    FlightCheck(
      name: "Database",
      layer: L3Transaction,
      status: CheckFailed("db not reachable"),
      duration_ms: 0,
    )
  let report = fractal_rca(fc)
  report.jidoka_halt |> should.equal(False)
}

// ---------------------------------------------------------------------------
// Test 11: fractal_rca on L6 failure → jidoka_halt = True
// ---------------------------------------------------------------------------

pub fn fractal_rca_l6_failure_jidoka_halt_true_test() {
  let fc =
    FlightCheck(
      name: "Zenoh Router",
      layer: L6Ecosystem,
      status: CheckFailed("port 7447 unreachable"),
      duration_ms: 0,
    )
  let report = fractal_rca(fc)
  report.jidoka_halt |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 12: fractal_rca why_chain has exactly 5 items
// ---------------------------------------------------------------------------

pub fn fractal_rca_why_chain_has_five_items_test() {
  let fc =
    FlightCheck(
      name: "Guardian",
      layer: L0Constitutional,
      status: CheckFailed("safety kernel down"),
      duration_ms: 0,
    )
  let report = fractal_rca(fc)
  list.length(report.why_chain) |> should.equal(5)
}

// ---------------------------------------------------------------------------
// Test 13: jidoka_halt returns False when decision is GoForLaunch
// ---------------------------------------------------------------------------

pub fn jidoka_halt_on_go_for_launch_false_test() {
  let result = run_preflight()
  result.decision |> should.equal(GoForLaunch)
  jidoka_halt(result) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// Test 14: format_flight_result returns non-empty string
// ---------------------------------------------------------------------------

pub fn format_flight_result_non_empty_test() {
  let result = run_preflight()
  let output = format_flight_result(result)
  string.is_empty(output) |> should.equal(False)
}

// ---------------------------------------------------------------------------
// Test 15: format_flight_result contains "FLIGHT CHECK"
// ---------------------------------------------------------------------------

pub fn format_flight_result_contains_flight_check_test() {
  let result = run_preflight()
  let output = format_flight_result(result)
  string.contains(output, "FLIGHT CHECK") |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 16: FlightDecision is GoForLaunch when all checks pass
// ---------------------------------------------------------------------------

pub fn flight_decision_go_for_launch_when_all_pass_test() {
  let result = run_preflight()
  case result.decision {
    GoForLaunch -> True
    _ -> False
  }
  |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 17: check_gleam_build returns CheckPassed
// ---------------------------------------------------------------------------

pub fn check_gleam_build_returns_passed_test() {
  let fc = check_gleam_build()
  fc.status |> should.equal(CheckPassed)
}

// ---------------------------------------------------------------------------
// Test 18: check_zenoh_reachable returns CheckPassed
// ---------------------------------------------------------------------------

pub fn check_zenoh_reachable_returns_passed_test() {
  let fc = check_zenoh_reachable()
  fc.status |> should.equal(CheckPassed)
}

// ---------------------------------------------------------------------------
// Test 19: check_federation returns CheckSkipped
// ---------------------------------------------------------------------------

pub fn check_federation_returns_skipped_test() {
  let fc = check_federation()
  case fc.status {
    CheckSkipped(_) -> True
    _ -> False
  }
  |> should.equal(True)
}

// ---------------------------------------------------------------------------
// Test 20: RcaReport corrective_actions non-empty for L0 failure
// ---------------------------------------------------------------------------

pub fn rca_report_corrective_actions_non_empty_for_l0_test() {
  let fc =
    FlightCheck(
      name: "Guardian",
      layer: L0Constitutional,
      status: CheckFailed("safety kernel down"),
      duration_ms: 0,
    )
  let report = fractal_rca(fc)
  { report.corrective_actions != [] } |> should.equal(True)
}

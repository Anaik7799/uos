// OODA Test Monitor — Verification Tests
// Tests pre-flight checks, element monitoring, KPI computation, and dashboard rendering.
// STAMP: SC-GLM-ZEN-001, SC-GLM-TST-001, SC-GLM-TST-002

import cepaf_gleam/testing/ooda_test_monitor.{PreflightResult}
import cepaf_gleam/ui/domain.{Dashboard, Immune, Planning, Verification, Zenoh}
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Pre-flight Tests
// =============================================================================

pub fn preflight_returns_8_checks_test() {
  let results = ooda_test_monitor.run_preflight()
  list.length(results) |> should.equal(8)
}

pub fn preflight_all_pass_test() {
  let results = ooda_test_monitor.run_preflight()
  ooda_test_monitor.preflight_passed(results) |> should.be_true()
}

pub fn preflight_nif_loaded_test() {
  let results = ooda_test_monitor.run_preflight()
  let nif_check = list.find(results, fn(r) { r.check == "c3i_nif_loaded" })
  case nif_check {
    Ok(r) -> r.passed |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn preflight_nav_graph_test() {
  let results = ooda_test_monitor.run_preflight()
  let nav_check = list.find(results, fn(r) { r.check == "nav_graph_31_pages" })
  case nav_check {
    Ok(r) -> r.passed |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn jidoka_rca_on_all_pass_test() {
  let results = ooda_test_monitor.run_preflight()
  let rca = ooda_test_monitor.jidoka_rca(results)
  rca |> string.contains("Proceeding") |> should.be_true()
}

pub fn jidoka_rca_on_failure_test() {
  let failed = [
    PreflightResult(check: "test_fail", passed: False, detail: "FAILED"),
  ]
  let rca = ooda_test_monitor.jidoka_rca(failed)
  rca |> string.contains("JIDOKA") |> should.be_true()
  rca |> string.contains("Root Cause Analysis") |> should.be_true()
}

// =============================================================================
// Element Test Creation
// =============================================================================

pub fn element_test_passing_test() {
  let result =
    ooda_test_monitor.element_test(
      Dashboard,
      "health_card",
      0,
      True,
      15,
      "renders",
      "rendered",
    )
  result.passed |> should.be_true()
  result.corrective_action |> should.equal("None")
}

pub fn element_test_failing_test() {
  let result =
    ooda_test_monitor.element_test(
      Dashboard,
      "broken_widget",
      2,
      False,
      50,
      "click works",
      "no response",
    )
  result.passed |> should.be_false()
  result.corrective_action
  |> string.contains("Fix broken_widget")
  |> should.be_true()
}

// =============================================================================
// Tab KPI Computation
// =============================================================================

pub fn tab_kpi_all_pass_test() {
  let results = [
    ooda_test_monitor.element_test(Dashboard, "a", 0, True, 10, "", ""),
    ooda_test_monitor.element_test(Dashboard, "b", 1, True, 20, "", ""),
    ooda_test_monitor.element_test(Dashboard, "c", 2, True, 15, "", ""),
  ]
  let kpi = ooda_test_monitor.compute_tab_kpi(Dashboard, results)
  kpi.total_elements |> should.equal(3)
  kpi.passed |> should.equal(3)
  kpi.failed |> should.equal(0)
  { kpi.coverage_pct >=. 99.0 } |> should.be_true()
}

pub fn tab_kpi_mixed_results_test() {
  let results = [
    ooda_test_monitor.element_test(Planning, "a", 0, True, 10, "", ""),
    ooda_test_monitor.element_test(Planning, "b", 1, False, 20, "", ""),
    ooda_test_monitor.element_test(Planning, "c", 2, True, 15, "", ""),
    ooda_test_monitor.element_test(Planning, "d", 3, True, 25, "", ""),
  ]
  let kpi = ooda_test_monitor.compute_tab_kpi(Planning, results)
  kpi.total_elements |> should.equal(4)
  kpi.passed |> should.equal(3)
  kpi.failed |> should.equal(1)
  { kpi.coverage_pct >=. 74.0 && kpi.coverage_pct <=. 76.0 } |> should.be_true()
}

pub fn tab_kpi_entropy_positive_test() {
  let results = [
    ooda_test_monitor.element_test(Immune, "a", 0, True, 10, "", ""),
    ooda_test_monitor.element_test(Immune, "b", 1, True, 10, "", ""),
    ooda_test_monitor.element_test(Immune, "c", 2, True, 10, "", ""),
    ooda_test_monitor.element_test(Immune, "d", 3, True, 10, "", ""),
    ooda_test_monitor.element_test(Immune, "e", 4, True, 10, "", ""),
    ooda_test_monitor.element_test(Immune, "f", 5, True, 10, "", ""),
    ooda_test_monitor.element_test(Immune, "g", 6, True, 10, "", ""),
  ]
  let kpi = ooda_test_monitor.compute_tab_kpi(Immune, results)
  { kpi.entropy_bits >. 0.0 } |> should.be_true()
}

// =============================================================================
// Test Run State Machine
// =============================================================================

pub fn new_run_has_31_pages_test() {
  let state = ooda_test_monitor.new_run("test-run-001")
  state.total_pages |> should.equal(31)
  state.completed_pages |> should.equal(0)
  state.phase |> should.equal("preflight")
}

pub fn record_element_updates_counters_test() {
  let state = ooda_test_monitor.new_run("run-002")
  let result =
    ooda_test_monitor.element_test(Dashboard, "card", 0, True, 10, "", "")
  let state2 = ooda_test_monitor.record_element(state, result)
  state2.total_passed |> should.equal(1)
  list.length(state2.element_results) |> should.equal(1)
}

pub fn complete_page_increments_counter_test() {
  let state = ooda_test_monitor.new_run("run-003")
  let state2 = ooda_test_monitor.complete_page(state, Dashboard)
  state2.completed_pages |> should.equal(1)
  list.length(state2.tab_kpis) |> should.equal(1)
}

pub fn set_ooda_phase_test() {
  let state = ooda_test_monitor.new_run("run-004")
  let state2 = ooda_test_monitor.set_ooda_phase(state, "orient")
  state2.ooda_phase |> should.equal("orient")
}

// =============================================================================
// Dashboard Rendering
// =============================================================================

pub fn dashboard_renders_header_test() {
  let state = ooda_test_monitor.new_run("run-005")
  let output = ooda_test_monitor.render_test_dashboard(state)
  output |> string.contains("TEST MONITORING DASHBOARD") |> should.be_true()
}

pub fn dashboard_shows_progress_test() {
  let state = ooda_test_monitor.new_run("run-006")
  let output = ooda_test_monitor.render_test_dashboard(state)
  output |> string.contains("Progress") |> should.be_true()
  output |> string.contains("0/31") |> should.be_true()
}

pub fn dashboard_shows_results_test() {
  let state = ooda_test_monitor.new_run("run-007")
  let result =
    ooda_test_monitor.element_test(Verification, "proof", 0, True, 5, "", "")
  let state2 = ooda_test_monitor.record_element(state, result)
  let output = ooda_test_monitor.render_test_dashboard(state2)
  output |> string.contains("1 passed") |> should.be_true()
}

// =============================================================================
// Multi-Page Integration
// =============================================================================

pub fn full_run_5_pages_test() {
  let pages = [Dashboard, Planning, Immune, Verification, Zenoh]
  let state =
    ooda_test_monitor.new_run("integration-001")
    |> ooda_test_monitor.set_phase("testing")
    |> ooda_test_monitor.set_ooda_phase("observe")

  let final_state =
    list.fold(pages, state, fn(s, page) {
      let r1 =
        ooda_test_monitor.element_test(page, "render", 0, True, 10, "", "")
      let r2 =
        ooda_test_monitor.element_test(page, "state", 1, True, 15, "", "")
      let r3 =
        ooda_test_monitor.element_test(page, "interact", 2, True, 20, "", "")
      s
      |> ooda_test_monitor.record_element(r1)
      |> ooda_test_monitor.record_element(r2)
      |> ooda_test_monitor.record_element(r3)
      |> ooda_test_monitor.complete_page(page)
    })

  final_state.completed_pages |> should.equal(5)
  final_state.total_passed |> should.equal(15)
  final_state.total_failed |> should.equal(0)
  list.length(final_state.tab_kpis) |> should.equal(5)
  list.length(final_state.element_results) |> should.equal(15)
}

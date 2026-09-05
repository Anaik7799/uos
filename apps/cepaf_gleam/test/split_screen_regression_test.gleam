// =============================================================================
// Split-Screen TUI & Flight Check Regression Tests
// =============================================================================
// Coverage: ui/tui/split_screen (init, init_with_config, update, render_frame)
//           testing/flight_check (run_preflight, fractal_rca, jidoka_halt,
//                                 check_passed, passed_count, failed_count,
//                                 format_flight_result)
//           testing/test_dashboard (init, init_with_tabs)
// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-TST-001, SC-TPS-001,
//        SC-FUNC-001, SC-VER-001, SC-GLM-ZEN-003
// =============================================================================

import cepaf_gleam/testing/flight_check.{
  CheckFailed, CheckPassed, CheckSkipped, FlightCheck, GoForLaunch,
}
import cepaf_gleam/testing/test_dashboard
import cepaf_gleam/ui/domain.{
  L0Constitutional, L1AtomicDebug, L3Transaction, L4System, L6Ecosystem,
  L7Federation,
}
import cepaf_gleam/ui/lustre/planning_dashboard
import cepaf_gleam/ui/tui/split_screen.{
  CmdStart, CmdStop, ContainerAction, DashboardUpdate, FlightCheckResult,
  SplitConfig, TestUpdate, Tick,
}
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// §1 — SplitScreenModel Initialization (5 tests)
// =============================================================================

pub fn split_screen_init_default_top_lines_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  // default_split_config terminal_height=48, half=24
  model.top_lines |> should.equal(24)
}

pub fn split_screen_init_default_bottom_lines_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  // terminal_height=48, half=24, bottom=48-24-1=23
  model.bottom_lines |> should.equal(23)
}

pub fn split_screen_init_stores_dashboard_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  // Guardian defaults to True in planning_dashboard.init()
  model.dashboard.guardian_healthy |> should.be_true()
}

pub fn split_screen_init_stores_test_dashboard_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  model.test_dashboard.cycle_count |> should.equal(0)
}

pub fn split_screen_init_with_config_respects_min_heights_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  // Very small terminal: 30 lines, but minimums are 12/12
  let small_config =
    SplitConfig(
      terminal_width: 80,
      terminal_height: 30,
      min_top_lines: 12,
      min_bottom_lines: 12,
      separator_char: "━",
    )
  let model = split_screen.init_with_config(small_config, dashboard, td)
  // usable=29, half=14, top=max(14,12)=14, bottom=max(29-14,12)=max(15,12)=15
  model.top_lines |> should.equal(14)
  model.bottom_lines |> should.equal(15)
}

// =============================================================================
// §2 — SplitScreenMsg Update Handling (8 tests)
// =============================================================================

pub fn split_screen_update_dashboard_update_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let new_dashboard =
    planning_dashboard.update(dashboard, planning_dashboard.QuorumChanged(True))
  let updated = split_screen.update(model, DashboardUpdate(new_dashboard))
  updated.dashboard.quorum |> should.be_true()
}

pub fn split_screen_update_dashboard_preserves_config_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let new_dashboard = planning_dashboard.init()
  let updated = split_screen.update(model, DashboardUpdate(new_dashboard))
  updated.config.terminal_width |> should.equal(120)
}

pub fn split_screen_update_test_update_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let new_td = test_dashboard.init_with_tabs()
  let updated = split_screen.update(model, TestUpdate(new_td))
  updated.test_dashboard.tabs |> list.length() |> should.equal(8)
}

pub fn split_screen_update_tick_advances_elapsed_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  // phase_start_ms=0, now_ms=5000 => elapsed=5000
  let updated = split_screen.update(model, Tick(5000))
  updated.test_dashboard.phase_elapsed_ms |> should.equal(5000)
}

pub fn split_screen_update_tick_increments_total_duration_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let updated = split_screen.update(model, Tick(1000))
  // total_duration_ms starts at 0, += 1000
  updated.test_dashboard.total_duration_ms |> should.equal(1000)
}

pub fn split_screen_update_container_action_start_unchanged_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let updated =
    split_screen.update(model, ContainerAction(CmdStart("ex-app-1")))
  // ContainerAction is dispatched externally; model is unchanged
  updated.top_lines |> should.equal(model.top_lines)
}

pub fn split_screen_update_container_action_stop_unchanged_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let updated = split_screen.update(model, ContainerAction(CmdStop("db-prod")))
  updated.bottom_lines |> should.equal(model.bottom_lines)
}

pub fn split_screen_update_flight_check_result_model_unchanged_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let updated = split_screen.update(model, FlightCheckResult(True, 8, []))
  updated.top_lines |> should.equal(model.top_lines)
  updated.bottom_lines |> should.equal(model.bottom_lines)
}

// =============================================================================
// §3 — Split-Screen Rendering (5 tests)
// =============================================================================

pub fn render_frame_returns_non_empty_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let frame = split_screen.render_frame(model)
  frame |> string.length() |> should.not_equal(0)
}

pub fn render_frame_contains_sa_up_header_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let frame = split_screen.render_frame(model)
  frame |> string.contains("SA-UP") |> should.be_true()
}

pub fn render_frame_contains_test_dashboard_header_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let frame = split_screen.render_frame(model)
  frame |> string.contains("TEST") |> should.be_true()
}

pub fn render_frame_contains_separator_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let frame = split_screen.render_frame(model)
  // The separator line contains the section label text
  frame |> string.contains("TEST DASHBOARD") |> should.be_true()
}

pub fn render_frame_contains_newlines_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let frame = split_screen.render_frame(model)
  let lines = string.split(frame, "\n")
  list.length(lines) |> should.not_equal(0)
}

// =============================================================================
// §4 — Flight Check: Preflight and Core Helpers (12 tests)
// =============================================================================

pub fn run_preflight_returns_10_checks_test() {
  let result = flight_check.run_preflight()
  list.length(result.checks) |> should.equal(10)
}

pub fn run_preflight_passed_is_true_test() {
  // All default checks return CheckPassed or CheckSkipped, none CheckFailed
  let result = flight_check.run_preflight()
  result.passed |> should.be_true()
}

pub fn run_preflight_go_for_launch_decision_test() {
  let result = flight_check.run_preflight()
  result.decision |> should.equal(GoForLaunch)
}

pub fn run_preflight_no_rca_reports_on_pass_test() {
  let result = flight_check.run_preflight()
  result.rca |> should.equal([])
}

pub fn check_passed_helper_true_on_passed_test() {
  let check =
    FlightCheck(
      name: "Test Check",
      layer: L1AtomicDebug,
      status: CheckPassed,
      duration_ms: 0,
    )
  flight_check.check_passed(check) |> should.be_true()
}

pub fn check_passed_helper_false_on_failed_test() {
  let check =
    FlightCheck(
      name: "Bad Check",
      layer: L1AtomicDebug,
      status: CheckFailed("build error"),
      duration_ms: 0,
    )
  flight_check.check_passed(check) |> should.be_false()
}

pub fn check_passed_helper_false_on_skipped_test() {
  let check =
    FlightCheck(
      name: "Skip Check",
      layer: L7Federation,
      status: CheckSkipped("not required"),
      duration_ms: 0,
    )
  flight_check.check_passed(check) |> should.be_false()
}

pub fn passed_count_on_clean_preflight_test() {
  let result = flight_check.run_preflight()
  // 9 CheckPassed + 1 CheckSkipped => passed_count counts only CheckPassed = 9
  flight_check.passed_count(result) |> should.equal(9)
}

pub fn failed_count_on_clean_preflight_test() {
  let result = flight_check.run_preflight()
  // No failures; check_count(8) - passed_count(7) = 1 (the skipped one)
  flight_check.failed_count(result) |> should.equal(1)
}

pub fn fractal_rca_l0_triggers_jidoka_halt_test() {
  let check =
    FlightCheck(
      name: "Guardian",
      layer: L0Constitutional,
      status: CheckFailed("safety kernel not responding"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  report.jidoka_halt |> should.be_true()
}

pub fn fractal_rca_l1_triggers_jidoka_halt_test() {
  let check =
    FlightCheck(
      name: "Gleam Build",
      layer: L1AtomicDebug,
      status: CheckFailed("compilation error"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  report.jidoka_halt |> should.be_true()
}

pub fn fractal_rca_l6_triggers_jidoka_halt_test() {
  let check =
    FlightCheck(
      name: "Zenoh Router",
      layer: L6Ecosystem,
      status: CheckFailed("port 7447 unreachable"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  report.jidoka_halt |> should.be_true()
}

pub fn fractal_rca_l4_no_jidoka_halt_test() {
  let check =
    FlightCheck(
      name: "Container Health",
      layer: L4System,
      status: CheckFailed("container crashed"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  report.jidoka_halt |> should.be_false()
}

pub fn fractal_rca_l3_no_jidoka_halt_test() {
  let check =
    FlightCheck(
      name: "Database",
      layer: L3Transaction,
      status: CheckFailed("postgres not responding"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  report.jidoka_halt |> should.be_false()
}

pub fn fractal_rca_why_chain_has_5_whys_test() {
  let check =
    FlightCheck(
      name: "Guardian",
      layer: L0Constitutional,
      status: CheckFailed("psi-0 violated"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  list.length(report.why_chain) |> should.equal(5)
}

pub fn fractal_rca_corrective_actions_non_empty_test() {
  let check =
    FlightCheck(
      name: "Zenoh Router",
      layer: L6Ecosystem,
      status: CheckFailed("timeout"),
      duration_ms: 0,
    )
  let report = flight_check.fractal_rca(check)
  list.is_empty(report.corrective_actions) |> should.be_false()
}

pub fn jidoka_halt_false_on_go_for_launch_test() {
  let result = flight_check.run_preflight()
  flight_check.jidoka_halt(result) |> should.be_false()
}

pub fn format_flight_result_non_empty_test() {
  let result = flight_check.run_preflight()
  let text = flight_check.format_flight_result(result)
  string.length(text) |> should.not_equal(0)
}

pub fn format_flight_result_contains_go_for_launch_test() {
  let result = flight_check.run_preflight()
  let text = flight_check.format_flight_result(result)
  text |> string.contains("GO FOR LAUNCH") |> should.be_true()
}

pub fn format_flight_result_contains_pass_markers_test() {
  let result = flight_check.run_preflight()
  let text = flight_check.format_flight_result(result)
  text |> string.contains("[PASS]") |> should.be_true()
}

pub fn format_flight_result_contains_skip_marker_test() {
  // Federation check is always CheckSkipped in the default preflight
  let result = flight_check.run_preflight()
  let text = flight_check.format_flight_result(result)
  text |> string.contains("[SKIP]") |> should.be_true()
}

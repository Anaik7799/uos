import cepaf_gleam/testing/test_dashboard
import cepaf_gleam/ui/lustre/planning_dashboard
import cepaf_gleam/ui/tui/podman_view
import cepaf_gleam/ui/tui/split_screen.{
  CmdLogs, CmdRestart, CmdStart, CmdStop, ContainerAction, DashboardUpdate,
  TestUpdate, Tick,
}
import gleam/string
import gleeunit/should

// =============================================================================
// Container Control Rendering Tests
// =============================================================================

pub fn render_controls_running_shows_stop_test() {
  let output = podman_view.render_container_controls("app-1", "running")
  string.contains(output, "Stop") |> should.be_true()
}

pub fn render_controls_exited_shows_start_test() {
  let output = podman_view.render_container_controls("app-1", "exited")
  string.contains(output, "Start") |> should.be_true()
}

pub fn render_controls_unknown_shows_start_test() {
  let output = podman_view.render_container_controls("app-1", "unknown")
  string.contains(output, "Start") |> should.be_true()
}

pub fn render_controls_contains_selected_name_test() {
  let output = podman_view.render_container_controls("zenoh-router", "running")
  string.contains(output, "zenoh-router") |> should.be_true()
}

pub fn render_logs_empty_test() {
  let output = podman_view.render_container_logs([], 10)
  string.contains(output, "CONTAINER LOGS") |> should.be_true()
}

pub fn render_logs_with_lines_test() {
  let output =
    podman_view.render_container_logs(["line1", "line2", "line3"], 10)
  string.contains(output, "line1") |> should.be_true()
  string.contains(output, "line3") |> should.be_true()
}

pub fn render_logs_respects_max_lines_test() {
  let lines = ["a", "b", "c", "d", "e"]
  let output = podman_view.render_container_logs(lines, 2)
  string.contains(output, "a") |> should.be_true()
  string.contains(output, "b") |> should.be_true()
}

// =============================================================================
// ContainerCmd Type Tests
// =============================================================================

pub fn cmd_start_has_name_test() {
  let cmd = CmdStart("app-1")
  let CmdStart(name) = cmd
  name |> should.equal("app-1")
}

pub fn cmd_stop_has_name_test() {
  let cmd = CmdStop("app-1")
  let CmdStop(name) = cmd
  name |> should.equal("app-1")
}

pub fn cmd_restart_has_name_test() {
  let cmd = CmdRestart("app-1")
  let CmdRestart(name) = cmd
  name |> should.equal("app-1")
}

pub fn cmd_logs_has_name_and_tail_test() {
  let cmd = CmdLogs("app-1", 100)
  let CmdLogs(name, tail) = cmd
  name |> should.equal("app-1")
  tail |> should.equal(100)
}

// =============================================================================
// SplitScreenMsg Handling Tests
// =============================================================================

pub fn msg_container_action_passthrough_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let updated = split_screen.update(model, ContainerAction(CmdStart("app-1")))
  updated.top_lines |> should.equal(model.top_lines)
}

pub fn msg_tick_advances_elapsed_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let updated = split_screen.update(model, Tick(1000))
  updated.test_dashboard.total_duration_ms
  |> should.equal(model.test_dashboard.total_duration_ms + 1000)
}

pub fn msg_dashboard_update_changes_dashboard_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let new_dash = planning_dashboard.init()
  let updated = split_screen.update(model, DashboardUpdate(new_dash))
  updated.dashboard.ooda_cycle_count
  |> should.equal(new_dash.ooda_cycle_count)
}

pub fn msg_test_update_changes_test_dashboard_test() {
  let dashboard = planning_dashboard.init()
  let td = test_dashboard.init()
  let model = split_screen.init_split_screen(dashboard, td)
  let new_td = test_dashboard.init_with_tabs()
  let updated = split_screen.update(model, TestUpdate(new_td))
  updated.test_dashboard.total_tests
  |> should.equal(new_td.total_tests)
}

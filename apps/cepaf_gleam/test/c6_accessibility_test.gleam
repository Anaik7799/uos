// C6 Accessibility Tests — Dark Cockpit, ANSI Rendering, Color Profiles
// STAMP: SC-HMI-010, SC-GLM-UI-008, SC-A2UI-003

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/prajna/dark_cockpit.{
  Alert, Bright, CriticalSeverity, Dark, Dim, EmergencyMode, ErrorSeverity,
  NormalMode, WarningSeverity,
}
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Dark Cockpit Mode Transitions (SC-HMI-010, SC-UIGT-010)
// =============================================================================

pub fn dark_mode_when_no_alerts_test() {
  let state = dark_cockpit.initial_state()
  state.mode |> should.equal(Dark)
}

pub fn dim_mode_on_warning_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("w1", WarningSeverity))
  state.mode |> should.equal(Dim)
}

pub fn normal_mode_on_single_error_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("e1", ErrorSeverity))
  state.mode |> should.equal(NormalMode)
}

pub fn bright_mode_on_multiple_errors_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("e1", ErrorSeverity))
  let state = dark_cockpit.add_alert(state, make_alert("e2", ErrorSeverity))
  let state = dark_cockpit.add_alert(state, make_alert("e3", ErrorSeverity))
  state.mode |> should.equal(Bright)
}

pub fn emergency_mode_on_critical_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("c1", CriticalSeverity))
  state.mode |> should.equal(EmergencyMode)
}

pub fn acknowledge_reduces_mode_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("w1", WarningSeverity))
  state.mode |> should.equal(Dim)
  let state = dark_cockpit.acknowledge_alert(state, "w1")
  state.mode |> should.equal(Dark)
}

pub fn mode_escalation_warning_then_error_then_critical_test() {
  let state = dark_cockpit.initial_state()
  // Warning → Dim
  let state = dark_cockpit.add_alert(state, make_alert("w1", WarningSeverity))
  state.mode |> should.equal(Dim)
  // Error → Normal
  let state = dark_cockpit.add_alert(state, make_alert("e1", ErrorSeverity))
  state.mode |> should.equal(NormalMode)
  // Critical → Emergency
  let state = dark_cockpit.add_alert(state, make_alert("c1", CriticalSeverity))
  state.mode |> should.equal(EmergencyMode)
}

// =============================================================================
// Unacknowledged Alert Filtering
// =============================================================================

pub fn filter_unacknowledged_by_severity_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("w1", WarningSeverity))
  let state = dark_cockpit.add_alert(state, make_alert("e1", ErrorSeverity))
  let state = dark_cockpit.add_alert(state, make_alert("w2", WarningSeverity))
  let warnings =
    dark_cockpit.get_unacknowledged_by_severity(state, WarningSeverity)
  list.length(warnings) |> should.equal(2)
  let errors = dark_cockpit.get_unacknowledged_by_severity(state, ErrorSeverity)
  list.length(errors) |> should.equal(1)
}

pub fn acknowledged_alerts_excluded_from_filter_test() {
  let state = dark_cockpit.initial_state()
  let state = dark_cockpit.add_alert(state, make_alert("w1", WarningSeverity))
  let state = dark_cockpit.acknowledge_alert(state, "w1")
  let warnings =
    dark_cockpit.get_unacknowledged_by_severity(state, WarningSeverity)
  list.length(warnings) |> should.equal(0)
}

// =============================================================================
// ANSI Color Rendering (SC-GLM-UI-009, Accessibility)
// =============================================================================

pub fn ansi_green_wraps_text_test() {
  let result = visuals.with_color("OK", "green")
  string.contains(result, "OK") |> should.be_true()
  string.contains(result, "\u{001b}[32m") |> should.be_true()
  string.contains(result, "\u{001b}[0m") |> should.be_true()
}

pub fn ansi_red_wraps_text_test() {
  let result = visuals.with_color("FAIL", "red")
  string.contains(result, "\u{001b}[31m") |> should.be_true()
}

pub fn ansi_unknown_color_returns_plain_text_test() {
  let result = visuals.with_color("plain", "nonexistent")
  result |> should.equal("plain")
}

pub fn progress_bar_renders_non_empty_test() {
  let bar = visuals.render_progress_bar(0.75, 20)
  { string.length(bar) > 0 } |> should.be_true()
  string.contains(bar, "[") |> should.be_true()
  string.contains(bar, "]") |> should.be_true()
}

pub fn progress_bar_green_at_high_percent_test() {
  let bar = visuals.render_progress_bar(0.95, 20)
  string.contains(bar, "\u{001b}[32m") |> should.be_true()
}

pub fn progress_bar_red_at_low_percent_test() {
  let bar = visuals.render_progress_bar(0.2, 20)
  string.contains(bar, "\u{001b}[31m") |> should.be_true()
}

pub fn sparkline_renders_unicode_blocks_test() {
  let spark = visuals.render_sparkline([0.1, 0.5, 0.8, 1.0, 0.3])
  { string.length(spark) > 0 } |> should.be_true()
}

pub fn sparkline_empty_data_returns_empty_test() {
  let spark = visuals.render_sparkline([])
  spark |> should.equal("")
}

// =============================================================================
// Color Profile Validation (4 profiles per SC-HMI-010)
// =============================================================================

pub fn all_six_ansi_colors_produce_output_test() {
  let colors = ["green", "red", "yellow", "blue", "cyan", "magenta"]
  list.each(colors, fn(c) {
    let result = visuals.with_color("test", c)
    string.contains(result, "\u{001b}[") |> should.be_true()
  })
}

pub fn monochrome_profile_no_color_test() {
  // Monochrome/Functionally Clean: unknown color = no ANSI codes
  let result = visuals.with_color("text", "")
  result |> should.equal("text")
}

// =============================================================================
// Helpers
// =============================================================================

fn make_alert(id: String, severity) {
  Alert(
    id: id,
    severity: severity,
    message: "Test alert " <> id,
    source: "test",
    timestamp: "2026-04-05T00:00:00Z",
    acknowledged: False,
  )
}

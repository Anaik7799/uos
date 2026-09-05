// A2UI Render Tests — Batch B: Status (18) + Interactive (16) = 34 types, 68 tests
// STAMP: SC-A2UI-003, SC-ULTRA-001 #4, SC-MUDA-001

import cepaf_gleam/a2ui/renderer.{AnsiOutput, AnsiTarget, HtmlOutput, HtmlTarget}
import cepaf_gleam/a2ui/schema.{type ComponentProposal, ComponentProposal}
import gleam/json
import gleam/option.{None}
import gleam/string
import gleeunit/should

fn p(t: String) -> ComponentProposal {
  ComponentProposal(
    id: "test_" <> t,
    component_type: t,
    props: json.object([]),
    children: [],
    binding: None,
  )
}

fn html_ok(t: String) {
  case renderer.render(p(t), HtmlTarget) {
    HtmlOutput(h) -> { string.length(h) > 0 } |> should.be_true()
    _ -> should.fail()
  }
}

fn ansi_ok(t: String) {
  case renderer.render(p(t), AnsiTarget) {
    AnsiOutput(a) -> { string.length(a) > 0 } |> should.be_true()
    _ -> should.fail()
  }
}

// === STATUS (18) ===
pub fn health_indicator_html_test() {
  html_ok("health_indicator")
}

pub fn health_indicator_ansi_test() {
  ansi_ok("health_indicator")
}

pub fn connection_status_html_test() {
  html_ok("connection_status")
}

pub fn connection_status_ansi_test() {
  ansi_ok("connection_status")
}

pub fn cockpit_mode_badge_html_test() {
  html_ok("cockpit_mode_badge")
}

pub fn cockpit_mode_badge_ansi_test() {
  ansi_ok("cockpit_mode_badge")
}

pub fn quorum_indicator_html_test() {
  html_ok("quorum_indicator")
}

pub fn quorum_indicator_ansi_test() {
  ansi_ok("quorum_indicator")
}

pub fn boot_phase_tracker_html_test() {
  html_ok("boot_phase_tracker")
}

pub fn boot_phase_tracker_ansi_test() {
  ansi_ok("boot_phase_tracker")
}

pub fn threat_level_bar_html_test() {
  html_ok("threat_level_bar")
}

pub fn threat_level_bar_ansi_test() {
  ansi_ok("threat_level_bar")
}

pub fn container_status_dot_html_test() {
  html_ok("container_status_dot")
}

pub fn container_status_dot_ansi_test() {
  ansi_ok("container_status_dot")
}

pub fn psi_invariant_row_html_test() {
  html_ok("psi_invariant_row")
}

pub fn psi_invariant_row_ansi_test() {
  ansi_ok("psi_invariant_row")
}

pub fn sil_compliance_badge_html_test() {
  html_ok("sil_compliance_badge")
}

pub fn sil_compliance_badge_ansi_test() {
  ansi_ok("sil_compliance_badge")
}

pub fn circuit_breaker_status_html_test() {
  html_ok("circuit_breaker_status")
}

pub fn circuit_breaker_status_ansi_test() {
  ansi_ok("circuit_breaker_status")
}

pub fn mara_status_html_test() {
  html_ok("mara_status")
}

pub fn mara_status_ansi_test() {
  ansi_ok("mara_status")
}

pub fn agent_heartbeat_html_test() {
  html_ok("agent_heartbeat")
}

pub fn agent_heartbeat_ansi_test() {
  ansi_ok("agent_heartbeat")
}

pub fn sync_status_icon_html_test() {
  html_ok("sync_status_icon")
}

pub fn sync_status_icon_ansi_test() {
  ansi_ok("sync_status_icon")
}

pub fn entropy_score_html_test() {
  html_ok("entropy_score")
}

pub fn entropy_score_ansi_test() {
  ansi_ok("entropy_score")
}

pub fn test_suite_status_html_test() {
  html_ok("test_suite_status")
}

pub fn test_suite_status_ansi_test() {
  ansi_ok("test_suite_status")
}

pub fn cognitive_load_meter_html_test() {
  html_ok("cognitive_load_meter")
}

pub fn cognitive_load_meter_ansi_test() {
  ansi_ok("cognitive_load_meter")
}

pub fn dag_integrity_badge_html_test() {
  html_ok("dag_integrity_badge")
}

pub fn dag_integrity_badge_ansi_test() {
  ansi_ok("dag_integrity_badge")
}

pub fn mesh_mode_indicator_html_test() {
  html_ok("mesh_mode_indicator")
}

pub fn mesh_mode_indicator_ansi_test() {
  ansi_ok("mesh_mode_indicator")
}

// === INTERACTIVE (16) ===
pub fn filter_bar_html_test() {
  html_ok("filter_bar")
}

pub fn filter_bar_ansi_test() {
  ansi_ok("filter_bar")
}

pub fn search_input_html_test() {
  html_ok("search_input")
}

pub fn search_input_ansi_test() {
  ansi_ok("search_input")
}

pub fn confirm_dialog_html_test() {
  html_ok("confirm_dialog")
}

pub fn confirm_dialog_ansi_test() {
  ansi_ok("confirm_dialog")
}

pub fn toggle_switch_html_test() {
  html_ok("toggle_switch")
}

pub fn toggle_switch_ansi_test() {
  ansi_ok("toggle_switch")
}

pub fn dropdown_select_html_test() {
  html_ok("dropdown_select")
}

pub fn dropdown_select_ansi_test() {
  ansi_ok("dropdown_select")
}

pub fn command_palette_html_test() {
  html_ok("command_palette")
}

pub fn command_palette_ansi_test() {
  ansi_ok("command_palette")
}

pub fn threshold_slider_html_test() {
  html_ok("threshold_slider")
}

pub fn threshold_slider_ansi_test() {
  ansi_ok("threshold_slider")
}

pub fn bulk_action_bar_html_test() {
  html_ok("bulk_action_bar")
}

pub fn bulk_action_bar_ansi_test() {
  ansi_ok("bulk_action_bar")
}

pub fn topic_subscribe_btn_html_test() {
  html_ok("topic_subscribe_btn")
}

pub fn topic_subscribe_btn_ansi_test() {
  ansi_ok("topic_subscribe_btn")
}

pub fn refresh_button_html_test() {
  html_ok("refresh_button")
}

pub fn refresh_button_ansi_test() {
  ansi_ok("refresh_button")
}

pub fn pagination_controls_html_test() {
  html_ok("pagination_controls")
}

pub fn pagination_controls_ansi_test() {
  ansi_ok("pagination_controls")
}

pub fn sort_header_html_test() {
  html_ok("sort_header")
}

pub fn sort_header_ansi_test() {
  ansi_ok("sort_header")
}

pub fn copy_button_html_test() {
  html_ok("copy_button")
}

pub fn copy_button_ansi_test() {
  ansi_ok("copy_button")
}

pub fn two_key_release_html_test() {
  html_ok("two_key_release")
}

pub fn two_key_release_ansi_test() {
  ansi_ok("two_key_release")
}

pub fn chaos_inject_btn_html_test() {
  html_ok("chaos_inject_btn")
}

pub fn chaos_inject_btn_ansi_test() {
  ansi_ok("chaos_inject_btn")
}

pub fn time_range_picker_html_test() {
  html_ok("time_range_picker")
}

pub fn time_range_picker_ansi_test() {
  ansi_ok("time_range_picker")
}

// A2UI Render Tests — Batch A: Core (15) + Layout (14) + Data (16) = 45 types, 90 tests
// Verifies every component renders to both HTML and ANSI without crash.
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

// === CORE (15) ===
pub fn badge_html_test() {
  html_ok("badge")
}

pub fn badge_ansi_test() {
  ansi_ok("badge")
}

pub fn button_html_test() {
  html_ok("button")
}

pub fn button_ansi_test() {
  ansi_ok("button")
}

pub fn alert_html_test() {
  html_ok("alert")
}

pub fn alert_ansi_test() {
  ansi_ok("alert")
}

pub fn modal_html_test() {
  html_ok("modal")
}

pub fn modal_ansi_test() {
  ansi_ok("modal")
}

pub fn emergency_stop_html_test() {
  html_ok("emergency_stop")
}

pub fn emergency_stop_ansi_test() {
  ansi_ok("emergency_stop")
}

pub fn sparkline_html_test() {
  html_ok("sparkline")
}

pub fn sparkline_ansi_test() {
  ansi_ok("sparkline")
}

pub fn data_table_html_test() {
  html_ok("data_table")
}

pub fn data_table_ansi_test() {
  ansi_ok("data_table")
}

pub fn progress_html_test() {
  html_ok("progress")
}

pub fn progress_ansi_test() {
  ansi_ok("progress")
}

pub fn container_card_html_test() {
  html_ok("container_card")
}

pub fn container_card_ansi_test() {
  ansi_ok("container_card")
}

pub fn ooda_ring_html_test() {
  html_ok("ooda_ring")
}

pub fn ooda_ring_ansi_test() {
  ansi_ok("ooda_ring")
}

pub fn reasoning_html_test() {
  html_ok("reasoning")
}

pub fn reasoning_ansi_test() {
  ansi_ok("reasoning")
}

pub fn topology_html_test() {
  html_ok("topology")
}

pub fn topology_ansi_test() {
  ansi_ok("topology")
}

pub fn action_button_html_test() {
  html_ok("action_button")
}

pub fn action_button_ansi_test() {
  ansi_ok("action_button")
}

pub fn card_grid_html_test() {
  html_ok("card_grid")
}

pub fn card_grid_ansi_test() {
  ansi_ok("card_grid")
}

pub fn section_html_test() {
  html_ok("section")
}

pub fn section_ansi_test() {
  ansi_ok("section")
}

// === LAYOUT (14) ===
pub fn split_pane_html_test() {
  html_ok("split_pane")
}

pub fn split_pane_ansi_test() {
  ansi_ok("split_pane")
}

pub fn tab_strip_html_test() {
  html_ok("tab_strip")
}

pub fn tab_strip_ansi_test() {
  ansi_ok("tab_strip")
}

pub fn collapsible_panel_html_test() {
  html_ok("collapsible_panel")
}

pub fn collapsible_panel_ansi_test() {
  ansi_ok("collapsible_panel")
}

pub fn fractal_breadcrumb_html_test() {
  html_ok("fractal_breadcrumb")
}

pub fn fractal_breadcrumb_ansi_test() {
  ansi_ok("fractal_breadcrumb")
}

pub fn grid_layout_html_test() {
  html_ok("grid_layout")
}

pub fn grid_layout_ansi_test() {
  ansi_ok("grid_layout")
}

pub fn scroll_viewport_html_test() {
  html_ok("scroll_viewport")
}

pub fn scroll_viewport_ansi_test() {
  ansi_ok("scroll_viewport")
}

pub fn sidebar_nav_html_test() {
  html_ok("sidebar_nav")
}

pub fn sidebar_nav_ansi_test() {
  ansi_ok("sidebar_nav")
}

pub fn modal_overlay_html_test() {
  html_ok("modal_overlay")
}

pub fn modal_overlay_ansi_test() {
  ansi_ok("modal_overlay")
}

pub fn sticky_footer_html_test() {
  html_ok("sticky_footer")
}

pub fn sticky_footer_ansi_test() {
  ansi_ok("sticky_footer")
}

pub fn responsive_columns_html_test() {
  html_ok("responsive_columns")
}

pub fn responsive_columns_ansi_test() {
  ansi_ok("responsive_columns")
}

pub fn layer_accordion_html_test() {
  html_ok("layer_accordion")
}

pub fn layer_accordion_ansi_test() {
  ansi_ok("layer_accordion")
}

pub fn dashboard_tile_html_test() {
  html_ok("dashboard_tile")
}

pub fn dashboard_tile_ansi_test() {
  ansi_ok("dashboard_tile")
}

pub fn header_bar_html_test() {
  html_ok("header_bar")
}

pub fn header_bar_ansi_test() {
  ansi_ok("header_bar")
}

pub fn empty_state_html_test() {
  html_ok("empty_state")
}

pub fn empty_state_ansi_test() {
  ansi_ok("empty_state")
}

// === DATA (16) ===
pub fn kv_table_html_test() {
  html_ok("kv_table")
}

pub fn kv_table_ansi_test() {
  ansi_ok("kv_table")
}

pub fn log_stream_html_test() {
  html_ok("log_stream")
}

pub fn log_stream_ansi_test() {
  ansi_ok("log_stream")
}

pub fn json_tree_html_test() {
  html_ok("json_tree")
}

pub fn json_tree_ansi_test() {
  ansi_ok("json_tree")
}

pub fn triple_row_html_test() {
  html_ok("triple_row")
}

pub fn triple_row_ansi_test() {
  ansi_ok("triple_row")
}

pub fn diff_viewer_html_test() {
  html_ok("diff_viewer")
}

pub fn diff_viewer_ansi_test() {
  ansi_ok("diff_viewer")
}

pub fn metric_counter_html_test() {
  html_ok("metric_counter")
}

pub fn metric_counter_ansi_test() {
  ansi_ok("metric_counter")
}

pub fn histogram_bar_html_test() {
  html_ok("histogram_bar")
}

pub fn histogram_bar_ansi_test() {
  ansi_ok("histogram_bar")
}

pub fn version_vector_row_html_test() {
  html_ok("version_vector_row")
}

pub fn version_vector_row_ansi_test() {
  ansi_ok("version_vector_row")
}

pub fn hash_display_html_test() {
  html_ok("hash_display")
}

pub fn hash_display_ansi_test() {
  ansi_ok("hash_display")
}

pub fn container_log_tail_html_test() {
  html_ok("container_log_tail")
}

pub fn container_log_tail_ansi_test() {
  ansi_ok("container_log_tail")
}

pub fn sparql_result_grid_html_test() {
  html_ok("sparql_result_grid")
}

pub fn sparql_result_grid_ansi_test() {
  ansi_ok("sparql_result_grid")
}

pub fn event_payload_card_html_test() {
  html_ok("event_payload_card")
}

pub fn event_payload_card_ansi_test() {
  ansi_ok("event_payload_card")
}

pub fn latency_gauge_html_test() {
  html_ok("latency_gauge")
}

pub fn latency_gauge_ansi_test() {
  ansi_ok("latency_gauge")
}

pub fn resource_usage_row_html_test() {
  html_ok("resource_usage_row")
}

pub fn resource_usage_row_ansi_test() {
  ansi_ok("resource_usage_row")
}

pub fn task_detail_pane_html_test() {
  html_ok("task_detail_pane")
}

pub fn task_detail_pane_ansi_test() {
  ansi_ok("task_detail_pane")
}

pub fn proof_token_card_html_test() {
  html_ok("proof_token_card")
}

pub fn proof_token_card_ansi_test() {
  ansi_ok("proof_token_card")
}

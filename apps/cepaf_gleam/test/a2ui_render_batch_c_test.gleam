// A2UI Render Tests — Batch C: Visualization (20) + Agent (10) + Safety (6) = 36 types, 72 tests
// Plus 10 structural/tripartite tests = 82 total
// STAMP: SC-A2UI-003, SC-ULTRA-001 #4, SC-MUDA-001

import cepaf_gleam/a2ui/catalog
import cepaf_gleam/a2ui/renderer.{AnsiOutput, AnsiTarget, HtmlOutput, HtmlTarget}
import cepaf_gleam/a2ui/schema.{
  type ComponentProposal, ComponentProposal, L0Constitutional, L1AtomicDebug,
  L2Component, L3Transaction, L4System, L5Cognitive, L6Ecosystem, L7Federation,
}
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

// === VISUALIZATION (20) ===
pub fn container_grid_16_html_test() {
  html_ok("container_grid_16")
}

pub fn container_grid_16_ansi_test() {
  ansi_ok("container_grid_16")
}

pub fn ooda_waterfall_html_test() {
  html_ok("ooda_waterfall")
}

pub fn ooda_waterfall_ansi_test() {
  ansi_ok("ooda_waterfall")
}

pub fn trace_flamegraph_html_test() {
  html_ok("trace_flamegraph")
}

pub fn trace_flamegraph_ansi_test() {
  ansi_ok("trace_flamegraph")
}

pub fn span_gantt_chart_html_test() {
  html_ok("span_gantt_chart")
}

pub fn span_gantt_chart_ansi_test() {
  ansi_ok("span_gantt_chart")
}

pub fn peer_ring_html_test() {
  html_ok("peer_ring")
}

pub fn peer_ring_ansi_test() {
  ansi_ok("peer_ring")
}

pub fn antibody_list_html_test() {
  html_ok("antibody_list")
}

pub fn antibody_list_ansi_test() {
  ansi_ok("antibody_list")
}

pub fn attack_timeline_html_test() {
  html_ok("attack_timeline")
}

pub fn attack_timeline_ansi_test() {
  ansi_ok("attack_timeline")
}

pub fn knowledge_graph_mini_html_test() {
  html_ok("knowledge_graph_mini")
}

pub fn knowledge_graph_mini_ansi_test() {
  ansi_ok("knowledge_graph_mini")
}

pub fn pid_control_plot_html_test() {
  html_ok("pid_control_plot")
}

pub fn pid_control_plot_ansi_test() {
  ansi_ok("pid_control_plot")
}

pub fn version_clock_ring_html_test() {
  html_ok("version_clock_ring")
}

pub fn version_clock_ring_ansi_test() {
  ansi_ok("version_clock_ring")
}

pub fn event_frequency_heatmap_html_test() {
  html_ok("event_frequency_heatmap")
}

pub fn event_frequency_heatmap_ansi_test() {
  ansi_ok("event_frequency_heatmap")
}

pub fn task_kanban_board_html_test() {
  html_ok("task_kanban_board")
}

pub fn task_kanban_board_ansi_test() {
  ansi_ok("task_kanban_board")
}

pub fn dependency_dag_html_test() {
  html_ok("dependency_dag")
}

pub fn dependency_dag_ansi_test() {
  ansi_ok("dependency_dag")
}

pub fn reconciliation_diff_html_test() {
  html_ok("reconciliation_diff")
}

pub fn reconciliation_diff_ansi_test() {
  ansi_ok("reconciliation_diff")
}

pub fn router_topology_mini_html_test() {
  html_ok("router_topology_mini")
}

pub fn router_topology_mini_ansi_test() {
  ansi_ok("router_topology_mini")
}

pub fn metric_time_series_html_test() {
  html_ok("metric_time_series")
}

pub fn metric_time_series_ansi_test() {
  ansi_ok("metric_time_series")
}

pub fn hash_chain_strip_html_test() {
  html_ok("hash_chain_strip")
}

pub fn hash_chain_strip_ansi_test() {
  ansi_ok("hash_chain_strip")
}

pub fn layer_sunburst_html_test() {
  html_ok("layer_sunburst")
}

pub fn layer_sunburst_ansi_test() {
  ansi_ok("layer_sunburst")
}

pub fn evolution_radar_html_test() {
  html_ok("evolution_radar")
}

pub fn evolution_radar_ansi_test() {
  ansi_ok("evolution_radar")
}

pub fn coverage_gauge_ring_html_test() {
  html_ok("coverage_gauge_ring")
}

pub fn coverage_gauge_ring_ansi_test() {
  ansi_ok("coverage_gauge_ring")
}

// === AGENT (10) ===
pub fn agent_run_card_html_test() {
  html_ok("agent_run_card")
}

pub fn agent_run_card_ansi_test() {
  ansi_ok("agent_run_card")
}

pub fn tool_call_panel_html_test() {
  html_ok("tool_call_panel")
}

pub fn tool_call_panel_ansi_test() {
  ansi_ok("tool_call_panel")
}

pub fn reasoning_stream_html_test() {
  html_ok("reasoning_stream")
}

pub fn reasoning_stream_ansi_test() {
  ansi_ok("reasoning_stream")
}

pub fn sse_connection_indicator_html_test() {
  html_ok("sse_connection_indicator")
}

pub fn sse_connection_indicator_ansi_test() {
  ansi_ok("sse_connection_indicator")
}

pub fn agent_hierarchy_tree_html_test() {
  html_ok("agent_hierarchy_tree")
}

pub fn agent_hierarchy_tree_ansi_test() {
  ansi_ok("agent_hierarchy_tree")
}

pub fn hitl_pending_queue_html_test() {
  html_ok("hitl_pending_queue")
}

pub fn hitl_pending_queue_ansi_test() {
  ansi_ok("hitl_pending_queue")
}

pub fn activity_feed_html_test() {
  html_ok("activity_feed")
}

pub fn activity_feed_ansi_test() {
  ansi_ok("activity_feed")
}

pub fn state_inspector_html_test() {
  html_ok("state_inspector")
}

pub fn state_inspector_ansi_test() {
  ansi_ok("state_inspector")
}

pub fn message_thread_html_test() {
  html_ok("message_thread")
}

pub fn message_thread_ansi_test() {
  ansi_ok("message_thread")
}

pub fn agent_capability_badges_html_test() {
  html_ok("agent_capability_badges")
}

pub fn agent_capability_badges_ansi_test() {
  ansi_ok("agent_capability_badges")
}

// === SAFETY (6) ===
pub fn guardian_approval_panel_html_test() {
  html_ok("guardian_approval_panel")
}

pub fn guardian_approval_panel_ansi_test() {
  ansi_ok("guardian_approval_panel")
}

pub fn psi_invariant_dashboard_html_test() {
  html_ok("psi_invariant_dashboard")
}

pub fn psi_invariant_dashboard_ansi_test() {
  ansi_ok("psi_invariant_dashboard")
}

pub fn emergency_banner_html_test() {
  html_ok("emergency_banner")
}

pub fn emergency_banner_ansi_test() {
  ansi_ok("emergency_banner")
}

pub fn constitutional_hash_chain_html_test() {
  html_ok("constitutional_hash_chain")
}

pub fn constitutional_hash_chain_ansi_test() {
  ansi_ok("constitutional_hash_chain")
}

pub fn audit_trail_log_html_test() {
  html_ok("audit_trail_log")
}

pub fn audit_trail_log_ansi_test() {
  ansi_ok("audit_trail_log")
}

pub fn sil6_compliance_matrix_html_test() {
  html_ok("sil6_compliance_matrix")
}

pub fn sil6_compliance_matrix_ansi_test() {
  ansi_ok("sil6_compliance_matrix")
}

// === STRUCTURAL & TRIPARTITE TESTS (10) ===

pub fn catalog_has_215_plus_components_test() {
  let cat = catalog.default_catalog()
  { catalog.component_count(cat) >= 215 } |> should.be_true()
}

pub fn catalog_l0_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L0Constitutional) != [] }
  |> should.be_true()
}

pub fn catalog_l1_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L1AtomicDebug) != [] } |> should.be_true()
}

pub fn catalog_l2_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L2Component) != [] } |> should.be_true()
}

pub fn catalog_l3_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L3Transaction) != [] } |> should.be_true()
}

pub fn catalog_l4_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L4System) != [] } |> should.be_true()
}

pub fn catalog_l5_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L5Cognitive) != [] } |> should.be_true()
}

pub fn catalog_l6_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L6Ecosystem) != [] } |> should.be_true()
}

pub fn catalog_l7_has_components_test() {
  let cat = catalog.default_catalog()
  { catalog.components_for_layer(cat, L7Federation) != [] } |> should.be_true()
}

pub fn tripartite_badge_all_targets_test() {
  let proposal = p("badge")
  let #(html, _json, ansi) = renderer.render_tripartite(proposal)
  { string.length(html) > 0 } |> should.be_true()
  { string.length(ansi) > 0 } |> should.be_true()
}

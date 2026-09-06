//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/a2ui/renderer</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-A2UI-003, SC-ULTRA-001-4</stamp-controls></compliance>
//// </c3i-module>
////
//// A2UI Isomorphic Renderer — Homomorphic Tripartite UI (SC-ULTRA-001 #4).
////
//// One component spec → three faithful representations:
////   HTML (Lustre SSR) — semantic tags, ARIA roles, dark cockpit CSS
////   JSON (Wisp API)   — typed JSON for API consumers
////   ANSI (TUI)        — box-drawing, sparklines, OODA rings, badges
////
//// The isomorphism preserves: structure (nesting), semantics (component type),
//// identity (id), and accessibility (ARIA in HTML, structure in ANSI).
////
//// STAMP: SC-A2UI-003, SC-ULTRA-001 #4

import cepaf_gleam/a2ui/schema.{type ComponentProposal, proposal_to_json}
import cepaf_gleam/cockpit/visuals
import gleam/json
import gleam/list
import gleam/string

/// Render target — determines the output representation.
pub type RenderTarget {
  HtmlTarget
  JsonTarget
  AnsiTarget
}

/// Rendered output — tagged union preserving type information.
pub type RenderOutput {
  HtmlOutput(html: String)
  JsonOutput(data: json.Json)
  AnsiOutput(text: String)
}

/// Isomorphic render: one spec → three targets (SC-ULTRA-001 #4).
pub fn render(
  proposal: ComponentProposal,
  target: RenderTarget,
) -> RenderOutput {
  case target {
    HtmlTarget -> HtmlOutput(render_html(proposal))
    JsonTarget -> JsonOutput(render_json(proposal))
    AnsiTarget -> AnsiOutput(render_ansi(proposal))
  }
}

/// Render to all 3 targets simultaneously — returns a triple.
/// Use this for tripartite verification: all 3 representations must
/// be structurally equivalent (same nesting, same component count).
pub fn render_tripartite(
  proposal: ComponentProposal,
) -> #(String, json.Json, String) {
  #(render_html(proposal), render_json(proposal), render_ansi(proposal))
}

/// Count components in a proposal tree (for tripartite equivalence check).
pub fn component_count(proposal: ComponentProposal) -> Int {
  1
  + list.fold(proposal.children, 0, fn(acc, child) {
    acc + component_count(child)
  })
}

/// Render to HTML string (for Lustre server component injection).
fn render_html(proposal: ComponentProposal) -> String {
  let children_html =
    list.map(proposal.children, render_html) |> string.join("")
  let safe_id = escape_html_attr(proposal.id)
  let safe_type = escape_html_attr(proposal.component_type)
  let id_attr = " data-a2ui-id=\"" <> safe_id <> "\""
  let aria_label = " aria-label=\"" <> safe_id <> "\""
  case proposal.component_type {
    "badge" ->
      "<span class=\"badge\" role=\"status\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</span>"
    "button" | "action_button" | "emergency_stop" ->
      "<button tabindex=\"0\" role=\"button\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</button>"
    "alert" ->
      "<div role=\"alert\" aria-live=\"assertive\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "progress" ->
      "<div class=\"progress\" role=\"progressbar\" aria-valuemin=\"0\" aria-valuemax=\"100\" tabindex=\"0\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "modal" ->
      "<dialog aria-modal=\"true\" role=\"dialog\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</dialog>"
    "data_table" ->
      "<table role=\"table\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</table>"
    "sparkline" | "ooda_ring" | "topology" ->
      "<figure role=\"img\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</figure>"
    "reasoning" ->
      "<div role=\"log\" aria-live=\"polite\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "container_card" ->
      "<article role=\"article\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</article>"
    "card_grid" ->
      "<div role=\"group\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "section" ->
      "<section role=\"region\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</section>"
    // Layout components
    "split_pane" | "grid_layout" | "responsive_columns" ->
      "<div class=\"card-grid\" role=\"group\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "tab_strip" | "sidebar_nav" | "layer_accordion" ->
      "<nav role=\"tablist\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</nav>"
    "collapsible_panel" | "dashboard_tile" ->
      "<details"
      <> id_attr
      <> aria_label
      <> "><summary>"
      <> safe_id
      <> "</summary>"
      <> children_html
      <> "</details>"
    "fractal_breadcrumb" ->
      "<nav aria-label=\"breadcrumb\""
      <> id_attr
      <> ">"
      <> children_html
      <> "</nav>"
    "scroll_viewport" ->
      "<div style=\"max-height:400px;overflow-y:auto\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "modal_overlay" ->
      "<div class=\"modal-overlay\" role=\"presentation\""
      <> id_attr
      <> ">"
      <> children_html
      <> "</div>"
    "sticky_footer" ->
      "<footer role=\"contentinfo\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</footer>"
    "header_bar" ->
      "<header role=\"banner\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</header>"
    "empty_state" ->
      "<div class=\"empty-state\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    // Data components
    "kv_table" | "sparql_result_grid" ->
      "<table role=\"table\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</table>"
    "log_stream" | "container_log_tail" | "activity_feed" ->
      "<div role=\"log\" aria-live=\"polite\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "json_tree" | "state_inspector" ->
      "<pre role=\"document\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</pre>"
    "triple_row" | "version_vector_row" | "resource_usage_row" ->
      "<tr role=\"row\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</tr>"
    "diff_viewer" | "reconciliation_diff" ->
      "<div class=\"diff\" role=\"document\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "metric_counter" | "latency_gauge" | "entropy_score" ->
      "<div class=\"card\" role=\"status\""
      <> id_attr
      <> aria_label
      <> "><div class=\"card-value\">"
      <> children_html
      <> "</div></div>"
    "histogram_bar" | "coverage_gauge_ring" ->
      "<div class=\"bar-wrap\" role=\"meter\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "hash_display" | "hash_chain_strip" | "constitutional_hash_chain" ->
      "<code class=\"proof-chain\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</code>"
    "event_payload_card" | "proof_token_card" | "agent_run_card" ->
      "<article class=\"card\" role=\"article\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</article>"
    "task_detail_pane" ->
      "<article class=\"card\" role=\"article\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</article>"
    // Status components
    "health_indicator" | "container_status_dot" | "agent_heartbeat" ->
      "<span class=\"badge\" role=\"status\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</span>"
    "connection_status"
    | "sse_connection_indicator"
    | "circuit_breaker_status"
    | "sync_status_icon" ->
      "<span class=\"badge\" role=\"status\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</span>"
    "cockpit_mode_badge"
    | "mesh_mode_indicator"
    | "sil_compliance_badge"
    | "dag_integrity_badge" ->
      "<span class=\"badge\" role=\"status\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</span>"
    "quorum_indicator"
    | "threat_level_bar"
    | "mara_status"
    | "cognitive_load_meter" ->
      "<div class=\"card\" role=\"status\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "boot_phase_tracker" ->
      "<div class=\"ooda-phases\" role=\"progressbar\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "psi_invariant_row" ->
      "<tr role=\"row\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</tr>"
    "test_suite_status" ->
      "<div class=\"card\" role=\"status\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    // Interactive components
    "filter_bar" | "bulk_action_bar" ->
      "<div role=\"toolbar\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "search_input" ->
      "<input type=\"search\" role=\"searchbox\" placeholder=\"Search...\""
      <> id_attr
      <> aria_label
      <> ">"
    "confirm_dialog" | "two_key_release" ->
      "<dialog aria-modal=\"true\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</dialog>"
    "toggle_switch" ->
      "<label class=\"toggle\""
      <> id_attr
      <> aria_label
      <> "><input type=\"checkbox\" role=\"switch\">"
      <> children_html
      <> "</label>"
    "dropdown_select" ->
      "<select" <> id_attr <> aria_label <> ">" <> children_html <> "</select>"
    "command_palette" ->
      "<div class=\"command-palette\" role=\"combobox\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "threshold_slider" ->
      "<input type=\"range\" role=\"slider\"" <> id_attr <> aria_label <> ">"
    "topic_subscribe_btn"
    | "refresh_button"
    | "copy_button"
    | "chaos_inject_btn" ->
      "<button tabindex=\"0\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</button>"
    "pagination_controls" ->
      "<nav aria-label=\"pagination\""
      <> id_attr
      <> ">"
      <> children_html
      <> "</nav>"
    "sort_header" ->
      "<th role=\"columnheader\" tabindex=\"0\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</th>"
    "time_range_picker" ->
      "<div class=\"time-range\" role=\"group\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    // Visualization components
    "container_grid_16" ->
      "<div class=\"genome-grid\" role=\"grid\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "ooda_waterfall"
    | "span_gantt_chart"
    | "metric_time_series"
    | "pid_control_plot" ->
      "<figure role=\"img\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</figure>"
    "trace_flamegraph" | "evolution_radar" | "layer_sunburst" ->
      "<figure role=\"img\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</figure>"
    "peer_ring" | "version_clock_ring" | "router_topology_mini" ->
      "<figure role=\"img\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</figure>"
    "antibody_list" | "hitl_pending_queue" | "message_thread" ->
      "<ul role=\"list\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</ul>"
    "attack_timeline" | "event_frequency_heatmap" ->
      "<div class=\"timeline\" role=\"img\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "knowledge_graph_mini" | "dependency_dag" ->
      "<figure role=\"img\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</figure>"
    "task_kanban_board" ->
      "<div class=\"card-grid-wide\" role=\"grid\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    // Agent components
    "tool_call_panel" | "reasoning_stream" ->
      "<div role=\"log\" aria-live=\"polite\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "agent_hierarchy_tree" ->
      "<ul role=\"tree\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</ul>"
    "agent_capability_badges" ->
      "<div class=\"ooda-phases\" role=\"group\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    // Safety components
    "guardian_approval_panel" ->
      "<div class=\"alert alert-warning\" role=\"alertdialog\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    "psi_invariant_dashboard" | "sil6_compliance_matrix" ->
      "<table role=\"table\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</table>"
    "emergency_banner" ->
      "<div class=\"alert alert-critical\" role=\"alert\" aria-live=\"assertive\""
      <> id_attr
      <> ">"
      <> children_html
      <> "</div>"
    "audit_trail_log" ->
      "<div role=\"log\" aria-live=\"off\""
      <> id_attr
      <> aria_label
      <> ">"
      <> children_html
      <> "</div>"
    _ ->
      "<div data-a2ui-type=\""
      <> safe_type
      <> "\""
      <> id_attr
      <> aria_label
      <> " role=\"region\""
      <> ">"
      <> children_html
      <> "</div>"
  }
}

fn escape_html_attr(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&#39;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

/// Render to JSON (for Wisp API response).
fn render_json(proposal: ComponentProposal) -> json.Json {
  proposal_to_json(proposal)
}

/// Render to rich ANSI terminal text (for TUI) using cockpit/visuals primitives.
/// Each A2UI component maps to its visually richest TUI representation.
fn render_ansi(proposal: ComponentProposal) -> String {
  let children_ansi =
    list.map(proposal.children, render_ansi) |> string.join("\n")
  let component_text = case proposal.component_type {
    "badge" -> visuals.render_badge(proposal.id, "info")
    "button" | "action_button" ->
      visuals.with_color("┃", "dim")
      <> visuals.with_color(" " <> proposal.id <> " ", "green")
      <> visuals.with_color("┃", "dim")
    "emergency_stop" -> visuals.render_badge("EMERGENCY STOP", "critical")
    "alert" ->
      visuals.with_color("⚠ ", "red")
      <> visuals.render_badge("ALERT", "critical")
      <> " "
      <> proposal.id
    "progress" -> proposal.id <> " " <> visuals.render_progress_bar(0.6, 20)
    "sparkline" ->
      proposal.id
      <> " "
      <> visuals.render_sparkline([0.2, 0.4, 0.6, 0.8, 0.7, 0.9, 0.85])
    "ooda_ring" -> visuals.render_ooda_ring("observe")
    "topology" ->
      visuals.with_color("◆", "green")
      <> visuals.with_color("───", "dim")
      <> visuals.with_color("◆", "green")
      <> visuals.with_color("───", "dim")
      <> visuals.with_color("◆", "green")
      <> " "
      <> proposal.id
    "reasoning" -> visuals.with_color("💭 ", "magenta") <> proposal.id
    "data_table" ->
      visuals.render_table(["Column A", "Column B"], [["data", "value"]], [
        12,
        12,
      ])
    "container_card" ->
      visuals.with_color("╭─ ", "cyan")
      <> proposal.id
      <> visuals.with_color(" ─╮", "cyan")
    "card_grid" ->
      visuals.with_color(
        "╔═══ " <> string.uppercase(proposal.id) <> " ═══╗",
        "cyan",
      )
    "section" ->
      visuals.with_color(
        "── " <> string.uppercase(proposal.id) <> " ──",
        "cyan",
      )
    "modal" ->
      visuals.with_color("┌─────────────────────────────┐\n", "white")
      <> visuals.with_color("│ ", "white")
      <> visuals.render_badge(proposal.id, "warning")
      <> visuals.with_color("           │\n", "white")
      <> visuals.with_color("└─────────────────────────────┘", "white")
    // --- LAYOUT ---
    "split_pane" ->
      visuals.with_color("╟", "dim")
      <> " "
      <> proposal.id
      <> " "
      <> visuals.with_color("╢", "dim")
    "tab_strip" -> visuals.with_color("┌─┐┌─┐┌─┐", "cyan") <> " " <> proposal.id
    "collapsible_panel" -> visuals.with_color("▸ ", "cyan") <> proposal.id
    "fractal_breadcrumb" ->
      visuals.with_color("L0 › L3 › L5", "dim") <> " " <> proposal.id
    "grid_layout" | "responsive_columns" ->
      visuals.with_color("┌┬┐", "dim") <> " " <> proposal.id
    "scroll_viewport" -> visuals.with_color("↕ ", "dim") <> proposal.id
    "sidebar_nav" -> visuals.with_color("≡ NAV", "cyan")
    "modal_overlay" -> visuals.with_color("█▓▒░", "dim") <> " " <> proposal.id
    "sticky_footer" ->
      visuals.with_color("─── ", "dim")
      <> proposal.id
      <> visuals.with_color(" ───", "dim")
    "layer_accordion" -> visuals.with_color("▼ L0-L7", "cyan")
    "dashboard_tile" ->
      visuals.with_color("┌─────┐", "cyan")
      <> "\n"
      <> visuals.with_color("│", "cyan")
      <> " "
      <> proposal.id
    "header_bar" -> visuals.with_color("═══ C3I ═══", "cyan")
    "empty_state" -> visuals.with_color("  ◌ ", "dim") <> proposal.id
    // --- DATA ---
    "kv_table" -> visuals.render_kv_row(proposal.id, "—", 16)
    "log_stream" -> visuals.with_color("│", "dim") <> " " <> proposal.id
    "json_tree" -> visuals.with_color("{…}", "yellow") <> " " <> proposal.id
    "triple_row" ->
      visuals.with_color("(S)─(P)→(O)", "magenta") <> " " <> proposal.id
    "diff_viewer" ->
      visuals.with_color("+", "green")
      <> visuals.with_color("-", "red")
      <> " "
      <> proposal.id
    "metric_counter" -> visuals.with_color("▲", "green") <> " " <> proposal.id
    "histogram_bar" ->
      visuals.render_progress_bar(0.7, 16) <> " " <> proposal.id
    "version_vector_row" ->
      visuals.with_color("⊕", "blue") <> " " <> proposal.id
    "hash_display" -> visuals.with_color("#", "yellow") <> proposal.id
    "container_log_tail" -> visuals.with_color("⏎ ", "dim") <> proposal.id
    "sparql_result_grid" ->
      visuals.with_color("?s ?p ?o", "magenta") <> " " <> proposal.id
    "event_payload_card" -> visuals.render_badge(proposal.id, "info")
    "latency_gauge" -> visuals.with_color("⏱", "yellow") <> " " <> proposal.id
    "resource_usage_row" ->
      visuals.render_progress_bar(0.5, 12) <> " " <> proposal.id
    "task_detail_pane" -> visuals.with_color("📋", "cyan") <> " " <> proposal.id
    "proof_token_card" ->
      visuals.render_badge("PROOF", "healthy") <> " " <> proposal.id
    // --- STATUS ---
    "health_indicator" -> visuals.with_color("●", "green")
    "connection_status" -> visuals.with_color("⟡ ", "green") <> proposal.id
    "cockpit_mode_badge" -> visuals.render_badge("DARK", "info")
    "quorum_indicator" -> visuals.with_color("⊛", "green") <> " 2/3 quorum"
    "boot_phase_tracker" ->
      visuals.with_color("①②③④⑤⑥⑦", "cyan") <> " " <> proposal.id
    "threat_level_bar" -> visuals.render_badge("NOMINAL", "healthy")
    "container_status_dot" ->
      visuals.with_color("●", "green") <> " " <> proposal.id
    "psi_invariant_row" ->
      visuals.with_color("[✓]", "green") <> " " <> proposal.id
    "sil_compliance_badge" -> visuals.render_badge("SIL-6", "healthy")
    "circuit_breaker_status" -> visuals.with_color("⚡", "green") <> " closed"
    "mara_status" -> visuals.with_color("🔥", "yellow") <> " " <> proposal.id
    "agent_heartbeat" -> visuals.with_color("♥", "green") <> " " <> proposal.id
    "sync_status_icon" -> visuals.with_color("⇌", "green") <> " in-sync"
    "entropy_score" -> visuals.with_color("H=", "cyan") <> "2.67"
    "test_suite_status" ->
      visuals.with_color("✓", "green") <> " " <> proposal.id
    "cognitive_load_meter" ->
      visuals.render_progress_bar(0.3, 10) <> " cognitive"
    "dag_integrity_badge" -> visuals.render_badge("DAG OK", "healthy")
    "mesh_mode_indicator" -> visuals.render_badge("CLUSTERED", "info")
    // --- INTERACTIVE ---
    "filter_bar" -> visuals.with_color("[all] [active] [pending]", "cyan")
    "search_input" -> visuals.with_color("🔍 ", "dim") <> "search..."
    "confirm_dialog" ->
      visuals.with_color("[Approve]", "green")
      <> " "
      <> visuals.with_color("[Reject]", "red")
    "toggle_switch" -> visuals.with_color("◉ ON", "green")
    "dropdown_select" -> visuals.with_color("▼ ", "cyan") <> proposal.id
    "command_palette" -> visuals.with_color("⌘K ", "cyan") <> "command palette"
    "threshold_slider" -> visuals.with_color("◄━━━━●━━━━►", "cyan")
    "bulk_action_bar" ->
      visuals.with_color("[Start All] [Stop All] [Restart]", "yellow")
    "topic_subscribe_btn" -> visuals.with_color("📡", "green") <> " subscribe"
    "refresh_button" -> visuals.with_color("↻", "cyan") <> " refresh"
    "pagination_controls" -> visuals.with_color("‹ 1 2 3 ›", "dim")
    "sort_header" -> visuals.with_color("▼ ", "cyan") <> proposal.id
    "copy_button" -> visuals.with_color("📋", "dim")
    "two_key_release" ->
      visuals.with_color("🔑", "yellow")
      <> visuals.with_color("🔑", "yellow")
      <> " bicameral"
    "chaos_inject_btn" -> visuals.render_badge("CHAOS", "critical") <> " inject"
    "time_range_picker" -> visuals.with_color("⏰ ", "dim") <> "range"
    // --- VISUALIZATION ---
    "container_grid_16" -> visuals.with_color("●●●●\n●●●●\n●●●●\n●●●●", "green")
    "ooda_waterfall" ->
      visuals.render_sparkline([0.03, 0.08, 0.02, 0.05, 0.04, 0.03])
      <> " OODA cycles"
    "trace_flamegraph" ->
      visuals.with_color("▓▓▓▒▒░░", "yellow") <> " flamegraph"
    "span_gantt_chart" ->
      visuals.with_color("━━━━  ━━━  ━━━━━━", "cyan") <> " gantt"
    "peer_ring" -> visuals.with_color("◆─◆─◆", "green") <> " federation ring"
    "antibody_list" -> visuals.with_color("🛡 ", "green") <> proposal.id
    "attack_timeline" -> visuals.with_color("──⚡──⚡──", "red") <> " attacks"
    "knowledge_graph_mini" -> visuals.with_color("⊙─⊙─⊙", "magenta") <> " kg"
    "pid_control_plot" ->
      visuals.render_sparkline([0.8, 0.9, 0.95, 0.98, 1.0, 0.99]) <> " PID"
    "version_clock_ring" -> visuals.with_color("◎ ", "blue") <> "version clocks"
    "event_frequency_heatmap" ->
      visuals.with_color("▓▒░▒▓", "yellow") <> " events/s"
    "task_kanban_board" -> visuals.with_color("│TODO│WIP│DONE│", "cyan")
    "dependency_dag" -> visuals.with_color("⊙→⊙→⊙", "dim") <> " DAG"
    "reconciliation_diff" ->
      visuals.with_color("+3 -1 ~2", "yellow") <> " reconcile"
    "router_topology_mini" -> visuals.with_color("◆─◆\n ╲╱\n  ◆", "green")
    "metric_time_series" ->
      visuals.render_sparkline([0.5, 0.6, 0.7, 0.8, 0.75, 0.9])
    "hash_chain_strip" -> visuals.with_color("[#a1]→[#b2]→[#c3]→[#d4]", "green")
    "layer_sunburst" -> visuals.with_color("◎ L0-L7", "cyan")
    "evolution_radar" -> visuals.with_color("◇ V1/V2/V3/V4", "magenta")
    "coverage_gauge_ring" -> visuals.render_progress_bar(0.85, 16) <> " CCM"
    // --- AGENT ---
    "agent_run_card" ->
      visuals.with_color("▶ ", "green") <> "run:" <> proposal.id
    "tool_call_panel" -> visuals.with_color("🔧 ", "yellow") <> proposal.id
    "reasoning_stream" -> visuals.with_color("💭 ", "magenta") <> proposal.id
    "sse_connection_indicator" -> visuals.with_color("📡", "green") <> " SSE"
    "agent_hierarchy_tree" ->
      visuals.with_color("├─ cortex\n│ ├─ intel×4\n│ └─ worker×20", "cyan")
    "hitl_pending_queue" -> visuals.with_color("⏳", "yellow") <> " HITL pending"
    "activity_feed" -> visuals.with_color("≡ ", "dim") <> proposal.id
    "state_inspector" ->
      visuals.with_color("{state}", "cyan") <> " " <> proposal.id
    "message_thread" -> visuals.with_color("💬 ", "blue") <> proposal.id
    "agent_capability_badges" ->
      visuals.render_badge("EMIT", "info")
      <> visuals.render_badge("HITL", "warning")
    // --- SAFETY ---
    "guardian_approval_panel" ->
      visuals.render_badge("GUARDIAN", "warning") <> " " <> proposal.id
    "psi_invariant_dashboard" ->
      visuals.with_color("Ψ₀✓ Ψ₁✓ Ψ₂✓ Ψ₃✓ Ψ₄✓ Ψ₅✓ Ω₀✓", "green")
    "emergency_banner" ->
      visuals.render_badge("EMERGENCY", "critical") <> " " <> proposal.id
    "constitutional_hash_chain" ->
      visuals.with_color("⊕→⊕→⊕→⊕", "green") <> " constitution"
    "audit_trail_log" -> visuals.with_color("📜 ", "dim") <> proposal.id
    "sil6_compliance_matrix" -> visuals.render_badge("SIL-6 MATRIX", "healthy")
    _ ->
      visuals.with_color("[" <> proposal.component_type <> "]", "dim")
      <> " "
      <> proposal.id
  }
  case children_ansi {
    "" -> component_text
    _ -> component_text <> "\n  " <> string.replace(children_ansi, "\n", "\n  ")
  }
}

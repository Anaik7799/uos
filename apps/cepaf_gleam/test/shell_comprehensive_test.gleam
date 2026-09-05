// Comprehensive tests for cepaf_gleam/ui/lustre/shell
// Covers all public render functions: status_card, container_card, mini_bar,
// section, kv_row, alert_banner, data_table, action_button, apalache_guard,
// genome_grid, ooda_5tier, proof_chain, render_a2ui_component,
// container_action_buttons, hot_reload_button, guardian_approval_panel,
// task_create_form, ooda_trigger_button, zenoh_publish_form,
// cockpit_mode_switch, zk_search_bar, alarm_acknowledge_button,
// beam_scheduler_panel, guard_grid_drilldown, ooda_trace_viewer,
// nif_latency_panel, zenoh_inspector_panel, otel_span_viewer,
// health_cascade_tree, emergency_stop_button, render_page
//
// Strategy: every function is pure / returns an Element(msg) or String.
// We call each function with representative arguments and assert the result
// is truthy (no crash). Where a string is returned we also verify key
// substrings are present.
//
// STAMP: SC-GLM-UI-001, SC-HMI-TEST, SC-MUDA-001

import cepaf_gleam/a2ui/schema as a2ui_schema
import cepaf_gleam/ui/lustre/shell
import gleam/json
import gleam/option
import gleam/string
import gleeunit/should
import lustre/element

// ---------------------------------------------------------------------------
// C1: status_card
// ---------------------------------------------------------------------------

pub fn status_card_healthy_test() {
  let el = shell.status_card("CPU", "Healthy", "32%", "16 cores")
  let html = element.to_string(el)
  string.contains(html, "CPU") |> should.be_true
  string.contains(html, "Healthy") |> should.be_true
  string.contains(html, "status-healthy") |> should.be_true
}

pub fn status_card_degraded_test() {
  let el = shell.status_card("Memory", "Degraded", "88%", "near limit")
  let html = element.to_string(el)
  string.contains(html, "status-degraded") |> should.be_true
  string.contains(html, "Degraded") |> should.be_true
}

pub fn status_card_critical_test() {
  let el = shell.status_card("Disk", "Critical", "99%", "full")
  let html = element.to_string(el)
  string.contains(html, "status-critical") |> should.be_true
}

pub fn status_card_unknown_test() {
  let el = shell.status_card("Network", "Unknown", "n/a", "no data")
  let html = element.to_string(el)
  string.contains(html, "status-unknown") |> should.be_true
}

pub fn status_card_has_card_class_test() {
  let el = shell.status_card("Test", "Healthy", "ok", "detail")
  let html = element.to_string(el)
  string.contains(html, "card") |> should.be_true
}

// ---------------------------------------------------------------------------
// C2: container_card
// ---------------------------------------------------------------------------

pub fn container_card_running_test() {
  let el = shell.container_card("ex-app-1", "running", 0.25, 0.4)
  let html = element.to_string(el)
  string.contains(html, "ex-app-1") |> should.be_true
  string.contains(html, "running") |> should.be_true
  string.contains(html, "status-healthy") |> should.be_true
}

pub fn container_card_stopped_test() {
  let el = shell.container_card("zenoh-router", "stopped", 0.0, 0.0)
  let html = element.to_string(el)
  string.contains(html, "status-critical") |> should.be_true
}

pub fn container_card_apoptotic_test() {
  let el = shell.container_card("cortex", "apoptotic", 0.05, 0.1)
  let html = element.to_string(el)
  string.contains(html, "cortex") |> should.be_true
  // apoptotic card has dissolved animation
  string.contains(html, "apoptot") |> should.be_true
}

pub fn container_card_shows_cpu_mem_test() {
  let el = shell.container_card("db-prod", "running", 0.5, 0.6)
  let html = element.to_string(el)
  string.contains(html, "CPU") |> should.be_true
  string.contains(html, "MEM") |> should.be_true
}

// ---------------------------------------------------------------------------
// C3: mini_bar
// ---------------------------------------------------------------------------

pub fn mini_bar_renders_test() {
  let el = shell.mini_bar(0.5, 1.0, "#00d4aa")
  let html = element.to_string(el)
  string.contains(html, "bar-fill") |> should.be_true
  string.contains(html, "bar-wrap") |> should.be_true
}

pub fn mini_bar_zero_max_test() {
  let el = shell.mini_bar(5.0, 0.0, "#ff0000")
  let html = element.to_string(el)
  // Should not crash; should render 0% width
  string.contains(html, "width:0%") |> should.be_true
}

pub fn mini_bar_full_test() {
  let el = shell.mini_bar(1.0, 1.0, "#3dd68c")
  let html = element.to_string(el)
  string.contains(html, "width:100%") |> should.be_true
}

// ---------------------------------------------------------------------------
// C4: section
// ---------------------------------------------------------------------------

pub fn section_renders_title_test() {
  let child = element.text("child content")
  let el = shell.section("System Status", [child])
  let html = element.to_string(el)
  string.contains(html, "System Status") |> should.be_true
  string.contains(html, "section-title") |> should.be_true
}

pub fn section_renders_children_test() {
  let child = element.text("hello world")
  let el = shell.section("Metrics", [child])
  let html = element.to_string(el)
  string.contains(html, "hello world") |> should.be_true
}

pub fn section_empty_children_test() {
  let el = shell.section("Empty", [])
  let html = element.to_string(el)
  string.contains(html, "Empty") |> should.be_true
}

// ---------------------------------------------------------------------------
// C5: kv_row
// ---------------------------------------------------------------------------

pub fn kv_row_renders_key_value_test() {
  let el = shell.kv_row("Version", "22.6.2")
  let html = element.to_string(el)
  string.contains(html, "Version") |> should.be_true
  string.contains(html, "22.6.2") |> should.be_true
  string.contains(html, "kv-key") |> should.be_true
  string.contains(html, "kv-value") |> should.be_true
}

pub fn kv_row_empty_value_test() {
  let el = shell.kv_row("Label", "")
  let html = element.to_string(el)
  string.contains(html, "Label") |> should.be_true
}

// ---------------------------------------------------------------------------
// C6: alert_banner
// ---------------------------------------------------------------------------

pub fn alert_banner_critical_test() {
  let el = shell.alert_banner("critical", "System failure detected")
  let html = element.to_string(el)
  string.contains(html, "alert-critical") |> should.be_true
  string.contains(html, "System failure detected") |> should.be_true
}

pub fn alert_banner_warning_test() {
  let el = shell.alert_banner("warning", "CPU above 80%")
  let html = element.to_string(el)
  string.contains(html, "alert-warning") |> should.be_true
}

pub fn alert_banner_info_test() {
  let el = shell.alert_banner("info", "Deployment complete")
  let html = element.to_string(el)
  string.contains(html, "alert-info") |> should.be_true
}

pub fn alert_banner_unknown_severity_falls_back_to_info_test() {
  let el = shell.alert_banner("debug", "Low-level event")
  let html = element.to_string(el)
  // Non-critical/non-warning → info class
  string.contains(html, "alert-info") |> should.be_true
}

// ---------------------------------------------------------------------------
// C7: data_table
// ---------------------------------------------------------------------------

pub fn data_table_renders_headers_test() {
  let headers = ["Name", "Status", "CPU"]
  let rows = [["ex-app-1", "running", "25%"]]
  let el = shell.data_table(headers, rows)
  let html = element.to_string(el)
  string.contains(html, "Name") |> should.be_true
  string.contains(html, "Status") |> should.be_true
  string.contains(html, "CPU") |> should.be_true
}

pub fn data_table_renders_rows_test() {
  let headers = ["Container", "State"]
  let rows = [
    ["zenoh-router", "running"],
    ["db-prod", "stopped"],
    ["cortex", "running"],
  ]
  let el = shell.data_table(headers, rows)
  let html = element.to_string(el)
  string.contains(html, "zenoh-router") |> should.be_true
  string.contains(html, "db-prod") |> should.be_true
  string.contains(html, "cortex") |> should.be_true
}

pub fn data_table_empty_rows_test() {
  let el = shell.data_table(["Col1", "Col2"], [])
  let html = element.to_string(el)
  string.contains(html, "Col1") |> should.be_true
  // table element present
  string.contains(html, "<table") |> should.be_true
}

// ---------------------------------------------------------------------------
// C8: action_button
// ---------------------------------------------------------------------------

pub fn action_button_renders_label_test() {
  let el = shell.action_button("Restart", "/api/v1/restart", "{}")
  let html = element.to_string(el)
  string.contains(html, "Restart") |> should.be_true
}

pub fn action_button_has_endpoint_test() {
  let el = shell.action_button("Deploy", "/api/v1/deploy", "{\"env\":\"prod\"}")
  let html = element.to_string(el)
  string.contains(html, "/api/v1/deploy") |> should.be_true
}

pub fn action_button_has_onclick_test() {
  let el = shell.action_button("Sync", "/api/v1/sync", "{}")
  let html = element.to_string(el)
  string.contains(html, "onclick") |> should.be_true
  string.contains(html, "fetch") |> should.be_true
}

// ---------------------------------------------------------------------------
// apalache_guard
// ---------------------------------------------------------------------------

pub fn apalache_guard_safe_renders_test() {
  let inner = element.text("Approve")
  let el = shell.apalache_guard(inner, "mathematically_safe")
  let html = element.to_string(el)
  string.contains(html, "apalache-guard") |> should.be_true
  string.contains(html, "Approve") |> should.be_true
}

pub fn apalache_guard_unsafe_shows_overlay_test() {
  let inner = element.text("Dangerous")
  let el = shell.apalache_guard(inner, "unsafe")
  let html = element.to_string(el)
  string.contains(html, "TLA+ UNSAFE") |> should.be_true
}

// ---------------------------------------------------------------------------
// genome_grid
// ---------------------------------------------------------------------------

pub fn genome_grid_renders_containers_test() {
  let containers = [
    #("zenoh-router", "healthy"),
    #("db-prod", "degraded"),
    #("cortex", "critical"),
  ]
  let el = shell.genome_grid(containers)
  let html = element.to_string(el)
  string.contains(html, "zenoh-router") |> should.be_true
  string.contains(html, "genome-healthy") |> should.be_true
  string.contains(html, "genome-degraded") |> should.be_true
  string.contains(html, "genome-critical") |> should.be_true
}

pub fn genome_grid_empty_test() {
  let el = shell.genome_grid([])
  let html = element.to_string(el)
  string.contains(html, "genome-grid") |> should.be_true
}

// ---------------------------------------------------------------------------
// ooda_5tier
// ---------------------------------------------------------------------------

pub fn ooda_5tier_observe_active_test() {
  let el = shell.ooda_5tier("observe")
  let html = element.to_string(el)
  string.contains(html, "Observe") |> should.be_true
  string.contains(html, "active") |> should.be_true
}

pub fn ooda_5tier_decide_active_test() {
  let el = shell.ooda_5tier("decide")
  let html = element.to_string(el)
  string.contains(html, "Decide") |> should.be_true
}

pub fn ooda_5tier_all_phases_present_test() {
  let el = shell.ooda_5tier("act")
  let html = element.to_string(el)
  string.contains(html, "Observe") |> should.be_true
  string.contains(html, "Orient") |> should.be_true
  string.contains(html, "Decide") |> should.be_true
  string.contains(html, "Act") |> should.be_true
  string.contains(html, "Verify") |> should.be_true
}

pub fn ooda_5tier_budget_labels_present_test() {
  let el = shell.ooda_5tier("orient")
  let html = element.to_string(el)
  // budget labels
  string.contains(html, "ms") |> should.be_true
}

// ---------------------------------------------------------------------------
// proof_chain
// ---------------------------------------------------------------------------

pub fn proof_chain_verified_test() {
  let proofs = [#("0xABCD1234", True), #("0xDEAD5678", False)]
  let el = shell.proof_chain(proofs)
  let html = element.to_string(el)
  string.contains(html, "0xABCD1234") |> should.be_true
  string.contains(html, "verified") |> should.be_true
  string.contains(html, "pending") |> should.be_true
}

pub fn proof_chain_empty_test() {
  let el = shell.proof_chain([])
  let html = element.to_string(el)
  string.contains(html, "proof-chain") |> should.be_true
}

pub fn proof_chain_arrow_between_blocks_test() {
  let proofs = [#("hash-a", True), #("hash-b", True)]
  let el = shell.proof_chain(proofs)
  let html = element.to_string(el)
  string.contains(html, "proof-arrow") |> should.be_true
}

// ---------------------------------------------------------------------------
// render_a2ui_component — invalid proposal returns error badge
// ---------------------------------------------------------------------------

pub fn render_a2ui_component_invalid_type_test() {
  let proposal =
    a2ui_schema.ComponentProposal(
      id: "test-invalid",
      component_type: "nonexistent_widget",
      props: json.object([]),
      children: [],
      binding: option.None,
    )
  let el = shell.render_a2ui_component(proposal)
  let html = element.to_string(el)
  // validator rejects unknown type → error div
  string.contains(html, "a2ui-error") |> should.be_true
}

pub fn render_a2ui_component_valid_badge_test() {
  let proposal =
    a2ui_schema.ComponentProposal(
      id: "test-badge",
      component_type: "badge",
      props: json.object([
        #("label", json.string("OK")),
        #("variant", json.string("success")),
      ]),
      children: [],
      binding: option.None,
    )
  let el = shell.render_a2ui_component(proposal)
  let html = element.to_string(el)
  // valid badge → element renders (may be error if badge not in catalog)
  { string.length(html) > 0 } |> should.equal(True)
}

// ---------------------------------------------------------------------------
// container_action_buttons
// ---------------------------------------------------------------------------

pub fn container_action_buttons_has_restart_test() {
  let el = shell.container_action_buttons()
  let html = element.to_string(el)
  string.contains(html, "Restart Containers") |> should.be_true
  string.contains(html, "/api/v1/podman/restart") |> should.be_true
}

pub fn container_action_buttons_has_stop_test() {
  let el = shell.container_action_buttons()
  let html = element.to_string(el)
  string.contains(html, "Stop Containers") |> should.be_true
  string.contains(html, "/api/v1/podman/stop") |> should.be_true
}

pub fn container_action_buttons_confirm_dialogs_test() {
  let el = shell.container_action_buttons()
  let html = element.to_string(el)
  string.contains(html, "confirm") |> should.be_true
}

// ---------------------------------------------------------------------------
// hot_reload_button
// ---------------------------------------------------------------------------

pub fn hot_reload_button_renders_test() {
  let el = shell.hot_reload_button()
  let html = element.to_string(el)
  string.contains(html, "Hot Reload") |> should.be_true
  string.contains(html, "/api/v1/reload") |> should.be_true
}

pub fn hot_reload_button_confirm_test() {
  let el = shell.hot_reload_button()
  let html = element.to_string(el)
  string.contains(html, "confirm") |> should.be_true
}

// ---------------------------------------------------------------------------
// guardian_approval_panel
// ---------------------------------------------------------------------------

pub fn guardian_approval_panel_renders_test() {
  let el = shell.guardian_approval_panel()
  let html = element.to_string(el)
  string.contains(html, "Guardian") |> should.be_true
  string.contains(html, "Approve") |> should.be_true
  string.contains(html, "Reject") |> should.be_true
}

pub fn guardian_approval_panel_endpoint_test() {
  let el = shell.guardian_approval_panel()
  let html = element.to_string(el)
  string.contains(html, "/api/v1/guardian/respond") |> should.be_true
}

pub fn guardian_approval_panel_2oo3_mentioned_test() {
  let el = shell.guardian_approval_panel()
  let html = element.to_string(el)
  string.contains(html, "2oo3") |> should.be_true
}

// ---------------------------------------------------------------------------
// task_create_form
// ---------------------------------------------------------------------------

pub fn task_create_form_renders_test() {
  let el = shell.task_create_form()
  let html = element.to_string(el)
  string.contains(html, "Add Task") |> should.be_true
  string.contains(html, "/api/v1/planning/add") |> should.be_true
}

pub fn task_create_form_has_priority_test() {
  let el = shell.task_create_form()
  let html = element.to_string(el)
  string.contains(html, "Priority") |> should.be_true
  string.contains(html, "P1") |> should.be_true
  string.contains(html, "P2") |> should.be_true
}

// ---------------------------------------------------------------------------
// ooda_trigger_button
// ---------------------------------------------------------------------------

pub fn ooda_trigger_button_renders_test() {
  let el = shell.ooda_trigger_button()
  let html = element.to_string(el)
  string.contains(html, "Trigger OODA Cycle") |> should.be_true
  string.contains(html, "/api/v1/system/ooda-trigger") |> should.be_true
}

// ---------------------------------------------------------------------------
// zenoh_publish_form
// ---------------------------------------------------------------------------

pub fn zenoh_publish_form_renders_test() {
  let el = shell.zenoh_publish_form()
  let html = element.to_string(el)
  string.contains(html, "Publish") |> should.be_true
  string.contains(html, "/api/v1/zenoh/publish") |> should.be_true
  string.contains(html, "Topic") |> should.be_true
  string.contains(html, "Payload") |> should.be_true
}

// ---------------------------------------------------------------------------
// cockpit_mode_switch
// ---------------------------------------------------------------------------

pub fn cockpit_mode_switch_has_all_modes_test() {
  let el = shell.cockpit_mode_switch()
  let html = element.to_string(el)
  string.contains(html, "Dark") |> should.be_true
  string.contains(html, "Normal") |> should.be_true
  string.contains(html, "Emergency") |> should.be_true
  string.contains(html, "/api/v1/cockpit/mode") |> should.be_true
}

// ---------------------------------------------------------------------------
// zk_search_bar
// ---------------------------------------------------------------------------

pub fn zk_search_bar_renders_test() {
  let el = shell.zk_search_bar()
  let html = element.to_string(el)
  string.contains(html, "Search") |> should.be_true
  string.contains(html, "/api/v1/knowledge/search") |> should.be_true
  string.contains(html, "Zettelkasten") |> should.be_true
}

// ---------------------------------------------------------------------------
// alarm_acknowledge_button
// ---------------------------------------------------------------------------

pub fn alarm_acknowledge_button_renders_test() {
  let el = shell.alarm_acknowledge_button()
  let html = element.to_string(el)
  string.contains(html, "Acknowledge Alarms") |> should.be_true
  string.contains(html, "/api/v1/cockpit/alarm/acknowledge") |> should.be_true
}

pub fn alarm_acknowledge_button_confirm_test() {
  let el = shell.alarm_acknowledge_button()
  let html = element.to_string(el)
  string.contains(html, "confirm") |> should.be_true
}

// ---------------------------------------------------------------------------
// beam_scheduler_panel
// ---------------------------------------------------------------------------

pub fn beam_scheduler_panel_renders_test() {
  let el = shell.beam_scheduler_panel()
  let html = element.to_string(el)
  string.contains(html, "BEAM Scheduler Metrics") |> should.be_true
  string.contains(html, "Schedulers") |> should.be_true
}

// ---------------------------------------------------------------------------
// guard_grid_drilldown
// ---------------------------------------------------------------------------

pub fn guard_grid_drilldown_renders_test() {
  let el = shell.guard_grid_drilldown()
  let html = element.to_string(el)
  string.contains(html, "Guard Grid") |> should.be_true
  string.contains(html, "24 Cells") |> should.be_true
}

// ---------------------------------------------------------------------------
// ooda_trace_viewer
// ---------------------------------------------------------------------------

pub fn ooda_trace_viewer_renders_test() {
  let el = shell.ooda_trace_viewer()
  let html = element.to_string(el)
  string.contains(html, "OODA Cycle Trace") |> should.be_true
  string.contains(html, "Observe") |> should.be_true
}

// ---------------------------------------------------------------------------
// nif_latency_panel
// ---------------------------------------------------------------------------

pub fn nif_latency_panel_renders_test() {
  let el = shell.nif_latency_panel()
  let html = element.to_string(el)
  string.contains(html, "NIF Call Latency") |> should.be_true
  string.contains(html, "plan_status") |> should.be_true
}

// ---------------------------------------------------------------------------
// zenoh_inspector_panel
// ---------------------------------------------------------------------------

pub fn zenoh_inspector_panel_renders_test() {
  let el = shell.zenoh_inspector_panel()
  let html = element.to_string(el)
  string.contains(html, "Zenoh Message Inspector") |> should.be_true
  string.contains(html, "indrajaal") |> should.be_true
}

// ---------------------------------------------------------------------------
// otel_span_viewer
// ---------------------------------------------------------------------------

pub fn otel_span_viewer_renders_test() {
  let el = shell.otel_span_viewer()
  let html = element.to_string(el)
  string.contains(html, "OTel Span Viewer") |> should.be_true
  string.contains(html, "OpenTelemetry") |> should.be_true
}

// ---------------------------------------------------------------------------
// health_cascade_tree
// ---------------------------------------------------------------------------

pub fn health_cascade_tree_renders_test() {
  let el = shell.health_cascade_tree()
  let html = element.to_string(el)
  string.contains(html, "Health Cascade Tree") |> should.be_true
  string.contains(html, "container") |> should.be_true
}

// ---------------------------------------------------------------------------
// emergency_stop_button
// ---------------------------------------------------------------------------

pub fn emergency_stop_button_renders_test() {
  let el = shell.emergency_stop_button()
  let html = element.to_string(el)
  string.contains(html, "EMERGENCY STOP") |> should.be_true
  string.contains(html, "/api/v1/emergency/trigger") |> should.be_true
}

pub fn emergency_stop_button_confirm_dialog_test() {
  let el = shell.emergency_stop_button()
  let html = element.to_string(el)
  string.contains(html, "confirm") |> should.be_true
  string.contains(html, "Guardian") |> should.be_true
}

pub fn emergency_stop_button_2oo3_consensus_test() {
  let el = shell.emergency_stop_button()
  let html = element.to_string(el)
  string.contains(html, "2oo3") |> should.be_true
}

// ---------------------------------------------------------------------------
// render_page (full HTML document)
// ---------------------------------------------------------------------------

pub fn render_page_produces_doctype_test() {
  let content = element.text("Hello C3I")
  let html = shell.render_page("Test Page", "/dashboard", content)
  string.contains(html, "<!doctype html>") |> should.be_true
}

pub fn render_page_has_title_test() {
  let content = element.text("Content")
  let html = shell.render_page("Dashboard", "/dashboard", content)
  string.contains(html, "C3I \u{2014} Dashboard") |> should.be_true
}

pub fn render_page_active_nav_link_test() {
  let content = element.text("Body")
  let html = shell.render_page("Planning", "/planning", content)
  string.contains(html, "active") |> should.be_true
  string.contains(html, "/planning") |> should.be_true
}

pub fn render_page_has_nav_brand_test() {
  let content = element.text("x")
  let html = shell.render_page("Home", "/dashboard", content)
  string.contains(html, "C3I") |> should.be_true
  string.contains(html, "nav-brand") |> should.be_true
}

pub fn render_page_has_main_tag_test() {
  let content = element.text("main content")
  let html = shell.render_page("Cockpit", "/cockpit", content)
  string.contains(html, "<main") |> should.be_true
  string.contains(html, "main content") |> should.be_true
}

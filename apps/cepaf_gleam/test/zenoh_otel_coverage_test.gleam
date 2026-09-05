// Zenoh OTel Span Coverage Tests — All 15 Pages + Attribute Helpers
// Validates SC-GLM-ZEN-001: All UI state changes publish OTel spans
// STAMP: SC-GLM-ZEN-001, SC-GLM-ZEN-002, SC-ZENOH-006

import cepaf_gleam/ui/domain.{
  Cockpit, Dashboard, Federation, HealthGrid, Immune, Kms, Knowledge, Mcp,
  Metabolic, Planning, Podman, Substrate, Telemetry, Verification, Zenoh,
}
import cepaf_gleam/ui/zenoh_otel.{Act, Decide, Observe, Orient}
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// All 15 Pages Create Valid Spans (SC-GLM-ZEN-001)
// =============================================================================

pub fn span_for_every_page_test() {
  let pages = [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
  ]
  let attrs = json.object([])
  list.each(pages, fn(page) {
    let span = zenoh_otel.new_span(page, "state_change", Observe, attrs)
    span.page |> should.equal(page)
    { span.name != "" } |> should.be_true()
  })
}

pub fn span_name_contains_page_path_test() {
  let span = zenoh_otel.new_span(Dashboard, "tick", Observe, json.object([]))
  string.contains(span.name, "/dashboard") |> should.be_true()
}

pub fn span_name_contains_element_test() {
  let span = zenoh_otel.new_span(Planning, "task_added", Act, json.object([]))
  string.contains(span.name, "task_added") |> should.be_true()
}

// =============================================================================
// OODA Phase Coverage
// =============================================================================

pub fn all_four_ooda_phases_test() {
  let attrs = json.object([])
  let observe = zenoh_otel.new_span(Dashboard, "el", Observe, attrs)
  let orient = zenoh_otel.new_span(Dashboard, "el", Orient, attrs)
  let decide = zenoh_otel.new_span(Dashboard, "el", Decide, attrs)
  let act = zenoh_otel.new_span(Dashboard, "el", Act, attrs)
  observe.ooda_phase |> should.equal(Observe)
  orient.ooda_phase |> should.equal(Orient)
  decide.ooda_phase |> should.equal(Decide)
  act.ooda_phase |> should.equal(Act)
}

pub fn ooda_phase_strings_unique_test() {
  let phases = [Observe, Orient, Decide, Act]
  let strings = list.map(phases, zenoh_otel.ooda_phase_to_string)
  let unique = list.unique(strings)
  list.length(unique) |> should.equal(4)
}

// =============================================================================
// Page-to-String Coverage (all 15)
// =============================================================================

pub fn all_15_page_strings_unique_test() {
  let pages = [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
  ]
  let strings = list.map(pages, zenoh_otel.page_to_string)
  let unique = list.unique(strings)
  list.length(unique) |> should.equal(15)
}

// =============================================================================
// Attribute Helpers
// =============================================================================

pub fn state_change_attrs_structure_test() {
  let attrs = zenoh_otel.state_change_attrs("idle", "active", "user_click")
  let j = json.to_string(attrs)
  string.contains(j, "\"from_state\":\"idle\"") |> should.be_true()
  string.contains(j, "\"to_state\":\"active\"") |> should.be_true()
  string.contains(j, "\"trigger\":\"user_click\"") |> should.be_true()
  string.contains(j, "\"span_kind\":\"state_change\"") |> should.be_true()
}

pub fn user_action_attrs_structure_test() {
  let attrs = zenoh_otel.user_action_attrs("navigate", "/zenoh")
  let j = json.to_string(attrs)
  string.contains(j, "\"action\":\"navigate\"") |> should.be_true()
  string.contains(j, "\"target\":\"/zenoh\"") |> should.be_true()
}

pub fn error_attrs_structure_test() {
  let attrs = zenoh_otel.error_attrs("Timeout", "5000ms exceeded")
  let j = json.to_string(attrs)
  string.contains(j, "\"error_type\":\"Timeout\"") |> should.be_true()
  string.contains(j, "\"error_message\":\"5000ms exceeded\"")
  |> should.be_true()
}

pub fn zenoh_message_attrs_structure_test() {
  let attrs = zenoh_otel.zenoh_message_attrs("indrajaal/health/node1", 42, 150)
  let j = json.to_string(attrs)
  string.contains(j, "\"zenoh_topic\"") |> should.be_true()
  string.contains(j, "\"message_count\":42") |> should.be_true()
  string.contains(j, "\"latency_us\":150") |> should.be_true()
}

pub fn control_attrs_structure_test() {
  let attrs = zenoh_otel.control_attrs("restart", "ex-app-1", "success")
  let j = json.to_string(attrs)
  string.contains(j, "\"action\":\"restart\"") |> should.be_true()
  string.contains(j, "\"span_kind\":\"control\"") |> should.be_true()
}

pub fn test_runner_attrs_structure_test() {
  let attrs = zenoh_otel.test_runner_attrs("my_test", "passed", 42)
  let j = json.to_string(attrs)
  string.contains(j, "\"test_name\":\"my_test\"") |> should.be_true()
  string.contains(j, "\"test_status\":\"passed\"") |> should.be_true()
}

pub fn agent_attrs_structure_test() {
  let attrs = zenoh_otel.agent_attrs("claude-01", "search", "codebase")
  let j = json.to_string(attrs)
  string.contains(j, "\"agent_id\":\"claude-01\"") |> should.be_true()
  string.contains(j, "\"span_kind\":\"agent\"") |> should.be_true()
}

// =============================================================================
// All Page Topics (SC-GLM-ZEN-002)
// =============================================================================

pub fn all_page_topics_returns_31_test() {
  let topics = zenoh_otel.all_page_topics()
  list.length(topics) |> should.equal(31)
}

pub fn all_page_topics_have_otel_prefix_test() {
  let topics = zenoh_otel.all_page_topics()
  list.each(topics, fn(t) {
    string.starts_with(t, "indrajaal/otel/ops/") |> should.be_true()
  })
}

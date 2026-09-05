//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>zenoh_wiring_regression_test</module></identity>
////   <fractal-topology><layer>L6_ECOSYSTEM</layer></fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-ZEN-001, SC-GLM-ZEN-002, SC-GLM-TST-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// 30 regression tests for Zenoh OTel wiring and observer enhancements.
////
//// Coverage:
////   - Per-page span creation (15 tests): one per Page variant
////   - control_attrs / test_runner_attrs / agent_attrs (6 tests)
////   - Observer enhanced verification (6 tests): verify_all_pages_published,
////     verify_ooda_coverage, verify_control_state_spans, verify_mcp_relay
////   - all_page_topics invariants (3 tests)
////
//// STAMP: SC-GLM-ZEN-001, SC-GLM-ZEN-002, SC-GLM-TST-001

import cepaf_gleam/testing/zenoh_test_observer
import cepaf_gleam/ui/domain.{
  Agents, Bicameral, Biomorphic, Bridge, Cockpit, ComponentDemo, Config,
  Dashboard, Database, Evolution, Federation, Git, HealthGrid, Holon,
  HomeostasisPage, Immune, Integrity, Kms, Knowledge, Mcp, Metabolic, Planning,
  PlanningDashboard, Podman, Prajna, Singularity, Smriti, Substrate, Telemetry,
  Verification, Zenoh,
}
import cepaf_gleam/ui/zenoh_otel.{
  Act, Decide, Observe, Orient, agent_attrs, all_page_topics, control_attrs,
  new_span, page_to_string, test_runner_attrs,
}
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Group 1: Per-page span creation (15 tests)
// One test per Page variant — verifies page field, element, and name wiring.
// =============================================================================

pub fn new_span_dashboard_page_test() {
  let span = new_span(Dashboard, "test_el", Observe, json.null())
  page_to_string(span.page) |> should.equal("dashboard")
  span.element |> should.equal("test_el")
}

pub fn new_span_planning_page_test() {
  let span = new_span(Planning, "plan_el", Orient, json.null())
  page_to_string(span.page) |> should.equal("planning")
  span.element |> should.equal("plan_el")
}

pub fn new_span_immune_page_test() {
  let span = new_span(Immune, "imm_el", Decide, json.null())
  page_to_string(span.page) |> should.equal("immune")
  span.ooda_phase |> should.equal(Decide)
}

pub fn new_span_knowledge_page_test() {
  let span = new_span(Knowledge, "kn_el", Act, json.null())
  page_to_string(span.page) |> should.equal("knowledge")
  span.ooda_phase |> should.equal(Act)
}

pub fn new_span_zenoh_page_test() {
  let span = new_span(Zenoh, "zen_el", Observe, json.null())
  page_to_string(span.page) |> should.equal("zenoh")
  span.element |> should.equal("zen_el")
}

pub fn new_span_cockpit_page_test() {
  let span = new_span(Cockpit, "ckt_el", Orient, json.null())
  page_to_string(span.page) |> should.equal("cockpit")
  span.ooda_phase |> should.equal(Orient)
}

pub fn new_span_verification_page_test() {
  let span = new_span(Verification, "ver_el", Observe, json.null())
  page_to_string(span.page) |> should.equal("verification")
  span.name |> should.equal("/verification/ver_el")
}

pub fn new_span_substrate_page_test() {
  let span = new_span(Substrate, "sub_el", Decide, json.null())
  page_to_string(span.page) |> should.equal("substrate")
  span.element |> should.equal("sub_el")
}

pub fn new_span_metabolic_page_test() {
  let span = new_span(Metabolic, "met_el", Act, json.null())
  page_to_string(span.page) |> should.equal("metabolic")
  span.ooda_phase |> should.equal(Act)
}

pub fn new_span_podman_page_test() {
  let span = new_span(Podman, "pod_el", Observe, json.null())
  page_to_string(span.page) |> should.equal("podman")
  span.element |> should.equal("pod_el")
}

pub fn new_span_mcp_page_test() {
  let span = new_span(Mcp, "mcp_el", Orient, json.null())
  page_to_string(span.page) |> should.equal("mcp")
  span.name |> should.equal("/mcp/mcp_el")
}

pub fn new_span_kms_page_test() {
  let span = new_span(Kms, "kms_el", Decide, json.null())
  page_to_string(span.page) |> should.equal("kms")
  span.element |> should.equal("kms_el")
}

pub fn new_span_telemetry_page_test() {
  let span = new_span(Telemetry, "tel_el", Act, json.null())
  page_to_string(span.page) |> should.equal("telemetry")
  span.ooda_phase |> should.equal(Act)
}

pub fn new_span_federation_page_test() {
  let span = new_span(Federation, "fed_el", Observe, json.null())
  page_to_string(span.page) |> should.equal("federation")
  span.name |> should.equal("/federation/fed_el")
}

pub fn new_span_health_grid_page_test() {
  let span = new_span(HealthGrid, "hg_el", Orient, json.null())
  page_to_string(span.page) |> should.equal("health_grid")
  span.element |> should.equal("hg_el")
}

// =============================================================================
// Group 2: control_attrs / test_runner_attrs / agent_attrs (6 tests)
// =============================================================================

pub fn control_attrs_contains_action_and_target_test() {
  let attrs = control_attrs("start", "container-1", "initiated")
  let s = json.to_string(attrs)
  string.contains(s, "start") |> should.be_true()
  string.contains(s, "container-1") |> should.be_true()
}

pub fn control_attrs_contains_span_kind_control_test() {
  let attrs = control_attrs("stop", "container-2", "ok")
  let s = json.to_string(attrs)
  string.contains(s, "control") |> should.be_true()
}

pub fn control_attrs_result_field_is_present_test() {
  let attrs = control_attrs("restart", "zenoh-router", "pending")
  let s = json.to_string(attrs)
  string.contains(s, "result") |> should.be_true()
  string.contains(s, "pending") |> should.be_true()
}

pub fn test_runner_attrs_contains_test_name_and_status_test() {
  let attrs = test_runner_attrs("my_unit_test", "passed", 42)
  let s = json.to_string(attrs)
  string.contains(s, "my_unit_test") |> should.be_true()
  string.contains(s, "passed") |> should.be_true()
}

pub fn test_runner_attrs_contains_duration_and_span_kind_test() {
  let attrs = test_runner_attrs("batch_test", "failed", 123)
  let s = json.to_string(attrs)
  string.contains(s, "123") |> should.be_true()
  string.contains(s, "test_runner") |> should.be_true()
}

pub fn agent_attrs_contains_agent_id_action_and_kind_test() {
  let attrs = agent_attrs("claude-001", "tool_call", "verification_page")
  let s = json.to_string(attrs)
  string.contains(s, "claude-001") |> should.be_true()
  string.contains(s, "tool_call") |> should.be_true()
  string.contains(s, "agent") |> should.be_true()
}

// =============================================================================
// Group 3: Observer enhanced verification (6 tests)
// =============================================================================

pub fn verify_all_pages_published_all_present_test() {
  // Seed the span log with one span per all 31 pages.
  let all_pages = [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
    Prajna, Agents, Holon, Config, Git, Database, Bridge, Smriti,
    PlanningDashboard, Integrity, Evolution, Biomorphic, HomeostasisPage,
    Bicameral, Singularity, ComponentDemo,
  ]
  let state =
    list.fold(all_pages, zenoh_test_observer.init([]), fn(acc, page) {
      zenoh_test_observer.record_span(
        acc,
        new_span(page, "el", Observe, json.null()),
      )
    })
  let results = zenoh_test_observer.verify_all_pages_published(state)
  list.length(results) |> should.equal(31)
  list.all(results, fn(r) { r.passed }) |> should.be_true()
}

pub fn verify_all_pages_published_missing_pages_fail_test() {
  // Only Dashboard and Planning published — remaining 29 of 31 pages must fail.
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_span(new_span(
      Dashboard,
      "el",
      Observe,
      json.null(),
    ))
    |> zenoh_test_observer.record_span(new_span(
      Planning,
      "el",
      Observe,
      json.null(),
    ))
  let results = zenoh_test_observer.verify_all_pages_published(state)
  let failed = list.filter(results, fn(r) { !r.passed })
  list.length(failed) |> should.equal(29)
}

pub fn verify_ooda_coverage_all_phases_pass_test() {
  // All four OODA phases present across spans — must pass.
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_span(new_span(
      Dashboard,
      "e1",
      Observe,
      json.null(),
    ))
    |> zenoh_test_observer.record_span(new_span(
      Planning,
      "e2",
      Orient,
      json.null(),
    ))
    |> zenoh_test_observer.record_span(new_span(
      Immune,
      "e3",
      Decide,
      json.null(),
    ))
    |> zenoh_test_observer.record_span(new_span(
      Knowledge,
      "e4",
      Act,
      json.null(),
    ))
  let result = zenoh_test_observer.verify_ooda_coverage(state)
  result.passed |> should.be_true()
  result.check_name |> should.equal("span_completeness")
}

pub fn verify_ooda_coverage_missing_phases_fail_test() {
  // Only Observe and Orient — Decide and Act absent.
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_span(new_span(
      Dashboard,
      "e1",
      Observe,
      json.null(),
    ))
    |> zenoh_test_observer.record_span(new_span(
      Planning,
      "e2",
      Orient,
      json.null(),
    ))
  let result = zenoh_test_observer.verify_ooda_coverage(state)
  result.passed |> should.be_false()
}

pub fn verify_control_state_spans_correlated_test() {
  // Control messages and non-empty span_log — must correlate (passed = true).
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_control(
      "indrajaal/control/container",
      "start",
    )
    |> zenoh_test_observer.record_span(new_span(
      Podman,
      "control_start",
      Decide,
      json.null(),
    ))
  let result = zenoh_test_observer.verify_control_state_spans(state)
  result.passed |> should.be_true()
  result.check_name |> should.equal("control_state_spans")
}

pub fn verify_mcp_relay_empty_received_vacuously_passes_test() {
  // Empty mcp_received list — no relay required, so passes.
  let state =
    zenoh_test_observer.init([])
    |> zenoh_test_observer.record_message(
      "indrajaal/otel/ops/mcp/tool_call",
      "{}",
    )
  let result = zenoh_test_observer.verify_mcp_relay(state, [])
  result.passed |> should.be_true()
  result.check_name |> should.equal("mcp_relay")
}

// =============================================================================
// Group 4: all_page_topics invariants (3 tests)
// =============================================================================

pub fn all_page_topics_returns_31_entries_test() {
  let topics = all_page_topics()
  list.length(topics) |> should.equal(31)
}

pub fn all_page_topics_all_start_with_prefix_test() {
  let prefix = "indrajaal/otel/ops/"
  let topics = all_page_topics()
  list.all(topics, fn(t) { string.starts_with(t, prefix) })
  |> should.be_true()
}

pub fn all_page_topics_no_duplicates_test() {
  let topics = all_page_topics()
  let unique =
    list.fold(topics, [], fn(acc, t) {
      case list.contains(acc, t) {
        True -> acc
        False -> [t, ..acc]
      }
    })
  list.length(unique) |> should.equal(list.length(topics))
}

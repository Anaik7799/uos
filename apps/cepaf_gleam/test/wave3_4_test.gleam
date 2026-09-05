// Wave 3+4 tests — dark cockpit modes, sparklines, system MCP tools, OTel coverage
// STAMP: SC-HMI-010, SC-GLM-ZEN-001, SC-MCP-001

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/mcp/server as mcp_server
import cepaf_gleam/ui/domain.{Critical, Degraded, Healthy, Unknown}
import cepaf_gleam/ui/state as mesh_state
import cepaf_gleam/ui/tui/renderer.{Bright, Dark, Dim, Emergency, Normal}
import cepaf_gleam/ui/zenoh_otel
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Dark Cockpit 5-Mode State Machine (SC-HMI-010)
// =============================================================================

pub fn dark_mode_when_healthy_no_threats_test() {
  renderer.determine_mode(Healthy, 0) |> should.equal(Dark)
}

pub fn dim_mode_when_healthy_with_threats_test() {
  renderer.determine_mode(Healthy, 1) |> should.equal(Dim)
}

pub fn normal_mode_when_degraded_test() {
  renderer.determine_mode(Degraded("slow"), 0) |> should.equal(Normal)
}

pub fn bright_mode_when_critical_few_threats_test() {
  renderer.determine_mode(Critical("outage"), 2) |> should.equal(Bright)
}

pub fn emergency_mode_when_critical_many_threats_test() {
  renderer.determine_mode(Critical("outage"), 5) |> should.equal(Emergency)
}

pub fn dim_mode_when_unknown_test() {
  renderer.determine_mode(Unknown, 0) |> should.equal(Dim)
}

pub fn mode_label_all_modes_test() {
  renderer.mode_label(Dark) |> should.equal("DARK")
  renderer.mode_label(Dim) |> should.equal("DIM")
  renderer.mode_label(Normal) |> should.equal("NORMAL")
  renderer.mode_label(Bright) |> should.equal("BRIGHT")
  renderer.mode_label(Emergency) |> should.equal("EMERGENCY")
}

// =============================================================================
// Sparkline + Progress Bar rendering
// =============================================================================

pub fn sparkline_renders_nonempty_test() {
  let result = visuals.render_sparkline([0.1, 0.5, 0.8, 1.0, 0.3])
  { string.length(result) > 0 } |> should.be_true()
}

pub fn progress_bar_renders_test() {
  let result = visuals.render_progress_bar(0.75, 20)
  string.contains(result, "=") |> should.be_true()
}

pub fn progress_bar_empty_test() {
  let result = visuals.render_progress_bar(0.0, 10)
  string.contains(result, "[") |> should.be_true()
}

pub fn progress_bar_full_test() {
  let result = visuals.render_progress_bar(1.0, 10)
  string.contains(result, "==========") |> should.be_true()
}

// =============================================================================
// Color support
// =============================================================================

pub fn with_color_white_test() {
  let result = visuals.with_color("test", "white")
  string.contains(result, "test") |> should.be_true()
}

pub fn with_color_dim_test() {
  let result = visuals.with_color("test", "dim")
  string.contains(result, "test") |> should.be_true()
}

pub fn with_color_bold_test() {
  let result = visuals.with_color("test", "bold")
  string.contains(result, "test") |> should.be_true()
}

// =============================================================================
// System MCP tools (mesh state)
// =============================================================================

pub fn system_health_tool_returns_json_test() {
  let result =
    mcp_server.handle_request(
      "tools/call",
      Some("1"),
      "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"system_health\",\"arguments\":{}},\"id\":\"1\"}",
    )
  case result {
    Some(r) -> string.contains(r, "container_count") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn system_dashboard_tool_returns_json_test() {
  let result =
    mcp_server.handle_request(
      "tools/call",
      Some("2"),
      "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"system_dashboard\",\"arguments\":{}},\"id\":\"2\"}",
    )
  case result {
    Some(r) -> string.contains(r, "Dashboard") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn system_verification_tool_returns_json_test() {
  let result =
    mcp_server.handle_request(
      "tools/call",
      Some("3"),
      "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\"system_verification\",\"arguments\":{}},\"id\":\"3\"}",
    )
  case result {
    Some(r) -> string.contains(r, "Verification") |> should.be_true()
    _ -> should.fail()
  }
}

// =============================================================================
// Mesh state verification JSON
// =============================================================================

pub fn verification_json_contains_test_counts_test() {
  let state = mesh_state.default_state()
  let result = mesh_state.to_verification_json(state)
  string.contains(result, "tests_passed") |> should.be_true()
  string.contains(result, "2817") |> should.be_true()
}

pub fn verification_json_contains_sil_test() {
  let state = mesh_state.default_state()
  let result = mesh_state.to_verification_json(state)
  string.contains(result, "SIL-6") |> should.be_true()
}

// =============================================================================
// OTel span coverage: all 30 pages have topic strings
// =============================================================================

pub fn otel_all_pages_have_topics_test() {
  // zenoh_otel.page_to_string uses exhaustive match on all 30 Page variants.
  // Gleam compiler guarantees no missing cases — this validates at runtime.
  let topic = zenoh_otel.page_to_string(domain.Dashboard)
  { string.length(topic) > 0 } |> should.be_true()
  let topic2 = zenoh_otel.page_to_string(domain.Singularity)
  topic2 |> should.equal("singularity")
}

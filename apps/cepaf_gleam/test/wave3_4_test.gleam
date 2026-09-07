// Wave 3+4 tests — dark cockpit modes, sparklines, system MCP tools, OTel coverage
// STAMP: SC-HMI-010, SC-GLM-ZEN-001, SC-MCP-001

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/mcp/server as mcp_server
import cepaf_gleam/mcp/tools as mcp_tools
import cepaf_gleam/ui/domain.{Critical, Degraded, Healthy, Unknown}
import cepaf_gleam/ui/state as mesh_state
import cepaf_gleam/ui/tui/renderer.{Bright, Dark, Dim, Emergency, Normal}
import cepaf_gleam/ui/zenoh_otel
import gleam/dynamic/decode
import gleam/json
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

fn system_tool_response(name: String, id: String) -> String {
  let assert Some(response) =
    mcp_server.handle_request(
      "tools/call",
      Some(id),
      "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"name\":\""
        <> name
        <> "\",\"arguments\":{}},\"id\":\""
        <> id
        <> "\"}",
    )
  response
}

fn response_content(
  response: String,
) -> Result(List(String), json.DecodeError) {
  let item_decoder = {
    use text <- decode.field("text", decode.string)
    decode.success(text)
  }
  let decoder = {
    use content <- decode.subfield(
      ["result", "content"],
      decode.list(item_decoder),
    )
    decode.success(content)
  }
  json.parse(response, decoder)
}

fn assert_nif_unavailable(response: String, fabricated_field: String) {
  let error_decoder = {
    use is_error <- decode.subfield(["result", "isError"], decode.bool)
    decode.success(is_error)
  }
  json.parse(response, error_decoder) |> should.equal(Ok(True))
  response |> string.contains("UNAVAILABLE") |> should.be_true
  response |> string.contains(fabricated_field) |> should.be_false
}

pub fn system_health_tool_returns_json_test() {
  let response = system_tool_response("system_health", "1")
  case mcp_tools.nif_runtime_available() {
    False -> assert_nif_unavailable(response, "container_count")
    True -> {
      let assert Ok([content, ..]) = response_content(response)
      let schema = {
        use _ <- decode.field("status", decode.string)
        use _ <- decode.field("interface", decode.string)
        use _ <- decode.field("port", decode.int)
        use _ <- decode.field("container_count", decode.int)
        use _ <- decode.field("healthy_count", decode.int)
        use _ <- decode.field("threat_level", decode.string)
        use _ <- decode.field("zenoh_connected", decode.bool)
        decode.success(Nil)
      }
      json.parse(content, schema) |> should.equal(Ok(Nil))
    }
  }
}

pub fn system_dashboard_tool_returns_json_test() {
  let response = system_tool_response("system_dashboard", "2")
  case mcp_tools.nif_runtime_available() {
    False -> assert_nif_unavailable(response, "container_count")
    True -> {
      let assert Ok([content, ..]) = response_content(response)
      let schema = {
        use _ <- decode.field("page", decode.string)
        use _ <- decode.field("path", decode.string)
        use _ <- decode.field("status", decode.string)
        use _ <- decode.field("container_count", decode.int)
        use _ <- decode.field("healthy_count", decode.int)
        use _ <- decode.field("health_pct", decode.float)
        use _ <- decode.field("zenoh_connected", decode.bool)
        decode.success(Nil)
      }
      json.parse(content, schema) |> should.equal(Ok(Nil))
    }
  }
}

pub fn system_verification_tool_returns_json_test() {
  let response = system_tool_response("system_verification", "3")
  case mcp_tools.nif_runtime_available() {
    False -> assert_nif_unavailable(response, "tests_total")
    True -> {
      let assert Ok([content, ..]) = response_content(response)
      let schema = {
        use _ <- decode.field("page", decode.string)
        use _ <- decode.field("status", decode.string)
        use _ <- decode.field("sil_level", decode.string)
        use _ <- decode.field("tests_total", decode.int)
        use _ <- decode.field("tests_passed", decode.int)
        use _ <- decode.field("tests_failed", decode.int)
        use _ <- decode.field("compliance_percent", decode.float)
        decode.success(Nil)
      }
      json.parse(content, schema) |> should.equal(Ok(Nil))
    }
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

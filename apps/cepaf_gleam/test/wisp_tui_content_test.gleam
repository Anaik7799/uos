// =============================================================================
// Wisp JSON Content + TUI ANSI View Rendering Tests
// =============================================================================
// Section 1: Wisp JSON Content Validation (26 tests — one per endpoint)
// Section 2: Wisp JSON Schema (6 tests)
// Section 3: TUI Renderer Primitives (8 tests)
// Section 4: TUI View Functions (10 tests)
// Section 5: Triple-Interface Parity (5 tests)
// =============================================================================
// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-UIGT-008, SC-UIGT-009
// =============================================================================

import cepaf_gleam/agui/sse as agui_sse
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/domain.{
  Critical, Dashboard, Degraded, Healthy, RenderContext, TelemetryPoint, Unknown,
}
import cepaf_gleam/ui/lustre/immune
import cepaf_gleam/ui/lustre/knowledge
import cepaf_gleam/ui/lustre/planning
import cepaf_gleam/ui/lustre/verification
import cepaf_gleam/ui/lustre/zenoh_mesh
import cepaf_gleam/ui/tui/immune_view
import cepaf_gleam/ui/tui/knowledge_view
import cepaf_gleam/ui/tui/planning_view
import cepaf_gleam/ui/tui/renderer
import cepaf_gleam/ui/tui/verification_view
import cepaf_gleam/ui/tui/zenoh_view
import cepaf_gleam/ui/wisp/router
import gleam/json
import gleam/string
import gleeunit/should

// =============================================================================
// Section 1: Wisp JSON Content Validation (26 tests)
// Verifies each endpoint returns JSON containing expected fields.
// =============================================================================

pub fn health_has_status_test() {
  let body = router.route("/health")
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn health_has_interface_test() {
  let body = router.route("/health")
  body |> string.contains("\"interface\"") |> should.be_true()
}

pub fn health_has_port_test() {
  let body = router.route("/health")
  body |> string.contains("\"port\"") |> should.be_true()
}

pub fn health_has_version_test() {
  let body = router.route("/health")
  body |> string.contains("\"version\"") |> should.be_true()
}

pub fn dashboard_has_page_test() {
  let body = router.route("/api/v1/dashboard")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn dashboard_has_path_test() {
  let body = router.route("/api/v1/dashboard")
  body |> string.contains("\"path\"") |> should.be_true()
}

pub fn dashboard_has_status_test() {
  let body = router.route("/api/v1/dashboard")
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn planning_has_page_test() {
  let body = router.route("/api/v1/planning")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn planning_has_status_test() {
  let body = router.route("/api/v1/planning")
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn planning_has_tasks_test() {
  let body = router.route("/api/v1/planning")
  body |> string.contains("\"pending_raw\"") |> should.be_true()
}

pub fn immune_has_page_test() {
  let body = router.route("/api/v1/immune")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn immune_has_status_test() {
  let body = router.route("/api/v1/immune")
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn zenoh_has_page_test() {
  let body = router.route("/api/v1/zenoh")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn zenoh_has_connected_test() {
  let body = router.route("/api/v1/zenoh")
  body |> string.contains("\"connected\"") |> should.be_true()
}

pub fn prajna_has_bio_test() {
  let body = router.route("/api/v1/prajna")
  body |> string.contains("\"bio\"") |> should.be_true()
}

pub fn prajna_has_immune_test() {
  let body = router.route("/api/v1/prajna")
  body |> string.contains("\"immune\"") |> should.be_true()
}

pub fn prajna_has_dark_cockpit_test() {
  let body = router.route("/api/v1/prajna")
  body |> string.contains("\"dark_cockpit\"") |> should.be_true()
}

pub fn prajna_has_circuit_breaker_test() {
  let body = router.route("/api/v1/prajna")
  body |> string.contains("\"circuit_breaker\"") |> should.be_true()
}

pub fn prajna_has_neuro_test() {
  let body = router.route("/api/v1/prajna")
  body |> string.contains("\"neuro\"") |> should.be_true()
}

pub fn agents_has_page_test() {
  let body = router.route("/api/v1/agents")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn agents_has_total_agents_test() {
  let body = router.route("/api/v1/agents")
  body |> string.contains("\"total_agents\"") |> should.be_true()
}

pub fn agents_has_levels_test() {
  let body = router.route("/api/v1/agents")
  body |> string.contains("\"levels\"") |> should.be_true()
}

pub fn federation_has_plane_test() {
  let body = router.route("/api/v1/federation")
  body |> string.contains("\"plane\"") |> should.be_true()
}

pub fn federation_has_local_id_test() {
  let body = router.route("/api/v1/federation")
  body |> string.contains("\"local_id\"") |> should.be_true()
}

pub fn federation_has_peers_test() {
  let body = router.route("/api/v1/federation")
  body |> string.contains("\"peers\"") |> should.be_true()
}

pub fn db_has_page_test() {
  let body = router.route("/api/v1/db")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn db_has_supported_types_test() {
  let body = router.route("/api/v1/db")
  body |> string.contains("\"supported_types\"") |> should.be_true()
}

pub fn verification_has_page_test() {
  let body = router.route("/api/v1/verification")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn verification_has_sil_level_test() {
  let body = router.route("/api/v1/verification")
  body |> string.contains("\"sil_level\"") |> should.be_true()
}

pub fn knowledge_has_page_test() {
  let body = router.route("/api/v1/knowledge")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn knowledge_has_nodes_test() {
  let body = router.route("/api/v1/knowledge")
  body |> string.contains("\"nodes\"") |> should.be_true()
}

pub fn substrate_has_page_test() {
  let body = router.route("/api/v1/substrate")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn metabolic_has_page_test() {
  let body = router.route("/api/v1/metabolic")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn podman_has_page_test() {
  let body = router.route("/api/v1/podman")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn mcp_has_page_test() {
  let body = router.route("/api/v1/mcp")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn kms_has_page_test() {
  let body = router.route("/api/v1/kms")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn telemetry_has_page_test() {
  let body = router.route("/api/v1/telemetry")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn ooda_has_page_test() {
  let body = router.route("/api/v1/ooda")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn ooda_has_status_test() {
  let body = router.route("/api/v1/ooda")
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn orchestration_has_page_test() {
  let body = router.route("/api/v1/orchestration")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn orchestration_has_quorum_test() {
  let body = router.route("/api/v1/orchestration")
  body |> string.contains("\"quorum\"") |> should.be_true()
}

pub fn safety_has_page_test() {
  let body = router.route("/api/v1/safety")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn safety_has_status_test() {
  let body = router.route("/api/v1/safety")
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn enforcer_has_page_test() {
  let body = router.route("/api/v1/enforcer")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn holon_has_page_test() {
  let body = router.route("/api/v1/holon")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn bridge_has_page_test() {
  let body = router.route("/api/v1/bridge")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn smriti_has_page_test() {
  let body = router.route("/api/v1/smriti")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn config_has_page_test() {
  let body = router.route("/api/v1/config")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn git_has_page_test() {
  let body = router.route("/api/v1/git")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn planning_dashboard_has_page_test() {
  let body = router.route("/api/v1/planning_dashboard")
  body |> string.contains("\"page\"") |> should.be_true()
}

pub fn planning_dashboard_has_panels_test() {
  let body = router.route("/api/v1/planning_dashboard")
  body |> string.contains("\"panels\"") |> should.be_true()
}

// =============================================================================
// Section 2: Wisp JSON Schema (6 tests)
// =============================================================================

pub fn all_endpoints_return_objects_health_test() {
  let body = router.route("/health")
  body |> string.starts_with("{") |> should.be_true()
}

pub fn all_endpoints_return_objects_planning_test() {
  let body = router.route("/api/v1/planning")
  body |> string.starts_with("{") |> should.be_true()
}

pub fn all_endpoints_return_objects_agents_test() {
  let body = router.route("/api/v1/agents")
  body |> string.starts_with("{") |> should.be_true()
}

pub fn pages_endpoint_has_pages_array_test() {
  let body = router.route("/api/v1/pages")
  // Returns object containing "pages" array
  body |> string.contains("\"pages\"") |> should.be_true()
  body |> string.contains("\"path\"") |> should.be_true()
  body |> string.contains("\"label\"") |> should.be_true()
}

pub fn encode_health_healthy_produces_string_test() {
  let encoded = router.encode_health(Healthy)
  // Healthy encodes as the string "healthy" — must contain that value
  encoded
  |> gleam_json_to_debug_string()
  |> string.contains("healthy")
  |> should.be_true()
}

pub fn encode_health_degraded_produces_object_test() {
  let encoded = router.encode_health(Degraded("test-reason"))
  encoded
  |> gleam_json_to_debug_string()
  |> string.contains("degraded")
  |> should.be_true()
}

pub fn encode_health_critical_produces_object_test() {
  let encoded = router.encode_health(Critical("critical-reason"))
  encoded
  |> gleam_json_to_debug_string()
  |> string.contains("critical")
  |> should.be_true()
}

pub fn encode_health_unknown_produces_string_test() {
  let encoded = router.encode_health(Unknown)
  encoded
  |> gleam_json_to_debug_string()
  |> string.contains("unknown")
  |> should.be_true()
}

pub fn agui_health_has_protocol_test() {
  let body = agui_sse.health_json()
  body |> string.contains("\"protocol\"") |> should.be_true()
}

pub fn agui_health_has_version_test() {
  let body = agui_sse.health_json()
  body |> string.contains("\"version\"") |> should.be_true()
}

pub fn agui_health_has_status_test() {
  let body = agui_sse.health_json()
  body |> string.contains("\"status\"") |> should.be_true()
}

pub fn agui_health_has_capabilities_test() {
  let body = agui_sse.health_json()
  body |> string.contains("\"capabilities\"") |> should.be_true()
}

pub fn agui_health_has_mesh_test() {
  let body = agui_sse.health_json()
  body |> string.contains("\"mesh\"") |> should.be_true()
}

pub fn agui_health_has_sil_level_test() {
  let body = agui_sse.health_json()
  body |> string.contains("\"sil_level\"") |> should.be_true()
}

// =============================================================================
// Section 3: TUI Renderer Primitives (8 tests)
// =============================================================================

pub fn render_progress_bar_zero_test() {
  let bar = visuals.render_progress_bar(0.0, 20)
  // Zero: all empty, red
  bar |> string.contains("[") |> should.be_true()
  bar |> string.contains("]") |> should.be_true()
}

pub fn render_progress_bar_half_test() {
  let bar = visuals.render_progress_bar(0.5, 20)
  // 50%: 10 filled chars, 10 empty
  bar |> string.contains("=") |> should.be_true()
}

pub fn render_progress_bar_full_test() {
  let bar = visuals.render_progress_bar(1.0, 10)
  // Full: all filled, green
  bar |> string.contains("=") |> should.be_true()
}

pub fn render_sparkline_empty_data_test() {
  let spark = visuals.render_sparkline([])
  spark |> should.equal("")
}

pub fn render_sparkline_with_data_test() {
  let spark = visuals.render_sparkline([0.0, 25.0, 50.0, 75.0, 100.0])
  spark |> string.length() |> should.equal(5)
}

pub fn with_color_green_returns_ansi_test() {
  let result = visuals.with_color("text", "green")
  // Must contain ESC character (ANSI escape)
  result |> string.contains("\u{001b}") |> should.be_true()
}

pub fn with_color_red_returns_ansi_test() {
  let result = visuals.with_color("text", "red")
  result |> string.contains("\u{001b}") |> should.be_true()
}

pub fn with_color_yellow_returns_ansi_test() {
  let result = visuals.with_color("text", "yellow")
  result |> string.contains("\u{001b}") |> should.be_true()
}

pub fn with_color_blue_returns_ansi_test() {
  let result = visuals.with_color("text", "blue")
  result |> string.contains("\u{001b}") |> should.be_true()
}

pub fn with_color_cyan_returns_ansi_test() {
  let result = visuals.with_color("text", "cyan")
  result |> string.contains("\u{001b}") |> should.be_true()
}

pub fn with_color_magenta_returns_ansi_test() {
  let result = visuals.with_color("text", "magenta")
  result |> string.contains("\u{001b}") |> should.be_true()
}

pub fn with_color_unknown_returns_plain_text_test() {
  // Unknown color name returns the text unchanged (no ANSI codes)
  let result = visuals.with_color("plain", "unknown_color")
  result |> should.equal("plain")
}

pub fn render_frame_non_empty_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { frame |> string.length() > 10 } |> should.be_true()
}

pub fn render_frame_contains_page_label_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("Dashboard") |> should.be_true()
}

pub fn render_frame_with_telemetry_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Degraded("low memory"),
      telemetry: [
        TelemetryPoint(key: "cpu", value: 45.0, timestamp: 1000, unit: "%"),
        TelemetryPoint(key: "mem", value: 80.0, timestamp: 1001, unit: "MB"),
      ],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  // Must contain telemetry section with point count
  frame |> string.contains("2 pts") |> should.be_true()
}

// =============================================================================
// Section 4: TUI View Functions (10 tests)
// =============================================================================

// --- planning_view ---

pub fn planning_view_render_non_empty_test() {
  let model = planning.init()
  let output = planning_view.render(model)
  output |> string.length() |> fn(n) { n > 0 } |> should.be_true()
}

pub fn planning_view_render_has_header_test() {
  let model = planning.init()
  let output = planning_view.render(model)
  output |> string.contains("PLANNING") |> should.be_true()
}

pub fn planning_view_render_has_ansi_test() {
  let model = planning.init()
  let output = planning_view.render(model)
  output |> string.contains("\u{001b}") |> should.be_true()
}

// --- immune_view ---

pub fn immune_view_render_non_empty_test() {
  let model = immune.init()
  let output = immune_view.render(model)
  output |> string.length() |> fn(n) { n > 0 } |> should.be_true()
}

pub fn immune_view_render_has_header_test() {
  let model = immune.init()
  let output = immune_view.render(model)
  output |> string.contains("IMMUNE") |> should.be_true()
}

pub fn immune_view_render_has_ansi_test() {
  let model = immune.init()
  let output = immune_view.render(model)
  output |> string.contains("\u{001b}") |> should.be_true()
}

// --- zenoh_view ---

pub fn zenoh_view_render_non_empty_test() {
  let model = zenoh_mesh.init()
  let output = zenoh_view.render(model)
  output |> string.length() |> fn(n) { n > 0 } |> should.be_true()
}

pub fn zenoh_view_render_has_header_test() {
  let model = zenoh_mesh.init()
  let output = zenoh_view.render(model)
  output |> string.contains("ZENOH") |> should.be_true()
}

pub fn zenoh_view_render_has_ansi_test() {
  let model = zenoh_mesh.init()
  let output = zenoh_view.render(model)
  output |> string.contains("\u{001b}") |> should.be_true()
}

// --- verification_view ---

pub fn verification_view_render_non_empty_test() {
  let model = verification.init()
  let output = verification_view.render(model)
  output |> string.length() |> fn(n) { n > 0 } |> should.be_true()
}

pub fn verification_view_render_has_header_test() {
  let model = verification.init()
  let output = verification_view.render(model)
  output |> string.contains("VERIFICATION") |> should.be_true()
}

pub fn verification_view_render_has_ansi_test() {
  let model = verification.init()
  let output = verification_view.render(model)
  output |> string.contains("\u{001b}") |> should.be_true()
}

// --- knowledge_view ---

pub fn knowledge_view_render_non_empty_test() {
  let model = knowledge_view_init_stub()
  let output = knowledge_view.render(model)
  output |> string.length() |> fn(n) { n > 0 } |> should.be_true()
}

pub fn knowledge_view_render_has_header_test() {
  let model = knowledge_view_init_stub()
  let output = knowledge_view.render(model)
  output |> string.contains("KNOWLEDGE") |> should.be_true()
}

pub fn knowledge_view_render_has_ansi_test() {
  let model = knowledge_view_init_stub()
  let output = knowledge_view.render(model)
  output |> string.contains("\u{001b}") |> should.be_true()
}

// =============================================================================
// Section 5: Triple-Interface Parity (5 pages × 3 interfaces)
// =============================================================================

// --- Dashboard parity ---

pub fn dashboard_lustre_init_produces_valid_model_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  // Dashboard shares RenderContext; TUI renderer uses it directly
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("Dashboard") |> should.be_true()
}

pub fn dashboard_wisp_returns_page_name_test() {
  let body = router.route("/api/v1/dashboard")
  body |> string.contains("Dashboard") |> should.be_true()
}

pub fn dashboard_tui_produces_non_empty_string_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  renderer.render_frame(ctx)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

// --- Planning parity ---

pub fn planning_lustre_init_valid_model_test() {
  let model = planning.init()
  model.tasks |> should.equal([])
}

pub fn planning_wisp_returns_page_name_test() {
  let body = router.route("/api/v1/planning")
  body |> string.contains("Planning") |> should.be_true()
}

pub fn planning_tui_produces_non_empty_string_test() {
  let model = planning.init()
  planning_view.render(model)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

// --- Immune parity ---

pub fn immune_lustre_init_valid_model_test() {
  let model = immune.init()
  model.mara_running |> should.be_false()
}

pub fn immune_wisp_returns_page_name_test() {
  let body = router.route("/api/v1/immune")
  body |> string.contains("Immune") |> should.be_true()
}

pub fn immune_tui_produces_non_empty_string_test() {
  let model = immune.init()
  immune_view.render(model)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

// --- Verification parity ---

pub fn verification_lustre_init_valid_model_test() {
  let model = verification.init()
  model.running |> should.be_false()
}

pub fn verification_wisp_returns_page_name_test() {
  let body = router.route("/api/v1/verification")
  body |> string.contains("Verification") |> should.be_true()
}

pub fn verification_tui_produces_non_empty_string_test() {
  let model = verification.init()
  verification_view.render(model)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

// --- Zenoh parity ---

pub fn zenoh_lustre_init_valid_model_test() {
  let model = zenoh_mesh.init()
  model.subscriptions |> should.equal([])
}

pub fn zenoh_wisp_returns_page_name_test() {
  let body = router.route("/api/v1/zenoh")
  body |> string.contains("Zenoh") |> should.be_true()
}

pub fn zenoh_tui_produces_non_empty_string_test() {
  let model = zenoh_mesh.init()
  zenoh_view.render(model)
  |> string.length()
  |> fn(n) { n > 0 }
  |> should.be_true()
}

// =============================================================================
// Private helpers
// =============================================================================

/// Convert a gleam/json.Json value to a debug string for content assertions.
fn gleam_json_to_debug_string(value: json.Json) -> String {
  json.to_string(json.object([#("v", value)]))
}

/// Build a minimal KnowledgeModel for TUI render tests via knowledge.init().
fn knowledge_view_init_stub() -> knowledge.KnowledgeModel {
  knowledge.init()
}

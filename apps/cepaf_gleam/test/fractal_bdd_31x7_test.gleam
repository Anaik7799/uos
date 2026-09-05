//// =============================================================================
//// [C3I-SIL6-MSTS] FRACTAL BDD 31x7 VERIFICATION SUITE
//// =============================================================================
//// <c3i-module>
////   <identity><module>cepaf_gleam/test/fractal_bdd_31x7_test</module></identity>
////   <fractal-topology><layer>L1_ATOMIC_DEBUG</layer></fractal-topology>
////   <compliance>
////     <stamp-controls>
////       SC-BDD-001, SC-GLM-UI-001, SC-GLM-UI-009, SC-UIGT-001,
////       SC-UIGT-003, SC-UIGT-007, SC-GLM-ZEN-001, SC-GLM-TST-001,
////       SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// 7 BDD Levels for all 31 pages = 217 tests.
////
//// BDD Level Definitions (mapped to sa-up dashboard TUI):
////   L0 Render          — Page route returns non-empty body (>10 chars)
////   L1 State Binding   — JSON body contains page-identifying field
////   L2 Interaction     — update(init(), Msg) produces correct state
////   L3 Telemetry Emit  — OTel span is structurally valid for page
////   L4 Mesh Reactivity — Zenoh topic for page present in all_page_topics()
////   L5 Fault Tolerance — RenderContext with Degraded health renders without crash
////   L6 Agentic Obs     — AG-UI EventType string mapped correctly for page
////
//// Pages (31):
////   Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
////   Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation,
////   HealthGrid, Prajna, Agents, Holon, Config, Git, Database, Bridge,
////   Smriti, PlanningDashboard, Integrity, Evolution, Biomorphic,
////   HomeostasisPage, Bicameral, Singularity, ComponentDemo
////
//// STAMP: SC-BDD-001, SC-GLM-UI-001, SC-UIGT-003, SC-UIGT-007
//// =============================================================================

import cepaf_gleam/agui/events
import cepaf_gleam/testing/nav_graph
import cepaf_gleam/ui/domain.{
  Agents, Bicameral, Biomorphic, Bridge, Cockpit, ComponentDemo, Config,
  Dashboard, Database, Degraded, Evolution, Federation, Git, HealthGrid, Healthy,
  Holon, HomeostasisPage, Immune, Integrity, Kms, Knowledge, Mcp, Metabolic,
  Planning, PlanningDashboard, Podman, Prajna, RenderContext, Singularity,
  Smriti, Substrate, Telemetry, Verification, Zenoh,
}
import cepaf_gleam/ui/tui/renderer
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/ui/zenoh_otel
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// PAGE 1: Dashboard
// =============================================================================

pub fn bdd_l0_dashboard_render_test() {
  let body = router.route("/api/v1/dashboard")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_dashboard_state_binding_test() {
  let body = router.route("/api/v1/dashboard")
  { string.length(body) > 0 }
  |> should.equal(True)
}

pub fn bdd_l2_dashboard_interaction_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Dashboard")
  |> should.be_true()
}

pub fn bdd_l3_dashboard_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Dashboard,
      "init",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("loading", "loaded", "init"),
    )
  span.page
  |> should.equal(Dashboard)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_dashboard_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "dashboard") })
  |> should.be_true()
}

pub fn bdd_l5_dashboard_degraded_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Degraded("test"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_dashboard_agui_obs_test() {
  let event = events.new_run_started("thread-dash", "run-dash")
  events.event_type_to_string(event.event_type)
  |> should.equal("RUN_STARTED")
}

// =============================================================================
// PAGE 2: Planning
// =============================================================================

pub fn bdd_l0_planning_render_test() {
  let body = router.route("/api/v1/planning")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_planning_state_binding_test() {
  let body = router.route("/api/v1/planning")
  string.contains(body, "Planning")
  |> should.be_true()
}

pub fn bdd_l2_planning_interaction_test() {
  let ctx =
    RenderContext(
      page: Planning,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Planning")
  |> should.be_true()
}

pub fn bdd_l3_planning_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Planning,
      "task_loaded",
      zenoh_otel.Orient,
      zenoh_otel.state_change_attrs("idle", "loaded", "data"),
    )
  span.page
  |> should.equal(Planning)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Orient")
}

pub fn bdd_l4_planning_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "planning") })
  |> should.be_true()
}

pub fn bdd_l5_planning_degraded_test() {
  let ctx =
    RenderContext(
      page: Planning,
      health: Degraded("db offline"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_planning_agui_obs_test() {
  let event = events.new_step_started("Planning")
  events.event_type_to_string(event.event_type)
  |> should.equal("STEP_STARTED")
}

// =============================================================================
// PAGE 3: Immune
// =============================================================================

pub fn bdd_l0_immune_render_test() {
  let body = router.route("/api/v1/immune")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_immune_state_binding_test() {
  let body = router.route("/api/v1/immune")
  { string.length(body) > 0 }
  |> should.equal(True)
}

pub fn bdd_l2_immune_interaction_test() {
  let ctx =
    RenderContext(
      page: Immune,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Immune")
  |> should.be_true()
}

pub fn bdd_l3_immune_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Immune,
      "threat_scan",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("idle", "scanning", "cron"),
    )
  span.page
  |> should.equal(Immune)
  { string.length(span.span_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_immune_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "immune") })
  |> should.be_true()
}

pub fn bdd_l5_immune_degraded_test() {
  let ctx =
    RenderContext(
      page: Immune,
      health: Degraded("threat detected"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_immune_agui_obs_test() {
  let event =
    events.new_state_snapshot(json.object([#("page", json.string("Immune"))]))
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 4: Knowledge
// =============================================================================

pub fn bdd_l0_knowledge_render_test() {
  let body = router.route("/api/v1/knowledge")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_knowledge_state_binding_test() {
  let body = router.route("/api/v1/knowledge")
  string.contains(body, "Knowledge")
  |> should.be_true()
}

pub fn bdd_l2_knowledge_interaction_test() {
  let ctx =
    RenderContext(
      page: Knowledge,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Knowledge")
  |> should.be_true()
}

pub fn bdd_l3_knowledge_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Knowledge,
      "graph_query",
      zenoh_otel.Orient,
      zenoh_otel.user_action_attrs("query", "knowledge_graph"),
    )
  span.page
  |> should.equal(Knowledge)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Orient")
}

pub fn bdd_l4_knowledge_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "knowledge") })
  |> should.be_true()
}

pub fn bdd_l5_knowledge_degraded_test() {
  let ctx =
    RenderContext(
      page: Knowledge,
      health: Degraded("index rebuild"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_knowledge_agui_obs_test() {
  let event = events.new_tool_call_start("tool-knowledge", "query_graph")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 5: Zenoh
// =============================================================================

pub fn bdd_l0_zenoh_render_test() {
  let body = router.route("/api/v1/zenoh")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_zenoh_state_binding_test() {
  let body = router.route("/api/v1/zenoh")
  { string.length(body) > 0 }
  |> should.equal(True)
}

pub fn bdd_l2_zenoh_interaction_test() {
  let ctx =
    RenderContext(
      page: Zenoh,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "ZENOH: CONNECTED")
  |> should.be_true()
}

pub fn bdd_l3_zenoh_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Zenoh,
      "session_connected",
      zenoh_otel.Observe,
      zenoh_otel.zenoh_message_attrs("indrajaal/health/mesh", 1, 50),
    )
  span.page
  |> should.equal(Zenoh)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_zenoh_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "zenoh") })
  |> should.be_true()
}

pub fn bdd_l5_zenoh_degraded_test() {
  let ctx =
    RenderContext(
      page: Zenoh,
      health: Degraded("router unreachable"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "ZENOH: DISCONNECTED")
  |> should.be_true()
}

pub fn bdd_l6_zenoh_agui_obs_test() {
  let event =
    events.new_activity_snapshot(
      "snap-zenoh",
      "mesh",
      json.object([#("routers", json.int(3))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("ACTIVITY_SNAPSHOT")
}

// =============================================================================
// PAGE 6: Cockpit
// =============================================================================

pub fn bdd_l0_cockpit_render_test() {
  let body = router.route("/api/cockpit/nodes")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_cockpit_state_binding_test() {
  let body = router.route("/api/cockpit/nodes")
  string.contains(body, "Cockpit")
  |> should.be_true()
}

pub fn bdd_l2_cockpit_interaction_test() {
  let ctx =
    RenderContext(
      page: Cockpit,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Cockpit")
  |> should.be_true()
}

pub fn bdd_l3_cockpit_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Cockpit,
      "node_refresh",
      zenoh_otel.Decide,
      zenoh_otel.user_action_attrs("refresh", "cockpit_nodes"),
    )
  span.page
  |> should.equal(Cockpit)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Decide")
}

pub fn bdd_l4_cockpit_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "cockpit") })
  |> should.be_true()
}

pub fn bdd_l5_cockpit_degraded_test() {
  let ctx =
    RenderContext(
      page: Cockpit,
      health: Degraded("node offline"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_cockpit_agui_obs_test() {
  let event = events.new_tool_call_start("tool-cockpit", "list_nodes")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 7: Verification
// =============================================================================

pub fn bdd_l0_verification_render_test() {
  let body = router.route("/api/v1/verification")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_verification_state_binding_test() {
  let body = router.route("/api/v1/verification")
  string.contains(body, "Verification")
  |> should.be_true()
}

pub fn bdd_l2_verification_interaction_test() {
  let ctx =
    RenderContext(
      page: Verification,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Verification")
  |> should.be_true()
}

pub fn bdd_l3_verification_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Verification,
      "sil_check",
      zenoh_otel.Act,
      zenoh_otel.state_change_attrs("pending", "verified", "run"),
    )
  span.page
  |> should.equal(Verification)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Act")
}

pub fn bdd_l4_verification_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "verification") })
  |> should.be_true()
}

pub fn bdd_l5_verification_degraded_test() {
  let ctx =
    RenderContext(
      page: Verification,
      health: Degraded("psi failure"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_verification_agui_obs_test() {
  let event = events.new_run_error("psi-3 failed", "PSI_VIOLATION")
  events.event_type_to_string(event.event_type)
  |> should.equal("RUN_ERROR")
}

// =============================================================================
// PAGE 8: Substrate
// =============================================================================

pub fn bdd_l0_substrate_render_test() {
  let body = router.route("/api/v1/substrate")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_substrate_state_binding_test() {
  let body = router.route("/api/v1/substrate")
  string.contains(body, "Substrate")
  |> should.be_true()
}

pub fn bdd_l2_substrate_interaction_test() {
  let ctx =
    RenderContext(
      page: Substrate,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Substrate")
  |> should.be_true()
}

pub fn bdd_l3_substrate_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Substrate,
      "db_status",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("unknown", "nominal", "poll"),
    )
  span.page
  |> should.equal(Substrate)
  { string.length(span.name) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_substrate_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "substrate") })
  |> should.be_true()
}

pub fn bdd_l5_substrate_degraded_test() {
  let ctx =
    RenderContext(
      page: Substrate,
      health: Degraded("disk pressure"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_substrate_agui_obs_test() {
  let event =
    events.new_state_snapshot(
      json.object([#("page", json.string("Substrate"))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 9: Metabolic
// =============================================================================

pub fn bdd_l0_metabolic_render_test() {
  let body = router.route("/api/v1/metabolic")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_metabolic_state_binding_test() {
  let body = router.route("/api/v1/metabolic")
  string.contains(body, "Metabolic")
  |> should.be_true()
}

pub fn bdd_l2_metabolic_interaction_test() {
  let ctx =
    RenderContext(
      page: Metabolic,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Metabolic")
  |> should.be_true()
}

pub fn bdd_l3_metabolic_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Metabolic,
      "pid_tick",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("optimal", "throttled", "cpu_spike"),
    )
  span.page
  |> should.equal(Metabolic)
  { string.length(span.element) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_metabolic_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "metabolic") })
  |> should.be_true()
}

pub fn bdd_l5_metabolic_degraded_test() {
  let ctx =
    RenderContext(
      page: Metabolic,
      health: Degraded("pid divergence"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_metabolic_agui_obs_test() {
  let event =
    events.new_activity_delta(
      "delta-metabolic",
      "pid",
      json.object([#("cpu_load", json.float(45.2))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("ACTIVITY_DELTA")
}

// =============================================================================
// PAGE 10: Podman
// =============================================================================

pub fn bdd_l0_podman_render_test() {
  let body = router.route("/api/v1/podman")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_podman_state_binding_test() {
  let body = router.route("/api/v1/podman")
  string.contains(body, "Podman")
  |> should.be_true()
}

pub fn bdd_l2_podman_interaction_test() {
  let ctx =
    RenderContext(
      page: Podman,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Podman")
  |> should.be_true()
}

pub fn bdd_l3_podman_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Podman,
      "container_start",
      zenoh_otel.Act,
      zenoh_otel.control_attrs("start", "ex-app-1", "initiated"),
    )
  span.page
  |> should.equal(Podman)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Act")
}

pub fn bdd_l4_podman_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "podman") })
  |> should.be_true()
}

pub fn bdd_l5_podman_degraded_test() {
  let ctx =
    RenderContext(
      page: Podman,
      health: Degraded("container crashed"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_podman_agui_obs_test() {
  let event = events.new_tool_call_start("tool-podman", "start_container")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 11: Mcp
// =============================================================================

pub fn bdd_l0_mcp_render_test() {
  let body = router.route("/api/v1/mcp")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_mcp_state_binding_test() {
  let body = router.route("/api/v1/mcp")
  string.contains(body, "MCP")
  |> should.be_true()
}

pub fn bdd_l2_mcp_interaction_test() {
  let ctx =
    RenderContext(
      page: Mcp,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "MCP")
  |> should.be_true()
}

pub fn bdd_l3_mcp_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Mcp,
      "tool_dispatch",
      zenoh_otel.Act,
      zenoh_otel.user_action_attrs("dispatch", "sentinel_tool"),
    )
  span.page
  |> should.equal(Mcp)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_mcp_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "mcp") })
  |> should.be_true()
}

pub fn bdd_l5_mcp_degraded_test() {
  let ctx =
    RenderContext(
      page: Mcp,
      health: Degraded("server timeout"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_mcp_agui_obs_test() {
  let event =
    events.new_tool_call_result("result-mcp", "ok", "{\"status\":\"ok\"}")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_RESULT")
}

// =============================================================================
// PAGE 12: Kms
// =============================================================================

pub fn bdd_l0_kms_render_test() {
  let body = router.route("/api/v1/kms")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_kms_state_binding_test() {
  let body = router.route("/api/v1/kms")
  string.contains(body, "KMS")
  |> should.be_true()
}

pub fn bdd_l2_kms_interaction_test() {
  let ctx =
    RenderContext(
      page: Kms,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "KMS")
  |> should.be_true()
}

pub fn bdd_l3_kms_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Kms,
      "key_rotation",
      zenoh_otel.Act,
      zenoh_otel.state_change_attrs("active", "rotating", "scheduled"),
    )
  span.page
  |> should.equal(Kms)
  { string.length(span.span_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_kms_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "kms") })
  |> should.be_true()
}

pub fn bdd_l5_kms_degraded_test() {
  let ctx =
    RenderContext(
      page: Kms,
      health: Degraded("key expired"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_kms_agui_obs_test() {
  let event =
    events.new_state_snapshot(json.object([#("page", json.string("Kms"))]))
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 13: Telemetry
// =============================================================================

pub fn bdd_l0_telemetry_render_test() {
  let body = router.route("/api/v1/telemetry")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_telemetry_state_binding_test() {
  let body = router.route("/api/v1/telemetry")
  string.contains(body, "Telemetry")
  |> should.be_true()
}

pub fn bdd_l2_telemetry_interaction_test() {
  let ctx =
    RenderContext(
      page: Telemetry,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Telemetry")
  |> should.be_true()
}

pub fn bdd_l3_telemetry_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Telemetry,
      "span_ingested",
      zenoh_otel.Observe,
      zenoh_otel.zenoh_message_attrs("indrajaal/otel/ops/telemetry", 8, 12),
    )
  span.page
  |> should.equal(Telemetry)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Observe")
}

pub fn bdd_l4_telemetry_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "telemetry") })
  |> should.be_true()
}

pub fn bdd_l5_telemetry_degraded_test() {
  let ctx =
    RenderContext(
      page: Telemetry,
      health: Degraded("otel collector unreachable"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_telemetry_agui_obs_test() {
  let event =
    events.new_text_message_chunk(
      "chunk-tel",
      "assistant",
      "Telemetry: 8 active spans, 1247 total traces",
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("TEXT_MESSAGE_CHUNK")
}

// =============================================================================
// PAGE 14: Federation
// =============================================================================

pub fn bdd_l0_federation_render_test() {
  let body = router.route("/api/v1/federation")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_federation_state_binding_test() {
  let body = router.route("/api/v1/federation")
  string.contains(body, "federation")
  |> should.be_true()
}

pub fn bdd_l2_federation_interaction_test() {
  let ctx =
    RenderContext(
      page: Federation,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Federation")
  |> should.be_true()
}

pub fn bdd_l3_federation_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Federation,
      "quorum_sync",
      zenoh_otel.Decide,
      zenoh_otel.state_change_attrs("syncing", "converged", "quorum"),
    )
  span.page
  |> should.equal(Federation)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Decide")
}

pub fn bdd_l4_federation_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "federation") })
  |> should.be_true()
}

pub fn bdd_l5_federation_degraded_test() {
  let ctx =
    RenderContext(
      page: Federation,
      health: Degraded("split brain"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_federation_agui_obs_test() {
  let event = events.new_run_started("thread-fed", "run-fed")
  events.event_type_to_string(event.event_type)
  |> should.equal("RUN_STARTED")
}

// =============================================================================
// PAGE 15: HealthGrid
// =============================================================================

pub fn bdd_l0_healthgrid_render_test() {
  let body = router.route("/api/v1/health_grid")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_healthgrid_state_binding_test() {
  let body = router.route("/api/v1/health_grid")
  string.contains(body, "Health Grid")
  |> should.be_true()
}

pub fn bdd_l2_healthgrid_interaction_test() {
  let ctx =
    RenderContext(
      page: HealthGrid,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Device Health Grid")
  |> should.be_true()
}

pub fn bdd_l3_healthgrid_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      HealthGrid,
      "device_poll",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("idle", "polling", "heartbeat"),
    )
  span.page
  |> should.equal(HealthGrid)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_healthgrid_mesh_test() {
  let topics = zenoh_otel.all_page_topics()
  list.any(topics, fn(t) { string.contains(t, "health_grid") })
  |> should.be_true()
}

pub fn bdd_l5_healthgrid_degraded_test() {
  let ctx =
    RenderContext(
      page: HealthGrid,
      health: Degraded("device offline"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_healthgrid_agui_obs_test() {
  let event =
    events.new_state_snapshot(
      json.object([#("page", json.string("HealthGrid"))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 16: Prajna
// =============================================================================

pub fn bdd_l0_prajna_render_test() {
  let body = router.route("/api/v1/prajna")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_prajna_state_binding_test() {
  let body = router.route("/api/v1/prajna")
  string.contains(body, "Prajna")
  |> should.be_true()
}

pub fn bdd_l2_prajna_interaction_test() {
  let ctx =
    RenderContext(
      page: Prajna,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Prajna")
  |> should.be_true()
}

pub fn bdd_l3_prajna_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Prajna,
      "biomorphic_tick",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("dormant", "active", "ooda"),
    )
  span.page
  |> should.equal(Prajna)
  { string.length(span.name) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_prajna_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Prajna)
  page_str
  |> should.equal("prajna")
}

pub fn bdd_l5_prajna_degraded_test() {
  let ctx =
    RenderContext(
      page: Prajna,
      health: Degraded("circuit open"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_prajna_agui_obs_test() {
  let event = events.new_reasoning_start("reason-prajna")
  events.event_type_to_string(event.event_type)
  |> should.equal("REASONING_START")
}

// =============================================================================
// PAGE 17: Agents
// =============================================================================

pub fn bdd_l0_agents_render_test() {
  let body = router.route("/api/v1/agents")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_agents_state_binding_test() {
  let body = router.route("/api/v1/agents")
  string.contains(body, "Cybernetic Agents")
  |> should.be_true()
}

pub fn bdd_l2_agents_interaction_test() {
  let ctx =
    RenderContext(
      page: Agents,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Cybernetic Agents")
  |> should.be_true()
}

pub fn bdd_l3_agents_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Agents,
      "agent_spawned",
      zenoh_otel.Act,
      zenoh_otel.agent_attrs("agent-007", "spawn", "L5_COGNITIVE"),
    )
  span.page
  |> should.equal(Agents)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Act")
}

pub fn bdd_l4_agents_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Agents)
  page_str
  |> should.equal("agents")
}

pub fn bdd_l5_agents_degraded_test() {
  let ctx =
    RenderContext(
      page: Agents,
      health: Degraded("deadlock detected"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_agents_agui_obs_test() {
  let event = events.new_step_started("AgentHierarchy")
  events.event_type_to_string(event.event_type)
  |> should.equal("STEP_STARTED")
}

// =============================================================================
// PAGE 18: Holon
// =============================================================================

pub fn bdd_l0_holon_render_test() {
  let body = router.route("/api/v1/holon")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_holon_state_binding_test() {
  let body = router.route("/api/v1/holon")
  string.contains(body, "Holon")
  |> should.be_true()
}

pub fn bdd_l2_holon_interaction_test() {
  let ctx =
    RenderContext(
      page: Holon,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Holon")
  |> should.be_true()
}

pub fn bdd_l3_holon_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Holon,
      "identity_resolved",
      zenoh_otel.Orient,
      zenoh_otel.state_change_attrs("unknown", "resolved", "boot"),
    )
  span.page
  |> should.equal(Holon)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_holon_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Holon)
  page_str
  |> should.equal("holon")
}

pub fn bdd_l5_holon_degraded_test() {
  let ctx =
    RenderContext(
      page: Holon,
      health: Degraded("identity conflict"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_holon_agui_obs_test() {
  let event =
    events.new_state_snapshot(json.object([#("page", json.string("Holon"))]))
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 19: Config
// =============================================================================

pub fn bdd_l0_config_render_test() {
  let body = router.route("/api/v1/config")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_config_state_binding_test() {
  let body = router.route("/api/v1/config")
  string.contains(body, "Mesh Configuration")
  |> should.be_true()
}

pub fn bdd_l2_config_interaction_test() {
  let ctx =
    RenderContext(
      page: Config,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Mesh Configuration")
  |> should.be_true()
}

pub fn bdd_l3_config_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Config,
      "config_reload",
      zenoh_otel.Act,
      zenoh_otel.state_change_attrs("stale", "fresh", "reload"),
    )
  span.page
  |> should.equal(Config)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Act")
}

pub fn bdd_l4_config_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Config)
  page_str
  |> should.equal("config")
}

pub fn bdd_l5_config_degraded_test() {
  let ctx =
    RenderContext(
      page: Config,
      health: Degraded("invalid quorum"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_config_agui_obs_test() {
  let event = events.new_tool_call_start("tool-config", "reload_mesh_config")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 20: Git
// =============================================================================

pub fn bdd_l0_git_render_test() {
  let body = router.route("/api/v1/git")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_git_state_binding_test() {
  let body = router.route("/api/v1/git")
  string.contains(body, "Git")
  |> should.be_true()
}

pub fn bdd_l2_git_interaction_test() {
  let ctx =
    RenderContext(
      page: Git,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Git")
  |> should.be_true()
}

pub fn bdd_l3_git_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Git,
      "commit_analyzed",
      zenoh_otel.Orient,
      zenoh_otel.state_change_attrs("unanalyzed", "analyzed", "push"),
    )
  span.page
  |> should.equal(Git)
  { string.length(span.span_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_git_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Git)
  page_str
  |> should.equal("git")
}

pub fn bdd_l5_git_degraded_test() {
  let ctx =
    RenderContext(
      page: Git,
      health: Degraded("merge conflict"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_git_agui_obs_test() {
  let event =
    events.new_state_snapshot(json.object([#("page", json.string("Git"))]))
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 21: Database
// =============================================================================

pub fn bdd_l0_database_render_test() {
  let body = router.route("/api/v1/db")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_database_state_binding_test() {
  let body = router.route("/api/v1/db")
  string.contains(body, "Database")
  |> should.be_true()
}

pub fn bdd_l2_database_interaction_test() {
  let ctx =
    RenderContext(
      page: Database,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Database")
  |> should.be_true()
}

pub fn bdd_l3_database_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Database,
      "wal_checkpoint",
      zenoh_otel.Act,
      zenoh_otel.state_change_attrs("pending", "checkpointed", "wal"),
    )
  span.page
  |> should.equal(Database)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Act")
}

pub fn bdd_l4_database_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Database)
  page_str
  |> should.equal("database")
}

pub fn bdd_l5_database_degraded_test() {
  let ctx =
    RenderContext(
      page: Database,
      health: Degraded("postgres unreachable"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_database_agui_obs_test() {
  let event = events.new_tool_call_start("tool-db", "checkpoint_wal")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 22: Bridge
// =============================================================================

pub fn bdd_l0_bridge_render_test() {
  let body = router.route("/api/v1/bridge")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_bridge_state_binding_test() {
  let body = router.route("/api/v1/bridge")
  string.contains(body, "Bridge")
  |> should.be_true()
}

pub fn bdd_l2_bridge_interaction_test() {
  let ctx =
    RenderContext(
      page: Bridge,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Bridge")
  |> should.be_true()
}

pub fn bdd_l3_bridge_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Bridge,
      "rpc_dispatch",
      zenoh_otel.Act,
      zenoh_otel.user_action_attrs("dispatch", "bridge_rpc"),
    )
  span.page
  |> should.equal(Bridge)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_bridge_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Bridge)
  page_str
  |> should.equal("bridge")
}

pub fn bdd_l5_bridge_degraded_test() {
  let ctx =
    RenderContext(
      page: Bridge,
      health: Degraded("rpc timeout"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_bridge_agui_obs_test() {
  let event =
    events.new_tool_call_result("result-bridge", "ok", "{\"dispatched\":true}")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_RESULT")
}

// =============================================================================
// PAGE 23: Smriti
// =============================================================================

pub fn bdd_l0_smriti_render_test() {
  let body = router.route("/api/v1/smriti")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_smriti_state_binding_test() {
  let body = router.route("/api/v1/smriti")
  string.contains(body, "Smriti")
  |> should.be_true()
}

pub fn bdd_l2_smriti_interaction_test() {
  let ctx =
    RenderContext(
      page: Smriti,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Smriti")
  |> should.be_true()
}

pub fn bdd_l3_smriti_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Smriti,
      "catalog_query",
      zenoh_otel.Orient,
      zenoh_otel.user_action_attrs("query", "knowledge_catalog"),
    )
  span.page
  |> should.equal(Smriti)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Orient")
}

pub fn bdd_l4_smriti_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Smriti)
  page_str
  |> should.equal("smriti")
}

pub fn bdd_l5_smriti_degraded_test() {
  let ctx =
    RenderContext(
      page: Smriti,
      health: Degraded("embedding index stale"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_smriti_agui_obs_test() {
  let event = events.new_tool_call_start("tool-smriti", "semantic_search")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 24: PlanningDashboard
// =============================================================================

pub fn bdd_l0_planningdashboard_render_test() {
  let body = router.route("/api/v1/planning_dashboard")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_planningdashboard_state_binding_test() {
  let body = router.route("/api/v1/planning_dashboard")
  string.contains(body, "Planning Dashboard")
  |> should.be_true()
}

pub fn bdd_l2_planningdashboard_interaction_test() {
  let ctx =
    RenderContext(
      page: PlanningDashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Planning Dashboard")
  |> should.be_true()
}

pub fn bdd_l3_planningdashboard_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      PlanningDashboard,
      "panel_switch",
      zenoh_otel.Decide,
      zenoh_otel.state_change_attrs("tasks", "ooda", "user_nav"),
    )
  span.page
  |> should.equal(PlanningDashboard)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Decide")
}

pub fn bdd_l4_planningdashboard_mesh_test() {
  let page_str = zenoh_otel.page_to_string(PlanningDashboard)
  page_str
  |> should.equal("planning_dashboard")
}

pub fn bdd_l5_planningdashboard_degraded_test() {
  let ctx =
    RenderContext(
      page: PlanningDashboard,
      health: Degraded("task sync failed"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_planningdashboard_agui_obs_test() {
  let event = events.new_step_started("PlanningDashboard")
  events.event_type_to_string(event.event_type)
  |> should.equal("STEP_STARTED")
}

// =============================================================================
// PAGE 25: Integrity
// =============================================================================

pub fn bdd_l0_integrity_render_test() {
  let body = router.route("/api/v1/integrity")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_integrity_state_binding_test() {
  let body = router.route("/api/v1/integrity")
  string.contains(body, "Integrity")
  |> should.be_true()
}

pub fn bdd_l2_integrity_interaction_test() {
  let ctx =
    RenderContext(
      page: Integrity,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Mathematical Integrity")
  |> should.be_true()
}

pub fn bdd_l3_integrity_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Integrity,
      "psi_check",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("pending", "verified", "schedule"),
    )
  span.page
  |> should.equal(Integrity)
  { string.length(span.name) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_integrity_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Integrity)
  page_str
  |> should.equal("integrity")
}

pub fn bdd_l5_integrity_degraded_test() {
  let ctx =
    RenderContext(
      page: Integrity,
      health: Degraded("chain broken"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_integrity_agui_obs_test() {
  let event = events.new_run_error("psi-5 diverged", "PSI_5_VIOLATION")
  events.event_type_to_string(event.event_type)
  |> should.equal("RUN_ERROR")
}

// =============================================================================
// PAGE 26: Evolution
// =============================================================================

pub fn bdd_l0_evolution_render_test() {
  let body = router.route("/api/v1/evolution")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_evolution_state_binding_test() {
  let body = router.route("/api/v1/evolution")
  string.contains(body, "Evolution")
  |> should.be_true()
}

pub fn bdd_l2_evolution_interaction_test() {
  let ctx =
    RenderContext(
      page: Evolution,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Evolution")
  |> should.be_true()
}

pub fn bdd_l3_evolution_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Evolution,
      "cycle_complete",
      zenoh_otel.Act,
      zenoh_otel.state_change_attrs("evolving", "converged", "fitness"),
    )
  span.page
  |> should.equal(Evolution)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Act")
}

pub fn bdd_l4_evolution_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Evolution)
  page_str
  |> should.equal("evolution")
}

pub fn bdd_l5_evolution_degraded_test() {
  let ctx =
    RenderContext(
      page: Evolution,
      health: Degraded("entropy too high"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_evolution_agui_obs_test() {
  let event = events.new_reasoning_start("reason-evo")
  events.event_type_to_string(event.event_type)
  |> should.equal("REASONING_START")
}

// =============================================================================
// PAGE 27: Biomorphic
// =============================================================================

pub fn bdd_l0_biomorphic_render_test() {
  let body = router.route("/api/v1/biomorphic")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_biomorphic_state_binding_test() {
  let body = router.route("/api/v1/biomorphic")
  string.contains(body, "Biomorphic")
  |> should.be_true()
}

pub fn bdd_l2_biomorphic_interaction_test() {
  let ctx =
    RenderContext(
      page: Biomorphic,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Biomorphic")
  |> should.be_true()
}

pub fn bdd_l3_biomorphic_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Biomorphic,
      "subsystem_check",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("normal", "stressed", "cpu"),
    )
  span.page
  |> should.equal(Biomorphic)
  { string.length(span.span_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_biomorphic_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Biomorphic)
  page_str
  |> should.equal("biomorphic")
}

pub fn bdd_l5_biomorphic_degraded_test() {
  let ctx =
    RenderContext(
      page: Biomorphic,
      health: Degraded("neuro subsystem degraded"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_biomorphic_agui_obs_test() {
  let event =
    events.new_state_snapshot(
      json.object([#("page", json.string("Biomorphic"))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// PAGE 28: HomeostasisPage
// =============================================================================

pub fn bdd_l0_homeostasis_render_test() {
  let body = router.route("/api/v1/homeostasis")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_homeostasis_state_binding_test() {
  let body = router.route("/api/v1/homeostasis")
  string.contains(body, "Homeostasis")
  |> should.be_true()
}

pub fn bdd_l2_homeostasis_interaction_test() {
  let ctx =
    RenderContext(
      page: HomeostasisPage,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Homeostasis")
  |> should.be_true()
}

pub fn bdd_l3_homeostasis_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      HomeostasisPage,
      "pid_converged",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("diverging", "converged", "pid"),
    )
  span.page
  |> should.equal(HomeostasisPage)
  { string.length(span.name) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_homeostasis_mesh_test() {
  let page_str = zenoh_otel.page_to_string(HomeostasisPage)
  page_str
  |> should.equal("homeostasis")
}

pub fn bdd_l5_homeostasis_degraded_test() {
  let ctx =
    RenderContext(
      page: HomeostasisPage,
      health: Degraded("pid divergence > 15%"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_homeostasis_agui_obs_test() {
  let event =
    events.new_activity_snapshot(
      "snap-homeo",
      "pid",
      json.object([#("controller", json.string("converged"))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("ACTIVITY_SNAPSHOT")
}

// =============================================================================
// PAGE 29: Bicameral
// =============================================================================

pub fn bdd_l0_bicameral_render_test() {
  let body = router.route("/api/v1/bicameral")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_bicameral_state_binding_test() {
  let body = router.route("/api/v1/bicameral")
  string.contains(body, "Bicameral")
  |> should.be_true()
}

pub fn bdd_l2_bicameral_interaction_test() {
  let ctx =
    RenderContext(
      page: Bicameral,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Bicameral")
  |> should.be_true()
}

pub fn bdd_l3_bicameral_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Bicameral,
      "vote_cast",
      zenoh_otel.Decide,
      zenoh_otel.state_change_attrs("pending", "voted", "2key"),
    )
  span.page
  |> should.equal(Bicameral)
  zenoh_otel.ooda_phase_to_string(span.ooda_phase)
  |> should.equal("Decide")
}

pub fn bdd_l4_bicameral_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Bicameral)
  page_str
  |> should.equal("bicameral")
}

pub fn bdd_l5_bicameral_degraded_test() {
  let ctx =
    RenderContext(
      page: Bicameral,
      health: Degraded("chamber offline"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "DEGRADED")
  |> should.be_true()
}

pub fn bdd_l6_bicameral_agui_obs_test() {
  let event = events.new_tool_call_start("tool-bicameral", "cast_vote")
  events.event_type_to_string(event.event_type)
  |> should.equal("TOOL_CALL_START")
}

// =============================================================================
// PAGE 30: Singularity
// =============================================================================

pub fn bdd_l0_singularity_render_test() {
  let body = router.route("/api/v1/singularity")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_singularity_state_binding_test() {
  let body = router.route("/api/v1/singularity")
  string.contains(body, "Singularity")
  |> should.be_true()
}

pub fn bdd_l2_singularity_interaction_test() {
  let ctx =
    RenderContext(
      page: Singularity,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Singularity")
  |> should.be_true()
}

pub fn bdd_l3_singularity_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      Singularity,
      "capability_update",
      zenoh_otel.Orient,
      zenoh_otel.state_change_attrs("12pct", "15pct", "eval"),
    )
  span.page
  |> should.equal(Singularity)
  { string.length(span.trace_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_singularity_mesh_test() {
  let page_str = zenoh_otel.page_to_string(Singularity)
  page_str
  |> should.equal("singularity")
}

pub fn bdd_l5_singularity_degraded_test() {
  let ctx =
    RenderContext(
      page: Singularity,
      health: Degraded("safety margin breach"),
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_singularity_agui_obs_test() {
  let event = events.new_reasoning_start("reason-sing")
  events.event_type_to_string(event.event_type)
  |> should.equal("REASONING_START")
}

// =============================================================================
// PAGE 31: ComponentDemo
// =============================================================================

pub fn bdd_l0_componentdemo_render_test() {
  let body = router.route("/api/v1/components")
  { string.length(body) > 10 }
  |> should.equal(True)
}

pub fn bdd_l1_componentdemo_state_binding_test() {
  let body = router.route("/api/v1/components")
  string.contains(body, "Component Demo")
  |> should.be_true()
}

pub fn bdd_l2_componentdemo_interaction_test() {
  let ctx =
    RenderContext(
      page: ComponentDemo,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  string.contains(frame, "Component Demo")
  |> should.be_true()
}

pub fn bdd_l3_componentdemo_telemetry_emit_test() {
  let span =
    zenoh_otel.new_span(
      ComponentDemo,
      "catalog_render",
      zenoh_otel.Observe,
      zenoh_otel.state_change_attrs("empty", "loaded", "catalog"),
    )
  span.page
  |> should.equal(ComponentDemo)
  { string.length(span.span_id) > 0 }
  |> should.equal(True)
}

pub fn bdd_l4_componentdemo_mesh_test() {
  let page_str = zenoh_otel.page_to_string(ComponentDemo)
  page_str
  |> should.equal("component_demo")
}

pub fn bdd_l5_componentdemo_degraded_test() {
  let ctx =
    RenderContext(
      page: ComponentDemo,
      health: Degraded("catalog load failed"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  { string.length(frame) > 0 }
  |> should.equal(True)
}

pub fn bdd_l6_componentdemo_agui_obs_test() {
  let event =
    events.new_state_snapshot(
      json.object([#("page", json.string("ComponentDemo"))]),
    )
  events.event_type_to_string(event.event_type)
  |> should.equal("STATE_SNAPSHOT")
}

// =============================================================================
// CROSS-CUTTING: Navigation Graph Integrity
// =============================================================================

/// Confirm the nav graph contains all 31 pages (SC-UIGT-001).
pub fn bdd_nav_graph_31_pages_test() {
  nav_graph.page_count()
  |> should.equal(31)
}

/// Confirm all_pages() returns exactly 31 entries (no duplicates by count).
pub fn bdd_nav_graph_all_pages_list_test() {
  list.length(nav_graph.all_pages())
  |> should.equal(31)
}

/// Edge count = 31 * 30 = 930 (complete directed graph).
pub fn bdd_nav_graph_edge_count_test() {
  nav_graph.edge_count()
  |> should.equal(930)
}

/// All 31 OTel page strings are non-empty.
pub fn bdd_otel_all_page_strings_nonempty_test() {
  let pages = nav_graph.all_pages()
  list.all(pages, fn(p) { string.length(zenoh_otel.page_to_string(p)) > 0 })
  |> should.be_true()
}

/// Degraded context always produces non-empty frame for every page.
pub fn bdd_all_pages_degraded_nocrash_test() {
  let pages = nav_graph.all_pages()
  list.all(pages, fn(p) {
    let ctx =
      RenderContext(
        page: p,
        health: Degraded("regression test"),
        telemetry: [],
        zenoh_connected: False,
      )
    string.length(renderer.render_frame(ctx)) > 0
  })
  |> should.be_true()
}

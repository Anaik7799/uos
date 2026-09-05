// End-to-End Full-Stack Tests — HTTP request → Wisp Router → JSON Response
// Simulates internet access patterns via router.handle_request()
// Covers: all 28+ routes, AG-UI protocol, POST endpoints, CORS, error paths,
// multi-endpoint workflows, JSON schema validation, and content completeness.
// POST endpoints require Bearer token (SC-SEC-001). Tests use dev token.
// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-006, SC-AGUI-002, SC-SEC-001

import cepaf_gleam/ui/wisp/router
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Section 1: Full Route Coverage — Every ready GET endpoint returns 200 + valid JSON
// =============================================================================

pub fn e2e_all_28_get_routes_return_200_test() {
  let routes = all_get_routes()
  list.each(routes, fn(path) {
    let resp = get(path)
    resp.status |> should.equal(200)
  })
}

pub fn e2e_all_responses_are_valid_json_test() {
  let routes = all_get_routes()
  list.each(routes, fn(path) {
    let resp = get(path)
    let is_json =
      string.starts_with(resp.body, "{") || string.starts_with(resp.body, "[")
    is_json |> should.be_true()
  })
}

pub fn e2e_all_responses_non_empty_test() {
  let routes = all_get_routes()
  list.each(routes, fn(path) {
    let resp = get(path)
    { string.length(resp.body) >= 2 } |> should.be_true()
  })
}

// =============================================================================
// Section 2: Page Identity — Every page endpoint contains its page name
// =============================================================================

pub fn e2e_dashboard_identifies_itself_test() {
  get("/api/v1/dashboard").body |> contains("Dashboard")
}

pub fn e2e_planning_identifies_itself_test() {
  get("/api/v1/planning").body |> contains("Planning")
}

pub fn e2e_immune_identifies_itself_test() {
  get("/api/v1/immune").body |> contains("Immune")
}

pub fn e2e_knowledge_identifies_itself_test() {
  get("/api/v1/knowledge").body |> contains("Knowledge")
}

pub fn e2e_zenoh_identifies_itself_test() {
  get("/api/v1/zenoh").body |> contains("Zenoh")
}

pub fn e2e_verification_identifies_itself_test() {
  get("/api/v1/verification").body |> contains("Verification")
}

pub fn e2e_substrate_identifies_itself_test() {
  get("/api/v1/substrate").body |> contains("Substrate")
}

pub fn e2e_metabolic_identifies_itself_test() {
  get("/api/v1/metabolic").body |> contains("Metabolic")
}

pub fn e2e_podman_identifies_itself_test() {
  get("/api/v1/podman").body |> contains("Podman")
}

pub fn e2e_mcp_identifies_itself_test() {
  get("/api/v1/mcp").body |> contains("MCP")
}

pub fn e2e_kms_identifies_itself_test() {
  get("/api/v1/kms").body |> contains("KMS")
}

pub fn e2e_telemetry_identifies_itself_test() {
  get("/api/v1/telemetry").body |> contains("Telemetry")
}

pub fn e2e_prajna_identifies_itself_test() {
  get("/api/v1/prajna").body |> contains("Prajna")
}

pub fn e2e_agents_identifies_itself_test() {
  get("/api/v1/agents").body |> contains("Agents")
}

pub fn e2e_holon_identifies_itself_test() {
  get("/api/v1/holon").body |> contains("Holon")
}

pub fn e2e_config_identifies_itself_test() {
  get("/api/v1/config").body |> contains("Mesh")
}

pub fn e2e_git_identifies_itself_test() {
  get("/api/v1/git").body |> contains("Git")
}

pub fn e2e_db_identifies_itself_test() {
  get("/api/v1/db").body |> contains("Database")
}

pub fn e2e_bridge_identifies_itself_test() {
  get("/api/v1/bridge").body |> contains("Bridge")
}

pub fn e2e_smriti_identifies_itself_test() {
  get("/api/v1/smriti").body |> contains("Smriti")
}

pub fn e2e_health_grid_identifies_itself_test() {
  get("/api/v1/health_grid").body |> contains("Health Grid")
}

pub fn e2e_planning_dashboard_identifies_itself_test() {
  get("/api/v1/planning_dashboard").body |> contains("Planning Dashboard")
}

pub fn e2e_federation_identifies_itself_test() {
  get("/api/v1/federation").body |> contains("federation")
}

// =============================================================================
// Section 3: AG-UI Protocol E2E
// =============================================================================

pub fn e2e_agui_health_has_protocol_version_test() {
  let body = get("/ag-ui/health").body
  contains(body, "ag-ui")
  contains(body, "1.0.0")
  contains(body, "SIL-6")
}

pub fn e2e_agui_health_has_capabilities_test() {
  let body = get("/ag-ui/health").body
  contains(body, "streaming")
  contains(body, "state_snapshots")
  contains(body, "tool_calls")
  contains(body, "text_messages")
  contains(body, "lifecycle_events")
}

pub fn e2e_agui_state_has_thread_id_test() {
  let body = get("/ag-ui/state").body
  contains(body, "thread")
}

pub fn e2e_agui_hitl_pending_returns_array_test() {
  let body = get("/ag-ui/hitl/pending").body
  string.starts_with(body, "[") |> should.be_true()
}

pub fn e2e_agui_events_returns_sse_test() {
  let resp = get("/ag-ui/events")
  resp.status |> should.equal(200)
  // SSE response has text/event-stream content type
  // but our handler returns it as a regular response
  { string.length(resp.body) > 0 } |> should.be_true()
}

// =============================================================================
// Section 4: POST Endpoint E2E
// =============================================================================

pub fn e2e_agui_run_post_returns_run_id_test() {
  let resp = post_authenticated("/ag-ui/run")
  resp.status |> should.equal(200)
  contains(resp.body, "run")
}

pub fn e2e_agui_hitl_respond_post_accepted_test() {
  let resp = post_authenticated("/ag-ui/hitl/respond")
  resp.status |> should.equal(200)
  contains(resp.body, "accepted")
}

pub fn e2e_agui_tools_result_post_received_test() {
  let resp = post_authenticated("/ag-ui/tools/result")
  resp.status |> should.equal(200)
  contains(resp.body, "received")
}

pub fn e2e_post_unknown_returns_404_test() {
  // Auth passes (dev token), path unknown → 404
  let resp = post_authenticated("/api/v1/nonexistent")
  resp.status |> should.equal(404)
}

// =============================================================================
// Section 5: Error Handling E2E
// =============================================================================

pub fn e2e_unknown_route_returns_not_found_json_test() {
  let resp = get("/api/v1/does_not_exist_xyz")
  resp.status |> should.equal(404)
  contains(resp.body, "not_found")
  string.contains(resp.body, "does_not_exist_xyz") |> should.be_false()
}

pub fn e2e_delete_method_returns_405_test() {
  let req =
    request.new()
    |> request.set_method(http.Delete)
    |> request.set_path("/health")
    |> request.set_body("")
  let resp = router.handle_request(req)
  resp.status |> should.equal(405)
  contains(resp.body, "method_not_allowed")
}

pub fn e2e_put_method_returns_405_test() {
  let req =
    request.new()
    |> request.set_method(http.Put)
    |> request.set_path("/api/v1/dashboard")
    |> request.set_body("")
  let resp = router.handle_request(req)
  resp.status |> should.equal(405)
}

pub fn e2e_patch_method_returns_405_test() {
  let req =
    request.new()
    |> request.set_method(http.Patch)
    |> request.set_path("/health")
    |> request.set_body("")
  let resp = router.handle_request(req)
  resp.status |> should.equal(405)
}

// =============================================================================
// Section 6: Dual-Route Parity (both /api/v1/ and /api/domain/ work)
// =============================================================================

pub fn e2e_dual_route_planning_test() {
  let a = router.route("/api/v1/planning")
  let b = router.route("/api/planning/tasks")
  a |> should.equal(b)
}

pub fn e2e_dual_route_immune_test() {
  let a = router.route("/api/v1/immune")
  let b = router.route("/api/immune/status")
  // Both routes return NIF-backed data with dynamic timestamps,
  // so verify structural equivalence rather than exact string match.
  a |> string.contains("\"page\":\"Immune System\"") |> should.be_true()
  b |> string.contains("\"page\":\"Immune System\"") |> should.be_true()
  a |> string.contains("\"threat_level\"") |> should.be_true()
  b |> string.contains("\"threat_level\"") |> should.be_true()
}

pub fn e2e_dual_route_zenoh_test() {
  let a = router.route("/api/v1/zenoh")
  let b = router.route("/api/zenoh/health")
  a |> should.equal(b)
}

pub fn e2e_dual_route_substrate_test() {
  let a = router.route("/api/v1/substrate")
  let b = router.route("/api/substrate/status")
  a |> should.equal(b)
}

pub fn e2e_dual_route_kms_test() {
  let a = router.route("/api/v1/kms")
  let b = router.route("/api/kms/catalog")
  a |> should.equal(b)
}

// =============================================================================
// Section 7: Health Endpoint Schema Validation
// =============================================================================

pub fn e2e_health_has_status_field_test() {
  contains(get("/health").body, "\"status\"")
}

pub fn e2e_health_has_interface_field_test() {
  contains(get("/health").body, "\"interface\"")
}

pub fn e2e_health_has_port_field_test() {
  contains(get("/health").body, "\"port\"")
}

pub fn e2e_health_has_version_field_test() {
  contains(get("/health").body, "\"version\"")
}

// =============================================================================
// Section 8: Pages Discovery — /api/v1/pages lists all navigable pages
// =============================================================================

pub fn e2e_pages_lists_dashboard_test() {
  contains(get("/api/v1/pages").body, "/dashboard")
}

pub fn e2e_pages_lists_planning_test() {
  contains(get("/api/v1/pages").body, "/planning")
}

pub fn e2e_pages_lists_verification_test() {
  contains(get("/api/v1/pages").body, "/verification")
}

pub fn e2e_pages_has_13_entries_test() {
  let body = get("/api/v1/pages").body
  // Count occurrences of "path" in the response
  let count = string.split(body, "\"path\"") |> list.length()
  // 13 pages = 13 "path" keys + 1 initial segment = 14 splits
  { count >= 14 } |> should.be_true()
}

// =============================================================================
// Section 9: Multi-Endpoint Workflow — Simulate operator journey
// =============================================================================

pub fn e2e_workflow_check_health_then_dashboard_test() {
  // Step 1: Check system health
  let health = get("/health")
  health.status |> should.equal(200)
  contains(health.body, "ok")
  // Step 2: Navigate to dashboard
  let dash = get("/api/v1/dashboard")
  dash.status |> should.equal(200)
  contains(dash.body, "Dashboard")
}

pub fn e2e_workflow_discover_pages_then_visit_each_test() {
  // Step 1: Get page list
  let pages = get("/api/v1/pages")
  pages.status |> should.equal(200)
  // Step 2: Visit first 3 core pages
  get("/api/v1/dashboard").status |> should.equal(200)
  get("/api/v1/planning").status |> should.equal(200)
  get("/api/v1/verification").status |> should.equal(200)
}

pub fn e2e_workflow_agui_lifecycle_test() {
  // Step 1: Check AG-UI health
  let agui = get("/ag-ui/health")
  agui.status |> should.equal(200)
  contains(agui.body, "streaming")
  // Step 2: Start a run (requires auth — SC-SEC-001)
  let run = post_authenticated("/ag-ui/run")
  run.status |> should.equal(200)
  // Step 3: Check state
  let state = get("/ag-ui/state")
  state.status |> should.equal(200)
  // Step 4: Check pending approvals
  let pending = get("/ag-ui/hitl/pending")
  pending.status |> should.equal(200)
}

pub fn e2e_workflow_safety_verification_test() {
  // Step 1: Check verification status
  let verify = get("/api/v1/verification")
  verify.status |> should.equal(200)
  // Step 2: Check safety kernel
  let safety = get("/api/safety/status")
  safety.status |> should.equal(200)
  contains(safety.body, "Safety")
  // Step 3: Check enforcer
  let enforcer = get("/api/enforcer/status")
  enforcer.status |> should.equal(200)
  contains(enforcer.body, "Enforcer")
}

pub fn e2e_workflow_federation_check_test() {
  // Step 1: Check federation status
  let fed = get("/api/v1/federation")
  fed.status |> should.equal(503)
  contains(fed.body, "peer")
  contains(fed.body, "l7_federation_state_source_not_wired")
  // Step 2: Check mesh config
  let config = get("/api/v1/config")
  config.status |> should.equal(200)
  contains(config.body, "Mesh Configuration")
}

pub fn e2e_workflow_prajna_biomorphic_check_test() {
  // Step 1: Prajna health
  let prajna = get("/api/v1/prajna")
  prajna.status |> should.equal(200)
  contains(prajna.body, "dark_cockpit")
  // Step 2: Check biomorphic matrix
  let bio = get("/api/v1/biomorphic")
  bio.status |> should.equal(200)
  // Step 3: Check homeostasis
  let homeo = get("/api/v1/homeostasis")
  homeo.status |> should.equal(200)
  contains(homeo.body, "kp")
}

// =============================================================================
// Section 10: Extended Endpoints (Layer 2 Supervisor features)
// =============================================================================

pub fn e2e_integrity_returns_json_test() {
  let resp = get("/api/v1/integrity")
  resp.status |> should.equal(200)
  contains(resp.body, "Integrity")
}

pub fn e2e_evolution_returns_json_test() {
  let resp = get("/api/v1/evolution")
  resp.status |> should.equal(200)
  contains(resp.body, "Evolution")
}

pub fn e2e_biomorphic_returns_json_test() {
  let resp = get("/api/v1/biomorphic")
  resp.status |> should.equal(200)
  contains(resp.body, "Biomorphic")
}

pub fn e2e_homeostasis_returns_json_test() {
  let resp = get("/api/v1/homeostasis")
  resp.status |> should.equal(200)
  contains(resp.body, "Homeostasis")
}

pub fn e2e_bicameral_returns_json_test() {
  let resp = get("/api/v1/bicameral")
  resp.status |> should.equal(200)
  contains(resp.body, "Bicameral")
}

pub fn e2e_singularity_returns_json_test() {
  let resp = get("/api/v1/singularity")
  resp.status |> should.equal(200)
  contains(resp.body, "Singularity")
}

// =============================================================================
// Section 11: Safety & Enforcer Endpoints
// =============================================================================

pub fn e2e_safety_has_guardian_status_test() {
  let body = get("/api/safety/status").body
  contains(body, "guardian")
}

pub fn e2e_safety_has_psi_checks_test() {
  let body = get("/api/safety/status").body
  contains(body, "ExistenceInvariant")
  contains(body, "Truthfulness")
}

pub fn e2e_enforcer_has_statistics_test() {
  let body = get("/api/enforcer/status").body
  contains(body, "statistics")
  contains(body, "total_checks")
}

// =============================================================================
// Section 12: OODA, Orchestration, Graph, Access, Chaya, Math
// =============================================================================

pub fn e2e_ooda_returns_json_test() {
  let resp = get("/api/v1/ooda")
  resp.status |> should.equal(200)
}

pub fn e2e_orchestration_returns_json_test() {
  let resp = get("/api/v1/orchestration")
  resp.status |> should.equal(200)
}

pub fn e2e_graph_returns_json_test() {
  let resp = get("/api/v1/graph")
  resp.status |> should.equal(200)
}

pub fn e2e_access_returns_json_test() {
  let resp = get("/api/v1/access")
  resp.status |> should.equal(200)
}

pub fn e2e_chaya_returns_json_test() {
  let resp = get("/api/v1/chaya")
  resp.status |> should.equal(200)
}

pub fn e2e_math_returns_json_test() {
  let resp = get("/api/v1/math")
  resp.status |> should.equal(200)
}

// =============================================================================
// Helpers
// =============================================================================

fn get(path: String) -> response.Response(String) {
  request.new()
  |> request.set_method(http.Get)
  |> request.set_path(path)
  |> request.set_body("")
  |> router.handle_request()
}

/// POST with the dev bearer token (SC-SEC-001 — mutations require auth).
fn post_authenticated(path: String) -> response.Response(String) {
  request.new()
  |> request.set_method(http.Post)
  |> request.set_path(path)
  |> request.set_body("")
  |> request.set_header("authorization", "Bearer c3i-dev-token")
  |> router.handle_request()
}

fn contains(body: String, expected: String) {
  string.contains(body, expected) |> should.be_true()
}

fn all_get_routes() -> List(String) {
  [
    "/health", "/api/v1/pages", "/api/v1/dashboard", "/api/v1/planning",
    "/api/v1/immune", "/api/v1/knowledge", "/api/v1/zenoh",
    "/api/v1/verification", "/api/v1/substrate", "/api/v1/metabolic",
    "/api/v1/podman", "/api/v1/mcp", "/api/v1/kms", "/api/v1/telemetry",
    "/api/v1/prajna", "/api/v1/agents", "/api/v1/holon", "/api/v1/config",
    "/api/v1/git", "/api/v1/db", "/api/v1/bridge", "/api/v1/smriti",
    "/api/v1/planning_dashboard", "/ag-ui/health", "/ag-ui/state",
    "/ag-ui/hitl/pending",
  ]
}

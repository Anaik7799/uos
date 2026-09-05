// HTTP Internet Regression Tests — All 26+ Endpoints via Mist Server
// Validates every Wisp route returns valid JSON via HTTP GET/POST.
// POST endpoints require Bearer token auth (SC-SEC-001).
// STAMP: SC-GLM-UI-006, SC-GLM-UI-003, SC-GLM-UI-001, SC-AGUI-002, SC-SEC-001

import cepaf_gleam/ui/wisp/router
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/string
import gleeunit/should

/// Dev token matching auth.default_dev_token — used only in tests.
const dev_token = "c3i-dev-token"

// =============================================================================
// Health & Discovery Endpoints
// =============================================================================

pub fn http_health_returns_200_test() {
  let resp = get("/health")
  resp.status |> should.equal(200)
  string.contains(resp.body, "\"status\":\"ok\"") |> should.be_true()
}

pub fn http_pages_lists_all_pages_test() {
  let resp = get("/api/v1/pages")
  resp.status |> should.equal(200)
  string.contains(resp.body, "\"pages\"") |> should.be_true()
  string.contains(resp.body, "Dashboard") |> should.be_true()
  string.contains(resp.body, "Planning") |> should.be_true()
  string.contains(resp.body, "Verification") |> should.be_true()
}

// =============================================================================
// Core Domain Endpoints (13 primary pages)
// =============================================================================

pub fn http_dashboard_returns_json_test() {
  let resp = get("/api/v1/dashboard")
  resp.status |> should.equal(200)
  string.contains(resp.body, "\"page\"") |> should.be_true()
  string.contains(resp.body, "Dashboard") |> should.be_true()
}

pub fn http_planning_returns_json_test() {
  let resp = get("/api/v1/planning")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Planning") |> should.be_true()
}

pub fn http_immune_returns_json_test() {
  let resp = get("/api/v1/immune")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Immune") |> should.be_true()
}

pub fn http_knowledge_returns_json_test() {
  let resp = get("/api/v1/knowledge")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Knowledge") |> should.be_true()
}

pub fn http_zenoh_returns_json_test() {
  let resp = get("/api/v1/zenoh")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Zenoh") |> should.be_true()
}

pub fn http_verification_returns_json_test() {
  let resp = get("/api/v1/verification")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Verification") |> should.be_true()
}

pub fn http_substrate_returns_json_test() {
  let resp = get("/api/v1/substrate")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Substrate") |> should.be_true()
}

pub fn http_metabolic_returns_json_test() {
  let resp = get("/api/v1/metabolic")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Metabolic") |> should.be_true()
}

pub fn http_podman_returns_json_test() {
  let resp = get("/api/v1/podman")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Podman") |> should.be_true()
}

pub fn http_mcp_returns_json_test() {
  let resp = get("/api/v1/mcp")
  resp.status |> should.equal(200)
  string.contains(resp.body, "MCP") |> should.be_true()
}

pub fn http_kms_returns_json_test() {
  let resp = get("/api/v1/kms")
  resp.status |> should.equal(200)
  string.contains(resp.body, "KMS") |> should.be_true()
}

pub fn http_telemetry_returns_json_test() {
  let resp = get("/api/v1/telemetry")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Telemetry") |> should.be_true()
}

// =============================================================================
// Extended Endpoints (Wave 2 — Prajna, Agents, Holon, Config, Git, DB, Bridge, Smriti)
// =============================================================================

pub fn http_prajna_returns_json_test() {
  let resp = get("/api/v1/prajna")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Prajna") |> should.be_true()
  string.contains(resp.body, "dark_cockpit") |> should.be_true()
}

pub fn http_agents_returns_json_test() {
  let resp = get("/api/v1/agents")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Agents") |> should.be_true()
}

pub fn http_holon_returns_json_test() {
  let resp = get("/api/v1/holon")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Holon") |> should.be_true()
}

pub fn http_config_returns_json_test() {
  let resp = get("/api/v1/config")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Mesh") |> should.be_true()
}

pub fn http_git_returns_json_test() {
  let resp = get("/api/v1/git")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Git") |> should.be_true()
}

pub fn http_db_returns_json_test() {
  let resp = get("/api/v1/db")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Database") |> should.be_true()
}

pub fn http_bridge_returns_json_test() {
  let resp = get("/api/v1/bridge")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Bridge") |> should.be_true()
}

pub fn http_smriti_returns_json_test() {
  let resp = get("/api/v1/smriti")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Smriti") |> should.be_true()
}

// =============================================================================
// Parity Endpoints (Health Grid, Planning Dashboard)
// =============================================================================

pub fn http_health_grid_returns_json_test() {
  let resp = get("/api/v1/health_grid")
  resp.status |> should.equal(501)
  string.contains(resp.body, "Health Grid") |> should.be_true()
  string.contains(resp.body, "device_inventory_source_not_wired")
  |> should.be_true()
}

pub fn http_planning_dashboard_returns_json_test() {
  let resp = get("/api/v1/planning_dashboard")
  resp.status |> should.equal(200)
  string.contains(resp.body, "Planning Dashboard") |> should.be_true()
}

// =============================================================================
// Federation Endpoint
// =============================================================================

pub fn http_federation_returns_json_test() {
  let resp = get("/api/v1/federation")
  resp.status |> should.equal(503)
  string.contains(resp.body, "federation") |> should.be_true()
  string.contains(resp.body, "l7_federation_state_source_not_wired")
  |> should.be_true()
}

pub fn http_ai_chat_get_not_wired_is_501_test() {
  let resp = get("/api/v1/ai/chat?q=system+health")
  resp.status |> should.equal(501)
  string.contains(resp.body, "llm_chat_get_not_wired") |> should.be_true()
}

// =============================================================================
// AG-UI Protocol Endpoints
// =============================================================================

pub fn http_agui_health_returns_json_test() {
  let resp = get("/ag-ui/health")
  resp.status |> should.equal(200)
  string.contains(resp.body, "ag-ui") |> should.be_true()
  string.contains(resp.body, "SIL-6") |> should.be_true()
}

pub fn http_agui_state_returns_json_test() {
  let resp = get("/ag-ui/state")
  resp.status |> should.equal(200)
  string.contains(resp.body, "thread") |> should.be_true()
}

pub fn http_agui_hitl_pending_returns_json_test() {
  let resp = get("/ag-ui/hitl/pending")
  resp.status |> should.equal(200)
  // Empty approval queue = empty JSON array
  string.contains(resp.body, "[") |> should.be_true()
}

// =============================================================================
// POST Endpoints
// =============================================================================

pub fn http_agui_run_post_returns_200_test() {
  let resp = post_with_token("/ag-ui/run", dev_token)
  resp.status |> should.equal(200)
}

pub fn http_agui_hitl_respond_post_returns_200_test() {
  let resp = post_with_token("/ag-ui/hitl/respond", dev_token)
  resp.status |> should.equal(200)
  string.contains(resp.body, "accepted") |> should.be_true()
}

pub fn http_agui_tools_result_post_returns_200_test() {
  let resp = post_with_token("/ag-ui/tools/result", dev_token)
  resp.status |> should.equal(200)
  string.contains(resp.body, "received") |> should.be_true()
}

pub fn http_ooda_trigger_post_returns_202_test() {
  let resp = post_with_token("/api/v1/ooda/trigger", dev_token)
  resp.status |> should.equal(202)
  string.contains(resp.body, "accepted") |> should.be_true()
}

pub fn http_zenoh_publish_without_topic_returns_400_test() {
  let resp = post_with_token("/api/v1/zenoh/publish", dev_token)
  resp.status |> should.equal(400)
  string.contains(resp.body, "missing_topic") |> should.be_true()
}

// Auth boundary tests (SC-SEC-001)

pub fn http_post_without_token_returns_401_test() {
  let resp = post("/ag-ui/run")
  resp.status |> should.equal(401)
  string.contains(resp.body, "unauthorized") |> should.be_true()
  string.contains(resp.body, "SC-SEC-001") |> should.be_true()
}

pub fn http_post_with_wrong_token_returns_401_test() {
  let resp = post_with_token("/ag-ui/run", "wrong-token")
  resp.status |> should.equal(401)
  string.contains(resp.body, "unauthorized") |> should.be_true()
}

// =============================================================================
// Error Handling
// =============================================================================

pub fn http_not_found_returns_404_test() {
  let resp = get("/api/v1/nonexistent")
  resp.status |> should.equal(404)
  string.contains(resp.body, "not_found") |> should.be_true()
  string.contains(resp.body, "/api/v1/nonexistent") |> should.be_false()
}

pub fn http_method_not_allowed_returns_405_test() {
  let req =
    request.new()
    |> request.set_method(http.Delete)
    |> request.set_path("/health")
    |> request.set_body("")
  let resp = router.handle_request(req)
  resp.status |> should.equal(405)
}

// =============================================================================
// JSON Structure Validation
// =============================================================================

pub fn http_all_responses_are_valid_json_test() {
  let paths = [
    "/health", "/api/v1/pages", "/api/v1/dashboard", "/api/v1/planning",
    "/api/v1/immune", "/api/v1/knowledge", "/api/v1/zenoh",
    "/api/v1/verification", "/api/v1/substrate", "/api/v1/metabolic",
    "/api/v1/podman", "/api/v1/mcp", "/api/v1/kms", "/api/v1/telemetry",
    "/api/v1/prajna", "/api/v1/agents", "/api/v1/holon", "/api/v1/config",
    "/api/v1/git", "/api/v1/db", "/api/v1/bridge", "/api/v1/smriti",
    "/api/v1/health_grid", "/api/v1/planning_dashboard", "/api/v1/federation",
    "/api/v1/ai/chat?q=system+health", "/ag-ui/health",
  ]
  list.each(paths, fn(path) {
    let resp = get(path)
    // All JSON responses must start with { or [
    let starts_json =
      string.starts_with(resp.body, "{") || string.starts_with(resp.body, "[")
    starts_json |> should.be_true()
  })
}

pub fn http_all_get_endpoints_return_200_test() {
  let paths = [
    "/health", "/api/v1/pages", "/api/v1/dashboard", "/api/v1/planning",
    "/api/v1/immune", "/api/v1/knowledge", "/api/v1/zenoh",
    "/api/v1/verification", "/api/v1/substrate", "/api/v1/metabolic",
    "/api/v1/podman", "/api/v1/mcp", "/api/v1/kms", "/api/v1/telemetry",
    "/api/v1/prajna", "/api/v1/agents", "/api/v1/holon", "/api/v1/config",
    "/api/v1/git", "/api/v1/db", "/api/v1/bridge", "/api/v1/smriti",
    "/api/v1/planning_dashboard", "/ag-ui/health",
  ]
  list.each(paths, fn(path) {
    let resp = get(path)
    resp.status |> should.equal(200)
  })
}

// =============================================================================
// Helpers — simulate HTTP via router.handle_request (no live server needed)
// =============================================================================

import gleam/list

fn get(path: String) -> response.Response(String) {
  let req =
    request.new()
    |> request.set_method(http.Get)
    |> request.set_path(path)
    |> request.set_body("")
  router.handle_request(req)
}

fn post(path: String) -> response.Response(String) {
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path(path)
    |> request.set_body("")
  router.handle_request(req)
}

fn post_with_token(path: String, token: String) -> response.Response(String) {
  let req =
    request.new()
    |> request.set_method(http.Post)
    |> request.set_path(path)
    |> request.set_body("")
    |> request.set_header("authorization", "Bearer " <> token)
  router.handle_request(req)
}

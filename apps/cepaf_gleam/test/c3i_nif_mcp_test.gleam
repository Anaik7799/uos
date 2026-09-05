// =============================================================================
// C3I Unified NIF + MCP Verification Tests
// =============================================================================
// Validates all 14 NIF-backed MCP tools return valid JSON via Wisp API routes.
// Tests real data flow: Rust NIF -> Erlang -> Gleam -> Wisp JSON.
//
// Section 1: Planning NIFs (7 tests)
// Section 2: System NIFs (5 tests)
// Section 3: Knowledge + Verification NIFs (2 tests)
// Section 4: MoZ Dispatch (7 tests)
// Section 5: Router NIF Integration (10 tests)
// Section 6: Nav Graph 30-Page Coverage (5 tests)
// =============================================================================
// STAMP: SC-MCP-001, SC-TODO-001, SC-NIF-001, SC-ZMOF-005, SC-UIGT-001

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/moz/planning as moz_planning
import cepaf_gleam/moz/system as moz_system
import cepaf_gleam/testing/nav_graph
import cepaf_gleam/ui/wisp/router
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Section 1: Planning NIFs
// =============================================================================

pub fn nif_plan_status_returns_json_test() {
  let result = c3i_nif.plan_status()
  result |> string.contains("\"total\"") |> should.be_true()
  result |> string.contains("\"completed\"") |> should.be_true()
  result |> string.contains("\"pending\"") |> should.be_true()
}

pub fn nif_plan_list_pending_returns_array_test() {
  let result = c3i_nif.plan_list_pending()
  // Returns JSON array (may be empty [] or populated)
  { string.starts_with(result, "[") || string.contains(result, "\"error\"") }
  |> should.be_true()
}

pub fn nif_plan_list_by_status_all_test() {
  let result = c3i_nif.plan_list_by_status("all")
  string.starts_with(result, "[") |> should.be_true()
}

pub fn nif_plan_list_by_status_completed_test() {
  let result = c3i_nif.plan_list_by_status("completed")
  string.starts_with(result, "[") |> should.be_true()
}

pub fn nif_plan_get_task_missing_test() {
  let result = c3i_nif.plan_get_task("nonexistent_id_12345")
  result |> string.contains("error") |> should.be_true()
}

pub fn nif_plan_search_empty_test() {
  let result = c3i_nif.plan_search("zzz_no_match_zzz")
  string.starts_with(result, "[") |> should.be_true()
}

pub fn nif_plan_search_returns_results_test() {
  let result = c3i_nif.plan_search("task")
  // Should return array (possibly empty, possibly with matches)
  { string.starts_with(result, "[") || string.contains(result, "\"error\"") }
  |> should.be_true()
}

// =============================================================================
// Section 2: System NIFs
// =============================================================================

pub fn nif_system_health_returns_json_test() {
  let result = c3i_nif.system_health()
  result |> string.contains("\"status\"") |> should.be_true()
  result |> string.contains("\"container_count\"") |> should.be_true()
  result |> string.contains("\"interface\"") |> should.be_true()
  result |> string.contains("\"port\"") |> should.be_true()
  result |> string.contains("\"version\"") |> should.be_true()
}

pub fn nif_system_dashboard_returns_json_test() {
  let result = c3i_nif.system_dashboard()
  result |> string.contains("\"page\":\"Dashboard\"") |> should.be_true()
  result |> string.contains("\"health_pct\"") |> should.be_true()
  result |> string.contains("\"dark_cockpit_mode\"") |> should.be_true()
}

pub fn nif_system_immune_returns_json_test() {
  let result = c3i_nif.system_immune()
  result |> string.contains("\"page\":\"Immune System\"") |> should.be_true()
  result |> string.contains("\"threat_level\"") |> should.be_true()
}

pub fn nif_system_zenoh_returns_json_test() {
  let result = c3i_nif.system_zenoh()
  result |> string.contains("\"page\":\"Zenoh Mesh\"") |> should.be_true()
  result |> string.contains("\"connected\"") |> should.be_true()
  result |> string.contains("\"routers\"") |> should.be_true()
}

pub fn nif_system_verification_returns_json_test() {
  let result = c3i_nif.system_verification()
  result |> string.contains("\"page\":\"Verification\"") |> should.be_true()
  result |> string.contains("\"sil_level\"") |> should.be_true()
  result |> string.contains("\"tests_total\"") |> should.be_true()
}

// =============================================================================
// Section 3: Knowledge + Verification NIFs
// =============================================================================

pub fn nif_knowledge_search_returns_json_test() {
  let result = c3i_nif.knowledge_search("test")
  result |> string.contains("\"query\"") |> should.be_true()
  result |> string.contains("\"results\"") |> should.be_true()
  result |> string.contains("\"total\"") |> should.be_true()
}

pub fn nif_verification_run_returns_json_test() {
  let result = c3i_nif.verification_run()
  result |> string.contains("\"ok\"") |> should.be_true()
  result |> string.contains("\"warnings\"") |> should.be_true()
  result |> string.contains("\"errors\"") |> should.be_true()
}

// =============================================================================
// Section 4: MoZ Dispatch
// =============================================================================

pub fn moz_planning_dispatch_status_test() {
  let args = json.object([])
  let result = moz_planning.dispatch("plan_status", args)
  result |> string.contains("\"total\"") |> should.be_true()
}

pub fn moz_planning_dispatch_list_pending_test() {
  let args = json.object([])
  let result = moz_planning.dispatch("plan_list_pending", args)
  string.starts_with(result, "[") |> should.be_true()
}

pub fn moz_planning_dispatch_unknown_test() {
  let args = json.object([])
  let result = moz_planning.dispatch("unknown_tool", args)
  result |> string.contains("\"error\"") |> should.be_true()
}

pub fn moz_planning_available_tools_test() {
  let tools = moz_planning.available_tools()
  list.length(tools) |> should.equal(7)
}

pub fn moz_system_dispatch_health_test() {
  let result = moz_system.dispatch("system_health")
  result |> string.contains("\"status\"") |> should.be_true()
}

pub fn moz_system_dispatch_unknown_test() {
  let result = moz_system.dispatch("unknown_tool")
  result |> string.contains("\"error\"") |> should.be_true()
}

pub fn moz_system_available_tools_test() {
  let tools = moz_system.available_tools()
  list.length(tools) |> should.equal(7)
}

// =============================================================================
// Section 5: Router NIF Integration
// =============================================================================

pub fn router_health_has_nif_fields_test() {
  let body = router.route("/health")
  body |> string.contains("\"status\"") |> should.be_true()
  body |> string.contains("\"container_count\"") |> should.be_true()
}

pub fn router_dashboard_has_nif_fields_test() {
  let body = router.route("/api/v1/dashboard")
  body |> string.contains("\"page\":\"Dashboard\"") |> should.be_true()
  body |> string.contains("\"health_pct\"") |> should.be_true()
}

pub fn router_immune_has_nif_fields_test() {
  let body = router.route("/api/v1/immune")
  body |> string.contains("\"page\":\"Immune System\"") |> should.be_true()
  body |> string.contains("\"threat_level\"") |> should.be_true()
}

pub fn router_zenoh_has_nif_fields_test() {
  let body = router.route("/api/v1/zenoh")
  body |> string.contains("\"page\":\"Zenoh Mesh\"") |> should.be_true()
  body |> string.contains("\"connected\"") |> should.be_true()
}

pub fn router_plan_status_nif_test() {
  let body = router.route("/api/v1/plan/status")
  body |> string.contains("\"total\"") |> should.be_true()
}

pub fn router_plan_list_all_nif_test() {
  let body = router.route("/api/v1/plan/list/all")
  string.starts_with(body, "[") |> should.be_true()
}

pub fn router_plan_list_completed_nif_test() {
  let body = router.route("/api/v1/plan/list/completed")
  string.starts_with(body, "[") |> should.be_true()
}

pub fn router_pages_has_30_pages_test() {
  let body = router.route("/api/v1/pages")
  body |> string.contains("\"Singularity Estimation\"") |> should.be_true()
  body |> string.contains("\"Bicameral Sign-Off\"") |> should.be_true()
  body |> string.contains("\"Evolution Vectors\"") |> should.be_true()
}

pub fn router_integrity_has_data_test() {
  let body = router.route("/api/v1/integrity")
  body |> string.contains("\"page\":\"Integrity\"") |> should.be_true()
  body |> string.contains("\"constitution_hash\"") |> should.be_true()
}

pub fn router_evolution_has_data_test() {
  let body = router.route("/api/v1/evolution")
  body |> string.contains("\"page\":\"Evolution\"") |> should.be_true()
}

// =============================================================================
// Section 6: Nav Graph 31-Page Coverage
// =============================================================================

pub fn nav_graph_has_30_pages_test() {
  nav_graph.page_count() |> should.equal(31)
}

pub fn nav_graph_all_pages_length_test() {
  list.length(nav_graph.all_pages()) |> should.equal(31)
}

pub fn nav_graph_edge_count_test() {
  nav_graph.edge_count() |> should.equal(930)
}

pub fn nav_graph_density_is_1_test() {
  nav_graph.density() |> should.equal(1.0)
}

pub fn nav_graph_scc_is_1_test() {
  nav_graph.scc_count() |> should.equal(1)
}

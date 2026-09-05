// =============================================================================
// WebUI Full Coverage Test — Comprehensive tests for ALL 13 Lustre MVU modules
// and ALL Wisp API router endpoints.
// =============================================================================
// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-009
// Coverage: ui/domain (13 pages), ui/wisp/router (19+ paths),
//           ui/lustre/{substrate,metabolic,podman,mcp,kms,telemetry}
// =============================================================================

import cepaf_gleam/ui/domain
import cepaf_gleam/ui/lustre/kms
import cepaf_gleam/ui/lustre/mcp
import cepaf_gleam/ui/lustre/metabolic
import cepaf_gleam/ui/lustre/podman
import cepaf_gleam/ui/lustre/substrate
import cepaf_gleam/ui/lustre/telemetry as lustre_telemetry
import cepaf_gleam/ui/wisp/router
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// Section 1: page_to_path — ALL 13 Page variants
// =============================================================================

pub fn page_to_path_dashboard_test() {
  domain.page_to_path(domain.Dashboard) |> should.equal("/dashboard")
}

pub fn page_to_path_planning_test() {
  domain.page_to_path(domain.Planning) |> should.equal("/planning")
}

pub fn page_to_path_immune_test() {
  domain.page_to_path(domain.Immune) |> should.equal("/immune")
}

pub fn page_to_path_knowledge_test() {
  domain.page_to_path(domain.Knowledge) |> should.equal("/knowledge")
}

pub fn page_to_path_zenoh_test() {
  domain.page_to_path(domain.Zenoh) |> should.equal("/zenoh")
}

pub fn page_to_path_cockpit_test() {
  domain.page_to_path(domain.Cockpit) |> should.equal("/cockpit")
}

pub fn page_to_path_verification_test() {
  domain.page_to_path(domain.Verification) |> should.equal("/verification")
}

pub fn page_to_path_substrate_test() {
  domain.page_to_path(domain.Substrate) |> should.equal("/substrate")
}

pub fn page_to_path_metabolic_test() {
  domain.page_to_path(domain.Metabolic) |> should.equal("/metabolic")
}

pub fn page_to_path_podman_test() {
  domain.page_to_path(domain.Podman) |> should.equal("/podman")
}

pub fn page_to_path_mcp_test() {
  domain.page_to_path(domain.Mcp) |> should.equal("/mcp")
}

pub fn page_to_path_kms_test() {
  domain.page_to_path(domain.Kms) |> should.equal("/kms")
}

pub fn page_to_path_telemetry_test() {
  domain.page_to_path(domain.Telemetry) |> should.equal("/telemetry")
}

// =============================================================================
// Section 2: page_to_label — ALL 13 Page variants
// =============================================================================

pub fn page_to_label_dashboard_test() {
  domain.page_to_label(domain.Dashboard) |> should.equal("Dashboard")
}

pub fn page_to_label_planning_test() {
  domain.page_to_label(domain.Planning) |> should.equal("Planning")
}

pub fn page_to_label_immune_test() {
  domain.page_to_label(domain.Immune) |> should.equal("Immune System")
}

pub fn page_to_label_knowledge_test() {
  domain.page_to_label(domain.Knowledge) |> should.equal("Knowledge (Smriti)")
}

pub fn page_to_label_zenoh_test() {
  domain.page_to_label(domain.Zenoh) |> should.equal("Zenoh Mesh")
}

pub fn page_to_label_cockpit_test() {
  domain.page_to_label(domain.Cockpit) |> should.equal("Cockpit")
}

pub fn page_to_label_verification_test() {
  domain.page_to_label(domain.Verification) |> should.equal("Verification")
}

pub fn page_to_label_substrate_test() {
  domain.page_to_label(domain.Substrate) |> should.equal("Substrate")
}

pub fn page_to_label_metabolic_test() {
  domain.page_to_label(domain.Metabolic) |> should.equal("Metabolic")
}

pub fn page_to_label_podman_test() {
  domain.page_to_label(domain.Podman) |> should.equal("Podman")
}

pub fn page_to_label_mcp_test() {
  domain.page_to_label(domain.Mcp) |> should.equal("MCP Server")
}

pub fn page_to_label_kms_test() {
  domain.page_to_label(domain.Kms) |> should.equal("KMS Catalog")
}

pub fn page_to_label_telemetry_test() {
  domain.page_to_label(domain.Telemetry) |> should.equal("Telemetry")
}

// =============================================================================
// Section 3: Wisp Router — ALL route() paths return valid JSON (no not_found)
// =============================================================================

/// Helper: asserts that router output does NOT contain "not_found" error.
fn assert_route_valid(path: String) {
  let result = router.route(path)
  string.contains(result, "\"not_found\"") |> should.be_false()
}

pub fn route_health_test() {
  assert_route_valid("/health")
}

pub fn route_api_health_test() {
  assert_route_valid("/api/health")
}

pub fn route_api_v1_pages_test() {
  assert_route_valid("/api/v1/pages")
}

pub fn route_api_pages_test() {
  assert_route_valid("/api/pages")
}

pub fn route_api_v1_dashboard_test() {
  assert_route_valid("/api/v1/dashboard")
}

pub fn route_api_dashboard_test() {
  assert_route_valid("/api/dashboard")
}

pub fn route_api_v1_planning_test() {
  assert_route_valid("/api/v1/planning")
}

pub fn route_api_planning_tasks_test() {
  assert_route_valid("/api/planning/tasks")
}

pub fn route_api_v1_immune_test() {
  assert_route_valid("/api/v1/immune")
}

pub fn route_api_immune_status_test() {
  assert_route_valid("/api/immune/status")
}

pub fn route_api_v1_knowledge_test() {
  assert_route_valid("/api/v1/knowledge")
}

pub fn route_api_knowledge_graph_test() {
  assert_route_valid("/api/knowledge/graph")
}

pub fn route_api_v1_zenoh_test() {
  assert_route_valid("/api/v1/zenoh")
}

pub fn route_api_zenoh_health_test() {
  assert_route_valid("/api/zenoh/health")
}

pub fn route_api_v1_verification_test() {
  assert_route_valid("/api/v1/verification")
}

pub fn route_api_verification_status_test() {
  assert_route_valid("/api/verification/status")
}

pub fn route_api_cockpit_nodes_test() {
  assert_route_valid("/api/cockpit/nodes")
}

pub fn route_api_substrate_status_test() {
  assert_route_valid("/api/substrate/status")
}

pub fn route_api_v1_substrate_test() {
  assert_route_valid("/api/v1/substrate")
}

pub fn route_api_metabolic_status_test() {
  assert_route_valid("/api/metabolic/status")
}

pub fn route_api_v1_metabolic_test() {
  assert_route_valid("/api/v1/metabolic")
}

pub fn route_api_podman_containers_test() {
  assert_route_valid("/api/podman/containers")
}

pub fn route_api_v1_podman_test() {
  assert_route_valid("/api/v1/podman")
}

pub fn route_api_mcp_status_test() {
  assert_route_valid("/api/mcp/status")
}

pub fn route_api_v1_mcp_test() {
  assert_route_valid("/api/v1/mcp")
}

pub fn route_api_kms_catalog_test() {
  assert_route_valid("/api/kms/catalog")
}

pub fn route_api_v1_kms_test() {
  assert_route_valid("/api/v1/kms")
}

pub fn route_api_telemetry_status_test() {
  assert_route_valid("/api/telemetry/status")
}

pub fn route_api_v1_telemetry_test() {
  assert_route_valid("/api/v1/telemetry")
}

// Route 404 returns not_found for unknown paths
pub fn route_unknown_returns_not_found_test() {
  let result = router.route("/api/nonexistent")
  string.contains(result, "\"not_found\"") |> should.be_true()
}

// =============================================================================
// Section 4: Wisp Router — content validation for key endpoints
// =============================================================================

pub fn route_health_contains_status_ok_test() {
  let result = router.route("/health")
  string.contains(result, "\"ok\"") |> should.be_true()
  string.contains(result, "\"wisp\"") |> should.be_true()
  string.contains(result, "4100") |> should.be_true()
}

pub fn route_pages_contains_all_13_pages_test() {
  let result = router.route("/api/v1/pages")
  // Verify all 13 page labels appear
  string.contains(result, "Dashboard") |> should.be_true()
  string.contains(result, "Planning") |> should.be_true()
  string.contains(result, "Immune System") |> should.be_true()
  string.contains(result, "Knowledge (Smriti)") |> should.be_true()
  string.contains(result, "Zenoh Mesh") |> should.be_true()
  string.contains(result, "Cockpit") |> should.be_true()
  string.contains(result, "Verification") |> should.be_true()
  string.contains(result, "Substrate") |> should.be_true()
  string.contains(result, "Metabolic") |> should.be_true()
  string.contains(result, "Podman") |> should.be_true()
  string.contains(result, "MCP Server") |> should.be_true()
  string.contains(result, "KMS Catalog") |> should.be_true()
  string.contains(result, "Telemetry") |> should.be_true()
}

pub fn route_planning_contains_tasks_test() {
  let result = router.route("/api/v1/planning")
  string.contains(result, "\"Planning\"") |> should.be_true()
  string.contains(result, "\"summary_raw\"") |> should.be_true()
  string.contains(result, "\"pending_raw\"") |> should.be_true()
}

pub fn route_immune_contains_threat_level_test() {
  let result = router.route("/api/v1/immune")
  string.contains(result, "\"Immune System\"") |> should.be_true()
  string.contains(result, "\"nominal\"") |> should.be_true()
}

pub fn route_knowledge_contains_nodes_and_links_test() {
  let result = router.route("/api/v1/knowledge")
  string.contains(result, "\"Knowledge Graph\"") |> should.be_true()
  string.contains(result, "\"nodes\"") |> should.be_true()
  string.contains(result, "\"links\"") |> should.be_true()
}

pub fn route_zenoh_contains_routers_test() {
  let result = router.route("/api/v1/zenoh")
  string.contains(result, "\"Zenoh Mesh\"") |> should.be_true()
  string.contains(result, "\"router_endpoints\"") |> should.be_true()
}

pub fn route_verification_contains_sil6_test() {
  let result = router.route("/api/v1/verification")
  string.contains(result, "\"Verification\"") |> should.be_true()
  string.contains(result, "\"SIL-6\"") |> should.be_true()
}

pub fn route_cockpit_contains_nodes_test() {
  let result = router.route("/api/cockpit/nodes")
  string.contains(result, "\"Cockpit\"") |> should.be_true()
  string.contains(result, "\"dark_cockpit\"") |> should.be_true()
}

pub fn route_substrate_contains_governor_test() {
  let result = router.route("/api/substrate/status")
  string.contains(result, "\"Substrate\"") |> should.be_true()
  string.contains(result, "\"governor_action\"") |> should.be_true()
  string.contains(result, "\"SQLite\"") |> should.be_true()
}

pub fn route_metabolic_contains_set_point_test() {
  let result = router.route("/api/metabolic/status")
  string.contains(result, "\"Metabolic\"") |> should.be_true()
  string.contains(result, "\"set_point\"") |> should.be_true()
  string.contains(result, "\"energy\"") |> should.be_true()
}

pub fn route_podman_contains_containers_test() {
  let result = router.route("/api/podman/containers")
  string.contains(result, "\"Podman\"") |> should.be_true()
  string.contains(result, "\"containers\"") |> should.be_true()
  string.contains(result, "\"total\"") |> should.be_true()
}

pub fn route_mcp_contains_tools_test() {
  let result = router.route("/api/mcp/status")
  string.contains(result, "\"MCP Server\"") |> should.be_true()
  string.contains(result, "\"tools\"") |> should.be_true()
  string.contains(result, "\"active_sessions\"") |> should.be_true()
}

pub fn route_kms_contains_checkpoints_test() {
  let result = router.route("/api/kms/catalog")
  string.contains(result, "\"KMS\"") |> should.be_true()
  string.contains(result, "\"total_keys\"") |> should.be_true()
  string.contains(result, "\"checkpoints\"") |> should.be_true()
}

pub fn route_telemetry_contains_otel_test() {
  let result = router.route("/api/telemetry/status")
  string.contains(result, "\"Telemetry\"") |> should.be_true()
  string.contains(result, "\"total_traces\"") |> should.be_true()
  string.contains(result, "\"log_level\"") |> should.be_true()
}

// =============================================================================
// Section 5: encode_health — ALL 4 HealthStatus variants
// =============================================================================

pub fn encode_health_healthy_test() {
  let result = router.encode_health(domain.Healthy) |> json.to_string()
  result |> should.equal("\"healthy\"")
}

pub fn encode_health_degraded_test() {
  let result =
    router.encode_health(domain.Degraded("high load")) |> json.to_string()
  string.contains(result, "\"degraded\"") |> should.be_true()
  string.contains(result, "\"high load\"") |> should.be_true()
}

pub fn encode_health_critical_test() {
  let result =
    router.encode_health(domain.Critical("node down")) |> json.to_string()
  string.contains(result, "\"critical\"") |> should.be_true()
  string.contains(result, "\"node down\"") |> should.be_true()
}

pub fn encode_health_unknown_test() {
  let result = router.encode_health(domain.Unknown) |> json.to_string()
  result |> should.equal("\"unknown\"")
}

// =============================================================================
// Section 6: Lustre Substrate — init, update, query functions
// =============================================================================

pub fn substrate_init_defaults_test() {
  let model = substrate.init()
  model.governor_action |> should.be_none()
  model.db_connections |> should.equal([])
  model.file_ops |> should.equal([])
}

pub fn substrate_update_governor_updated_test() {
  let model = substrate.init()
  let action =
    substrate.GovernorAction(name: "Maintain", state: "active", timestamp: 1000)
  let updated = substrate.update(model, substrate.GovernorUpdated(action))
  updated.governor_action |> should.be_some()
}

pub fn substrate_update_db_stats_received_test() {
  let model = substrate.init()
  let conn =
    substrate.DbConnection(
      id: "db1",
      database: "holon.db",
      status: "active",
      latency_ms: 2,
    )
  let updated = substrate.update(model, substrate.DbStatsReceived([conn]))
  list.length(updated.db_connections) |> should.equal(1)
}

pub fn substrate_update_refresh_noop_test() {
  let model = substrate.init()
  let updated = substrate.update(model, substrate.RefreshSubstrate)
  updated |> should.equal(model)
}

pub fn substrate_active_connections_test() {
  let conns = [
    substrate.DbConnection(
      id: "db1",
      database: "holon.db",
      status: "active",
      latency_ms: 2,
    ),
    substrate.DbConnection(
      id: "db2",
      database: "cache.db",
      status: "idle",
      latency_ms: 5,
    ),
    substrate.DbConnection(
      id: "db3",
      database: "log.db",
      status: "active",
      latency_ms: 1,
    ),
  ]
  let model =
    substrate.SubstrateModel(
      governor_action: substrate.init().governor_action,
      db_connections: conns,
      file_ops: [],
    )
  substrate.active_connections(model) |> list.length |> should.equal(2)
}

pub fn substrate_active_connections_empty_test() {
  let model = substrate.init()
  substrate.active_connections(model) |> should.equal([])
}

pub fn substrate_connection_count_test() {
  let conns = [
    substrate.DbConnection(
      id: "db1",
      database: "a.db",
      status: "active",
      latency_ms: 1,
    ),
    substrate.DbConnection(
      id: "db2",
      database: "b.db",
      status: "idle",
      latency_ms: 2,
    ),
  ]
  let model =
    substrate.SubstrateModel(
      governor_action: substrate.init().governor_action,
      db_connections: conns,
      file_ops: [],
    )
  substrate.connection_count(model) |> should.equal(2)
}

pub fn substrate_connection_count_zero_test() {
  let model = substrate.init()
  substrate.connection_count(model) |> should.equal(0)
}

// =============================================================================
// Section 7: Lustre Metabolic — init, update, query functions
// =============================================================================

pub fn metabolic_init_defaults_test() {
  let model = metabolic.init()
  model.set_point |> should.equal(0.5)
  model.energy |> should.equal(1.0)
  model.cpu_load |> should.equal(0.0)
  model.health |> should.equal(domain.Healthy)
}

pub fn metabolic_update_set_point_test() {
  let model = metabolic.init()
  let updated = metabolic.update(model, metabolic.SetPointUpdated(0.8))
  updated.set_point |> should.equal(0.8)
}

pub fn metabolic_update_energy_changed_test() {
  let model = metabolic.init()
  let updated = metabolic.update(model, metabolic.EnergyChanged(0.75))
  updated.energy |> should.equal(0.75)
}

pub fn metabolic_update_health_changed_test() {
  let model = metabolic.init()
  let updated =
    metabolic.update(
      model,
      metabolic.HealthChanged(domain.Degraded("high cpu")),
    )
  updated.health |> should.equal(domain.Degraded("high cpu"))
}

pub fn metabolic_update_health_to_critical_test() {
  let model = metabolic.init()
  let updated =
    metabolic.update(
      model,
      metabolic.HealthChanged(domain.Critical("memory overflow")),
    )
  updated.health |> should.equal(domain.Critical("memory overflow"))
}

pub fn metabolic_update_refresh_noop_test() {
  let model = metabolic.init()
  let updated = metabolic.update(model, metabolic.RefreshMetabolic)
  updated |> should.equal(model)
}

pub fn metabolic_energy_ratio_normal_test() {
  let model = metabolic.init()
  // energy=1.0, set_point=0.5 → ratio=2.0
  metabolic.energy_ratio(model) |> should.equal(2.0)
}

pub fn metabolic_energy_ratio_equal_test() {
  let model = metabolic.init()
  let updated =
    model
    |> metabolic.update(metabolic.SetPointUpdated(1.0))
    |> metabolic.update(metabolic.EnergyChanged(1.0))
  metabolic.energy_ratio(updated) |> should.equal(1.0)
}

pub fn metabolic_energy_ratio_zero_set_point_test() {
  let model = metabolic.init()
  let updated = metabolic.update(model, metabolic.SetPointUpdated(0.0))
  metabolic.energy_ratio(updated) |> should.equal(0.0)
}

pub fn metabolic_is_overloaded_false_test() {
  let model = metabolic.init()
  // cpu_load=0.0
  metabolic.is_overloaded(model) |> should.be_false()
}

pub fn metabolic_is_overloaded_true_test() {
  // Build a model with high cpu_load via MetabolicModel constructor
  let model =
    metabolic.MetabolicModel(
      set_point: 0.5,
      energy: 1.0,
      cpu_load: 0.95,
      health: domain.Healthy,
    )
  metabolic.is_overloaded(model) |> should.be_true()
}

pub fn metabolic_is_overloaded_at_threshold_test() {
  let model =
    metabolic.MetabolicModel(
      set_point: 0.5,
      energy: 1.0,
      cpu_load: 0.9,
      health: domain.Healthy,
    )
  // 0.9 is NOT >. 0.9, so should be False
  metabolic.is_overloaded(model) |> should.be_false()
}

// =============================================================================
// Section 8: Lustre Podman — init, update, query functions
// =============================================================================

pub fn podman_init_defaults_test() {
  let model = podman.init()
  model.containers |> should.equal([])
  model.images |> should.equal([])
  model.volumes |> should.equal([])
  model.networks |> should.equal([])
}

pub fn podman_update_containers_loaded_test() {
  let model = podman.init()
  let c =
    podman.Container(
      id: "c1",
      name: "zenoh-router-1",
      status: "running",
      image: "eclipse/zenoh:1.2.0",
    )
  let updated = podman.update(model, podman.ContainersLoaded([c]))
  list.length(updated.containers) |> should.equal(1)
}

pub fn podman_update_images_loaded_test() {
  let model = podman.init()
  let img =
    podman.Image(
      id: "img1",
      repository: "eclipse/zenoh",
      tag: "1.2.0",
      size_mb: 150,
    )
  let updated = podman.update(model, podman.ImagesLoaded([img]))
  list.length(updated.images) |> should.equal(1)
}

pub fn podman_update_start_container_noop_test() {
  let model = podman.init()
  let updated = podman.update(model, podman.StartContainer("c1"))
  updated |> should.equal(model)
}

pub fn podman_update_stop_container_noop_test() {
  let model = podman.init()
  let updated = podman.update(model, podman.StopContainer("c1"))
  updated |> should.equal(model)
}

pub fn podman_update_refresh_noop_test() {
  let model = podman.init()
  let updated = podman.update(model, podman.RefreshPodman)
  updated |> should.equal(model)
}

pub fn podman_running_containers_test() {
  let containers = [
    podman.Container(
      id: "c1",
      name: "router-1",
      status: "running",
      image: "zenoh:1.2",
    ),
    podman.Container(
      id: "c2",
      name: "router-2",
      status: "exited",
      image: "zenoh:1.2",
    ),
    podman.Container(
      id: "c3",
      name: "db-prod",
      status: "running",
      image: "db:21",
    ),
  ]
  let model =
    podman.PodmanModel(
      containers: containers,
      images: [],
      volumes: [],
      networks: [],
    )
  podman.running_containers(model) |> list.length |> should.equal(2)
}

pub fn podman_running_containers_empty_test() {
  let model = podman.init()
  podman.running_containers(model) |> should.equal([])
}

pub fn podman_container_count_test() {
  let containers = [
    podman.Container(id: "c1", name: "a", status: "running", image: "img:1"),
    podman.Container(id: "c2", name: "b", status: "exited", image: "img:2"),
  ]
  let model =
    podman.PodmanModel(
      containers: containers,
      images: [],
      volumes: [],
      networks: [],
    )
  podman.container_count(model) |> should.equal(2)
}

pub fn podman_container_count_zero_test() {
  let model = podman.init()
  podman.container_count(model) |> should.equal(0)
}

pub fn podman_running_count_test() {
  let containers = [
    podman.Container(id: "c1", name: "a", status: "running", image: "img:1"),
    podman.Container(id: "c2", name: "b", status: "exited", image: "img:2"),
    podman.Container(id: "c3", name: "c", status: "running", image: "img:3"),
  ]
  let model =
    podman.PodmanModel(
      containers: containers,
      images: [],
      volumes: [],
      networks: [],
    )
  podman.running_count(model) |> should.equal(2)
}

pub fn podman_running_count_zero_test() {
  let model = podman.init()
  podman.running_count(model) |> should.equal(0)
}

// =============================================================================
// Section 9: Lustre MCP — init, update, query functions
// =============================================================================

pub fn mcp_init_defaults_test() {
  let model = mcp.init()
  model.tools |> should.equal([])
  model.active_sessions |> should.equal([])
  model.server_status |> should.equal(mcp.Stopped)
}

pub fn mcp_update_tools_loaded_test() {
  let model = mcp.init()
  let tool =
    mcp.McpTool(
      name: "planning_query",
      description: "Query tasks",
      enabled: True,
    )
  let updated = mcp.update(model, mcp.ToolsLoaded([tool]))
  list.length(updated.tools) |> should.equal(1)
}

pub fn mcp_update_session_started_test() {
  let model = mcp.init()
  let session = mcp.McpSession(id: "s1", client: "opencode", started_at: 1000)
  let updated = mcp.update(model, mcp.SessionStarted(session))
  list.length(updated.active_sessions) |> should.equal(1)
}

pub fn mcp_update_session_started_prepends_test() {
  let model = mcp.init()
  let s1 = mcp.McpSession(id: "s1", client: "opencode", started_at: 1000)
  let s2 = mcp.McpSession(id: "s2", client: "gemini", started_at: 2000)
  let updated =
    model
    |> mcp.update(mcp.SessionStarted(s1))
    |> mcp.update(mcp.SessionStarted(s2))
  list.length(updated.active_sessions) |> should.equal(2)
}

pub fn mcp_update_session_ended_test() {
  let model = mcp.init()
  let session = mcp.McpSession(id: "s1", client: "opencode", started_at: 1000)
  let updated =
    model
    |> mcp.update(mcp.SessionStarted(session))
    |> mcp.update(mcp.SessionEnded("s1"))
  updated.active_sessions |> should.equal([])
}

pub fn mcp_update_session_ended_nonexistent_test() {
  let model = mcp.init()
  let updated = mcp.update(model, mcp.SessionEnded("nonexistent"))
  updated.active_sessions |> should.equal([])
}

pub fn mcp_update_refresh_noop_test() {
  let model = mcp.init()
  let updated = mcp.update(model, mcp.RefreshMcp)
  updated |> should.equal(model)
}

pub fn mcp_enabled_tools_test() {
  let tools = [
    mcp.McpTool(name: "a", description: "desc a", enabled: True),
    mcp.McpTool(name: "b", description: "desc b", enabled: False),
    mcp.McpTool(name: "c", description: "desc c", enabled: True),
  ]
  let model =
    mcp.McpModel(tools: tools, active_sessions: [], server_status: mcp.Stopped)
  mcp.enabled_tools(model) |> list.length |> should.equal(2)
}

pub fn mcp_enabled_tools_none_enabled_test() {
  let tools = [
    mcp.McpTool(name: "a", description: "desc a", enabled: False),
    mcp.McpTool(name: "b", description: "desc b", enabled: False),
  ]
  let model =
    mcp.McpModel(tools: tools, active_sessions: [], server_status: mcp.Stopped)
  mcp.enabled_tools(model) |> should.equal([])
}

pub fn mcp_enabled_tools_empty_test() {
  let model = mcp.init()
  mcp.enabled_tools(model) |> should.equal([])
}

pub fn mcp_session_count_test() {
  let model = mcp.init()
  let s1 = mcp.McpSession(id: "s1", client: "a", started_at: 1000)
  let s2 = mcp.McpSession(id: "s2", client: "b", started_at: 2000)
  let updated =
    model
    |> mcp.update(mcp.SessionStarted(s1))
    |> mcp.update(mcp.SessionStarted(s2))
  mcp.session_count(updated) |> should.equal(2)
}

pub fn mcp_session_count_zero_test() {
  let model = mcp.init()
  mcp.session_count(model) |> should.equal(0)
}

// =============================================================================
// Section 10: Lustre KMS — init, update, query functions
// =============================================================================

pub fn kms_init_defaults_test() {
  let model = kms.init()
  model.checkpoints |> should.equal([])
  model.total_keys |> should.equal(0)
  model.active_keys |> should.equal(0)
}

pub fn kms_update_checkpoints_loaded_test() {
  let model = kms.init()
  let cp =
    kms.Checkpoint(
      id: "cp1",
      label: "Release 21.3",
      timestamp: 1000,
      key_count: 5,
    )
  let updated = kms.update(model, kms.CheckpointsLoaded([cp]))
  list.length(updated.checkpoints) |> should.equal(1)
}

pub fn kms_update_checkpoints_loaded_multiple_test() {
  let model = kms.init()
  let cp1 =
    kms.Checkpoint(
      id: "cp1",
      label: "Release 21.3",
      timestamp: 1000,
      key_count: 5,
    )
  let cp2 =
    kms.Checkpoint(
      id: "cp2",
      label: "Release 21.4",
      timestamp: 2000,
      key_count: 3,
    )
  let updated = kms.update(model, kms.CheckpointsLoaded([cp1, cp2]))
  list.length(updated.checkpoints) |> should.equal(2)
}

pub fn kms_update_key_rotated_noop_test() {
  let model = kms.init()
  let updated = kms.update(model, kms.KeyRotated("key-123"))
  updated |> should.equal(model)
}

pub fn kms_update_refresh_noop_test() {
  let model = kms.init()
  let updated = kms.update(model, kms.RefreshKms)
  updated |> should.equal(model)
}

pub fn kms_latest_checkpoint_empty_test() {
  let model = kms.init()
  kms.latest_checkpoint(model) |> should.be_error()
}

pub fn kms_latest_checkpoint_returns_first_test() {
  let cp1 =
    kms.Checkpoint(id: "cp1", label: "First", timestamp: 1000, key_count: 5)
  let cp2 =
    kms.Checkpoint(id: "cp2", label: "Second", timestamp: 2000, key_count: 3)
  let model =
    kms.KmsModel(checkpoints: [cp1, cp2], total_keys: 8, active_keys: 6)
  case kms.latest_checkpoint(model) {
    Ok(cp) -> cp.id |> should.equal("cp1")
    Error(_) -> should.fail()
  }
}

pub fn kms_checkpoint_count_test() {
  let cps = [
    kms.Checkpoint(id: "a", label: "A", timestamp: 1, key_count: 1),
    kms.Checkpoint(id: "b", label: "B", timestamp: 2, key_count: 2),
    kms.Checkpoint(id: "c", label: "C", timestamp: 3, key_count: 3),
  ]
  let model = kms.KmsModel(checkpoints: cps, total_keys: 6, active_keys: 4)
  kms.checkpoint_count(model) |> should.equal(3)
}

pub fn kms_checkpoint_count_zero_test() {
  let model = kms.init()
  kms.checkpoint_count(model) |> should.equal(0)
}

// =============================================================================
// Section 11: Lustre Telemetry — init, update, query functions
// =============================================================================

pub fn telemetry_init_defaults_test() {
  let model = lustre_telemetry.init()
  model.spans |> should.equal([])
  model.metrics |> should.equal([])
  model.log_level |> should.equal(lustre_telemetry.Info)
  model.active_traces |> should.equal(0)
}

pub fn telemetry_update_span_received_test() {
  let model = lustre_telemetry.init()
  let span =
    lustre_telemetry.Span(
      trace_id: "t1",
      span_id: "sp1",
      name: "http.request",
      duration_us: 1200,
      status: "ok",
    )
  let updated =
    lustre_telemetry.update(model, lustre_telemetry.SpanReceived(span))
  list.length(updated.spans) |> should.equal(1)
}

pub fn telemetry_update_span_prepends_test() {
  let model = lustre_telemetry.init()
  let sp1 =
    lustre_telemetry.Span(
      trace_id: "t1",
      span_id: "sp1",
      name: "request",
      duration_us: 100,
      status: "ok",
    )
  let sp2 =
    lustre_telemetry.Span(
      trace_id: "t1",
      span_id: "sp2",
      name: "db.query",
      duration_us: 50,
      status: "ok",
    )
  let updated =
    model
    |> lustre_telemetry.update(lustre_telemetry.SpanReceived(sp1))
    |> lustre_telemetry.update(lustre_telemetry.SpanReceived(sp2))
  list.length(updated.spans) |> should.equal(2)
  // Most recent span is first
  case updated.spans {
    [first, ..] -> first.span_id |> should.equal("sp2")
    _ -> should.fail()
  }
}

pub fn telemetry_update_metric_updated_test() {
  let model = lustre_telemetry.init()
  let metric =
    lustre_telemetry.Metric(
      name: "cpu_percent",
      value: 32.5,
      unit: "%",
      timestamp: 1000,
    )
  let updated =
    lustre_telemetry.update(model, lustre_telemetry.MetricUpdated(metric))
  list.length(updated.metrics) |> should.equal(1)
}

pub fn telemetry_update_set_log_level_test() {
  let model = lustre_telemetry.init()
  let updated =
    lustre_telemetry.update(
      model,
      lustre_telemetry.SetLogLevel(lustre_telemetry.Debug),
    )
  updated.log_level |> should.equal(lustre_telemetry.Debug)
}

pub fn telemetry_update_set_log_level_warning_test() {
  let model = lustre_telemetry.init()
  let updated =
    lustre_telemetry.update(
      model,
      lustre_telemetry.SetLogLevel(lustre_telemetry.Warning),
    )
  updated.log_level |> should.equal(lustre_telemetry.Warning)
}

pub fn telemetry_update_set_log_level_error_test() {
  let model = lustre_telemetry.init()
  let updated =
    lustre_telemetry.update(
      model,
      lustre_telemetry.SetLogLevel(lustre_telemetry.Error),
    )
  updated.log_level |> should.equal(lustre_telemetry.Error)
}

pub fn telemetry_update_refresh_noop_test() {
  let model = lustre_telemetry.init()
  let updated =
    lustre_telemetry.update(model, lustre_telemetry.RefreshTelemetry)
  updated |> should.equal(model)
}

pub fn telemetry_log_level_to_string_debug_test() {
  lustre_telemetry.log_level_to_string(lustre_telemetry.Debug)
  |> should.equal("DEBUG")
}

pub fn telemetry_log_level_to_string_info_test() {
  lustre_telemetry.log_level_to_string(lustre_telemetry.Info)
  |> should.equal("INFO")
}

pub fn telemetry_log_level_to_string_warning_test() {
  lustre_telemetry.log_level_to_string(lustre_telemetry.Warning)
  |> should.equal("WARNING")
}

pub fn telemetry_log_level_to_string_error_test() {
  lustre_telemetry.log_level_to_string(lustre_telemetry.Error)
  |> should.equal("ERROR")
}

pub fn telemetry_recent_spans_empty_test() {
  let model = lustre_telemetry.init()
  lustre_telemetry.recent_spans(model, 5) |> should.equal([])
}

pub fn telemetry_recent_spans_takes_n_test() {
  let sp1 =
    lustre_telemetry.Span(
      trace_id: "t1",
      span_id: "s1",
      name: "a",
      duration_us: 10,
      status: "ok",
    )
  let sp2 =
    lustre_telemetry.Span(
      trace_id: "t1",
      span_id: "s2",
      name: "b",
      duration_us: 20,
      status: "ok",
    )
  let sp3 =
    lustre_telemetry.Span(
      trace_id: "t1",
      span_id: "s3",
      name: "c",
      duration_us: 30,
      status: "ok",
    )
  let model =
    lustre_telemetry.init()
    |> lustre_telemetry.update(lustre_telemetry.SpanReceived(sp1))
    |> lustre_telemetry.update(lustre_telemetry.SpanReceived(sp2))
    |> lustre_telemetry.update(lustre_telemetry.SpanReceived(sp3))
  // Take 2 of 3
  lustre_telemetry.recent_spans(model, 2) |> list.length |> should.equal(2)
  // Take more than available — returns all
  lustre_telemetry.recent_spans(model, 10) |> list.length |> should.equal(3)
}

pub fn telemetry_metric_by_name_found_test() {
  let m1 =
    lustre_telemetry.Metric(
      name: "cpu_percent",
      value: 32.5,
      unit: "%",
      timestamp: 1000,
    )
  let m2 =
    lustre_telemetry.Metric(
      name: "memory_mb",
      value: 8192.0,
      unit: "MB",
      timestamp: 1000,
    )
  let model =
    lustre_telemetry.init()
    |> lustre_telemetry.update(lustre_telemetry.MetricUpdated(m1))
    |> lustre_telemetry.update(lustre_telemetry.MetricUpdated(m2))
  case lustre_telemetry.metric_by_name(model, "cpu_percent") {
    Ok(metric) -> metric.value |> should.equal(32.5)
    Error(_) -> should.fail()
  }
}

pub fn telemetry_metric_by_name_not_found_test() {
  let model = lustre_telemetry.init()
  lustre_telemetry.metric_by_name(model, "nonexistent") |> should.be_error()
}

// =============================================================================
// Section 12: Router default_port constant
// =============================================================================

pub fn router_default_port_test() {
  router.default_port |> should.equal(4100)
}

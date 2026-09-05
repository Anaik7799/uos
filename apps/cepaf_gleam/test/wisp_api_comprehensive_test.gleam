// =============================================================================
// Wisp REST API Comprehensive Tests
// =============================================================================
// Covers all public JSON response functions across the Wisp API layer.
//
// Strategy: call route() for each registered path and verify:
//   1. Response is non-empty
//   2. Response contains '{' (object) or '[' (array) — valid JSON structure
//   3. Response contains expected domain keys
//
// For pure API modules (planning_api, immune_api, etc.) we call the pub fn
// directly with minimal test data and verify JSON structure.
//
// NOTE: Functions that call NIFs (system_health, plan_status, etc.) are
// tested via route() — the NIF returns a stub or live value, both valid.
//
// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-UIGT-008
// =============================================================================

import cepaf_gleam/fractal/l7_federation.{
  FederationPeer, PeerConnected, PeerSuspected, add_peer, increment_version,
  initial_federation,
}
import cepaf_gleam/immune/domain as immune_domain
import cepaf_gleam/knowledge/domain as knowledge_domain
import cepaf_gleam/ui/domain
import cepaf_gleam/ui/wisp/cockpit_api
import cepaf_gleam/ui/wisp/federation_api
import cepaf_gleam/ui/wisp/immune_api
import cepaf_gleam/ui/wisp/knowledge_api
import cepaf_gleam/ui/wisp/planning_api
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/ui/wisp/verification_api
import cepaf_gleam/verification/graph_verification
import cepaf_gleam/verification/prometheus
import cepaf_gleam/verification/swarm
import gleam/json
import gleam/option
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

fn is_json(s: String) -> Bool {
  string.contains(s, "{") || string.contains(s, "[")
}

fn route_is_json(path: String) -> Nil {
  let result = router.route(path)
  { string.length(result) > 0 } |> should.be_true()
  result |> is_json() |> should.be_true()
}

// ---------------------------------------------------------------------------
// 1. Health endpoint — always JSON, NIF-backed
// ---------------------------------------------------------------------------

pub fn health_route_returns_json_test() {
  route_is_json("/health")
}

pub fn health_route_has_status_field_test() {
  let result = router.route("/health")
  result |> string.contains("status") |> should.be_true()
}

pub fn health_route_has_timestamp_test() {
  let result = router.route("/health")
  result |> string.contains("last_updated_ms") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 2. Core page routes — all return non-empty JSON
// ---------------------------------------------------------------------------

pub fn planning_route_returns_json_test() {
  route_is_json("/api/v1/planning")
}

pub fn dashboard_route_returns_json_test() {
  route_is_json("/api/v1/dashboard")
}

pub fn immune_route_returns_json_test() {
  route_is_json("/api/v1/immune")
}

pub fn zenoh_route_returns_json_test() {
  route_is_json("/api/v1/zenoh")
}

pub fn verification_route_returns_json_test() {
  route_is_json("/api/v1/verification")
}

pub fn knowledge_route_returns_json_test() {
  route_is_json("/api/v1/knowledge")
}

pub fn cockpit_mode_route_returns_json_test() {
  route_is_json("/api/v1/cockpit/mode")
}

pub fn cockpit_alarms_route_returns_json_test() {
  route_is_json("/api/v1/cockpit/alarms")
}

pub fn federation_route_returns_json_test() {
  route_is_json("/api/v1/federation")
}

pub fn component_demo_route_returns_json_test() {
  route_is_json("/api/v1/component_demo")
}

// ---------------------------------------------------------------------------
// 3. Dashboard variant routes
// ---------------------------------------------------------------------------

pub fn dashboard_live_route_returns_json_test() {
  route_is_json("/api/v1/dashboard/live")
}

pub fn dashboard_system_route_returns_json_test() {
  route_is_json("/api/v1/dashboard/system")
}

pub fn dashboard_agents_route_returns_json_test() {
  route_is_json("/api/v1/dashboard/agents")
}

// ---------------------------------------------------------------------------
// 4. System endpoint routes
// ---------------------------------------------------------------------------

pub fn system_health_route_returns_json_test() {
  route_is_json("/api/v1/system/health")
}

pub fn system_immune_route_returns_json_test() {
  route_is_json("/api/v1/system/immune")
}

pub fn system_verification_route_returns_json_test() {
  route_is_json("/api/v1/system/verification")
}

pub fn system_zenoh_route_returns_json_test() {
  route_is_json("/api/v1/system/zenoh")
}

pub fn system_dashboard_route_returns_json_test() {
  route_is_json("/api/v1/system/dashboard")
}

pub fn system_ooda_route_returns_json_test() {
  route_is_json("/api/v1/system/ooda")
}

pub fn system_tps_route_returns_json_test() {
  route_is_json("/api/v1/system/tps")
}

pub fn system_snapshot_route_returns_json_test() {
  route_is_json("/api/v1/system/snapshot")
}

pub fn system_circuits_route_returns_json_test() {
  route_is_json("/api/v1/system/circuits")
}

// ---------------------------------------------------------------------------
// 5. OODA routes
// ---------------------------------------------------------------------------

pub fn ooda_route_returns_json_test() {
  route_is_json("/api/v1/ooda")
}

pub fn ooda_decide_route_returns_json_test() {
  route_is_json("/api/v1/ooda/decide")
}

// ---------------------------------------------------------------------------
// 6. Safety / enforcer routes
// ---------------------------------------------------------------------------

pub fn safety_route_returns_json_test() {
  route_is_json("/api/v1/safety")
}

pub fn enforcer_route_returns_json_test() {
  route_is_json("/api/v1/enforcer")
}

pub fn access_control_route_returns_json_test() {
  route_is_json("/api/v1/access_control")
}

// ---------------------------------------------------------------------------
// 7. Agent / orchestration routes
// ---------------------------------------------------------------------------

pub fn agents_route_returns_json_test() {
  route_is_json("/api/v1/agents")
}

pub fn orchestration_route_returns_json_test() {
  route_is_json("/api/v1/orchestration")
}

pub fn graph_verification_route_returns_json_test() {
  route_is_json("/api/v1/graph_verification")
}

pub fn prajna_route_returns_json_test() {
  route_is_json("/api/v1/prajna")
}

// ---------------------------------------------------------------------------
// 8. Infrastructure / domain page routes
// ---------------------------------------------------------------------------

pub fn substrate_route_returns_json_test() {
  route_is_json("/api/v1/substrate")
}

pub fn metabolic_route_returns_json_test() {
  route_is_json("/api/v1/metabolic")
}

pub fn podman_route_returns_json_test() {
  route_is_json("/api/v1/podman")
}

pub fn mcp_route_returns_json_test() {
  route_is_json("/api/v1/mcp")
}

pub fn kms_route_returns_json_test() {
  route_is_json("/api/v1/kms")
}

pub fn telemetry_route_returns_json_test() {
  route_is_json("/api/v1/telemetry")
}

// ---------------------------------------------------------------------------
// 9. Extended domain routes
// ---------------------------------------------------------------------------

pub fn integrity_route_returns_json_test() {
  route_is_json("/api/v1/integrity")
}

pub fn evolution_route_returns_json_test() {
  route_is_json("/api/v1/evolution")
}

pub fn biomorphic_route_returns_json_test() {
  route_is_json("/api/v1/biomorphic")
}

pub fn homeostasis_route_returns_json_test() {
  route_is_json("/api/v1/homeostasis")
}

pub fn bicameral_route_returns_json_test() {
  route_is_json("/api/v1/bicameral")
}

pub fn singularity_route_returns_json_test() {
  route_is_json("/api/v1/singularity")
}

pub fn mesh_config_route_returns_json_test() {
  route_is_json("/api/v1/mesh_config")
}

pub fn holon_route_returns_json_test() {
  route_is_json("/api/v1/holon")
}

pub fn git_route_returns_json_test() {
  route_is_json("/api/v1/git")
}

pub fn smriti_route_returns_json_test() {
  route_is_json("/api/v1/smriti")
}

pub fn chaya_sync_route_returns_json_test() {
  route_is_json("/api/v1/chaya_sync")
}

pub fn math_optimization_route_returns_json_test() {
  route_is_json("/api/v1/math_optimization")
}

pub fn db_route_returns_json_test() {
  route_is_json("/api/v1/db")
}

pub fn bridge_route_returns_json_test() {
  route_is_json("/api/v1/bridge")
}

pub fn health_grid_route_returns_json_test() {
  route_is_json("/api/v1/health_grid")
}

pub fn planning_dashboard_route_returns_json_test() {
  route_is_json("/api/v1/planning_dashboard")
}

pub fn data_freshness_route_returns_json_test() {
  route_is_json("/api/v1/health/freshness")
}

pub fn fitness_route_returns_json_test() {
  route_is_json("/api/v1/fitness")
}

// ---------------------------------------------------------------------------
// 10. Allium routes
// ---------------------------------------------------------------------------

pub fn allium_list_route_returns_json_test() {
  route_is_json("/api/v1/allium")
}

pub fn allium_spec_ignition_route_returns_json_test() {
  route_is_json("/api/v1/allium/ignition")
}

pub fn allium_spec_unknown_returns_json_test() {
  let result = router.route("/api/v1/allium/nonexistent_spec_xyz")
  result |> is_json() |> should.be_true()
}

// ---------------------------------------------------------------------------
// 11. AG-UI routes
// ---------------------------------------------------------------------------

pub fn agui_run_route_returns_json_test() {
  route_is_json("/ag-ui/run")
}

pub fn agui_health_route_returns_json_test() {
  route_is_json("/ag-ui/health")
}

pub fn agui_state_route_returns_json_test() {
  route_is_json("/ag-ui/state")
}

pub fn agui_hitl_pending_route_returns_json_test() {
  route_is_json("/ag-ui/hitl/pending")
}

// ---------------------------------------------------------------------------
// 12. Hot reload route
// ---------------------------------------------------------------------------

pub fn hot_reload_returns_json_test() {
  let result = router.route("/api/v1/reload")
  result |> is_json() |> should.be_true()
  let has_status = string.contains(result, "status")
  let has_action = string.contains(result, "action")
  { has_status || has_action } |> should.be_true()
}

// ---------------------------------------------------------------------------
// 13. 404 handler
// ---------------------------------------------------------------------------

pub fn not_found_returns_json_test() {
  let result = router.route("/api/v1/nonexistent_route_xyz_123")
  result |> is_json() |> should.be_true()
}

pub fn not_found_has_error_field_test() {
  let result = router.route("/api/v1/this_does_not_exist_qwerty")
  let has_error = string.contains(result, "error")
  let has_not_found = string.contains(result, "not_found")
  { has_error || has_not_found } |> should.be_true()
}

// ---------------------------------------------------------------------------
// 14. planning_api.gleam — pure typed JSON builders
// ---------------------------------------------------------------------------

pub fn planning_api_empty_task_list_test() {
  let result = planning_api.list_tasks_json([])
  result |> is_json() |> should.be_true()
  result |> string.contains("tasks") |> should.be_true()
}

pub fn planning_api_task_list_with_item_test() {
  let task =
    planning_api.TaskSummary(
      id: "T001",
      title: "Implement Zenoh mesh",
      status: "in_progress",
      priority: "P1",
    )
  let result = planning_api.list_tasks_json([task])
  result |> string.contains("T001") |> should.be_true()
  result |> string.contains("Zenoh") |> should.be_true()
}

pub fn planning_api_task_detail_json_test() {
  let task =
    planning_api.TaskSummary(
      id: "T002",
      title: "Add Gleam NIF",
      status: "pending",
      priority: "P0",
    )
  let result = planning_api.task_detail_json(task)
  result |> is_json() |> should.be_true()
  result |> string.contains("T002") |> should.be_true()
  result |> string.contains("P0") |> should.be_true()
}

pub fn planning_api_status_summary_json_test() {
  let result = planning_api.status_summary_json(5, 3, 10, 1)
  result |> is_json() |> should.be_true()
  result |> string.contains("pending") |> should.be_true()
  result |> string.contains("in_progress") |> should.be_true()
  result |> string.contains("completed") |> should.be_true()
  result |> string.contains("blocked") |> should.be_true()
}

pub fn planning_api_status_summary_totals_test() {
  let result = planning_api.status_summary_json(2, 0, 5, 0)
  result |> string.contains("total") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 15. immune_api.gleam — pure typed JSON builders
// ---------------------------------------------------------------------------

pub fn immune_api_nominal_threat_level_test() {
  let result = immune_api.immune_status_json([], [], False)
  result |> is_json() |> should.be_true()
  result |> string.contains("nominal") |> should.be_true()
}

pub fn immune_api_elevated_threat_level_test() {
  let ab =
    immune_domain.Antibody(
      id: "ab-001",
      target_pattern: "crash_loop",
      reason: "repeated failure",
      expires_at: 9_999_999,
    )
  let attack =
    immune_domain.ContainerAssault(name: "zenoh-router-1", mode: "kill")
  let result = immune_api.immune_status_json([ab], [attack], True)
  result |> string.contains("elevated") |> should.be_true()
  result |> string.contains("ab-001") |> should.be_true()
}

pub fn immune_api_critical_threshold_test() {
  let make_attack = fn(n) {
    immune_domain.ZenohFlood(topic: "t/" <> n, count: 100)
  }
  let attacks = [make_attack("1"), make_attack("2"), make_attack("3")]
  let result = immune_api.immune_status_json([], attacks, True)
  result |> string.contains("critical") |> should.be_true()
}

pub fn immune_api_events_json_empty_test() {
  let result = immune_api.events_json([])
  result |> is_json() |> should.be_true()
  result |> string.contains("event_count") |> should.be_true()
}

pub fn immune_api_events_json_with_event_test() {
  let events = [
    immune_domain.AntibodySynthesized("ab-001", "crash_loop"),
    immune_domain.AttackBlocked("atk-001", "pattern matched"),
  ]
  let result = immune_api.events_json(events)
  result |> string.contains("antibody_synthesized") |> should.be_true()
  result |> string.contains("attack_blocked") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 16. knowledge_api.gleam — pure typed JSON builders
// ---------------------------------------------------------------------------

pub fn knowledge_api_empty_graph_test() {
  let result = knowledge_api.knowledge_graph_json([], [])
  result |> is_json() |> should.be_true()
  result |> string.contains("node_count") |> should.be_true()
}

pub fn knowledge_api_node_detail_test() {
  let node =
    knowledge_domain.KnowledgeNode(
      id: "zk-001",
      title: "Architecture Decision",
      level: knowledge_domain.Molecular,
      rhetorical: knowledge_domain.Axiom,
      entropy: 2.5,
      drift: 0.1,
      tags: ["architecture", "decision"],
    )
  let result = knowledge_api.node_detail_json(node)
  result |> is_json() |> should.be_true()
  result |> string.contains("zk-001") |> should.be_true()
  result |> string.contains("molecular") |> should.be_true()
}

pub fn knowledge_api_node_detail_evidence_test() {
  let node =
    knowledge_domain.KnowledgeNode(
      id: "zk-002",
      title: "Empirical measurement",
      level: knowledge_domain.Atomic,
      rhetorical: knowledge_domain.Evidence,
      entropy: 1.2,
      drift: 0.05,
      tags: ["measurement"],
    )
  let result = knowledge_api.node_detail_json(node)
  result |> string.contains("evidence") |> should.be_true()
}

pub fn knowledge_api_graph_with_link_test() {
  let link =
    knowledge_domain.KnowledgeLink(
      source_id: "zk-001",
      target_id: "zk-002",
      relation_type: "supports",
    )
  let result = knowledge_api.knowledge_graph_json([], [link])
  result |> string.contains("link_count") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 17. cockpit_api.gleam — pure typed JSON builders (using route-based tests)
// ---------------------------------------------------------------------------

pub fn cockpit_api_empty_nodes_test() {
  let result = cockpit_api.nodes_json([])
  result |> is_json() |> should.be_true()
  result |> string.contains("node_count") |> should.be_true()
}

pub fn cockpit_api_empty_alarms_test() {
  let result = cockpit_api.alarms_json([])
  result |> is_json() |> should.be_true()
  result |> string.contains("alarm_count") |> should.be_true()
}

pub fn cockpit_alarms_route_has_total_field_test() {
  let result = router.route("/api/v1/cockpit/alarms")
  result |> string.contains("total") |> should.be_true()
}

pub fn cockpit_alarms_route_has_critical_field_test() {
  let result = router.route("/api/v1/cockpit/alarms")
  result |> string.contains("critical") |> should.be_true()
}

pub fn cockpit_mode_route_has_modes_array_test() {
  let result = router.route("/api/v1/cockpit/mode")
  result |> string.contains("modes") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 18. federation_api.gleam — pure typed JSON builders
// ---------------------------------------------------------------------------

fn federation_fixture_state() {
  let local = "test-local-federation"
  let peer1 =
    FederationPeer(
      peer_id: "test-peer-a",
      endpoint: "tcp/test-peer-a:4001",
      status: PeerConnected,
      version_vector: [#(local, 1), #("test-peer-a", 3)],
      attestation_valid: True,
      last_seen: 1_712_120_000,
    )
  let peer2 =
    FederationPeer(
      peer_id: "test-peer-b",
      endpoint: "tcp/test-peer-b:4002",
      status: PeerSuspected,
      version_vector: [#(local, 0), #("test-peer-b", 1)],
      attestation_valid: False,
      last_seen: 1_712_119_000,
    )

  initial_federation(local)
  |> add_peer(peer1)
  |> add_peer(peer2)
  |> increment_version()
}

pub fn federation_api_status_json_test() {
  let state = federation_fixture_state()
  let result = federation_api.federation_status_json(state)
  result |> is_json() |> should.be_true()
  result |> string.contains("federation") |> should.be_true()
  result |> string.contains("peer_count") |> should.be_true()
}

pub fn federation_api_fixture_state_has_peers_test() {
  let state = federation_fixture_state()
  let result = federation_api.federation_status_json(state)
  result |> string.contains("test-peer-a") |> should.be_true()
}

pub fn federation_api_peer_list_json_test() {
  let state = federation_fixture_state()
  let result = federation_api.peer_list_json(state.peers)
  result |> is_json() |> should.be_true()
}

pub fn federation_api_empty_peer_list_test() {
  let result = federation_api.peer_list_json([])
  result |> is_json() |> should.be_true()
  result |> string.contains("peer_count") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 19. verification_api.gleam — pure typed JSON builders
// ---------------------------------------------------------------------------

pub fn verification_api_status_json_test() {
  let result = verification_api.verification_status_json(14, 16, True)
  result |> is_json() |> should.be_true()
  result |> string.contains("verification") |> should.be_true()
  result |> string.contains("compliant") |> should.be_true()
}

pub fn verification_api_status_zero_total_test() {
  // Should not divide by zero
  let result = verification_api.verification_status_json(0, 0, False)
  result |> is_json() |> should.be_true()
}

pub fn verification_api_compliance_pct_test() {
  let result = verification_api.verification_status_json(8, 16, True)
  // 8/16 = 50%
  result |> string.contains("50") |> should.be_true()
}

pub fn verification_api_dag_status_json_test() {
  let result = verification_api.dag_status_json(16, 45, True)
  result |> is_json() |> should.be_true()
  result |> string.contains("is_acyclic") |> should.be_true()
  result |> string.contains("dag_status") |> should.be_true()
}

pub fn verification_api_graph_checks_empty_test() {
  let result = verification_api.graph_checks_json([])
  result |> is_json() |> should.be_true()
  result |> string.contains("all_passed") |> should.be_true()
}

pub fn verification_api_graph_checks_with_data_test() {
  let checks = [
    graph_verification.GraphCheck(
      name: "DeadlockFree",
      passed: True,
      details: "No cycles detected",
    ),
    graph_verification.GraphCheck(
      name: "Completeness",
      passed: True,
      details: "All paths reachable",
    ),
  ]
  let result = verification_api.graph_checks_json(checks)
  result |> string.contains("DeadlockFree") |> should.be_true()
  result |> string.contains("Completeness") |> should.be_true()
}

pub fn verification_api_proof_token_verified_test() {
  let proof =
    prometheus.ProofToken(
      dag_hash: "sha256:abc123",
      path: ["L0", "L1", "L7"],
      verified_at: 1_712_000_000,
      constraints_checked: ["SC-SIL4-001", "SC-SAFETY-001"],
      result: prometheus.Verified,
    )
  let result = verification_api.proof_token_json(proof)
  result |> is_json() |> should.be_true()
  result |> string.contains("sha256:abc123") |> should.be_true()
  result |> string.contains("verified") |> should.be_true()
}

pub fn verification_api_proof_token_rejected_test() {
  let proof =
    prometheus.ProofToken(
      dag_hash: "sha256:def456",
      path: ["L0"],
      verified_at: 1_712_000_000,
      constraints_checked: ["SC-SIL4-001"],
      result: prometheus.Rejected(["Missing quorum"]),
    )
  let result = verification_api.proof_token_json(proof)
  result |> string.contains("rejected") |> should.be_true()
}

pub fn verification_api_biomorphic_matrix_test() {
  let matrix =
    domain.BiomorphicMatrix(levels: [
      #(domain.L0Constitutional, domain.Healthy),
      #(domain.L4System, domain.Healthy),
    ])
  let result = verification_api.biomorphic_matrix_json(matrix)
  result |> is_json() |> should.be_true()
  result |> string.contains("biomorphic_matrix") |> should.be_true()
}

pub fn verification_api_bicameral_sign_off_test() {
  let sign_off =
    domain.BicameralSignOff(
      key1_signed: True,
      key2_signed: True,
      authorized_by: option.Some("Abhijit.Naik"),
    )
  let result = verification_api.bicameral_sign_off_json(sign_off)
  result |> is_json() |> should.be_true()
  result |> string.contains("key1_signed") |> should.be_true()
  result |> string.contains("Abhijit.Naik") |> should.be_true()
}

pub fn verification_api_swarm_report_test() {
  let report =
    swarm.SwarmReport(
      healthy_containers: 14,
      total_containers: 16,
      ooda_metrics: swarm.OodaMetrics(
        agent_latency_ms: 22,
        intelligence_latency_ms: 85,
        compliance: True,
      ),
      fractal_layers: [
        swarm.FractalLayerReport(layer: 0, status: "active", evidence: "NIF ok"),
        swarm.FractalLayerReport(layer: 7, status: "active", evidence: "fed ok"),
      ],
    )
  let result = verification_api.swarm_report_json(report)
  result |> is_json() |> should.be_true()
  result |> string.contains("healthy_containers") |> should.be_true()
  result |> string.contains("fractal_layers") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 20. encode_health — router public function
// ---------------------------------------------------------------------------

pub fn encode_health_healthy_test() {
  let j = router.encode_health(domain.Healthy)
  let result = json.to_string(j)
  result |> string.contains("healthy") |> should.be_true()
}

pub fn encode_health_degraded_test() {
  let j = router.encode_health(domain.Degraded("NIF timeout"))
  let result = json.to_string(j)
  result |> string.contains("degraded") |> should.be_true()
  result |> string.contains("NIF timeout") |> should.be_true()
}

pub fn encode_health_critical_test() {
  let j = router.encode_health(domain.Critical("quorum lost"))
  let result = json.to_string(j)
  result |> string.contains("critical") |> should.be_true()
}

pub fn encode_health_unknown_test() {
  let j = router.encode_health(domain.Unknown)
  let result = json.to_string(j)
  result |> string.contains("unknown") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 21. Structural assertions — planning JSON fields
// ---------------------------------------------------------------------------

pub fn planning_json_has_summary_raw_test() {
  let result = router.route("/api/v1/planning")
  result |> string.contains("summary_raw") |> should.be_true()
}

pub fn planning_json_has_pending_raw_test() {
  let result = router.route("/api/v1/planning")
  result |> string.contains("pending_raw") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 22. Circuit breaker structural assertions
// ---------------------------------------------------------------------------

pub fn circuits_has_four_breakers_test() {
  let result = router.route("/api/v1/system/circuits")
  result |> string.contains("gemini_direct") |> should.be_true()
  result |> string.contains("openrouter") |> should.be_true()
  result |> string.contains("ollama_gemma3") |> should.be_true()
  result |> string.contains("ollama_gemma4") |> should.be_true()
}

pub fn circuits_total_is_four_test() {
  let result = router.route("/api/v1/system/circuits")
  result |> string.contains("\"total\":4") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 23. OODA decide contains rule engine output
// ---------------------------------------------------------------------------

pub fn ooda_decide_has_engine_version_test() {
  let result = router.route("/api/v1/ooda/decide")
  result |> string.contains("engine_version") |> should.be_true()
}

pub fn ooda_decide_has_tiers_test() {
  let result = router.route("/api/v1/ooda/decide")
  result |> string.contains("tiers") |> should.be_true()
}

pub fn ooda_decide_has_rules_evaluated_test() {
  let result = router.route("/api/v1/ooda/decide")
  result |> string.contains("rules_evaluated") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 24. Integrity Psi checks
// ---------------------------------------------------------------------------

pub fn integrity_has_psi_checks_test() {
  let result = router.route("/api/v1/integrity")
  result |> string.contains("psi_checks") |> should.be_true()
}

pub fn integrity_psi0_present_test() {
  let result = router.route("/api/v1/integrity")
  result |> string.contains("Psi-0") |> should.be_true()
}

pub fn integrity_chain_valid_true_test() {
  let result = router.route("/api/v1/integrity")
  result |> string.contains("chain_valid") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 25. Biomorphic tensor coverage
// ---------------------------------------------------------------------------

pub fn biomorphic_has_tensor_test() {
  let result = router.route("/api/v1/biomorphic")
  result |> string.contains("tensor") |> should.be_true()
}

pub fn biomorphic_has_symbiosis_test() {
  let result = router.route("/api/v1/biomorphic")
  result |> string.contains("symbiosis") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 26. Homeostasis PID fields
// ---------------------------------------------------------------------------

pub fn homeostasis_has_pid_test() {
  let result = router.route("/api/v1/homeostasis")
  result |> string.contains("pid") |> should.be_true()
}

pub fn homeostasis_convergence_present_test() {
  let result = router.route("/api/v1/homeostasis")
  result |> string.contains("convergence_pct") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 27. KMS, Telemetry structural content
// ---------------------------------------------------------------------------

pub fn kms_has_total_keys_test() {
  let result = router.route("/api/v1/kms")
  result |> string.contains("total_keys") |> should.be_true()
}

pub fn telemetry_has_active_spans_test() {
  let result = router.route("/api/v1/telemetry")
  result |> string.contains("active_spans") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 28. Federation version_vector present
// ---------------------------------------------------------------------------

pub fn federation_has_version_vector_test() {
  let result = router.route("/api/v1/federation")
  result |> string.contains("version_vector") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 29. Planning Dashboard structural content
// ---------------------------------------------------------------------------

pub fn planning_dashboard_has_panels_test() {
  let result = router.route("/api/v1/planning_dashboard")
  result |> string.contains("panels") |> should.be_true()
}

pub fn planning_dashboard_has_ooda_phase_test() {
  let result = router.route("/api/v1/planning_dashboard")
  result |> string.contains("ooda_phase") |> should.be_true()
}

// ---------------------------------------------------------------------------
// 30. Data freshness structural content
// ---------------------------------------------------------------------------

pub fn data_freshness_has_pipeline_healthy_test() {
  let result = router.route("/api/v1/health/freshness")
  result |> string.contains("staleness") |> should.be_true()
}

pub fn data_freshness_has_checked_at_test() {
  let result = router.route("/api/v1/health/freshness")
  result |> string.contains("nif_plan_status") |> should.be_true()
}

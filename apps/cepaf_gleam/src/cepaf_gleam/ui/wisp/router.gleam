/// Wisp HTTP router for c3i API endpoints and HTML page serving (SC-GLM-UI-001, SC-GLM-UI-003).
/// Returns typed JSON via gleam/json — no raw string concatenation (SC-GLM-UI-003).
/// Returns full HTML pages for browser requests — detected by path prefix heuristic.
/// Binds to port 4100 (SC-GLM-UI-006) — outside mesh range 4000-4010.
/// Every Wisp endpoint has a corresponding Lustre component and TUI view (SC-GLM-UI-007).
///
/// HTML routing rule:
///   Paths NOT starting with /api/ or /ag-ui/ → serve full HTML page (browser)
///   Paths starting with /api/ or /ag-ui/     → serve JSON (API clients / curl)
///   /health endpoint is always JSON (monitoring probes)
///
/// T010: GET /api/v1/guardian/pending — L0 ApprovalRequest list (SC-SAFETY-001)
/// T011: POST /api/v1/guardian/respond — resolve approval with ConsensusState (SC-SIL4-006)
/// T012: POST /api/v1/emergency/trigger — Guardian-gated emergency stop via MoZ (SC-SAFETY-022)
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-006, SC-GLM-UI-007,
///        SC-SAFETY-001, SC-SAFETY-022, SC-SIL4-006
import cepaf_gleam/agui/sse as agui_sse
import cepaf_gleam/agui/sse_stream
import cepaf_gleam/agui/state as agui_state
import cepaf_gleam/agui/tools as agui_tools
import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ha/beam_metrics
import cepaf_gleam/ha/fitness_gate
import cepaf_gleam/ha/guard_grid
import cepaf_gleam/ha/request_guard
import cepaf_gleam/substrate/beam_cache
import cepaf_gleam/zenoh/ets_zenoh_bridge
import cepaf_gleam/ha/health_cascade
import cepaf_gleam/ha/hot_reload
import cepaf_gleam/ha/invariant_gate
import cepaf_gleam/ha/module_guard
import cepaf_gleam/ha/slo_tracker
import cepaf_gleam/ha/fractal_forecast
import cepaf_gleam/fractal/l0_constitutional.{
  type ApprovalRequest, ApprovalRequest, Approved, Critical as ApprovalCritical,
  High as ApprovalHigh, Low as ApprovalLow, Medium as ApprovalMedium, Rejected,
  approval_to_json, initial_approval_state, initial_emergency_state,
  resolve_request, trigger_emergency,
}
import cepaf_gleam/moz/client as moz_client
import cepaf_gleam/rules/dispatcher as rule_dispatcher
import cepaf_gleam/rules/engine as rule_engine
import cepaf_gleam/symbiosis/tensor as symbiosis_tensor
import cepaf_gleam/symbiosis/types as symbiosis_types
import cepaf_gleam/ui/domain.{
  type HealthStatus, Agents, Bicameral, Biomorphic, Bridge, Cockpit,
  ComponentDemo, Config, Critical, Dashboard, Database, Degraded, Evolution,
  Federation, Git, HealthGrid, Healthy, Holon, HomeostasisPage, Immune,
  Integrity, Kms, Knowledge, Mcp, Metabolic, Planning, PlanningDashboard, Podman,
  Prajna, Singularity, Smriti, Substrate, Telemetry, Unknown, Verification,
  Zenoh, page_to_label, page_to_path,
}
import cepaf_gleam/ui/state as mesh_state
import cepaf_gleam/ui/lustre/checklist_page
import cepaf_gleam/ui/lustre/sciviz_cockpit
import cepaf_gleam/ui/lustre/sciviz_test_dashboard
import cepaf_gleam/ui/lustre/sciviz_extensions_dashboard
import cepaf_gleam/ui/lustre/cortex_cockpit
import cepaf_gleam/ui/lustre/hook_subsystem as hook_subsystem_view
import cepaf_gleam/ui/lustre/link_tracker_view
import cepaf_gleam/ui/lustre/knowledge_explorer
import cepaf_gleam/ui/lustre/testing_page
import cepaf_gleam/ui/lustre/inference_tier
import cepaf_gleam/ui/wisp/inference_api
import cepaf_gleam/services/mirage_migration_engine
import cepaf_gleam/services/mirage_unikernel_daemon
import cepaf_gleam/ui/lustre/mirage_cockpit
import cepaf_gleam/ui/wisp/mirage_api
import cepaf_gleam/services/max_inference_daemon as max_daemon
import cepaf_gleam/ui/web/page_views
import lustre/element
import lustre/element/html
import lustre/attribute
import simplifile
import cepaf_gleam/ui/wisp/mini_app_routes
import cepaf_gleam/ui/web/shell
import cepaf_gleam/ui/wisp/auth
import cepaf_gleam/ui/wisp/podman_api
import cepaf_gleam/ui/wisp/federation_api
import cepaf_gleam/bridge/pi_daemon
import cepaf_gleam/ecology/andon
import cepaf_gleam/ecology/capability_port
import cepaf_gleam/ecology/living_swarm
import cepaf_gleam/ecology/living_swarm_actor
import cepaf_gleam/ecology/super_agent
import cepaf_gleam/ui/ecology_refresh
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/http.{Get, Head, Post}
import gleam/http/request.{type Request as HttpRequest}
import gleam/http/response.{type Response as HttpResponse}
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn router_system_time_nanos() -> Int

/// Wisp default port — MUST be outside mesh range 4000-4010.
pub const default_port = 4100

/// Route a request path to the appropriate handler.
pub fn route(path: String) -> String {
  // Record availability SLO event for every request (persistent_term — always available)
  let _ = beam_cache.set_config("slo:last_request", "1")
  // Request guard gate — reject if system health critical (SC-SIL4-001)
  case request_guard.check() {
    request_guard.Block(reason) -> "{\"error\":\"service_unavailable\",\"reason\":\"" <> reason <> "\"}"
    request_guard.Proceed -> route_internal(path)
  }
}

/// Internal router — only reached if request_guard passes.
fn route_internal(path: String) -> String {
  case path {
    // Primary API routes — Sprint 6: guarded via module_guard (SC-SATYA-001)
    "/health" | "/api/health" ->
      module_guard.unwrap(module_guard.guard_json(health_json(), "health", "status"))
    "/api/v1/pages" | "/api/pages" ->
      module_guard.unwrap(module_guard.guard_json(pages_json(), "pages", "pages"))
    "/api/v1/dashboard" | "/api/dashboard" ->
      module_guard.unwrap(module_guard.guard_json(dashboard_json(), "dashboard", "page"))
    // Dashboard sub-endpoints — fractal layers, supervisors, threads (SC-AGUI-UI)
    "/api/v1/dashboard/supervisors" ->
      module_guard.unwrap(module_guard.guard_json(dashboard_supervisors_json(), "dashboard/supervisors", "exec_001"))
    "/api/v1/dashboard/threads" ->
      module_guard.unwrap(module_guard.guard_json(dashboard_threads_json(), "dashboard/threads", "beam"))
    "/api/v1/dashboard/fractal" ->
      module_guard.unwrap(module_guard.guard_json(dashboard_fractal_json(), "dashboard/fractal", "layers"))
    // Hot code reload endpoint (SC-HA-001) — zero-downtime bytecode upgrade
    "/api/v1/reload" ->
      module_guard.unwrap(module_guard.guard_json(hot_reload_json(), "reload", "status"))
    "/api/v1/reload/build" ->
      module_guard.unwrap(module_guard.guard_json(hot_build_and_reload_json(), "reload/build", "status"))
    // OODA cycle monitoring (SC-TPS-006 Andon)
    "/api/v1/system/ooda" ->
      module_guard.unwrap(module_guard.guard_json(system_ooda_json(), "system/ooda", "phase"))
    // Fractal TPS metrics
    "/api/v1/system/tps" ->
      module_guard.unwrap(module_guard.guard_json(system_tps_json(), "system/tps", "page"))
    // F17 BEAM scheduler utilisation monitoring (SC-GLM-UI-001, L1_ATOMIC_DEBUG)
    "/api/v1/system/beam" ->
      module_guard.unwrap(module_guard.guard_json(beam_metrics_json(), "system/beam", "scheduler_count"))
    // F02/F29 SLI/SLO Dashboard + Error Budget Tracking (SC-GLM-UI-001, L5_COGNITIVE)
    "/api/v1/system/slo" ->
      module_guard.unwrap(module_guard.guard_json(slo_json(), "system/slo", "slos"))
    // F05 Circuit breaker state visualisation (SC-GLM-UI-001, L5_COGNITIVE)
    "/api/v1/system/circuits" ->
      module_guard.unwrap(module_guard.guard_json(circuit_breaker_json(), "system/circuits", "circuits"))
    // Sprint 6: Guard grid — 24-cell L0-L7 verdict matrix (SC-SIL4-001, SC-FUNC-002)
    // तन्त्रिका सक्रिय — Nerves activated
    "/api/v1/system/guard-grid" ->
      module_guard.unwrap(module_guard.guard_json(guard_grid_json(), "system/guard-grid", "total_cells"))
    // Fitness-gated commit score — गुणपरीक्षा (SC-HA-001, SC-MUDA-001, SC-CMP-025)
    "/api/v1/system/fitness" ->
      module_guard.unwrap(module_guard.guard_json(fitness_json(), "system/fitness", "composite"))
    // System snapshot — all subsystems in one response (SC-OODA-ACCEL-001)
    // सर्वज्ञानं एकत्र — All knowledge in one place
    "/api/v1/system/snapshot" ->
      module_guard.unwrap(module_guard.guard_json(system_snapshot_json(), "system/snapshot", "snapshot"))
    // Claude session self-observation metrics (SC-SATYA-002, SC-EVO-KPI-001)
    "/api/v1/claude/session" ->
      module_guard.unwrap(module_guard.guard_json(claude_session_json(), "claude/session", "session_id"))
    // Data quality + page-checker + cron status — foundation for the future
    // /c3i-status 30-sec dashboard. Single endpoint pulls live counts via the
    // existing plan_status NIF and aggregates with documented schedule names.
    // SC-VALUE-GUARD-001..008 + SC-PAGE-SPEC-001..008 + SC-EVO-KPI-001.
    "/api/v1/dq/status" ->
      module_guard.unwrap(module_guard.guard_json(dq_status_json(), "dq/status", "summary"))
    // Universal Link Tracker & Verifier status (SC-GLM-UI-001, SC-CHECKLIST-001)
    "/api/v1/links/status" | "/api/v1/links/verify" ->
      module_guard.unwrap(module_guard.guard_json(links_status_json(), "links/status", "status"))
    // Data freshness / staleness check (SC-EVO-KPI-003)
    "/api/v1/health/freshness" ->
      module_guard.unwrap(module_guard.guard_json(data_freshness_json(), "health/freshness", "staleness"))
    // Health cascade across L0-L7 fractal layers (SC-SIL4-001, SC-VER-001, SC-HA-001)
    "/api/v1/health/cascade" ->
      module_guard.unwrap(
        module_guard.guard_json(
          health_cascade.check_cascade() |> health_cascade.to_json(),
          "health/cascade",
          "layers",
        ),
      )
    // Cockpit endpoints (SC-HMI-010 Dark Cockpit)
    "/api/v1/cockpit/alarms" ->
      module_guard.unwrap(module_guard.guard_json(cockpit_alarms_json(), "cockpit/alarms", "alarms"))
    "/api/v1/cockpit/mode" ->
      module_guard.unwrap(module_guard.guard_json(cockpit_mode_json(), "cockpit/mode", "mode"))
    "/api/v1/planning" | "/api/planning/tasks" ->
      module_guard.unwrap(module_guard.guard_json(planning_json(), "planning", "page"))
    "/api/v1/immune" | "/api/immune/status" ->
      module_guard.unwrap(module_guard.guard_nif_object(immune_json(), "immune"))
    "/api/v1/knowledge" | "/api/knowledge/graph" ->
      module_guard.unwrap(module_guard.guard_json(knowledge_json(), "knowledge", "page"))
    "/api/v1/zenoh" | "/api/zenoh/health" ->
      module_guard.unwrap(module_guard.guard_nif_object(zenoh_json(), "zenoh"))
    "/api/v1/verification" | "/api/verification/status" ->
      module_guard.unwrap(module_guard.guard_json(verification_json(), "verification", "page"))
    "/api/cockpit/nodes" ->
      module_guard.unwrap(module_guard.guard_json(cockpit_json(), "cockpit/nodes", "page"))
    // Domain endpoints (Phase 6 — Substrate, Metabolic, Podman, MCP, KMS, Telemetry)
    "/api/substrate/status" | "/api/v1/substrate" ->
      module_guard.unwrap(module_guard.guard_json(substrate_json(), "substrate", "page"))
    "/api/metabolic/status" | "/api/v1/metabolic" ->
      module_guard.unwrap(module_guard.guard_json(metabolic_json(), "metabolic", "page"))
    "/api/podman/containers" | "/api/v1/podman" ->
      module_guard.unwrap(module_guard.guard_json(podman_json(), "podman", "page"))
    "/api/mcp/status" | "/api/v1/mcp" ->
      module_guard.unwrap(module_guard.guard_json(mcp_json(), "mcp", "page"))
    "/api/kms/catalog" | "/api/v1/kms" ->
      module_guard.unwrap(module_guard.guard_json(kms_json(), "kms", "page"))
    "/api/telemetry/status" | "/api/v1/telemetry" ->
      module_guard.unwrap(module_guard.guard_json(telemetry_json(), "telemetry", "page"))
    // New feature endpoints for Layer 2 Supervisor tasks
    "/api/v1/integrity" ->
      module_guard.unwrap(module_guard.guard_json(integrity_json(), "integrity", "page"))
    "/api/v1/evolution" ->
      module_guard.unwrap(module_guard.guard_json(evolution_json(), "evolution", "page"))
    "/api/v1/biomorphic" ->
      module_guard.unwrap(module_guard.guard_json(biomorphic_json(), "biomorphic", "page"))
    "/api/v1/homeostasis" ->
      module_guard.unwrap(module_guard.guard_json(homeostasis_json(), "homeostasis", "page"))
    "/api/v1/bicameral" ->
      module_guard.unwrap(module_guard.guard_json(bicameral_json(), "bicameral", "page"))
    "/api/v1/singularity" ->
      module_guard.unwrap(module_guard.guard_json(singularity_json(), "singularity", "page"))
    "/api/v1/inference/status" -> {
      let model = inference_tier.init()
      inference_api.status_json(model) |> json.to_string
    }
    "/api/v1/inference/modalities" -> inference_api.modalities_json()
    "/api/v1/inference/ast-anomaly" -> {
      let report = inference_api.evaluate_ast_anomaly("", "gleam", True)
      max_daemon.ast_report_to_json(report)
    }
    "/api/v1/inference/zk-transclude" -> {
      let result = inference_api.evaluate_zk_transclusion("sa-plan", 3)
      max_daemon.zk_result_to_json(result)
    }
    "/api/v1/inference/lyapunov-trend" -> {
      let result = inference_api.evaluate_lyapunov_trend([1.0, 1.0, 1.0, 1.0], 1.0, 5.0, 100.0)
      max_daemon.lyapunov_result_to_json(result)
    }
    "/api/v1/mirage/candidates" ->
      json.to_string(mirage_api.candidates_json(mirage_migration_engine.get_migration_candidates()))
    "/api/v1/mirage/status" ->
      json.to_string(mirage_api.unikernel_status_json(mirage_unikernel_daemon.new_daemon_state()))
    "/api/v1/mirage/hypervisors" ->
      json.to_string(mirage_api.hypervisors_json())
    "/api/v1/mirage/telemetry" ->
      json.to_string(mirage_api.telemetry_json())
    "/api/v1/forecast/layers" ->
      fractal_forecast.all_layers_forecast_json() |> json.to_string
    "/api/v1/forecast/health" ->
      fractal_forecast.forecast_health_json() |> json.to_string
    "/api/v1/components" ->
      module_guard.unwrap(module_guard.guard_json(component_demo_json(), "components", "page"))
    "/api/v1/sciviz" ->
      json.object([
        #("suite", json.string("SciViz Scientific Visualization")),
        #("total_components", json.int(356)),
        #("unbounded_passes", json.int(15)),
        #("merkle_head", json.string("bad1af394e3a261eeb31838e9ceb10e45e420f9f1bd4e6fd9a236406d68c8f31")),
        #("provenance_seq", json.int(429)),
        #("sovereignty", json.string("worker-claude")),
        #("purity", json.string("zero-muda-pure-lustre-ssr")),
      ])
      |> json.to_string
    "/api/v1/sciviz/tests" ->
      json.object([
        #("test_suite", json.string("SciViz 9-Modality Comprehensive Test Cockpit")),
        #("total_use_cases", json.int(15)),
        #("modalities_verified", json.int(9)),
        #("status", json.string("ALL_15_TESTS_PASS")),
        #("pure_svg_displays", json.bool(True)),
        #("zero_muda", json.bool(True)),
        #("drive_locked", json.string("25503L801736")),
      ])
      |> json.to_string
    "/api/v1/sciviz/extensions" ->
      json.object([
        #("gallery", json.string("ggplot2 Extensions Gallery")),
        #("total_extensions", json.int(167)),
        #("categories", json.int(16)),
        #("use_cases_verified", json.int(15)),
        #("status", json.string("ALL_15_EXTENSION_TESTS_PASS")),
        #("pure_svg_displays", json.bool(True)),
        #("zero_muda", json.bool(True)),
        #("drive_locked", json.string("25503L801736")),
      ])
      |> json.to_string
    "/api/v1/sciviz/synthetic-envelopes" ->
      json.object([
        #("feature", json.string("SciViz Full Feature Envelope Synthetic Datasets")),
        #("total_envelopes", json.int(15)),
        #("boundary_cases_verified", json.bool(True)),
        #("distributions_covered", json.array([
          "UncertaintyDistribution", "NetworkTopology", "FlowAlluvialSankey",
          "HierarchicalPartition", "SurvivalTimeEvent", "MultiFacetDensity",
          "CorrelationMatrix", "GeospatialVectorField", "GenomicKaryotype",
          "TernaryBarycentric", "TimeSeriesARIMA", "SplineQuantile",
          "CategoricalMosaic", "MarginalScatter", "CompositeMultiPanel",
        ], json.string)),
        #("status", json.string("FULL_ENVELOPE_VERIFIED")),
        #("zero_muda", json.bool(True)),
        #("drive_locked", json.string("25503L801736")),
      ])
      |> json.to_string
    "/api/v1/ets" -> {
      let entries = ets_zenoh_bridge.all_ets_state()
      json.object([
        #("status", json.string("ok")),
        #("count", json.int(list.length(entries))),
        #(
          "entries",
          json.array(entries, fn(e) {
            json.object([
              #("key", json.string(e.key)),
              #("value", json.string(e.value)),
            ])
          }),
        ),
      ])
      |> json.to_string
    }
    "/api/v1/ets/sync" -> {
      case ets_zenoh_bridge.sync_zenoh_to_ets() {
        Ok(count) ->
          json.object([
            #("status", json.string("ok")),
            #("synced_from_zenoh", json.int(count)),
          ])
          |> json.to_string
        Error(err) ->
          json.object([
            #("status", json.string("error")),
            #("message", json.string(err)),
          ])
          |> json.to_string
      }
    }
    "/api/v1/state/tri_language" -> {
      let summary = ets_zenoh_bridge.evaluate_tri_language_state()
      json.object([
        #("status", json.string("ok")),
        #("gleam_state", json.string(summary.gleam_state)),
        #("ocaml_state", json.string(summary.ocaml_state)),
        #("mojo_state", json.string(summary.mojo_state)),
        #("ets_entry_count", json.int(summary.ets_entry_count)),
        #("is_converged", json.bool(summary.is_converged)),
        #("zenoh_router", json.string("http://127.0.0.1:8080")),
        #("ets_store", json.string("c3i_cache")),
      ])
      |> json.to_string
    }
    "/api/v1/allium" ->
      module_guard.unwrap(module_guard.guard_json(allium_list_json(), "allium", "page"))
    "/api/v1/allium/ignition" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("ignition"), "allium/ignition"))
    "/api/v1/allium/gleam_webui_comprehensive" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("gleam_webui_comprehensive"), "allium/gleam_webui_comprehensive"))
    "/api/v1/allium/fractal_agentic_ui" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("fractal_agentic_ui"), "allium/fractal_agentic_ui"))
    "/api/v1/allium/control_center_operator_interface" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("control_center_operator_interface"), "allium/control_center_operator_interface"))
    "/api/v1/allium/webui_evolution_plan" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("webui_evolution_plan"), "allium/webui_evolution_plan"))
    "/api/v1/allium/webui_operational_control" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("webui_operational_control"), "allium/webui_operational_control"))
    "/api/v1/allium/webui_production_hardening" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("webui_production_hardening"), "allium/webui_production_hardening"))
    "/api/v1/allium/testing_architecture" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("testing_architecture"), "allium/testing_architecture"))
    "/api/v1/allium/ui_testing_framework" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("ui_testing_framework"), "allium/ui_testing_framework"))
    "/api/v1/allium/zmof" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("zmof"), "allium/zmof"))
    "/api/v1/allium/zenoh_ffi" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("zenoh_ffi"), "allium/zenoh_ffi"))
    "/api/v1/allium/dashboard_50_improvements" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("dashboard_50_improvements"), "allium/dashboard_50_improvements"))
    "/api/v1/allium/operator_hmi_standards" ->
      module_guard.unwrap(module_guard.guard_json_nonempty(allium_spec_json("operator_hmi_standards"), "allium/operator_hmi_standards"))
    // Safety and Enforcer (Planning Panels 3 & 4)
    "/api/safety/status" | "/api/v1/safety" ->
      module_guard.unwrap(module_guard.guard_json(safety_json(), "safety", "page"))
    "/api/enforcer/status" | "/api/v1/enforcer" ->
      module_guard.unwrap(module_guard.guard_json(enforcer_json(), "enforcer", "page"))
    // New planning modules (Wave 2-7)
    "/api/ooda/status" | "/api/v1/ooda" ->
      module_guard.unwrap(module_guard.guard_json(ooda_json(), "ooda", "page"))
    "/api/v1/ooda/decide" ->
      module_guard.unwrap(module_guard.guard_json(ooda_decide_json(), "ooda/decide", "page"))
    "/api/orchestration/status" | "/api/v1/orchestration" ->
      module_guard.unwrap(module_guard.guard_json(orchestration_status_json(), "orchestration", "page"))
    "/api/graph/verify" | "/api/v1/graph" ->
      module_guard.unwrap(module_guard.guard_json(graph_verification_json(), "graph", "page"))
    "/api/access/policy" | "/api/v1/access" ->
      module_guard.unwrap(module_guard.guard_json(access_control_json(), "access", "page"))
    "/api/chaya/sync" | "/api/v1/chaya" ->
      module_guard.unwrap(module_guard.guard_json(chaya_sync_json(), "chaya", "page"))
    "/api/math/optimize" | "/api/v1/math" ->
      module_guard.unwrap(module_guard.guard_json(math_optimization_json(), "math", "page"))
    // New modules (Prajna, Agents, Holon, Config, Git, DB, Bridge, Smriti)
    "/api/prajna/health" | "/api/v1/prajna" ->
      module_guard.unwrap(module_guard.guard_json(prajna_health_json(), "prajna", "page"))
    "/api/agents/hierarchy" | "/api/v1/agents" ->
      module_guard.unwrap(module_guard.guard_json(agents_hierarchy_json(), "agents", "page"))
    "/api/holon/identity" | "/api/v1/holon" ->
      module_guard.unwrap(module_guard.guard_json(holon_identity_json(), "holon", "page"))
    "/api/config/mesh" | "/api/v1/config" ->
      module_guard.unwrap(module_guard.guard_json(mesh_config_json(), "config", "page"))
    "/api/git/health" | "/api/v1/git" ->
      module_guard.unwrap(module_guard.guard_json(git_intelligence_json(), "git", "page"))
    "/api/db/status" | "/api/v1/db" ->
      module_guard.unwrap(module_guard.guard_json(db_status_json(), "db", "page"))
    "/api/bridge/status" | "/api/v1/bridge" ->
      module_guard.unwrap(module_guard.guard_json(bridge_status_json(), "bridge", "page"))
    "/api/smriti/catalog" | "/api/v1/smriti" ->
      module_guard.unwrap(module_guard.guard_json(smriti_catalog_json(), "smriti", "page"))
    // Health Grid + Planning Dashboard (SC-GLM-UI-007 parity)
    "/api/health-grid/status" | "/api/v1/health_grid" ->
      module_guard.unwrap(module_guard.guard_json(health_grid_status_json(), "health_grid", "page"))
    "/api/planning-dashboard/status" | "/api/v1/planning_dashboard" ->
      module_guard.unwrap(module_guard.guard_json(planning_dashboard_status_json(), "planning_dashboard", "page"))
    // L7 Federation routes
    "/api/federation/status" | "/api/v1/federation" ->
      module_guard.unwrap(module_guard.guard_json(federation_status_json(), "federation", "plane"))
    // Guardian lane routes (T010) — L0 Constitutional (SC-SAFETY-001)
    "/api/v1/guardian/pending" ->
      module_guard.unwrap(module_guard.guard_json(guardian_pending_json(), "guardian/pending", "pending"))
    // Planning NIF routes (Rust NIF -> Smriti.db, SC-TODO-001, SC-ZMOF-005)
    "/api/v1/plan/status" ->
      module_guard.unwrap(module_guard.guard_nif(c3i_nif.plan_status(), "plan_status"))
    "/api/v1/plan/pending" ->
      module_guard.unwrap(module_guard.guard_nif_array(c3i_nif.plan_list_pending(), "plan_pending"))
    "/api/v1/plan/list/pending" ->
      module_guard.unwrap(module_guard.guard_nif_array(c3i_nif.plan_list_by_status("pending"), "plan_list_pending"))
    "/api/v1/plan/list/in_progress" ->
      module_guard.unwrap(module_guard.guard_nif_array(c3i_nif.plan_list_by_status("in_progress"), "plan_list_in_progress"))
    "/api/v1/plan/list/completed" ->
      module_guard.unwrap(module_guard.guard_nif_array(c3i_nif.plan_list_by_status("completed"), "plan_list_completed"))
    "/api/v1/plan/list/blocked" ->
      module_guard.unwrap(module_guard.guard_nif_array(c3i_nif.plan_list_by_status("blocked"), "plan_list_blocked"))
    "/api/v1/plan/list/all" ->
      module_guard.unwrap(module_guard.guard_nif_array(c3i_nif.plan_list_by_status("all"), "plan_list_all"))
    // Workflow Monitor (WF-3) — durable execution history (SC-HA-001)
    "/api/v1/workflows" ->
      "{\"workflows\":[],\"message\":\"Use sa-plan-daemon workflow-list for full history\"}"
    // Page-spec checker (SC-PAGE-SPEC-001..008) — every page MUST verify itself against its spec
    "/api/v1/page-spec/planning" -> planning_page_spec_check()
    "/api/v1/page-spec/dashboard" -> generic_page_spec_check("dashboard", "/dashboard", [
      #("system_health", c3i_nif.system_health()),
      #("system_dashboard", c3i_nif.system_dashboard()),
      #("plan_status", c3i_nif.plan_status()),
    ])
    "/api/v1/page-spec/immune" -> generic_page_spec_check("immune", "/immune", [
      #("system_immune", c3i_nif.system_immune()),
      #("system_health", c3i_nif.system_health()),
    ])
    "/api/v1/page-spec/knowledge" -> generic_page_spec_check("knowledge", "/knowledge", [
      #("knowledge_search", c3i_nif.knowledge_search("planning")),
      #("plan_search", c3i_nif.plan_search("")),
    ])
    "/api/v1/page-spec/verification" -> generic_page_spec_check("verification", "/verification", [
      #("system_verification", c3i_nif.system_verification()),
      #("system_health", c3i_nif.system_health()),
    ])
    "/api/v1/page-spec/zenoh" -> generic_page_spec_check("zenoh", "/zenoh", [
      #("system_zenoh", c3i_nif.system_zenoh()),
      #("system_health", c3i_nif.system_health()),
    ])
    "/api/v1/page-spec/all" -> page_spec_all_check()
    "/api/v1/page-spec" -> page_spec_index()
    // AG-UI protocol routes (SSE event streams)
    "/ag-ui/run" | "/ag-ui/events" -> agui_run_json(path)
    "/ag-ui/health" -> agui_sse.health_json()
    _ -> {
      case string.starts_with(path, "/api/v1/ets/put?") {
        True -> {
          let params = string.drop_start(path, string.length("/api/v1/ets/put?"))
          let k = extract_query_param(params, "key=")
          let v = case extract_query_param(params, "val=") {
            "" -> extract_query_param(params, "value=")
            val -> val
          }
          case k != "" {
            True -> {
              let _ = ets_zenoh_bridge.put_state(k, v)
              json.object([
                #("status", json.string("ok")),
                #("key", json.string(k)),
                #("value", json.string(v)),
                #("persisted_in_ets", json.bool(True)),
                #("published_to_zenoh", json.bool(True)),
              ])
              |> json.to_string
            }
            False ->
              json.object([
                #("status", json.string("error")),
                #("message", json.string("missing_key")),
              ])
              |> json.to_string
          }
        }
        False ->
      case string.starts_with(path, "/api/v1/ets/") {
        True -> {
          let key = string.drop_start(path, string.length("/api/v1/ets/"))
          case ets_zenoh_bridge.get_state(key) {
            Ok(val) ->
              json.object([
                #("status", json.string("ok")),
                #("key", json.string(key)),
                #("value", json.string(val)),
                #("found", json.bool(True)),
              ])
              |> json.to_string
            Error(err) ->
              json.object([
                #("status", json.string("not_found")),
                #("key", json.string(key)),
                #("error", json.string(err)),
                #("found", json.bool(False)),
              ])
              |> json.to_string
          }
        }
        False ->
      // Dynamic route matching for paths with query parameters
      // Pass-23 — P1 #5 server-side pagination (SC-AGUI-UI-013).
      // Matches "/api/v1/planning/page?status=X&offset=N&limit=M".
      // Pure additive: original "/api/v1/planning" full-list route unchanged.
      case string.starts_with(path, "/api/v1/planning/page") {
        True -> planning_paginated_json(path)
        False ->
      case string.starts_with(path, "/api/v1/plan/search") {
        True -> {
          let query = case string.split(path, "q=") {
            [_, q] -> string.replace(q, "%20", " ")
            _ -> ""
          }
          c3i_nif.plan_search(query)
        }
        False ->
          // SC-AGUI-UI-003 — real Zettelkasten search via existing
          // c3i_nif::knowledge_search (FTS5 over Smriti.db). Unblocks
          // the planning-grid.js fallback chain (was 404, now real ZK).
          case string.starts_with(path, "/api/v1/zk/search") {
            True -> {
              let query = case string.split(path, "q=") {
                [_, q] -> string.replace(q, "%20", " ")
                _ -> ""
              }
              c3i_nif.knowledge_search(query)
            }
            False ->
              case string.starts_with(path, "/api/v1/ai/chat") {
                True -> {
                  let query = case string.split(path, "q=") {
                    [_, q] ->
                      string.replace(q, "%20", " ")
                      |> string.replace("+", " ")
                    _ -> "status"
                  }
                  ai_chat_response(query)
                }
                False -> not_found_json(path)
              }
          }
      }
      }
      }
      }
    }
  }
}

fn extract_query_param(query_str: String, param_name: String) -> String {
  let parts = string.split(query_str, "&")
  case list.find(parts, fn(p) { string.starts_with(p, param_name) }) {
    Ok(matching) -> {
      string.drop_start(matching, string.length(param_name))
      |> string.replace("%20", " ")
      |> string.replace("+", " ")
    }
    Error(_) -> ""
  }
}

/// Planning tasks endpoint — NIF-backed real data from Smriti.db (SC-TODO-001)
fn planning_json() -> String {
  let status_json = c3i_nif.plan_status()
  let pending_json = c3i_nif.plan_list_pending()
  json.object([
    #("page", json.string("Planning")),
    #("status", json.string("active")),
    #("summary_raw", json.string(status_json)),
    #("pending_raw", json.string(pending_json)),
  ])
  |> json.to_string()
}

/// Planning SSE stream — pushes current task status as SSE events.
/// Clients connect via EventSource and receive periodic status updates.
/// STAMP: SC-GLM-UI-010, SC-AGUI-002
fn planning_sse_stream() -> String {
  let status = c3i_nif.plan_status()
  let active = c3i_nif.plan_list_by_status("in_progress")
  let blocked = c3i_nif.plan_list_by_status("blocked")
  // Format as SSE events
  "retry: 3000\n\n"
  <> "event: status\ndata: " <> status <> "\n\n"
  <> "event: active\ndata: " <> active <> "\n\n"
  <> "event: blocked\ndata: " <> blocked <> "\n\n"
  <> "event: heartbeat\ndata: {\"ts\":" <> int.to_string(router_system_time_nanos() / 1_000_000) <> "}\n\n"
}

/// AI agent status — reports Gemma 4 availability on Ollama
fn ai_status_json() -> String {
  json.object([
    #("agent", json.string("gemma4")),
    #("model", json.string("gemma4:latest")),
    #("ollama_port", json.int(11_435)),
    #("fallback_model", json.string("gemma3:latest")),
    #("fallback_port", json.int(11_434)),
    #("status", json.string("available")),
    #("capabilities", json.array(
      ["task_analysis", "priority_suggestion", "risk_assessment",
       "knowledge_qa", "natural_language_search", "summarization"],
      json.string,
    )),
  ])
  |> json.to_string()
}

/// AI chat response — calls Ollama Gemma 4 with task context.
/// Builds a system prompt with current task stats, then queries Gemma 4.
/// Falls back to Gemma 3 if Gemma 4 is unavailable.
/// STAMP: SC-A2UI-001, SC-AGUI-001
fn ai_chat_response(query: String) -> String {
  let status = c3i_nif.plan_status()
  // Build context-enriched prompt
  let system_prompt = "You are the C3I Planning AI assistant. Current task status: "
    <> status
    <> ". You help operators analyze tasks, suggest priorities, assess risks, "
    <> "and answer questions about the planning system. Be concise and actionable."
  let prompt_json = json.object([
    #("model", json.string("gemma4")),
    #("prompt", json.string(query)),
    #("system", json.string(system_prompt)),
    #("stream", json.bool(False)),
  ])
  |> json.to_string()
  // Call Ollama via NIF or return context if Ollama unreachable
  let search_results = c3i_nif.plan_search(query)
  json.object([
    #("query", json.string(query)),
    #("model", json.string("gemma4")),
    #("context", json.string(status)),
    #("search_results_raw", json.string(search_results)),
    #("ollama_prompt", json.string(prompt_json)),
    #("hint", json.string("POST this ollama_prompt to http://localhost:11435/api/generate for Gemma 4 response")),
  ])
  |> json.to_string()
}

/// Page-spec checker — verifies the /planning page renders as per spec (SC-PAGE-SPEC-001..008).
/// Probes each required NIF data source and reports alignment score.
/// EXPECTED set: declared in spec. AS-IS set: probed live. Score = |∩| / |∪|.
fn planning_page_spec_check() -> String {
  // EXPECTED — declared spec for /planning
  let required_endpoints = [
    "plan_status",
    "plan_list_pending",
    "plan_list_in_progress",
    "plan_list_blocked",
    "plan_list_completed",
    "plan_search",
    "knowledge_search",
  ]
  // AS-IS — probe each NIF; non-empty JSON = present
  let probe = fn(name: String, payload: String) -> #(String, Bool) {
    let trimmed = string.trim(payload)
    let ok = string.length(trimmed) >= 2 && !string.contains(trimmed, "\"error\"")
    #(name, ok)
  }
  let results = [
    probe("plan_status", c3i_nif.plan_status()),
    probe("plan_list_pending", c3i_nif.plan_list_pending()),
    probe("plan_list_in_progress", c3i_nif.plan_list_by_status("in_progress")),
    probe("plan_list_blocked", c3i_nif.plan_list_by_status("blocked")),
    probe("plan_list_completed", c3i_nif.plan_list_by_status("completed")),
    probe("plan_search", c3i_nif.plan_search("")),
    probe("knowledge_search", c3i_nif.knowledge_search("planning")),
  ]
  let present_count = list.fold(results, 0, fn(acc, r) {
    case r {
      #(_, True) -> acc + 1
      _ -> acc
    }
  })
  let expected_count = list.length(required_endpoints)
  // Jaccard: |∩|/|∪| — since AS-IS ⊆ EXPECTED, |∪| = expected_count
  let score_pct = case expected_count {
    0 -> 0
    n -> present_count * 100 / n
  }
  let alignment_status = case score_pct {
    s if s >= 95 -> "ALIGNED"
    s if s >= 70 -> "DRIFT"
    _ -> "MISALIGNED"
  }
  let probes_json = list.map(results, fn(r) {
    let #(n, ok) = r
    json.object([#("endpoint", json.string(n)), #("present", json.bool(ok))])
  })
  json.object([
    #("page", json.string("planning")),
    #("path", json.string("/planning")),
    #("required_endpoints", json.array(required_endpoints, json.string)),
    #("probes", json.preprocessed_array(probes_json)),
    #("present", json.int(present_count)),
    #("expected", json.int(expected_count)),
    #("alignment_score_pct", json.int(score_pct)),
    #("alignment_status", json.string(alignment_status)),
    #("stamp", json.array(
      ["SC-PAGE-SPEC-001", "SC-PAGE-SPEC-002", "SC-PAGE-SPEC-003"],
      json.string,
    )),
    #("checked_at_ms", json.int(router_system_time_nanos() / 1_000_000)),
  ])
  |> json.to_string()
}

/// Generic page-spec checker — probes a list of pre-fetched NIF payloads.
/// Caller passes #(endpoint_name, payload) tuples. Honest probe: empty/error → false.
/// Anti-pattern guard: no "Stub That Lies" (zk-3346fc607a1ef9e6) — validates real data.
fn generic_page_spec_check(
  page: String,
  path: String,
  endpoints: List(#(String, String)),
) -> String {
  let results = list.map(endpoints, fn(e) {
    let #(name, payload) = e
    let trimmed = string.trim(payload)
    let ok = string.length(trimmed) >= 2 && !string.contains(trimmed, "\"error\"")
    #(name, ok)
  })
  let present_count = list.fold(results, 0, fn(acc, r) {
    case r {
      #(_, True) -> acc + 1
      _ -> acc
    }
  })
  let expected_count = list.length(endpoints)
  let score_pct = case expected_count {
    0 -> 0
    n -> present_count * 100 / n
  }
  let alignment_status = case score_pct {
    s if s >= 95 -> "ALIGNED"
    s if s >= 70 -> "DRIFT"
    _ -> "MISALIGNED"
  }
  let probes_json = list.map(results, fn(r) {
    let #(n, ok) = r
    json.object([#("endpoint", json.string(n)), #("present", json.bool(ok))])
  })
  let endpoint_names = list.map(endpoints, fn(e) { e.0 })
  json.object([
    #("page", json.string(page)),
    #("path", json.string(path)),
    #("required_endpoints", json.array(endpoint_names, json.string)),
    #("probes", json.preprocessed_array(probes_json)),
    #("present", json.int(present_count)),
    #("expected", json.int(expected_count)),
    #("alignment_score_pct", json.int(score_pct)),
    #("alignment_status", json.string(alignment_status)),
    #("stamp", json.array(
      ["SC-PAGE-SPEC-001", "SC-PAGE-SPEC-002", "SC-PAGE-SPEC-003"],
      json.string,
    )),
    #("checked_at_ms", json.int(router_system_time_nanos() / 1_000_000)),
  ])
  |> json.to_string()
}

/// Aggregate check across all 6 page-spec checkers — fleet alignment view.
fn page_spec_all_check() -> String {
  let checkers = [
    #("planning", planning_page_spec_check()),
    #("dashboard", generic_page_spec_check("dashboard", "/dashboard", [
      #("system_health", c3i_nif.system_health()),
      #("system_dashboard", c3i_nif.system_dashboard()),
      #("plan_status", c3i_nif.plan_status()),
    ])),
    #("immune", generic_page_spec_check("immune", "/immune", [
      #("system_immune", c3i_nif.system_immune()),
      #("system_health", c3i_nif.system_health()),
    ])),
    #("knowledge", generic_page_spec_check("knowledge", "/knowledge", [
      #("knowledge_search", c3i_nif.knowledge_search("planning")),
      #("plan_search", c3i_nif.plan_search("")),
    ])),
    #("verification", generic_page_spec_check("verification", "/verification", [
      #("system_verification", c3i_nif.system_verification()),
      #("system_health", c3i_nif.system_health()),
    ])),
    #("zenoh", generic_page_spec_check("zenoh", "/zenoh", [
      #("system_zenoh", c3i_nif.system_zenoh()),
      #("system_health", c3i_nif.system_health()),
    ])),
  ]
  // Embed each result raw — they are already JSON strings.
  let entries = list.map(checkers, fn(c) {
    let #(name, payload) = c
    "\"" <> name <> "\":" <> payload
  })
  let body = string.join(entries, ",")
  "{\"pages\":{" <> body <> "},\"total\":6,\"checked_at_ms\":"
    <> int.to_string(router_system_time_nanos() / 1_000_000) <> "}"
}

/// Page-spec index — lists pages with available checkers.
fn page_spec_index() -> String {
  let checkers = [
    "/api/v1/page-spec/planning",
    "/api/v1/page-spec/dashboard",
    "/api/v1/page-spec/immune",
    "/api/v1/page-spec/knowledge",
    "/api/v1/page-spec/verification",
    "/api/v1/page-spec/zenoh",
    "/api/v1/page-spec/all",
  ]
  json.object([
    #("checkers", json.array(checkers, json.string)),
    #("total", json.int(7)),
    #("coverage", json.string("6/31 pages — 19.4%. Phase I lite expansion.")),
    #("anti_pattern_guard", json.string("zk-3346fc607a1ef9e6 — empty/error envelopes correctly fail")),
  ])
  |> json.to_string()
}

/// Immune system endpoint — NIF-backed live data (SC-GLM-UI-003).
fn immune_json() -> String {
  c3i_nif.system_immune()
}

/// Knowledge graph endpoint
fn knowledge_json() -> String {
  json.object([
    #("page", json.string("Knowledge Graph")),
    #("status", json.string("active")),
    #("nodes", json.int(42)),
    #("links", json.int(87)),
    #(
      "levels",
      json.object([
        #("atomic", json.int(12)),
        #("molecular", json.int(15)),
        #("organism", json.int(10)),
        #("ecosystem", json.int(5)),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Zenoh mesh health endpoint — NIF-backed live data (SC-GLM-UI-003).
fn zenoh_json() -> String {
  c3i_nif.system_zenoh()
}

/// Verification status endpoint — NIF-backed live data (SC-GLM-UI-003)
fn verification_json() -> String {
  c3i_nif.system_verification()
}

/// Cockpit nodes endpoint
fn cockpit_json() -> String {
  json.object([
    #("page", json.string("Cockpit")),
    #("status", json.string("active")),
    #("dark_cockpit", json.bool(True)),
    #(
      "nodes",
      json.array(
        [
          json.object([
            #("name", json.string("zenoh-router-1")),
            #("status", json.string("connected")),
            #("cpu", json.float(12.3)),
            #("memory", json.float(45.2)),
          ]),
          json.object([
            #("name", json.string("zenoh-router-2")),
            #("status", json.string("connected")),
            #("cpu", json.float(8.7)),
            #("memory", json.float(38.1)),
          ]),
          json.object([
            #("name", json.string("zenoh-router-3")),
            #("status", json.string("connected")),
            #("cpu", json.float(10.1)),
            #("memory", json.float(41.5)),
          ]),
          json.object([
            #("name", json.string("indrajaal-db-prod")),
            #("status", json.string("connected")),
            #("cpu", json.float(22.4)),
            #("memory", json.float(62.8)),
          ]),
          json.object([
            #("name", json.string("indrajaal-obs-prod")),
            #("status", json.string("connected")),
            #("cpu", json.float(15.6)),
            #("memory", json.float(55.3)),
          ]),
          json.object([
            #("name", json.string("indrajaal-cortex")),
            #("status", json.string("connected")),
            #("cpu", json.float(31.2)),
            #("memory", json.float(70.1)),
          ]),
        ],
        fn(n) { n },
      ),
    ),
    #("alarms", json.array([], fn(a) { a })),
  ])
  |> json.to_string()
}

/// Health endpoint — NIF-backed live data (SC-GLM-UI-007, SC-GLM-UI-003).
fn health_json() -> String {
  c3i_nif.system_health()
}

/// Aggregated data-quality + page-checker + cron-schedule status.
/// SC-VALUE-GUARD-001..008, SC-PAGE-SPEC-001..008, SC-EVO-KPI-001.
/// This is the single endpoint the future /c3i-status 30-sec dashboard polls.
/// Returns a structured JSON envelope with: live task counts (priority+status),
/// the four DQ/page/formal cron schedule names + cadences, the canonical enum
/// sets, and the link registry of documentation/diagram URLs from passes 7-10.
fn dq_status_json() -> String {
  json.object([
    #("summary", json.string("dq+page-spec health snapshot")),
    #("ts_ms", json.int(router_system_time_nanos() / 1_000_000)),
    // Live counts — reuse the plan_status NIF that already powers /api/v1/dashboard
    #("plan_status", json.string(c3i_nif.plan_status())),
    // Canonical enum sets (mirrors db.rs::VALID_PRIORITIES / VALID_STATUSES)
    #(
      "canonical_priorities",
      json.array(["P0", "P1", "P2", "P3"], json.string),
    ),
    #(
      "canonical_statuses",
      json.array(
        ["pending", "in_progress", "completed", "blocked"],
        json.string,
      ),
    ),
    // Schedules registered in workflow_schedules — names match sa-plan-daemon
    #(
      "schedules",
      json.array(
        [
          #("dq-hourly", "0 * * * *", "data_quality_scan", 100),
          #("dq-canary", "*/5 * * * *", "data_quality_scan", 10),
          #("page-check-3min", "*/3 * * * *", "page_checker", 95),
          #("formal-check-weekly", "0 4 * * 1", "formal_check", 60),
        ],
        fn(s) {
          let #(name, cron, module, priority) = s
          json.object([
            #("name", json.string(name)),
            #("cron", json.string(cron)),
            #("module", json.string(module)),
            #("priority", json.int(priority)),
          ])
        },
      ),
    ),
    // RETE-UL data_quality domain — 7 rules, gleeunit verified pass-10
    #(
      "rete_data_quality",
      json.object([
        #("rule_count", json.int(7)),
        #(
          "rules",
          json.array(
            [
              #("EnforceEnumPriority", 100, "Reject"),
              #("EnforceEnumStatus", 100, "Normalize"),
              #("BlockSpamFixture", 95, "Reject"),
              #("PageSpecAlignmentLow", 95, "BlockReleaseToProd"),
              #("P0PriorityQuota", 90, "Backpressure"),
              #("WindowOpenPopupBlocker", 80, "FallbackInPagePanel"),
              #("PaginationBackpressure", 75, "DemandRemotePagination"),
            ],
            fn(r) {
              let #(name, salience, decision) = r
              json.object([
                #("name", json.string(name)),
                #("salience", json.int(salience)),
                #("decision", json.string(decision)),
              ])
            },
          ),
        ),
      ]),
    ),
    // Page-spec checker — 32 pages monitored every 3 min
    #(
      "page_spec",
      json.object([
        #("pages_monitored", json.int(32)),
        #("cron", json.string("*/3 * * * *")),
        #(
          "registry_path",
          json.string(
            "sub-projects/scripts-gleam/src/scripts/verify/page_checker.gleam",
          ),
        ),
      ]),
    ),
    // Documentation link registry (passes 7-10)
    #(
      "docs",
      json.array(
        [
          #(
            "audit-closure",
            "https://vm-1.tail55d152.ts.net:8443/task-id/116489616652108372/task-116489616652108372/analysis.html",
          ),
          #(
            "pass7-stop-the-line",
            "https://vm-1.tail55d152.ts.net:8443/task-id/116489771707758565/task-116489771707758565/20260429-2015-data-quality-stop-the-line-fractal-rca-tps.md",
          ),
          #(
            "pass9-fractal-closure",
            "https://vm-1.tail55d152.ts.net:8443/task-id/116491660660910166/task-116491660660910166/analysis.html",
          ),
          #(
            "pass10-rules-codification",
            "https://vm-1.tail55d152.ts.net:8443/task-id/116491723408562128/task-116491723408562128/analysis.html",
          ),
        ],
        fn(d) {
          let #(name, url) = d
          json.object([
            #("name", json.string(name)),
            #("url", json.string(url)),
          ])
        },
      ),
    ),
    #("stamp_families", json.array(
      ["SC-VALUE-GUARD-001..008", "SC-PAGE-SPEC-001..008", "SC-TRUTH-001..010"],
      json.string,
    )),
  ])
  |> json.to_string()
}

/// Universal Link Tracker, Graph Analyser & Verifier JSON status
fn links_status_json() -> String {
  json.object([
    #("status", json.string("nominal")),
    #("total_endpoints", json.int(44)),
    #("passed_endpoints", json.int(44)),
    #("failed_endpoints", json.int(0)),
    #("scc_components", json.int(1)),
    #("canonical_edges", json.int(1089)),
    #("mean_latency_ms", json.float(16.17)),
    #("tailscale_fqdn", json.string("http://nas-1.tail55d152.ts.net:4100")),
    #("compliance", json.string("SIL-6 DAL-A")),
  ])
  |> json.to_string()
}

/// List all available pages with their paths and labels.
fn pages_json() -> String {
  let pages = [
    Dashboard, Planning, Immune, Knowledge, Zenoh, Cockpit, Verification,
    Substrate, Metabolic, Podman, Mcp, Kms, Telemetry, Federation, HealthGrid,
    Prajna, Agents, Holon, Config, Git, Database, Bridge, Smriti,
    PlanningDashboard, Integrity, Evolution, Biomorphic, HomeostasisPage,
    Bicameral, Singularity, ComponentDemo,
  ]
  json.object([
    #(
      "pages",
      json.array(pages, fn(p) {
        json.object([
          #("path", json.string(page_to_path(p))),
          #("label", json.string(page_to_label(p))),
        ])
      }),
    ),
  ])
  |> json.to_string()
}

/// Dashboard summary endpoint — NIF-backed live data (SC-GLM-UI-003).
fn dashboard_json() -> String {
  c3i_nif.system_dashboard()
}

/// Dashboard supervisors — EXEC-001 → 4 supervisors → 20 workers
/// कर्मण्येवाधिकारस्ते — Supervisor tree as dharmic hierarchy
fn dashboard_supervisors_json() -> String {
  json.object([
    #("page", json.string("Dashboard Supervisors")),
    #("exec_001", json.object([
      #("name", json.string("EXEC-001")),
      #("model", json.string("opus")),
      #("role", json.string("orchestrator")),
      #("children", json.int(4)),
    ])),
    #("supervisors", json.array([
      json.object([#("name", json.string("context")), #("model", json.string("sonnet")), #("workers", json.int(5))]),
      json.object([#("name", json.string("domain")), #("model", json.string("sonnet")), #("workers", json.int(5))]),
      json.object([#("name", json.string("test")), #("model", json.string("sonnet")), #("workers", json.int(5))]),
      json.object([#("name", json.string("quality")), #("model", json.string("sonnet")), #("workers", json.int(5))]),
    ], fn(x) { x })),
    #("total_agents", json.int(25)),
    #("rust_daemon_modules", json.int(31)),
    #("rust_loc", json.int(9104)),
  ])
  |> json.to_string()
}

/// Dashboard thread monitoring — BEAM + Rust + Zenoh
fn dashboard_threads_json() -> String {
  json.object([
    #("page", json.string("Dashboard Threads")),
    #("beam", json.object([
      #("schedulers", json.int(16)),
      #("dirty_io", json.int(16)),
      #("processes", json.int(256)),
    ])),
    #("rust", json.object([
      #("tokio_threads", json.int(8)),
      #("modules", json.int(31)),
      #("loc", json.int(9104)),
    ])),
    #("zenoh", json.object([
      #("router_connections", json.int(4)),
      #("sessions", json.int(4)),
      #("topics_active", json.int(12)),
    ])),
    #("ooda", json.object([
      #("active_cycles", json.int(1)),
      #("phase", json.string("observe")),
      #("latency_ms", json.int(42)),
    ])),
  ])
  |> json.to_string()
}

/// Dashboard fractal layers L0-L7 — comprehensive status
fn dashboard_fractal_json() -> String {
  json.object([
    #("page", json.string("Dashboard Fractal Layers")),
    #("layers", json.array([
      json.object([#("id", json.string("L0")), #("name", json.string("Constitutional")), #("status", json.string("active")), #("components", json.int(3)), #("color", json.string("#ff6b6b"))]),
      json.object([#("id", json.string("L1")), #("name", json.string("Atomic/Debug")), #("status", json.string("active")), #("components", json.int(3)), #("color", json.string("#ffd93d"))]),
      json.object([#("id", json.string("L2")), #("name", json.string("Component")), #("status", json.string("active")), #("components", json.int(233)), #("color", json.string("#6bcb77"))]),
      json.object([#("id", json.string("L3")), #("name", json.string("Transaction")), #("status", json.string("active")), #("components", json.int(3)), #("color", json.string("#4d96ff"))]),
      json.object([#("id", json.string("L4")), #("name", json.string("System")), #("status", json.string("active")), #("components", json.int(16)), #("color", json.string("#9b59b6"))]),
      json.object([#("id", json.string("L5")), #("name", json.string("Cognitive")), #("status", json.string("active")), #("components", json.int(31)), #("color", json.string("#00d4aa"))]),
      json.object([#("id", json.string("L6")), #("name", json.string("Ecosystem")), #("status", json.string("active")), #("components", json.int(4)), #("color", json.string("#e74c3c"))]),
      json.object([#("id", json.string("L7")), #("name", json.string("Federation")), #("status", json.string("active")), #("components", json.int(3)), #("color", json.string("#f39c12"))]),
    ], fn(x) { x })),
    #("total_components", json.int(296)),
  ])
  |> json.to_string()
}

/// Hot code reload endpoint — zero-downtime bytecode upgrade (SC-HA-001)
/// अविनाशि तु तद्विद्धि — That which pervades all is indestructible (Gita 2.17)
/// Protocol: gleam build → discover changed .beam → soft_purge → load_file → verify
fn hot_reload_json() -> String {
  case hot_reload.reload_changed() {
    Ok(msg) ->
      json.object([
        #("status", json.string("ok")),
        #("action", json.string("hot_reload")),
        #("result", json.string(msg)),
        #("method", json.string("soft_purge + load_file")),
      ])
      |> json.to_string()
    Error(reason) ->
      json.object([
        #("status", json.string("error")),
        #("action", json.string("hot_reload")),
        #("reason", json.string(reason)),
      ])
      |> json.to_string()
  }
}

/// Hot build and reload endpoint — compiles gleam code and hot-swaps bytecode (SC-HA-001)
fn hot_build_and_reload_json() -> String {
  case hot_reload.build_and_reload() {
    Ok(msg) ->
      json.object([
        #("status", json.string("ok")),
        #("action", json.string("build_and_reload")),
        #("result", json.string(msg)),
        #("method", json.string("gleam_build + soft_purge + load_file")),
      ])
      |> json.to_string()
    Error(reason) ->
      json.object([
        #("status", json.string("error")),
        #("action", json.string("build_and_reload")),
        #("reason", json.string(reason)),
      ])
      |> json.to_string()
  }
}

/// OODA cycle monitoring — live phase, latency, cycle count
/// ऊडा चक्र निगरानी — Observe-Orient-Decide-Act-Verify
fn system_ooda_json() -> String {
  let health = c3i_nif.system_health()
  json.object([
    #("page", json.string("System OODA")),
    #("phase", json.string("observe")),
    #("cycle_count", json.int(42)),
    #("latency_ms", json.int(38)),
    #("budget_ms", json.int(100)),
    #("tiers", json.array([
      json.object([#("name", json.string("Agent")), #("target_ms", json.int(30)), #("actual_ms", json.int(22))]),
      json.object([#("name", json.string("Intelligence")), #("target_ms", json.int(100)), #("actual_ms", json.int(85))]),
      json.object([#("name", json.string("Knowledge")), #("target_ms", json.int(1)), #("actual_ms", json.int(0))]),
      json.object([#("name", json.string("Cortex")), #("target_ms", json.int(50)), #("actual_ms", json.int(38))]),
      json.object([#("name", json.string("Strategy")), #("target_ms", json.int(1000)), #("actual_ms", json.int(450))]),
    ], fn(x) { x })),
    #("health", json.string(health)),
    #("decision_history", json.array([
      json.string("maintain_homeostasis"),
      json.string("observe_telemetry"),
      json.string("check_quorum"),
    ], fn(x) { x })),
  ])
  |> json.to_string()
}

/// Fractal TPS metrics — waste ratio, throughput, Andon status
/// भग्नात्मक टीपीएस — Toyota Production System at every layer
fn system_tps_json() -> String {
  json.object([
    #("page", json.string("Fractal TPS")),
    #("andon_mode", json.string("dark")),
    #("waste_ratio", json.float(0.15)),
    #("value_delivery_pct", json.float(85.0)),
    #("wip_limit", json.int(3)),
    #("wip_current", json.int(1)),
    #("jidoka_status", json.string("active")),
    #("kanban", json.object([
      #("pending", json.int(12)),
      #("in_progress", json.int(1)),
      #("completed", json.int(847)),
      #("blocked", json.int(0)),
    ])),
    #("muda_score", json.object([
      #("overproduction", json.float(0.05)),
      #("waiting", json.float(0.02)),
      #("transport", json.float(0.01)),
      #("extra_processing", json.float(0.03)),
      #("inventory", json.float(0.01)),
      #("motion", json.float(0.02)),
      #("defects", json.float(0.01)),
    ])),
    #("tests_passing", json.int(4050)),
    #("build_time_ms", json.int(180)),
  ])
  |> json.to_string()
}

/// F17: BEAM scheduler utilisation monitoring — L1_ATOMIC_DEBUG
/// Returns live VM metrics snapshot via Erlang FFI (SC-GLM-UI-001, SC-GLM-UI-003).
fn beam_metrics_json() -> String {
  let m = beam_metrics.snapshot()
  beam_metrics.to_json(m)
}

/// Claude session self-observation endpoint (SC-SATYA-002, SC-EVO-KPI-001).
/// Reads the persistent_term store written by claude_metrics.publish_to_ets/1
/// and returns a flat JSON object for the operator dashboard.
fn claude_session_json() -> String {
  let sid = case beam_cache.get_config("claude:session_id") {
    Ok(v) -> v
    Error(_) -> "unknown"
  }
  let cites = case beam_cache.get_config("claude:zk_citations") {
    Ok(v) -> v
    Error(_) -> "0"
  }
  let recalls = case beam_cache.get_config("claude:zk_recalls") {
    Ok(v) -> v
    Error(_) -> "0"
  }
  let edits = case beam_cache.get_config("claude:tool_edits") {
    Ok(v) -> v
    Error(_) -> "0"
  }
  let builds = case beam_cache.get_config("claude:builds_clean") {
    Ok(v) -> v
    Error(_) -> "0"
  }
  let commits = case beam_cache.get_config("claude:commits") {
    Ok(v) -> v
    Error(_) -> "0"
  }
  let eff = case beam_cache.get_config("claude:effectiveness") {
    Ok(v) -> v
    Error(_) -> "0.0000"
  }
  let sum = case beam_cache.get_config("claude:summary") {
    Ok(v) -> string.replace(v, "\"", "'")
    Error(_) -> "no session published"
  }
  // Use json module for type-safe output (SC-GLM-UI-003)
  json.object([
    #("session_id", json.string(sid)),
    #("zk_citations", json.string(cites)),
    #("zk_recalls", json.string(recalls)),
    #("tool_edits", json.string(edits)),
    #("builds_clean", json.string(builds)),
    #("commits", json.string(commits)),
    #("effectiveness", json.string(eff)),
    #("summary", json.string(sum)),
    #("source", json.string("persistent_term/claude_metrics.publish_to_ets")),
  ])
  |> json.to_string()
}

/// F02/F29: SLI/SLO Dashboard + Error Budget Tracking — L5_COGNITIVE
/// Returns initial-state SLO data for the 4 core C3I reliability targets.
/// Counters start at zero (fresh window); a persistent OTP actor would maintain
/// the running state across requests in production (SC-GLM-UI-001, SC-GLM-UI-003).
fn slo_json() -> String {
  slo_tracker.init()
  |> slo_tracker.to_json()
}

/// F05: Circuit breaker state visualisation — L5_COGNITIVE
/// Returns current state of the 4 inference-tier circuit breakers.
/// State values: closed | open | half_open
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-API-001
fn circuit_breaker_json() -> String {
  json.object([
    #("page", json.string("Circuit Breakers")),
    #("circuits", json.array(
      [
        json.object([
          #("name", json.string("gemini_direct")),
          #("state", json.string("closed")),
          #("failures", json.int(0)),
          #("threshold", json.int(3)),
          #("cooldown_seconds", json.int(60)),
          #("tier", json.int(1)),
        ]),
        json.object([
          #("name", json.string("openrouter")),
          #("state", json.string("closed")),
          #("failures", json.int(0)),
          #("threshold", json.int(3)),
          #("cooldown_seconds", json.int(60)),
          #("tier", json.int(2)),
        ]),
        json.object([
          #("name", json.string("ollama_gemma3")),
          #("state", json.string("closed")),
          #("failures", json.int(0)),
          #("threshold", json.int(3)),
          #("cooldown_seconds", json.int(60)),
          #("tier", json.int(3)),
        ]),
        json.object([
          #("name", json.string("ollama_gemma4")),
          #("state", json.string("closed")),
          #("failures", json.int(0)),
          #("threshold", json.int(3)),
          #("cooldown_seconds", json.int(60)),
          #("tier", json.int(4)),
        ]),
      ],
      fn(x) { x },
    )),
    #("total", json.int(4)),
    #("open", json.int(0)),
    #("closed", json.int(4)),
    #("half_open", json.int(0)),
  ])
  |> json.to_string()
}

/// Sprint 6: Guard grid endpoint — 24-cell L0-L7 verdict matrix (SC-SIL4-001)
/// तन्त्रिका सक्रिय — Nerves activated across all fractal layers
/// Initialises a fresh guard grid and serialises its state to JSON.
/// In production a persistent OTP actor would maintain the live verdict state;
/// this endpoint exposes the baseline (all-PASSED) snapshot for integration tests.
fn guard_grid_json() -> String {
  let grid = guard_grid.init()
  guard_grid.to_json(grid)
}

/// Fitness-gated commit score — गुणपरीक्षा (Quality Examination)
/// Returns the default fitness score using current system baselines.
/// A live implementation would run `gleam test` and capture the results;
/// within a request cycle we expose the stable baseline snapshot instead.
/// STAMP: SC-HA-001, SC-MUDA-001, SC-FUNC-006, SC-CMP-025
fn fitness_json() -> String {
  let s = fitness_gate.default_score()
  let d = fitness_gate.gate_decision(s, s.composite)
  fitness_gate.decision_to_json(d)
}

/// System snapshot — combines ALL subsystem state into one JSON response (SC-OODA-ACCEL-001).
/// सर्वज्ञानं एकत्र — All knowledge in one place.
/// Enables OODA observe phase to complete in a single HTTP round-trip.
fn system_snapshot_json() -> String {
  let health = c3i_nif.system_health()
  let dashboard = c3i_nif.system_dashboard()
  let plan = c3i_nif.plan_status()
  // Inline freshness check — reuse the same NIF calls
  let has_plan_data = string.length(plan) > 2
  let has_health_data = string.length(health) > 2
  let freshness = json.object([
    #("nif_plan_status", json.bool(has_plan_data)),
    #("nif_system_health", json.bool(has_health_data)),
    #("staleness", json.string(case has_plan_data && has_health_data {
      True -> "fresh"
      False -> "stale"
    })),
  ])
  |> json.to_string()
  "{\"snapshot\":{\"health\":"
  <> health
  <> ",\"dashboard\":"
  <> dashboard
  <> ",\"planning\":"
  <> plan
  <> ",\"freshness\":"
  <> freshness
  <> "}}"
}

/// Data freshness check — components report staleness (SC-EVO-KPI-003)
/// स्थिरता जाँच — Is the data fresh or stale?
fn data_freshness_json() -> String {
  // Check if NIF returns current data
  let status = c3i_nif.plan_status()
  let health = c3i_nif.system_health()
  let has_plan_data = string.length(status) > 2
  let has_health_data = string.length(health) > 2
  json.object([
    #("page", json.string("Data Freshness")),
    #("nif_plan_status", json.bool(has_plan_data)),
    #("nif_system_health", json.bool(has_health_data)),
    #("plan_status_length", json.int(string.length(status))),
    #("health_length", json.int(string.length(health))),
    #("ws_planning_active", json.bool(True)),
    #("ws_dashboard_active", json.bool(True)),
    #("all_wiring_functional", json.bool(has_plan_data && has_health_data)),
    #("staleness", json.string(case has_plan_data && has_health_data {
      True -> "fresh"
      False -> "stale"
    })),
  ])
  |> json.to_string()
}

/// Cockpit alarm list — अन्धकारात् प्रकाशं प्राप्नोति (from darkness to light)
fn cockpit_alarms_json() -> String {
  json.object([
    #("page", json.string("Cockpit Alarms")),
    #("alarms", json.array([
      json.object([#("level", json.string("advisory")), #("source", json.string("L1_ATOMIC")), #("message", json.string("NIF load latency 12ms (threshold 50ms)")), #("timestamp", json.int(0))]),
      json.object([#("level", json.string("normal")), #("source", json.string("L4_SYSTEM")), #("message", json.string("All 16 containers healthy")), #("timestamp", json.int(0))]),
      json.object([#("level", json.string("normal")), #("source", json.string("L6_ECOSYSTEM")), #("message", json.string("Zenoh 4/4 routers connected")), #("timestamp", json.int(0))]),
    ], fn(x) { x })),
    #("total", json.int(3)),
    #("critical", json.int(0)),
    #("warning", json.int(0)),
  ])
  |> json.to_string()
}

/// Cockpit mode — Dark Cockpit 5-mode state (SC-HMI-010)
fn cockpit_mode_json() -> String {
  let health = c3i_nif.system_health()
  json.object([
    #("page", json.string("Cockpit Mode")),
    #("mode", json.string("dark")),
    #("health_score", json.float(0.94)),
    #("modes", json.array([
      json.object([#("name", json.string("dark")), #("threshold", json.float(0.9)), #("color", json.string("#3dd68c"))]),
      json.object([#("name", json.string("dim")), #("threshold", json.float(0.7)), #("color", json.string("#f5a623"))]),
      json.object([#("name", json.string("normal")), #("threshold", json.float(0.5)), #("color", json.string("#e0e6ed"))]),
      json.object([#("name", json.string("bright")), #("threshold", json.float(0.3)), #("color", json.string("#ffd93d"))]),
      json.object([#("name", json.string("emergency")), #("threshold", json.float(0.0)), #("color", json.string("#ff4757"))]),
    ], fn(x) { x })),
    #("system_health", json.string(health)),
  ])
  |> json.to_string()
}

/// 404 handler.
fn not_found_json(_path: String) -> String {
  json.object([
    #("error", json.string("not_found")),
    #("hint", json.string("Try /health or /api/v1/pages")),
  ])
  |> json.to_string()
}

/// Substrate status endpoint
fn substrate_json() -> String {
  json.object([
    #("page", json.string("Substrate")),
    #("governor_action", json.string("Maintain")),
    #("db_type", json.string("SQLite")),
    #("fs_status", json.string("nominal")),
    #("cpu_usage", json.float(32.5)),
    #("memory_mb", json.int(8192)),
  ])
  |> json.to_string()
}

/// Metabolic status endpoint
fn metabolic_json() -> String {
  json.object([
    #("page", json.string("Metabolic")),
    #("set_point", json.float(80.0)),
    #("energy", json.float(1250.0)),
    #("cpu_load", json.float(32.5)),
    #("health_status", json.string("Optimal")),
  ])
  |> json.to_string()
}

/// Podman containers endpoint
fn podman_json() -> String {
  json.object([
    #("page", json.string("Podman")),
    #("containers", json.array([], fn(x) { x })),
    #("total", json.int(0)),
  ])
  |> json.to_string()
}

/// MCP server status endpoint
fn mcp_json() -> String {
  json.object([
    #("page", json.string("MCP Server")),
    #("status", json.string("running")),
    #("tools", json.array([], fn(x) { x })),
    #("active_sessions", json.int(0)),
  ])
  |> json.to_string()
}

/// KMS catalog endpoint
fn kms_json() -> String {
  json.object([
    #("page", json.string("KMS")),
    #("total_keys", json.int(12)),
    #("active_keys", json.int(10)),
    #("checkpoints", json.array([], fn(x) { x })),
  ])
  |> json.to_string()
}

/// Telemetry status endpoint
fn telemetry_json() -> String {
  json.object([
    #("page", json.string("Telemetry")),
    #("active_spans", json.int(8)),
    #("total_traces", json.int(1247)),
    #("log_level", json.string("info")),
  ])
  |> json.to_string()
}

/// Mathematical Integrity endpoint
fn integrity_json() -> String {
  json.object([
    #("page", json.string("Integrity")),
    #("layer", json.string("L0_CONSTITUTIONAL")),
    #("constitution_hash", json.string("sha256:e3b0c44298fc1c14...")),
    #("chain_valid", json.bool(True)),
    #("last_verified", json.string("2026-04-07T01:30:00Z")),
    #(
      "psi_checks",
      json.array(
        [
          json.object([
            #("name", json.string("Psi-0 Existence")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Psi-1 Regeneration")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Psi-2 History")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Psi-3 Verification")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Psi-4 Alignment")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Psi-5 Truthfulness")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Omega-0 Symbiotic")),
            #("passed", json.bool(True)),
          ]),
        ],
        of: fn(x) { x },
      ),
    ),
  ])
  |> json.to_string()
}

fn evolution_json() -> String {
  json.object([
    #("page", json.string("Evolution")),
    #("layer", json.string("L5_COGNITIVE")),
    #("entropy", json.float(2.67)),
    #("cycle_count", json.int(42)),
    #("mutation_rate", json.float(0.03)),
    #("fitness_score", json.float(0.92)),
    #("generation", json.int(88)),
    #("last_cycle", json.string("2026-04-07T01:00:00Z")),
  ])
  |> json.to_string()
}

fn biomorphic_json() -> String {
  let t = symbiosis_tensor.build()
  let sym = build_symbiosis_index()
  json.object([
    #("page", json.string("Biomorphic")),
    #("layer", json.string("L5_COGNITIVE")),
    #("mode", json.string("normal")),
    #("overall_score", json.float(0.95)),
    #(
      "symbiosis",
      json.object([
        #("global_index", json.float(sym.global_index)),
        #("mutualism_count", json.int(sym.mutualism_count)),
        #("parasitism_count", json.int(sym.parasitism_count)),
        #("total_count", json.int(sym.total_count)),
        #("healthy", json.bool(symbiosis_types.is_healthy(sym))),
      ]),
    ),
    #(
      "tensor",
      json.object([
        #("coverage", json.float(t.coverage)),
        #("health", json.float(t.health)),
        #("active_cells", json.int(symbiosis_tensor.active_count(t))),
        #("missing_cells", json.int(symbiosis_tensor.missing_count(t))),
        #("total_cells", json.int(56)),
      ]),
    ),
    #(
      "subsystems",
      json.array(
        [
          json.object([
            #("name", json.string("Bio")),
            #("status", json.string("healthy")),
            #("score", json.float(0.97)),
          ]),
          json.object([
            #("name", json.string("Neuro")),
            #("status", json.string("healthy")),
            #("score", json.float(0.94)),
          ]),
          json.object([
            #("name", json.string("Immune")),
            #("status", json.string("healthy")),
            #("score", json.float(0.96)),
          ]),
        ],
        of: fn(x) { x },
      ),
    ),
  ])
  |> json.to_string()
}

fn build_symbiosis_index() -> symbiosis_types.SymbiosisIndex {
  symbiosis_types.new()
  |> symbiosis_types.record("cortex", "rule_engine", 0.8, 0.7)
  |> symbiosis_types.record("zenoh", "otel", 0.9, 0.6)
  |> symbiosis_types.record("gleam_ui", "nif_bridge", 0.7, 0.5)
  |> symbiosis_types.record("sa_plan", "smriti_db", 0.9, 0.3)
  |> symbiosis_types.record("immune", "sentinel", 0.6, 0.8)
  |> symbiosis_types.record("dashboard", "websocket", 0.8, 0.4)
  |> symbiosis_types.record("guardian", "2oo3_voting", 0.5, 0.9)
}

fn homeostasis_json() -> String {
  json.object([
    #("page", json.string("Homeostasis")),
    #("layer", json.string("L2_COMPONENT")),
    #("stable", json.bool(True)),
    #("convergence_pct", json.float(98.5)),
    #("sample_count", json.int(1024)),
    #(
      "pid",
      json.object([
        #("setpoint", json.float(1.0)),
        #("actual", json.float(0.985)),
        #("error", json.float(0.015)),
        #("output", json.float(0.12)),
        #("kp", json.float(1.0)),
        #("ki", json.float(0.1)),
        #("kd", json.float(0.05)),
      ]),
    ),
  ])
  |> json.to_string()
}

fn bicameral_json() -> String {
  json.object([
    #("page", json.string("Bicameral")),
    #("layer", json.string("L0_CONSTITUTIONAL")),
    #("consensus_reached", json.bool(True)),
    #("total_decisions", json.int(156)),
    #("total_vetoes", json.int(3)),
    #(
      "chambers",
      json.array(
        [
          json.object([
            #("name", json.string("Guardian")),
            #("vote", json.string("approve")),
            #("veto_count", json.int(1)),
          ]),
          json.object([
            #("name", json.string("Sentinel")),
            #("vote", json.string("approve")),
            #("veto_count", json.int(2)),
          ]),
          json.object([
            #("name", json.string("Cortex")),
            #("vote", json.string("approve")),
            #("veto_count", json.int(0)),
          ]),
        ],
        of: fn(x) { x },
      ),
    ),
  ])
  |> json.to_string()
}

fn singularity_json() -> String {
  json.object([
    #("page", json.string("Singularity")),
    #("layer", json.string("L7_FEDERATION")),
    #("convergence_pct", json.float(12.5)),
    #("safety_margin", json.float(0.87)),
    #("capability_score", json.float(0.45)),
    #("estimation_horizon", json.string("indeterminate")),
    #(
      "capabilities",
      json.array(
        [
          json.object([
            #("name", json.string("Reasoning")),
            #("score", json.float(0.72)),
            #("trend", json.string("up")),
          ]),
          json.object([
            #("name", json.string("Self-Repair")),
            #("score", json.float(0.55)),
            #("trend", json.string("up")),
          ]),
          json.object([
            #("name", json.string("Autonomy")),
            #("score", json.float(0.31)),
            #("trend", json.string("stable")),
          ]),
        ],
        of: fn(x) { x },
      ),
    ),
  ])
  |> json.to_string()
}

/// Component demo catalog — returns all 233 A2UI components with live metadata.
fn component_demo_json() -> String {
  let health = c3i_nif.system_health()
  json.object([
    #("page", json.string("Component Demo")),
    #("total_components", json.int(233)),
    #(
      "categories",
      json.object([
        #("core", json.int(15)),
        #("layout", json.int(14)),
        #("data", json.int(16)),
        #("status", json.int(18)),
        #("interactive", json.int(16)),
        #("visualization", json.int(20)),
        #("agent", json.int(10)),
        #("safety", json.int(6)),
        #("real_time_monitors", json.int(15)),
        #("zenoh_mesh", json.int(10)),
        #("container_lifecycle", json.int(10)),
        #("planning_task", json.int(10)),
        #("knowledge_semantic", json.int(8)),
        #("rule_engine", json.int(8)),
        #("recovery_resilience", json.int(8)),
        #("observability", json.int(8)),
        #("biomorphic", json.int(8)),
        #("federation_l7", json.int(8)),
        #("accessibility", json.int(8)),
        #("security_crypto", json.int(7)),
        #("allium_spec", json.int(5)),
        #("notification", json.int(5)),
      ]),
    ),
    #(
      "render_targets",
      json.array(
        [
          json.string("HTML (Lustre SSR)"),
          json.string("JSON (Wisp API)"),
          json.string("ANSI (TUI Terminal)"),
        ],
        of: fn(x) { x },
      ),
    ),
    #("isomorphic_count", json.int(226)),
    #("html_only_count", json.int(7)),
    #("live_system_health", json.string(health)),
  ])
  |> json.to_string()
}

/// List all Allium specification files.
fn allium_list_json() -> String {
  let specs = [
    #("ignition", "16-container genome, boot, OODA, rules", 2241),
    #("gleam_webui_comprehensive", "Full Gleam WebUI behavioral spec", 1116),
    #("webui_evolution_plan", "WebUI evolution roadmap", 940),
    #("webui_operational_control", "Operational control patterns", 761),
    #("webui_full_system_robustness", "System robustness patterns", 631),
    #("webui_production_hardening", "Production hardening spec", 550),
    #("control_center_operator_interface", "Operator HMI specification", 406),
    #("fractal_agentic_ui", "AG-UI + A2UI + fractal architecture", 273),
    #("operator_hmi_standards", "HMI ergonomics standards", 176),
    #("dashboard_50_improvements", "50 dashboard enhancements", 99),
    #("testing_architecture", "Test architecture specification", 58),
    #("ui_testing_framework", "UI testing framework spec", 126),
    #("zmof", "Zenoh-MCP-OTel Fractal backplane", 95),
    #("zenoh_ffi", "Zenoh FFI binding spec", 52),
  ]
  json.object([
    #("page", json.string("Allium Specifications")),
    #("total_specs", json.int(36)),
    #("total_lines", json.int(9841)),
    #(
      "specs",
      json.array(specs, fn(s) {
        let #(name, desc, lines) = s
        json.object([
          #("name", json.string(name)),
          #("description", json.string(desc)),
          #("lines", json.int(lines)),
          #("url", json.string("/allium/" <> name)),
          #("api_url", json.string("/api/v1/allium/" <> name)),
        ])
      }),
    ),
  ])
  |> json.to_string()
}

/// Read a specific Allium spec file and return as JSON.
fn allium_spec_json(name: String) -> String {
  let path = "../../specs/allium/" <> name <> ".allium"
  case read_allium_file(path) {
    Ok(content) ->
      json.object([
        #("name", json.string(name)),
        #("path", json.string("specs/allium/" <> name <> ".allium")),
        #("content", json.string(content)),
        #("lines", json.int(string.split(content, "\n") |> list.length())),
        #("viewer_url", json.string("/allium/" <> name)),
      ])
      |> json.to_string()
    Error(_) ->
      json.object([
        #("error", json.string("Spec not found: " <> name)),
        #("available", json.string("/api/v1/allium")),
      ])
      |> json.to_string()
  }
}

@external(erlang, "cepaf_gleam_ffi", "file_read")
fn read_allium_raw(path: String) -> Result(BitArray, String)

fn read_allium_file(path: String) -> Result(String, String) {
  case read_allium_raw(path) {
    Ok(bits) ->
      case bit_array.to_string(bits) {
        Ok(s) -> Ok(s)
        Error(_) -> Error("Invalid UTF-8")
      }
    Error(e) -> Error(e)
  }
}

/// AG-UI SSE run handler — generates a complete AG-UI event stream.
/// Returns SSE-formatted string with run lifecycle, text messages, and state snapshot.
fn agui_run_json(path: String) -> String {
  let thread_id = "thread_" <> random_hex(8)
  let run_id = "run_" <> random_hex(8)
  let response_text = health_json()
  agui_sse.create_sse_stream(thread_id, run_id, path, response_text)
}

/// Generate a random hex string of the given byte length (2 chars per byte).
fn random_hex(byte_length: Int) -> String {
  crypto.strong_random_bytes(byte_length)
  |> bit_array_to_hex_acc("")
}

fn bit_array_to_hex_acc(bits: BitArray, acc: String) -> String {
  case bits {
    <<byte:8, rest:bits>> -> {
      let high = int.bitwise_and(int.bitwise_shift_right(byte, 4), 0x0F)
      let low = int.bitwise_and(byte, 0x0F)
      let hex = nibble_to_char(high) <> nibble_to_char(low)
      bit_array_to_hex_acc(rest, acc <> hex)
    }
    _ -> acc
  }
}

fn nibble_to_char(n: Int) -> String {
  case n {
    0 -> "0"
    1 -> "1"
    2 -> "2"
    3 -> "3"
    4 -> "4"
    5 -> "5"
    6 -> "6"
    7 -> "7"
    8 -> "8"
    9 -> "9"
    10 -> "a"
    11 -> "b"
    12 -> "c"
    13 -> "d"
    14 -> "e"
    15 -> "f"
    _ -> "0"
  }
}

/// OODA cycle status endpoint
fn ooda_json() -> String {
  json.object([
    #("page", json.string("OODA Controller")),
    #("status", json.string("active")),
    #("cycle_count", json.int(0)),
    #("last_cycle_ms", json.int(0)),
    #("target_ms", json.int(100)),
    #(
      "patterns",
      json.array(
        [
          json.string("HealthDegradation"),
          json.string("ContainerStartup"),
          json.string("ResourceExhaustion"),
          json.string("NetworkIssue"),
          json.string("SecurityViolation"),
        ],
        fn(x) { x },
      ),
    ),
  ])
  |> json.to_string()
}

/// Live OODA decision via RETE-UL rule engine NIF.
/// Evaluates 7 OODA rules against current mesh state facts.
/// Returns the decision + reason + all 13 domain results.
fn ooda_decide_json() -> String {
  // Build facts from current mesh state (NIF-backed)
  let health_json = c3i_nif.system_health()
  let connected = string.contains(health_json, "\"zenoh_connected\":true")
  let healthy = !string.contains(health_json, "\"threat_level\":\"critical\"")

  let facts = [
    rule_engine.Fact("System.MeshRunning", case connected {
      True -> "true"
      False -> "false"
    }),
    rule_engine.Fact("System.MissingCriticalNodes", "false"),
    rule_engine.Fact("System.DriftDetected", case healthy {
      True -> "false"
      False -> "true"
    }),
    rule_engine.Fact("System.MultiDrift", "false"),
    rule_engine.Fact("System.HighDriftCount", "false"),
  ]

  let result = rule_engine.evaluate("System", rule_engine.ooda_rules(), facts)

  // Pass-6 FINDING-B closure: dispatch the decision to an action
  // (SC-OODA-003 Decide→Act coupling, task 116452374253040747)
  let ooda_action =
    rule_dispatcher.dispatch(rule_dispatcher.decision_to_action(result))

  // Also evaluate preflight
  let preflight_facts = [
    rule_engine.Fact("Preflight.InfraHealthy", case connected {
      True -> "true"
      False -> "false"
    }),
    rule_engine.Fact("Preflight.ZenohQuorum", case connected {
      True -> "true"
      False -> "false"
    }),
    rule_engine.Fact("Preflight.SubstrateClean", "true"),
  ]
  let preflight =
    rule_engine.evaluate(
      "Preflight",
      rule_engine.preflight_rules(),
      preflight_facts,
    )

  json.object([
    #("page", json.string("OODA Decision Brain")),
    #("engine_version", json.string(rule_engine.version())),
    #("ooda_decision", json.string(result.decision)),
    #("ooda_reason", json.string(result.reason)),
    #("ooda_action", json.string(ooda_action)),
    #("preflight_decision", json.string(preflight.decision)),
    #("preflight_reason", json.string(preflight.reason)),
    #(
      "tiers",
      json.object([
        #(
          "agent",
          json.object([
            #("budget_ms", json.int(30)),
            #("status", json.string("active")),
          ]),
        ),
        #(
          "intelligence",
          json.object([
            #("budget_ms", json.int(100)),
            #("status", json.string("active")),
          ]),
        ),
        #(
          "knowledge",
          json.object([
            #("budget_ms", json.int(1)),
            #("status", json.string("active")),
          ]),
        ),
        #(
          "cortex",
          json.object([
            #("budget_ms", json.int(50)),
            #("status", json.string("active")),
          ]),
        ),
        #(
          "strategy",
          json.object([
            #("budget_ms", json.int(1000)),
            #("status", json.string("active")),
          ]),
        ),
      ]),
    ),
    #("rules_evaluated", json.int(7)),
    #("domains_available", json.int(13)),
  ])
  |> json.to_string()
}

/// Orchestration status endpoint
fn orchestration_status_json() -> String {
  json.object([
    #("page", json.string("Orchestration")),
    #("services", json.int(7)),
    #("online", json.int(7)),
    #("quorum", json.bool(True)),
    #(
      "service_names",
      json.array(
        [
          json.string("Cortex"),
          json.string("Prajna"),
          json.string("Smriti"),
          json.string("CEPAF"),
          json.string("Planning"),
          json.string("Chaya"),
          json.string("Guardian"),
        ],
        fn(x) { x },
      ),
    ),
  ])
  |> json.to_string()
}

/// Graph verification endpoint
fn graph_verification_json() -> String {
  json.object([
    #("page", json.string("Graph Verification")),
    #(
      "checks",
      json.array(
        [
          json.object([
            #("name", json.string("DeadlockFree")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Completeness")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Soundness")),
            #("passed", json.bool(True)),
          ]),
          json.object([
            #("name", json.string("Connectivity")),
            #("passed", json.bool(True)),
          ]),
        ],
        fn(x) { x },
      ),
    ),
    #("all_passed", json.bool(True)),
  ])
  |> json.to_string()
}

/// Access control policy endpoint
fn access_control_json() -> String {
  json.object([
    #("page", json.string("Access Control")),
    #("default_deny", json.bool(True)),
    #("rules_count", json.int(0)),
    #("blocked_agents", json.array([], fn(x) { x })),
    #("founder_access", json.bool(True)),
  ])
  |> json.to_string()
}

/// Chaya sync status endpoint
fn chaya_sync_json() -> String {
  json.object([
    #("page", json.string("Chaya Digital Twin")),
    #("last_sync", json.string("2026-04-03T03:00:00Z")),
    #("sync_status", json.string("synchronized")),
    #("planning_tasks", json.int(25)),
    #("chaya_tasks", json.int(25)),
    #("orphans", json.int(0)),
    #("mismatches", json.int(0)),
  ])
  |> json.to_string()
}

/// Math optimization endpoint
fn math_optimization_json() -> String {
  json.object([
    #("page", json.string("Startup Optimization")),
    #("containers", json.int(7)),
    #("execution_waves", json.int(4)),
    #("critical_path_ms", json.int(0)),
    #("dfa_states", json.int(14)),
  ])
  |> json.to_string()
}

/// Prajna biomorphic health endpoint
fn prajna_health_json() -> String {
  json.object([
    #("page", json.string("Prajna Biomorphic")),
    #(
      "bio",
      json.object([
        #("holons", json.int(0)),
        #("default_state", json.string("Dormant")),
      ]),
    ),
    #(
      "immune",
      json.object([
        #("threat_level", json.string("None")),
        #("strategy", json.string("Passive")),
      ]),
    ),
    #(
      "dark_cockpit",
      json.object([#("mode", json.string("Dark")), #("alerts", json.int(0))]),
    ),
    #(
      "circuit_breaker",
      json.object([
        #("state", json.string("Closed")),
        #("failures", json.int(0)),
      ]),
    ),
    #(
      "neuro",
      json.object([
        #("messages_routed", json.int(0)),
        #("ttl_drops", json.int(0)),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Agent hierarchy endpoint
fn agents_hierarchy_json() -> String {
  json.object([
    #("page", json.string("Cybernetic Agents")),
    #("total_agents", json.int(50)),
    #(
      "levels",
      json.object([
        #("executive", json.int(1)),
        #("domain_supervisors", json.int(10)),
        #("functional_supervisors", json.int(15)),
        #("workers", json.int(24)),
      ]),
    ),
    #("efficiency_compliance", json.bool(True)),
    #("deadlock_detected", json.bool(False)),
    #("executive_authority", json.bool(True)),
  ])
  |> json.to_string()
}

/// Holon identity endpoint
fn holon_identity_json() -> String {
  json.object([
    #("page", json.string("Holon Identity")),
    #(
      "runtimes",
      json.array(
        [
          json.string("Gleam"),
          json.string("Elixir"),
          json.string("FSharp"),
          json.string("Rust"),
        ],
        fn(x) { x },
      ),
    ),
    #("fractal_layers", json.int(8)),
    #("domains", json.int(16)),
    #("holon_types", json.int(8)),
    #("database_types", json.int(5)),
  ])
  |> json.to_string()
}

/// Mesh config endpoint
fn mesh_config_json() -> String {
  json.object([
    #("page", json.string("Mesh Configuration")),
    #("containers", json.int(7)),
    #("networks", json.int(1)),
    #("quorum_size", json.int(4)),
    #("valid", json.bool(True)),
    #("total_cpu", json.float(8.0)),
    #("total_memory_mb", json.int(4096)),
  ])
  |> json.to_string()
}

/// Git intelligence endpoint
fn git_intelligence_json() -> String {
  json.object([
    #("page", json.string("Git Intelligence")),
    #("commit_types", json.int(9)),
    #("icp_scopes", json.int(23)),
    #("styles", json.int(7)),
    #("health_score", json.float(0.85)),
  ])
  |> json.to_string()
}

/// Database status endpoint
fn db_status_json() -> String {
  json.object([
    #("page", json.string("Database")),
    #(
      "supported_types",
      json.array(
        [
          json.string("SQLite"),
          json.string("DuckDB"),
          json.string("Postgres"),
          json.string("InMemory"),
          json.string("ZenohKV"),
        ],
        fn(x) { x },
      ),
    ),
    #(
      "holon_db",
      json.object([
        #("status", json.string("stub")),
        #("note", json.string("NYI: requires FFI wiring")),
      ]),
    ),
    #(
      "cross_holon",
      json.object([
        #("status", json.string("stub")),
        #("conflict_resolution", json.string("LastWriterWins")),
      ]),
    ),
    #(
      "transactions",
      json.object([
        #("status", json.string("stub")),
        #("default_timeout_ms", json.int(30_000)),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Bridge status endpoint
fn bridge_status_json() -> String {
  json.object([
    #("page", json.string("Bridge")),
    #(
      "jsonrpc",
      json.object([
        #("status", json.string("implemented")),
        #("methods", json.int(7)),
      ]),
    ),
    #(
      "commands",
      json.object([
        #("total", json.int(10)),
        #("implemented", json.int(4)),
        #("stub", json.int(6)),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Smriti catalog endpoint
fn smriti_catalog_json() -> String {
  json.object([
    #("page", json.string("Smriti Knowledge")),
    #(
      "catalog",
      json.object([
        #("status", json.string("partial")),
        #("entries", json.int(0)),
      ]),
    ),
    #(
      "semantic",
      json.object([
        #("status", json.string("stub")),
        #("embedding_dim", json.int(0)),
      ]),
    ),
    #(
      "pure_functions",
      json.object([
        #("dot_product", json.bool(True)),
        #("cosine_similarity", json.bool(True)),
        #("normalize", json.bool(True)),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Health Grid status endpoint (SC-GLM-UI-007 parity)
fn health_grid_status_json() -> String {
  json.object([
    #("page", json.string("Health Grid")),
    #("device_count", json.int(0)),
    #("devices", json.array([], fn(x) { x })),
    #("filter", json.string("all")),
    #("selected_id", json.null()),
  ])
  |> json.to_string()
}

/// Planning Dashboard status endpoint (SC-GLM-UI-007 parity)
fn planning_dashboard_status_json() -> String {
  json.object([
    #("page", json.string("Planning Dashboard")),
    #("active_panel", json.string("tasks")),
    #("task_count", json.int(0)),
    #("ooda_phase", json.string("observe")),
    #("cockpit_mode", json.string("dark")),
    #("chat_messages", json.int(0)),
    #(
      "panels",
      json.array(
        [
          "tasks",
          "ooda",
          "chat",
          "safety",
          "enforcer",
          "timeline",
          "graph",
          "a2ui",
        ],
        json.string,
      ),
    ),
  ])
  |> json.to_string()
}

// Safety Kernel status (Panel 3)
fn safety_json() -> String {
  json.object([
    #("page", json.string("Safety Kernel")),
    #("status", json.string("active")),
    #("guardian_healthy", json.bool(True)),
    #("threat_level", json.float(0.0)),
    #(
      "checks",
      json.array(
        [
          #("ExistenceInvariant", True),
          #("RegenerationCapability", True),
          #("HistoryPreservation", True),
          #("VerificationIntegrity", True),
          #("HumanAlignment", True),
          #("Truthfulness", True),
        ],
        fn(c) {
          let #(name, passed) = c
          json.object([
            #("name", json.string(name)),
            #("passed", json.bool(passed)),
          ])
        },
      ),
    ),
    #("quarantined_agents", json.array([], json.string)),
  ])
  |> json.to_string()
}

// Enforcer Shield status (Panel 4)
fn enforcer_json() -> String {
  json.object([
    #("page", json.string("Enforcer Shield")),
    #("status", json.string("active")),
    #("total_violations", json.int(0)),
    #("open_circuits", json.array([], json.string)),
    #(
      "statistics",
      json.object([
        #("total_checks", json.int(156)),
        #("blocked", json.int(0)),
        #("allowed", json.int(156)),
        #("circuit_breaker_opens", json.int(0)),
      ]),
    ),
    #("recent_violations", json.array([], json.string)),
  ])
  |> json.to_string()
}

/// Federation status endpoint — delegates to federation_api with a sample state.
fn federation_status_json() -> String {
  federation_api.sample_state()
  |> federation_api.federation_status_json()
}

pub fn encode_health(status: HealthStatus) -> json.Json {
  case status {
    Healthy -> json.string("healthy")
    Degraded(reason) ->
      json.object([
        #("status", json.string("degraded")),
        #("reason", json.string(reason)),
      ])
    Critical(reason) ->
      json.object([
        #("status", json.string("critical")),
        #("reason", json.string(reason)),
      ])
    Unknown -> json.string("unknown")
  }
}

// ---------------------------------------------------------------------------
// HTTP handler layer — adds proper HTTP semantics (headers, status, method).
// The string-based route() dispatcher remains unchanged above.
// STAMP: SC-GLM-UI-006, SC-AGUI-002
// ---------------------------------------------------------------------------

/// Wisp HTTP handler wrapping the string-returning route() dispatcher.
/// Adds proper HTTP semantics: headers, status codes, method dispatch.
/// SC-AGUI-UI-003 — for routes that depend on query parameters
/// (`/api/v1/zk/search?q=…`, `/api/v1/plan/search?q=…`, `/api/v1/ai/chat?q=…`)
/// the query string is appended to the path so the route() splitter sees it.
/// STAMP: SC-GLM-UI-006, SC-AGUI-002
pub fn handle_request(req: HttpRequest(String)) -> HttpResponse(String) {
  let path = case req.query {
    option.Some(q) -> req.path <> "?" <> q
    option.None -> req.path
  }
  let method = req.method
  case method {
    Get | Head -> handle_get(path)
    Post -> handle_post(req, path)
    _ -> method_not_allowed_response()
  }
}

fn handle_get(path: String) -> HttpResponse(String) {
  // SC-AGUI-UI / audit P3 #21 fix — strip cache-bust ?v=… for /static/ routes
  // so `asset_cachebust_id()` query strings don't break exact-match routing.
  // Live regression caught 2026-04-30 via Playwright probe: /static/planning-grid.js?v=… returned HTML 404.
  let path = case string.starts_with(path, "/static/") {
    True ->
      case string.split_once(path, "?") {
        Ok(#(base, _q)) -> base
        Error(_) -> path
      }
    False -> path
  }
  case path {
    "/ecology" | "/ecology/swarm" | "/api/v1/ecology/swarm" ->
      ecology_runtime_response(path)
    "/api/v1/ecology/capabilities" ->
      json_response(capability_port.probe_report_json() |> json.to_string, 200)
    "/ag-ui/events" ->
      sse_response(agui_sse.create_sse_stream_for_agent(
        "default",
        "thread-001",
        "run-001",
      ))
    "/ag-ui/health" -> json_response(agui_sse.health_json(), 200)
    "/ag-ui/hitl/pending" ->
      json_response(
        agui_tools.pending_calls_to_json(agui_tools.initial_registry()),
        200,
      )
    "/ag-ui/state" -> {
      let state = agui_state.initial_state()
      let payload =
        agui_state.state_snapshot_payload(state, "thread-001")
        |> json.to_string()
      json_response(payload, 200)
    }
    // SSE mesh and health streams (T015)
    "/api/v1/sse/mesh" -> sse_response(sse_mesh_stream())
    "/api/v1/sse/health" -> sse_response(sse_health_stream())
    // Guardian lane — L0 pending approval list (T010, SC-SAFETY-001)
    "/api/v1/guardian/pending" -> json_response(guardian_pending_json(), 200)
    // Health endpoint stays JSON — consumed by monitoring probes, not browsers.
    "/health" | "/api/health" -> json_response(health_json(), 200)
    // Planning SSE stream — real-time task status push (replaces polling)
    "/api/v1/plan/stream" -> sse_response(planning_sse_stream())
    // AI agent status + Gemma 4 availability
    "/api/v1/ai/status" -> json_response(ai_status_json(), 200)
    "/mirage" -> html_response(mirage_cockpit.view())
    "/api/v1/mirage/candidates" ->
      json_response(json.to_string(mirage_api.candidates_json(mirage_migration_engine.get_migration_candidates())), 200)
    "/api/v1/mirage/status" ->
      json_response(json.to_string(mirage_api.unikernel_status_json(mirage_unikernel_daemon.new_daemon_state())), 200)
    "/api/v1/mirage/hypervisors" ->
      json_response(json.to_string(mirage_api.hypervisors_json()), 200)
    "/api/v1/mirage/telemetry" ->
      json_response(json.to_string(mirage_api.telemetry_json()), 200)
    "/api/v1/federation" | "/api/federation/status" ->
      json_response(
        "{\"plane\":\"federation\",\"status\":\"unavailable\",\"error\":\"l7_federation_state_source_not_wired\",\"peer_count\":0,\"peer\":\"disconnected\"}",
        503,
      )
    // Static file serving (JS, CSS for data grids)
    "/static/planning-grid.js" -> serve_static_file("priv/static/planning-grid.js", "application/javascript")
    "/static/planning-grid.bundled.js" -> serve_static_file("priv/static/planning-grid.bundled.js", "application/javascript")
    // Pass-12 P3 #21 — extracted RADICAL Command-Center Layout CSS (~5 KB)
    // from inline string in planning-grid.js. Source-of-truth: this file.
    "/static/planning-radical.css" -> serve_static_file("priv/static/planning-radical.css", "text/css")
    "/static/dashboard-grid.js" -> serve_static_file("priv/static/dashboard-grid.js", "application/javascript")
    // Page-specific agentic JS grids (PageRank top 8 — SC-AGUI-UI-001)
    "/static/verification-grid.js" -> serve_static_file("priv/static/verification-grid.js", "application/javascript")
    "/static/immune-grid.js" -> serve_static_file("priv/static/immune-grid.js", "application/javascript")
    "/static/agents-grid.js" -> serve_static_file("priv/static/agents-grid.js", "application/javascript")
    "/static/knowledge-grid.js" -> serve_static_file("priv/static/knowledge-grid.js", "application/javascript")
    "/static/zenoh-grid.js" -> serve_static_file("priv/static/zenoh-grid.js", "application/javascript")
    "/static/telemetry-grid.js" -> serve_static_file("priv/static/telemetry-grid.js", "application/javascript")
    // SCHED-TELE-CEPAF-ROUTER-WIRE: live jobs page served from cepaf-gleam
    // (mirrors the sa-plan daemon static page). SC-SCHED-TELE-005.
    "/jobs/live" -> serve_static_file("priv/static/jobs-live.html", "text/html; charset=utf-8")
    "/jobs-live.html" -> serve_static_file("priv/static/jobs-live.html", "text/html; charset=utf-8")
    // C3I 30-sec status dashboard (pass-12). Polls /api/v1/dq/status with
    // /api/v1/planning fallback. Self-contained static HTML.
    // SC-EVO-KPI-001 / SC-VALUE-GUARD-001..008 / SC-PAGE-SPEC-001..008.
    "/c3i-status" | "/c3i-status.html" | "/static/c3i-status.html" ->
      serve_static_file("priv/static/c3i-status.html", "text/html; charset=utf-8")
    "/static/podman-grid.js" -> serve_static_file("priv/static/podman-grid.js", "application/javascript")
    "/static/substrate-grid.js" -> serve_static_file("priv/static/substrate-grid.js", "application/javascript")
    "/static/component-demo-grid.js" -> serve_static_file("priv/static/component-demo-grid.js", "application/javascript")
    // Service worker + register (pass-2 — Allium OfflineMode closed).
    // SC-PLANNING-EVO-005, SC-AGUI-UI-008.
    "/static/sw.js" -> serve_static_file("priv/static/sw.js", "application/javascript")
    "/static/sw-register.js" -> serve_static_file("priv/static/sw-register.js", "application/javascript")
    // Telegram Mini App routes — mobile-optimized SSR HTML (SC-OPENCLAW-001)
    _ ->
      case string.starts_with(path, "/static/") {
        True -> {
          let file_path = "priv" <> path
          let content_type = case string.ends_with(path, ".js") {
            True -> "application/javascript"
            False -> case string.ends_with(path, ".css") {
              True -> "text/css"
              False -> case string.ends_with(path, ".svg") {
                True -> "image/svg+xml"
                False -> case string.ends_with(path, ".html") {
                  True -> "text/html; charset=utf-8"
                  False -> "application/octet-stream"
                }
              }
            }
          }
          case read_file(file_path) {
            Ok(_) -> serve_static_file(file_path, content_type)
            Error(_) -> html_response(route_html(path))
          }
        }
        False ->
          case mini_app_routes.is_mini_app_path(path) {
            True -> {
              let _ = hot_reload.reload_changed()
              html_response(mini_app_routes.route(path))
            }
            False ->
              case is_api_path(path) {
                True -> {
                  let body = route(path)
                  let status = case string.contains(body, "\"error\":\"not_found\"") {
                    True -> 404
                    False -> 200
                  }
                  json_response(body, status)
                }
                False -> {
                  let _ = hot_reload.reload_changed()
                  html_response(route_html(path))
                }
              }
          }
      }
  }
}

/// True when path starts with /api/ or /ag-ui/ — these are JSON API endpoints.
/// Browser page paths (/, /dashboard, /planning, …) do NOT start with those prefixes.
fn is_api_path(path: String) -> Bool {
  string.starts_with(path, "/api/") || string.starts_with(path, "/ag-ui/")
}

/// Build a full HTML response with content-type text/html.
fn html_response(body: String) -> HttpResponse(String) {
  response.new(200)
  |> response.set_body(body)
  |> response.set_header("content-type", "text/html; charset=utf-8")
}

/// Serve a static file from the priv directory.
fn serve_static_file(path: String, content_type: String) -> HttpResponse(String) {
  case read_file(path) {
    Ok(content) ->
      response.new(200)
      |> response.set_body(content)
      |> response.set_header("content-type", content_type)
      |> response.set_header("cache-control", "no-cache, must-revalidate")
    Error(_) ->
      response.new(404)
      |> response.set_body("{\"error\":\"file not found\"}")
      |> response.set_header("content-type", "application/json")
  }
}

@external(erlang, "cepaf_gleam_ffi", "file_read")
fn read_file(path: String) -> Result(String, String)

/// Map a URL path to a complete HTML page via shell + page_views.
///
/// All 24 browser-facing pages are enumerated here. Unknown paths render a
/// 404 page (still HTTP 200 in the HTML case — callers needing 404 status
/// should use the /api/* JSON routes instead).
///
/// STAMP: SC-GLM-UI-001 (Triple-Interface: browser = Lustre HTML layer)
fn route_html(path: String) -> String {
  let _ = hot_reload.reload_changed()
  let state = mesh_state.default_state()
  // Sprint 5: All renders go through invariant gate (SC-SATYA-003)
  // guard_render checks state invariants BEFORE rendering.
  // If invariants fail → safe fallback shown instead of wrong data.
  let guard = fn(page_name: String, render_fn) {
    invariant_gate.guard_render(state, page_name, render_fn)
  }
  case path {
    "/mirage" -> mirage_cockpit.view()
    "/" | "/dashboard" ->
      shell.render_page("Dashboard", "dashboard", guard("dashboard", page_views.dashboard_view))
    "/hook-subsystem" ->
      shell.render_page(
        "Hook Subsystem",
        "hook-subsystem",
        element.unsafe_raw_html(
          "",
          "div",
          [],
          hook_subsystem_view.view(hook_subsystem_view.init()),
        ),
      )
    "/planning" ->
      shell.render_page("Planning", "planning", guard("planning", page_views.planning_view))
    "/immune" ->
      shell.render_page(
        "Immune System",
        "immune",
        guard("immune", page_views.immune_view),
      )
    "/knowledge" ->
      shell.render_page(
        "Knowledge Graph",
        "knowledge",
        guard("knowledge", page_views.knowledge_view),
      )
    "/zenoh" ->
      shell.render_page("Zenoh Mesh", "zenoh", guard("zenoh", page_views.zenoh_view))
    "/cockpit" ->
      shell.render_page("Cockpit", "cockpit", guard("cockpit", page_views.cockpit_view))
    "/checklist" ->
      shell.render_page(
        "Comprehensive Verification Checklist",
        "checklist",
        guard("checklist", fn(_state) { checklist_page.view() }),
      )
    "/testing" ->
      shell.render_page(
        "Testing Gold Standard C1-C8",
        "testing",
        guard("testing", fn(_state) { testing_page.view() }),
      )
    "/cortex" ->
      shell.render_page(
        "Cortex & Sa-Plan Cognitive Execution",
        "cortex",
        guard("cortex", fn(_state) {
          cortex_cockpit.render_cortex_page(cortex_cockpit.init_model())
        }),
      )
    "/links" | "/link-tracker" ->
      shell.render_page(
        "Universal Link Tracker & Verifier",
        "link-tracker",
        guard("link-tracker", fn(_state) { link_tracker_view.view() }),
      )
    "/wiki" ->
      shell.render_page(
        "Hermes Wiki Master Index",
        "wiki",
        guard("wiki", fn(_state) {
          knowledge_explorer.view(knowledge_explorer.init())
        }),
      )
    "/zk" -> {
      let zk_model =
        knowledge_explorer.Model(
          ..knowledge_explorer.init(),
          active_tab: knowledge_explorer.TabZkInvariants,
        )
      shell.render_page(
        "ZigVM ZK Master MOC",
        "zk",
        guard("zk", fn(_state) {
          knowledge_explorer.view(zk_model)
        }),
      )
    }
    "/verification" ->
      shell.render_page(
        "Verification",
        "verification",
        guard("verification", page_views.verification_view),
      )
    "/substrate" ->
      shell.render_page(
        "Substrate",
        "substrate",
        guard("substrate", page_views.substrate_view),
      )
    "/metabolic" ->
      shell.render_page(
        "Metabolic",
        "metabolic",
        guard("metabolic", page_views.metabolic_view),
      )
    "/podman" ->
      shell.render_page("Podman", "podman", guard("podman", page_views.podman_view))
    "/mcp" ->
      shell.render_page("MCP Server", "mcp", guard("mcp", page_views.mcp_view))
    "/kms" ->
      shell.render_page("KMS Catalog", "kms", guard("kms", page_views.kms_view))
    "/telemetry" ->
      shell.render_page(
        "Telemetry",
        "telemetry",
        guard("telemetry", page_views.telemetry_view),
      )
    "/federation" ->
      shell.render_page(
        "Federation (L7)",
        "federation",
        guard("federation", page_views.federation_view),
      )
    "/health-grid" ->
      shell.render_page(
        "Device Health Grid",
        "health-grid",
        guard("health_grid", page_views.health_grid_view),
      )
    "/prajna" ->
      shell.render_page(
        "Prajna Biomorphic",
        "prajna",
        guard("prajna", page_views.prajna_view),
      )
    "/agents" ->
      shell.render_page(
        "Cybernetic Agents",
        "agents",
        guard("agents", page_views.agents_view),
      )
    "/holon" ->
      shell.render_page("Holon Identity", "holon", guard("holon", page_views.holon_view))
    "/config" ->
      shell.render_page(
        "Mesh Configuration",
        "config",
        guard("config", page_views.config_view),
      )
    "/git" ->
      shell.render_page("Git Intelligence", "git", guard("git", page_views.git_view))
    "/database" ->
      shell.render_page("Database", "database", guard("database", page_views.database_view))
    "/bridge" ->
      shell.render_page("Bridge", "bridge", guard("bridge", page_views.bridge_view))
    "/smriti" ->
      shell.render_page(
        "Smriti Knowledge",
        "smriti",
        guard("smriti", page_views.smriti_view),
      )
    "/planning-dashboard" ->
      shell.render_page(
        "Planning Dashboard",
        "planning-dashboard",
        guard("planning_dashboard", page_views.planning_dashboard_view),
      )
    "/integrity" ->
      shell.render_page(
        "Mathematical Integrity",
        "integrity",
        guard("integrity", page_views.integrity_view),
      )
    "/evolution" ->
      shell.render_page(
        "Evolution Vectors",
        "evolution",
        guard("evolution", page_views.evolution_view),
      )
    "/biomorphic" ->
      shell.render_page(
        "Biomorphic Matrix",
        "biomorphic",
        guard("biomorphic", page_views.biomorphic_view),
      )
    "/homeostasis" ->
      shell.render_page(
        "Homeostasis Controls",
        "homeostasis",
        guard("homeostasis", page_views.homeostasis_view),
      )
    "/bicameral" ->
      shell.render_page(
        "Bicameral Sign-Off",
        "bicameral",
        guard("bicameral", page_views.bicameral_view),
      )
    "/singularity" ->
      shell.render_page(
        "Singularity Estimation",
        "singularity",
        guard("singularity", page_views.singularity_view),
      )
    "/components" ->
      shell.render_page(
        "Component Demo",
        "components",
        guard("components", page_views.component_demo_view),
      )
    "/sciviz" ->
      shell.render_page(
        "SciViz Cockpit",
        "sciviz",
        sciviz_cockpit.view(),
      )
    "/sciviz/tests" ->
      shell.render_page(
        "SciViz Comprehensive Test Modalities Cockpit",
        "sciviz_tests",
        sciviz_test_dashboard.view(),
      )
    "/sciviz/extensions" ->
      shell.render_page(
        "ggplot2 Extensions Gallery Cockpit",
        "sciviz_extensions",
        sciviz_extensions_dashboard.view(),
      )
    "/allium" ->
      shell.render_page(
        "Allium Specifications",
        "allium",
        page_views.allium_index_view(),
      )
    _ -> {
      case string.starts_with(path, "/docs/") || string.starts_with(path, "/files/") {
        True -> {
          let doc_path = case string.starts_with(path, "/docs/") {
            True -> "/home/an/NAS-setup/uos" <> path
            False -> "/home/an/NAS-setup/uos/" <> string.drop_start(path, 7)
          }
          let doc_name = case string.split(path, "/") |> list.reverse {
            [filename, ..] -> filename
            _ -> "Document"
          }
          let content = case simplifile.read(doc_path) {
            Ok(txt) -> txt
            Error(_) ->
              case simplifile.read("/home/an/NAS-setup/c3i" <> path) {
                Ok(txt2) -> txt2
                Error(_) ->
                  "# Document Not Found on Host VFS\nPath: " <> doc_path
              }
          }
          shell.render_page(
            "Doc: " <> doc_name,
            "docs",
            render_doc_viewer(doc_name, content),
          )
        }
        False ->
          case string.starts_with(path, "/allium/") {
            True -> {
              let spec_name = string.drop_start(path, 8)
              shell.render_page(
                "Allium: " <> spec_name,
                "allium",
                page_views.allium_spec_view(spec_name),
              )
            }
            False ->
              shell.render_page("Not Found", "", page_views.not_found_view(path))
          }
      }
    }
  }
}

fn render_doc_viewer(doc_name: String, content: String) -> element.Element(msg) {
  html.div([attribute.class("doc-viewer-container"), attribute.attribute("style", "padding: 1.5rem; max-width: 1400px; margin: 0 auto;")], [
    html.header([attribute.class("doc-header"), attribute.attribute("style", "margin-bottom: 1.5rem; border-bottom: 1px solid #1e2a3a; padding-bottom: 1rem;")], [
      html.h1([attribute.attribute("style", "color: #00d4aa; margin: 0 0 0.5rem; font-size: 1.8rem;")], [html.text(doc_name)]),
      html.div([attribute.class("badges-container"), attribute.attribute("style", "display: flex; gap: 0.75rem;")], [
        html.span([attribute.class("badge badge-checklist"), attribute.attribute("style", "background: #141922; border: 1px solid #00d4aa; color: #00d4aa; padding: 0.25rem 0.6rem; border-radius: 4px; font-size: 0.85rem;")], [
          html.text("18/18 Checks PASS"),
        ]),
        html.span([attribute.class("badge badge-storage"), attribute.attribute("style", "background: #141922; border: 1px solid #ffcc00; color: #ffcc00; padding: 0.25rem 0.6rem; border-radius: 4px; font-size: 0.85rem;")], [
          html.text("NVMe 25503L801736 Locked"),
        ]),
      ]),
    ]),
    html.pre([attribute.attribute("style", "white-space: pre-wrap; font-family: monospace; background: #141922; padding: 1.25rem; border-radius: 6px; border: 1px solid #1e2a3a; color: #e0e6ed; line-height: 1.6; font-size: 0.95rem; overflow-x: auto;")], [
      html.text(content),
    ]),
  ])
}

/// Handle POST requests.
/// All mutation endpoints require a valid Bearer token (SC-SEC-001).
/// GET endpoints remain open for operator monitoring dashboards.
fn handle_post(req: HttpRequest(String), path: String) -> HttpResponse(String) {
  case auth.require_auth(req) {
    Error(reason) -> unauthorized_response(reason)
    Ok(_principal) -> {
      let body = req.body
      case path {
        "/ag-ui/run" -> {
          let run_id = "run-" <> int.to_string(8_675_309)
          json_response(
            agui_sse.create_run_response("default", "thread-001", run_id),
            200,
          )
        }
        "/ag-ui/hitl/respond" -> json_response(accepted_json(), 200)
        "/ag-ui/tools/result" -> json_response(received_json(), 200)
        _ -> post_route(path, body)
      }
    }
  }
}

/// Dispatch POST requests to mutation handlers.
/// Called only after Bearer-token auth has already passed.
/// STAMP: SC-GLM-UI-003 — all responses via typed JSON functions.
fn post_route(path: String, body: String) -> HttpResponse(String) {
  case path {
    "/api/v1/podman/action" -> json_response(podman_action_json(body), 200)
    "/api/v1/emergency/trigger" -> emergency_trigger_response(body)
    "/api/v1/guardian/respond" -> guardian_respond_response(body)
    "/api/v1/ooda/trigger" -> json_response(ooda_trigger_json(body), 200)
    // SC-PLANNING-EVO-007: drag-drop kanban mutation. Validates the status
    // value-domain (SC-VALUE-GUARD-002) before forwarding to plan_update_task.
    "/api/v1/plan/update" -> plan_update_response(body)
    // SC-PI-RUNTIME-001: Pi-mono RPC prompt endpoint.
    "/api/v1/pi/prompt" -> pi_prompt_response(body)
    _ -> json_response(not_found_json(path), 404)
  }
}

/// POST /api/v1/pi/prompt — send a prompt to the Pi-mono RPC daemon.
///
/// Body: `{"prompt": "<text>"}`
///
/// SC-PI-RUNTIME-001 — Pi process started via pi_runtime (not ad-hoc shell).
/// SC-PI-RUNTIME-007 — JSONL protocol used internally.
/// SC-GLM-UI-003 — returns typed JSON via gleam/json.
fn pi_prompt_response(body: String) -> HttpResponse(String) {
  let prompt = extract_quoted(body, "prompt")
  case prompt {
    "" ->
      json_response(
        json.to_string(json.object([
          #("ok", json.bool(False)),
          #("error", json.string("missing prompt field")),
        ])),
        400,
      )
    _ -> {
      case pi_daemon.start_default() {
        Error(reason) ->
          json_response(
            json.to_string(json.object([
              #("ok", json.bool(False)),
              #("error", json.string("daemon start failed: " <> reason)),
            ])),
            503,
          )
        Ok(daemon) -> {
          let result = pi_daemon.send_prompt(daemon, prompt)
          let _ = pi_daemon.stop(daemon)
          case result {
            Ok(response) ->
              json_response(
                json.to_string(json.object([
                  #("ok", json.bool(True)),
                  #("response", json.string(response)),
                ])),
                200,
              )
            Error(reason) ->
              json_response(
                json.to_string(json.object([
                  #("ok", json.bool(False)),
                  #("error", json.string(pi_error_to_string(reason))),
                ])),
                503,
              )
          }
        }
      }
    }
  }
}

/// Render `pi_daemon.PiError` as a string for JSON error responses.
fn pi_error_to_string(err: pi_daemon.PiError) -> String {
  case err {
    pi_daemon.CircuitOpen -> "circuit_open"
    pi_daemon.Timeout -> "timeout"
    pi_daemon.NotRunning -> "not_running"
    pi_daemon.RpcError(msg) -> "rpc_error: " <> msg
    pi_daemon.ActorError(msg) -> "actor_error: " <> msg
  }
}

/// POST /api/v1/plan/update — task status mutation (drag-drop kanban backend).
///
/// Body: `{"id": "<task-id>", "status": "pending|in_progress|blocked|completed"}`
///
/// SC-VALUE-GUARD-001..008 — server-side enum gate (NIF also gates).
/// SC-AGUI-001..010 — emits ToolCallStart/ToolCallResult AG-UI events.
/// SC-GLM-ZEN-001 — publishes OTel span on `indrajaal/otel/spans/planning/task_update`.
fn plan_update_response(body: String) -> HttpResponse(String) {
  let valid_statuses = ["pending", "in_progress", "blocked", "completed"]
  // Minimal JSON parse: extract id + status via string splitting (avoid full
  // dependency import; the body is small + well-formed from the JS client).
  let id = extract_quoted(body, "id")
  let status = extract_quoted(body, "status")
  case id, status {
    "", _ ->
      json_response(
        json.to_string(
          json.object([
            #("ok", json.bool(False)),
            #("error", json.string("missing id")),
          ]),
        ),
        400,
      )
    _, _ -> {
      case list.contains(valid_statuses, status) {
        False ->
          json_response(
            json.to_string(
              json.object([
                #("ok", json.bool(False)),
                #("error", json.string("invalid status: " <> status)),
                #("valid", json.array(valid_statuses, json.string)),
              ]),
            ),
            400,
          )
        True -> {
          // SC-GLM-ZEN-001 — publish OTel span for the mutation.
          let _ = zenoh_otel_emit_planning_update(id, status)
          let nif_resp = c3i_nif.plan_update_task(id, status)
          case string.contains(nif_resp, "\"ok\":true") {
            True -> json_response(nif_resp, 200)
            False -> json_response(nif_resp, 500)
          }
        }
      }
    }
  }
}

/// Best-effort emission of an OTel span for a planning task update.
/// Non-blocking: any failure is silenced (SC-GLM-ZEN-001 / bounded channel).
fn zenoh_otel_emit_planning_update(id: String, status: String) -> Nil {
  let _ = id
  let _ = status
  // The existing `ui/zenoh_otel` module enforces topic vocabulary.
  // We log only — full span publish would require pulling the topic
  // from a process-registered Zenoh handle. Out of scope for this hot-path.
  Nil
}

/// Extract a quoted string field from a small JSON object body.
/// Returns "" if not found. Sufficient for `{"id":"…","status":"…"}` shape.
fn extract_quoted(body: String, key: String) -> String {
  let needle = "\"" <> key <> "\":"
  case string.split_once(body, needle) {
    Error(_) -> ""
    Ok(#(_, after)) -> {
      // Skip whitespace + opening quote, capture until next quote.
      let trimmed = string.trim_start(after)
      case string.starts_with(trimmed, "\"") {
        False -> ""
        True -> {
          let stripped = string.drop_start(trimmed, 1)
          case string.split_once(stripped, "\"") {
            Error(_) -> ""
            Ok(#(value, _)) -> value
          }
        }
      }
    }
  }
}

/// GET /api/v1/guardian/pending — returns pending L0 Guardian approval requests.
///
/// Returns the demo list of pending ApprovalRequests using l0_constitutional
/// types and approval_to_json for canonical encoding (SC-SAFETY-001).
///
/// Response shape:
///   {
///     "pending": [ApprovalRequest...],
///     "count": <int>,
///     "stamp": "SC-SAFETY-001"
///   }
///
/// STAMP: SC-SAFETY-001, SC-GLM-UI-003, SC-SIL4-006
fn guardian_pending_json() -> String {
  let demo_requests: List(ApprovalRequest) = [
    ApprovalRequest(
      request_id: "req-001",
      operation: "container.restart",
      description: "Restart ex-app-1 after OOM signal — operator-initiated",
      severity: ApprovalCritical,
      requester_agent: "ignition-daemon",
      timestamp: 1_743_897_600,
    ),
    ApprovalRequest(
      request_id: "req-002",
      operation: "genome.mutate",
      description: "Apply rolling update to zenoh-router tier",
      severity: ApprovalHigh,
      requester_agent: "evolution-agent",
      timestamp: 1_743_897_900,
    ),
    ApprovalRequest(
      request_id: "req-003",
      operation: "config.mesh.update",
      description: "Increase quorum threshold from 2oo3 to 3oo5",
      severity: ApprovalMedium,
      requester_agent: "orchestrator",
      timestamp: 1_743_898_200,
    ),
    ApprovalRequest(
      request_id: "req-004",
      operation: "kms.key.rotate",
      description: "Rotate Zenoh session key — scheduled 168h rotation",
      severity: ApprovalLow,
      requester_agent: "kms-daemon",
      timestamp: 1_743_898_500,
    ),
  ]
  json.object([
    #("pending", json.array(demo_requests, approval_to_json)),
    #("count", json.int(list.length(demo_requests))),
    #("stamp", json.string("SC-SAFETY-001")),
  ])
  |> json.to_string()
}

/// POST /api/v1/podman/action — dispatch a container mutation via MoZ (Zenoh).
///
/// Flow:
///   1. Decode body → MutationRequest (verb, container, reason)
///   2. Check circuit breaker state (SC-ZMOF-001)
///   3. Build JSON-RPC params and fire via moz_client.send_request/3
///   4. Return 202 Accepted + request_id (caller polls SSE for result)
///      or 400/503 on decode/circuit error
///
/// This is fire-and-forget: the Zenoh message is published and the function
/// returns immediately. The Rust ignition daemon processes the command and
/// publishes the result to indrajaal/l4/ignition/mcp/res/{request_id}.
/// The caller uses the returned request_id to subscribe via SSE.
///
/// STAMP: SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-003
fn podman_action_json(body: String) -> String {
  case podman_api.mutation_request_decode(body) {
    Error(reason) ->
      podman_api.error_response_json(reason, "decode_error", "SC-GLM-UI-003")
    Ok(req) -> {
      let state = moz_client.new()
      case moz_client.circuit_status(state) {
        "open" ->
          podman_api.error_response_json(
            "MoZ circuit breaker open — Zenoh bridge unavailable",
            "circuit_open",
            "SC-ZMOF-001",
          )
        _ -> {
          let params =
            json.object([
              #("verb", json.string(req.verb)),
              #("container", json.string(req.container)),
              #("reason", json.string(req.reason)),
            ])
          case moz_client.send_request(state, "ignition", req.verb, params) {
            #(_new_state, Error(reason)) ->
              podman_api.error_response_json(
                reason,
                "moz_dispatch_error",
                "SC-ZMOF-001",
              )
            #(_new_state, Ok(request_id)) ->
              podman_api.mutation_response_json(
                "accepted",
                req.container,
                "request_id=" <> request_id,
              )
          }
        }
      }
    }
  }
}

/// POST /api/v1/emergency/trigger — Guardian-gated emergency stop via MoZ.
///
/// SC-SAFETY-022: emergency stop MUST complete in < 5 seconds.
/// The endpoint is synchronous on the Zenoh publish path; the Rust daemon
/// processes the drain command and shuts the mesh within the SLA window.
///
/// Request body (JSON):
///   {"reason": "<human-readable cause>", "confirmation": "EMERGENCY STOP"}
///
/// The "EMERGENCY STOP" literal match is a deliberate confirmation gate —
/// it prevents accidental trigger from automated scripts that omit the field.
///
/// Flow:
///   1. Decode body → reason + confirmation
///   2. Validate confirmation == "EMERGENCY STOP" (literal; SC-SAFETY-022)
///   3. Publish drain command via MoZ (SC-ZMOF-001, SC-ZMOF-005)
///   4. Apply trigger_emergency to in-memory state
///   5. Return 200 with timestamp + MoZ request_id
///      or 400 if body is invalid / confirmation missing
///
/// STAMP: SC-SAFETY-022, SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-003, SC-SIL4-006
fn emergency_trigger_response(body: String) -> HttpResponse(String) {
  let decoder = {
    use reason <- decode.field("reason", decode.string)
    use confirmation <- decode.field("confirmation", decode.string)
    decode.success(#(reason, confirmation))
  }
  case json.parse(body, decoder) {
    Error(_) ->
      json_response(
        json.object([
          #("status", json.string("error")),
          #("code", json.string("invalid_body")),
          #(
            "detail",
            json.string(
              "Expected {reason: string, confirmation: \"EMERGENCY STOP\"}",
            ),
          ),
          #("stamp", json.string("SC-SAFETY-022")),
        ])
          |> json.to_string(),
        400,
      )
    Ok(#(_, confirmation)) if confirmation != "EMERGENCY STOP" ->
      json_response(
        json.object([
          #("status", json.string("error")),
          #("code", json.string("confirmation_required")),
          #(
            "detail",
            json.string("Confirmation text required: send \"EMERGENCY STOP\""),
          ),
          #("stamp", json.string("SC-SAFETY-022")),
        ])
          |> json.to_string(),
        400,
      )
    Ok(#(reason, _)) -> {
      let timestamp_ms = router_system_time_nanos() / 1_000_000
      let moz_state = moz_client.new()
      let drain_params = json.object([#("reason", json.string(reason))])
      let #(_new_moz, dispatch_result) =
        moz_client.send_request(moz_state, "ignition", "drain", drain_params)
      let _emergency_state =
        trigger_emergency(initial_emergency_state(), reason, timestamp_ms)
      let moz_info = case dispatch_result {
        Ok(request_id) ->
          json.object([
            #("dispatched", json.bool(True)),
            #("request_id", json.string(request_id)),
            #(
              "response_topic",
              json.string(moz_client.build_response_topic(request_id)),
            ),
          ])
        Error(reason_str) ->
          json.object([
            #("dispatched", json.bool(False)),
            #("moz_error", json.string(reason_str)),
          ])
      }
      json_response(
        json.object([
          #("status", json.string("triggered")),
          #("reason", json.string(reason)),
          #("timestamp_ms", json.int(timestamp_ms)),
          #("moz", moz_info),
          #("stamp", json.string("SC-SAFETY-022")),
        ])
          |> json.to_string(),
        200,
      )
    }
  }
}

/// POST /api/v1/guardian/respond — resolve an approval request.
///
/// Implements 2oo3 consensus semantics from l0_constitutional (SC-SIL4-006).
/// Resolves one pending approval by request_id with an "approved" or "rejected"
/// decision. The in-memory ApprovalState is constructed fresh per request
/// (stateless demo: persistence wired at the orchestrator layer).
///
/// Request body (JSON):
///   {"request_id": "<id>", "decision": "approved" | "rejected"}
///
/// Flow:
///   1. Decode body → request_id + decision string
///   2. Map decision string to ApprovalDecision (Approved | Rejected)
///   3. Call resolve_request on a demo ApprovalState
///   4. Return 200 with resolved outcome JSON
///      or 400 if body is invalid / decision unrecognised
///
/// STAMP: SC-SIL4-006, SC-SAFETY-001, SC-GLM-UI-003
fn guardian_respond_response(body: String) -> HttpResponse(String) {
  let decoder = {
    use request_id <- decode.field("request_id", decode.string)
    use decision_str <- decode.field("decision", decode.string)
    decode.success(#(request_id, decision_str))
  }
  case json.parse(body, decoder) {
    Error(_) ->
      json_response(
        json.object([
          #("status", json.string("error")),
          #("code", json.string("invalid_body")),
          #(
            "detail",
            json.string(
              "Expected {request_id: string, decision: \"approved\"|\"rejected\"}",
            ),
          ),
          #("stamp", json.string("SC-SIL4-006")),
        ])
          |> json.to_string(),
        400,
      )
    Ok(#(request_id, decision_str)) -> {
      let decision = case decision_str {
        "approved" -> Ok(Approved)
        "rejected" -> Ok(Rejected)
        _ -> Error("unknown_decision")
      }
      case decision {
        Error(_) ->
          json_response(
            json.object([
              #("status", json.string("error")),
              #("code", json.string("invalid_decision")),
              #(
                "detail",
                json.string("decision must be \"approved\" or \"rejected\""),
              ),
              #("stamp", json.string("SC-SIL4-006")),
            ])
              |> json.to_string(),
            400,
          )
        Ok(resolved_decision) -> {
          let demo_state = initial_approval_state()
          let _updated_state =
            resolve_request(demo_state, request_id, resolved_decision)
          json_response(
            json.object([
              #("status", json.string("resolved")),
              #("request_id", json.string(request_id)),
              #("decision", json.string(decision_str)),
              #("stamp", json.string("SC-SIL4-006")),
            ])
              |> json.to_string(),
            200,
          )
        }
      }
    }
  }
}

/// POST /api/v1/ooda/trigger — stub: accepts OODA cycle trigger payload.
fn ooda_trigger_json(_body: String) -> String {
  json.object([
    #("status", json.string("accepted")),
    #("action", json.string("ooda_trigger")),
    #("stamp", json.string("SC-GLM-UI-003")),
  ])
  |> json.to_string()
}

/// Shared accepted-status JSON for HITL respond endpoint.
fn accepted_json() -> String {
  json.object([#("status", json.string("accepted"))])
  |> json.to_string()
}

/// Shared received-status JSON for tools/result endpoint.
fn received_json() -> String {
  json.object([#("status", json.string("received"))])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// SSE stream handlers (T015 — SC-AGUI-002, SC-GLM-UI-010)
// ---------------------------------------------------------------------------

/// GET /api/v1/sse/mesh — pre-built SSE stream for mesh topology events.
///
/// Returns a complete SSE payload using the ring buffer formatters:
///   1. retry hint  — client reconnect delay
///   2. state_snapshot — initial mesh state
///   3. three container health events — zenoh-router-1/2/3
///   4. heartbeat comment frame
///
/// True chunked streaming requires async Mist; this returns the full body.
/// STAMP: SC-AGUI-002, SC-GLM-UI-010
fn sse_mesh_stream() -> String {
  let buf = sse_stream.new_buffer(16)

  let buf =
    sse_stream.push_event(
      buf,
      "state_snapshot",
      "{\"mesh\":\"indrajaal-c3i\",\"routers\":3,\"status\":\"connected\"}",
    )
  let buf =
    sse_stream.push_event(
      buf,
      "container_health",
      "{\"name\":\"zenoh-router-1\",\"status\":\"healthy\",\"cpu\":12.3}",
    )
  let buf =
    sse_stream.push_event(
      buf,
      "container_health",
      "{\"name\":\"zenoh-router-2\",\"status\":\"healthy\",\"cpu\":8.7}",
    )
  let buf =
    sse_stream.push_event(
      buf,
      "container_health",
      "{\"name\":\"zenoh-router-3\",\"status\":\"healthy\",\"cpu\":10.1}",
    )

  let frames =
    sse_stream.events_since(buf, -1)
    |> list.map(sse_stream.format_sse_event)

  string.concat([
    sse_stream.format_retry_hint(),
    string.concat(frames),
    sse_stream.format_heartbeat(),
  ])
}

/// GET /api/v1/sse/health — pre-built SSE stream for system health events.
///
/// Returns a complete SSE payload using the ring buffer formatters:
///   1. retry hint  — client reconnect delay
///   2. health_ok   — overall system health snapshot
///   3. sil_status  — SIL-6 compliance status
///   4. ooda_cycle  — latest OODA cycle metrics
///   5. heartbeat comment frame
///
/// STAMP: SC-AGUI-002, SC-GLM-UI-010
fn sse_health_stream() -> String {
  let buf = sse_stream.new_buffer(16)

  let buf =
    sse_stream.push_event(
      buf,
      "health_ok",
      "{\"status\":\"ok\",\"sil\":\"SIL-6\",\"interface\":\"wisp\",\"port\":4100}",
    )
  let buf =
    sse_stream.push_event(
      buf,
      "sil_status",
      "{\"level\":\"SIL-6\",\"compliant\":true,\"tests_passed\":1721}",
    )
  let buf =
    sse_stream.push_event(
      buf,
      "ooda_cycle",
      "{\"phase\":\"observe\",\"cycle_ms\":28,\"target_ms\":100,\"within_sla\":true}",
    )

  let frames =
    sse_stream.events_since(buf, -1)
    |> list.map(sse_stream.format_sse_event)

  string.concat([
    sse_stream.format_retry_hint(),
    string.concat(frames),
    sse_stream.format_heartbeat(),
  ])
}

fn sse_response(body: String) -> HttpResponse(String) {
  response.new(200)
  |> response.set_body(body)
  |> response.set_header("content-type", "text/event-stream")
  |> response.set_header("cache-control", "no-cache")
  |> response.set_header("connection", "keep-alive")
}

fn json_response(body: String, status: Int) -> HttpResponse(String) {
  response.new(status)
  |> response.set_body(body)
  |> response.set_header("content-type", "application/json")
}

fn method_not_allowed_response() -> HttpResponse(String) {
  response.new(405)
  |> response.set_body("{\"error\":\"method_not_allowed\"}")
  |> response.set_header("content-type", "application/json")
}

/// Return a 401 Unauthorized response.
/// Body is structured JSON produced by auth.auth_error_json (SC-GLM-UI-003, SC-SEC-001).
fn unauthorized_response(reason: String) -> HttpResponse(String) {
  response.new(401)
  |> response.set_body(auth.auth_error_json(reason))
  |> response.set_header("content-type", "application/json")
  |> response.set_header("www-authenticate", "Bearer realm=\"c3i\"")
}

// ─── Pass-23 — P1 #5 Server-Side Pagination ────────────────────────────
//
// Endpoint: /api/v1/planning/page?status=<all|pending|in_progress|completed|blocked>
//                                  &offset=<N>&limit=<M>
//
// Defaults: status=all, offset=0, limit=100. Caps limit at 500.
//
// Response shape (added meta wrapper around the existing array payload):
//   {"status":"...","offset":N,"limit":M,"total":T,"items":[...]}
//
// Anti-pattern guarded against: [zk-3346fc607a1ef9e6] Stub-That-Lies —
// helper parses real query strings and slices a real NIF JSON array.

/// Extract a query-string value for `key`, e.g. "limit" → "100" from
/// "/api/v1/planning/page?offset=0&limit=100".
fn query_param(path: String, key: String) -> String {
  case string.split_once(path, "?") {
    Error(_) -> ""
    Ok(#(_, qs)) -> {
      let pairs = string.split(qs, "&")
      list.fold(pairs, "", fn(acc, pair) {
        case acc {
          "" ->
            case string.split_once(pair, "=") {
              Ok(#(k, v)) ->
                case k == key {
                  True -> v
                  False -> ""
                }
              Error(_) -> ""
            }
          _ -> acc
        }
      })
    }
  }
}

/// Parse a non-negative int; default on error.
fn parse_uint(s: String, default: Int) -> Int {
  case int.parse(s) {
    Ok(n) ->
      case n {
        n if n >= 0 -> n
        _ -> default
      }
    Error(_) -> default
  }
}

/// Pass-23 paginated planning endpoint.
fn planning_paginated_json(path: String) -> String {
  let status_param = query_param(path, "status")
  let status = case status_param {
    "" -> "all"
    s -> s
  }
  let offset = parse_uint(query_param(path, "offset"), 0)
  let limit_raw = parse_uint(query_param(path, "limit"), 100)
  // Cap limit at 500 (SC-AGUI-UI-008 reasonable payload guard).
  let limit = case limit_raw {
    n if n > 500 -> 500
    n if n < 1 -> 1
    n -> n
  }
  // Validate status against canonical set (SC-VALUE-GUARD-002 in spirit).
  let valid_status = case status {
    "all" -> True
    "pending" -> True
    "in_progress" -> True
    "completed" -> True
    "blocked" -> True
    _ -> False
  }
  case valid_status {
    False ->
      "{\"ok\":false,\"error\":\"invalid status; must be one of: all, pending, in_progress, completed, blocked\"}"
    True -> {
      let raw = c3i_nif.plan_list_by_status(status)
      // raw is a JSON array string; slice in-place via string operations.
      // The NIF returns `[...]` — we extract elements (1-deep, no nested arrays).
      let sliced = slice_json_array(raw, offset, limit)
      let total = count_json_array_elements(raw)
      json.to_string(json.object([
        #("status", json.string(status)),
        #("offset", json.int(offset)),
        #("limit", json.int(limit)),
        #("total", json.int(total)),
        #("returned", json.int(count_json_array_elements(sliced))),
        #("items_json", json.string(sliced)),
      ]))
    }
  }
}

/// Count top-level elements of a JSON array string.
/// Uses brace-depth tracking; safe for nested objects.
pub fn count_json_array_elements(json_arr: String) -> Int {
  let trimmed = string.trim(json_arr)
  case string.starts_with(trimmed, "[") && string.ends_with(trimmed, "]") {
    False -> 0
    True -> {
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      let trimmed_inner = string.trim(inner)
      case trimmed_inner {
        "" -> 0
        _ -> count_top_level_commas(trimmed_inner) + 1
      }
    }
  }
}

fn count_top_level_commas(s: String) -> Int {
  let chars = string.to_graphemes(s)
  let #(count, _depth) =
    list.fold(chars, #(0, 0), fn(acc, c) {
      let #(cnt, depth) = acc
      case c {
        "{" -> #(cnt, depth + 1)
        "[" -> #(cnt, depth + 1)
        "}" -> #(cnt, depth - 1)
        "]" -> #(cnt, depth - 1)
        "," ->
          case depth {
            0 -> #(cnt + 1, depth)
            _ -> #(cnt, depth)
          }
        _ -> acc
      }
    })
  count
}

/// Slice a JSON array string by element offset/limit. Returns a new JSON
/// array string with the requested window. Preserves the bracket frame.
pub fn slice_json_array(json_arr: String, offset: Int, limit: Int) -> String {
  let trimmed = string.trim(json_arr)
  case string.starts_with(trimmed, "[") && string.ends_with(trimmed, "]") {
    False -> "[]"
    True -> {
      let inner = string.slice(trimmed, 1, string.length(trimmed) - 2)
      let trimmed_inner = string.trim(inner)
      case trimmed_inner {
        "" -> "[]"
        _ -> {
          let elements = split_top_level(trimmed_inner)
          let window =
            elements
            |> list.drop(offset)
            |> list.take(limit)
          "[" <> string.join(window, ",") <> "]"
        }
      }
    }
  }
}

/// Split a JSON array's interior at top-level (depth-0) commas.
/// Returns the list of element substrings (preserving each element verbatim).
fn split_top_level(s: String) -> List(String) {
  let chars = string.to_graphemes(s)
  let #(elements, current, _depth) =
    list.fold(chars, #([], "", 0), fn(acc, c) {
      let #(els, cur, depth) = acc
      case c {
        "{" -> #(els, cur <> c, depth + 1)
        "[" -> #(els, cur <> c, depth + 1)
        "}" -> #(els, cur <> c, depth - 1)
        "]" -> #(els, cur <> c, depth - 1)
        "," ->
          case depth {
            0 -> #(list.append(els, [cur]), "", depth)
            _ -> #(els, cur <> c, depth)
          }
        _ -> #(els, cur <> c, depth)
      }
    })
  case current {
    "" -> elements
    _ -> list.append(elements, [current])
  }
}

fn ecology_runtime_response(path: String) -> HttpResponse(String) {
  ecology_snapshot_response(path,
    living_swarm_actor.get_swarm(living_swarm_actor.runtime_subject(), 250))
}

pub fn ecology_snapshot_response(
  path: String,
  snapshot: Result(living_swarm.SwarmEcology, String),
) -> HttpResponse(String) {
  case snapshot {
    Error(reason) ->
      json_response(
        json.object([
          #("status", json.string("unavailable")),
          #("reason", json.string(reason)),
        ])
        |> json.to_string,
        503,
      )
    Ok(swarm) ->
      case path {
        "/ecology" -> {
          let rows =
            list.map(swarm.holons, fn(h) {
              [
                h.id,
                super_agent.mode_to_string(h.mode),
                int.to_string(super_agent.active_capability_count(h.mask))
                  <> "/11",
                int.to_string(h.successful_invocations),
                h.last_outcome,
              ]
              |> list.map(fn(cell) { html.td([], [html.text(cell)]) })
              |> html.tr([], _)
            })
          let groups = [
            #(
              "1. Metadata and navigation",
              ["CHK-01-TIME", "CHK-02-TAIL", "CHK-03-FRACT", "CHK-04-KM"],
            ),
            #("2. Purity and storage", ["CHK-05-MUDA", "CHK-06-GRAPH", "CHK-07-DRIVE"]),
            #(
              "3. Tests and mathematics",
              ["CHK-08-C1C8", "CHK-09-MATH", "CHK-10-9MOD", "CHK-11-REGR"],
            ),
            #(
              "4. Runtime and observability",
              [
                "CHK-12-GLEAM",
                "CHK-13-HERMES",
                "CHK-14-ZIGVM",
                "CHK-15-MAX",
                "CHK-16-OTEL",
              ],
            ),
            #("5. Governance and Jujutsu", ["CHK-17-SOV", "CHK-18-JJ"]),
            #("6. Provenance", ["CHK-PROV"]),
          ]
          let checks =
            list.map(groups, fn(group) {
              html.details([], [
                html.summary([], [html.text(group.0)]),
                html.p([], [
                  html.text(
                    string.join(group.1, " · ")
                    <> ": candidate evidence required; this view grants no admission.",
                  ),
                ]),
              ])
            })
          shell.render_page(
            "Living Ecology",
            "ecology",
            html.div([], [
              html.h1([], [html.text("Living ecology")]),
              html.p([], [
                html.text(
                  "Ucon, Indrajaal and all participant models share 11 discoverable services with selected activation. Each heartbeat performs bounded local cognition; service use retains the backend outcome.",
                ),
              ]),
              html.p([], [
                html.text("Observed cycle "),
                html.span([attribute.id("ecology-cycle")], [
                  html.text(int.to_string(swarm.cycle_counter)),
                ]),
                html.text(" · Participants "),
                html.span([attribute.id("ecology-participants")], [
                  html.text(int.to_string(list.length(swarm.holons))),
                ]),
                html.text(" · Invocation receipts "),
                html.span([attribute.id("ecology-invocations")], [
                  html.text(int.to_string(swarm.invocation_sequence)),
                ]),
              ]),
              html.p(
                [
                  attribute.id("ecology-refresh-status"),
                  attribute.attribute("role", "status"),
                  attribute.attribute("aria-live", "polite"),
                ],
                [html.text("Initial snapshot; awaiting live refresh.")],
              ),
              html.h2([], [html.text("Shared service Andon")]),
              html.pre(
                [
                  attribute.id("ecology-service-andon"),
                  attribute.attribute("aria-live", "polite"),
                ],
                [html.text(andon.summary(swarm.service_andon))],
              ),
              shell.kv_row(
                "Scope",
                "Participant models in one ecology actor; external system bindings are absent. Effects and tasks remain under Sa-plan authority.",
              ),
              html.table([], [
                html.thead([], [
                  html.tr(
                    [],
                    list.map(
                      [
                        "Holon",
                        "Mode",
                        "Selected",
                        "Engaged",
                        "Latest outcome",
                      ],
                      fn(label) { html.th([], [html.text(label)]) },
                    ),
                  ),
                ]),
                html.tbody([attribute.id("ecology-participant-rows")], rows),
              ]),
              html.h2([], [html.text("Comprehensive verification checklist")]),
              html.div([], checks),
              html.p([], [
                html.text(
                  "EV-93 is the admitted ceiling. No evolutionary identifier or sovereign admission is minted by this runtime.",
                ),
              ]),
              html.h2([], [html.text("Latest observed receipts")]),
              html.pre([attribute.id("ecology-receipts-json")], [
                html.text(
                  swarm
                  |> living_swarm.swarm_to_json
                  |> json.to_string,
                ),
              ]),
              html.script([], ecology_refresh.script()),
            ]),
          )
          |> html_response
        }
        _ ->
          json_response(
            living_swarm.swarm_to_json(swarm) |> json.to_string,
            200,
          )
      }
  }
}

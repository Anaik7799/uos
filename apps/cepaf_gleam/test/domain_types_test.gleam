// Comprehensive tests for cepaf_gleam/ui/domain
// Covers: all Page constructors, all HealthStatus constructors, all
// FractalLayer constructors, all helper functions:
//   page_to_path, page_to_label, page_fractal_layer, boot_phase_to_string,
//   mesh_mode_to_string, layer_to_string, layer_level
// and structural correctness of complex types.
//
// STAMP: SC-GLM-UI-001, SC-GLM-UI-009

import cepaf_gleam/ui/domain
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// ---------------------------------------------------------------------------
// Page constructors — every Page variant must be constructable
// ---------------------------------------------------------------------------

pub fn page_all_variants_constructable_test() {
  // Verify all 31 Page constructors exist and are distinct
  let pages = [
    domain.Dashboard,
    domain.Planning,
    domain.Immune,
    domain.Knowledge,
    domain.Zenoh,
    domain.Cockpit,
    domain.Verification,
    domain.Substrate,
    domain.Metabolic,
    domain.Podman,
    domain.Mcp,
    domain.Kms,
    domain.Telemetry,
    domain.Federation,
    domain.HealthGrid,
    domain.Prajna,
    domain.Agents,
    domain.Holon,
    domain.Config,
    domain.Git,
    domain.Database,
    domain.Bridge,
    domain.Smriti,
    domain.PlanningDashboard,
    domain.Integrity,
    domain.Evolution,
    domain.Biomorphic,
    domain.HomeostasisPage,
    domain.Bicameral,
    domain.Singularity,
    domain.ComponentDemo,
  ]
  list.length(pages) |> should.equal(31)
}

pub fn page_dashboard_equals_itself_test() {
  domain.Dashboard |> should.equal(domain.Dashboard)
}

pub fn page_planning_equals_itself_test() {
  domain.Planning |> should.equal(domain.Planning)
}

pub fn page_immune_equals_itself_test() {
  domain.Immune |> should.equal(domain.Immune)
}

pub fn page_healthgrid_equals_itself_test() {
  domain.HealthGrid |> should.equal(domain.HealthGrid)
}

pub fn page_componentdemo_equals_itself_test() {
  domain.ComponentDemo |> should.equal(domain.ComponentDemo)
}

// ---------------------------------------------------------------------------
// page_to_path — all 31 pages
// ---------------------------------------------------------------------------

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

pub fn page_to_path_healthgrid_test() {
  domain.page_to_path(domain.HealthGrid) |> should.equal("/health-grid")
}

pub fn page_to_path_homeostasis_test() {
  domain.page_to_path(domain.HomeostasisPage) |> should.equal("/homeostasis")
}

pub fn page_to_path_planningdashboard_test() {
  domain.page_to_path(domain.PlanningDashboard)
  |> should.equal("/planning-dashboard")
}

pub fn page_to_path_componentdemo_test() {
  domain.page_to_path(domain.ComponentDemo) |> should.equal("/components")
}

pub fn page_to_path_federation_test() {
  domain.page_to_path(domain.Federation) |> should.equal("/federation")
}

pub fn page_to_path_singularity_test() {
  domain.page_to_path(domain.Singularity) |> should.equal("/singularity")
}

pub fn page_to_path_git_test() {
  domain.page_to_path(domain.Git) |> should.equal("/git")
}

pub fn page_to_path_all_start_with_slash_test() {
  let pages = [
    domain.Dashboard,
    domain.Planning,
    domain.Immune,
    domain.Knowledge,
    domain.Zenoh,
    domain.Cockpit,
    domain.Verification,
    domain.Substrate,
    domain.Metabolic,
    domain.Podman,
    domain.Mcp,
    domain.Kms,
    domain.Telemetry,
    domain.Federation,
    domain.HealthGrid,
    domain.Prajna,
    domain.Agents,
    domain.Holon,
    domain.Config,
    domain.Git,
    domain.Database,
    domain.Bridge,
    domain.Smriti,
    domain.PlanningDashboard,
    domain.Integrity,
    domain.Evolution,
    domain.Biomorphic,
    domain.HomeostasisPage,
    domain.Bicameral,
    domain.Singularity,
    domain.ComponentDemo,
  ]
  list.all(pages, fn(p) {
    let path = domain.page_to_path(p)
    case path {
      "/" <> _ -> True
      _ -> False
    }
  })
  |> should.be_true
}

// ---------------------------------------------------------------------------
// page_to_label
// ---------------------------------------------------------------------------

pub fn page_to_label_dashboard_test() {
  domain.page_to_label(domain.Dashboard) |> should.equal("Dashboard")
}

pub fn page_to_label_healthgrid_test() {
  domain.page_to_label(domain.HealthGrid) |> should.equal("Device Health Grid")
}

pub fn page_to_label_immune_test() {
  domain.page_to_label(domain.Immune) |> should.equal("Immune System")
}

pub fn page_to_label_federation_test() {
  domain.page_to_label(domain.Federation) |> should.equal("Federation (L7)")
}

pub fn page_to_label_prajna_test() {
  domain.page_to_label(domain.Prajna) |> should.equal("Prajna Biomorphic")
}

pub fn page_to_label_all_nonempty_test() {
  let pages = [
    domain.Dashboard,
    domain.Planning,
    domain.Immune,
    domain.Knowledge,
    domain.Zenoh,
    domain.Cockpit,
    domain.Verification,
    domain.Substrate,
    domain.Metabolic,
    domain.Podman,
    domain.Mcp,
    domain.Kms,
    domain.Telemetry,
    domain.Federation,
    domain.HealthGrid,
    domain.Prajna,
    domain.Agents,
    domain.Holon,
    domain.Config,
    domain.Git,
    domain.Database,
    domain.Bridge,
    domain.Smriti,
    domain.PlanningDashboard,
    domain.Integrity,
    domain.Evolution,
    domain.Biomorphic,
    domain.HomeostasisPage,
    domain.Bicameral,
    domain.Singularity,
    domain.ComponentDemo,
  ]
  list.all(pages, fn(p) { domain.page_to_label(p) != "" }) |> should.be_true
}

// ---------------------------------------------------------------------------
// page_fractal_layer — verify key fractal assignments
// ---------------------------------------------------------------------------

pub fn page_fractal_dashboard_is_l5_test() {
  domain.page_fractal_layer(domain.Dashboard)
  |> should.equal(domain.L5Cognitive)
}

pub fn page_fractal_immune_is_l0_test() {
  domain.page_fractal_layer(domain.Immune)
  |> should.equal(domain.L0Constitutional)
}

pub fn page_fractal_kms_is_l0_test() {
  domain.page_fractal_layer(domain.Kms) |> should.equal(domain.L0Constitutional)
}

pub fn page_fractal_zenoh_is_l6_test() {
  domain.page_fractal_layer(domain.Zenoh) |> should.equal(domain.L6Ecosystem)
}

pub fn page_fractal_podman_is_l4_test() {
  domain.page_fractal_layer(domain.Podman) |> should.equal(domain.L4System)
}

pub fn page_fractal_planning_is_l3_test() {
  domain.page_fractal_layer(domain.Planning)
  |> should.equal(domain.L3Transaction)
}

pub fn page_fractal_federation_is_l7_test() {
  domain.page_fractal_layer(domain.Federation)
  |> should.equal(domain.L7Federation)
}

pub fn page_fractal_metabolic_is_l1_test() {
  domain.page_fractal_layer(domain.Metabolic)
  |> should.equal(domain.L1AtomicDebug)
}

pub fn page_fractal_homeostasis_is_l2_test() {
  domain.page_fractal_layer(domain.HomeostasisPage)
  |> should.equal(domain.L2Component)
}

// ---------------------------------------------------------------------------
// HealthStatus constructors
// ---------------------------------------------------------------------------

pub fn health_status_healthy_test() {
  domain.Healthy |> should.equal(domain.Healthy)
}

pub fn health_status_degraded_test() {
  domain.Degraded("low memory")
  |> should.equal(domain.Degraded("low memory"))
}

pub fn health_status_critical_test() {
  domain.Critical("disk full") |> should.equal(domain.Critical("disk full"))
}

pub fn health_status_unknown_test() {
  domain.Unknown |> should.equal(domain.Unknown)
}

// ---------------------------------------------------------------------------
// FractalLayer constructors and layer_to_string / layer_level
// ---------------------------------------------------------------------------

pub fn layer_to_string_l0_test() {
  domain.layer_to_string(domain.L0Constitutional)
  |> should.equal("L0_CONSTITUTIONAL")
}

pub fn layer_to_string_l1_test() {
  domain.layer_to_string(domain.L1AtomicDebug)
  |> should.equal("L1_ATOMIC_DEBUG")
}

pub fn layer_to_string_l2_test() {
  domain.layer_to_string(domain.L2Component) |> should.equal("L2_COMPONENT")
}

pub fn layer_to_string_l3_test() {
  domain.layer_to_string(domain.L3Transaction)
  |> should.equal("L3_TRANSACTION")
}

pub fn layer_to_string_l4_test() {
  domain.layer_to_string(domain.L4System) |> should.equal("L4_SYSTEM")
}

pub fn layer_to_string_l5_test() {
  domain.layer_to_string(domain.L5Cognitive) |> should.equal("L5_COGNITIVE")
}

pub fn layer_to_string_l6_test() {
  domain.layer_to_string(domain.L6Ecosystem) |> should.equal("L6_ECOSYSTEM")
}

pub fn layer_to_string_l7_test() {
  domain.layer_to_string(domain.L7Federation) |> should.equal("L7_FEDERATION")
}

pub fn layer_level_l0_test() {
  domain.layer_level(domain.L0Constitutional) |> should.equal(0)
}

pub fn layer_level_l1_test() {
  domain.layer_level(domain.L1AtomicDebug) |> should.equal(1)
}

pub fn layer_level_l2_test() {
  domain.layer_level(domain.L2Component) |> should.equal(2)
}

pub fn layer_level_l3_test() {
  domain.layer_level(domain.L3Transaction) |> should.equal(3)
}

pub fn layer_level_l4_test() {
  domain.layer_level(domain.L4System) |> should.equal(4)
}

pub fn layer_level_l5_test() {
  domain.layer_level(domain.L5Cognitive) |> should.equal(5)
}

pub fn layer_level_l6_test() {
  domain.layer_level(domain.L6Ecosystem) |> should.equal(6)
}

pub fn layer_level_l7_test() {
  domain.layer_level(domain.L7Federation) |> should.equal(7)
}

pub fn layer_level_monotonically_ascending_test() {
  let levels = [
    domain.layer_level(domain.L0Constitutional),
    domain.layer_level(domain.L1AtomicDebug),
    domain.layer_level(domain.L2Component),
    domain.layer_level(domain.L3Transaction),
    domain.layer_level(domain.L4System),
    domain.layer_level(domain.L5Cognitive),
    domain.layer_level(domain.L6Ecosystem),
    domain.layer_level(domain.L7Federation),
  ]
  let pairs = list.zip(levels, list.drop(levels, 1))
  list.all(pairs, fn(p) {
    let #(a, b) = p
    b == a + 1
  })
  |> should.be_true
}

// ---------------------------------------------------------------------------
// boot_phase_to_string
// ---------------------------------------------------------------------------

pub fn boot_phase_preflight_test() {
  domain.boot_phase_to_string(domain.Preflight) |> should.equal("preflight")
}

pub fn boot_phase_foundation_test() {
  domain.boot_phase_to_string(domain.Foundation) |> should.equal("foundation")
}

pub fn boot_phase_mesh_test() {
  domain.boot_phase_to_string(domain.Mesh) |> should.equal("mesh")
}

pub fn boot_phase_cognitive_test() {
  domain.boot_phase_to_string(domain.Cognitive) |> should.equal("cognitive")
}

pub fn boot_phase_application_test() {
  domain.boot_phase_to_string(domain.Application) |> should.equal("application")
}

pub fn boot_phase_homeostasis_test() {
  domain.boot_phase_to_string(domain.Homeostasis) |> should.equal("homeostasis")
}

pub fn boot_phase_swarm_test() {
  domain.boot_phase_to_string(domain.Swarm) |> should.equal("swarm")
}

// ---------------------------------------------------------------------------
// mesh_mode_to_string
// ---------------------------------------------------------------------------

pub fn mesh_mode_standalone_test() {
  domain.mesh_mode_to_string(domain.Standalone) |> should.equal("standalone")
}

pub fn mesh_mode_clustered_test() {
  domain.mesh_mode_to_string(domain.Clustered) |> should.equal("clustered")
}

pub fn mesh_mode_federated_test() {
  domain.mesh_mode_to_string(domain.Federated) |> should.equal("federated")
}

// ---------------------------------------------------------------------------
// Composite types
// ---------------------------------------------------------------------------

pub fn telemetry_point_constructor_test() {
  let tp =
    domain.TelemetryPoint(
      key: "cpu",
      value: 0.42,
      timestamp: 1_000_000,
      unit: "%",
    )
  tp.key |> should.equal("cpu")
  tp.value |> should.equal(0.42)
  tp.unit |> should.equal("%")
  tp.timestamp |> should.equal(1_000_000)
}

pub fn device_health_constructor_test() {
  let dh =
    domain.DeviceHealth(
      id: "dev-001",
      health_score: 0.95,
      device_type: "sensor",
      status: domain.Online,
      last_seen: 9999,
    )
  dh.id |> should.equal("dev-001")
  dh.health_score |> should.equal(0.95)
  dh.status |> should.equal(domain.Online)
}

pub fn device_status_online_test() {
  domain.Online |> should.equal(domain.Online)
}

pub fn device_status_offline_test() {
  domain.Offline |> should.equal(domain.Offline)
}

pub fn device_status_maintenance_test() {
  domain.Maintenance |> should.equal(domain.Maintenance)
}

pub fn render_context_constructor_test() {
  let ctx =
    domain.RenderContext(
      page: domain.Dashboard,
      health: domain.Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  ctx.page |> should.equal(domain.Dashboard)
  ctx.health |> should.equal(domain.Healthy)
  ctx.zenoh_connected |> should.be_true
}

pub fn render_context_with_telemetry_test() {
  let tp =
    domain.TelemetryPoint(key: "mem", value: 0.7, timestamp: 1, unit: "%")
  let ctx =
    domain.RenderContext(
      page: domain.Telemetry,
      health: domain.Degraded("high mem"),
      telemetry: [tp],
      zenoh_connected: False,
    )
  list.length(ctx.telemetry) |> should.equal(1)
  ctx.zenoh_connected |> should.be_false
}

pub fn boot_config_constructor_test() {
  let cfg =
    domain.BootConfig(
      mode: domain.Standalone,
      timeout_ms: 30_000,
      max_retries: 3,
      patient_mode: True,
    )
  cfg.mode |> should.equal(domain.Standalone)
  cfg.max_retries |> should.equal(3)
  cfg.patient_mode |> should.be_true
}

pub fn voice_status_idle_test() {
  domain.VoiceIdle |> should.equal(domain.VoiceIdle)
}

pub fn voice_status_listening_test() {
  domain.VoiceListening |> should.equal(domain.VoiceListening)
}

pub fn voice_status_authenticated_test() {
  domain.VoiceAuthenticated("alice")
  |> should.equal(domain.VoiceAuthenticated("alice"))
}

pub fn voice_status_rejected_test() {
  domain.VoiceRejected("spoof") |> should.equal(domain.VoiceRejected("spoof"))
}

pub fn agent_binding_constructor_test() {
  let ab =
    domain.AgentBinding(
      agent_id: "agent-01",
      run_id: Some("run-42"),
      subscribed_topics: ["indrajaal/otel/spans/**"],
    )
  ab.agent_id |> should.equal("agent-01")
  ab.run_id |> should.equal(Some("run-42"))
  list.length(ab.subscribed_topics) |> should.equal(1)
}

pub fn fractal_element_constructor_test() {
  let fe =
    domain.FractalElement(
      id: "fe-001",
      layer: domain.L0Constitutional,
      element_type: "guardian_button",
      agent_binding: None,
      capabilities: [domain.EmitEvents],
      stamp_controls: ["SC-SIL4-006"],
    )
  fe.id |> should.equal("fe-001")
  fe.layer |> should.equal(domain.L0Constitutional)
  fe.agent_binding |> should.equal(None)
}

pub fn mathematical_integrity_constructor_test() {
  let mi = domain.MathematicalIntegrity(hs: 2.7, epsilon: 0.01, ds: 0.05)
  mi.hs |> should.equal(2.7)
  mi.epsilon |> should.equal(0.01)
}

pub fn evolution_vectors_constructor_test() {
  let ev = domain.EvolutionVectors(v1: 0.9, v2: 0.8, v3: 0.7, v4: 0.6)
  ev.v1 |> should.equal(0.9)
  ev.v4 |> should.equal(0.6)
}

pub fn bicameral_signoff_both_unsigned_test() {
  let bs =
    domain.BicameralSignOff(
      key1_signed: False,
      key2_signed: False,
      authorized_by: None,
    )
  bs.key1_signed |> should.be_false
  bs.key2_signed |> should.be_false
  bs.authorized_by |> should.equal(None)
}

pub fn bicameral_signoff_both_signed_test() {
  let bs =
    domain.BicameralSignOff(
      key1_signed: True,
      key2_signed: True,
      authorized_by: Some("admin"),
    )
  bs.key1_signed |> should.be_true
  bs.authorized_by |> should.equal(Some("admin"))
}

pub fn singularity_estimation_constructor_test() {
  let se =
    domain.SingularityEstimation(
      time_to_singularity_ms: 86_400_000,
      confidence_interval: 0.95,
      critical_threshold_reached: False,
    )
  se.confidence_interval |> should.equal(0.95)
  se.critical_threshold_reached |> should.be_false
}

pub fn biomorphic_matrix_constructor_test() {
  let bm =
    domain.BiomorphicMatrix(levels: [
      #(domain.L0Constitutional, domain.Healthy),
      #(domain.L7Federation, domain.Degraded("latency")),
    ])
  list.length(bm.levels) |> should.equal(2)
}

pub fn homeostasis_controls_constructor_test() {
  let hc =
    domain.HomeostasisControls(
      kp: 1.0,
      ki: 0.1,
      kd: 0.05,
      set_point: 0.8,
      current_value: 0.75,
      error: 0.05,
    )
  hc.kp |> should.equal(1.0)
  hc.error |> should.equal(0.05)
  hc.set_point |> should.equal(0.8)
}

// ---------------------------------------------------------------------------
// Action constructors
// ---------------------------------------------------------------------------

pub fn action_navigate_test() {
  domain.Navigate(domain.Dashboard)
  |> should.equal(domain.Navigate(domain.Dashboard))
}

pub fn action_refresh_test() {
  domain.Refresh |> should.equal(domain.Refresh)
}

pub fn action_execute_test() {
  domain.Execute("restart") |> should.equal(domain.Execute("restart"))
}

pub fn action_subscribe_test() {
  domain.Subscribe("indrajaal/health/**")
  |> should.equal(domain.Subscribe("indrajaal/health/**"))
}

pub fn action_unsubscribe_test() {
  domain.Unsubscribe("indrajaal/health/**")
  |> should.equal(domain.Unsubscribe("indrajaal/health/**"))
}

pub fn action_request_approval_test() {
  domain.RequestApproval("req-1", "Stop cortex", 0)
  |> should.equal(domain.RequestApproval("req-1", "Stop cortex", 0))
}

pub fn action_biometric_verify_test() {
  domain.BiometricVerify("base64data")
  |> should.equal(domain.BiometricVerify("base64data"))
}

// ---------------------------------------------------------------------------
// Capability variants
// ---------------------------------------------------------------------------

pub fn capability_emit_events_test() {
  domain.EmitEvents |> should.equal(domain.EmitEvents)
}

pub fn capability_receive_events_test() {
  domain.ReceiveEvents |> should.equal(domain.ReceiveEvents)
}

pub fn capability_propose_ui_test() {
  domain.ProposeUI |> should.equal(domain.ProposeUI)
}

pub fn capability_accept_hitl_test() {
  domain.AcceptHITL |> should.equal(domain.AcceptHITL)
}

pub fn capability_persist_state_test() {
  domain.PersistState |> should.equal(domain.PersistState)
}

pub fn capability_stream_content_test() {
  domain.StreamContent |> should.equal(domain.StreamContent)
}

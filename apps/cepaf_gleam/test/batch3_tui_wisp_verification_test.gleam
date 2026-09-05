// =============================================================================
// Batch 3: TUI / Wisp / Verification / Domain Pure-Logic Tests
// =============================================================================
// Covers modules with ZERO prior test coverage.
// ALL functions tested here are pure — no FFI, no network, no SQLite.
// STAMP: SC-GLM-CMP-001, SC-GLM-UI-001
// =============================================================================

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/core/ids
import cepaf_gleam/metabolic/domain as metabolic_domain
import cepaf_gleam/metabolic/service as metabolic_service
import cepaf_gleam/podman/domain as podman_domain
import cepaf_gleam/podman/http_client
import cepaf_gleam/substrate/governor
import cepaf_gleam/ui/domain.{
  Critical, Dashboard, Degraded, Healthy, RenderContext, TelemetryPoint, Unknown,
}
import cepaf_gleam/ui/tui/renderer
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/verification/probes
import cepaf_gleam/verification/swarm
import cepaf_gleam/zenoh/domain as zenoh_domain
import gleam/json
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// 1. cockpit/visuals — with_color, render_progress_bar, render_sparkline
// =============================================================================

pub fn visuals_with_color_green_test() {
  let result = visuals.with_color("OK", "green")
  result |> should.equal("\u{001b}[32mOK\u{001b}[0m")
}

pub fn visuals_with_color_red_test() {
  let result = visuals.with_color("FAIL", "red")
  result |> should.equal("\u{001b}[31mFAIL\u{001b}[0m")
}

pub fn visuals_with_color_yellow_test() {
  let result = visuals.with_color("WARN", "yellow")
  result |> should.equal("\u{001b}[33mWARN\u{001b}[0m")
}

pub fn visuals_with_color_cyan_test() {
  let result = visuals.with_color("INFO", "cyan")
  result |> should.equal("\u{001b}[36mINFO\u{001b}[0m")
}

pub fn visuals_with_color_magenta_test() {
  let result = visuals.with_color("DBG", "magenta")
  result |> should.equal("\u{001b}[35mDBG\u{001b}[0m")
}

pub fn visuals_with_color_blue_test() {
  let result = visuals.with_color("NOTE", "blue")
  result |> should.equal("\u{001b}[34mNOTE\u{001b}[0m")
}

pub fn visuals_with_color_unknown_passthrough_test() {
  // Unknown color returns text unchanged (no ANSI wrapping)
  let result = visuals.with_color("plain", "neon")
  result |> should.equal("plain")
}

pub fn visuals_render_progress_bar_full_test() {
  let bar = visuals.render_progress_bar(1.0, 10)
  // 100% → green, all filled
  bar |> string.contains("[==========]") |> should.be_true()
}

pub fn visuals_render_progress_bar_half_test() {
  let bar = visuals.render_progress_bar(0.5, 10)
  // 50% → yellow
  bar |> string.contains("[=====     ]") |> should.be_true()
}

pub fn visuals_render_progress_bar_low_test() {
  let bar = visuals.render_progress_bar(0.2, 10)
  // 20% → red
  bar |> string.contains("[==        ]") |> should.be_true()
}

pub fn visuals_render_progress_bar_zero_test() {
  let bar = visuals.render_progress_bar(0.0, 10)
  bar |> string.contains("[          ]") |> should.be_true()
}

pub fn visuals_render_sparkline_basic_test() {
  let spark = visuals.render_sparkline([0.0, 3.5, 7.0])
  // Should produce 3 characters (one per data point)
  string.length(spark) |> should.equal(3)
}

pub fn visuals_render_sparkline_empty_test() {
  let spark = visuals.render_sparkline([])
  spark |> should.equal("")
}

pub fn visuals_render_sparkline_uniform_test() {
  // All equal values → all map to block index 7 (max)
  let spark = visuals.render_sparkline([5.0, 5.0, 5.0])
  spark |> should.equal("███")
}

pub fn visuals_render_sparkline_all_zero_test() {
  // All zero → max_val is 0.0, so index=0 → space
  let spark = visuals.render_sparkline([0.0, 0.0])
  spark |> should.equal("  ")
}

// =============================================================================
// 2. podman/domain — status_to_string, string_to_status, health_status_*,
//                     default_config
// =============================================================================

pub fn podman_status_to_string_created_test() {
  podman_domain.status_to_string(podman_domain.Created)
  |> should.equal("created")
}

pub fn podman_status_to_string_running_test() {
  podman_domain.status_to_string(podman_domain.Running)
  |> should.equal("running")
}

pub fn podman_status_to_string_paused_test() {
  podman_domain.status_to_string(podman_domain.Paused)
  |> should.equal("paused")
}

pub fn podman_status_to_string_restarting_test() {
  podman_domain.status_to_string(podman_domain.Restarting)
  |> should.equal("restarting")
}

pub fn podman_status_to_string_removing_test() {
  podman_domain.status_to_string(podman_domain.Removing)
  |> should.equal("removing")
}

pub fn podman_status_to_string_exited_test() {
  podman_domain.status_to_string(podman_domain.Exited(137))
  |> should.equal("exited")
}

pub fn podman_status_to_string_dead_test() {
  podman_domain.status_to_string(podman_domain.Dead("oom"))
  |> should.equal("dead")
}

pub fn podman_status_to_string_unknown_test() {
  podman_domain.status_to_string(podman_domain.Unknown("custom"))
  |> should.equal("custom")
}

pub fn podman_string_to_status_roundtrip_test() {
  podman_domain.string_to_status("created")
  |> should.equal(podman_domain.Created)
  podman_domain.string_to_status("running")
  |> should.equal(podman_domain.Running)
  podman_domain.string_to_status("paused")
  |> should.equal(podman_domain.Paused)
  podman_domain.string_to_status("restarting")
  |> should.equal(podman_domain.Restarting)
  podman_domain.string_to_status("removing")
  |> should.equal(podman_domain.Removing)
  podman_domain.string_to_status("exited")
  |> should.equal(podman_domain.Exited(0))
  podman_domain.string_to_status("dead")
  |> should.equal(podman_domain.Dead("unknown"))
}

pub fn podman_string_to_status_unknown_test() {
  podman_domain.string_to_status("wat")
  |> should.equal(podman_domain.Unknown("wat"))
}

pub fn podman_health_status_to_string_starting_test() {
  podman_domain.health_status_to_string(podman_domain.Starting)
  |> should.equal("starting")
}

pub fn podman_health_status_to_string_healthy_test() {
  podman_domain.health_status_to_string(podman_domain.Healthy)
  |> should.equal("healthy")
}

pub fn podman_health_status_to_string_unhealthy_test() {
  podman_domain.health_status_to_string(podman_domain.Unhealthy(3))
  |> should.equal("unhealthy")
}

pub fn podman_health_status_to_string_none_test() {
  podman_domain.health_status_to_string(podman_domain.NoHealthcheck)
  |> should.equal("none")
}

pub fn podman_health_status_to_string_unknown_test() {
  podman_domain.health_status_to_string(podman_domain.UnknownHealth("x"))
  |> should.equal("x")
}

pub fn podman_string_to_health_status_roundtrip_test() {
  podman_domain.string_to_health_status("starting")
  |> should.equal(podman_domain.Starting)
  podman_domain.string_to_health_status("healthy")
  |> should.equal(podman_domain.Healthy)
  podman_domain.string_to_health_status("unhealthy")
  |> should.equal(podman_domain.Unhealthy(0))
  podman_domain.string_to_health_status("none")
  |> should.equal(podman_domain.NoHealthcheck)
  podman_domain.string_to_health_status("")
  |> should.equal(podman_domain.NoHealthcheck)
}

pub fn podman_string_to_health_status_unknown_test() {
  podman_domain.string_to_health_status("bogus")
  |> should.equal(podman_domain.UnknownHealth("bogus"))
}

pub fn podman_default_config_test() {
  let cfg = podman_domain.default_config()
  cfg.api_version |> should.equal("5.7.0")
  cfg.timeout_ms |> should.equal(30_000)
  cfg.retry_count |> should.equal(3)
  cfg.retry_delay_ms |> should.equal(1000)
}

// =============================================================================
// 3. podman/http_client — create (pure struct construction, no network)
// =============================================================================

pub fn http_client_create_rootless_test() {
  let cfg =
    podman_domain.PodmanClientConfig(
      socket: podman_domain.Rootless(
        uid: "1000",
        path: "/run/user/1000/podman/podman.sock",
      ),
      api_version: "5.7.0",
      timeout_ms: 30_000,
      retry_count: 3,
      retry_delay_ms: 1000,
    )
  let client = http_client.create(cfg)
  client.socket_path
  |> should.equal("/run/user/1000/podman/podman.sock")
  client.base_path
  |> should.equal("http://localhost/v5.7.0/libpod")
}

pub fn http_client_create_rootful_test() {
  let cfg =
    podman_domain.PodmanClientConfig(
      socket: podman_domain.Rootful(path: "/run/podman/podman.sock"),
      api_version: "4.0.0",
      timeout_ms: 10_000,
      retry_count: 1,
      retry_delay_ms: 500,
    )
  let client = http_client.create(cfg)
  client.socket_path
  |> should.equal("/run/podman/podman.sock")
  client.base_path
  |> should.equal("http://localhost/v4.0.0/libpod")
}

// =============================================================================
// 4. verification/probes — verify_2oo3
// =============================================================================

pub fn verify_2oo3_all_healthy_test() {
  probes.verify_2oo3([probes.Healthy, probes.Healthy, probes.Healthy])
  |> should.equal(probes.Healthy)
}

pub fn verify_2oo3_two_healthy_test() {
  probes.verify_2oo3([probes.Healthy, probes.Unhealthy("x"), probes.Healthy])
  |> should.equal(probes.Healthy)
}

pub fn verify_2oo3_one_healthy_test() {
  let result =
    probes.verify_2oo3([
      probes.Healthy,
      probes.Unhealthy("a"),
      probes.Unhealthy("b"),
    ])
  case result {
    probes.Unhealthy(msg) -> msg |> string.contains("1/3") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn verify_2oo3_none_healthy_test() {
  let result =
    probes.verify_2oo3([
      probes.Unhealthy("a"),
      probes.Unhealthy("b"),
      probes.Unhealthy("c"),
    ])
  case result {
    probes.Unhealthy(msg) -> msg |> string.contains("0/3") |> should.be_true()
    _ -> should.fail()
  }
}

pub fn verify_2oo3_empty_list_test() {
  // 0 healthy out of 0 — quorum not reached
  let result = probes.verify_2oo3([])
  case result {
    probes.Unhealthy(_) -> should.be_true(True)
    _ -> should.fail()
  }
}

// =============================================================================
// 5. verification/swarm — verify_ooda_compliance, generate_report
// =============================================================================

pub fn swarm_verify_ooda_compliance_test() {
  let metrics = swarm.verify_ooda_compliance(["t1", "t2"])
  metrics.compliance |> should.be_true()
  metrics.agent_latency_ms |> should.equal(25)
  metrics.intelligence_latency_ms |> should.equal(80)
}

pub fn swarm_generate_report_test() {
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: True,
    )
  let report = swarm.generate_report(metrics, 12, 15)
  report.healthy_containers |> should.equal(12)
  report.total_containers |> should.equal(15)
  report.ooda_metrics.compliance |> should.be_true()
  // Must contain 8 fractal layer entries (L0-L7)
  list.length(report.fractal_layers) |> should.equal(8)
  let _l0 =
    list.find(report.fractal_layers, fn(l) { l.layer == 0 })
    |> should.be_ok()
  let _l1 =
    list.find(report.fractal_layers, fn(l) { l.layer == 1 })
    |> should.be_ok()
  let _l4 =
    list.find(report.fractal_layers, fn(l) { l.layer == 4 })
    |> should.be_ok()
}

// =============================================================================
// 6. zenoh/domain — empty_health, default_config
// =============================================================================

pub fn zenoh_empty_health_test() {
  let h = zenoh_domain.empty_health()
  h.session_id |> should.equal("")
  h.connected_at |> should.equal(0)
  h.last_heartbeat |> should.equal(0)
  h.reconnect_count |> should.equal(0)
  h.messages_published |> should.equal(0)
  h.messages_received |> should.equal(0)
  h.error_count |> should.equal(0)
  h.status |> should.equal(zenoh_domain.Disconnected)
}

pub fn zenoh_default_config_test() {
  let cfg = zenoh_domain.default_config()
  cfg.router_endpoint |> should.equal("tcp/localhost:7447")
  cfg.mode |> should.equal("client")
  cfg.connect_timeout_ms |> should.equal(5000)
}

// =============================================================================
// 7. substrate/governor — evaluate_metabolic_state
// =============================================================================

pub fn governor_low_cpu_expands_test() {
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 20.0,
      memory_usage_mb: 4096,
      container_count: 5,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.Expand)
}

pub fn governor_mid_cpu_maintains_test() {
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 60.0,
      memory_usage_mb: 8192,
      container_count: 10,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.Maintain)
}

pub fn governor_high_cpu_contracts_test() {
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 90.0,
      memory_usage_mb: 8192,
      container_count: 15,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.Contract)
}

pub fn governor_memory_exhaustion_halts_test() {
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 50.0,
      memory_usage_mb: 40_000,
      container_count: 15,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.EmergencyHalt("Memory exhaustion detected"))
}

pub fn governor_boundary_cpu_85_contracts_test() {
  // cpu > 85.0 → Contract
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 85.1,
      memory_usage_mb: 1024,
      container_count: 3,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.Contract)
}

pub fn governor_boundary_cpu_40_expands_test() {
  // cpu < 40.0 → Expand
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 39.9,
      memory_usage_mb: 1024,
      container_count: 3,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.Expand)
}

pub fn governor_boundary_cpu_exactly_40_maintains_test() {
  // cpu == 40.0: NOT <40.0, so Maintain
  let metrics =
    governor.ResourceMetrics(
      cpu_usage_pct: 40.0,
      memory_usage_mb: 1024,
      container_count: 3,
    )
  governor.evaluate_metabolic_state(metrics)
  |> should.equal(governor.Maintain)
}

// =============================================================================
// 8. metabolic/service — calculate_metabolic_set_point, update_set_point
// =============================================================================

pub fn metabolic_set_point_normal_test() {
  // energy=100.0, cpu_load=0.5 → base_rate = 100*0.8 = 80.0, cpu ≤ 0.95 → 80.0
  metabolic_service.calculate_metabolic_set_point(100.0, 0.5)
  |> should.equal(80.0)
}

pub fn metabolic_set_point_high_cpu_test() {
  // energy=100.0, cpu_load=0.96 (>0.95) → base_rate 80.0 * 0.5 = 40.0
  metabolic_service.calculate_metabolic_set_point(100.0, 0.96)
  |> should.equal(40.0)
}

pub fn metabolic_set_point_zero_energy_test() {
  metabolic_service.calculate_metabolic_set_point(0.0, 0.5)
  |> should.equal(0.0)
}

pub fn metabolic_set_point_boundary_cpu_095_test() {
  // Exactly 0.95 is NOT > 0.95, so no throttle
  metabolic_service.calculate_metabolic_set_point(100.0, 0.95)
  |> should.equal(80.0)
}

pub fn metabolic_update_set_point_test() {
  let holon_id = ids.holon_id_from_string("test-holon-001")
  let state =
    metabolic_domain.MetabolicState(
      holon_id: holon_id,
      timestamp: "2026-04-02T00:00:00Z",
      cpu_usage_percent: 50.0,
      memory_usage_bytes: 1_073_741_824,
      network_latency_ms: 2.5,
      tps: 1000.0,
      error_rate: 0.01,
      metabolic_rate: 0.0,
      health_status: metabolic_domain.Stable,
    )
  let updated = metabolic_service.update_set_point(state)
  // cpu_usage_percent=50.0, so cpu_load = 50.0/100.0 = 0.5 (≤0.95)
  // base_rate = 100.0 * 0.8 = 80.0 → no throttle → 80.0
  updated.metabolic_rate |> should.equal(80.0)
  // Other fields unchanged
  updated.cpu_usage_percent |> should.equal(50.0)
  updated.tps |> should.equal(1000.0)
}

pub fn metabolic_update_set_point_high_cpu_test() {
  let holon_id = ids.holon_id_from_string("test-holon-002")
  let state =
    metabolic_domain.MetabolicState(
      holon_id: holon_id,
      timestamp: "2026-04-02T00:00:00Z",
      cpu_usage_percent: 96.0,
      memory_usage_bytes: 2_147_483_648,
      network_latency_ms: 5.0,
      tps: 500.0,
      error_rate: 0.05,
      metabolic_rate: 0.0,
      health_status: metabolic_domain.Degraded,
    )
  let updated = metabolic_service.update_set_point(state)
  // cpu_load = 96.0/100.0 = 0.96 (>0.95) → throttle: 80.0 * 0.5 = 40.0
  updated.metabolic_rate |> should.equal(40.0)
}

// =============================================================================
// 9. ui/wisp/router — route (various paths), encode_health
// =============================================================================

pub fn router_health_endpoint_test() {
  let resp = router.route("/health")
  resp |> string.contains("\"status\"") |> should.be_true()
  resp |> string.contains("\"ok\"") |> should.be_true()
  resp |> string.contains("\"wisp\"") |> should.be_true()
  resp |> string.contains("4100") |> should.be_true()
}

pub fn router_pages_endpoint_test() {
  let resp = router.route("/api/v1/pages")
  resp |> string.contains("\"pages\"") |> should.be_true()
  resp |> string.contains("Dashboard") |> should.be_true()
  resp |> string.contains("Planning") |> should.be_true()
}

pub fn router_dashboard_endpoint_test() {
  let resp = router.route("/api/v1/dashboard")
  resp |> string.contains("Dashboard") |> should.be_true()
  resp |> string.contains("\"active\"") |> should.be_true()
}

pub fn router_planning_endpoint_test() {
  let resp = router.route("/api/v1/planning")
  resp |> string.contains("Planning") |> should.be_true()
}

pub fn router_immune_endpoint_test() {
  let resp = router.route("/api/v1/immune")
  resp |> string.contains("Immune") |> should.be_true()
}

pub fn router_knowledge_endpoint_test() {
  let resp = router.route("/api/v1/knowledge")
  resp |> string.contains("Knowledge") |> should.be_true()
}

pub fn router_zenoh_endpoint_test() {
  let resp = router.route("/api/v1/zenoh")
  resp |> string.contains("Zenoh") |> should.be_true()
}

pub fn router_verification_endpoint_test() {
  let resp = router.route("/api/v1/verification")
  resp |> string.contains("Verification") |> should.be_true()
}

pub fn router_not_found_test() {
  let resp = router.route("/nonexistent")
  resp |> string.contains("not_found") |> should.be_true()
  resp |> string.contains("/nonexistent") |> should.be_false()
}

pub fn router_default_port_test() {
  router.default_port |> should.equal(4100)
}

pub fn router_encode_health_healthy_test() {
  let encoded = router.encode_health(Healthy) |> json.to_string()
  encoded |> should.equal("\"healthy\"")
}

pub fn router_encode_health_degraded_test() {
  let encoded =
    router.encode_health(Degraded("high latency")) |> json.to_string()
  encoded |> string.contains("degraded") |> should.be_true()
  encoded |> string.contains("high latency") |> should.be_true()
}

pub fn router_encode_health_critical_test() {
  let encoded = router.encode_health(Critical("db down")) |> json.to_string()
  encoded |> string.contains("critical") |> should.be_true()
  encoded |> string.contains("db down") |> should.be_true()
}

pub fn router_encode_health_unknown_test() {
  let encoded = router.encode_health(Unknown) |> json.to_string()
  encoded |> should.equal("\"unknown\"")
}

// =============================================================================
// 10. ui/tui/renderer — render_frame with mock RenderContext
// =============================================================================

pub fn tui_render_frame_healthy_no_telemetry_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  // Must contain header elements
  frame |> string.contains("c3i") |> should.be_true()
  frame |> string.contains("Dashboard") |> should.be_true()
  // Must contain health
  frame |> string.contains("HEALTH: OK") |> should.be_true()
  // Must contain zenoh connected
  frame |> string.contains("ZENOH: CONNECTED") |> should.be_true()
  // No telemetry
  frame |> string.contains("no data") |> should.be_true()
}

pub fn tui_render_frame_degraded_with_telemetry_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Degraded("high load"),
      telemetry: [
        TelemetryPoint(key: "cpu", value: 50.0, timestamp: 1000, unit: "%"),
        TelemetryPoint(key: "cpu", value: 75.0, timestamp: 2000, unit: "%"),
      ],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("DEGRADED") |> should.be_true()
  frame |> string.contains("high load") |> should.be_true()
  frame |> string.contains("ZENOH: DISCONNECTED") |> should.be_true()
  frame |> string.contains("2 pts") |> should.be_true()
}

pub fn tui_render_frame_critical_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Critical("db failure"),
      telemetry: [],
      zenoh_connected: False,
    )
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("CRITICAL") |> should.be_true()
  frame |> string.contains("db failure") |> should.be_true()
}

pub fn tui_render_frame_unknown_health_test() {
  let ctx =
    RenderContext(
      page: Dashboard,
      health: Unknown,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("UNKNOWN") |> should.be_true()
}

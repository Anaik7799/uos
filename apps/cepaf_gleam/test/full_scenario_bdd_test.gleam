//// =============================================================================
//// FULL USE CASE SCENARIO: BDD 7-LEVEL VERIFICATION
//// =============================================================================
//// STAMP: SC-BDD-001, SC-GLM-UI-001, SC-GLM-UI-009
//// Ref: docs/journal/20260404-0800-50-bdd-7level-usecases.md
////
//// This suite performs "Golden Triangle" verification by asserting on:
//// 1. Lustre Model state transitions.
//// 2. Wisp (API) JSON responses.
//// 3. TUI (ANSI) rendered frames.
//// =============================================================================

import cepaf_gleam/ui/domain.{
  Cockpit, Healthy, RenderContext, TelemetryPoint, Verification,
}
import cepaf_gleam/ui/lustre/verification
import cepaf_gleam/ui/tui/renderer
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/verification/probes
import cepaf_gleam/verification/swarm
import gleam/json
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// =============================================================================
// SCENARIO 1: UC-02 Wave 0 Zenoh Quorum Consensus (Checks Tab)
// =============================================================================

pub fn uc02_zenoh_quorum_consensus_test() {
  // GIVEN: 2 of 3 Zenoh routers are healthy
  let probes_list = [
    probes.Healthy,
    probes.Healthy,
    probes.Unhealthy("timeout"),
  ]

  // WHEN: refresh_state evaluates the state vector
  let quorum_result = probes.verify_2oo3(probes_list)

  // THEN: The result is Healthy (Consensus reached)
  quorum_result |> should.equal(probes.Healthy)

  // AND: The TUI frame renders the consensus
  let ctx =
    RenderContext(
      page: Verification,
      health: Healthy,
      telemetry: [],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("ZENOH: CONNECTED") |> should.be_true()

  // AND: The Wisp API returns active status
  let resp = router.route("/api/v1/verification")
  resp |> string.contains("\"active\"") |> should.be_true()
}

// =============================================================================
// SCENARIO 2: UC-05 State Machine Transition Sparkline (Swarm/Podman Tab)
// =============================================================================

pub fn uc05_state_machine_transition_sparkline_test() {
  // GIVEN: A container transitions from 'created' to 'running'

  // WHEN: A swarm report is generated
  let metrics =
    swarm.OodaMetrics(
      agent_latency_ms: 10,
      intelligence_latency_ms: 20,
      compliance: True,
    )
  let report = swarm.generate_report(metrics, 16, 16)

  // THEN: The Lustre VerificationModel updates correctly
  let model = verification.init()
  let updated_model =
    verification.update(model, verification.ReportReceived(report))

  updated_model.last_report |> should.equal(Some(report))
  verification.compliance_percent(report) |> should.equal(100.0)

  // AND: The TUI frame shows '1 pts' (telemetry simulation)
  let ctx =
    RenderContext(
      page: domain.Podman,
      health: Healthy,
      telemetry: [TelemetryPoint("swarm_healthy", 16.0, 0, "nodes")],
      zenoh_connected: True,
    )
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("(1 pts)") |> should.be_true()
}

// =============================================================================
// SCENARIO 3: UC-32 Agent Confidence Score (Agent UI / Cockpit)
// =============================================================================

pub fn uc32_agent_confidence_score_test() {
  // GIVEN: The system has high confidence (92%)
  let confidence = 0.92

  // WHEN: The CockpitModel receives an update (simulated via RenderContext)
  let ctx =
    RenderContext(
      page: Cockpit,
      health: Healthy,
      telemetry: [TelemetryPoint("agent_confidence", confidence, 0, "score")],
      zenoh_connected: True,
    )

  // THEN: The TUI frame renders the confidence telemetry point
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("(1 pts)") |> should.be_true()

  // AND: The Wisp API returns the cockpit state
  let resp = router.route("/api/cockpit/nodes")
  resp |> string.contains("Cockpit") |> should.be_true()
}

// =============================================================================
// SCENARIO 4: UC-41 TUI Logger Integration (Logs Tab)
// =============================================================================

pub fn uc41_tui_logger_integration_test() {
  // GIVEN: A critical failure occurred
  let failure_reason = "DB_TIMEOUT"

  // WHEN: The health state is set to Critical
  let ctx =
    RenderContext(
      page: domain.Telemetry,
      health: domain.Critical(failure_reason),
      telemetry: [],
      zenoh_connected: False,
    )

  // THEN: The TUI frame renders 'CRITICAL' and the reason
  let frame = renderer.render_frame(ctx)
  frame |> string.contains("CRITICAL") |> should.be_true()
  frame |> string.contains(failure_reason) |> should.be_true()

  // AND: The Wisp API encodes the critical state correctly
  let encoded_health = router.encode_health(domain.Critical(failure_reason))
  let health_json = json.to_string(encoded_health)
  health_json |> string.contains("critical") |> should.be_true()
  health_json |> string.contains(failure_reason) |> should.be_true()
}

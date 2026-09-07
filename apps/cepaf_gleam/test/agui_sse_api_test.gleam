// =============================================================================
// [C3I-SIL6-MSTS] AG-UI 32-EVENT SSE API TEST SUITE (SC-AGUI-001, SC-GLM-UI-001)
// =============================================================================

import cepaf_gleam/ui/wisp/agui_sse_api.{
  AGUIStreamConfig, agui_manifest_summary_json, default_config,
  sse_32_event_manifest_stream, sse_cockpit_push_frame,
}
import cepaf_gleam/ui/wisp/router
import gleam/string
import gleeunit/should

pub fn default_config_test() {
  let cfg = default_config()
  cfg.thread_id |> should.equal("thread-cockpit-001")
  cfg.run_id |> should.equal("run-cockpit-001")
  cfg.agent |> should.equal("c3i-cockpit-supervisor")
}

pub fn sse_32_event_manifest_contains_all_categories_test() {
  let cfg =
    AGUIStreamConfig(
      thread_id: "th-test-42",
      run_id: "rn-test-42",
      agent: "test-agent",
      trace_id: "00-trace-test-01",
    )

  let stream = sse_32_event_manifest_stream(cfg)

  // Verify AG-UI data frame formatting
  string.contains(stream, "\"type\":\"RUN_STARTED\"") |> should.be_true()
  string.contains(stream, "\"type\":\"STEP_STARTED\"") |> should.be_true()
  string.contains(stream, "\"type\":\"STATE_SNAPSHOT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"STATE_DELTA\"") |> should.be_true()
  string.contains(stream, "\"type\":\"MESSAGES_SNAPSHOT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"ACTIVITY_SNAPSHOT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"ACTIVITY_DELTA\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TEXT_MESSAGE_START\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TEXT_MESSAGE_CONTENT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TEXT_MESSAGE_CHUNK\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TEXT_MESSAGE_END\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_START\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_MESSAGE_START\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_MESSAGE_CONTENT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_MESSAGE_CHUNK\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_MESSAGE_END\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_END\"") |> should.be_true()
  string.contains(stream, "\"type\":\"REASONING_ENCRYPTED_VALUE\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TOOL_CALL_START\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TOOL_CALL_ARGS\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TOOL_CALL_CHUNK\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TOOL_CALL_RESULT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"TOOL_CALL_END\"") |> should.be_true()
  string.contains(stream, "\"type\":\"BIOMETRIC_STARTED\"") |> should.be_true()
  string.contains(stream, "\"type\":\"BIOMETRIC_RESULT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"APPROVAL_REQUESTED\"") |> should.be_true()
  string.contains(stream, "\"type\":\"APPROVAL_RESULT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"CUSTOM\"") |> should.be_true()
  string.contains(stream, "\"type\":\"META_EVENT\"") |> should.be_true()
  string.contains(stream, "\"type\":\"RAW\"") |> should.be_true()
  string.contains(stream, "\"type\":\"STEP_FINISHED\"") |> should.be_true()
  string.contains(stream, "\"type\":\"RUN_FINISHED\"") |> should.be_true()

  // Verify payloads are embedded
  string.contains(stream, "th-test-42") |> should.be_true()
  string.contains(stream, "rn-test-42") |> should.be_true()
  string.contains(stream, "00-trace-test-01") |> should.be_true()
}

pub fn sse_cockpit_push_frame_test() {
  let frame =
    sse_cockpit_push_frame(
      "telemetry_tick",
      "{\"cpu\":0.15,\"memory\":0.42}",
      "tick-100",
    )

  string.contains(frame, "id: tick-100\n") |> should.be_true()
  string.contains(frame, "event: telemetry_tick\n") |> should.be_true()
  string.contains(frame, "data: {\"cpu\":0.15,\"memory\":0.42}\n")
  |> should.be_true()
  string.contains(frame, "retry: 3000\n") |> should.be_true()
}

pub fn agui_manifest_summary_test() {
  let manifest = agui_manifest_summary_json()
  string.contains(manifest, "\"protocol\":\"AG-UI-v1\"") |> should.be_true()
  string.contains(manifest, "\"event_count\":32") |> should.be_true()
  string.contains(manifest, "\"status\":\"compliant\"") |> should.be_true()
}

pub fn router_agui_routes_test() {
  let sse_out = router.route("/ag-ui/events/sse")
  string.contains(sse_out, "\"type\":\"RUN_STARTED\"") |> should.be_true()
  string.contains(sse_out, "\"type\":\"RUN_FINISHED\"") |> should.be_true()

  let stream_out = router.route("/api/v1/ag-ui/stream")
  string.contains(stream_out, "\"type\":\"RUN_STARTED\"") |> should.be_true()

  let manifest_out = router.route("/ag-ui/manifest")
  string.contains(manifest_out, "\"protocol\":\"AG-UI-v1\"") |> should.be_true()
}

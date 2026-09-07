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

  // Verify W3C SSE frame formatting
  string.contains(stream, "event: RUN_STARTED\n") |> should.be_true()
  string.contains(stream, "event: STEP_STARTED\n") |> should.be_true()
  string.contains(stream, "event: STATE_SNAPSHOT\n") |> should.be_true()
  string.contains(stream, "event: STATE_DELTA\n") |> should.be_true()
  string.contains(stream, "event: MESSAGES_SNAPSHOT\n") |> should.be_true()
  string.contains(stream, "event: ACTIVITY_SNAPSHOT\n") |> should.be_true()
  string.contains(stream, "event: ACTIVITY_DELTA\n") |> should.be_true()
  string.contains(stream, "event: TEXT_MESSAGE_START\n") |> should.be_true()
  string.contains(stream, "event: TEXT_MESSAGE_CONTENT\n") |> should.be_true()
  string.contains(stream, "event: TEXT_MESSAGE_CHUNK\n") |> should.be_true()
  string.contains(stream, "event: TEXT_MESSAGE_END\n") |> should.be_true()
  string.contains(stream, "event: REASONING_START\n") |> should.be_true()
  string.contains(stream, "event: REASONING_MESSAGE_START\n") |> should.be_true()
  string.contains(stream, "event: REASONING_MESSAGE_CONTENT\n") |> should.be_true()
  string.contains(stream, "event: REASONING_MESSAGE_CHUNK\n") |> should.be_true()
  string.contains(stream, "event: REASONING_MESSAGE_END\n") |> should.be_true()
  string.contains(stream, "event: REASONING_END\n") |> should.be_true()
  string.contains(stream, "event: REASONING_ENCRYPTED_VALUE\n") |> should.be_true()
  string.contains(stream, "event: TOOL_CALL_START\n") |> should.be_true()
  string.contains(stream, "event: TOOL_CALL_ARGS\n") |> should.be_true()
  string.contains(stream, "event: TOOL_CALL_CHUNK\n") |> should.be_true()
  string.contains(stream, "event: TOOL_CALL_RESULT\n") |> should.be_true()
  string.contains(stream, "event: TOOL_CALL_END\n") |> should.be_true()
  string.contains(stream, "event: BIOMETRIC_STARTED\n") |> should.be_true()
  string.contains(stream, "event: BIOMETRIC_RESULT\n") |> should.be_true()
  string.contains(stream, "event: APPROVAL_REQUESTED\n") |> should.be_true()
  string.contains(stream, "event: APPROVAL_RESULT\n") |> should.be_true()
  string.contains(stream, "event: CUSTOM\n") |> should.be_true()
  string.contains(stream, "event: META_EVENT\n") |> should.be_true()
  string.contains(stream, "event: RAW\n") |> should.be_true()
  string.contains(stream, "event: STEP_FINISHED\n") |> should.be_true()
  string.contains(stream, "event: RUN_FINISHED\n") |> should.be_true()

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
  string.contains(sse_out, "event: RUN_STARTED\n") |> should.be_true()
  string.contains(sse_out, "event: RUN_FINISHED\n") |> should.be_true()

  let stream_out = router.route("/api/v1/ag-ui/stream")
  string.contains(stream_out, "event: RUN_STARTED\n") |> should.be_true()

  let manifest_out = router.route("/ag-ui/manifest")
  string.contains(manifest_out, "\"protocol\":\"AG-UI-v1\"") |> should.be_true()
}

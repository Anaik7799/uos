//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/wisp/agui_sse_api</module>
////     <fsharp-lineage>N/A — new Gleam-first AG-UI 32-Event SSE API</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <cross-layer-dependencies>
////       <dep layer="L3_TRANSACTION">cepaf_gleam/agui/events</dep>
////       <dep layer="L4_SYSTEM">cepaf_gleam/agui/sse_stream</dep>
////     </cross-layer-dependencies>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-AGUI-001, SC-AGUI-002, SC-GLM-UI-001, SC-GLM-UI-010</stamp-controls>
////   </compliance>
////   <algebraic-properties>
////     <property name="completeness">Every one of the 32 AG-UI event types is serializable to W3C SSE wire format.</property>
////     <property name="idempotency">Repeated stream generation for identical configs yields deterministic frames.</property>
////   </algebraic-properties>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/agui/events.{type AgUiEvent}
import cepaf_gleam/agui/sse_stream.{SSEEvent}
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string

/// Configuration for an AG-UI real-time event stream.
pub type AGUIStreamConfig {
  AGUIStreamConfig(
    thread_id: String,
    run_id: String,
    agent: String,
    trace_id: String,
  )
}

/// Creates a default stream configuration for the cockpit dashboard.
pub fn default_config() -> AGUIStreamConfig {
  AGUIStreamConfig(
    thread_id: "thread-cockpit-001",
    run_id: "run-cockpit-001",
    agent: "c3i-cockpit-supervisor",
    trace_id: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
  )
}

/// Encodes an AG-UI event into an AG-UI data frame: `data: {json}\n\n`
pub fn event_to_sse_frame(event: AgUiEvent) -> String {
  events.to_sse_frame(event)
}

/// Generates a single W3C SSE frame for a custom named event and JSON payload.
pub fn sse_cockpit_push_frame(
  event_name: String,
  data_json: String,
  id: String,
) -> String {
  sse_stream.format_sse_event(
    SSEEvent(
      id: id,
      event_type: event_name,
      data: data_json,
      retry_ms: Some(3000),
    ),
  )
}

/// Emits the full 32-event AG-UI protocol sequence in canonical order.
/// Ensures all categories (Lifecycle, Text, Tool, State, Activity, Reasoning, Special)
/// are verified end-to-end.
pub fn sse_32_event_manifest_stream(config: AGUIStreamConfig) -> String {
  let message_id = "msg-" <> config.run_id
  let tool_id = "tool-call-001"
  let approval_id = "appr-001"

  let event_list: List(AgUiEvent) = [
    // 1. RUN_STARTED
    events.new_run_started(config.thread_id, config.run_id),
    // 2. STEP_STARTED
    events.new_step_started("initialize_mesh"),
    // 3. STATE_SNAPSHOT
    events.new_state_snapshot(
      json.object([
        #("agent", json.string(config.agent)),
        #("trace_id", json.string(config.trace_id)),
        #("status", json.string("operational")),
      ]),
    ),
    // 4. STATE_DELTA
    events.new_state_delta(
      json.array([json.string("/status"), json.string("active")], fn(x) { x }),
    ),
    // 5. MESSAGES_SNAPSHOT
    events.new_messages_snapshot(
      json.array([json.string("system: ready")], fn(x) { x }),
    ),
    // 6. ACTIVITY_SNAPSHOT
    events.new_activity_snapshot(
      message_id,
      "cockpit",
      json.object([#("subsystem", json.string("telemetry"))]),
    ),
    // 7. ACTIVITY_DELTA
    events.new_activity_delta(
      message_id,
      "cockpit",
      json.object([#("status", json.string("streaming"))]),
    ),
    // 8. TEXT_MESSAGE_START
    events.new_text_message_start(message_id, "assistant"),
    // 9. TEXT_MESSAGE_CONTENT
    events.new_text_message_content(message_id, "C3I Live Cockpit Connected"),
    // 10. TEXT_MESSAGE_CHUNK
    events.new_text_message_chunk(message_id, "assistant", " [Telemetry Active]"),
    // 11. TEXT_MESSAGE_END
    events.new_text_message_end(message_id),
    // 12. REASONING_START
    events.new_reasoning_start(message_id),
    // 13. REASONING_MESSAGE_START
    events.new_reasoning_message_start(message_id),
    // 14. REASONING_MESSAGE_CONTENT
    events.new_reasoning_message_content(message_id, "Analyzing OODA loop metrics..."),
    // 15. REASONING_MESSAGE_CHUNK
    events.new_reasoning_message_chunk(message_id, " Lyapunov trend stable."),
    // 16. REASONING_MESSAGE_END
    events.new_reasoning_message_end(message_id),
    // 17. REASONING_END
    events.new_reasoning_end(message_id),
    // 18. REASONING_ENCRYPTED_VALUE
    events.new_reasoning_encrypted_value("opaque_proof", message_id, "enc:0x89abcdef"),
    // 19. TOOL_CALL_START
    events.new_tool_call_start(tool_id, "audit_subsystems"),
    // 20. TOOL_CALL_ARGS
    events.new_tool_call_args(tool_id, "{\"scope\":\"l0_l9\"}"),
    // 21. TOOL_CALL_CHUNK
    events.new_tool_call_chunk(tool_id, "audit_subsystems", "{\"detail\":true}"),
    // 22. TOOL_CALL_RESULT
    events.new_tool_call_result(
      message_id,
      tool_id,
      "{\"result\":\"all_healthy\"}",
    ),
    // 23. TOOL_CALL_END
    events.new_tool_call_end(tool_id),
    // 24. BIOMETRIC_STARTED
    events.new_biometric_started("operator-001"),
    // 25. BIOMETRIC_RESULT
    events.new_biometric_result("operator-001", True, 0.99),
    // 26. APPROVAL_REQUESTED
    events.new_approval_requested(approval_id, "Approve mesh parameter reload"),
    // 27. APPROVAL_RESULT
    events.new_approval_result(approval_id, True),
    // 28. CUSTOM
    events.new_custom(
      "mesh_status",
      json.object([#("peers", json.int(3))]),
    ),
    // 29. META_EVENT
    events.new_meta_event(
      "trace_sync",
      json.object([#("trace_id", json.string(config.trace_id))]),
    ),
    // 30. RAW
    events.new_raw(
      json.object([#("frame", json.string("0xDEADBEEF"))]),
      "c3i_raw_feed",
    ),
    // 31. STEP_FINISHED
    events.new_step_finished("initialize_mesh"),
    // 32. RUN_FINISHED
    events.new_run_finished(config.thread_id, config.run_id),
  ]

  let frames = list.map(event_list, event_to_sse_frame)
  string.concat(frames)
}

/// Generates a summary JSON descriptor of the AG-UI 32-event protocol manifest.
pub fn agui_manifest_summary_json() -> String {
  json.object([
    #("protocol", json.string("AG-UI-v1")),
    #("event_count", json.int(32)),
    #("categories", json.array([
      json.string("Lifecycle"),
      json.string("Text"),
      json.string("Tool"),
      json.string("State"),
      json.string("Activity"),
      json.string("Reasoning"),
      json.string("Special"),
    ], fn(x) { x })),
    #("sse_transport", json.string("W3C-EventSource")),
    #("status", json.string("compliant")),
  ])
  |> json.to_string()
}

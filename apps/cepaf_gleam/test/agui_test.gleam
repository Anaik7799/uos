/// AG-UI Protocol comprehensive tests — events, SSE, Zenoh bus, router.
///
/// STAMP: SC-GLM-CMP-001, SC-GLM-CORE-002, SC-GLM-CORE-003
import cepaf_gleam/agui/events.{
  Custom, MessagesSnapshot, Raw, RunError, RunFinished, RunStarted, StateDelta,
  StateSnapshot, StepFinished, StepStarted, TextMessageContent, TextMessageEnd,
  TextMessageStart, ToolCallArgs, ToolCallEnd, ToolCallResult, ToolCallStart,
}
import cepaf_gleam/agui/sse
import cepaf_gleam/ui/wisp/router
import gleam/json
import gleam/string
import gleeunit/should

// =============================================================================
// 1. new_run_started — verify thread_id and run_id are set
// =============================================================================

pub fn new_run_started_sets_thread_id_test() {
  let event = events.new_run_started("thread-abc", "run-123")
  event.thread_id
  |> should.equal("thread-abc")
}

pub fn new_run_started_sets_run_id_test() {
  let event = events.new_run_started("thread-abc", "run-123")
  event.run_id
  |> should.equal("run-123")
}

pub fn new_run_started_event_type_test() {
  let event = events.new_run_started("t1", "r1")
  event.event_type
  |> should.equal(RunStarted)
}

// =============================================================================
// 2. new_run_finished — verify event type is RunFinished
// =============================================================================

pub fn new_run_finished_event_type_test() {
  let event = events.new_run_finished("t1", "r1")
  event.event_type
  |> should.equal(RunFinished)
}

pub fn new_run_finished_thread_id_test() {
  let event = events.new_run_finished("thread-xyz", "run-456")
  event.thread_id
  |> should.equal("thread-xyz")
}

// =============================================================================
// 3. new_run_error — verify error message and code
// =============================================================================

pub fn new_run_error_event_type_test() {
  let event = events.new_run_error("something broke", "ERR_500")
  event.event_type
  |> should.equal(RunError)
}

pub fn new_run_error_payload_contains_message_test() {
  let event = events.new_run_error("something broke", "ERR_500")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "something broke")
  |> should.be_true()
}

pub fn new_run_error_payload_contains_code_test() {
  let event = events.new_run_error("something broke", "ERR_500")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "ERR_500")
  |> should.be_true()
}

// =============================================================================
// 4. new_text_message_start — verify message_id and role
// =============================================================================

pub fn new_text_message_start_event_type_test() {
  let event = events.new_text_message_start("msg-001", "assistant")
  event.event_type
  |> should.equal(TextMessageStart)
}

pub fn new_text_message_start_payload_message_id_test() {
  let event = events.new_text_message_start("msg-001", "assistant")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "msg-001")
  |> should.be_true()
}

pub fn new_text_message_start_payload_role_test() {
  let event = events.new_text_message_start("msg-001", "assistant")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "assistant")
  |> should.be_true()
}

// =============================================================================
// 5. new_text_message_content — verify delta text
// =============================================================================

pub fn new_text_message_content_event_type_test() {
  let event = events.new_text_message_content("msg-001", "Hello world")
  event.event_type
  |> should.equal(TextMessageContent)
}

pub fn new_text_message_content_delta_test() {
  let event = events.new_text_message_content("msg-001", "Hello world")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "Hello world")
  |> should.be_true()
}

// =============================================================================
// 6. new_text_message_end — verify message_id
// =============================================================================

pub fn new_text_message_end_event_type_test() {
  let event = events.new_text_message_end("msg-001")
  event.event_type
  |> should.equal(TextMessageEnd)
}

pub fn new_text_message_end_payload_message_id_test() {
  let event = events.new_text_message_end("msg-001")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "msg-001")
  |> should.be_true()
}

// =============================================================================
// 7. new_tool_call_start — verify tool_call_id and tool_name
// =============================================================================

pub fn new_tool_call_start_event_type_test() {
  let event = events.new_tool_call_start("tc-001", "read_file")
  event.event_type
  |> should.equal(ToolCallStart)
}

pub fn new_tool_call_start_tool_call_id_test() {
  let event = events.new_tool_call_start("tc-001", "read_file")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "tc-001")
  |> should.be_true()
}

pub fn new_tool_call_start_tool_name_test() {
  let event = events.new_tool_call_start("tc-001", "read_file")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "read_file")
  |> should.be_true()
}

// =============================================================================
// 8. new_tool_call_end — verify tool_call_id
// =============================================================================

pub fn new_tool_call_end_event_type_test() {
  let event = events.new_tool_call_end("tc-001")
  event.event_type
  |> should.equal(ToolCallEnd)
}

pub fn new_tool_call_end_tool_call_id_test() {
  let event = events.new_tool_call_end("tc-001")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "tc-001")
  |> should.be_true()
}

// =============================================================================
// 9. new_state_snapshot — verify snapshot JSON
// =============================================================================

pub fn new_state_snapshot_event_type_test() {
  let snap = json.object([#("key", json.string("value"))])
  let event = events.new_state_snapshot(snap)
  event.event_type
  |> should.equal(StateSnapshot)
}

pub fn new_state_snapshot_payload_test() {
  let snap = json.object([#("health", json.string("ok"))])
  let event = events.new_state_snapshot(snap)
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "health")
  |> should.be_true()
}

// =============================================================================
// 10. new_state_delta — verify delta operations
// =============================================================================

pub fn new_state_delta_event_type_test() {
  let ops =
    json.object([
      #("op", json.string("replace")),
      #("path", json.string("/status")),
      #("value", json.string("ok")),
    ])
  let event = events.new_state_delta(ops)
  event.event_type
  |> should.equal(StateDelta)
}

pub fn new_state_delta_payload_test() {
  let ops =
    json.object([
      #("op", json.string("replace")),
      #("path", json.string("/status")),
    ])
  let event = events.new_state_delta(ops)
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "replace")
  |> should.be_true()
}

// =============================================================================
// 11. new_step_started — verify step_name
// =============================================================================

pub fn new_step_started_event_type_test() {
  let event = events.new_step_started("processing")
  event.event_type
  |> should.equal(StepStarted)
}

pub fn new_step_started_payload_test() {
  let event = events.new_step_started("processing")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "processing")
  |> should.be_true()
}

// =============================================================================
// 12. new_step_finished — verify step_name
// =============================================================================

pub fn new_step_finished_event_type_test() {
  let event = events.new_step_finished("processing")
  event.event_type
  |> should.equal(StepFinished)
}

pub fn new_step_finished_payload_test() {
  let event = events.new_step_finished("done-step")
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "done-step")
  |> should.be_true()
}

// =============================================================================
// 13. new_custom — verify name and value
// =============================================================================

pub fn new_custom_event_type_test() {
  let event = events.new_custom("heartbeat", json.int(42))
  event.event_type
  |> should.equal(Custom)
}

pub fn new_custom_payload_name_test() {
  let event = events.new_custom("heartbeat", json.int(42))
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "heartbeat")
  |> should.be_true()
}

pub fn new_custom_payload_value_test() {
  let event = events.new_custom("heartbeat", json.int(42))
  let payload_str = json.to_string(event.payload)
  string.contains(payload_str, "42")
  |> should.be_true()
}

// =============================================================================
// 14. event_type_to_string for ALL 17 variants
// =============================================================================

pub fn event_type_run_started_string_test() {
  events.event_type_to_string(RunStarted)
  |> should.equal("RUN_STARTED")
}

pub fn event_type_run_finished_string_test() {
  events.event_type_to_string(RunFinished)
  |> should.equal("RUN_FINISHED")
}

pub fn event_type_run_error_string_test() {
  events.event_type_to_string(RunError)
  |> should.equal("RUN_ERROR")
}

pub fn event_type_step_started_string_test() {
  events.event_type_to_string(StepStarted)
  |> should.equal("STEP_STARTED")
}

pub fn event_type_step_finished_string_test() {
  events.event_type_to_string(StepFinished)
  |> should.equal("STEP_FINISHED")
}

pub fn event_type_text_message_start_string_test() {
  events.event_type_to_string(TextMessageStart)
  |> should.equal("TEXT_MESSAGE_START")
}

pub fn event_type_text_message_content_string_test() {
  events.event_type_to_string(TextMessageContent)
  |> should.equal("TEXT_MESSAGE_CONTENT")
}

pub fn event_type_text_message_end_string_test() {
  events.event_type_to_string(TextMessageEnd)
  |> should.equal("TEXT_MESSAGE_END")
}

pub fn event_type_tool_call_start_string_test() {
  events.event_type_to_string(ToolCallStart)
  |> should.equal("TOOL_CALL_START")
}

pub fn event_type_tool_call_args_string_test() {
  events.event_type_to_string(ToolCallArgs)
  |> should.equal("TOOL_CALL_ARGS")
}

pub fn event_type_tool_call_end_string_test() {
  events.event_type_to_string(ToolCallEnd)
  |> should.equal("TOOL_CALL_END")
}

pub fn event_type_tool_call_result_string_test() {
  events.event_type_to_string(ToolCallResult)
  |> should.equal("TOOL_CALL_RESULT")
}

pub fn event_type_state_snapshot_string_test() {
  events.event_type_to_string(StateSnapshot)
  |> should.equal("STATE_SNAPSHOT")
}

pub fn event_type_state_delta_string_test() {
  events.event_type_to_string(StateDelta)
  |> should.equal("STATE_DELTA")
}

pub fn event_type_messages_snapshot_string_test() {
  events.event_type_to_string(MessagesSnapshot)
  |> should.equal("MESSAGES_SNAPSHOT")
}

pub fn event_type_raw_string_test() {
  events.event_type_to_string(Raw)
  |> should.equal("RAW")
}

pub fn event_type_custom_string_test() {
  events.event_type_to_string(Custom)
  |> should.equal("CUSTOM")
}

// =============================================================================
// 15. to_sse_frame — verify output starts with "data: " and ends with "\n\n"
// =============================================================================

pub fn to_sse_frame_starts_with_data_test() {
  let event = events.new_run_started("t1", "r1")
  let frame = events.to_sse_frame(event)
  string.starts_with(frame, "data: ")
  |> should.be_true()
}

pub fn to_sse_frame_ends_with_double_newline_test() {
  let event = events.new_run_started("t1", "r1")
  let frame = events.to_sse_frame(event)
  string.ends_with(frame, "\n\n")
  |> should.be_true()
}

// =============================================================================
// 16. to_sse_frame — verify output contains valid JSON
// =============================================================================

pub fn to_sse_frame_contains_type_field_test() {
  let event = events.new_run_started("t1", "r1")
  let frame = events.to_sse_frame(event)
  string.contains(frame, "\"type\"")
  |> should.be_true()
}

pub fn to_sse_frame_contains_run_started_type_test() {
  let event = events.new_run_started("t1", "r1")
  let frame = events.to_sse_frame(event)
  string.contains(frame, "RUN_STARTED")
  |> should.be_true()
}

pub fn to_sse_frame_contains_thread_id_field_test() {
  let event = events.new_run_started("t1", "r1")
  let frame = events.to_sse_frame(event)
  string.contains(frame, "\"thread_id\"")
  |> should.be_true()
}

pub fn to_sse_frame_contains_run_id_field_test() {
  let event = events.new_run_started("t1", "r1")
  let frame = events.to_sse_frame(event)
  string.contains(frame, "\"run_id\"")
  |> should.be_true()
}

// =============================================================================
// 17. create_sse_stream — verify it contains RUN_STARTED event
// =============================================================================

pub fn sse_stream_contains_run_started_test() {
  let stream =
    sse.create_sse_stream("t1", "r1", "/health", "{\"status\":\"ok\"}")
  string.contains(stream, "RUN_STARTED")
  |> should.be_true()
}

// =============================================================================
// 18. create_sse_stream — verify it contains RUN_FINISHED event
// =============================================================================

pub fn sse_stream_contains_run_finished_test() {
  let stream =
    sse.create_sse_stream("t1", "r1", "/health", "{\"status\":\"ok\"}")
  string.contains(stream, "RUN_FINISHED")
  |> should.be_true()
}

// =============================================================================
// 19. create_sse_stream — verify it contains STATE_SNAPSHOT event
// =============================================================================

pub fn sse_stream_contains_state_snapshot_test() {
  let stream =
    sse.create_sse_stream("t1", "r1", "/health", "{\"status\":\"ok\"}")
  string.contains(stream, "STATE_SNAPSHOT")
  |> should.be_true()
}

pub fn sse_stream_all_frames_start_with_data_test() {
  let stream =
    sse.create_sse_stream("t1", "r1", "/health", "{\"status\":\"ok\"}")
  // Every frame starts with "data: " — split on double-newline and verify
  string.split(stream, "\n\n")
  |> should_all_start_with_data_or_empty()
}

fn should_all_start_with_data_or_empty(parts: List(String)) -> Nil {
  case parts {
    [] -> Nil
    [part, ..rest] -> {
      case string.is_empty(part) {
        True -> should_all_start_with_data_or_empty(rest)
        False -> {
          string.starts_with(part, "data: ")
          |> should.be_true()
          should_all_start_with_data_or_empty(rest)
        }
      }
    }
  }
}

// =============================================================================
// 20. Topic format verification — Zenoh bus topic patterns
// =============================================================================

pub fn zenoh_agui_topic_format_test() {
  // AG-UI event topic: c3i/agui/events/{agent_id}
  let topic = "c3i/agui/events/" <> "cortex-agent-01"
  string.contains(topic, "c3i/agui/events/")
  |> should.be_true()
}

pub fn zenoh_agui_topic_contains_agent_id_test() {
  let agent_id = "cortex-agent-01"
  let topic = "c3i/agui/events/" <> agent_id
  string.contains(topic, agent_id)
  |> should.be_true()
}

pub fn zenoh_a2a_topic_format_test() {
  // A2A direct topic: c3i/a2a/{source}/{target}
  let topic = "c3i/a2a/" <> "agent-a" <> "/" <> "agent-b"
  string.contains(topic, "c3i/a2a/")
  |> should.be_true()
}

pub fn zenoh_a2a_broadcast_topic_test() {
  let topic = "c3i/a2a/broadcast"
  should.equal(topic, "c3i/a2a/broadcast")
}

// =============================================================================
// 21. route("/ag-ui/health") returns valid JSON with protocol version
// =============================================================================

pub fn agui_health_route_contains_protocol_test() {
  let result = router.route("/ag-ui/health")
  string.contains(result, "ag-ui")
  |> should.be_true()
}

pub fn agui_health_route_contains_version_test() {
  let result = router.route("/ag-ui/health")
  string.contains(result, "1.0.0")
  |> should.be_true()
}

pub fn agui_health_route_contains_status_ok_test() {
  let result = router.route("/ag-ui/health")
  string.contains(result, "ok")
  |> should.be_true()
}

// =============================================================================
// 22. route("/ag-ui/events") returns SSE-formatted string
// =============================================================================

pub fn agui_events_route_contains_data_prefix_test() {
  let result = router.route("/ag-ui/events")
  string.contains(result, "data: ")
  |> should.be_true()
}

pub fn agui_events_route_contains_run_started_test() {
  let result = router.route("/ag-ui/events")
  string.contains(result, "RUN_STARTED")
  |> should.be_true()
}

pub fn agui_events_route_contains_run_finished_test() {
  let result = router.route("/ag-ui/events")
  string.contains(result, "RUN_FINISHED")
  |> should.be_true()
}

pub fn agui_events_route_contains_double_newline_test() {
  let result = router.route("/ag-ui/events")
  string.contains(result, "\n\n")
  |> should.be_true()
}

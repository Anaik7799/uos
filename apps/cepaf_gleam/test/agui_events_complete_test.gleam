/// AG-UI event constructor and serialization tests — full coverage of all 28 event types.
///
/// STAMP: SC-AGUI-001, SC-GLM-CMP-001, SC-GLM-CORE-002
import cepaf_gleam/agui/events.{
  ActivityDelta, ActivitySnapshot, Custom, MessagesSnapshot, MetaEvent, Raw,
  ReasoningEncryptedValue, ReasoningEnd, ReasoningMessageChunk,
  ReasoningMessageContent, ReasoningMessageEnd, ReasoningMessageStart,
  ReasoningStart, RunError, RunFinished, RunStarted, StateDelta, StateSnapshot,
  StepFinished, StepStarted, TextMessageChunk, TextMessageContent,
  TextMessageEnd, TextMessageStart, ToolCallArgs, ToolCallChunk, ToolCallEnd,
  ToolCallResult, ToolCallStart,
}
import gleam/json
import gleam/string
import gleeunit/should

// =============================================================================
// Lifecycle events
// =============================================================================

pub fn run_started_creates_valid_event_test() {
  let e = events.new_run_started("thread-1", "run-1")
  e.event_type |> should.equal(RunStarted)
  e.thread_id |> should.equal("thread-1")
  e.run_id |> should.equal("run-1")
}

pub fn run_finished_creates_valid_event_test() {
  let e = events.new_run_finished("t", "r")
  e.event_type |> should.equal(RunFinished)
}

pub fn run_finished_preserves_thread_id_test() {
  let e = events.new_run_finished("thread-fin", "run-fin")
  e.thread_id |> should.equal("thread-fin")
}

pub fn run_error_creates_valid_event_test() {
  let e = events.new_run_error("timeout", "E001")
  e.event_type |> should.equal(RunError)
}

pub fn run_error_payload_contains_message_test() {
  let e = events.new_run_error("timeout error", "E001")
  let s = json.to_string(e.payload)
  string.contains(s, "timeout error") |> should.be_true()
}

pub fn run_error_payload_contains_code_test() {
  let e = events.new_run_error("timeout", "E999")
  let s = json.to_string(e.payload)
  string.contains(s, "E999") |> should.be_true()
}

pub fn step_started_creates_valid_event_test() {
  let e = events.new_step_started("processing")
  e.event_type |> should.equal(StepStarted)
}

pub fn step_started_payload_contains_step_name_test() {
  let e = events.new_step_started("boot-sequence")
  let s = json.to_string(e.payload)
  string.contains(s, "boot-sequence") |> should.be_true()
}

pub fn step_finished_creates_valid_event_test() {
  let e = events.new_step_finished("processing")
  e.event_type |> should.equal(StepFinished)
}

pub fn step_finished_payload_contains_step_name_test() {
  let e = events.new_step_finished("teardown")
  let s = json.to_string(e.payload)
  string.contains(s, "teardown") |> should.be_true()
}

// =============================================================================
// Text message events
// =============================================================================

pub fn text_message_start_event_type_test() {
  let e = events.new_text_message_start("msg-1", "assistant")
  e.event_type |> should.equal(TextMessageStart)
}

pub fn text_message_start_payload_contains_message_id_test() {
  let e = events.new_text_message_start("msg-42", "assistant")
  let s = json.to_string(e.payload)
  string.contains(s, "msg-42") |> should.be_true()
}

pub fn text_message_start_payload_contains_role_test() {
  let e = events.new_text_message_start("msg-1", "user")
  let s = json.to_string(e.payload)
  string.contains(s, "user") |> should.be_true()
}

pub fn text_message_content_event_type_test() {
  let e = events.new_text_message_content("msg-1", "hello")
  e.event_type |> should.equal(TextMessageContent)
}

pub fn text_message_content_payload_contains_delta_test() {
  let e = events.new_text_message_content("msg-1", "hello world")
  let s = json.to_string(e.payload)
  string.contains(s, "hello world") |> should.be_true()
}

pub fn text_message_end_event_type_test() {
  let e = events.new_text_message_end("msg-1")
  e.event_type |> should.equal(TextMessageEnd)
}

pub fn text_message_end_payload_contains_message_id_test() {
  let e = events.new_text_message_end("msg-end-99")
  let s = json.to_string(e.payload)
  string.contains(s, "msg-end-99") |> should.be_true()
}

pub fn text_message_chunk_event_type_test() {
  let e = events.new_text_message_chunk("msg-1", "assistant", "hello world")
  e.event_type |> should.equal(TextMessageChunk)
}

pub fn text_message_chunk_payload_contains_role_test() {
  let e = events.new_text_message_chunk("msg-1", "assistant", "chunk")
  let s = json.to_string(e.payload)
  string.contains(s, "assistant") |> should.be_true()
}

pub fn text_message_chunk_payload_contains_delta_test() {
  let e = events.new_text_message_chunk("msg-1", "assistant", "delta-text")
  let s = json.to_string(e.payload)
  string.contains(s, "delta-text") |> should.be_true()
}

// =============================================================================
// Tool call events
// =============================================================================

pub fn tool_call_start_event_type_test() {
  let e = events.new_tool_call_start("tc-1", "search")
  e.event_type |> should.equal(ToolCallStart)
}

pub fn tool_call_start_payload_contains_tool_call_id_test() {
  let e = events.new_tool_call_start("tc-007", "read_file")
  let s = json.to_string(e.payload)
  string.contains(s, "tc-007") |> should.be_true()
}

pub fn tool_call_start_payload_contains_tool_name_test() {
  let e = events.new_tool_call_start("tc-1", "sentinel_check")
  let s = json.to_string(e.payload)
  string.contains(s, "sentinel_check") |> should.be_true()
}

pub fn tool_call_args_event_type_test() {
  let e = events.new_tool_call_args("tc-1", "{\"query\":\"test\"}")
  e.event_type |> should.equal(ToolCallArgs)
}

pub fn tool_call_args_payload_contains_delta_test() {
  let e = events.new_tool_call_args("tc-1", "{\"q\":\"alarm\"}")
  let s = json.to_string(e.payload)
  string.contains(s, "alarm") |> should.be_true()
}

pub fn tool_call_end_event_type_test() {
  let e = events.new_tool_call_end("tc-1")
  e.event_type |> should.equal(ToolCallEnd)
}

pub fn tool_call_end_payload_contains_tool_call_id_test() {
  let e = events.new_tool_call_end("tc-end-5")
  let s = json.to_string(e.payload)
  string.contains(s, "tc-end-5") |> should.be_true()
}

pub fn tool_call_result_event_type_test() {
  let e = events.new_tool_call_result("msg-1", "tc-1", "found 3 results")
  e.event_type |> should.equal(ToolCallResult)
}

pub fn tool_call_result_payload_contains_content_test() {
  let e = events.new_tool_call_result("msg-1", "tc-1", "found 3 results")
  let s = json.to_string(e.payload)
  string.contains(s, "found 3 results") |> should.be_true()
}

pub fn tool_call_chunk_event_type_test() {
  let e = events.new_tool_call_chunk("tc-1", "search", "{\"q\":\"x\"}")
  e.event_type |> should.equal(ToolCallChunk)
}

pub fn tool_call_chunk_payload_contains_tool_name_test() {
  let e = events.new_tool_call_chunk("tc-1", "guardian_approve", "{}")
  let s = json.to_string(e.payload)
  string.contains(s, "guardian_approve") |> should.be_true()
}

// =============================================================================
// State events
// =============================================================================

pub fn state_snapshot_event_type_test() {
  let e =
    events.new_state_snapshot(json.object([#("health", json.string("ok"))]))
  e.event_type |> should.equal(StateSnapshot)
}

pub fn state_snapshot_payload_carries_data_test() {
  let e =
    events.new_state_snapshot(
      json.object([#("status", json.string("running"))]),
    )
  let s = json.to_string(e.payload)
  string.contains(s, "running") |> should.be_true()
}

pub fn state_delta_event_type_test() {
  let e = events.new_state_delta(json.array([], fn(x) { x }))
  e.event_type |> should.equal(StateDelta)
}

pub fn messages_snapshot_event_type_test() {
  let e = events.new_messages_snapshot(json.array([], fn(x) { x }))
  e.event_type |> should.equal(MessagesSnapshot)
}

// =============================================================================
// Activity events
// =============================================================================

pub fn activity_snapshot_event_type_test() {
  let e =
    events.new_activity_snapshot("msg-1", "thinking", json.string("analyzing"))
  e.event_type |> should.equal(ActivitySnapshot)
}

pub fn activity_snapshot_payload_contains_activity_type_test() {
  let e =
    events.new_activity_snapshot("msg-1", "reasoning", json.string("content"))
  let s = json.to_string(e.payload)
  string.contains(s, "reasoning") |> should.be_true()
}

pub fn activity_delta_event_type_test() {
  let e =
    events.new_activity_delta("msg-1", "thinking", json.array([], fn(x) { x }))
  e.event_type |> should.equal(ActivityDelta)
}

pub fn activity_delta_payload_contains_message_id_test() {
  let e =
    events.new_activity_delta(
      "msg-delta-7",
      "search",
      json.array([], fn(x) { x }),
    )
  let s = json.to_string(e.payload)
  string.contains(s, "msg-delta-7") |> should.be_true()
}

// =============================================================================
// Reasoning events
// =============================================================================

pub fn reasoning_start_event_type_test() {
  let e = events.new_reasoning_start("msg-1")
  e.event_type |> should.equal(ReasoningStart)
}

pub fn reasoning_message_start_event_type_test() {
  let e = events.new_reasoning_message_start("msg-1")
  e.event_type |> should.equal(ReasoningMessageStart)
}

pub fn reasoning_message_content_event_type_test() {
  let e = events.new_reasoning_message_content("msg-1", "thinking about safety")
  e.event_type |> should.equal(ReasoningMessageContent)
}

pub fn reasoning_message_content_payload_contains_delta_test() {
  let e = events.new_reasoning_message_content("msg-1", "sil6-analysis")
  let s = json.to_string(e.payload)
  string.contains(s, "sil6-analysis") |> should.be_true()
}

pub fn reasoning_message_end_event_type_test() {
  let e = events.new_reasoning_message_end("msg-1")
  e.event_type |> should.equal(ReasoningMessageEnd)
}

pub fn reasoning_message_chunk_event_type_test() {
  let e = events.new_reasoning_message_chunk("msg-1", "chunk data")
  e.event_type |> should.equal(ReasoningMessageChunk)
}

pub fn reasoning_message_chunk_payload_contains_delta_test() {
  let e = events.new_reasoning_message_chunk("msg-1", "streamed-fragment")
  let s = json.to_string(e.payload)
  string.contains(s, "streamed-fragment") |> should.be_true()
}

pub fn reasoning_end_event_type_test() {
  let e = events.new_reasoning_end("msg-1")
  e.event_type |> should.equal(ReasoningEnd)
}

pub fn reasoning_end_payload_contains_message_id_test() {
  let e = events.new_reasoning_end("msg-reason-end")
  let s = json.to_string(e.payload)
  string.contains(s, "msg-reason-end") |> should.be_true()
}

pub fn reasoning_encrypted_value_event_type_test() {
  let e =
    events.new_reasoning_encrypted_value("message", "ent-1", "encrypted-data")
  e.event_type |> should.equal(ReasoningEncryptedValue)
}

pub fn reasoning_encrypted_value_payload_contains_entity_id_test() {
  let e = events.new_reasoning_encrypted_value("message", "entity-xyz", "blob")
  let s = json.to_string(e.payload)
  string.contains(s, "entity-xyz") |> should.be_true()
}

// =============================================================================
// Special events
// =============================================================================

pub fn meta_event_type_test() {
  let e = events.new_meta_event("annotation", json.string("note"))
  e.event_type |> should.equal(MetaEvent)
}

pub fn meta_event_payload_contains_meta_type_test() {
  let e = events.new_meta_event("copyright", json.string("2026"))
  let s = json.to_string(e.payload)
  string.contains(s, "copyright") |> should.be_true()
}

pub fn raw_event_type_test() {
  let e = events.new_raw(json.string("external"), "zenoh")
  e.event_type |> should.equal(Raw)
}

pub fn raw_event_payload_contains_source_test() {
  let e = events.new_raw(json.object([]), "zenoh-mesh")
  let s = json.to_string(e.payload)
  string.contains(s, "zenoh-mesh") |> should.be_true()
}

pub fn custom_event_type_test() {
  let e = events.new_custom("circuit_breaker", json.string("opened"))
  e.event_type |> should.equal(Custom)
}

pub fn custom_event_payload_contains_name_test() {
  let e = events.new_custom("watchdog_alert", json.int(1))
  let s = json.to_string(e.payload)
  string.contains(s, "watchdog_alert") |> should.be_true()
}

// =============================================================================
// SSE serialization
// =============================================================================

pub fn to_sse_frame_starts_with_data_prefix_test() {
  let e = events.new_run_started("t", "r")
  let frame = events.to_sse_frame(e)
  string.starts_with(frame, "data: ") |> should.be_true()
}

pub fn to_sse_frame_ends_with_double_newline_test() {
  let e = events.new_run_started("t", "r")
  let frame = events.to_sse_frame(e)
  string.ends_with(frame, "\n\n") |> should.be_true()
}

pub fn to_json_contains_type_field_test() {
  let e = events.new_step_started("boot")
  let j = events.to_json(e)
  let s = json.to_string(j)
  string.contains(s, "STEP_STARTED") |> should.be_true()
}

pub fn to_json_contains_timestamp_field_test() {
  let e = events.new_step_started("boot")
  let j = events.to_json(e)
  let s = json.to_string(j)
  string.contains(s, "timestamp") |> should.be_true()
}

pub fn to_json_contains_thread_id_field_test() {
  let e = events.new_run_started("t-json", "r-json")
  let j = events.to_json(e)
  let s = json.to_string(j)
  string.contains(s, "thread_id") |> should.be_true()
}

pub fn to_json_contains_run_id_field_test() {
  let e = events.new_run_started("t", "r")
  let j = events.to_json(e)
  let s = json.to_string(j)
  string.contains(s, "run_id") |> should.be_true()
}

// =============================================================================
// Timestamp validation
// =============================================================================

pub fn events_have_positive_timestamps_test() {
  let e = events.new_run_started("t", "r")
  { e.timestamp > 0 } |> should.be_true()
}

pub fn tool_call_events_have_positive_timestamps_test() {
  let e = events.new_tool_call_start("tc-1", "search")
  { e.timestamp > 0 } |> should.be_true()
}

pub fn reasoning_events_have_positive_timestamps_test() {
  let e = events.new_reasoning_start("msg-1")
  { e.timestamp > 0 } |> should.be_true()
}

// =============================================================================
// event_type_to_string — remaining types not in agui_test.gleam
// =============================================================================

pub fn event_type_text_message_chunk_string_test() {
  events.event_type_to_string(TextMessageChunk)
  |> should.equal("TEXT_MESSAGE_CHUNK")
}

pub fn event_type_tool_call_chunk_string_test() {
  events.event_type_to_string(ToolCallChunk) |> should.equal("TOOL_CALL_CHUNK")
}

pub fn event_type_activity_snapshot_string_test() {
  events.event_type_to_string(ActivitySnapshot)
  |> should.equal("ACTIVITY_SNAPSHOT")
}

pub fn event_type_activity_delta_string_test() {
  events.event_type_to_string(ActivityDelta) |> should.equal("ACTIVITY_DELTA")
}

pub fn event_type_reasoning_start_string_test() {
  events.event_type_to_string(ReasoningStart) |> should.equal("REASONING_START")
}

pub fn event_type_reasoning_message_start_string_test() {
  events.event_type_to_string(ReasoningMessageStart)
  |> should.equal("REASONING_MESSAGE_START")
}

pub fn event_type_reasoning_message_content_string_test() {
  events.event_type_to_string(ReasoningMessageContent)
  |> should.equal("REASONING_MESSAGE_CONTENT")
}

pub fn event_type_reasoning_message_end_string_test() {
  events.event_type_to_string(ReasoningMessageEnd)
  |> should.equal("REASONING_MESSAGE_END")
}

pub fn event_type_reasoning_message_chunk_string_test() {
  events.event_type_to_string(ReasoningMessageChunk)
  |> should.equal("REASONING_MESSAGE_CHUNK")
}

pub fn event_type_reasoning_end_string_test() {
  events.event_type_to_string(ReasoningEnd) |> should.equal("REASONING_END")
}

pub fn event_type_reasoning_encrypted_value_string_test() {
  events.event_type_to_string(ReasoningEncryptedValue)
  |> should.equal("REASONING_ENCRYPTED_VALUE")
}

pub fn event_type_meta_event_string_test() {
  events.event_type_to_string(MetaEvent) |> should.equal("META_EVENT")
}

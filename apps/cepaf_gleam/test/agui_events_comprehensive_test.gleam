/// Comprehensive AG-UI 32-event protocol tests.
/// Covers all 32 EventType constructors (including the 4 extended types:
/// BiometricStarted, BiometricResult, ApprovalRequested, ApprovalResult),
/// SSE serialization, event_type_to_string exhaustive mapping,
/// state RFC 6902 patch pipeline, and tool lifecycle state machine.
///
/// STAMP: SC-AGUI-001, SC-AGUI-003, SC-AGUI-004, SC-GLM-CORE-002
import cepaf_gleam/agui/events.{
  ActivityDelta, ActivitySnapshot, ApprovalRequested, ApprovalResult,
  BiometricResult, BiometricStarted, Custom, MessagesSnapshot, MetaEvent, Raw,
  ReasoningEncryptedValue, ReasoningEnd, ReasoningMessageChunk,
  ReasoningMessageContent, ReasoningMessageEnd, ReasoningMessageStart,
  ReasoningStart, RunError, RunFinished, RunStarted, StateDelta, StateSnapshot,
  StepFinished, StepStarted, TextMessageChunk, TextMessageContent,
  TextMessageEnd, TextMessageStart, ToolCallArgs, ToolCallChunk, ToolCallEnd,
  ToolCallResult, ToolCallStart,
}
import cepaf_gleam/agui/state
import cepaf_gleam/agui/tools
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit/should

// =============================================================================
// §1 Lifecycle — 5 events
// =============================================================================

pub fn lifecycle_run_started_event_type_test() {
  let e = events.new_run_started("t1", "r1")
  e.event_type |> should.equal(RunStarted)
}

pub fn lifecycle_run_started_ids_roundtrip_test() {
  let e = events.new_run_started("thread-abc", "run-xyz")
  e.thread_id |> should.equal("thread-abc")
  e.run_id |> should.equal("run-xyz")
}

pub fn lifecycle_run_finished_event_type_test() {
  let e = events.new_run_finished("t2", "r2")
  e.event_type |> should.equal(RunFinished)
}

pub fn lifecycle_run_finished_ids_roundtrip_test() {
  let e = events.new_run_finished("thread-fin", "run-fin")
  e.thread_id |> should.equal("thread-fin")
  e.run_id |> should.equal("run-fin")
}

pub fn lifecycle_run_error_event_type_test() {
  let e = events.new_run_error("fail", "E001")
  e.event_type |> should.equal(RunError)
}

pub fn lifecycle_run_error_payload_has_message_test() {
  let e = events.new_run_error("timeout error", "E001")
  json.to_string(e.payload)
  |> string.contains("timeout error")
  |> should.be_true()
}

pub fn lifecycle_run_error_payload_has_code_test() {
  let e = events.new_run_error("fail", "E404")
  json.to_string(e.payload) |> string.contains("E404") |> should.be_true()
}

pub fn lifecycle_step_started_event_type_test() {
  let e = events.new_step_started("observe")
  e.event_type |> should.equal(StepStarted)
}

pub fn lifecycle_step_started_payload_has_name_test() {
  let e = events.new_step_started("orient-phase")
  json.to_string(e.payload)
  |> string.contains("orient-phase")
  |> should.be_true()
}

pub fn lifecycle_step_finished_event_type_test() {
  let e = events.new_step_finished("decide")
  e.event_type |> should.equal(StepFinished)
}

pub fn lifecycle_step_finished_payload_has_name_test() {
  let e = events.new_step_finished("act-complete")
  json.to_string(e.payload)
  |> string.contains("act-complete")
  |> should.be_true()
}

// =============================================================================
// §2 Text — 4 events
// =============================================================================

pub fn text_message_start_event_type_test() {
  let e = events.new_text_message_start("msg-1", "assistant")
  e.event_type |> should.equal(TextMessageStart)
}

pub fn text_message_start_payload_has_role_test() {
  let e = events.new_text_message_start("msg-1", "user")
  json.to_string(e.payload) |> string.contains("user") |> should.be_true()
}

pub fn text_message_start_payload_has_message_id_test() {
  let e = events.new_text_message_start("msg-42", "assistant")
  json.to_string(e.payload) |> string.contains("msg-42") |> should.be_true()
}

pub fn text_message_content_event_type_test() {
  let e = events.new_text_message_content("msg-1", "Hello")
  e.event_type |> should.equal(TextMessageContent)
}

pub fn text_message_content_payload_has_delta_test() {
  let e = events.new_text_message_content("msg-1", "streaming delta")
  json.to_string(e.payload)
  |> string.contains("streaming delta")
  |> should.be_true()
}

pub fn text_message_end_event_type_test() {
  let e = events.new_text_message_end("msg-1")
  e.event_type |> should.equal(TextMessageEnd)
}

pub fn text_message_end_payload_has_message_id_test() {
  let e = events.new_text_message_end("end-msg-99")
  json.to_string(e.payload) |> string.contains("end-msg-99") |> should.be_true()
}

pub fn text_message_chunk_event_type_test() {
  let e = events.new_text_message_chunk("msg-1", "assistant", "partial")
  e.event_type |> should.equal(TextMessageChunk)
}

pub fn text_message_chunk_payload_has_all_fields_test() {
  let e = events.new_text_message_chunk("msg-ch", "user", "chunk text")
  let s = json.to_string(e.payload)
  s |> string.contains("msg-ch") |> should.be_true()
  s |> string.contains("user") |> should.be_true()
  s |> string.contains("chunk text") |> should.be_true()
}

// =============================================================================
// §3 Tool — 5 events
// =============================================================================

pub fn tool_call_start_event_type_test() {
  let e = events.new_tool_call_start("call-1", "plan_status")
  e.event_type |> should.equal(ToolCallStart)
}

pub fn tool_call_start_payload_has_tool_name_test() {
  let e = events.new_tool_call_start("call-abc", "system_health")
  json.to_string(e.payload)
  |> string.contains("system_health")
  |> should.be_true()
}

pub fn tool_call_start_payload_has_call_id_test() {
  let e = events.new_tool_call_start("call-xyz", "plan_list")
  json.to_string(e.payload) |> string.contains("call-xyz") |> should.be_true()
}

pub fn tool_call_args_event_type_test() {
  let e = events.new_tool_call_args("call-1", "{\"q\":\"test\"}")
  e.event_type |> should.equal(ToolCallArgs)
}

pub fn tool_call_args_payload_has_delta_test() {
  let e = events.new_tool_call_args("call-2", "partial-args")
  json.to_string(e.payload)
  |> string.contains("partial-args")
  |> should.be_true()
}

pub fn tool_call_end_event_type_test() {
  let e = events.new_tool_call_end("call-1")
  e.event_type |> should.equal(ToolCallEnd)
}

pub fn tool_call_end_payload_has_call_id_test() {
  let e = events.new_tool_call_end("call-end-77")
  json.to_string(e.payload)
  |> string.contains("call-end-77")
  |> should.be_true()
}

pub fn tool_call_result_event_type_test() {
  let e = events.new_tool_call_result("msg-1", "call-1", "{\"status\":\"ok\"}")
  e.event_type |> should.equal(ToolCallResult)
}

pub fn tool_call_result_payload_has_all_fields_test() {
  let e = events.new_tool_call_result("msg-r", "call-r", "result content")
  let s = json.to_string(e.payload)
  s |> string.contains("msg-r") |> should.be_true()
  s |> string.contains("call-r") |> should.be_true()
  s |> string.contains("result content") |> should.be_true()
}

pub fn tool_call_chunk_event_type_test() {
  let e = events.new_tool_call_chunk("call-1", "plan_search", "arg-delta")
  e.event_type |> should.equal(ToolCallChunk)
}

pub fn tool_call_chunk_payload_has_all_fields_test() {
  let e = events.new_tool_call_chunk("call-ck", "my_tool", "ck-delta")
  let s = json.to_string(e.payload)
  s |> string.contains("call-ck") |> should.be_true()
  s |> string.contains("my_tool") |> should.be_true()
  s |> string.contains("ck-delta") |> should.be_true()
}

// =============================================================================
// §4 State — 3 events
// =============================================================================

pub fn state_snapshot_event_type_test() {
  let e = events.new_state_snapshot(json.object([#("k", json.string("v"))]))
  e.event_type |> should.equal(StateSnapshot)
}

pub fn state_snapshot_payload_passes_through_test() {
  let payload = json.object([#("health", json.string("nominal"))])
  let e = events.new_state_snapshot(payload)
  json.to_string(e.payload) |> string.contains("nominal") |> should.be_true()
}

pub fn state_delta_event_type_test() {
  let e =
    events.new_state_delta(
      json.array([json.object([#("op", json.string("add"))])], fn(x) { x }),
    )
  e.event_type |> should.equal(StateDelta)
}

pub fn messages_snapshot_event_type_test() {
  let e = events.new_messages_snapshot(json.array([], fn(x) { x }))
  e.event_type |> should.equal(MessagesSnapshot)
}

// =============================================================================
// §5 Activity — 2 events
// =============================================================================

pub fn activity_snapshot_event_type_test() {
  let e =
    events.new_activity_snapshot(
      "msg-1",
      "thinking",
      json.object([#("step", json.string("1"))]),
    )
  e.event_type |> should.equal(ActivitySnapshot)
}

pub fn activity_snapshot_payload_has_type_test() {
  let e = events.new_activity_snapshot("m", "searching", json.object([]))
  json.to_string(e.payload)
  |> string.contains("searching")
  |> should.be_true()
}

pub fn activity_delta_event_type_test() {
  let e = events.new_activity_delta("msg-1", "thinking", json.object([]))
  e.event_type |> should.equal(ActivityDelta)
}

pub fn activity_delta_payload_has_message_id_test() {
  let e = events.new_activity_delta("msg-delta-7", "searching", json.object([]))
  json.to_string(e.payload)
  |> string.contains("msg-delta-7")
  |> should.be_true()
}

// =============================================================================
// §6 Reasoning — 7 events
// =============================================================================

pub fn reasoning_start_event_type_test() {
  let e = events.new_reasoning_start("msg-1")
  e.event_type |> should.equal(ReasoningStart)
}

pub fn reasoning_start_payload_has_message_id_test() {
  let e = events.new_reasoning_start("rs-msg-99")
  json.to_string(e.payload) |> string.contains("rs-msg-99") |> should.be_true()
}

pub fn reasoning_message_start_event_type_test() {
  let e = events.new_reasoning_message_start("msg-1")
  e.event_type |> should.equal(ReasoningMessageStart)
}

pub fn reasoning_message_content_event_type_test() {
  let e = events.new_reasoning_message_content("msg-1", "thinking step 1")
  e.event_type |> should.equal(ReasoningMessageContent)
}

pub fn reasoning_message_content_payload_has_delta_test() {
  let e = events.new_reasoning_message_content("msg-rmc", "think deeply")
  json.to_string(e.payload)
  |> string.contains("think deeply")
  |> should.be_true()
}

pub fn reasoning_message_end_event_type_test() {
  let e = events.new_reasoning_message_end("msg-1")
  e.event_type |> should.equal(ReasoningMessageEnd)
}

pub fn reasoning_message_chunk_event_type_test() {
  let e = events.new_reasoning_message_chunk("msg-1", "partial reasoning")
  e.event_type |> should.equal(ReasoningMessageChunk)
}

pub fn reasoning_message_chunk_payload_has_delta_test() {
  let e = events.new_reasoning_message_chunk("msg-rmch", "chunk reason")
  json.to_string(e.payload)
  |> string.contains("chunk reason")
  |> should.be_true()
}

pub fn reasoning_end_event_type_test() {
  let e = events.new_reasoning_end("msg-1")
  e.event_type |> should.equal(ReasoningEnd)
}

pub fn reasoning_encrypted_value_event_type_test() {
  let e =
    events.new_reasoning_encrypted_value("reasoning", "entity-1", "enc-blob")
  e.event_type |> should.equal(ReasoningEncryptedValue)
}

pub fn reasoning_encrypted_value_payload_has_all_fields_test() {
  let e =
    events.new_reasoning_encrypted_value("subtype-x", "eid-42", "blob-data")
  let s = json.to_string(e.payload)
  s |> string.contains("subtype-x") |> should.be_true()
  s |> string.contains("eid-42") |> should.be_true()
  s |> string.contains("blob-data") |> should.be_true()
}

// =============================================================================
// §7 Special — 4 events (Raw, Custom, MetaEvent, plus Heartbeat via Custom)
// =============================================================================

pub fn raw_event_type_test() {
  let e = events.new_raw(json.object([#("x", json.int(1))]), "zenoh")
  e.event_type |> should.equal(Raw)
}

pub fn raw_payload_has_source_test() {
  let e = events.new_raw(json.null(), "kafka-bridge")
  json.to_string(e.payload)
  |> string.contains("kafka-bridge")
  |> should.be_true()
}

pub fn custom_event_type_test() {
  let e = events.new_custom("heartbeat", json.int(42))
  e.event_type |> should.equal(Custom)
}

pub fn custom_payload_has_name_test() {
  let e = events.new_custom("fitness-check", json.bool(True))
  json.to_string(e.payload)
  |> string.contains("fitness-check")
  |> should.be_true()
}

pub fn meta_event_type_test() {
  let e = events.new_meta_event("protocol_version", json.string("2.0"))
  e.event_type |> should.equal(MetaEvent)
}

pub fn meta_event_payload_has_meta_type_test() {
  let e = events.new_meta_event("schema_update", json.null())
  json.to_string(e.payload)
  |> string.contains("schema_update")
  |> should.be_true()
}

// =============================================================================
// §8 Extended events — BiometricStarted, BiometricResult, ApprovalRequested, ApprovalResult
// =============================================================================

pub fn biometric_started_event_type_test() {
  let e = events.new_biometric_started("user-001")
  e.event_type |> should.equal(BiometricStarted)
}

pub fn biometric_started_payload_has_user_id_test() {
  let e = events.new_biometric_started("abhi-naik")
  json.to_string(e.payload)
  |> string.contains("abhi-naik")
  |> should.be_true()
}

pub fn biometric_result_event_type_test() {
  let e = events.new_biometric_result("user-001", True, 0.98)
  e.event_type |> should.equal(BiometricResult)
}

pub fn biometric_result_payload_has_success_test() {
  let e = events.new_biometric_result("user-42", True, 0.99)
  json.to_string(e.payload)
  |> string.contains("true")
  |> should.be_true()
}

pub fn biometric_result_payload_has_score_test() {
  let e = events.new_biometric_result("user-42", True, 0.95)
  let s = json.to_string(e.payload)
  s |> string.contains("0.95") |> should.be_true()
}

pub fn approval_requested_event_type_test() {
  let e = events.new_approval_requested("appr-1", "Delete container db-prod?")
  e.event_type |> should.equal(ApprovalRequested)
}

pub fn approval_requested_payload_has_description_test() {
  let e =
    events.new_approval_requested(
      "appr-7",
      "Restart zenoh-router in production",
    )
  json.to_string(e.payload)
  |> string.contains("Restart zenoh-router in production")
  |> should.be_true()
}

pub fn approval_requested_payload_has_approval_id_test() {
  let e = events.new_approval_requested("appr-99", "desc")
  json.to_string(e.payload)
  |> string.contains("appr-99")
  |> should.be_true()
}

pub fn approval_result_event_type_test() {
  let e = events.new_approval_result("appr-1", True)
  e.event_type |> should.equal(ApprovalResult)
}

pub fn approval_result_approved_true_test() {
  let e = events.new_approval_result("appr-ok", True)
  json.to_string(e.payload) |> string.contains("true") |> should.be_true()
}

pub fn approval_result_approved_false_test() {
  let e = events.new_approval_result("appr-no", False)
  json.to_string(e.payload) |> string.contains("false") |> should.be_true()
}

// =============================================================================
// §9 event_type_to_string — exhaustive mapping for all 32 types
// =============================================================================

pub fn event_type_string_run_started_test() {
  events.event_type_to_string(RunStarted)
  |> should.equal("RUN_STARTED")
}

pub fn event_type_string_run_finished_test() {
  events.event_type_to_string(RunFinished)
  |> should.equal("RUN_FINISHED")
}

pub fn event_type_string_run_error_test() {
  events.event_type_to_string(RunError) |> should.equal("RUN_ERROR")
}

pub fn event_type_string_step_started_test() {
  events.event_type_to_string(StepStarted) |> should.equal("STEP_STARTED")
}

pub fn event_type_string_step_finished_test() {
  events.event_type_to_string(StepFinished) |> should.equal("STEP_FINISHED")
}

pub fn event_type_string_text_message_start_test() {
  events.event_type_to_string(TextMessageStart)
  |> should.equal("TEXT_MESSAGE_START")
}

pub fn event_type_string_text_message_content_test() {
  events.event_type_to_string(TextMessageContent)
  |> should.equal("TEXT_MESSAGE_CONTENT")
}

pub fn event_type_string_text_message_end_test() {
  events.event_type_to_string(TextMessageEnd)
  |> should.equal("TEXT_MESSAGE_END")
}

pub fn event_type_string_tool_call_start_test() {
  events.event_type_to_string(ToolCallStart)
  |> should.equal("TOOL_CALL_START")
}

pub fn event_type_string_tool_call_args_test() {
  events.event_type_to_string(ToolCallArgs) |> should.equal("TOOL_CALL_ARGS")
}

pub fn event_type_string_tool_call_end_test() {
  events.event_type_to_string(ToolCallEnd) |> should.equal("TOOL_CALL_END")
}

pub fn event_type_string_tool_call_result_test() {
  events.event_type_to_string(ToolCallResult)
  |> should.equal("TOOL_CALL_RESULT")
}

pub fn event_type_string_state_snapshot_test() {
  events.event_type_to_string(StateSnapshot)
  |> should.equal("STATE_SNAPSHOT")
}

pub fn event_type_string_state_delta_test() {
  events.event_type_to_string(StateDelta) |> should.equal("STATE_DELTA")
}

pub fn event_type_string_messages_snapshot_test() {
  events.event_type_to_string(MessagesSnapshot)
  |> should.equal("MESSAGES_SNAPSHOT")
}

pub fn event_type_string_raw_test() {
  events.event_type_to_string(Raw) |> should.equal("RAW")
}

pub fn event_type_string_custom_test() {
  events.event_type_to_string(Custom) |> should.equal("CUSTOM")
}

pub fn event_type_string_text_message_chunk_test() {
  events.event_type_to_string(TextMessageChunk)
  |> should.equal("TEXT_MESSAGE_CHUNK")
}

pub fn event_type_string_tool_call_chunk_test() {
  events.event_type_to_string(ToolCallChunk)
  |> should.equal("TOOL_CALL_CHUNK")
}

pub fn event_type_string_activity_snapshot_test() {
  events.event_type_to_string(ActivitySnapshot)
  |> should.equal("ACTIVITY_SNAPSHOT")
}

pub fn event_type_string_activity_delta_test() {
  events.event_type_to_string(ActivityDelta)
  |> should.equal("ACTIVITY_DELTA")
}

pub fn event_type_string_reasoning_start_test() {
  events.event_type_to_string(ReasoningStart)
  |> should.equal("REASONING_START")
}

pub fn event_type_string_reasoning_message_start_test() {
  events.event_type_to_string(ReasoningMessageStart)
  |> should.equal("REASONING_MESSAGE_START")
}

pub fn event_type_string_reasoning_message_content_test() {
  events.event_type_to_string(ReasoningMessageContent)
  |> should.equal("REASONING_MESSAGE_CONTENT")
}

pub fn event_type_string_reasoning_message_end_test() {
  events.event_type_to_string(ReasoningMessageEnd)
  |> should.equal("REASONING_MESSAGE_END")
}

pub fn event_type_string_reasoning_message_chunk_test() {
  events.event_type_to_string(ReasoningMessageChunk)
  |> should.equal("REASONING_MESSAGE_CHUNK")
}

pub fn event_type_string_reasoning_end_test() {
  events.event_type_to_string(ReasoningEnd) |> should.equal("REASONING_END")
}

pub fn event_type_string_reasoning_encrypted_value_test() {
  events.event_type_to_string(ReasoningEncryptedValue)
  |> should.equal("REASONING_ENCRYPTED_VALUE")
}

pub fn event_type_string_meta_event_test() {
  events.event_type_to_string(MetaEvent) |> should.equal("META_EVENT")
}

pub fn event_type_string_biometric_started_test() {
  events.event_type_to_string(BiometricStarted)
  |> should.equal("BIOMETRIC_STARTED")
}

pub fn event_type_string_biometric_result_test() {
  events.event_type_to_string(BiometricResult)
  |> should.equal("BIOMETRIC_RESULT")
}

pub fn event_type_string_approval_requested_test() {
  events.event_type_to_string(ApprovalRequested)
  |> should.equal("APPROVAL_REQUESTED")
}

pub fn event_type_string_approval_result_test() {
  events.event_type_to_string(ApprovalResult)
  |> should.equal("APPROVAL_RESULT")
}

// =============================================================================
// §10 to_json / to_sse_frame serialization
// =============================================================================

pub fn to_json_contains_type_field_test() {
  let e = events.new_run_started("t", "r")
  json.to_string(events.to_json(e))
  |> string.contains("RUN_STARTED")
  |> should.be_true()
}

pub fn to_json_contains_timestamp_field_test() {
  let e = events.new_run_started("t", "r")
  json.to_string(events.to_json(e))
  |> string.contains("timestamp")
  |> should.be_true()
}

pub fn to_json_contains_thread_id_field_test() {
  let e = events.new_run_started("thread-json", "run-json")
  json.to_string(events.to_json(e))
  |> string.contains("thread-json")
  |> should.be_true()
}

pub fn to_sse_frame_starts_with_data_test() {
  let e = events.new_run_started("t", "r")
  events.to_sse_frame(e) |> string.starts_with("data: ") |> should.be_true()
}

pub fn to_sse_frame_ends_with_double_newline_test() {
  let e = events.new_run_started("t", "r")
  events.to_sse_frame(e) |> string.ends_with("\n\n") |> should.be_true()
}

pub fn to_sse_frame_contains_event_type_test() {
  let e = events.new_step_started("ooda-observe")
  events.to_sse_frame(e)
  |> string.contains("STEP_STARTED")
  |> should.be_true()
}

// =============================================================================
// §11 State — RFC 6902 patch pipeline
// =============================================================================

pub fn state_initial_version_is_zero_test() {
  state.initial_state().version |> should.equal(0)
}

pub fn state_apply_snapshot_increments_version_test() {
  let s0 = state.initial_state()
  let s1 = state.apply_snapshot(s0, json.object([#("k", json.string("v"))]))
  s1.version |> should.equal(1)
}

pub fn state_apply_delta_increments_version_test() {
  let s0 = state.initial_state()
  let ops = [state.new_add("/health", json.string("nominal"))]
  let s1 = state.apply_delta(s0, ops)
  s1.version |> should.equal(1)
}

pub fn state_multiple_deltas_increment_each_test() {
  let s0 = state.initial_state()
  let ops = [state.new_replace("/mode", json.string("bright"))]
  let s1 = state.apply_delta(s0, ops)
  let s2 = state.apply_delta(s1, [state.new_remove("/tmp")])
  s2.version |> should.equal(2)
}

pub fn state_add_op_json_has_op_field_test() {
  let op = state.new_add("/x", json.int(7))
  let j = json.to_string(state.patch_op_to_json(op))
  j |> string.contains("\"add\"") |> should.be_true()
}

pub fn state_replace_op_json_has_op_field_test() {
  let op = state.new_replace("/y", json.bool(True))
  let j = json.to_string(state.patch_op_to_json(op))
  j |> string.contains("\"replace\"") |> should.be_true()
}

pub fn state_remove_op_json_has_op_field_test() {
  let op = state.new_remove("/z")
  let j = json.to_string(state.patch_op_to_json(op))
  j |> string.contains("\"remove\"") |> should.be_true()
}

pub fn state_move_op_json_has_from_field_test() {
  let op = state.new_move("/old", "/new")
  let j = json.to_string(state.patch_op_to_json(op))
  j |> string.contains("/old") |> should.be_true()
  j |> string.contains("/new") |> should.be_true()
}

pub fn state_copy_op_json_has_from_and_path_test() {
  let op = state.new_copy("/src", "/dst")
  let j = json.to_string(state.patch_op_to_json(op))
  j |> string.contains("\"copy\"") |> should.be_true()
}

pub fn state_test_op_json_has_value_test() {
  let op = state.new_test("/count", json.int(42))
  let j = json.to_string(state.patch_op_to_json(op))
  j |> string.contains("\"test\"") |> should.be_true()
  j |> string.contains("42") |> should.be_true()
}

pub fn state_patch_list_to_json_produces_array_test() {
  let ops = [
    state.new_add("/a", json.string("x")),
    state.new_remove("/b"),
  ]
  let j = json.to_string(state.patch_list_to_json(ops))
  j |> string.starts_with("[") |> should.be_true()
}

pub fn state_pointer_key_appends_slash_test() {
  state.pointer_key("", "health") |> should.equal("/health")
}

pub fn state_pointer_key_escapes_tilde_test() {
  state.pointer_key("", "a~b") |> should.equal("/a~0b")
}

pub fn state_pointer_key_escapes_slash_test() {
  state.pointer_key("", "a/b") |> should.equal("/a~1b")
}

pub fn state_pointer_index_produces_correct_path_test() {
  state.pointer_index("/items", 3) |> should.equal("/items/3")
}

pub fn state_add_keys_produces_correct_count_test() {
  let pairs = [
    #("alpha", json.string("1")),
    #("beta", json.string("2")),
    #("gamma", json.string("3")),
  ]
  let ops = state.add_keys(pairs)
  list.length(ops) |> should.equal(3)
}

pub fn state_replace_keys_produces_correct_count_test() {
  let pairs = [#("x", json.int(1)), #("y", json.int(2))]
  let ops = state.replace_keys(pairs)
  list.length(ops) |> should.equal(2)
}

pub fn state_remove_keys_produces_correct_count_test() {
  let ops = state.remove_keys(["a", "b", "c", "d"])
  list.length(ops) |> should.equal(4)
}

pub fn state_snapshot_payload_has_version_test() {
  let s = state.initial_state()
  let payload = state.state_snapshot_payload(s, "t-snap")
  json.to_string(payload) |> string.contains("t-snap") |> should.be_true()
}

pub fn state_delta_payload_has_thread_id_test() {
  let ops = [state.new_add("/k", json.string("v"))]
  let payload = state.state_delta_payload(ops, "t-delta", 5)
  let j = json.to_string(payload)
  j |> string.contains("t-delta") |> should.be_true()
  j |> string.contains("5") |> should.be_true()
}

// =============================================================================
// §12 Tools — lifecycle state machine (ToolRegistry)
// =============================================================================

pub fn tools_initial_registry_has_no_calls_test() {
  let reg = tools.initial_registry()
  tools.active_calls(reg) |> list.length() |> should.equal(0)
}

pub fn tools_initial_registry_has_no_pending_test() {
  let reg = tools.initial_registry()
  tools.pending_approvals(reg) |> should.equal(0)
}

pub fn tools_start_call_adds_to_active_test() {
  let reg = tools.initial_registry()
  let reg2 = tools.start_call(reg, "call-1", "plan_status")
  tools.active_calls(reg2) |> list.length() |> should.equal(1)
}

pub fn tools_append_args_does_not_increase_active_count_test() {
  let reg =
    tools.initial_registry()
    |> tools.start_call("call-1", "plan_list")
  let reg2 = tools.append_args(reg, "call-1", "{\"st")
  tools.active_calls(reg2) |> list.length() |> should.equal(1)
}

pub fn tools_end_args_without_approval_keeps_active_test() {
  let tool =
    tools.ToolDef(
      name: "plan_status",
      description: "desc",
      parameters_schema: json.object([]),
      requires_approval: False,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("call-1", "plan_status")
    |> tools.end_args("call-1")
  tools.active_calls(reg) |> list.length() |> should.equal(1)
}

pub fn tools_end_args_with_approval_adds_to_queue_test() {
  let tool =
    tools.ToolDef(
      name: "emergency_stop",
      description: "L0 action",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("call-l0", "emergency_stop")
    |> tools.end_args("call-l0")
  tools.pending_approvals(reg) |> should.equal(1)
}

pub fn tools_approve_call_removes_from_queue_test() {
  let tool =
    tools.ToolDef(
      name: "emergency_stop",
      description: "L0",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("call-l0", "emergency_stop")
    |> tools.end_args("call-l0")
    |> tools.approve_call("call-l0")
  tools.pending_approvals(reg) |> should.equal(0)
}

pub fn tools_reject_call_removes_from_queue_test() {
  let tool =
    tools.ToolDef(
      name: "hard_restart",
      description: "L0",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("call-hr", "hard_restart")
    |> tools.end_args("call-hr")
    |> tools.reject_call("call-hr", "operator denied")
  tools.pending_approvals(reg) |> should.equal(0)
}

pub fn tools_reject_call_removes_from_active_test() {
  let tool =
    tools.ToolDef(
      name: "hard_restart",
      description: "L0",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("call-rej", "hard_restart")
    |> tools.end_args("call-rej")
    |> tools.reject_call("call-rej", "denied")
  tools.active_calls(reg) |> list.length() |> should.equal(0)
}

pub fn tools_set_result_completes_call_test() {
  let reg =
    tools.initial_registry()
    |> tools.start_call("call-done", "plan_search")
    |> tools.set_result("call-done", "{\"count\":5}")
  tools.active_calls(reg) |> list.length() |> should.equal(0)
}

pub fn tools_pending_call_ids_returns_queue_test() {
  let tool =
    tools.ToolDef(
      name: "op1",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("id-q", "op1")
    |> tools.end_args("id-q")
  let ids = tools.pending_call_ids(reg)
  list.contains(ids, "id-q") |> should.be_true()
}

pub fn tools_pending_calls_to_json_is_valid_json_test() {
  let tool =
    tools.ToolDef(
      name: "op2",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("id-json", "op2")
    |> tools.end_args("id-json")
  let s = tools.pending_calls_to_json(reg)
  s |> string.starts_with("[") |> should.be_true()
  s |> string.contains("id-json") |> should.be_true()
}

pub fn tools_call_state_to_json_has_tool_name_test() {
  let reg =
    tools.initial_registry()
    |> tools.start_call("call-sj", "knowledge_search")
  let calls = tools.active_calls(reg)
  case calls {
    [call, ..] -> {
      let j = json.to_string(tools.call_state_to_json(call))
      j |> string.contains("knowledge_search") |> should.be_true()
    }
    [] -> should.fail()
  }
}

pub fn tools_tool_def_to_json_has_name_test() {
  let tool =
    tools.ToolDef(
      name: "system_health",
      description: "desc",
      parameters_schema: json.object([]),
      requires_approval: False,
    )
  let j = json.to_string(tools.tool_def_to_json(tool))
  j |> string.contains("system_health") |> should.be_true()
}

pub fn tools_tool_def_to_json_requires_approval_false_test() {
  let tool =
    tools.ToolDef(
      name: "safe_op",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: False,
    )
  let j = json.to_string(tools.tool_def_to_json(tool))
  j |> string.contains("false") |> should.be_true()
}

pub fn tools_unknown_call_id_ignored_gracefully_test() {
  let reg = tools.initial_registry()
  // Append to non-existent call — should NOT crash
  let reg2 = tools.append_args(reg, "ghost-id", "data")
  tools.active_calls(reg2) |> list.length() |> should.equal(0)
}

pub fn tools_messages_to_json_produces_array_test() {
  // state.messages_to_json accepts List(ConversationMessage)
  // Build a message and verify the JSON array format
  let msgs = [
    state.ConversationMessage(
      id: "m1",
      role: "user",
      content: "hello world",
      tool_call_id: option.None,
      timestamp: 0,
    ),
  ]
  let j = json.to_string(state.messages_to_json(msgs))
  j |> string.starts_with("[") |> should.be_true()
  j |> string.contains("hello world") |> should.be_true()
}

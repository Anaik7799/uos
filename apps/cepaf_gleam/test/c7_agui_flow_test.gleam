// C7 AG-UI Event Flow Integration Tests
// Category: C7_Performance (weight 2.5) — AG-UI lifecycle sequences
// STAMP: SC-AGUI-001..010, SC-GLM-UI-010

import cepaf_gleam/agui/events.{
  ActivityDelta, ActivitySnapshot, Custom, MessagesSnapshot, MetaEvent, Raw,
  ReasoningEncryptedValue, ReasoningEnd, ReasoningMessageChunk,
  ReasoningMessageContent, ReasoningMessageEnd, ReasoningMessageStart,
  ReasoningStart, RunError, RunFinished, RunStarted, StateDelta, StateSnapshot,
  StepFinished, StepStarted, TextMessageChunk, TextMessageContent,
  TextMessageEnd, TextMessageStart, ToolCallArgs, ToolCallChunk, ToolCallEnd,
  ToolCallResult, ToolCallStart,
}
import cepaf_gleam/agui/tools
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Full Lifecycle Flow Tests
// =============================================================================

pub fn full_lifecycle_run_started_to_finished_test() {
  // RunStarted → StepStarted → ToolCallStart → ToolCallResult → StepFinished → RunFinished
  let e1 = events.new_run_started("t1", "r1")
  let e2 = events.new_step_started("search")
  let e3 = events.new_tool_call_start("tc-1", "read_file")
  let e4 = events.new_tool_call_result("msg-1", "tc-1", "file contents here")
  let e5 = events.new_step_finished("search")
  let e6 = events.new_run_finished("t1", "r1")
  let flow = [e1, e2, e3, e4, e5, e6]
  // Verify event type ordering
  let types = list.map(flow, fn(e) { e.event_type })
  types
  |> should.equal([
    RunStarted, StepStarted, ToolCallStart, ToolCallResult, StepFinished,
    RunFinished,
  ])
}

pub fn reasoning_chain_flow_test() {
  // ReasoningStart → ReasoningMessageStart → Content × 3 → MessageEnd → ReasoningEnd
  let e1 = events.new_reasoning_start("msg-1")
  let e2 = events.new_reasoning_message_start("msg-1")
  let e3 = events.new_reasoning_message_content("msg-1", "Step 1: analyze...")
  let e4 = events.new_reasoning_message_content("msg-1", "Step 2: plan...")
  let e5 = events.new_reasoning_message_content("msg-1", "Step 3: execute...")
  let e6 = events.new_reasoning_message_end("msg-1")
  let e7 = events.new_reasoning_end("msg-1")
  let flow = [e1, e2, e3, e4, e5, e6, e7]
  list.length(flow) |> should.equal(7)
  {
    list.first(flow)
    |> fn(r) {
      case r {
        Ok(e) -> e.event_type == ReasoningStart
        _ -> False
      }
    }
  }
  |> should.be_true()
}

pub fn text_streaming_flow_test() {
  // TextMessageStart → TextMessageContent × N → TextMessageEnd
  let e1 = events.new_text_message_start("m1", "assistant")
  let e2 = events.new_text_message_content("m1", "Hello ")
  let e3 = events.new_text_message_content("m1", "world!")
  let e4 = events.new_text_message_end("m1")
  let types = list.map([e1, e2, e3, e4], fn(e) { e.event_type })
  types
  |> should.equal([
    TextMessageStart, TextMessageContent, TextMessageContent, TextMessageEnd,
  ])
}

pub fn state_snapshot_and_delta_flow_test() {
  let snap = events.new_state_snapshot(json.object([#("count", json.int(0))]))
  let delta =
    events.new_state_delta(
      json.array(
        [
          json.object([
            #("op", json.string("replace")),
            #("path", json.string("/count")),
            #("value", json.int(1)),
          ]),
        ],
        fn(x) { x },
      ),
    )
  snap.event_type |> should.equal(StateSnapshot)
  delta.event_type |> should.equal(StateDelta)
}

// =============================================================================
// HITL Tool Flow Tests
// =============================================================================

pub fn hitl_approval_via_agui_flow_test() {
  // ToolCallStart → args → end → AwaitingApproval → approve → result
  let tool =
    tools.ToolDef(
      name: "deploy",
      description: "Deploy to prod",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg = tools.new_registry([tool])
  let reg = tools.start_call(reg, "tc-1", "deploy")
  let reg = tools.append_args(reg, "tc-1", "{\"target\":\"prod\"}")
  let reg = tools.end_args(reg, "tc-1")
  // Verify HITL gate triggered
  tools.pending_approvals(reg) |> should.equal(1)
  // Approve
  let reg = tools.approve_call(reg, "tc-1")
  let reg = tools.set_result(reg, "tc-1", "deployed")
  case dict.get(reg.calls, "tc-1") {
    Ok(call) -> call.result |> should.equal(Some("deployed"))
    Error(_) -> should.fail()
  }
}

pub fn hitl_rejection_blocks_execution_test() {
  let tool =
    tools.ToolDef(
      name: "delete_all",
      description: "Dangerous",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-2", "delete_all")
    |> tools.end_args("tc-2")
  let reg = tools.reject_call(reg, "tc-2", "Too dangerous")
  case dict.get(reg.calls, "tc-2") {
    Ok(call) ->
      case call.status {
        tools.Failed(r) -> r |> should.equal("Too dangerous")
        _ -> should.fail()
      }
    Error(_) -> should.fail()
  }
}

// =============================================================================
// Activity + Error Recovery Tests
// =============================================================================

pub fn activity_snapshot_delta_sequence_test() {
  let snap =
    events.new_activity_snapshot(
      "act-1",
      "task_tracking",
      json.object([#("tasks", json.int(5))]),
    )
  let delta =
    events.new_activity_delta(
      "act-1",
      "task_tracking",
      json.object([#("tasks", json.int(6))]),
    )
  snap.event_type |> should.equal(ActivitySnapshot)
  delta.event_type |> should.equal(ActivityDelta)
}

pub fn error_recovery_new_run_after_error_test() {
  let e1 = events.new_run_started("t1", "r1")
  let e2 = events.new_run_error("timeout", "E001")
  let e3 = events.new_run_started("t1", "r2")
  e1.event_type |> should.equal(RunStarted)
  e2.event_type |> should.equal(RunError)
  e3.event_type |> should.equal(RunStarted)
}

// =============================================================================
// Event Completeness + SSE Tests
// =============================================================================

pub fn all_32_event_types_have_unique_strings_test() {
  let all_types = [
    RunStarted, RunFinished, RunError, StepStarted, StepFinished,
    TextMessageStart, TextMessageContent, TextMessageEnd, TextMessageChunk,
    ToolCallStart, ToolCallArgs, ToolCallEnd, ToolCallResult, ToolCallChunk,
    StateSnapshot, StateDelta, MessagesSnapshot, ActivitySnapshot, ActivityDelta,
    ReasoningStart, ReasoningMessageStart, ReasoningMessageContent,
    ReasoningMessageEnd, ReasoningMessageChunk, ReasoningEnd,
    ReasoningEncryptedValue, Raw, Custom, MetaEvent,
  ]
  let strings = list.map(all_types, events.event_type_to_string)
  let unique_count = list.unique(strings) |> list.length()
  // 29 unique types (Heartbeat is separate runtime construct)
  unique_count |> should.equal(list.length(all_types))
}

pub fn sse_multi_frame_composition_test() {
  let e1 = events.new_run_started("t1", "r1")
  let e2 = events.new_text_message_start("m1", "assistant")
  let e3 = events.new_text_message_content("m1", "Hello")
  let frames = [
    events.to_sse_frame(e1),
    events.to_sse_frame(e2),
    events.to_sse_frame(e3),
  ]
  // Each frame should be a valid SSE data line
  list.each(frames, fn(f) {
    string.starts_with(f, "data: ") |> should.be_true()
    string.ends_with(f, "\n\n") |> should.be_true()
  })
  // Combined stream should have 3 frames
  list.length(frames) |> should.equal(3)
}

pub fn encrypted_reasoning_payload_structure_test() {
  let e =
    events.new_reasoning_encrypted_value(
      "msg-1",
      "base64cipher==",
      "aes-256-gcm",
    )
  e.event_type |> should.equal(ReasoningEncryptedValue)
  let payload_str = json.to_string(e.payload)
  string.contains(payload_str, "base64cipher==") |> should.be_true()
  string.contains(payload_str, "aes-256-gcm") |> should.be_true()
}

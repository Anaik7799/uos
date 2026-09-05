/// AG-UI Protocol Event Types for C3I Agent-User Interface
/// Implements the full AG-UI event specification (32 types) for streaming
/// agent interactions via Server-Sent Events (SSE).
///
/// STAMP: SC-AGUI-001, SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-CORE-003
import gleam/json
import gleam/string

/// All AG-UI event types per the protocol specification.
pub type EventType {
  RunStarted
  RunFinished
  RunError
  StepStarted
  StepFinished
  TextMessageStart
  TextMessageContent
  TextMessageEnd
  ToolCallStart
  ToolCallArgs
  ToolCallEnd
  ToolCallResult
  StateSnapshot
  StateDelta
  MessagesSnapshot
  Raw
  Custom
  TextMessageChunk
  ToolCallChunk
  ActivitySnapshot
  ActivityDelta
  ReasoningStart
  ReasoningMessageStart
  ReasoningMessageContent
  ReasoningMessageEnd
  ReasoningMessageChunk
  ReasoningEnd
  ReasoningEncryptedValue
  MetaEvent
  BiometricStarted
  BiometricResult
  ApprovalRequested
  ApprovalResult
}

/// Core AG-UI event structure carrying typed payloads over SSE.
pub type AgUiEvent {
  AgUiEvent(
    event_type: EventType,
    timestamp: Int,
    thread_id: String,
    run_id: String,
    payload: json.Json,
  )
}

// ---------------------------------------------------------------------------
// FFI bindings for ID generation and timestamps
// ---------------------------------------------------------------------------

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

/// Returns millisecond timestamp from nanosecond system time.
fn now_ms() -> Int {
  system_time_nanos() / 1_000_000
}

// ---------------------------------------------------------------------------
// EventType serialization
// ---------------------------------------------------------------------------

/// Convert an EventType to its AG-UI protocol string representation.
pub fn event_type_to_string(event_type: EventType) -> String {
  case event_type {
    RunStarted -> "RUN_STARTED"
    RunFinished -> "RUN_FINISHED"
    RunError -> "RUN_ERROR"
    StepStarted -> "STEP_STARTED"
    StepFinished -> "STEP_FINISHED"
    TextMessageStart -> "TEXT_MESSAGE_START"
    TextMessageContent -> "TEXT_MESSAGE_CONTENT"
    TextMessageEnd -> "TEXT_MESSAGE_END"
    ToolCallStart -> "TOOL_CALL_START"
    ToolCallArgs -> "TOOL_CALL_ARGS"
    ToolCallEnd -> "TOOL_CALL_END"
    ToolCallResult -> "TOOL_CALL_RESULT"
    StateSnapshot -> "STATE_SNAPSHOT"
    StateDelta -> "STATE_DELTA"
    MessagesSnapshot -> "MESSAGES_SNAPSHOT"
    Raw -> "RAW"
    Custom -> "CUSTOM"
    TextMessageChunk -> "TEXT_MESSAGE_CHUNK"
    ToolCallChunk -> "TOOL_CALL_CHUNK"
    ActivitySnapshot -> "ACTIVITY_SNAPSHOT"
    ActivityDelta -> "ACTIVITY_DELTA"
    ReasoningStart -> "REASONING_START"
    ReasoningMessageStart -> "REASONING_MESSAGE_START"
    ReasoningMessageContent -> "REASONING_MESSAGE_CONTENT"
    ReasoningMessageEnd -> "REASONING_MESSAGE_END"
    ReasoningMessageChunk -> "REASONING_MESSAGE_CHUNK"
    ReasoningEnd -> "REASONING_END"
    ReasoningEncryptedValue -> "REASONING_ENCRYPTED_VALUE"
    MetaEvent -> "META_EVENT"
    BiometricStarted -> "BIOMETRIC_STARTED"
    BiometricResult -> "BIOMETRIC_RESULT"
    ApprovalRequested -> "APPROVAL_REQUESTED"
    ApprovalResult -> "APPROVAL_RESULT"
  }
}

// ---------------------------------------------------------------------------
// Biometric and Approval constructors
// ---------------------------------------------------------------------------

/// Create a BIOMETRIC_STARTED event.
pub fn new_biometric_started(user_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: BiometricStarted,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("user_id", json.string(user_id)),
    ]),
  )
}

/// Create a BIOMETRIC_RESULT event.
pub fn new_biometric_result(
  user_id: String,
  success: Bool,
  score: Float,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: BiometricResult,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("user_id", json.string(user_id)),
      #("success", json.bool(success)),
      #("score", json.float(score)),
    ]),
  )
}

/// Create an APPROVAL_REQUESTED event.
pub fn new_approval_requested(
  approval_id: String,
  description: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ApprovalRequested,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("approval_id", json.string(approval_id)),
      #("description", json.string(description)),
    ]),
  )
}

/// Create an APPROVAL_RESULT event.
pub fn new_approval_result(approval_id: String, approved: Bool) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ApprovalResult,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("approval_id", json.string(approval_id)),
      #("approved", json.bool(approved)),
    ]),
  )
}

// ---------------------------------------------------------------------------
// Event constructors
// ---------------------------------------------------------------------------

/// Create a RUN_STARTED event for the given thread and run.
pub fn new_run_started(thread_id: String, run_id: String) -> AgUiEvent {
  AgUiEvent(
    event_type: RunStarted,
    timestamp: now_ms(),
    thread_id: thread_id,
    run_id: run_id,
    payload: json.object([
      #("thread_id", json.string(thread_id)),
      #("run_id", json.string(run_id)),
    ]),
  )
}

/// Create a RUN_FINISHED event for the given thread and run.
pub fn new_run_finished(thread_id: String, run_id: String) -> AgUiEvent {
  AgUiEvent(
    event_type: RunFinished,
    timestamp: now_ms(),
    thread_id: thread_id,
    run_id: run_id,
    payload: json.object([
      #("thread_id", json.string(thread_id)),
      #("run_id", json.string(run_id)),
    ]),
  )
}

/// Create a RUN_ERROR event with a message and error code.
pub fn new_run_error(message: String, code: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: RunError,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message", json.string(message)),
      #("code", json.string(code)),
    ]),
  )
}

/// Create a TEXT_MESSAGE_START event for a new message.
pub fn new_text_message_start(message_id: String, role: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: TextMessageStart,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("role", json.string(role)),
    ]),
  )
}

/// Create a TEXT_MESSAGE_CONTENT event with a text delta.
pub fn new_text_message_content(message_id: String, delta: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: TextMessageContent,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("delta", json.string(delta)),
    ]),
  )
}

/// Create a TEXT_MESSAGE_END event.
pub fn new_text_message_end(message_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: TextMessageEnd,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
    ]),
  )
}

/// Create a TOOL_CALL_START event.
pub fn new_tool_call_start(tool_call_id: String, tool_name: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ToolCallStart,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("tool_call_id", json.string(tool_call_id)),
      #("tool_name", json.string(tool_name)),
    ]),
  )
}

/// Create a TOOL_CALL_END event.
pub fn new_tool_call_end(tool_call_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ToolCallEnd,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("tool_call_id", json.string(tool_call_id)),
    ]),
  )
}

/// Create a STATE_SNAPSHOT event carrying a full state JSON blob.
pub fn new_state_snapshot(snapshot_json: json.Json) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: StateSnapshot,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: snapshot_json,
  )
}

/// Create a STATE_DELTA event carrying incremental state operations.
pub fn new_state_delta(delta_ops: json.Json) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: StateDelta,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: delta_ops,
  )
}

/// Create a STEP_STARTED event.
pub fn new_step_started(step_name: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: StepStarted,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("step_name", json.string(step_name)),
    ]),
  )
}

/// Create a STEP_FINISHED event.
pub fn new_step_finished(step_name: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: StepFinished,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("step_name", json.string(step_name)),
    ]),
  )
}

/// Create a CUSTOM event with a name and arbitrary JSON value.
pub fn new_custom(name: String, value: json.Json) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: Custom,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("name", json.string(name)),
      #("value", value),
    ]),
  )
}

/// Create a TOOL_CALL_ARGS event with streaming argument delta.
pub fn new_tool_call_args(tool_call_id: String, delta: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ToolCallArgs,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("tool_call_id", json.string(tool_call_id)),
      #("delta", json.string(delta)),
    ]),
  )
}

/// Create a TOOL_CALL_RESULT event with the result of a tool invocation.
pub fn new_tool_call_result(
  message_id: String,
  tool_call_id: String,
  content: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ToolCallResult,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("tool_call_id", json.string(tool_call_id)),
      #("content", json.string(content)),
    ]),
  )
}

/// Create a TEXT_MESSAGE_CHUNK event with a streaming text delta and role.
pub fn new_text_message_chunk(
  message_id: String,
  role: String,
  delta: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: TextMessageChunk,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("role", json.string(role)),
      #("delta", json.string(delta)),
    ]),
  )
}

/// Create a TOOL_CALL_CHUNK event with a streaming tool argument delta.
pub fn new_tool_call_chunk(
  tool_call_id: String,
  tool_name: String,
  delta: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ToolCallChunk,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("tool_call_id", json.string(tool_call_id)),
      #("tool_name", json.string(tool_name)),
      #("delta", json.string(delta)),
    ]),
  )
}

/// Create a MESSAGES_SNAPSHOT event carrying a full messages JSON blob.
pub fn new_messages_snapshot(messages: json.Json) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: MessagesSnapshot,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: messages,
  )
}

/// Create an ACTIVITY_SNAPSHOT event with full activity state.
pub fn new_activity_snapshot(
  message_id: String,
  activity_type: String,
  content: json.Json,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ActivitySnapshot,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("activity_type", json.string(activity_type)),
      #("content", content),
    ]),
  )
}

/// Create an ACTIVITY_DELTA event with incremental activity patch.
pub fn new_activity_delta(
  message_id: String,
  activity_type: String,
  patch: json.Json,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ActivityDelta,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("activity_type", json.string(activity_type)),
      #("patch", patch),
    ]),
  )
}

/// Create a REASONING_START event signalling the start of a reasoning block.
pub fn new_reasoning_start(message_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningStart,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
    ]),
  )
}

/// Create a REASONING_MESSAGE_START event.
pub fn new_reasoning_message_start(message_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningMessageStart,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
    ]),
  )
}

/// Create a REASONING_MESSAGE_CONTENT event with a text delta.
pub fn new_reasoning_message_content(
  message_id: String,
  delta: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningMessageContent,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("delta", json.string(delta)),
    ]),
  )
}

/// Create a REASONING_MESSAGE_END event.
pub fn new_reasoning_message_end(message_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningMessageEnd,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
    ]),
  )
}

/// Create a REASONING_MESSAGE_CHUNK event with a streaming delta.
pub fn new_reasoning_message_chunk(
  message_id: String,
  delta: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningMessageChunk,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
      #("delta", json.string(delta)),
    ]),
  )
}

/// Create a REASONING_END event signalling the end of a reasoning block.
pub fn new_reasoning_end(message_id: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningEnd,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("message_id", json.string(message_id)),
    ]),
  )
}

/// Create a REASONING_ENCRYPTED_VALUE event carrying an opaque encrypted blob.
pub fn new_reasoning_encrypted_value(
  subtype: String,
  entity_id: String,
  encrypted_value: String,
) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: ReasoningEncryptedValue,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("subtype", json.string(subtype)),
      #("entity_id", json.string(entity_id)),
      #("encrypted_value", json.string(encrypted_value)),
    ]),
  )
}

/// Create a META_EVENT carrying protocol-level metadata.
pub fn new_meta_event(meta_type: String, payload: json.Json) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: MetaEvent,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("meta_type", json.string(meta_type)),
      #("payload", payload),
    ]),
  )
}

/// Create a RAW event wrapping an arbitrary JSON blob with a source tag.
pub fn new_raw(event: json.Json, source: String) -> AgUiEvent {
  let id = generate_id()
  AgUiEvent(
    event_type: Raw,
    timestamp: now_ms(),
    thread_id: id,
    run_id: id,
    payload: json.object([
      #("source", json.string(source)),
      #("event", event),
    ]),
  )
}

// ---------------------------------------------------------------------------
// SSE serialization
// ---------------------------------------------------------------------------

/// Serialize an AgUiEvent to its full JSON representation.
pub fn to_json(event: AgUiEvent) -> json.Json {
  json.object([
    #("type", json.string(event_type_to_string(event.event_type))),
    #("timestamp", json.int(event.timestamp)),
    #("thread_id", json.string(event.thread_id)),
    #("run_id", json.string(event.run_id)),
    #("payload", event.payload),
  ])
}

/// Format an AgUiEvent as an SSE data frame: `data: {json}\n\n`
pub fn to_sse_frame(event: AgUiEvent) -> String {
  let json_str = json.to_string(to_json(event))
  string.concat(["data: ", json_str, "\n\n"])
}

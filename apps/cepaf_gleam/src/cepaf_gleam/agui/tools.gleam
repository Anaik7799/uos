//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/agui/tools</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-AGUI-004</stamp-controls></compliance>
//// </c3i-module>
////
//// AG-UI tool call lifecycle management.
//// Tracks tool calls from Start -> Args -> End -> Result.
//// Includes HITL approval queue for L0 safety-critical operations.
//// STAMP: SC-AGUI-004

import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// Tool definition — passed to agents for capability discovery.
pub type ToolDef {
  ToolDef(
    name: String,
    description: String,
    parameters_schema: json.Json,
    // JSON Schema for accepted args
    requires_approval: Bool,
    // L0 operations need HITL
  )
}

/// Active tool call state — tracks in-progress calls.
pub type ToolCallState {
  ToolCallState(
    tool_call_id: String,
    tool_name: String,
    args_buffer: String,
    // Accumulated args deltas
    status: ToolCallStatus,
    result: Option(String),
    parent_message_id: Option(String),
  )
}

/// Tool call lifecycle status.
pub type ToolCallStatus {
  Pending
  // ToolCallStart received
  ArgsStreaming
  // ToolCallArgs being received
  ArgsComplete
  // ToolCallEnd received, waiting execution
  AwaitingApproval
  // HITL approval needed (SC-AGUI-004)
  Executing
  // Tool is running
  Completed
  // Result received
  Failed(reason: String)
}

/// Tool call registry — tracks all active calls.
pub type ToolRegistry {
  ToolRegistry(
    calls: Dict(String, ToolCallState),
    available_tools: List(ToolDef),
    approval_queue: List(String),
    // tool_call_ids awaiting HITL
  )
}

/// Create an empty tool registry with available tools.
pub fn new_registry(tools: List(ToolDef)) -> ToolRegistry {
  ToolRegistry(calls: dict.new(), available_tools: tools, approval_queue: [])
}

/// Register a new tool call (on TOOL_CALL_START).
pub fn start_call(
  registry: ToolRegistry,
  tool_call_id: String,
  tool_name: String,
) -> ToolRegistry {
  let call =
    ToolCallState(
      tool_call_id: tool_call_id,
      tool_name: tool_name,
      args_buffer: "",
      status: Pending,
      result: None,
      parent_message_id: None,
    )
  ToolRegistry(
    ..registry,
    calls: dict.insert(registry.calls, tool_call_id, call),
  )
}

/// Append args delta (on TOOL_CALL_ARGS).
pub fn append_args(
  registry: ToolRegistry,
  tool_call_id: String,
  delta: String,
) -> ToolRegistry {
  case dict.get(registry.calls, tool_call_id) {
    Ok(call) -> {
      let updated =
        ToolCallState(
          ..call,
          args_buffer: call.args_buffer <> delta,
          status: ArgsStreaming,
        )
      ToolRegistry(
        ..registry,
        calls: dict.insert(registry.calls, tool_call_id, updated),
      )
    }
    Error(_) -> registry
  }
}

/// Finalize args (on TOOL_CALL_END).
pub fn end_args(registry: ToolRegistry, tool_call_id: String) -> ToolRegistry {
  case dict.get(registry.calls, tool_call_id) {
    Ok(call) -> {
      let needs_approval =
        list.any(registry.available_tools, fn(t) {
          t.name == call.tool_name && t.requires_approval
        })
      let new_status = case needs_approval {
        True -> AwaitingApproval
        False -> ArgsComplete
      }
      let updated = ToolCallState(..call, status: new_status)
      let new_queue = case needs_approval {
        True -> [tool_call_id, ..registry.approval_queue]
        False -> registry.approval_queue
      }
      ToolRegistry(
        ..registry,
        calls: dict.insert(registry.calls, tool_call_id, updated),
        approval_queue: new_queue,
      )
    }
    Error(_) -> registry
  }
}

/// Record tool result (on TOOL_CALL_RESULT).
pub fn set_result(
  registry: ToolRegistry,
  tool_call_id: String,
  content: String,
) -> ToolRegistry {
  case dict.get(registry.calls, tool_call_id) {
    Ok(call) -> {
      let updated =
        ToolCallState(..call, status: Completed, result: Some(content))
      ToolRegistry(
        ..registry,
        calls: dict.insert(registry.calls, tool_call_id, updated),
      )
    }
    Error(_) -> registry
  }
}

/// Approve a tool call in the HITL queue (SC-AGUI-004).
pub fn approve_call(
  registry: ToolRegistry,
  tool_call_id: String,
) -> ToolRegistry {
  case dict.get(registry.calls, tool_call_id) {
    Ok(call) -> {
      let updated = ToolCallState(..call, status: Executing)
      ToolRegistry(
        ..registry,
        calls: dict.insert(registry.calls, tool_call_id, updated),
        approval_queue: list.filter(registry.approval_queue, fn(id) {
          id != tool_call_id
        }),
      )
    }
    Error(_) -> registry
  }
}

/// Reject a tool call in the HITL queue.
pub fn reject_call(
  registry: ToolRegistry,
  tool_call_id: String,
  reason: String,
) -> ToolRegistry {
  case dict.get(registry.calls, tool_call_id) {
    Ok(call) -> {
      let updated = ToolCallState(..call, status: Failed(reason))
      ToolRegistry(
        ..registry,
        calls: dict.insert(registry.calls, tool_call_id, updated),
        approval_queue: list.filter(registry.approval_queue, fn(id) {
          id != tool_call_id
        }),
      )
    }
    Error(_) -> registry
  }
}

/// Get count of pending approvals.
pub fn pending_approvals(registry: ToolRegistry) -> Int {
  list.length(registry.approval_queue)
}

/// Get all active (non-completed) calls.
pub fn active_calls(registry: ToolRegistry) -> List(ToolCallState) {
  dict.values(registry.calls)
  |> list.filter(fn(c) {
    case c.status {
      Completed -> False
      Failed(_) -> False
      _ -> True
    }
  })
}

/// Create an empty tool registry with no pre-registered tools.
/// Convenience constructor for contexts where no tools are pre-loaded.
pub fn initial_registry() -> ToolRegistry {
  new_registry([])
}

/// Return the list of tool_call_ids currently awaiting HITL approval.
pub fn pending_call_ids(registry: ToolRegistry) -> List(String) {
  registry.approval_queue
}

/// Serialize the full approval_queue to a JSON array of call-id strings.
/// Used by GET /ag-ui/hitl/pending.
pub fn pending_calls_to_json(registry: ToolRegistry) -> String {
  json.array(registry.approval_queue, json.string)
  |> json.to_string()
}

/// Serialize a single ToolCallState to a JSON object.
pub fn call_state_to_json(call: ToolCallState) -> json.Json {
  json.object([
    #("tool_call_id", json.string(call.tool_call_id)),
    #("tool_name", json.string(call.tool_name)),
    #("status", json.string(tool_status_string(call.status))),
    #("args_buffer", json.string(call.args_buffer)),
  ])
}

/// Convert a ToolCallStatus variant to a human-readable string.
fn tool_status_string(status: ToolCallStatus) -> String {
  case status {
    Pending -> "pending"
    ArgsStreaming -> "args_streaming"
    ArgsComplete -> "args_complete"
    AwaitingApproval -> "awaiting_approval"
    Executing -> "executing"
    Completed -> "completed"
    Failed(reason) -> "failed:" <> reason
  }
}

/// Serialize tool definition to JSON for capability discovery.
pub fn tool_def_to_json(tool: ToolDef) -> json.Json {
  json.object([
    #("name", json.string(tool.name)),
    #("description", json.string(tool.description)),
    #("parameters", tool.parameters_schema),
    #("requires_approval", json.bool(tool.requires_approval)),
  ])
}

//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/fractal/l3_transaction</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-STM-001, SC-AGUI-003</stamp-controls></compliance>
//// </c3i-module>
////
//// L3 Transaction: state diff viewer, tool call panel, conversation history.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// State diff entry — visualizes a JSON Patch operation.
pub type StateDiffEntry {
  StateDiffEntry(
    operation: String,
    path: String,
    old_value: Option(String),
    new_value: Option(String),
    timestamp: Int,
  )
}

/// Tool call display state.
pub type ToolCallDisplay {
  ToolCallDisplay(
    tool_call_id: String,
    tool_name: String,
    args: String,
    status: ToolDisplayStatus,
    result: Option(String),
    duration_ms: Option(Int),
  )
}

pub type ToolDisplayStatus {
  ToolPending
  ToolStreaming
  ToolAwaitingApproval
  ToolExecuting
  ToolCompleted
  ToolFailed(reason: String)
}

/// Transaction panel state.
pub type TransactionPanelState {
  TransactionPanelState(
    state_diffs: List(StateDiffEntry),
    tool_calls: List(ToolCallDisplay),
    max_diffs: Int,
  )
}

pub fn initial_panel() -> TransactionPanelState {
  TransactionPanelState(state_diffs: [], tool_calls: [], max_diffs: 100)
}

pub fn add_diff(
  state: TransactionPanelState,
  diff: StateDiffEntry,
) -> TransactionPanelState {
  let new_diffs = [diff, ..state.state_diffs]
  let trimmed = list.take(new_diffs, state.max_diffs)
  TransactionPanelState(..state, state_diffs: trimmed)
}

pub fn add_tool_call(
  state: TransactionPanelState,
  call: ToolCallDisplay,
) -> TransactionPanelState {
  TransactionPanelState(..state, tool_calls: [call, ..state.tool_calls])
}

pub fn update_tool_status(
  state: TransactionPanelState,
  tool_call_id: String,
  new_status: ToolDisplayStatus,
) -> TransactionPanelState {
  let updated =
    list.map(state.tool_calls, fn(tc) {
      case tc.tool_call_id == tool_call_id {
        True -> ToolCallDisplay(..tc, status: new_status)
        False -> tc
      }
    })
  TransactionPanelState(..state, tool_calls: updated)
}

pub fn set_tool_result(
  state: TransactionPanelState,
  tool_call_id: String,
  result: String,
  duration: Int,
) -> TransactionPanelState {
  let updated =
    list.map(state.tool_calls, fn(tc) {
      case tc.tool_call_id == tool_call_id {
        True ->
          ToolCallDisplay(
            ..tc,
            status: ToolCompleted,
            result: Some(result),
            duration_ms: Some(duration),
          )
        False -> tc
      }
    })
  TransactionPanelState(..state, tool_calls: updated)
}

pub fn is_active_status(status: ToolDisplayStatus) -> Bool {
  case status {
    ToolCompleted -> False
    ToolFailed(_) -> False
    _ -> True
  }
}

pub fn active_tool_count(state: TransactionPanelState) -> Int {
  list.length(
    list.filter(state.tool_calls, fn(tc) { is_active_status(tc.status) }),
  )
}

pub fn diff_to_json(diff: StateDiffEntry) -> json.Json {
  json.object([
    #("op", json.string(diff.operation)),
    #("path", json.string(diff.path)),
    #("old_value", case diff.old_value {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("new_value", case diff.new_value {
      Some(v) -> json.string(v)
      None -> json.null()
    }),
    #("timestamp", json.int(diff.timestamp)),
  ])
}

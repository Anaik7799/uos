/// AG-UI state management tests — RFC 6902 JSON Patch operations and SharedState.
///
/// STAMP: SC-AGUI-003, SC-GLM-CMP-001, SC-GLM-CORE-002
import cepaf_gleam/agui/state
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Patch operation constructors
// =============================================================================

pub fn add_operation_has_correct_op_field_test() {
  let op = state.new_add("/name", json.string("test"))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "\"add\"") |> should.be_true()
}

pub fn add_operation_has_correct_path_field_test() {
  let op = state.new_add("/name", json.string("test"))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "/name") |> should.be_true()
}

pub fn add_operation_has_correct_value_test() {
  let op = state.new_add("/color", json.string("amber"))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "amber") |> should.be_true()
}

pub fn replace_operation_has_correct_op_field_test() {
  let op = state.new_replace("/health", json.string("degraded"))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "\"replace\"") |> should.be_true()
}

pub fn replace_operation_has_correct_path_test() {
  let op = state.new_replace("/health", json.string("degraded"))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "/health") |> should.be_true()
}

pub fn replace_operation_has_correct_value_test() {
  let op = state.new_replace("/status", json.string("critical"))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "critical") |> should.be_true()
}

pub fn remove_operation_has_correct_op_field_test() {
  let op = state.new_remove("/old_field")
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "\"remove\"") |> should.be_true()
}

pub fn remove_operation_has_correct_path_test() {
  let op = state.new_remove("/deprecated_key")
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "/deprecated_key") |> should.be_true()
}

pub fn move_operation_has_correct_op_field_test() {
  let op = state.new_move("/source", "/dest")
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "\"move\"") |> should.be_true()
}

pub fn move_operation_has_from_and_path_test() {
  let op = state.new_move("/old/path", "/new/path")
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "from") |> should.be_true()
  string.contains(s, "/old/path") |> should.be_true()
}

pub fn copy_operation_has_correct_op_field_test() {
  let op = state.new_copy("/from", "/to")
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "\"copy\"") |> should.be_true()
}

pub fn copy_operation_has_from_and_path_test() {
  let op = state.new_copy("/source_path", "/target_path")
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "/source_path") |> should.be_true()
  string.contains(s, "/target_path") |> should.be_true()
}

pub fn test_operation_has_correct_op_field_test() {
  let op = state.new_test("/value", json.int(42))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "\"test\"") |> should.be_true()
}

pub fn test_operation_has_correct_value_test() {
  let op = state.new_test("/count", json.int(99))
  let j = state.patch_op_to_json(op)
  let s = json.to_string(j)
  string.contains(s, "99") |> should.be_true()
}

// =============================================================================
// Patch list serialization
// =============================================================================

pub fn patch_list_serializes_to_json_array_test() {
  let ops = [state.new_add("/a", json.int(1)), state.new_remove("/b")]
  let j = state.patch_list_to_json(ops)
  let s = json.to_string(j)
  string.starts_with(s, "[") |> should.be_true()
  string.ends_with(s, "]") |> should.be_true()
}

pub fn patch_list_empty_serializes_to_empty_array_test() {
  let j = state.patch_list_to_json([])
  let s = json.to_string(j)
  s |> should.equal("[]")
}

pub fn patch_list_contains_all_ops_test() {
  let ops = [
    state.new_add("/x", json.int(1)),
    state.new_replace("/y", json.string("v")),
    state.new_remove("/z"),
  ]
  let j = state.patch_list_to_json(ops)
  let s = json.to_string(j)
  string.contains(s, "\"add\"") |> should.be_true()
  string.contains(s, "\"replace\"") |> should.be_true()
  string.contains(s, "\"remove\"") |> should.be_true()
}

// =============================================================================
// SharedState
// =============================================================================

pub fn initial_state_has_version_zero_test() {
  let s = state.initial_state()
  s.version |> should.equal(0)
}

pub fn apply_snapshot_increments_version_test() {
  let s = state.initial_state()
  let new =
    state.apply_snapshot(s, json.object([#("health", json.string("ok"))]))
  new.version |> should.equal(1)
}

pub fn apply_snapshot_replaces_data_test() {
  let s = state.initial_state()
  let snap = json.object([#("mode", json.string("emergency"))])
  let new = state.apply_snapshot(s, snap)
  let data_str = json.to_string(new.data)
  string.contains(data_str, "emergency") |> should.be_true()
}

pub fn apply_delta_increments_version_test() {
  let s = state.initial_state()
  let new = state.apply_delta(s, [state.new_add("/x", json.int(1))])
  new.version |> should.equal(1)
}

pub fn apply_delta_multiple_ops_increments_by_one_test() {
  let s = state.initial_state()
  let ops = [
    state.new_add("/a", json.int(1)),
    state.new_add("/b", json.int(2)),
    state.new_add("/c", json.int(3)),
  ]
  let new = state.apply_delta(s, ops)
  // apply_delta is ONE atomic boundary: version increments by 1 regardless of op count
  new.version |> should.equal(1)
}

pub fn apply_snapshot_then_delta_version_is_two_test() {
  let s = state.initial_state()
  let s1 = state.apply_snapshot(s, json.object([]))
  let s2 = state.apply_delta(s1, [state.new_add("/k", json.string("v"))])
  s2.version |> should.equal(2)
}

// =============================================================================
// ConversationMessage
// =============================================================================

pub fn messages_to_json_produces_array_test() {
  let msgs = [
    state.ConversationMessage("m1", "user", "hello", None, 1000),
    state.ConversationMessage("m2", "assistant", "hi there", None, 1001),
  ]
  let j = state.messages_to_json(msgs)
  let s = json.to_string(j)
  string.starts_with(s, "[") |> should.be_true()
  string.ends_with(s, "]") |> should.be_true()
}

pub fn messages_to_json_contains_user_role_test() {
  let msgs = [state.ConversationMessage("m1", "user", "hello", None, 1000)]
  let j = state.messages_to_json(msgs)
  let s = json.to_string(j)
  string.contains(s, "user") |> should.be_true()
}

pub fn messages_to_json_contains_assistant_role_test() {
  let msgs = [
    state.ConversationMessage("m1", "assistant", "response", None, 1000),
  ]
  let j = state.messages_to_json(msgs)
  let s = json.to_string(j)
  string.contains(s, "assistant") |> should.be_true()
}

pub fn messages_to_json_contains_tool_call_id_when_some_test() {
  let msgs = [
    state.ConversationMessage("m1", "tool", "result", Some("tc-007"), 1000),
  ]
  let j = state.messages_to_json(msgs)
  let s = json.to_string(j)
  string.contains(s, "tc-007") |> should.be_true()
}

pub fn messages_to_json_contains_null_tool_call_id_when_none_test() {
  let msgs = [state.ConversationMessage("m1", "user", "hi", None, 1000)]
  let j = state.messages_to_json(msgs)
  let s = json.to_string(j)
  string.contains(s, "null") |> should.be_true()
}

pub fn messages_to_json_contains_content_test() {
  let msgs = [
    state.ConversationMessage("m1", "user", "specific-content-xyz", None, 1000),
  ]
  let j = state.messages_to_json(msgs)
  let s = json.to_string(j)
  string.contains(s, "specific-content-xyz") |> should.be_true()
}

pub fn messages_to_json_empty_list_is_empty_array_test() {
  let j = state.messages_to_json([])
  let s = json.to_string(j)
  s |> should.equal("[]")
}

// =============================================================================
// State delta payload helper
// =============================================================================

pub fn state_delta_payload_contains_patch_key_test() {
  let ops = [state.new_add("/field", json.string("value"))]
  let j = state.state_delta_payload(ops, "thread-1", 3)
  let s = json.to_string(j)
  string.contains(s, "patch") |> should.be_true()
}

pub fn state_delta_payload_contains_version_test() {
  let j = state.state_delta_payload([], "thread-1", 7)
  let s = json.to_string(j)
  string.contains(s, "7") |> should.be_true()
}

pub fn state_snapshot_payload_contains_version_test() {
  let s = state.initial_state()
  let j = state.state_snapshot_payload(s, "thread-1")
  let str = json.to_string(j)
  string.contains(str, "version") |> should.be_true()
}

// =============================================================================
// JSON Pointer path builders
// =============================================================================

pub fn pointer_key_appends_key_with_slash_test() {
  state.pointer_key("", "name") |> should.equal("/name")
}

pub fn pointer_key_escapes_tilde_test() {
  state.pointer_key("", "a~b") |> should.equal("/a~0b")
}

pub fn pointer_key_escapes_slash_test() {
  state.pointer_key("", "a/b") |> should.equal("/a~1b")
}

pub fn pointer_index_appends_integer_test() {
  state.pointer_index("/items", 3) |> should.equal("/items/3")
}

// =============================================================================
// Batch patch builders
// =============================================================================

pub fn add_keys_produces_add_operations_test() {
  let ops = state.add_keys([#("health", json.string("ok"))])
  let j = state.patch_list_to_json(ops)
  let s = json.to_string(j)
  string.contains(s, "\"add\"") |> should.be_true()
}

pub fn replace_keys_produces_replace_operations_test() {
  let ops = state.replace_keys([#("mode", json.string("dark"))])
  let j = state.patch_list_to_json(ops)
  let s = json.to_string(j)
  string.contains(s, "\"replace\"") |> should.be_true()
}

pub fn remove_keys_produces_remove_operations_test() {
  let ops = state.remove_keys(["stale_key"])
  let j = state.patch_list_to_json(ops)
  let s = json.to_string(j)
  string.contains(s, "\"remove\"") |> should.be_true()
}

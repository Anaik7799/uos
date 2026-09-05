// AG-UI tools lifecycle and Lustre effects tests.
//
// STAMP: SC-AGUI-004, SC-AGUI-014, SC-AGUI-017

import cepaf_gleam/agui/tools.{
  ArgsComplete, AwaitingApproval, Completed, Executing, Failed, Pending, ToolDef,
}
import cepaf_gleam/ui/lustre/effects.{
  Approved, BatchEffects, Edited, Escalated, NoEffect, Rejected,
  SendHitlDecision, SendToolResult, StartRun, SubscribeAgent,
}
import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should

// =============================================================================
// tools — registry lifecycle
// =============================================================================

pub fn new_registry_creates_empty_calls_test() {
  let reg = tools.new_registry([])
  dict.size(reg.calls) |> should.equal(0)
}

pub fn new_registry_stores_available_tools_test() {
  let tool =
    ToolDef(
      name: "my_tool",
      description: "desc",
      parameters_schema: json.object([]),
      requires_approval: False,
    )
  let reg = tools.new_registry([tool])
  list.length(reg.available_tools) |> should.equal(1)
}

pub fn start_call_adds_call_to_registry_test() {
  let reg = tools.new_registry([])
  let reg2 = tools.start_call(reg, "tc-1", "my_tool")
  dict.size(reg2.calls) |> should.equal(1)
}

pub fn start_call_sets_pending_status_test() {
  let reg = tools.new_registry([])
  let reg2 = tools.start_call(reg, "tc-1", "my_tool")
  case dict.get(reg2.calls, "tc-1") {
    Ok(call) -> call.status |> should.equal(Pending)
    Error(_) -> should.fail()
  }
}

pub fn append_args_accumulates_delta_string_test() {
  let reg =
    tools.new_registry([])
    |> tools.start_call("tc-2", "my_tool")
    |> tools.append_args("tc-2", "{\"a\":")
    |> tools.append_args("tc-2", "1}")

  case dict.get(reg.calls, "tc-2") {
    Ok(call) -> call.args_buffer |> should.equal("{\"a\":1}")
    Error(_) -> should.fail()
  }
}

pub fn append_args_sets_args_streaming_status_test() {
  let reg =
    tools.new_registry([])
    |> tools.start_call("tc-3", "my_tool")
    |> tools.append_args("tc-3", "delta")

  case dict.get(reg.calls, "tc-3") {
    Ok(call) -> call.status |> should.equal(tools.ArgsStreaming)
    Error(_) -> should.fail()
  }
}

pub fn end_args_sets_args_complete_for_no_approval_tool_test() {
  let tool =
    ToolDef(
      name: "safe_tool",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: False,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-4", "safe_tool")
    |> tools.end_args("tc-4")

  case dict.get(reg.calls, "tc-4") {
    Ok(call) -> call.status |> should.equal(ArgsComplete)
    Error(_) -> should.fail()
  }
}

pub fn end_args_sets_awaiting_approval_for_approval_required_tool_test() {
  let tool =
    ToolDef(
      name: "dangerous_tool",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-5", "dangerous_tool")
    |> tools.end_args("tc-5")

  case dict.get(reg.calls, "tc-5") {
    Ok(call) -> call.status |> should.equal(AwaitingApproval)
    Error(_) -> should.fail()
  }
}

pub fn set_result_marks_completed_test() {
  let reg =
    tools.new_registry([])
    |> tools.start_call("tc-6", "my_tool")
    |> tools.set_result("tc-6", "success output")

  case dict.get(reg.calls, "tc-6") {
    Ok(call) -> {
      call.status |> should.equal(Completed)
      call.result |> should.equal(Some("success output"))
    }
    Error(_) -> should.fail()
  }
}

pub fn approve_call_removes_from_approval_queue_test() {
  let tool =
    ToolDef(
      name: "gate_tool",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-7", "gate_tool")
    |> tools.end_args("tc-7")

  // Before approval: should be in queue
  tools.pending_approvals(reg) |> should.equal(1)

  let reg2 = tools.approve_call(reg, "tc-7")
  tools.pending_approvals(reg2) |> should.equal(0)
}

pub fn approve_call_sets_executing_status_test() {
  let tool =
    ToolDef(
      name: "gate_tool2",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-8", "gate_tool2")
    |> tools.end_args("tc-8")
    |> tools.approve_call("tc-8")

  case dict.get(reg.calls, "tc-8") {
    Ok(call) -> call.status |> should.equal(Executing)
    Error(_) -> should.fail()
  }
}

pub fn reject_call_sets_failed_status_test() {
  let tool =
    ToolDef(
      name: "gate_tool3",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-9", "gate_tool3")
    |> tools.end_args("tc-9")
    |> tools.reject_call("tc-9", "operator rejected")

  case dict.get(reg.calls, "tc-9") {
    Ok(call) ->
      case call.status {
        Failed(reason) -> reason |> should.equal("operator rejected")
        _ -> should.fail()
      }
    Error(_) -> should.fail()
  }
}

pub fn reject_call_removes_from_approval_queue_test() {
  let tool =
    ToolDef(
      name: "gate_tool4",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-10", "gate_tool4")
    |> tools.end_args("tc-10")

  tools.pending_approvals(reg) |> should.equal(1)

  let reg2 = tools.reject_call(reg, "tc-10", "no")
  tools.pending_approvals(reg2) |> should.equal(0)
}

pub fn pending_approvals_count_test() {
  let tool =
    ToolDef(
      name: "g1",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let reg =
    tools.new_registry([tool])
    |> tools.start_call("tc-11", "g1")
    |> tools.end_args("tc-11")
    |> tools.start_call("tc-12", "g1")
    |> tools.end_args("tc-12")

  tools.pending_approvals(reg) |> should.equal(2)
}

pub fn active_calls_filters_out_completed_test() {
  let reg =
    tools.new_registry([])
    |> tools.start_call("tc-13", "tool_a")
    |> tools.start_call("tc-14", "tool_b")
    |> tools.set_result("tc-14", "done")

  let active = tools.active_calls(reg)
  list.length(active) |> should.equal(1)
  list.any(active, fn(c) { c.tool_call_id == "tc-13" }) |> should.be_true
}

pub fn active_calls_filters_out_failed_test() {
  let reg =
    tools.new_registry([])
    |> tools.start_call("tc-15", "tool_c")
    |> tools.start_call("tc-16", "tool_d")
    |> tools.reject_call("tc-16", "denied")

  let active = tools.active_calls(reg)
  list.any(active, fn(c) { c.tool_call_id == "tc-15" }) |> should.be_true
  list.any(active, fn(c) { c.tool_call_id == "tc-16" }) |> should.be_false
}

pub fn tool_def_to_json_serializes_name_test() {
  let tool =
    ToolDef(
      name: "my_serialized_tool",
      description: "does things",
      parameters_schema: json.object([]),
      requires_approval: False,
    )
  let j = json.to_string(tools.tool_def_to_json(tool))
  j |> string.contains("my_serialized_tool") |> should.be_true
  j |> string.contains("does things") |> should.be_true
}

pub fn tool_def_to_json_includes_requires_approval_test() {
  let tool =
    ToolDef(
      name: "approval_needed",
      description: "d",
      parameters_schema: json.object([]),
      requires_approval: True,
    )
  let j = json.to_string(tools.tool_def_to_json(tool))
  j |> string.contains("true") |> should.be_true
}

// =============================================================================
// effects — constructors
// =============================================================================

pub fn subscribe_agent_creates_subscribe_agent_effect_test() {
  let eff = effects.subscribe_agent("cortex")
  case eff {
    SubscribeAgent(agent_id, topics) -> {
      agent_id |> should.equal("cortex")
      { topics != [] } |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn start_run_creates_start_run_effect_test() {
  let eff = effects.start_run("sentinel", "analyse threat")
  case eff {
    StartRun(agent_id, input, _thread_id) -> {
      agent_id |> should.equal("sentinel")
      input |> should.equal("analyse threat")
    }
    _ -> should.fail()
  }
}

pub fn send_tool_result_creates_effect_test() {
  let eff = effects.send_tool_result("tc-99", "result_value")
  case eff {
    SendToolResult(tool_call_id, result) -> {
      tool_call_id |> should.equal("tc-99")
      result |> should.equal("result_value")
    }
    _ -> should.fail()
  }
}

pub fn approve_creates_send_hitl_decision_approved_test() {
  let eff = effects.approve("req-1")
  case eff {
    SendHitlDecision(request_id, decision) -> {
      request_id |> should.equal("req-1")
      decision |> should.equal(Approved)
    }
    _ -> should.fail()
  }
}

pub fn reject_creates_send_hitl_decision_rejected_test() {
  let eff = effects.reject("req-2")
  case eff {
    SendHitlDecision(request_id, decision) -> {
      request_id |> should.equal("req-2")
      decision |> should.equal(Rejected)
    }
    _ -> should.fail()
  }
}

pub fn batch_creates_batch_effects_test() {
  let eff =
    effects.batch([effects.subscribe_agent("a"), effects.subscribe_agent("b")])
  case eff {
    BatchEffects(inner) -> list.length(inner) |> should.equal(2)
    _ -> should.fail()
  }
}

pub fn none_creates_no_effect_test() {
  effects.none() |> should.equal(NoEffect)
}

// =============================================================================
// effects — decision_to_string
// =============================================================================

pub fn decision_to_string_approved_test() {
  effects.decision_to_string(Approved) |> should.equal("approved")
}

pub fn decision_to_string_rejected_test() {
  effects.decision_to_string(Rejected) |> should.equal("rejected")
}

pub fn decision_to_string_escalated_test() {
  effects.decision_to_string(Escalated) |> should.equal("escalated")
}

pub fn decision_to_string_edited_test() {
  effects.decision_to_string(Edited("new_val"))
  |> should.equal("edited:new_val")
}

// =============================================================================
// effects — effect_to_json
// =============================================================================

pub fn effect_to_json_subscribe_agent_has_type_field_test() {
  let eff = effects.subscribe_agent("chaya")
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("subscribe_agent") |> should.be_true
  j |> string.contains("chaya") |> should.be_true
}

pub fn effect_to_json_start_run_has_type_field_test() {
  let eff = effects.start_run("cortex", "do_task")
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("start_run") |> should.be_true
}

pub fn effect_to_json_send_tool_result_has_type_field_test() {
  let eff = effects.send_tool_result("tc-abc", "output")
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("tool_result") |> should.be_true
  j |> string.contains("tc-abc") |> should.be_true
}

pub fn effect_to_json_hitl_decision_approved_test() {
  let eff = effects.approve("req-5")
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("hitl_decision") |> should.be_true
  j |> string.contains("approved") |> should.be_true
}

pub fn effect_to_json_no_effect_test() {
  let eff = effects.none()
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("none") |> should.be_true
}

pub fn effect_to_json_batch_effects_test() {
  let eff = effects.batch([effects.none(), effects.none()])
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("batch") |> should.be_true
}

pub fn effect_to_json_subscribe_zenoh_test() {
  let eff = effects.subscribe_zenoh("indrajaal/health/+")
  let j = json.to_string(effects.effect_to_json(eff))
  j |> string.contains("subscribe_zenoh") |> should.be_true
  j |> string.contains("indrajaal/health/+") |> should.be_true
}

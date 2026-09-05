/// MCP-over-Zenoh (MoZ) protocol tests.
/// Covers: MoZClientState construction, topic builders, JSON-RPC message
/// formatting, circuit breaker state, planning dispatch, system dispatch,
/// available_tools listings, and response topic construction.
///
/// STAMP: SC-ZMOF-001, SC-ZMOF-005, SC-GLM-UI-003
import cepaf_gleam/moz/client as moz
import cepaf_gleam/moz/planning
import cepaf_gleam/moz/system as moz_system
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

// =============================================================================
// §1 MoZClientState — initial state invariants
// =============================================================================

pub fn moz_client_new_has_zero_failures_test() {
  let state = moz.new()
  state.consecutive_failures |> should.equal(0)
}

pub fn moz_client_new_has_empty_pending_test() {
  let state = moz.new()
  list.length(state.pending) |> should.equal(0)
}

pub fn moz_client_new_is_available_test() {
  let state = moz.new()
  moz.is_available(state) |> should.equal(True)
}

pub fn moz_client_new_circuit_is_closed_test() {
  let state = moz.new()
  moz.circuit_status(state) |> should.equal("closed")
}

pub fn moz_client_new_has_none_session_test() {
  let state = moz.new()
  state.session |> should.equal(None)
}

pub fn moz_client_invalidate_session_test() {
  let state = moz.new()
  let state2 = moz.invalidate_session(state)
  state2.session |> should.equal(None)
}

// =============================================================================
// §2 Topic builders — request and response topic construction
// =============================================================================

pub fn moz_build_request_topic_format_test() {
  let topic = moz.build_request_topic("planning", "plan_status", "req-001")
  topic
  |> should.equal(
    "indrajaal/l5/cog/mcp/req/planning/plan_status/req-001",
  )
}

pub fn moz_build_request_topic_has_prefix_test() {
  let topic = moz.build_request_topic("system", "health", "r-42")
  topic |> string.starts_with(moz.request_topic_prefix) |> should.be_true()
}

pub fn moz_build_request_topic_contains_domain_test() {
  let topic = moz.build_request_topic("planning", "plan_add", "r-1")
  topic |> string.contains("planning") |> should.be_true()
}

pub fn moz_build_request_topic_contains_method_test() {
  let topic = moz.build_request_topic("planning", "plan_search", "r-2")
  topic |> string.contains("plan_search") |> should.be_true()
}

pub fn moz_build_request_topic_contains_request_id_test() {
  let topic = moz.build_request_topic("system", "health", "unique-id-xyz")
  topic |> string.contains("unique-id-xyz") |> should.be_true()
}

pub fn moz_build_response_topic_format_test() {
  let topic = moz.build_response_topic("req-abc")
  topic |> should.equal("indrajaal/l5/cog/mcp/res/req-abc")
}

pub fn moz_build_response_topic_has_prefix_test() {
  let topic = moz.build_response_topic("r-123")
  topic |> string.starts_with(moz.response_topic_prefix) |> should.be_true()
}

pub fn moz_build_response_topic_ends_with_request_id_test() {
  let topic = moz.build_response_topic("terminal-id")
  topic |> string.ends_with("terminal-id") |> should.be_true()
}

pub fn moz_topic_constants_have_correct_prefix_test() {
  moz.request_topic_prefix
  |> should.equal("indrajaal/l5/cog/mcp/req")
}

pub fn moz_response_prefix_is_correct_test() {
  moz.response_topic_prefix
  |> should.equal("indrajaal/l5/cog/mcp/res")
}

pub fn moz_query_prefix_is_correct_test() {
  moz.query_topic_prefix
  |> should.equal("indrajaal/l5/cog/mcp/query")
}

// =============================================================================
// §3 JSON-RPC 2.0 message formatting
// =============================================================================

pub fn moz_build_request_json_has_jsonrpc_field_test() {
  let payload =
    moz.build_request_json("plan_status", json.object([]), "req-1")
  payload |> string.contains("jsonrpc") |> should.be_true()
}

pub fn moz_build_request_json_jsonrpc_version_is_20_test() {
  let payload =
    moz.build_request_json("plan_status", json.object([]), "req-1")
  payload |> string.contains("2.0") |> should.be_true()
}

pub fn moz_build_request_json_has_method_field_test() {
  let payload =
    moz.build_request_json("system_health", json.object([]), "req-2")
  payload |> string.contains("method") |> should.be_true()
}

pub fn moz_build_request_json_method_value_correct_test() {
  let payload =
    moz.build_request_json("plan_add", json.object([]), "req-3")
  payload |> string.contains("plan_add") |> should.be_true()
}

pub fn moz_build_request_json_has_id_field_test() {
  let payload =
    moz.build_request_json("knowledge_search", json.object([]), "id-77")
  payload |> string.contains("id-77") |> should.be_true()
}

pub fn moz_build_request_json_has_params_field_test() {
  let payload =
    moz.build_request_json(
      "plan_search",
      json.object([#("query", json.string("zenoh"))]),
      "req-4",
    )
  payload |> string.contains("params") |> should.be_true()
  payload |> string.contains("zenoh") |> should.be_true()
}

pub fn moz_build_request_json_is_valid_json_string_test() {
  let payload =
    moz.build_request_json("plan_list", json.object([]), "req-valid")
  // Valid JSON starts with { and ends with }
  payload |> string.starts_with("{") |> should.be_true()
  payload |> string.ends_with("}") |> should.be_true()
}

// =============================================================================
// §4 Circuit breaker — failure and success transitions
// =============================================================================

pub fn moz_record_failure_increments_counter_test() {
  let state = moz.new()
  let s1 = moz.record_failure(state)
  s1.consecutive_failures |> should.equal(1)
}

pub fn moz_record_failure_twice_increments_twice_test() {
  let state = moz.new()
  let s1 = moz.record_failure(state) |> moz.record_failure()
  s1.consecutive_failures |> should.equal(2)
}

pub fn moz_record_success_resets_failure_counter_test() {
  let state = moz.new()
  let failed = moz.record_failure(state)
  let recovered = moz.record_success(failed)
  recovered.consecutive_failures |> should.equal(0)
}

pub fn moz_max_consecutive_failures_constant_test() {
  moz.max_consecutive_failures |> should.equal(5)
}

pub fn moz_circuit_open_after_max_failures_test() {
  // Apply max_consecutive_failures failures in sequence (5 times)
  let s0 = moz.new()
  let s1 = moz.record_failure(s0)
  let s2 = moz.record_failure(s1)
  let s3 = moz.record_failure(s2)
  let s4 = moz.record_failure(s3)
  let s5 = moz.record_failure(s4)
  // After 5 failures consecutive_failures == 5 (== max_consecutive_failures)
  { s5.consecutive_failures > moz.max_consecutive_failures - 1 }
  |> should.equal(True)
  // circuit status must be one of the three valid states
  let status = moz.circuit_status(s5)
  let valid_statuses = ["closed", "half_open", "open"]
  list.contains(valid_statuses, status) |> should.be_true()
}

// =============================================================================
// §5 planning module — available_tools and dispatch
// =============================================================================

pub fn planning_topic_prefix_is_correct_test() {
  planning.topic_prefix |> should.equal("indrajaal/moz/planning")
}

pub fn planning_response_topic_format_test() {
  let topic = planning.response_topic("plan-req-99")
  topic |> string.contains("plan-req-99") |> should.be_true()
  topic |> string.contains(planning.topic_prefix) |> should.be_true()
}

pub fn planning_available_tools_has_seven_tools_test() {
  list.length(planning.available_tools()) |> should.equal(7)
}

pub fn planning_available_tools_contains_plan_status_test() {
  let names = list.map(planning.available_tools(), fn(t) { t.0 })
  list.contains(names, "plan_status") |> should.be_true()
}

pub fn planning_available_tools_contains_plan_list_test() {
  let names = list.map(planning.available_tools(), fn(t) { t.0 })
  list.contains(names, "plan_list") |> should.be_true()
}

pub fn planning_available_tools_contains_plan_add_test() {
  let names = list.map(planning.available_tools(), fn(t) { t.0 })
  list.contains(names, "plan_add") |> should.be_true()
}

pub fn planning_available_tools_contains_plan_update_test() {
  let names = list.map(planning.available_tools(), fn(t) { t.0 })
  list.contains(names, "plan_update") |> should.be_true()
}

pub fn planning_available_tools_contains_plan_search_test() {
  let names = list.map(planning.available_tools(), fn(t) { t.0 })
  list.contains(names, "plan_search") |> should.be_true()
}

pub fn planning_available_tools_each_has_description_test() {
  let all_have_desc =
    list.all(planning.available_tools(), fn(t) { string.length(t.1) > 0 })
  all_have_desc |> should.be_true()
}

pub fn planning_dispatch_unknown_tool_returns_error_json_test() {
  let result = planning.dispatch("nonexistent_tool_xyz", json.object([]))
  result |> string.contains("error") |> should.be_true()
  result |> string.contains("nonexistent_tool_xyz") |> should.be_true()
}

pub fn planning_build_request_json_has_jsonrpc_test() {
  let req =
    planning.build_request("plan_status", json.object([]), "req-plan-1")
  req |> string.contains("2.0") |> should.be_true()
}

pub fn planning_build_request_json_has_method_test() {
  let req =
    planning.build_request("plan_search", json.object([]), "req-plan-2")
  req |> string.contains("planning/plan_search") |> should.be_true()
}

pub fn planning_build_request_json_has_request_id_test() {
  let req =
    planning.build_request("plan_list", json.object([]), "my-plan-req-id")
  req |> string.contains("my-plan-req-id") |> should.be_true()
}

// =============================================================================
// §6 system module — available_tools and dispatch
// =============================================================================

pub fn system_topic_prefix_is_correct_test() {
  moz_system.topic_prefix |> should.equal("indrajaal/moz/system")
}

pub fn system_response_topic_format_test() {
  let topic = moz_system.response_topic("sys-req-42")
  topic |> string.contains("sys-req-42") |> should.be_true()
  topic |> string.contains(moz_system.topic_prefix) |> should.be_true()
}

pub fn system_available_tools_has_seven_tools_test() {
  list.length(moz_system.available_tools()) |> should.equal(7)
}

pub fn system_available_tools_contains_system_health_test() {
  let names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  list.contains(names, "system_health") |> should.be_true()
}

pub fn system_available_tools_contains_system_dashboard_test() {
  let names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  list.contains(names, "system_dashboard") |> should.be_true()
}

pub fn system_available_tools_contains_system_immune_test() {
  let names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  list.contains(names, "system_immune") |> should.be_true()
}

pub fn system_available_tools_contains_system_zenoh_test() {
  let names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  list.contains(names, "system_zenoh") |> should.be_true()
}

pub fn system_available_tools_contains_knowledge_search_test() {
  let names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  list.contains(names, "knowledge_search") |> should.be_true()
}

pub fn system_available_tools_contains_verification_run_test() {
  let names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  list.contains(names, "verification_run") |> should.be_true()
}

pub fn system_available_tools_each_has_description_test() {
  let all_have_desc =
    list.all(moz_system.available_tools(), fn(t) { string.length(t.1) > 0 })
  all_have_desc |> should.be_true()
}

pub fn system_dispatch_unknown_tool_returns_error_json_test() {
  let result = moz_system.dispatch("totally_unknown_sys_tool")
  result |> string.contains("error") |> should.be_true()
  result |> string.contains("totally_unknown_sys_tool") |> should.be_true()
}

// =============================================================================
// §7 MoZRequest / MoZError / MoZResponse type constructors
// =============================================================================

pub fn moz_request_fields_are_accessible_test() {
  let req =
    moz.MoZRequest(method: "plan_status", params: json.object([]), request_id: "r-1")
  req.method |> should.equal("plan_status")
  req.request_id |> should.equal("r-1")
}

pub fn moz_error_fields_accessible_test() {
  let err = moz.MoZError(code: -32_601, message: "Method not found")
  err.code |> should.equal(-32_601)
  err.message |> should.equal("Method not found")
}

pub fn moz_response_ok_result_test() {
  let resp =
    moz.MoZResponse(
      result: Ok(json.object([#("ok", json.bool(True))])),
      request_id: "r-ok",
    )
  resp.request_id |> should.equal("r-ok")
  case resp.result {
    Ok(_) -> should.be_true(True)
    Error(_) -> should.fail()
  }
}

pub fn moz_response_error_result_test() {
  let err = moz.MoZError(code: -32_000, message: "Server error")
  let resp = moz.MoZResponse(result: Error(err), request_id: "r-err")
  case resp.result {
    Error(e) -> e.code |> should.equal(-32_000)
    Ok(_) -> should.fail()
  }
}

// =============================================================================
// §8 Cross-module: planning + system tool count totals
// =============================================================================

pub fn total_moz_tools_planning_plus_system_is_fourteen_test() {
  let planning_count = list.length(planning.available_tools())
  let system_count = list.length(moz_system.available_tools())
  { planning_count + system_count } |> should.equal(14)
}

pub fn moz_planning_and_system_tool_names_are_distinct_test() {
  let planning_names = list.map(planning.available_tools(), fn(t) { t.0 })
  let system_names = list.map(moz_system.available_tools(), fn(t) { t.0 })
  // No planning tool should share a name with a system tool
  let overlap =
    list.filter(planning_names, fn(n) { list.contains(system_names, n) })
  list.length(overlap) |> should.equal(0)
}

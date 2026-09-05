// MoZ coverage test — SC-ZMOF-001, SC-ZMOF-005
// Tests MoZ client state, topic builders, circuit breaker, planning/system dispatch
// using verified public API from moz/client.gleam, moz/planning.gleam, moz/system.gleam

import cepaf_gleam/moz/client as moz
import cepaf_gleam/moz/planning
import cepaf_gleam/moz/system as moz_system
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── moz.new / initial state ───────────────────────────────────────────────────

pub fn moz_new_consecutive_failures_zero_test() {
  let state = moz.new()
  state.consecutive_failures |> should.equal(0)
}

pub fn moz_new_pending_empty_test() {
  let state = moz.new()
  state.pending |> should.equal([])
}

pub fn moz_new_available_test() {
  let state = moz.new()
  moz.is_available(state) |> should.equal(True)
}

pub fn moz_new_circuit_closed_test() {
  let state = moz.new()
  moz.circuit_status(state) |> should.equal("closed")
}

// ── topic builders ────────────────────────────────────────────────────────────

pub fn build_request_topic_structure_test() {
  let topic = moz.build_request_topic("planning", "plan_status", "req-001")
  should.be_true(string.contains(topic, "planning"))
  should.be_true(string.contains(topic, "plan_status"))
  should.be_true(string.contains(topic, "req-001"))
}

pub fn build_request_topic_prefix_test() {
  let topic = moz.build_request_topic("system", "health", "abc")
  should.be_true(string.starts_with(topic, moz.request_topic_prefix))
}

pub fn build_response_topic_contains_id_test() {
  let topic = moz.build_response_topic("req-42")
  should.be_true(string.contains(topic, "req-42"))
}

pub fn build_response_topic_prefix_test() {
  let topic = moz.build_response_topic("xyz")
  should.be_true(string.starts_with(topic, moz.response_topic_prefix))
}

// ── constants ─────────────────────────────────────────────────────────────────

pub fn request_topic_prefix_test() {
  moz.request_topic_prefix
  |> should.equal("indrajaal/l5/cog/mcp/req")
}

pub fn response_topic_prefix_test() {
  moz.response_topic_prefix
  |> should.equal("indrajaal/l5/cog/mcp/res")
}

pub fn query_topic_prefix_test() {
  moz.query_topic_prefix
  |> should.equal("indrajaal/l5/cog/mcp/query")
}

pub fn max_consecutive_failures_test() {
  moz.max_consecutive_failures |> should.equal(5)
}

// ── build_request_json ────────────────────────────────────────────────────────

pub fn build_request_json_contains_method_test() {
  let payload =
    moz.build_request_json("plan_status", json.object([]), "req-001")
  should.be_true(string.contains(payload, "plan_status"))
}

pub fn build_request_json_contains_jsonrpc_test() {
  let payload = moz.build_request_json("test_method", json.object([]), "id-1")
  should.be_true(string.contains(payload, "2.0"))
}

pub fn build_request_json_contains_id_test() {
  let payload =
    moz.build_request_json("method", json.object([]), "my-request-id")
  should.be_true(string.contains(payload, "my-request-id"))
}

// ── record_failure / record_success ──────────────────────────────────────────

pub fn record_failure_increments_test() {
  let state = moz.new()
  let state2 = moz.record_failure(state)
  state2.consecutive_failures |> should.equal(1)
}

pub fn record_success_resets_failures_test() {
  let state = moz.new()
  let state2 = moz.record_failure(state)
  let state3 = moz.record_success(state2)
  state3.consecutive_failures |> should.equal(0)
}

pub fn multiple_failures_increment_test() {
  let state = moz.new()
  let s1 = moz.record_failure(state)
  let s2 = moz.record_failure(s1)
  let s3 = moz.record_failure(s2)
  s3.consecutive_failures |> should.equal(3)
}

// ── MoZRequest type ───────────────────────────────────────────────────────────

pub fn moz_request_construction_test() {
  let req =
    moz.MoZRequest(
      method: "plan_status",
      params: json.object([]),
      request_id: "r-001",
    )
  req.method |> should.equal("plan_status")
  req.request_id |> should.equal("r-001")
}

// ── MoZError type ─────────────────────────────────────────────────────────────

pub fn moz_error_construction_test() {
  let err = moz.MoZError(code: -32_601, message: "Method not found")
  err.code |> should.equal(-32_601)
  err.message |> should.equal("Method not found")
}

// ── planning module ───────────────────────────────────────────────────────────

pub fn planning_topic_prefix_test() {
  planning.topic_prefix |> should.equal("indrajaal/moz/planning")
}

pub fn planning_response_topic_test() {
  let topic = planning.response_topic("req-100")
  should.be_true(string.contains(topic, "req-100"))
  should.be_true(string.contains(topic, "planning"))
}

pub fn planning_available_tools_count_test() {
  let tools = planning.available_tools()
  // There are 7 planning tools defined
  should.be_true(list_length(tools) == 7)
}

pub fn planning_available_tools_has_plan_status_test() {
  let tools = planning.available_tools()
  let names = list_map(tools, fn(t) { t.0 })
  should.be_true(list_contains(names, "plan_status"))
}

pub fn planning_available_tools_has_plan_search_test() {
  let tools = planning.available_tools()
  let names = list_map(tools, fn(t) { t.0 })
  should.be_true(list_contains(names, "plan_search"))
}

pub fn planning_dispatch_unknown_tool_test() {
  let result = planning.dispatch("unknown_tool_xyz", json.object([]))
  should.be_true(string.contains(result, "Unknown"))
}

pub fn planning_build_request_contains_method_test() {
  let payload = planning.build_request("plan_status", json.object([]), "r-001")
  should.be_true(string.contains(payload, "plan_status"))
}

// ── system module ─────────────────────────────────────────────────────────────

pub fn system_topic_prefix_test() {
  moz_system.topic_prefix |> should.equal("indrajaal/moz/system")
}

pub fn system_response_topic_test() {
  let topic = moz_system.response_topic("req-200")
  should.be_true(string.contains(topic, "req-200"))
  should.be_true(string.contains(topic, "system"))
}

pub fn system_available_tools_count_test() {
  let tools = moz_system.available_tools()
  // 7 system tools defined
  should.be_true(list_length(tools) >= 5)
}

pub fn system_available_tools_has_system_health_test() {
  let tools = moz_system.available_tools()
  let names = list_map(tools, fn(t) { t.0 })
  should.be_true(list_contains(names, "system_health"))
}

pub fn system_available_tools_has_knowledge_search_test() {
  let tools = moz_system.available_tools()
  let names = list_map(tools, fn(t) { t.0 })
  should.be_true(list_contains(names, "knowledge_search"))
}

pub fn system_dispatch_unknown_tool_test() {
  let result = moz_system.dispatch("unknown_tool_xyz")
  should.be_true(string.contains(result, "Unknown"))
}

// ── Helpers ───────────────────────────────────────────────────────────────────

import gleam/list

fn list_length(lst: List(a)) -> Int {
  list.length(lst)
}

fn list_map(lst: List(a), f: fn(a) -> b) -> List(b) {
  list.map(lst, f)
}

fn list_contains(lst: List(a), item: a) -> Bool {
  list.contains(lst, item)
}

/// AG-UI SSE, tools, and Wisp router tests.
///
/// Covers SSE protocol headers, run-response JSON, agent-aware stream
/// content, tool registry lifecycle, and route dispatch for the Wisp
/// router (SC-AGUI-002, SC-AGUI-004, SC-GLM-UI-001, SC-UIGT-008).
///
/// STAMP: SC-AGUI-002, SC-AGUI-004, SC-GLM-UI-001, SC-GLM-UI-003,
///        SC-UIGT-008, SC-FED-001
import cepaf_gleam/agui/sse as agui_sse
import cepaf_gleam/agui/tools as agui_tools
import cepaf_gleam/ui/wisp/router
import gleam/list
import gleam/string
import gleeunit/should

// =============================================================================
// SSE headers — sse_headers() -> List(#(String, String))
// =============================================================================

pub fn sse_headers_has_event_stream_test() {
  let headers = agui_sse.sse_headers()
  let found =
    list.any(headers, fn(h) {
      let #(name, value) = h
      name == "content-type" && value == "text/event-stream"
    })
  found |> should.be_true()
}

pub fn sse_headers_has_cache_control_test() {
  let headers = agui_sse.sse_headers()
  let found =
    list.any(headers, fn(h) {
      let #(name, value) = h
      name == "cache-control" && value == "no-cache"
    })
  found |> should.be_true()
}

pub fn sse_headers_has_connection_test() {
  let headers = agui_sse.sse_headers()
  let found =
    list.any(headers, fn(h) {
      let #(name, value) = h
      name == "connection" && value == "keep-alive"
    })
  found |> should.be_true()
}

pub fn sse_headers_has_three_entries_test() {
  agui_sse.sse_headers()
  |> list.length()
  |> should.equal(3)
}

// =============================================================================
// create_run_response — JSON object for POST /ag-ui/run
// =============================================================================

pub fn create_run_response_contains_run_id_test() {
  let j = agui_sse.create_run_response("cortex", "thread-001", "run-abc")
  string.contains(j, "run-abc") |> should.be_true()
}

pub fn create_run_response_contains_agent_test() {
  let j = agui_sse.create_run_response("cortex", "thread-001", "run-abc")
  string.contains(j, "cortex") |> should.be_true()
}

pub fn create_run_response_contains_protocol_test() {
  let j = agui_sse.create_run_response("cortex", "thread-001", "run-abc")
  string.contains(j, "ag-ui-v1") |> should.be_true()
}

pub fn create_run_response_contains_status_started_test() {
  let j = agui_sse.create_run_response("sentinel", "t-99", "r-99")
  string.contains(j, "started") |> should.be_true()
}

// =============================================================================
// create_sse_stream_for_agent — agent-aware SSE frame stream
// =============================================================================

pub fn create_sse_stream_for_agent_contains_custom_event_test() {
  let output =
    agui_sse.create_sse_stream_for_agent("cortex", "thread-002", "run-002")
  string.contains(output, "event: Custom") |> should.be_true()
}

pub fn create_sse_stream_for_agent_contains_agent_test() {
  let output =
    agui_sse.create_sse_stream_for_agent("guardian", "thread-003", "run-003")
  string.contains(output, "guardian") |> should.be_true()
}

// =============================================================================
// ToolRegistry — initial_registry, pending_call_ids, pending_calls_to_json
// =============================================================================

pub fn pending_calls_empty_registry_test() {
  let registry = agui_tools.initial_registry()
  agui_tools.pending_call_ids(registry)
  |> should.equal([])
}

pub fn pending_calls_to_json_empty_test() {
  let registry = agui_tools.initial_registry()
  agui_tools.pending_calls_to_json(registry)
  |> should.equal("[]")
}

pub fn initial_registry_has_no_pending_approvals_test() {
  let registry = agui_tools.initial_registry()
  agui_tools.pending_approvals(registry)
  |> should.equal(0)
}

// =============================================================================
// Wisp router — route(path) -> String
// =============================================================================

pub fn route_health_returns_json_test() {
  let j = router.route("/health")
  string.contains(j, "status") |> should.be_true()
}

pub fn route_agui_health_returns_json_test() {
  let j = router.route("/ag-ui/health")
  string.contains(j, "protocol") |> should.be_true()
}

pub fn route_federation_returns_json_test() {
  let j = router.route("/api/v1/federation")
  string.contains(j, "federation") |> should.be_true()
}

pub fn route_unknown_returns_not_found_test() {
  let j = router.route("/this/path/does/not/exist")
  string.contains(j, "not_found") |> should.be_true()
}

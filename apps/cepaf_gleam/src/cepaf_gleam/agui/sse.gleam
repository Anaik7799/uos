/// AG-UI SSE Endpoint — generates complete Server-Sent Event streams
/// for agent-user interactions.
///
/// Note: To avoid an import cycle with `ui/wisp/router`, the query response
/// text is passed in rather than importing the router directly. The router
/// calls this module, not vice versa.
///
/// STAMP: SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-UI-001
import cepaf_gleam/agui/events
import gleam/json
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

/// Create a complete SSE event stream for a given query.
///
/// Emits the canonical AG-UI event sequence:
///   RUN_STARTED -> STEP_STARTED("processing") -> STATE_SNAPSHOT (health)
///   -> TEXT_MESSAGE (response) -> STEP_FINISHED -> RUN_FINISHED
///
/// `query` is the original request path and `response_text` is the result
/// of routing that query (e.g. via `router.route(query)`). This avoids a
/// circular dependency between this module and the router.
pub fn create_sse_stream(
  thread_id: String,
  run_id: String,
  query: String,
  response_text: String,
) -> String {
  let message_id = generate_id()

  // Build the system health snapshot
  let health_json =
    json.object([
      #("system", json.string("c3i")),
      #("health", json.string("ok")),
      #("interface", json.string("agui-sse")),
      #("query", json.string(query)),
    ])

  // Assemble the complete SSE stream
  string.concat([
    // 1. RUN_STARTED
    events.to_sse_frame(events.new_run_started(thread_id, run_id)),
    // 2. STEP_STARTED
    events.to_sse_frame(events.new_step_started("processing")),
    // 3. STATE_SNAPSHOT (current system health)
    events.to_sse_frame(events.new_state_snapshot(health_json)),
    // 4. TEXT_MESSAGE sequence (start -> content -> end)
    events.to_sse_frame(events.new_text_message_start(message_id, "assistant")),
    events.to_sse_frame(events.new_text_message_content(
      message_id,
      response_text,
    )),
    events.to_sse_frame(events.new_text_message_end(message_id)),
    // 5. STEP_FINISHED
    events.to_sse_frame(events.new_step_finished("processing")),
    // 6. RUN_FINISHED
    events.to_sse_frame(events.new_run_finished(thread_id, run_id)),
  ])
}

/// Create an agent-aware SSE stream with agent metadata as the first event.
/// Prepends a Custom event carrying agent/thread/run identity, then emits the
/// standard demo event sequence via create_sse_stream/4.
/// STAMP: SC-AGUI-002, SC-GLM-UI-010
pub fn create_sse_stream_for_agent(
  agent: String,
  thread_id: String,
  run_id: String,
) -> String {
  let meta_payload =
    json.object([
      #("agent", json.string(agent)),
      #("thread_id", json.string(thread_id)),
      #("run_id", json.string(run_id)),
    ])
    |> json.to_string()
  let meta_frame = "event: Custom\ndata: " <> meta_payload <> "\n\n"
  let stream = create_sse_stream(thread_id, run_id, "/ag-ui/run", meta_payload)
  meta_frame <> stream
}

/// Return a JSON string for the POST /ag-ui/run response.
/// Includes run_id, agent, thread_id, status, and protocol version.
/// STAMP: SC-AGUI-002
pub fn create_run_response(
  agent: String,
  thread_id: String,
  run_id: String,
) -> String {
  json.object([
    #("run_id", json.string(run_id)),
    #("agent", json.string(agent)),
    #("thread_id", json.string(thread_id)),
    #("status", json.string("started")),
    #("protocol", json.string("ag-ui-v1")),
  ])
  |> json.to_string()
}

/// Return the required SSE response headers as a list of name/value pairs.
/// STAMP: SC-AGUI-002
pub fn sse_headers() -> List(#(String, String)) {
  [
    #("content-type", "text/event-stream"),
    #("cache-control", "no-cache"),
    #("connection", "keep-alive"),
  ]
}

/// Return AG-UI protocol health/capabilities as JSON string.
pub fn health_json() -> String {
  json.object([
    #("protocol", json.string("ag-ui")),
    #("version", json.string("1.0.0")),
    #("status", json.string("ok")),
    #(
      "capabilities",
      json.object([
        #("streaming", json.bool(True)),
        #("state_snapshots", json.bool(True)),
        #("tool_calls", json.bool(True)),
        #("text_messages", json.bool(True)),
        #("lifecycle_events", json.bool(True)),
      ]),
    ),
    #("mesh", json.string("indrajaal-c3i")),
    #("sil_level", json.string("SIL-6")),
  ])
  |> json.to_string()
}

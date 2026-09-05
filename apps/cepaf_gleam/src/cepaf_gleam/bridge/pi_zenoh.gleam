//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/bridge/pi_zenoh</module>
////     <fsharp-lineage>no F# lineage — Gleam-native Pi bridge</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Pi Agent Zenoh Event Publisher / Subscriber</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>SC-PI-001, SC-GLM-ZEN-001, SC-ZMOF-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective" augmentation="pub-sub-transport">
////       Pi agent events are injected into the Zenoh mesh as JSON payloads.
////       Every PiEvent variant maps to a structured JSON object published
////       to indrajaal/pi/** topics.  No information is lost; the JSON schema
////       is a strict superset of each variant's fields.
////     </morphism>
////     <morphism type="surjective" loss="callback-lifetime">
////       Subscription callbacks are fire-and-forget Erlang process messages.
////       If the receiving process exits before a message arrives the message
////       is silently dropped.  Mitigation: callers MUST own a long-lived
////       OTP actor or supervisor before calling subscribe_*.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Pi Agent Zenoh Event Publisher.
////
//// Publishes Pi agent events to the Zenoh mesh and subscribes to Zenoh events
//// for Pi consumption.
////
//// SC-PI-001 mandate: ALL Pi events MUST go through Zenoh.
//// SC-GLM-ZEN-001: State changes MUST publish OTel spans.
//// SC-ZMOF-001: Zenoh is the SOLE internal transport.
////
//// Topic schema:
////   indrajaal/pi/events        — Pi lifecycle & reasoning events (pub)
////   indrajaal/pi/tools         — Tool call start/result events   (pub)
////   indrajaal/pi/sessions      — Session open/close events       (pub)
////   indrajaal/pi/health        — Pi agent health heartbeats      (pub)
////   indrajaal/pi/inference     — Inference pipeline events       (pub)
////   indrajaal/c3i/commands/**  — C3I → Pi command channel        (sub)
////
//// OTel span topic:
////   indrajaal/otel/ops/pi/{operation}

import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process.{type Pid}
import gleam/json
import gleam/string

// =============================================================================
// FFI Bindings
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> String

// =============================================================================
// Zenoh Topic Constants (SC-PI-001)
// =============================================================================

/// All Pi agent lifecycle and reasoning events are published here.
pub const pi_events_topic = "indrajaal/pi/events"

/// Tool call start/args/result events from the Pi agent.
pub const pi_tools_topic = "indrajaal/pi/tools"

/// Session lifecycle events (opened, closed, reconnected).
pub const pi_sessions_topic = "indrajaal/pi/sessions"

/// Periodic health heartbeat published by the Pi agent.
pub const pi_health_topic = "indrajaal/pi/health"

/// Inference pipeline events (tier selection, latency, model).
pub const pi_inference_topic = "indrajaal/pi/inference"

/// C3I → Pi command channel (Pi subscribes to this).
pub const c3i_commands_topic = "indrajaal/c3i/commands/**"

/// OTel span topic prefix for Pi operations.
const pi_otel_prefix = "indrajaal/otel/ops/pi/"

// =============================================================================
// Domain Types
// =============================================================================

/// Lifecycle state of the Pi agent process.
pub type PiAgentState {
  /// Pi agent is initialising (NIF not yet ready).
  PiStarting
  /// Pi agent is fully operational.
  PiOnline
  /// Pi agent is disconnected from the Zenoh mesh.
  PiOffline
  /// Pi agent has encountered an unrecoverable error.
  PiFailed(reason: String)
  /// Pi agent is gracefully draining active requests.
  PiDraining
}

/// All events emitted by the Pi agent to the Zenoh mesh.
pub type PiEvent {
  /// Pi agent run lifecycle events (mirrors AG-UI RunStarted / RunFinished).
  PiRunStarted(run_id: String, session_id: String)
  PiRunFinished(run_id: String, session_id: String, duration_ms: Int)
  PiRunError(run_id: String, reason: String)

  /// Reasoning trace events from the Pi OODA loop.
  PiReasoningStart(run_id: String, phase: String)
  PiReasoningContent(run_id: String, content: String)
  PiReasoningEnd(run_id: String, tokens_used: Int)

  /// Tool call events (mirrors AG-UI ToolCallStart / ToolCallEnd).
  PiToolCallStart(run_id: String, tool_name: String, args_json: String)
  PiToolCallEnd(run_id: String, tool_name: String, result_json: String)
  PiToolCallError(run_id: String, tool_name: String, error: String)

  /// Inference cascade tier selection.
  PiInferenceTier(run_id: String, tier: Int, model: String, latency_ms: Int)

  /// Custom domain event (extensible escape hatch).
  PiCustomEvent(kind: String, payload: String)
}

/// OTel span for a Pi operation (SC-GLM-ZEN-001).
pub type PiSpan {
  PiSpan(
    trace_id: String,
    span_id: String,
    operation: String,
    page: String,
    timestamp_nanos: String,
  )
}

// =============================================================================
// Internal Helpers
// =============================================================================

fn pi_agent_state_to_string(state: PiAgentState) -> String {
  case state {
    PiStarting -> "starting"
    PiOnline -> "online"
    PiOffline -> "offline"
    PiFailed(_) -> "failed"
    PiDraining -> "draining"
  }
}

fn pi_event_kind(event: PiEvent) -> String {
  case event {
    PiRunStarted(_, _) -> "run_started"
    PiRunFinished(_, _, _) -> "run_finished"
    PiRunError(_, _) -> "run_error"
    PiReasoningStart(_, _) -> "reasoning_start"
    PiReasoningContent(_, _) -> "reasoning_content"
    PiReasoningEnd(_, _) -> "reasoning_end"
    PiToolCallStart(_, _, _) -> "tool_call_start"
    PiToolCallEnd(_, _, _) -> "tool_call_end"
    PiToolCallError(_, _, _) -> "tool_call_error"
    PiInferenceTier(_, _, _, _) -> "inference_tier"
    PiCustomEvent(kind, _) -> "custom_" <> kind
  }
}

fn pi_event_to_json(event: PiEvent) -> json.Json {
  let kind = pi_event_kind(event)
  case event {
    PiRunStarted(run_id, session_id) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("session_id", json.string(session_id)),
      ])

    PiRunFinished(run_id, session_id, duration_ms) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("session_id", json.string(session_id)),
        #("duration_ms", json.int(duration_ms)),
      ])

    PiRunError(run_id, reason) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("reason", json.string(reason)),
      ])

    PiReasoningStart(run_id, phase) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("phase", json.string(phase)),
      ])

    PiReasoningContent(run_id, content) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("content", json.string(content)),
      ])

    PiReasoningEnd(run_id, tokens_used) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("tokens_used", json.int(tokens_used)),
      ])

    PiToolCallStart(run_id, tool_name, args_json) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("tool_name", json.string(tool_name)),
        #("args", json.string(args_json)),
      ])

    PiToolCallEnd(run_id, tool_name, result_json) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("tool_name", json.string(tool_name)),
        #("result", json.string(result_json)),
      ])

    PiToolCallError(run_id, tool_name, error) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("tool_name", json.string(tool_name)),
        #("error", json.string(error)),
      ])

    PiInferenceTier(run_id, tier, model, latency_ms) ->
      json.object([
        #("kind", json.string(kind)),
        #("run_id", json.string(run_id)),
        #("tier", json.int(tier)),
        #("model", json.string(model)),
        #("latency_ms", json.int(latency_ms)),
      ])

    PiCustomEvent(event_kind, payload) ->
      json.object([
        #("kind", json.string(kind)),
        #("event_kind", json.string(event_kind)),
        #("payload", json.string(payload)),
      ])
  }
}

fn publish_to_zenoh(topic: String, payload: String) -> Result(Nil, String) {
  case zenoh.open("{}") {
    Error(reason) -> Error("zenoh_open_failed: " <> reason)
    Ok(session) -> zenoh.put(session, topic, payload)
  }
}

// =============================================================================
// Event Publishing Functions
// =============================================================================

/// Publish a Pi agent event to the Zenoh mesh.
///
/// SC-PI-001: ALL Pi events MUST go through Zenoh.
/// SC-ZMOF-001: Zenoh is the SOLE internal transport.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">PiEvent → JSON → Zenoh pub/sub</morphism>
///   <formal-proof>
///     <P> event is a valid PiEvent variant </P>
///     <C> publish_pi_event(event) </C>
///     <Q> Ok(Nil) iff Zenoh session opened and put succeeded;
///         Error(reason) otherwise — never panics </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn publish_pi_event(event: PiEvent) -> Result(Nil, String) {
  let payload = json.to_string(pi_event_to_json(event))
  publish_to_zenoh(pi_events_topic, payload)
}

/// Publish a Pi tool call result to the tools topic.
///
/// Convenience wrapper for the common tool result pattern.
pub fn publish_pi_tool_result(
  tool_name: String,
  result: String,
) -> Result(Nil, String) {
  let run_id = generate_id()
  let payload =
    json.to_string(
      json.object([
        #("kind", json.string("tool_result")),
        #("tool_name", json.string(tool_name)),
        #("result", json.string(result)),
        #("run_id", json.string(run_id)),
      ]),
    )
  publish_to_zenoh(pi_tools_topic, payload)
}

/// Publish Pi agent health status to the health topic.
///
/// Called on every OODA heartbeat cycle (10s cadence per SC-ZENOH-006).
pub fn publish_pi_health(status: PiAgentState) -> Result(Nil, String) {
  let state_str = pi_agent_state_to_string(status)
  let failed_reason = case status {
    PiFailed(r) -> r
    _ -> ""
  }
  let payload =
    json.to_string(
      json.object([
        #("state", json.string(state_str)),
        #("failed_reason", json.string(failed_reason)),
        #("timestamp_nanos", json.string(system_time_nanos())),
      ]),
    )
  publish_to_zenoh(pi_health_topic, payload)
}

// =============================================================================
// OTel Span Integration (SC-GLM-ZEN-001)
// =============================================================================

/// Create an OTel span for a Pi operation.
///
/// Follows the pattern established in `ui/zenoh_otel.gleam`.
/// The caller is responsible for publishing via `publish_pi_span/1`.
pub fn create_pi_span(operation: String, page: String) -> PiSpan {
  PiSpan(
    trace_id: generate_id(),
    span_id: generate_id(),
    operation: operation,
    page: page,
    timestamp_nanos: system_time_nanos(),
  )
}

/// Publish a Pi OTel span to the Zenoh mesh.
///
/// Topic: indrajaal/otel/ops/pi/{operation}
pub fn publish_pi_span(span: PiSpan) -> Result(Nil, String) {
  let topic = pi_otel_prefix <> span.operation
  let payload =
    json.to_string(
      json.object([
        #("trace_id", json.string(span.trace_id)),
        #("span_id", json.string(span.span_id)),
        #("operation", json.string(span.operation)),
        #("page", json.string(span.page)),
        #("timestamp_nanos", json.string(span.timestamp_nanos)),
        #("source", json.string("pi_agent")),
      ]),
    )
  publish_to_zenoh(topic, payload)
}

/// Convenience: create and immediately publish a Pi OTel span.
pub fn emit_pi_span(operation: String, page: String) -> Result(Nil, String) {
  let span = create_pi_span(operation, page)
  publish_pi_span(span)
}

// =============================================================================
// Subscription Handlers
// =============================================================================

/// Subscribe to Pi agent events on the events topic.
///
/// The provided `callback` Pid receives Erlang messages whenever a new event
/// is published to `indrajaal/pi/events`.
///
/// SC-ZMOF-001: subscriptions use Zenoh pub/sub exclusively.
///
/// PRECONDITION: `callback` MUST be a long-lived OTP actor Pid.
/// Temporary process Pids will lose messages on process exit.
pub fn subscribe_pi_events(callback: Pid) -> Result(Nil, String) {
  case zenoh.open("{}") {
    Error(reason) -> Error("zenoh_open_failed: " <> reason)
    Ok(session) -> zenoh.subscribe(session, pi_events_topic, callback)
  }
}

/// Subscribe to C3I command messages destined for the Pi agent.
///
/// C3I publishes commands to `indrajaal/c3i/commands/**`.
/// Pi consumes them here and dispatches to its tool handlers.
///
/// Topic wildcard `**` matches all sub-keys, enabling namespace routing:
///   indrajaal/c3i/commands/restart
///   indrajaal/c3i/commands/drain
///   indrajaal/c3i/commands/reconfigure
pub fn subscribe_c3i_commands(callback: Pid) -> Result(Nil, String) {
  case zenoh.open("{}") {
    Error(reason) -> Error("zenoh_open_failed: " <> reason)
    Ok(session) -> zenoh.subscribe(session, c3i_commands_topic, callback)
  }
}

// =============================================================================
// Topic Accessors (for external callers / test observers)
// =============================================================================

/// Return the OTel span topic for a given Pi operation.
///
/// Used by `testing/zenoh_test_observer.gleam` to verify spans are published.
pub fn pi_otel_topic(operation: String) -> String {
  pi_otel_prefix <> operation
}

/// Return all Pi topic prefixes for bulk subscription.
///
/// Used by test observers and monitoring dashboards.
pub fn all_pi_topics() -> List(String) {
  [
    pi_events_topic,
    pi_tools_topic,
    pi_sessions_topic,
    pi_health_topic,
    pi_inference_topic,
  ]
}

// =============================================================================
// Convenience: Publish a session lifecycle event
// =============================================================================

/// Publish a Pi session opened event.
pub fn publish_session_opened(session_id: String) -> Result(Nil, String) {
  let payload =
    json.to_string(
      json.object([
        #("kind", json.string("session_opened")),
        #("session_id", json.string(session_id)),
        #("timestamp_nanos", json.string(system_time_nanos())),
      ]),
    )
  publish_to_zenoh(pi_sessions_topic, payload)
}

/// Publish a Pi session closed event.
pub fn publish_session_closed(
  session_id: String,
  reason: String,
) -> Result(Nil, String) {
  let payload =
    json.to_string(
      json.object([
        #("kind", json.string("session_closed")),
        #("session_id", json.string(session_id)),
        #("reason", json.string(reason)),
        #("timestamp_nanos", json.string(system_time_nanos())),
      ]),
    )
  publish_to_zenoh(pi_sessions_topic, payload)
}

// =============================================================================
// Convenience: Publish an inference tier event
// =============================================================================

/// Publish a Pi inference tier selection event to the inference topic.
///
/// Mirrors the 6-tier hedged cascade in the Rust sa-plan-daemon cortex.
pub fn publish_inference_tier(
  run_id: String,
  tier: Int,
  model: String,
  latency_ms: Int,
) -> Result(Nil, String) {
  let event =
    PiInferenceTier(
      run_id: run_id,
      tier: tier,
      model: model,
      latency_ms: latency_ms,
    )
  let payload =
    json.to_string(
      json.object([
        #("kind", json.string("inference_tier")),
        #("run_id", json.string(event.run_id)),
        #("tier", json.int(event.tier)),
        #("model", json.string(event.model)),
        #("latency_ms", json.int(event.latency_ms)),
      ]),
    )
  publish_to_zenoh(pi_inference_topic, payload)
}

// =============================================================================
// Topic Routing Helpers
// =============================================================================

/// Derive the correct Zenoh topic for a PiEvent variant.
///
/// Used by router logic that needs to dispatch to the appropriate
/// topic without calling publish_pi_event directly.
pub fn topic_for_event(event: PiEvent) -> String {
  case event {
    PiToolCallStart(_, _, _) | PiToolCallEnd(_, _, _) | PiToolCallError(_, _, _) ->
      pi_tools_topic
    PiInferenceTier(_, _, _, _) -> pi_inference_topic
    _ -> pi_events_topic
  }
}

/// Publish a PiEvent to its canonical topic (determined by topic_for_event).
pub fn publish_routed(event: PiEvent) -> Result(Nil, String) {
  let topic = topic_for_event(event)
  let payload = json.to_string(pi_event_to_json(event))
  publish_to_zenoh(topic, payload)
}

// =============================================================================
// String Helpers (for pattern matching in tests)
// =============================================================================

/// Validate that a raw payload string contains the expected event kind.
pub fn payload_has_kind(payload: String, kind: String) -> Bool {
  string.contains(payload, "\"kind\":\"" <> kind <> "\"")
}

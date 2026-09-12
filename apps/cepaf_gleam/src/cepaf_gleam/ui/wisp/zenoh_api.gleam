//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/wisp/zenoh_api</module></identity>
////   <fractal-topology><layer>L6_ECOSYSTEM</layer></fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-ZENOH-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////

/// Wisp API for Zenoh Mesh plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Provides endpoints for Zenoh message inspection, OTel span query,
/// subscription management, and message replay for testing.
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-ZENOH-001
import cepaf_gleam/ui/zenoh_otel.{
  type OtelSpan, ooda_phase_to_string, page_to_string,
}
import cepaf_gleam/zenoh/domain.{
  type ConnectionStatus, type ZenohHealth, Connected, Connecting, Disconnected,
}
import gleam/json
import gleam/list

// ---------------------------------------------------------------------------
// Health and Status Endpoints
// ---------------------------------------------------------------------------

pub fn zenoh_health_json(health: ZenohHealth) -> String {
  json.object([
    #("plane", json.string("zenoh")),
    #("status", json.string(connection_status_string(health.status))),
    #("session_id", json.string(health.session_id)),
    #("connected_at", json.int(health.connected_at)),
    #("last_heartbeat", json.int(health.last_heartbeat)),
    #("reconnect_count", json.int(health.reconnect_count)),
    #("messages_published", json.int(health.messages_published)),
    #("messages_received", json.int(health.messages_received)),
    #("error_count", json.int(health.error_count)),
  ])
  |> json.to_string()
}

pub fn subscriptions_json(topics: List(String)) -> String {
  json.object([
    #("plane", json.string("zenoh")),
    #("subscription_count", json.int(list.length(topics))),
    #("topics", json.array(topics, json.string)),
  ])
  |> json.to_string()
}

fn connection_status_string(status: ConnectionStatus) -> String {
  case status {
    Connected -> "connected"
    Disconnected -> "disconnected"
    Connecting -> "connecting"
    domain.Error(msg) -> "error: " <> msg
  }
}

// ---------------------------------------------------------------------------
// Message Inspection Endpoints
// ---------------------------------------------------------------------------

/// JSON response for Zenoh message inspection.
pub fn message_inspection_json(
  topic: String,
  message_count: Int,
  last_message: String,
  last_timestamp: Int,
) -> String {
  json.object([
    #("endpoint", json.string("/zenoh/inspect")),
    #("topic", json.string(topic)),
    #("message_count", json.int(message_count)),
    #("last_message", json.string(last_message)),
    #("last_timestamp", json.int(last_timestamp)),
  ])
  |> json.to_string()
}

/// JSON response for listing all active Zenoh topics.
pub fn topics_list_json(topics: List(#(String, Int))) -> String {
  let topic_entries =
    list.map(topics, fn(pair) {
      let #(t, count) = pair
      json.object([
        #("topic", json.string(t)),
        #("message_count", json.int(count)),
      ])
    })

  json.object([
    #("endpoint", json.string("/zenoh/topics")),
    #("total_topics", json.int(list.length(topics))),
    #("topics", json.array(topic_entries, fn(j) { j })),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// OTel Span Query Endpoints
// ---------------------------------------------------------------------------

/// Convert an OtelSpan to JSON for API response.
fn otel_span_to_json(span: OtelSpan) -> json.Json {
  json.object([
    #("trace_id", json.string(span.trace_id)),
    #("span_id", json.string(span.span_id)),
    #("name", json.string(span.name)),
    #("ooda_phase", json.string(ooda_phase_to_string(span.ooda_phase))),
    #("page", json.string(page_to_string(span.page))),
    #("element", json.string(span.element)),
    #("timestamp", json.int(span.timestamp)),
    #("duration_us", json.int(span.duration_us)),
    #("attributes", span.attributes),
  ])
}

/// JSON response for OTel span query by page.
pub fn otel_spans_by_page_json(page: String, spans: List(OtelSpan)) -> String {
  let span_entries = list.map(spans, otel_span_to_json)

  json.object([
    #("endpoint", json.string("/zenoh/otel/spans")),
    #("page", json.string(page)),
    #("span_count", json.int(list.length(spans))),
    #("spans", json.array(span_entries, fn(j) { j })),
  ])
  |> json.to_string()
}

/// JSON response for OTel span query by OODA phase.
pub fn otel_spans_by_phase_json(phase: String, spans: List(OtelSpan)) -> String {
  let span_entries = list.map(spans, otel_span_to_json)

  json.object([
    #("endpoint", json.string("/zenoh/otel/spans/phase")),
    #("ooda_phase", json.string(phase)),
    #("span_count", json.int(list.length(spans))),
    #("spans", json.array(span_entries, fn(j) { j })),
  ])
  |> json.to_string()
}

/// JSON response for OTel summary statistics.
pub fn otel_summary_json(
  total_spans: Int,
  observe_count: Int,
  orient_count: Int,
  decide_count: Int,
  act_count: Int,
  avg_duration_us: Float,
) -> String {
  json.object([
    #("endpoint", json.string("/zenoh/otel/summary")),
    #("total_spans", json.int(total_spans)),
    #(
      "by_phase",
      json.object([
        #("Observe", json.int(observe_count)),
        #("Orient", json.int(orient_count)),
        #("Decide", json.int(decide_count)),
        #("Act", json.int(act_count)),
      ]),
    ),
    #("avg_duration_us", json.float(avg_duration_us)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Subscription Management Endpoints
// ---------------------------------------------------------------------------

/// JSON response for subscription management operations.
pub fn subscription_action_json(
  action: String,
  topic: String,
  success: Bool,
  message: String,
) -> String {
  json.object([
    #("endpoint", json.string("/zenoh/subscriptions")),
    #("action", json.string(action)),
    #("topic", json.string(topic)),
    #("success", json.bool(success)),
    #("message", json.string(message)),
  ])
  |> json.to_string()
}

/// JSON response for listing all active subscriptions with health.
pub fn subscriptions_health_json(
  subscriptions: List(#(String, String, Int)),
) -> String {
  let sub_entries =
    list.map(subscriptions, fn(triple) {
      let #(topic, status, message_count) = triple
      json.object([
        #("topic", json.string(topic)),
        #("status", json.string(status)),
        #("message_count", json.int(message_count)),
      ])
    })

  json.object([
    #("endpoint", json.string("/zenoh/subscriptions/health")),
    #("total_subscriptions", json.int(list.length(subscriptions))),
    #("subscriptions", json.array(sub_entries, fn(j) { j })),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Message Replay Endpoints (for testing)
// ---------------------------------------------------------------------------

/// JSON response for message replay request.
pub fn replay_request_json(
  topic: String,
  from_timestamp: Int,
  to_timestamp: Int,
  max_messages: Int,
) -> String {
  json.object([
    #("endpoint", json.string("/zenoh/replay")),
    #("topic", json.string(topic)),
    #("from_timestamp", json.int(from_timestamp)),
    #("to_timestamp", json.int(to_timestamp)),
    #("max_messages", json.int(max_messages)),
  ])
  |> json.to_string()
}

/// JSON response for message replay result.
pub fn replay_result_json(
  topic: String,
  messages_replayed: Int,
  duration_ms: Int,
  success: Bool,
) -> String {
  json.object([
    #("endpoint", json.string("/zenoh/replay/result")),
    #("topic", json.string(topic)),
    #("messages_replayed", json.int(messages_replayed)),
    #("duration_ms", json.int(duration_ms)),
    #("success", json.bool(success)),
  ])
  |> json.to_string()
}

/// JSON response for batch replay of multiple topics.
pub fn batch_replay_result_json(
  topics: List(#(String, Int)),
  total_messages: Int,
  total_duration_ms: Int,
) -> String {
  let topic_entries =
    list.map(topics, fn(pair) {
      let #(t, count) = pair
      json.object([
        #("topic", json.string(t)),
        #("messages_replayed", json.int(count)),
      ])
    })

  json.object([
    #("endpoint", json.string("/zenoh/replay/batch")),
    #("topics", json.array(topic_entries, fn(j) { j })),
    #("total_messages", json.int(total_messages)),
    #("total_duration_ms", json.int(total_duration_ms)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Combined Status Endpoint
// ---------------------------------------------------------------------------

/// JSON response combining health, subscriptions, and OTel stats.
pub fn zenoh_status_json(
  health: ZenohHealth,
  subscription_count: Int,
  otel_span_count: Int,
  message_rate: Float,
) -> String {
  json.object([
    #("plane", json.string("zenoh")),
    #("status", json.string(connection_status_string(health.status))),
    #("session_id", json.string(health.session_id)),
    #("subscription_count", json.int(subscription_count)),
    #("otel_span_count", json.int(otel_span_count)),
    #("message_rate_per_sec", json.float(message_rate)),
    #("messages_published", json.int(health.messages_published)),
    #("messages_received", json.int(health.messages_received)),
    #("error_count", json.int(health.error_count)),
    #("reconnect_count", json.int(health.reconnect_count)),
  ])
  |> json.to_string()
}

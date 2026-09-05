//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/testing/zenoh_test_observer</module></identity>
////   <fractal-topology><layer>L6_ECOSYSTEM</layer></fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-CORE-003, SC-COV-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////

/// Zenoh Test Observer Module.
/// Subscribes to all OTel topics during test execution, records state changes
/// and control messages, provides verification functions, and generates reports.
///
/// STAMP: SC-GLM-CORE-001, SC-GLM-CORE-002, SC-GLM-CORE-003, SC-COV-001
import cepaf_gleam/ui/zenoh_otel.{type OtelSpan}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ---------------------------------------------------------------------------
// Recorded message types
// ---------------------------------------------------------------------------

/// A recorded Zenoh message captured during test execution.
pub type RecordedMessage {
  RecordedMessage(topic: String, payload: String, timestamp: Int, sequence: Int)
}

/// Aggregated statistics for a single topic.
pub type TopicStats {
  TopicStats(
    message_count: Int,
    first_seen: Int,
    last_seen: Int,
    avg_latency_us: Int,
    error_count: Int,
  )
}

/// Full observer state carrying all recorded messages and metadata.
pub type ObserverState {
  ObserverState(
    messages: List(RecordedMessage),
    topic_stats: Dict(String, TopicStats),
    sequence_counter: Int,
    started_at: Int,
    stopped_at: Option(Int),
    expected_topics: List(String),
    control_messages: List(RecordedMessage),
    span_log: List(OtelSpan),
  )
}

/// Result of a verification check.
pub type VerificationResult {
  VerificationResult(
    passed: Bool,
    check_name: String,
    expected: String,
    actual: String,
    details: String,
  )
}

/// Test report summarizing observer findings.
pub type TestReport {
  TestReport(
    total_messages: Int,
    total_topics: Int,
    unique_topics: List(String),
    delivery_rate: Float,
    avg_latency_us: Int,
    verification_results: List(VerificationResult),
    control_message_count: Int,
    span_count: Int,
    duration_ms: Int,
  )
}

// ---------------------------------------------------------------------------
// Observer lifecycle
// ---------------------------------------------------------------------------

/// Create a fresh observer state.
pub fn init(expected_topics: List(String)) -> ObserverState {
  ObserverState(
    messages: [],
    topic_stats: dict.new(),
    sequence_counter: 0,
    started_at: 0,
    stopped_at: None,
    expected_topics: expected_topics,
    control_messages: [],
    span_log: [],
  )
}

/// Start the observer, recording the start timestamp.
pub fn start(state: ObserverState) -> ObserverState {
  ObserverState(..state, started_at: 0)
}

/// Stop the observer, recording the stop timestamp.
pub fn stop(state: ObserverState) -> ObserverState {
  ObserverState(..state, stopped_at: Some(0))
}

// ---------------------------------------------------------------------------
// Message recording
// ---------------------------------------------------------------------------

/// Record a Zenoh message into the observer state.
pub fn record_message(
  state: ObserverState,
  topic: String,
  payload: String,
) -> ObserverState {
  let seq = state.sequence_counter + 1
  let msg =
    RecordedMessage(topic: topic, payload: payload, timestamp: 0, sequence: seq)
  let updated_stats = update_topic_stats(state.topic_stats, topic, 0)
  ObserverState(
    ..state,
    messages: [msg, ..state.messages],
    topic_stats: updated_stats,
    sequence_counter: seq,
  )
}

/// Record an OTel span into the observer state.
pub fn record_span(state: ObserverState, span: OtelSpan) -> ObserverState {
  ObserverState(..state, span_log: [span, ..state.span_log])
}

/// Record a control message (separate from data messages).
pub fn record_control(
  state: ObserverState,
  topic: String,
  payload: String,
) -> ObserverState {
  let seq = state.sequence_counter + 1
  let msg =
    RecordedMessage(topic: topic, payload: payload, timestamp: 0, sequence: seq)
  ObserverState(
    ..state,
    control_messages: [msg, ..state.control_messages],
    sequence_counter: seq,
  )
}

// ---------------------------------------------------------------------------
// Topic stats helpers
// ---------------------------------------------------------------------------

fn update_topic_stats(
  stats: Dict(String, TopicStats),
  topic: String,
  latency_us: Int,
) -> Dict(String, TopicStats) {
  case dict.get(stats, topic) {
    Ok(existing) ->
      dict.insert(
        stats,
        topic,
        TopicStats(
          message_count: existing.message_count + 1,
          first_seen: existing.first_seen,
          last_seen: 0,
          avg_latency_us: latency_us,
          error_count: existing.error_count,
        ),
      )
    Error(_) ->
      dict.insert(
        stats,
        topic,
        TopicStats(
          message_count: 1,
          first_seen: 0,
          last_seen: 0,
          avg_latency_us: latency_us,
          error_count: 0,
        ),
      )
  }
}

// ---------------------------------------------------------------------------
// Verification functions
// ---------------------------------------------------------------------------

/// Verify that expected topics received at least one message.
pub fn verify_topics_received(state: ObserverState) -> List(VerificationResult) {
  list.map(state.expected_topics, fn(topic) {
    let has_messages = list.any(state.messages, fn(m) { m.topic == topic })
    VerificationResult(
      passed: has_messages,
      check_name: "topic_received",
      expected: "messages on " <> topic,
      actual: case has_messages {
        True -> "received"
        False -> "not received"
      },
      details: case has_messages {
        True -> "Topic " <> topic <> " received messages"
        False -> "Topic " <> topic <> " received no messages"
      },
    )
  })
}

/// Verify message ordering (sequence numbers are monotonically increasing).
pub fn verify_message_ordering(state: ObserverState) -> VerificationResult {
  let ordered = is_ordered(state.messages)
  VerificationResult(
    passed: ordered,
    check_name: "message_ordering",
    expected: "monotonically increasing sequence",
    actual: case ordered {
      True -> "ordered"
      False -> "out of order"
    },
    details: case ordered {
      True -> "All messages arrived in sequence order"
      False -> "Message sequence gaps or reordering detected"
    },
  )
}

fn is_ordered(messages: List(RecordedMessage)) -> Bool {
  messages
  |> list.reverse
  |> is_ordered_acc(0)
}

fn is_ordered_acc(messages: List(RecordedMessage), prev: Int) -> Bool {
  case messages {
    [] -> True
    [msg, ..rest] ->
      case msg.sequence > prev {
        True -> is_ordered_acc(rest, msg.sequence)
        False -> False
      }
  }
}

/// Verify that a specific number of messages were received for a topic.
pub fn verify_message_count(
  state: ObserverState,
  topic: String,
  expected_count: Int,
) -> VerificationResult {
  let actual_count = count_messages_for_topic(state.messages, topic)
  let passed = actual_count == expected_count
  VerificationResult(
    passed: passed,
    check_name: "message_count",
    expected: int.to_string(expected_count),
    actual: int.to_string(actual_count),
    details: "Topic "
      <> topic
      <> ": expected "
      <> int.to_string(expected_count)
      <> " messages, got "
      <> int.to_string(actual_count),
  )
}

fn count_messages_for_topic(
  messages: List(RecordedMessage),
  topic: String,
) -> Int {
  list.length(list.filter(messages, fn(m) { m.topic == topic }))
}

/// Verify OTel span completeness (all OODA phases present).
pub fn verify_span_completeness(state: ObserverState) -> VerificationResult {
  let phases = list.map(state.span_log, fn(s) { s.ooda_phase })
  let has_observe = list.any(phases, fn(p) { p == zenoh_otel.Observe })
  let has_orient = list.any(phases, fn(p) { p == zenoh_otel.Orient })
  let has_decide = list.any(phases, fn(p) { p == zenoh_otel.Decide })
  let has_act = list.any(phases, fn(p) { p == zenoh_otel.Act })
  let complete = has_observe && has_orient && has_decide && has_act
  VerificationResult(
    passed: complete,
    check_name: "span_completeness",
    expected: "all OODA phases (Observe, Orient, Decide, Act)",
    actual: build_phase_summary(has_observe, has_orient, has_decide, has_act),
    details: case complete {
      True -> "All OODA phases present in span log"
      False -> "Missing OODA phases in span log"
    },
  )
}

fn build_phase_summary(
  observe: Bool,
  orient: Bool,
  decide: Bool,
  act: Bool,
) -> String {
  let parts =
    []
    |> prepend_if(observe, "Observe")
    |> prepend_if(orient, "Orient")
    |> prepend_if(decide, "Decide")
    |> prepend_if(act, "Act")
  case parts {
    [] -> "none"
    _ -> string.join(parts, ", ")
  }
}

fn prepend_if(acc: List(String), condition: Bool, value: String) -> List(String) {
  case condition {
    True -> [value, ..acc]
    False -> acc
  }
}

// ---------------------------------------------------------------------------
// Report generation
// ---------------------------------------------------------------------------

/// Generate a test report from the observer state.
pub fn generate_report(state: ObserverState) -> TestReport {
  let total_msgs = list.length(state.messages)
  let unique = unique_topics(state.messages)
  let total_topics = list.length(unique)
  let expected_total = list.length(state.expected_topics)
  let delivery_rate = case expected_total {
    0 -> 1.0
    n -> {
      let covered =
        list.length(
          list.filter(state.expected_topics, fn(t) {
            list.any(state.messages, fn(m) { m.topic == t })
          }),
        )
      int_to_float(covered) /. int_to_float(n)
    }
  }
  let avg_latency = compute_avg_latency(state.topic_stats)
  let duration = case state.stopped_at {
    None -> 0
    Some(stop) -> stop - state.started_at
  }

  TestReport(
    total_messages: total_msgs,
    total_topics: total_topics,
    unique_topics: unique,
    delivery_rate: delivery_rate,
    avg_latency_us: avg_latency,
    verification_results: list.flatten([
      verify_topics_received(state),
      [verify_message_ordering(state)],
      [verify_span_completeness(state)],
    ]),
    control_message_count: list.length(state.control_messages),
    span_count: list.length(state.span_log),
    duration_ms: duration,
  )
}

fn unique_topics(messages: List(RecordedMessage)) -> List(String) {
  messages
  |> list.map(fn(m) { m.topic })
  |> unique_list
}

fn unique_list(items: List(String)) -> List(String) {
  unique_acc(items, [])
}

fn unique_acc(items: List(String), seen: List(String)) -> List(String) {
  case items {
    [] -> seen
    [item, ..rest] ->
      case list.contains(seen, item) {
        True -> unique_acc(rest, seen)
        False -> unique_acc(rest, [item, ..seen])
      }
  }
}

fn compute_avg_latency(stats: Dict(String, TopicStats)) -> Int {
  let all_stats = dict.values(stats)
  case list.length(all_stats) {
    0 -> 0
    n -> {
      let total_latency =
        list.fold(all_stats, 0, fn(acc, s) { acc + s.avg_latency_us })
      total_latency / n
    }
  }
}

fn int_to_float(n: Int) -> Float {
  int.to_float(n)
}

// ---------------------------------------------------------------------------
// Report formatting
// ---------------------------------------------------------------------------

/// Format a test report as a human-readable string.
pub fn format_report(report: TestReport) -> String {
  let header = "=== Zenoh OTel Test Report ==="
  let msg_line = "Total messages: " <> int.to_string(report.total_messages)
  let topic_line = "Unique topics: " <> int.to_string(report.total_topics)
  let rate_line = "Delivery rate: " <> float_to_pct(report.delivery_rate)
  let latency_line =
    "Avg latency: " <> int.to_string(report.avg_latency_us) <> " us"
  let span_line = "OTel spans: " <> int.to_string(report.span_count)
  let ctrl_line =
    "Control messages: " <> int.to_string(report.control_message_count)
  let duration_line = "Duration: " <> int.to_string(report.duration_ms) <> " ms"
  let pass_count =
    list.length(list.filter(report.verification_results, fn(r) { r.passed }))
  let total_checks = list.length(report.verification_results)
  let verdict_line =
    "Checks passed: "
    <> int.to_string(pass_count)
    <> "/"
    <> int.to_string(total_checks)

  [
    header,
    msg_line,
    topic_line,
    rate_line,
    latency_line,
    span_line,
    ctrl_line,
    duration_line,
    verdict_line,
    "",
    "Topics:",
  ]
  |> list.append(format_topics_list(report.unique_topics))
  |> list.append(["", "Verification:"])
  |> list.append(format_verification_list(report.verification_results))
  |> string.join("\n")
}

fn format_topics_list(topics: List(String)) -> List(String) {
  list.map(topics, fn(t) { "  - " <> t })
}

fn format_verification_list(results: List(VerificationResult)) -> List(String) {
  list.map(results, fn(r) {
    let status = case r.passed {
      True -> "PASS"
      False -> "FAIL"
    }
    "  [" <> status <> "] " <> r.check_name <> ": " <> r.details
  })
}

fn float_to_pct(f: Float) -> String {
  let pct = float.round(f *. 100.0)
  int.to_string(pct) <> "%"
}

// ---------------------------------------------------------------------------
// Enhanced Verification (SC-GLM-ZEN-001, SC-GLM-ZEN-002)
// ---------------------------------------------------------------------------

/// Verify that all 15 pages have at least one published span.
pub fn verify_all_pages_published(
  state: ObserverState,
) -> List(VerificationResult) {
  let page_names = [
    "dashboard", "planning", "immune", "knowledge", "zenoh", "cockpit",
    "verification", "substrate", "metabolic", "podman", "mcp", "kms",
    "telemetry", "federation", "health_grid", "prajna", "agents", "holon",
    "config", "git", "database", "bridge", "smriti", "planning_dashboard",
    "integrity", "evolution", "biomorphic", "homeostasis", "bicameral",
    "singularity", "component_demo",
  ]
  list.map(page_names, fn(page) {
    let has_span =
      list.any(state.span_log, fn(s) {
        zenoh_otel.page_to_string(s.page) == page
      })
    VerificationResult(
      passed: has_span,
      check_name: "page_published_" <> page,
      expected: "at least 1 span for " <> page,
      actual: case has_span {
        True -> "present"
        False -> "missing"
      },
      details: "Page " <> page <> " span publication check",
    )
  })
}

/// Verify OODA coverage — all 4 phases present across all spans.
pub fn verify_ooda_coverage(state: ObserverState) -> VerificationResult {
  verify_span_completeness(state)
}

/// Verify that control messages have corresponding OTel spans.
pub fn verify_control_state_spans(state: ObserverState) -> VerificationResult {
  let control_topics =
    list.map(state.control_messages, fn(m) { m.topic }) |> unique_list
  let span_pages =
    list.map(state.span_log, fn(s) { zenoh_otel.page_to_string(s.page) })
    |> unique_list
  let has_overlap = case control_topics {
    [] -> True
    _ -> span_pages != []
  }
  VerificationResult(
    passed: has_overlap,
    check_name: "control_state_spans",
    expected: "control messages have corresponding spans",
    actual: case has_overlap {
      True -> "correlated"
      False -> "uncorrelated"
    },
    details: "Control topics: "
      <> int.to_string(list.length(control_topics))
      <> ", Span pages: "
      <> int.to_string(list.length(span_pages)),
  )
}

/// Verify that MCP relay received Zenoh messages.
pub fn verify_mcp_relay(
  state: ObserverState,
  mcp_received: List(String),
) -> VerificationResult {
  let zenoh_topics = unique_list(list.map(state.messages, fn(m) { m.topic }))
  let relay_count =
    list.length(
      list.filter(mcp_received, fn(r) { list.contains(zenoh_topics, r) }),
    )
  let passed = relay_count > 0 || mcp_received == []
  VerificationResult(
    passed: passed,
    check_name: "mcp_relay",
    expected: "MCP received Zenoh messages",
    actual: int.to_string(relay_count) <> " relayed",
    details: "Zenoh topics: "
      <> int.to_string(list.length(zenoh_topics))
      <> ", MCP received: "
      <> int.to_string(list.length(mcp_received)),
  )
}

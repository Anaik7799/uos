import cepaf_gleam/testing/zenoh_test_observer
import cepaf_gleam/ui/domain.{
  Cockpit, Dashboard, Federation, HealthGrid, Immune, Kms, Knowledge, Mcp,
  Metabolic, Planning, Podman, Substrate, Telemetry, Verification, Zenoh,
}
import cepaf_gleam/ui/zenoh_otel.{
  type OtelSpan, Act, Decide, Observe, Orient, error_attrs, new_span,
  ooda_phase_to_string, page_to_string, state_change_attrs, user_action_attrs,
  zenoh_message_attrs,
}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

pub fn ooda_phase_to_string_test() {
  ooda_phase_to_string(Observe) |> should.equal("Observe")
  ooda_phase_to_string(Orient) |> should.equal("Orient")
  ooda_phase_to_string(Decide) |> should.equal("Decide")
  ooda_phase_to_string(Act) |> should.equal("Act")
}

pub fn page_to_string_test() {
  page_to_string(Dashboard) |> should.equal("dashboard")
  page_to_string(Planning) |> should.equal("planning")
  page_to_string(Zenoh) |> should.equal("zenoh")
  page_to_string(Federation) |> should.equal("federation")
}

pub fn new_span_creates_valid_span_test() {
  let attrs = json.object([#("key", json.string("value"))])
  let span = new_span(Dashboard, "state_change", Observe, attrs)

  span.page |> should.equal(Dashboard)
  span.element |> should.equal("state_change")
  span.ooda_phase |> should.equal(Observe)
  span.name |> should.equal("/dashboard/state_change")
}

pub fn span_to_json_contains_required_fields_test() {
  let attrs = json.object([#("test", json.string("true"))])
  let span = new_span(Planning, "task_update", Decide, attrs)

  let j = span_to_json_for_test(span)
  let json_str = json.to_string(j)

  assert string.contains(json_str, "trace_id")
  assert string.contains(json_str, "span_id")
  assert string.contains(json_str, "ooda_phase")
  assert string.contains(json_str, "Decide")
  assert string.contains(json_str, "/planning")
  assert string.contains(json_str, "task_update")
}

pub fn state_change_attrs_builds_correct_json_test() {
  let attrs = state_change_attrs("idle", "active", "user_click")
  let json_str = json.to_string(attrs)

  assert string.contains(json_str, "from_state")
  assert string.contains(json_str, "idle")
  assert string.contains(json_str, "to_state")
  assert string.contains(json_str, "active")
  assert string.contains(json_str, "trigger")
  assert string.contains(json_str, "user_click")
  assert string.contains(json_str, "state_change")
}

pub fn user_action_attrs_builds_correct_json_test() {
  let attrs = user_action_attrs("navigate", "/zenoh")
  let json_str = json.to_string(attrs)

  assert string.contains(json_str, "navigate")
  assert string.contains(json_str, "/zenoh")
  assert string.contains(json_str, "user_action")
}

pub fn zenoh_message_attrs_builds_correct_json_test() {
  let attrs = zenoh_message_attrs("c3i/test", 42, 1500)
  let json_str = json.to_string(attrs)

  assert string.contains(json_str, "c3i/test")
  assert string.contains(json_str, "42")
  assert string.contains(json_str, "1500")
  assert string.contains(json_str, "zenoh_message")
}

pub fn error_attrs_builds_correct_json_test() {
  let attrs = error_attrs("ConnectionError", "timeout after 5000ms")
  let json_str = json.to_string(attrs)

  assert string.contains(json_str, "ConnectionError")
  assert string.contains(json_str, "timeout after 5000ms")
  assert string.contains(json_str, "error")
}

pub fn observer_init_creates_empty_state_test() {
  let topics = ["indrajaal/otel/ops/_dashboard/state"]
  let state = zenoh_test_observer.init(topics)

  state.messages |> should.equal([])
  state.sequence_counter |> should.equal(0)
  state.expected_topics |> should.equal(topics)
  state.span_log |> should.equal([])
  state.control_messages |> should.equal([])
}

pub fn observer_record_message_increments_sequence_test() {
  let state = zenoh_test_observer.init([])
  let state1 = zenoh_test_observer.record_message(state, "topic/a", "{}")
  let state2 = zenoh_test_observer.record_message(state1, "topic/b", "{}")

  state1.sequence_counter |> should.equal(1)
  state2.sequence_counter |> should.equal(2)
  list.length(state2.messages) |> should.equal(2)
}

pub fn observer_record_span_test() {
  let state = zenoh_test_observer.init([])
  let span = new_span(Dashboard, "test", Observe, json.object([]))
  let state1 = zenoh_test_observer.record_span(state, span)

  list.length(state1.span_log) |> should.equal(1)
}

pub fn observer_record_control_message_test() {
  let state = zenoh_test_observer.init([])
  let state1 = zenoh_test_observer.record_control(state, "ctrl", "start")

  list.length(state1.control_messages) |> should.equal(1)
  state1.control_messages
  |> list.first
  |> should.equal(
    Ok(zenoh_test_observer.RecordedMessage("ctrl", "start", 0, 1)),
  )
}

pub fn verify_topics_received_all_pass_test() {
  let topics = ["topic/a", "topic/b"]
  let state = zenoh_test_observer.init(topics)
  let state1 = zenoh_test_observer.record_message(state, "topic/a", "{}")
  let state2 = zenoh_test_observer.record_message(state1, "topic/b", "{}")

  let results = zenoh_test_observer.verify_topics_received(state2)
  list.length(results) |> should.equal(2)
  list.all(results, fn(r) { r.passed }) |> should.equal(True)
}

pub fn verify_topics_received_some_fail_test() {
  let topics = ["topic/a", "topic/b", "topic/c"]
  let state = zenoh_test_observer.init(topics)
  let state1 = zenoh_test_observer.record_message(state, "topic/a", "{}")

  let results = zenoh_test_observer.verify_topics_received(state1)
  let passed = list.length(list.filter(results, fn(r) { r.passed }))
  passed |> should.equal(1)
}

pub fn verify_message_ordering_ordered_test() {
  let state = zenoh_test_observer.init([])
  let state1 = zenoh_test_observer.record_message(state, "t", "{}")
  let state2 = zenoh_test_observer.record_message(state1, "t", "{}")
  let state3 = zenoh_test_observer.record_message(state2, "t", "{}")

  let result = zenoh_test_observer.verify_message_ordering(state3)
  result.passed |> should.equal(True)
}

pub fn verify_message_count_test() {
  let state = zenoh_test_observer.init([])
  let state1 = zenoh_test_observer.record_message(state, "topic/x", "{}")
  let state2 = zenoh_test_observer.record_message(state1, "topic/x", "{}")

  let result = zenoh_test_observer.verify_message_count(state2, "topic/x", 2)
  result.passed |> should.equal(True)
}

pub fn verify_span_completeness_all_phases_test() {
  let state = zenoh_test_observer.init([])
  let s1 = new_span(Dashboard, "a", Observe, json.object([]))
  let s2 = new_span(Dashboard, "b", Orient, json.object([]))
  let s3 = new_span(Dashboard, "c", Decide, json.object([]))
  let s4 = new_span(Dashboard, "d", Act, json.object([]))
  let state1 =
    state
    |> zenoh_test_observer.record_span(s1)
    |> zenoh_test_observer.record_span(s2)
    |> zenoh_test_observer.record_span(s3)
    |> zenoh_test_observer.record_span(s4)

  let result = zenoh_test_observer.verify_span_completeness(state1)
  result.passed |> should.equal(True)
}

pub fn verify_span_completeness_missing_phases_test() {
  let state = zenoh_test_observer.init([])
  let s1 = new_span(Dashboard, "a", Observe, json.object([]))
  let state1 = zenoh_test_observer.record_span(state, s1)

  let result = zenoh_test_observer.verify_span_completeness(state1)
  result.passed |> should.equal(False)
}

pub fn generate_report_computes_correct_metrics_test() {
  let topics = ["t1", "t2"]
  let state = zenoh_test_observer.init(topics)
  let state1 = zenoh_test_observer.record_message(state, "t1", "{}")
  let state2 = zenoh_test_observer.record_message(state1, "t2", "{}")
  let span = new_span(Dashboard, "test", Observe, json.object([]))
  let state3 = zenoh_test_observer.record_span(state2, span)
  let state4 = zenoh_test_observer.stop(state3)

  let report = zenoh_test_observer.generate_report(state4)

  report.total_messages |> should.equal(2)
  report.total_topics |> should.equal(2)
  report.span_count |> should.equal(1)
  let delivery_ok = case report.delivery_rate {
    0.0 -> False
    rate -> rate >. 0.9
  }
  delivery_ok |> should.equal(True)
}

pub fn format_report_produces_nonempty_string_test() {
  let state = zenoh_test_observer.init([])
  let report = zenoh_test_observer.generate_report(state)
  let formatted = zenoh_test_observer.format_report(report)

  assert string.length(formatted) > 0
  assert string.contains(formatted, "Zenoh OTel Test Report")
}

pub fn publish_for_page_creates_correct_span_test() {
  let attrs = json.object([#("test", json.string("true"))])
  let span = new_span(Cockpit, "navigation", Act, attrs)

  span.page |> should.equal(Cockpit)
  span.element |> should.equal("navigation")
  span.ooda_phase |> should.equal(Act)
}

pub fn all_page_span_functions_create_valid_spans_test() {
  let attrs = json.object([])
  let s1 = new_span(Dashboard, "el", Observe, attrs)
  s1.page |> should.equal(Dashboard)
  let s2 = new_span(Planning, "el", Observe, attrs)
  s2.page |> should.equal(Planning)
  let s3 = new_span(Immune, "el", Observe, attrs)
  s3.page |> should.equal(Immune)
  let s4 = new_span(Knowledge, "el", Observe, attrs)
  s4.page |> should.equal(Knowledge)
  let s5 = new_span(Zenoh, "el", Observe, attrs)
  s5.page |> should.equal(Zenoh)
  let s6 = new_span(Cockpit, "el", Observe, attrs)
  s6.page |> should.equal(Cockpit)
  let s7 = new_span(Verification, "el", Observe, attrs)
  s7.page |> should.equal(Verification)
  let s8 = new_span(Substrate, "el", Observe, attrs)
  s8.page |> should.equal(Substrate)
  let s9 = new_span(Metabolic, "el", Observe, attrs)
  s9.page |> should.equal(Metabolic)
  let s10 = new_span(Podman, "el", Observe, attrs)
  s10.page |> should.equal(Podman)
  let s11 = new_span(Mcp, "el", Observe, attrs)
  s11.page |> should.equal(Mcp)
  let s12 = new_span(Kms, "el", Observe, attrs)
  s12.page |> should.equal(Kms)
  let s13 = new_span(Telemetry, "el", Observe, attrs)
  s13.page |> should.equal(Telemetry)
  let s14 = new_span(Federation, "el", Observe, attrs)
  s14.page |> should.equal(Federation)
  let s15 = new_span(HealthGrid, "el", Observe, attrs)
  s15.page |> should.equal(HealthGrid)
}

pub fn otel_topic_naming_convention_test() {
  let span = new_span(Dashboard, "state", Observe, json.object([]))
  span.name |> should.equal("/dashboard/state")
}

pub fn observer_start_stop_lifecycle_test() {
  let state = zenoh_test_observer.init([])
  let started = zenoh_test_observer.start(state)
  let stopped = zenoh_test_observer.stop(started)

  case stopped.stopped_at {
    Some(_) -> True
    None -> False
  }
  |> should.equal(True)
}

pub fn unique_topics_deduplicates_test() {
  let state = zenoh_test_observer.init([])
  let state1 = zenoh_test_observer.record_message(state, "t1", "{}")
  let state2 = zenoh_test_observer.record_message(state1, "t1", "{}")
  let state3 = zenoh_test_observer.record_message(state2, "t2", "{}")

  let report = zenoh_test_observer.generate_report(state3)
  report.total_topics |> should.equal(2)
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

fn span_to_json_for_test(span: OtelSpan) -> json.Json {
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

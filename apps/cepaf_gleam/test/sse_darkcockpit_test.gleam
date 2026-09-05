// SSE Ring Buffer, Dark Cockpit mode transitions, and Subscription Tracker tests.
//
// Tasks: T027 (SSE streaming infrastructure) + T028 (dark cockpit transitions)
// STAMP: SC-AGUI-002, SC-GLM-UI-010, SC-AGUI-014, SC-AGUI-017, SC-UIGT-010
// Coverage: C5 (interactive state changes), C7 (AG-UI events flow)

import cepaf_gleam/agui/sse_stream.{
  SSEEvent, events_since, format_heartbeat, format_retry_hint, format_sse_event,
  new_buffer, push_event,
}
import cepaf_gleam/prajna/dark_cockpit.{
  Alert, Bright, CriticalSeverity, Dark, Dim, EmergencyMode, ErrorSeverity,
  NormalMode, WarningSeverity, acknowledge_alert, add_alert, determine_mode,
  initial_state, simulate_health_alerts,
}
import cepaf_gleam/ui/lustre/effects.{
  NoEffect, SubscribeZenoh, new_tracker, subscribe_tracked, subscription_count,
  unsubscribe_all,
}
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

// =============================================================================
// SSE Ring Buffer — new_buffer
// =============================================================================

pub fn new_buffer_creates_empty_events_test() {
  let buf = new_buffer(10)
  list.length(buf.events) |> should.equal(0)
}

pub fn new_buffer_stores_correct_max_size_test() {
  let buf = new_buffer(25)
  buf.max_size |> should.equal(25)
}

pub fn new_buffer_next_id_starts_at_zero_test() {
  let buf = new_buffer(5)
  buf.next_id |> should.equal(0)
}

// =============================================================================
// SSE Ring Buffer — push_event / sequential IDs
// =============================================================================

pub fn push_event_first_id_is_zero_test() {
  let buf = new_buffer(10)
  let buf2 = push_event(buf, "test", "payload")
  let first = list.first(buf2.events)
  case first {
    Ok(ev) -> ev.id |> should.equal("0")
    Error(_) -> should.fail()
  }
}

pub fn push_event_sequential_ids_test() {
  let buf =
    new_buffer(10)
    |> push_event("t", "a")
    |> push_event("t", "b")
    |> push_event("t", "c")
  let ids = list.map(buf.events, fn(ev) { ev.id })
  ids |> should.equal(["0", "1", "2"])
}

pub fn push_event_increments_next_id_test() {
  let buf =
    new_buffer(10)
    |> push_event("t", "a")
    |> push_event("t", "b")
  buf.next_id |> should.equal(2)
}

// =============================================================================
// SSE Ring Buffer — eviction when full
// =============================================================================

pub fn push_event_evicts_oldest_when_full_test() {
  // Push 3 events into a size-2 buffer; only the last 2 should remain.
  let buf =
    new_buffer(2)
    |> push_event("t", "first")
    |> push_event("t", "second")
    |> push_event("t", "third")
  list.length(buf.events) |> should.equal(2)
  // ID "0" (first) was evicted; remaining ids are "1" and "2".
  let ids = list.map(buf.events, fn(ev) { ev.id })
  ids |> should.equal(["1", "2"])
}

pub fn push_100_into_size10_has_exactly_10_test() {
  let buf =
    int_range(0, 99)
    |> list.fold(new_buffer(10), fn(b, _) { push_event(b, "t", "d") })
  list.length(buf.events) |> should.equal(10)
}

pub fn push_100_into_size10_highest_id_is_99_test() {
  let buf =
    int_range(0, 99)
    |> list.fold(new_buffer(10), fn(b, _) { push_event(b, "t", "d") })
  let last_ev = list.last(buf.events)
  case last_ev {
    Ok(ev) -> ev.id |> should.equal("99")
    Error(_) -> should.fail()
  }
}

// =============================================================================
// SSE Ring Buffer — events_since
// =============================================================================

pub fn events_since_minus1_returns_all_test() {
  let buf =
    new_buffer(10)
    |> push_event("t", "a")
    |> push_event("t", "b")
    |> push_event("t", "c")
  events_since(buf, -1) |> list.length |> should.equal(3)
}

pub fn events_since_n_returns_only_newer_test() {
  let buf =
    new_buffer(10)
    |> push_event("t", "a")
    |> push_event("t", "b")
    |> push_event("t", "c")
    |> push_event("t", "d")
  // Events with id > 1 are id=2 and id=3.
  let result = events_since(buf, 1)
  list.length(result) |> should.equal(2)
  let ids = list.map(result, fn(ev) { ev.id })
  ids |> should.equal(["2", "3"])
}

pub fn events_since_returns_empty_when_last_id_at_highest_test() {
  let buf =
    new_buffer(10)
    |> push_event("t", "a")
    |> push_event("t", "b")
  // highest id is 1; requesting events_since(1) returns nothing.
  events_since(buf, 1) |> should.equal([])
}

pub fn events_since_returns_empty_when_last_id_exceeds_all_test() {
  let buf =
    new_buffer(10)
    |> push_event("t", "a")
  events_since(buf, 999) |> should.equal([])
}

// =============================================================================
// SSE Wire Format — format_sse_event
// =============================================================================

pub fn format_sse_event_contains_id_line_test() {
  let ev =
    SSEEvent(id: "42", event_type: "update", data: "hello", retry_ms: None)
  let wire = format_sse_event(ev)
  wire |> string.contains("id: 42\n") |> should.be_true()
}

pub fn format_sse_event_contains_event_line_test() {
  let ev = SSEEvent(id: "1", event_type: "status", data: "ok", retry_ms: None)
  let wire = format_sse_event(ev)
  wire |> string.contains("event: status\n") |> should.be_true()
}

pub fn format_sse_event_contains_data_line_test() {
  let ev = SSEEvent(id: "1", event_type: "msg", data: "payload", retry_ms: None)
  let wire = format_sse_event(ev)
  wire |> string.contains("data: payload\n") |> should.be_true()
}

pub fn format_sse_event_ends_with_double_newline_test() {
  let ev = SSEEvent(id: "1", event_type: "msg", data: "x", retry_ms: None)
  let wire = format_sse_event(ev)
  wire |> string.ends_with("\n\n") |> should.be_true()
}

pub fn format_sse_event_correct_full_wire_format_test() {
  let ev = SSEEvent(id: "7", event_type: "ping", data: "{}", retry_ms: None)
  let wire = format_sse_event(ev)
  wire |> should.equal("id: 7\nevent: ping\ndata: {}\n\n")
}

// =============================================================================
// SSE Wire Format — heartbeat and retry hint
// =============================================================================

pub fn format_heartbeat_produces_correct_string_test() {
  format_heartbeat() |> should.equal(": heartbeat\n\n")
}

pub fn format_retry_hint_produces_correct_string_test() {
  format_retry_hint() |> should.equal("retry: 3000\n\n")
}

// =============================================================================
// Dark Cockpit — initial state
// =============================================================================

pub fn initial_state_is_dark_mode_test() {
  let state = initial_state()
  state.mode |> should.equal(Dark)
}

pub fn initial_state_has_empty_alerts_test() {
  let state = initial_state()
  list.length(state.alerts) |> should.equal(0)
}

// =============================================================================
// Dark Cockpit — mode transitions via add_alert
// =============================================================================

pub fn add_warning_alert_transitions_to_dim_test() {
  let state = initial_state()
  let alert =
    Alert(
      id: "a1",
      severity: WarningSeverity,
      message: "disk usage high",
      source: "test",
      timestamp: "t0",
      acknowledged: False,
    )
  let next = add_alert(state, alert)
  next.mode |> should.equal(Dim)
}

pub fn add_critical_alert_transitions_to_emergency_test() {
  let state = initial_state()
  let alert =
    Alert(
      id: "c1",
      severity: CriticalSeverity,
      message: "container down",
      source: "test",
      timestamp: "t0",
      acknowledged: False,
    )
  let next = add_alert(state, alert)
  next.mode |> should.equal(EmergencyMode)
}

pub fn add_error_alert_transitions_to_normal_mode_test() {
  let state = initial_state()
  let alert =
    Alert(
      id: "e1",
      severity: ErrorSeverity,
      message: "health check failed",
      source: "test",
      timestamp: "t0",
      acknowledged: False,
    )
  let next = add_alert(state, alert)
  next.mode |> should.equal(NormalMode)
}

pub fn add_three_error_alerts_transitions_to_bright_test() {
  let state = initial_state()
  let make_err = fn(id) {
    Alert(
      id: id,
      severity: ErrorSeverity,
      message: "err",
      source: "test",
      timestamp: "t0",
      acknowledged: False,
    )
  }
  let next =
    state
    |> add_alert(make_err("e1"))
    |> add_alert(make_err("e2"))
    |> add_alert(make_err("e3"))
  next.mode |> should.equal(Bright)
}

// =============================================================================
// Dark Cockpit — acknowledge_alert
// =============================================================================

pub fn acknowledge_alert_marks_alert_acked_test() {
  let state = initial_state()
  let alert =
    Alert(
      id: "w1",
      severity: WarningSeverity,
      message: "warn",
      source: "test",
      timestamp: "t0",
      acknowledged: False,
    )
  let with_alert = add_alert(state, alert)
  let acked = acknowledge_alert(with_alert, "w1")
  let found = list.find(acked.alerts, fn(a) { a.id == "w1" })
  case found {
    Ok(a) -> a.acknowledged |> should.be_true()
    Error(_) -> should.fail()
  }
}

pub fn acknowledge_all_alerts_returns_to_dark_test() {
  let state = initial_state()
  let alert =
    Alert(
      id: "w2",
      severity: WarningSeverity,
      message: "warn",
      source: "test",
      timestamp: "t0",
      acknowledged: False,
    )
  let with_alert = add_alert(state, alert)
  // Mode should now be Dim (one unacked warning).
  with_alert.mode |> should.equal(Dim)
  // Acknowledge it — mode must return to Dark.
  let acked = acknowledge_alert(with_alert, "w2")
  acked.mode |> should.equal(Dark)
}

// =============================================================================
// Dark Cockpit — simulate_health_alerts
// =============================================================================

pub fn simulate_health_alerts_adds_at_least_one_alert_test() {
  let state = initial_state()
  let live = simulate_health_alerts(state)
  { list.length(live.alerts) >= 1 } |> should.be_true()
}

pub fn simulate_health_alerts_transitions_away_from_dark_test() {
  let state = initial_state()
  let live = simulate_health_alerts(state)
  // The demo alert is Warning severity, so mode must not be Dark.
  live.mode |> should.not_equal(Dark)
}

// =============================================================================
// Dark Cockpit — determine_mode
// =============================================================================

pub fn determine_mode_no_alerts_is_dark_test() {
  determine_mode([]) |> should.equal(Dark)
}

pub fn determine_mode_one_warning_is_dim_test() {
  let alerts = [
    Alert(
      id: "w",
      severity: WarningSeverity,
      message: "w",
      source: "t",
      timestamp: "t0",
      acknowledged: False,
    ),
  ]
  determine_mode(alerts) |> should.equal(Dim)
}

pub fn determine_mode_one_critical_is_emergency_test() {
  let alerts = [
    Alert(
      id: "c",
      severity: CriticalSeverity,
      message: "c",
      source: "t",
      timestamp: "t0",
      acknowledged: False,
    ),
  ]
  determine_mode(alerts) |> should.equal(EmergencyMode)
}

pub fn determine_mode_all_acked_is_dark_test() {
  let alerts = [
    Alert(
      id: "w",
      severity: WarningSeverity,
      message: "w",
      source: "t",
      timestamp: "t0",
      acknowledged: True,
    ),
    Alert(
      id: "e",
      severity: ErrorSeverity,
      message: "e",
      source: "t",
      timestamp: "t0",
      acknowledged: True,
    ),
  ]
  determine_mode(alerts) |> should.equal(Dark)
}

// =============================================================================
// Dark Cockpit — max_alerts bound
// =============================================================================

pub fn alert_list_respects_max_alerts_bound_test() {
  // Push 210 alerts into the state; it must retain at most 200.
  let make_warn = fn(n) {
    Alert(
      id: "a" <> int_to_string(n),
      severity: WarningSeverity,
      message: "w",
      source: "t",
      timestamp: "t0",
      acknowledged: False,
    )
  }
  let state =
    int_range(1, 210)
    |> list.fold(initial_state(), fn(s, n) { add_alert(s, make_warn(n)) })
  { list.length(state.alerts) <= 200 } |> should.be_true()
}

// =============================================================================
// Subscription Tracker
// =============================================================================

pub fn new_tracker_has_zero_subscriptions_test() {
  new_tracker() |> subscription_count |> should.equal(0)
}

pub fn subscribe_tracked_adds_topic_test() {
  let tracker = new_tracker()
  let #(t2, _eff) = subscribe_tracked(tracker, "indrajaal/health/node1")
  subscription_count(t2) |> should.equal(1)
}

pub fn subscribe_tracked_effect_is_subscribe_zenoh_test() {
  let tracker = new_tracker()
  let #(_t2, eff) = subscribe_tracked(tracker, "indrajaal/health/node1")
  eff |> should.equal(SubscribeZenoh("indrajaal/health/node1"))
}

pub fn subscribe_tracked_same_topic_twice_is_idempotent_test() {
  let tracker = new_tracker()
  let #(t2, _) = subscribe_tracked(tracker, "topic/a")
  let #(t3, eff2) = subscribe_tracked(t2, "topic/a")
  // Count must stay at 1.
  subscription_count(t3) |> should.equal(1)
  // Second call returns NoEffect.
  eff2 |> should.equal(NoEffect)
}

pub fn subscribe_tracked_two_different_topics_test() {
  let tracker = new_tracker()
  let #(t2, _) = subscribe_tracked(tracker, "topic/a")
  let #(t3, _) = subscribe_tracked(t2, "topic/b")
  subscription_count(t3) |> should.equal(2)
}

pub fn unsubscribe_all_returns_empty_tracker_test() {
  let tracker = new_tracker()
  let #(t2, _) = subscribe_tracked(tracker, "topic/a")
  let #(t3, _) = subscribe_tracked(t2, "topic/b")
  let empty = unsubscribe_all(t3)
  subscription_count(empty) |> should.equal(0)
}

pub fn subscription_count_matches_list_length_test() {
  let tracker = new_tracker()
  let #(t2, _) = subscribe_tracked(tracker, "x/1")
  let #(t3, _) = subscribe_tracked(t2, "x/2")
  let #(t4, _) = subscribe_tracked(t3, "x/3")
  subscription_count(t4) |> should.equal(3)
}

// =============================================================================
// Internal helpers
// =============================================================================

fn int_to_string(n: Int) -> String {
  int.to_string(n)
}

fn int_range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..int_range(from + 1, to)]
  }
}

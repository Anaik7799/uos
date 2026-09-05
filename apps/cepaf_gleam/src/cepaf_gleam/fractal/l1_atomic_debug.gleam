//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/fractal/l1_atomic_debug</module></identity>
////   <fractal-topology><layer>L1_ATOMIC_DEBUG</layer></fractal-topology>
////   <compliance><stamp-controls>SC-DEBUG-001, SC-LOG-001</stamp-controls></compliance>
//// </c3i-module>
////
//// L1 Atomic/Debug: trace viewer, event stream monitor, AG-UI event feed.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// A trace span from OpenTelemetry.
pub type TraceSpan {
  TraceSpan(
    trace_id: String,
    span_id: String,
    parent_span_id: Option(String),
    operation: String,
    duration_us: Int,
    status: SpanStatus,
    attributes: List(#(String, String)),
  )
}

pub type SpanStatus {
  SpanOk
  SpanError(message: String)
}

/// AG-UI event log entry.
pub type EventLogEntry {
  EventLogEntry(
    event_type: String,
    timestamp: Int,
    thread_id: String,
    run_id: String,
    summary: String,
  )
}

/// Event stream monitor state.
pub type EventMonitorState {
  EventMonitorState(
    entries: List(EventLogEntry),
    max_entries: Int,
    filter: Option(String),
    paused: Bool,
  )
}

pub fn initial_monitor() -> EventMonitorState {
  EventMonitorState(entries: [], max_entries: 500, filter: None, paused: False)
}

pub fn add_event(
  state: EventMonitorState,
  entry: EventLogEntry,
) -> EventMonitorState {
  case state.paused {
    True -> state
    False -> {
      let filtered = case state.filter {
        None -> True
        Some(f) -> entry.event_type == f
      }
      case filtered {
        False -> state
        True -> {
          let new_entries = [entry, ..state.entries]
          let trimmed = list.take(new_entries, state.max_entries)
          EventMonitorState(..state, entries: trimmed)
        }
      }
    }
  }
}

pub fn pause_monitor(state: EventMonitorState) -> EventMonitorState {
  EventMonitorState(..state, paused: True)
}

pub fn resume_monitor(state: EventMonitorState) -> EventMonitorState {
  EventMonitorState(..state, paused: False)
}

pub fn set_filter(
  state: EventMonitorState,
  event_type: String,
) -> EventMonitorState {
  EventMonitorState(..state, filter: Some(event_type))
}

pub fn clear_filter(state: EventMonitorState) -> EventMonitorState {
  EventMonitorState(..state, filter: None)
}

pub fn event_count(state: EventMonitorState) -> Int {
  list.length(state.entries)
}

pub fn span_status_to_string(status: SpanStatus) -> String {
  case status {
    SpanOk -> "ok"
    SpanError(m) -> "error:" <> m
  }
}

pub fn trace_span_to_json(span: TraceSpan) -> json.Json {
  json.object([
    #("trace_id", json.string(span.trace_id)),
    #("span_id", json.string(span.span_id)),
    #("operation", json.string(span.operation)),
    #("duration_us", json.int(span.duration_us)),
    #("status", json.string(span_status_to_string(span.status))),
  ])
}

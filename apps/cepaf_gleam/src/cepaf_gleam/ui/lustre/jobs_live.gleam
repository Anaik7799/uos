/// Lustre MVU component for the /jobs/live page (SC-GLM-UI-001).
///
/// Subscribes to `indrajaal/l4/sched/**` (via the Wisp SSE bridge that wraps
/// `sa-plan sched-observe --json`) and renders a live table of every job
/// keyed by URN. SC-SCHED-TELE-005 + SCHED-TELE-CEPAF-UI.
///
/// Triple-interface partner:
///   - `ui/wisp/jobs_live_api.gleam`     — JSON + SSE wrapper
///   - `ui/tui/jobs_live_view.gleam`     — ANSI renderer
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-007, SC-SCHED-TELE-005
import gleam/list
import gleam/string

pub type JobEvent {
  JobEvent(
    at: String,
    urn: String,
    event: String,
    id: Int,
    queue: String,
    worker: String,
    payload: String,
  )
}

pub type JobRow {
  JobRow(
    urn: String,
    id: Int,
    queue: String,
    worker: String,
    state: String,
    // most-recent event timestamp
    last_at: String,
    // short summary of the most-recent event
    last_summary: String,
  )
}

pub type JobsLiveModel {
  JobsLiveModel(
    rows: List(JobRow),
    connected: Bool,
    last_seq: Int,
    dropped: Int,
    filter_queue: String,
  )
}

pub type JobsLiveMsg {
  EventReceived(JobEvent)
  SetFilterQueue(String)
  Connected
  Disconnected
  DropCounter(Int)
}

pub fn init() -> JobsLiveModel {
  JobsLiveModel(
    rows: [],
    connected: False,
    last_seq: 0,
    dropped: 0,
    filter_queue: "",
  )
}

pub fn update(m: JobsLiveModel, msg: JobsLiveMsg) -> JobsLiveModel {
  case msg {
    Connected -> JobsLiveModel(..m, connected: True)
    Disconnected -> JobsLiveModel(..m, connected: False)
    DropCounter(n) -> JobsLiveModel(..m, dropped: n)
    SetFilterQueue(q) -> JobsLiveModel(..m, filter_queue: q)
    EventReceived(ev) -> {
      let updated = upsert_row(m.rows, ev)
      JobsLiveModel(..m, rows: updated, last_seq: m.last_seq + 1)
    }
  }
}

/// Upsert the most-recent observed state for a job URN.
pub fn upsert_row(rows: List(JobRow), ev: JobEvent) -> List(JobRow) {
  // If the URN isn't a job-URN, skip (task/proc events are rendered elsewhere).
  case string.starts_with(ev.urn, "urn:c3i:job:") {
    False -> rows
    True -> {
      let existing = list.filter(rows, fn(r) { r.urn == ev.urn })
      let others = list.filter(rows, fn(r) { r.urn != ev.urn })
      let prev = case existing {
        [r, ..] -> r
        [] -> JobRow(
            urn: ev.urn,
            id: ev.id,
            queue: ev.queue,
            worker: ev.worker,
            state: "enqueued",
            last_at: "",
            last_summary: "",
          )
      }
      let next_state = event_to_state(ev.event, prev.state)
      let next = JobRow(
        ..prev,
        state: next_state,
        last_at: ev.at,
        last_summary: ev.event,
      )
      [next, ..others]
    }
  }
}

fn event_to_state(event: String, prev: String) -> String {
  case event {
    "enqueued" -> "enqueued"
    "started" -> "executing"
    "heartbeat" -> prev
    "stdout" -> prev
    "stderr" -> prev
    "completed" -> "completed"
    "failed" -> "failed"
    "timeout" -> "timeout"
    "cancelled" -> "cancelled"
    "retryable" -> "retryable"
    "discarded" -> "discarded"
    _ -> prev
  }
}

/// Render-friendly headline for triple-interface consumers.
pub fn headline(m: JobsLiveModel) -> String {
  let n = list.length(m.rows)
  let conn = case m.connected {
    True -> "CONNECTED"
    False -> "DISCONNECTED"
  }
  "jobs="
  <> int_to_string(n)
  <> " conn="
  <> conn
  <> " seq="
  <> int_to_string(m.last_seq)
  <> " dropped="
  <> int_to_string(m.dropped)
}

@external(erlang, "erlang", "integer_to_binary")
fn int_to_string_erl(n: Int) -> String

fn int_to_string(n: Int) -> String {
  int_to_string_erl(n)
}

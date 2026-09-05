/// Wisp API helper for /jobs/live (SC-GLM-UI-003).
/// Returns JSON snapshot of the live-jobs state produced by Lustre MVU.
///
/// Triple-interface sibling of `ui/lustre/jobs_live.gleam`.
///
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-SCHED-TELE-005
import cepaf_gleam/ui/lustre/jobs_live.{type JobRow, type JobsLiveModel}
import gleam/json
import gleam/list

pub fn jobs_json(m: JobsLiveModel) -> json.Json {
  json.object([
    #("connected", json.bool(m.connected)),
    #("last_seq", json.int(m.last_seq)),
    #("dropped", json.int(m.dropped)),
    #("filter_queue", json.string(m.filter_queue)),
    #("rows", json.array(m.rows, job_row_json)),
  ])
}

fn job_row_json(r: JobRow) -> json.Json {
  json.object([
    #("urn", json.string(r.urn)),
    #("id", json.int(r.id)),
    #("queue", json.string(r.queue)),
    #("worker", json.string(r.worker)),
    #("state", json.string(r.state)),
    #("last_at", json.string(r.last_at)),
    #("last_summary", json.string(r.last_summary)),
  ])
}

/// Typed event acceptor used by the SSE bridge.
pub fn event_to_json(evt_kind: String, urn: String, at: String) -> json.Json {
  json.object([
    #("kind", json.string(evt_kind)),
    #("urn", json.string(urn)),
    #("at", json.string(at)),
  ])
}

/// Filter rows by queue name (empty string = no filter).
pub fn filter_by_queue(m: JobsLiveModel, queue: String) -> List(JobRow) {
  case queue {
    "" -> m.rows
    q -> list.filter(m.rows, fn(r) { r.queue == q })
  }
}

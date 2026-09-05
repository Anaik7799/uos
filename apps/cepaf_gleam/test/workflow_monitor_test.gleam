/// Workflow Monitor tests — visibility types for durable workflow execution (WF-3)
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001
import cepaf_gleam/ha/workflow_monitor.{
  Completed, Failed, Paused, Running, TimedOut, WorkflowEvent, WorkflowRun,
  WorkflowSchedule, count_by_status, event_to_json, run_to_json,
  schedule_to_json, status_from_string, status_to_string, summary,
}
import gleam/string
import gleeunit/should

// ---------------------------------------------------------------------------
// status_to_string
// ---------------------------------------------------------------------------

pub fn status_to_string_running_test() {
  status_to_string(Running) |> should.equal("running")
}

pub fn status_to_string_completed_test() {
  status_to_string(Completed) |> should.equal("completed")
}

pub fn status_to_string_failed_test() {
  status_to_string(Failed) |> should.equal("failed")
}

pub fn status_to_string_timed_out_test() {
  status_to_string(TimedOut) |> should.equal("timed_out")
}

pub fn status_to_string_paused_test() {
  status_to_string(Paused) |> should.equal("paused")
}

// ---------------------------------------------------------------------------
// status_from_string
// ---------------------------------------------------------------------------

pub fn status_from_string_running_test() {
  status_from_string("running") |> should.equal(Running)
}

pub fn status_from_string_completed_test() {
  status_from_string("completed") |> should.equal(Completed)
}

pub fn status_from_string_failed_test() {
  status_from_string("failed") |> should.equal(Failed)
}

pub fn status_from_string_timed_out_test() {
  status_from_string("timed_out") |> should.equal(TimedOut)
}

pub fn status_from_string_paused_test() {
  status_from_string("paused") |> should.equal(Paused)
}

pub fn status_from_string_unknown_defaults_to_paused_test() {
  status_from_string("unknown_xyz") |> should.equal(Paused)
}

// ---------------------------------------------------------------------------
// event_to_json
// ---------------------------------------------------------------------------

pub fn event_to_json_contains_event_type_test() {
  let e =
    WorkflowEvent(
      event_type: "activity_completed",
      activity_name: "send_email",
      timestamp: "2026-04-17T10:00:00Z",
      duration_ms: 42,
      output: "ok",
    )
  event_to_json(e) |> string.contains("activity_completed") |> should.be_true()
}

pub fn event_to_json_contains_activity_name_test() {
  let e =
    WorkflowEvent(
      event_type: "started",
      activity_name: "fetch_data",
      timestamp: "2026-04-17T10:00:00Z",
      duration_ms: 10,
      output: "",
    )
  event_to_json(e) |> string.contains("fetch_data") |> should.be_true()
}

pub fn event_to_json_contains_duration_ms_test() {
  let e =
    WorkflowEvent(
      event_type: "completed",
      activity_name: "process",
      timestamp: "2026-04-17T10:00:00Z",
      duration_ms: 123,
      output: "done",
    )
  event_to_json(e) |> string.contains("123") |> should.be_true()
}

pub fn event_to_json_contains_timestamp_test() {
  let e =
    WorkflowEvent(
      event_type: "started",
      activity_name: "init",
      timestamp: "2026-04-17T10:00:00Z",
      duration_ms: 0,
      output: "",
    )
  event_to_json(e)
  |> string.contains("2026-04-17T10:00:00Z")
  |> should.be_true()
}

// ---------------------------------------------------------------------------
// run_to_json
// ---------------------------------------------------------------------------

pub fn run_to_json_contains_workflow_id_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-001",
      run_id: "run-abc",
      status: Running,
      workflow_type: "deploy_pipeline",
      started_at: "2026-04-17T09:00:00Z",
      events: [],
    )
  run_to_json(run) |> string.contains("wf-001") |> should.be_true()
}

pub fn run_to_json_contains_status_string_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-002",
      run_id: "run-xyz",
      status: Completed,
      workflow_type: "health_check",
      started_at: "2026-04-17T08:00:00Z",
      events: [],
    )
  run_to_json(run) |> string.contains("completed") |> should.be_true()
}

pub fn run_to_json_contains_workflow_type_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-003",
      run_id: "run-def",
      status: Failed,
      workflow_type: "ooda_cycle",
      started_at: "2026-04-17T07:00:00Z",
      events: [],
    )
  run_to_json(run) |> string.contains("ooda_cycle") |> should.be_true()
}

pub fn run_to_json_contains_events_array_test() {
  let e =
    WorkflowEvent(
      event_type: "activity_completed",
      activity_name: "check",
      timestamp: "2026-04-17T09:01:00Z",
      duration_ms: 5,
      output: "ok",
    )
  let run =
    WorkflowRun(
      workflow_id: "wf-004",
      run_id: "run-ghi",
      status: Completed,
      workflow_type: "check",
      started_at: "2026-04-17T09:00:00Z",
      events: [e],
    )
  run_to_json(run) |> string.contains("activity_completed") |> should.be_true()
}

// ---------------------------------------------------------------------------
// schedule_to_json
// ---------------------------------------------------------------------------

pub fn schedule_to_json_contains_id_test() {
  let s =
    WorkflowSchedule(
      id: "sched-1",
      workflow_type: "daily_health_check",
      cron_expression: "0 6 * * *",
      last_run: "2026-04-17T06:00:00Z",
      next_run: "2026-04-18T06:00:00Z",
      enabled: True,
    )
  schedule_to_json(s) |> string.contains("sched-1") |> should.be_true()
}

pub fn schedule_to_json_contains_cron_test() {
  let s =
    WorkflowSchedule(
      id: "sched-2",
      workflow_type: "hourly_sync",
      cron_expression: "0 * * * *",
      last_run: "2026-04-17T10:00:00Z",
      next_run: "2026-04-17T11:00:00Z",
      enabled: True,
    )
  schedule_to_json(s) |> string.contains("0 * * * *") |> should.be_true()
}

pub fn schedule_to_json_enabled_true_test() {
  let s =
    WorkflowSchedule(
      id: "sched-3",
      workflow_type: "sync",
      cron_expression: "* * * * *",
      last_run: "",
      next_run: "",
      enabled: True,
    )
  schedule_to_json(s) |> string.contains("true") |> should.be_true()
}

pub fn schedule_to_json_enabled_false_test() {
  let s =
    WorkflowSchedule(
      id: "sched-4",
      workflow_type: "disabled_job",
      cron_expression: "0 0 * * *",
      last_run: "",
      next_run: "",
      enabled: False,
    )
  schedule_to_json(s) |> string.contains("false") |> should.be_true()
}

// ---------------------------------------------------------------------------
// count_by_status / summary
// ---------------------------------------------------------------------------

pub fn count_by_status_empty_list_test() {
  count_by_status([], Running) |> should.equal(0)
}

pub fn count_by_status_single_match_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-a",
      run_id: "r-a",
      status: Failed,
      workflow_type: "t",
      started_at: "",
      events: [],
    )
  count_by_status([run], Failed) |> should.equal(1)
}

pub fn count_by_status_no_match_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-b",
      run_id: "r-b",
      status: Completed,
      workflow_type: "t",
      started_at: "",
      events: [],
    )
  count_by_status([run], Running) |> should.equal(0)
}

pub fn summary_empty_list_has_zero_total_test() {
  summary([]) |> string.contains("\"total\":0") |> should.be_true()
}

pub fn summary_counts_running_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-c",
      run_id: "r-c",
      status: Running,
      workflow_type: "t",
      started_at: "",
      events: [],
    )
  summary([run]) |> string.contains("\"running\":1") |> should.be_true()
}

pub fn summary_counts_failed_test() {
  let run =
    WorkflowRun(
      workflow_id: "wf-d",
      run_id: "r-d",
      status: Failed,
      workflow_type: "t",
      started_at: "",
      events: [],
    )
  summary([run]) |> string.contains("\"failed\":1") |> should.be_true()
}

pub fn summary_total_is_sum_of_runs_test() {
  let mk = fn(id, st) {
    WorkflowRun(
      workflow_id: id,
      run_id: id,
      status: st,
      workflow_type: "t",
      started_at: "",
      events: [],
    )
  }
  let runs = [mk("1", Running), mk("2", Completed), mk("3", Failed)]
  summary(runs) |> string.contains("\"total\":3") |> should.be_true()
}

//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/fractal/l4_system</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-CNT-001, SC-OODA-001</stamp-controls></compliance></c3i-module>
////
//// L4 System: run monitor, step tracker, container health dashboard.

import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

/// AG-UI run state for monitoring.
pub type RunState {
  RunState(
    run_id: String,
    thread_id: String,
    agent_id: String,
    status: RunStatus,
    steps: List(StepState),
    started_at: Int,
    finished_at: Option(Int),
    error: Option(String),
  )
}

pub type RunStatus {
  Running
  Completed
  Failed
  Cancelled
}

pub type StepState {
  StepState(
    name: String,
    status: StepStatus,
    started_at: Int,
    finished_at: Option(Int),
  )
}

pub type StepStatus {
  StepRunning
  StepCompleted
  StepFailed
}

/// Run monitor — tracks all active and recent runs.
pub type RunMonitorState {
  RunMonitorState(
    active_runs: List(RunState),
    completed_runs: List(RunState),
    max_history: Int,
  )
}

pub fn initial_run_monitor() -> RunMonitorState {
  RunMonitorState(active_runs: [], completed_runs: [], max_history: 50)
}

pub fn start_run(
  state: RunMonitorState,
  run_id: String,
  thread_id: String,
  agent_id: String,
  timestamp: Int,
) -> RunMonitorState {
  let run =
    RunState(
      run_id: run_id,
      thread_id: thread_id,
      agent_id: agent_id,
      status: Running,
      steps: [],
      started_at: timestamp,
      finished_at: None,
      error: None,
    )
  RunMonitorState(..state, active_runs: [run, ..state.active_runs])
}

pub fn start_step(
  state: RunMonitorState,
  run_id: String,
  step_name: String,
  timestamp: Int,
) -> RunMonitorState {
  let step =
    StepState(
      name: step_name,
      status: StepRunning,
      started_at: timestamp,
      finished_at: None,
    )
  let active =
    list.map(state.active_runs, fn(r) {
      case r.run_id == run_id {
        True -> RunState(..r, steps: list.append(r.steps, [step]))
        False -> r
      }
    })
  RunMonitorState(..state, active_runs: active)
}

pub fn finish_step(
  state: RunMonitorState,
  run_id: String,
  step_name: String,
  timestamp: Int,
) -> RunMonitorState {
  let active =
    list.map(state.active_runs, fn(r) {
      case r.run_id == run_id {
        True ->
          RunState(
            ..r,
            steps: list.map(r.steps, fn(s) {
              case s.name == step_name {
                True ->
                  StepState(
                    ..s,
                    status: StepCompleted,
                    finished_at: Some(timestamp),
                  )
                False -> s
              }
            }),
          )
        False -> r
      }
    })
  RunMonitorState(..state, active_runs: active)
}

pub fn finish_run(
  state: RunMonitorState,
  run_id: String,
  timestamp: Int,
) -> RunMonitorState {
  let #(finished, remaining) =
    list.partition(state.active_runs, fn(r) { r.run_id == run_id })
  let completed_runs =
    list.map(finished, fn(r) {
      RunState(..r, status: Completed, finished_at: Some(timestamp))
    })
  let history =
    list.append(completed_runs, state.completed_runs)
    |> list.take(state.max_history)
  RunMonitorState(
    active_runs: remaining,
    completed_runs: history,
    max_history: state.max_history,
  )
}

pub fn fail_run(
  state: RunMonitorState,
  run_id: String,
  error: String,
  timestamp: Int,
) -> RunMonitorState {
  let #(failed, remaining) =
    list.partition(state.active_runs, fn(r) { r.run_id == run_id })
  let completed_runs =
    list.map(failed, fn(r) {
      RunState(
        ..r,
        status: Failed,
        finished_at: Some(timestamp),
        error: Some(error),
      )
    })
  let history =
    list.append(completed_runs, state.completed_runs)
    |> list.take(state.max_history)
  RunMonitorState(
    active_runs: remaining,
    completed_runs: history,
    max_history: state.max_history,
  )
}

pub fn active_run_count(state: RunMonitorState) -> Int {
  list.length(state.active_runs)
}

pub fn run_to_json(run: RunState) -> json.Json {
  json.object([
    #("run_id", json.string(run.run_id)),
    #("agent_id", json.string(run.agent_id)),
    #(
      "status",
      json.string(case run.status {
        Running -> "running"
        Completed -> "completed"
        Failed -> "failed"
        Cancelled -> "cancelled"
      }),
    ),
    #("steps", json.int(list.length(run.steps))),
    #("started_at", json.int(run.started_at)),
  ])
}

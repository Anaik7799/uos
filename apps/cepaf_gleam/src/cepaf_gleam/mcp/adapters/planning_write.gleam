//// Pure transactional Sa-plan adapter. The OTP store owner must serialize execute
//// and commit its returned state before accepting the next call; stale snapshots
//// must never be committed independently by concurrent workers.

import cepaf_gleam/mcp/admission.{
  type TaskLifecycleState, type ValidatedCall, TaskAvailable, TaskCompleted,
  TaskExecuting,
}
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/evidence
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types.{type Outcome, NonRetryable, Refused, ToolError}
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/option.{Some}

pub type Task {
  Task(state: TaskLifecycleState, worker: String, attempt: Int)
}

pub type PlanningWriteStore {
  PlanningWriteStore(
    tasks: Dict(#(String, String), Task),
    jobs: Dict(String, String),
    workflows: Dict(String, String),
    bridge_submissions: Dict(String, String),
  )
}

pub fn new_store() -> PlanningWriteStore {
  PlanningWriteStore(dict.new(), dict.new(), dict.new(), dict.new())
}

fn arg(call: ValidatedCall, key: String) -> String {
  case dict.get(call.arguments, key) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

fn refuse(
  store: PlanningWriteStore,
  code: String,
) -> #(Outcome, PlanningWriteStore) {
  #(
    Refused(ToolError(code, "Sa-plan transaction refused", NonRetryable)),
    store,
  )
}

fn success(
  store: PlanningWriteStore,
  call: ValidatedCall,
  value: String,
) -> #(Outcome, PlanningWriteStore) {
  #(
    evidence.classify_backend_payload(
      call.spec.route,
      call.spec.name,
      json.to_string(json.object([#("result", json.string(value))])),
      candidate_id.current(),
    ),
    store,
  )
}

pub fn execute(
  store: PlanningWriteStore,
  call: ValidatedCall,
) -> #(Outcome, PlanningWriteStore) {
  let actor = principal.actor_id(call.principal)
  let key = #(arg(call, "plan_id"), arg(call, "task_id"))
  case actor == "" {
    True -> refuse(store, "MISSING_AUTHENTICATED_WORKER")
    False -> {
      case call.spec.name {
        "plan_add" ->
          case key.0 == "" || key.1 == "" {
            True -> refuse(store, "MISSING_TASK_ID")
            False ->
              case dict.has_key(store.tasks, key) {
                True -> refuse(store, "TASK_ALREADY_EXISTS")
                False ->
                  success(
                    PlanningWriteStore(
                      ..store,
                      tasks: dict.insert(
                        store.tasks,
                        key,
                        Task(TaskAvailable, "", 0),
                      ),
                    ),
                    call,
                    "available",
                  )
              }
          }
        "sa_task_claim" | "sa_task_complete" | "plan_update" ->
          case dict.get(store.tasks, key) {
            Error(_) -> refuse(store, "UNKNOWN_TASK_ID")
            Ok(task) -> transition(store, call, key, task, actor)
          }
        "sa_job_enqueue" -> {
          let id = arg(call, "job_id")
          case id == "" {
            True -> refuse(store, "MISSING_JOB_ID")
            False ->
              case dict.has_key(store.jobs, id) {
                True -> refuse(store, "JOB_ALREADY_EXISTS")
                False ->
                  success(
                    PlanningWriteStore(
                      ..store,
                      jobs: dict.insert(store.jobs, id, actor),
                    ),
                    call,
                    id,
                  )
              }
          }
        }
        "sa_workflow_start" -> {
          let id = arg(call, "workflow_id")
          case id == "" {
            True -> refuse(store, "MISSING_WORKFLOW_ID")
            False ->
              case dict.has_key(store.workflows, id) {
                True -> refuse(store, "WORKFLOW_ALREADY_EXISTS")
                False ->
                  success(
                    PlanningWriteStore(
                      ..store,
                      workflows: dict.insert(store.workflows, id, actor),
                    ),
                    call,
                    id,
                  )
              }
          }
        }
        "sa_bridge_submit" -> {
          let id = arg(call, "bridge_key")
          case id == "" {
            True -> refuse(store, "MISSING_BRIDGE_KEY")
            False ->
              case dict.get(store.bridge_submissions, id) {
                Ok(job_id) -> success(store, call, job_id)
                Error(_) -> {
                  let job_id = "bridge:" <> id
                  case dict.has_key(store.jobs, job_id) {
                    True -> refuse(store, "JOB_ALREADY_EXISTS")
                    False ->
                      success(
                        PlanningWriteStore(
                          ..store,
                          jobs: dict.insert(store.jobs, job_id, actor),
                          bridge_submissions: dict.insert(
                            store.bridge_submissions,
                            id,
                            job_id,
                          ),
                        ),
                        call,
                        job_id,
                      )
                  }
                }
              }
          }
        }
        _ -> refuse(store, "UNSUPPORTED_PLANNING_WRITE_TOOL")
      }
    }
  }
}

fn transition(
  store: PlanningWriteStore,
  call: ValidatedCall,
  key: #(String, String),
  task: Task,
  actor: String,
) -> #(Outcome, PlanningWriteStore) {
  let target = case call.spec.name {
    "sa_task_claim" -> "executing"
    "sa_task_complete" -> "completed"
    _ -> arg(call, "state")
  }
  case target, task.state {
    "executing", TaskAvailable -> {
      let claimed = Task(TaskExecuting, actor, task.attempt + 1)
      success(
        PlanningWriteStore(
          ..store,
          tasks: dict.insert(store.tasks, key, claimed),
        ),
        call,
        "executing",
      )
    }
    "executing", _ -> refuse(store, "TASK_ALREADY_CLAIMED")
    "completed", TaskExecuting -> {
      // The target attempt is mandatory; the admission attempt belongs to the
      // authority task and is not a substitute for the target's fencing token.
      case int.parse(arg(call, "attempt")) {
        Ok(attempt) if attempt == task.attempt ->
          case actor == task.worker {
            False -> refuse(store, "PRINCIPAL_WORKER_MISMATCH")
            True ->
              case call.attempt {
                Some(fence) if fence != attempt ->
                  refuse(store, "STALE_ATTEMPT_FENCE")
                _ ->
                  success(
                    PlanningWriteStore(
                      ..store,
                      tasks: dict.insert(
                        store.tasks,
                        key,
                        Task(..task, state: TaskCompleted),
                      ),
                    ),
                    call,
                    "completed",
                  )
              }
          }
        _ -> refuse(store, "STALE_ATTEMPT_FENCE")
      }
    }
    _, _ -> refuse(store, "INVALID_STATE_TRANSITION")
  }
}

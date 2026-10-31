//// Pure transactional Sa-plan adapter. The OTP store owner must serialize execute
//// and commit its returned state before accepting the next call; stale snapshots
//// must never be committed independently by concurrent workers.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/adapters/canonical_planning_store as canonical
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
import gleam/list
import gleam/option.{type Option, Some}
import gleam/string
import simplifile

pub type Task {
  Task(state: TaskLifecycleState, worker: String, attempt: Int)
  /// Local hold preserves the last canonical lifecycle state and its fence.
  /// It is never represented as completed or as a fresh claim.
  HeldTask(state: TaskLifecycleState, worker: String, attempt: Int)
  /// Explicit canonical backend configuration. Dispatch inspects this variant,
  /// never an encoded task identifier, and independently requires canonical
  /// storage for an actual Sa-plan workspace if configuration is lost.
  CanonicalBackendTask(
    state: TaskLifecycleState,
    worker: String,
    attempt: Int,
    backend: canonical.WriteBackend,
  )
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

pub fn new_canonical_store(root: String) -> PlanningWriteStore {
  new_canonical_store_with_db(
    root,
    root <> "/var/sa-plan/uos.sqlite3",
    canonical.resolve_sqlite_binary(root),
  )
}

pub fn new_canonical_store_with_db(
  root: String,
  db_path: String,
  sqlite_bin: Option(String),
) -> PlanningWriteStore {
  PlanningWriteStore(
    dict.from_list([
      #(
        #("", ""),
        CanonicalBackendTask(
          TaskAvailable,
          "",
          0,
          canonical.CanonicalSqliteWriteBackend(root, db_path, sqlite_bin),
        ),
      ),
    ]),
    dict.new(),
    dict.new(),
    dict.new(),
  )
}

fn arg(call: ValidatedCall, key: String) -> String {
  case dict.get(call.arguments, key) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

fn alias(call: ValidatedCall, first: String, second: String) -> String {
  case arg(call, first) {
    "" -> arg(call, second)
    value -> value
  }
}

fn plan_id(call: ValidatedCall) -> String {
  case alias(call, "plan_id", "plan") {
    "" ->
      case arg(call, "title") != "" || arg(call, "id") != "" {
        True -> "default"
        False -> ""
      }
    value -> value
  }
}

fn task_id(call: ValidatedCall) -> String {
  case alias(call, "task_id", "id") {
    "" ->
      case string.trim(arg(call, "title")) {
        "" -> ""
        title -> "title-" <> files_digest(title)
      }
    value -> value
  }
}

fn files_digest(title: String) -> String {
  // A deterministic content-derived slug avoids process/time-dependent IDs.
  string.slice(files.digest(title), 0, 16)
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
      json.to_string(
        json.object([
          #("result", json.string(value)),
          ..list.filter_map(
            ["title", "priority", "name", "queue", "args", "kind", "input"],
            fn(key) {
              case dict.get(call.arguments, key) {
                Ok(value) -> Ok(#(key, json.string(value)))
                Error(_) -> Error(Nil)
              }
            },
          )
        ]),
      ),
      candidate_id.current(),
    ),
    store,
  )
}

pub fn execute(
  store: PlanningWriteStore,
  call: ValidatedCall,
) -> #(Outcome, PlanningWriteStore) {
  case canonical.arguments_bounded(call) {
    False -> refuse(store, "INVALID_ARGUMENT")
    True -> execute_bounded(store, call)
  }
}

fn execute_bounded(
  store: PlanningWriteStore,
  call: ValidatedCall,
) -> #(Outcome, PlanningWriteStore) {
  let backends =
    dict.values(store.tasks)
    |> list.filter_map(fn(task) {
      case task {
        CanonicalBackendTask(backend: backend, ..) -> Ok(backend)
        _ -> Error(Nil)
      }
    })
  case backends {
    [backend] ->
      case canonical.execute(backend, call, plan_id(call), task_id(call)) {
        Ok(value) -> success(store, call, value)
        Error(error) -> #(Refused(error), store)
      }
    [] ->
      case
        simplifile.is_directory(
          principal.workspace_root(call.principal) <> "/var/sa-plan",
        )
      {
        Ok(False) -> execute_in_memory(store, call)
        _ -> refuse(store, "SA_PLAN_STORE_UNAVAILABLE")
      }
    _ -> refuse(store, "SA_PLAN_STORE_UNAVAILABLE")
  }
}

fn execute_in_memory(
  store: PlanningWriteStore,
  call: ValidatedCall,
) -> #(Outcome, PlanningWriteStore) {
  let actor = principal.actor_id(call.principal)
  let key = #(plan_id(call), task_id(call))
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
          let id = alias(call, "job_id", "id")
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
          let id = alias(call, "workflow_id", "id")
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
          let id = alias(call, "bridge_key", "task")
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
    _ ->
      case alias(call, "state", "status") {
        "in_progress" -> "executing"
        "pending" -> "available"
        state -> state
      }
  }
  case task.state == TaskCompleted {
    True -> refuse(store, "COMPLETED_TASK_IMMUTABLE")
    False -> transition_owned(store, call, key, task, actor, target)
  }
}

fn transition_owned(
  store: PlanningWriteStore,
  call: ValidatedCall,
  key: #(String, String),
  task: Task,
  actor: String,
  target: String,
) -> #(Outcome, PlanningWriteStore) {
  case target, task {
    "blocked", Task(..)
    | "blocked", HeldTask(..)
    | "available", HeldTask(..)
    | "executing", HeldTask(..)
    -> {
      let requested = int.parse(arg(call, "attempt"))
      let fence_matches = case call.attempt {
        Some(fence) -> requested == Ok(fence)
        _ -> True
      }
      case
        task.state,
        task.worker == actor,
        requested == Ok(task.attempt) && fence_matches
      {
        TaskExecuting, True, True -> {
          let updated = case target {
            "blocked" -> HeldTask(task.state, task.worker, task.attempt)
            "executing" -> Task(TaskExecuting, actor, task.attempt)
            _ -> Task(TaskAvailable, "", task.attempt)
          }
          success(
            PlanningWriteStore(
              ..store,
              tasks: dict.insert(store.tasks, key, updated),
            ),
            call,
            target,
          )
        }
        TaskAvailable, _, _ -> refuse(store, "TASK_NOT_EXECUTING")
        _, False, _ -> refuse(store, "PRINCIPAL_WORKER_MISMATCH")
        _, _, _ -> refuse(store, "STALE_ATTEMPT_FENCE")
      }
    }
    "available", Task(state: TaskAvailable, ..) ->
      success(store, call, "available")
    _, HeldTask(..) -> refuse(store, "TASK_BLOCKED")
    _, Task(..) -> transition_active(store, call, key, task, actor, target)
    _, CanonicalBackendTask(..) -> refuse(store, "UNKNOWN_TASK_ID")
  }
}

fn transition_active(
  store: PlanningWriteStore,
  call: ValidatedCall,
  key: #(String, String),
  task: Task,
  actor: String,
  target: String,
) -> #(Outcome, PlanningWriteStore) {
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
                        Task(TaskCompleted, task.worker, task.attempt),
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

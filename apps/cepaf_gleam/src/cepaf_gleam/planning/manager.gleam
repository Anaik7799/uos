// STAMP: SC-PLAN-006, SC-FUNC-001
// AOR: AOR-PLAN-006
// Criticality: Level 2 (HIGH) - Task Management Logic
//
// This module provides business logic for managing tasks, including state
// transitions and searches. It acts as a bridge between the domain and
// the repository.

import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/db/sqlite
import cepaf_gleam/moz/client as moz_client
import cepaf_gleam/planning/domain.{
  type PlanningError, type Task, InvalidTransition, RemoteError, Task,
  TaskNotFound,
}
import cepaf_gleam/planning/parser
import cepaf_gleam/planning/repository
import cepaf_gleam/planning/task
import gleam/bit_array
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set

// =============================================================================
// Task Management Module (Manager)
// =============================================================================

/// Retrieves all tasks from the authoritative sa-plan-daemon via Zenoh MCP.
pub fn list_tasks_remote() -> Result(List(Task), PlanningError) {
  let moz_state = moz_client.new()
  case moz_client.send_query(moz_state, "plan", "list") {
    #(_, Ok(payload)) -> {
      case parse_mcp_task_list(payload) {
        Ok(tasks) -> Ok(tasks)
        Error(e) -> Error(RemoteError("JSON parse error: " <> e))
      }
    }
    #(_, Error(reason)) -> Error(RemoteError("MoZ query failed: " <> reason))
  }
}

fn parse_mcp_task_list(payload: String) -> Result(List(Task), String) {
  let task_decoder = {
    use id <- decode.field("id", decode.string)
    use title <- decode.field("title", decode.string)
    use status <- decode.field("status", decode.string)
    use priority <- decode.field("priority", decode.string)
    use parent_id <- decode.optional_field(
      "parent_id",
      None,
      decode.optional(decode.string),
    )
    use owner <- decode.optional_field(
      "owner",
      None,
      decode.optional(decode.string),
    )
    use created <- decode.field("created", decode.string)

    decode.success(Task(
      id: ids.task_id_from_string(id),
      title: case types.new_non_empty_string(title) {
        Ok(t) -> t
        Error(_) -> {
          let assert Ok(t) = types.new_non_empty_string("Untitled")
          t
        }
      },
      description: None,
      status: types.task_status_from_string(status),
      priority: types.priority_from_string(priority),
      created_at: created,
      updated_at: created,
      due_date: None,
      completed_at: None,
      assignee_id: case owner {
        Some(o) -> Some(ids.user_id_from_string(o))
        None -> None
      },
      project_id: None,
      sprint_id: None,
      parent_task_id: case parent_id {
        Some(p) -> Some(ids.task_id_from_string(p))
        None -> None
      },
      tags: set.new(),
      dependencies: set.new(),
      estimated_minutes: None,
      actual_minutes: None,
      version: 0,
    ))
  }

  let response_decoder = {
    use result <- decode.field("result", decode.list(task_decoder))
    decode.success(result)
  }

  case json.parse(from: payload, using: response_decoder) {
    Ok(tasks) -> Ok(tasks)
    Error(_) -> Error("Failed to decode MCP task list")
  }
}

/// Updates the status of a task, ensuring valid state transitions.
pub fn update_task_status(
  task_obj: Task,
  new_status: types.TaskStatus,
) -> Result(Task, PlanningError) {
  case task_obj.status, new_status {
    _, types.InProgress -> Ok(task.start(task_obj))
    _, types.Completed -> Ok(task.complete(task_obj, None))
    // Note: block() and unblock() would need to be added to task.gleam if needed
    // For now, we'll just set the status directly via a generic setter if it exists
    _, _ if task_obj.status == new_status -> Ok(task_obj)
    from, to -> Error(InvalidTransition(from, to))
  }
}

/// Finds a task in a list by its string ID.
pub fn find_task(tasks: List(Task), id: String) -> Result(Task, PlanningError) {
  list.find(tasks, fn(t) { ids.task_id_to_string(t.id) == id })
  |> result.map_error(fn(_) { TaskNotFound(id) })
}

// =============================================================================
// Repository Bridge Functions
// =============================================================================

/// Initializes the database schema.
pub fn init_db() -> Result(Nil, String) {
  repository.ensure_db_exists()
}

/// Saves or updates a task in the database.
pub fn upsert_task(task_obj: Task) -> Result(Int, String) {
  repository.save_task(task_obj)
}

/// Retrieves all tasks from the database (DuckDB).
pub fn list_tasks() -> Result(List(Task), String) {
  repository.get_all_tasks()
}

/// Retrieves all tasks from a specific SQLite database file.
/// Attempts list_tasks_remote() first to use authoritative daemon state.
pub fn list_tasks_sqlite(path: String) -> Result(List(Task), String) {
  // 1. Try remote authoritative state first (Centralized State Mandate)
  case list_tasks_remote() {
    Ok(tasks) -> Ok(tasks)
    Error(_) -> {
      // 2. Fallback to direct SQLite access (NIF)
      case sqlite.open(path) {
        Ok(conn) -> {
          let res = repository.get_all_tasks_sqlite(conn)
          sqlite.close(conn)
          case res {
            Ok(tasks) -> Ok(tasks)
            Error(_) -> list_tasks_sqlite_cli(path)
          }
        }
        Error(_) -> list_tasks_sqlite_cli(path)
      }
    }
  }
}

@external(erlang, "cepaf_gleam_ffi", "os_cmd")
fn erl_os_cmd(cmd: String) -> Result(BitArray, String)

fn list_tasks_sqlite_cli(path: String) -> Result(List(Task), String) {
  let sql =
    "SELECT Id, Title, Status, Priority, Created, ParentId, Owner FROM Tasks"
  // Use default pipe separator, no header
  let cmd = "sqlite3 " <> path <> " \"" <> sql <> "\""
  case erl_os_cmd(cmd) {
    Ok(output_binary) -> {
      case bit_array.to_string(output_binary) {
        Ok(output_str) -> {
          let tasks = parser.parse_todolist_sqlite_output(output_str)
          Ok(tasks)
        }
        Error(_) -> Error("Failed to read sqlite3 output as UTF-8")
      }
    }
    Error(e) -> Error("os_cmd failed: " <> e)
  }
}

/// Retrieves a specific task by its strongly-typed ID.
pub fn get_task(id: ids.TaskId) -> Result(Task, String) {
  repository.get_task(id)
}

/// Updates a task's status remotely via the authoritative sa-plan-daemon.
pub fn update_task_remote(id: String, status: String) -> Result(Nil, String) {
  let moz_state = moz_client.new()
  let params =
    json.object([
      #("id", json.string(id)),
      #("status", json.string(status)),
    ])
  case moz_client.send_request(moz_state, "plan", "plan_update", params) {
    #(_, Ok(_)) -> Ok(Nil)
    #(_, Error(e)) -> Error("Remote update failed: " <> e)
  }
}

/// Synchronizes the PROJECT_TODOLIST.md file remotely via the daemon.
pub fn sync_todolist_remote() -> Result(Nil, String) {
  let moz_state = moz_client.new()
  case
    moz_client.send_request(moz_state, "plan", "plan_sync", json.object([]))
  {
    #(_, Ok(_)) -> Ok(Nil)
    #(_, Error(e)) -> Error("Remote sync failed: " <> e)
  }
}

/// Deletes a task by its string ID.
pub fn delete_task(id: String) -> Result(Int, String) {
  repository.delete_task(ids.task_id_from_string(id))
}

/// Deletes a task remotely via the authoritative sa-plan-daemon.
pub fn delete_task_remote(id: String) -> Result(Nil, String) {
  let moz_state = moz_client.new()
  let params = json.object([#("id", json.string(id))])
  case moz_client.send_request(moz_state, "plan", "plan_delete", params) {
    #(_, Ok(_)) -> Ok(Nil)
    #(_, Error(e)) -> Error("Remote delete failed: " <> e)
  }
}

/// Creates a new task with the given title and priority.
pub fn create_task(
  title: String,
  priority: types.Priority,
) -> Result(Task, String) {
  let input =
    domain.CreateTaskInput(
      title: title,
      description: None,
      priority: priority,
      due_date: None,
      project_id: None,
      parent_task_id: None,
      tags: set.new(),
      estimated_minutes: None,
    )
  task.create(input)
}

/// Creates a new task remotely via the authoritative sa-plan-daemon.
pub fn add_task_remote(
  title: String,
  priority: String,
) -> Result(String, String) {
  let moz_state = moz_client.new()
  let params =
    json.object([
      #("title", json.string(title)),
      #("priority", json.string(priority)),
    ])
  case moz_client.send_request(moz_state, "plan", "plan_add", params) {
    #(_, Ok(id)) -> Ok(id)
    #(_, Error(e)) -> Error("Remote add failed: " <> e)
  }
}

/// Dispatches a task for execution (placeholder).
pub fn dispatch_task(id: String) -> Result(Nil, String) {
  // Placeholder for task dispatching logic (SC-AGUI-001)
  io.println("🚀 Dispatching task: " <> id)
  Ok(Nil)
}

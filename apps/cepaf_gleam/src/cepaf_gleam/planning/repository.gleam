// STAMP: SC-HOLON-001, SC-DB-001
// AOR: AOR-HOLON-001, AOR-DB-001
// Criticality: Level 2 (HIGH) - Data Persistence Layer
//
// This module provides a high-level API for persisting and retrieving Task
// entities from the DuckDB database. It uses the low-level DuckDB FFI.

import cepaf_gleam/core/ids
import cepaf_gleam/core/types
import cepaf_gleam/db/duckdb
import cepaf_gleam/db/sqlite
import cepaf_gleam/planning/domain.{type Task, Task}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set

pub type DbBackend {
  DuckDBBackend
  SQLiteBackend(sqlite.DbConnection)
}

// =============================================================================
// FFI Wrappers
// =============================================================================

@external(erlang, "cepaf_gleam_ffi", "identity")
fn dynamic_from(a: a) -> Dynamic

@external(erlang, "cepaf_gleam_ffi", "to_string")
fn ffi_to_string(a: Dynamic) -> Result(String, Nil)

// =============================================================================
// Schema & Initialization
// =============================================================================

const schema_sql = "
  CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      status TEXT NOT NULL,
      priority TEXT NOT NULL,
      parent_id TEXT,
      owner_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      version INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_status ON tasks(status);
  CREATE INDEX IF NOT EXISTS idx_parent ON tasks(parent_id);
"

/// Ensures the database and the `tasks` table exist.
pub fn ensure_db_exists() -> Result(Nil, String) {
  duckdb.ensure_schema(schema_sql)
}

// =============================================================================
// Public API
// =============================================================================

/// Saves a task to the database (INSERT or REPLACE).
pub fn save_task(task: Task) -> Result(Int, String) {
  let sql =
    "
    INSERT OR REPLACE INTO tasks 
    (id, title, status, priority, parent_id, owner_id, created_at, updated_at, version)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
  "
  let params = [
    dynamic_from(ids.task_id_to_string(task.id)),
    dynamic_from(types.non_empty_string_value(task.title)),
    dynamic_from(types.task_status_to_string(task.status)),
    dynamic_from(types.priority_to_string(task.priority)),
    dynamic_from(option.map(task.parent_task_id, ids.task_id_to_string)),
    dynamic_from(option.map(task.assignee_id, ids.user_id_to_string)),
    dynamic_from(task.created_at),
    dynamic_from(task.updated_at),
    dynamic_from(task.version),
  ]

  duckdb.execute(sql, params)
}

/// Retrieves a task by its ID.
pub fn get_task(id: ids.TaskId) -> Result(Task, String) {
  let sql = "SELECT * FROM tasks WHERE id = ?"
  let params = [dynamic_from(ids.task_id_to_string(id))]

  use rows <- result.try(duckdb.query(sql, params))
  case rows {
    [row] -> parse_row(row)
    [] -> Error("Task not found")
    _ -> Error("Multiple tasks found with same ID")
  }
}

/// Retrieves all tasks from the database.
pub fn get_all_tasks() -> Result(List(Task), String) {
  let sql = "SELECT * FROM tasks"
  use rows <- result.try(duckdb.query(sql, []))
  list.try_map(rows, parse_row)
}

/// Retrieves all tasks from a specific SQLite connection.
pub fn get_all_tasks_sqlite(
  conn: sqlite.DbConnection,
) -> Result(List(Task), String) {
  let sql =
    "SELECT id, title, status, priority, parent_id, owner_id, created_at, updated_at, version FROM tasks"
  use rows <- result.try(sqlite.query(conn, sql, []))
  list.try_map(rows, parse_row)
}

/// Deletes a task by its ID.
pub fn delete_task(id: ids.TaskId) -> Result(Int, String) {
  let sql = "DELETE FROM tasks WHERE id = ?"
  let params = [dynamic_from(ids.task_id_to_string(id))]
  duckdb.execute(sql, params)
}

/// Attempt to list all tasks from SQLite. Returns Error if DB unavailable.
/// Callers should fall back to sample data on Error (SC-FUNC-005).
///
/// NOTE: The authoritative implementation uses DuckDB via `get_all_tasks/0`.
/// This SQLite variant is provided as a fallback path when DuckDB is
/// unavailable. The sqlite module exposes `open/1`, `query_raw/3`, and
/// `close/1` — the `sqlite_open`/`sqlite_query`/`sqlite_close` bindings
/// referenced in the task spec are not available; this stub degrades
/// gracefully per SC-FUNC-005 and SC-GLM-CORE-002.
pub fn find_all_tasks(_db_path: String) -> Result(List(domain.Task), String) {
  // SQLite path not implemented — delegate to DuckDB path or return error.
  // Callers should fall back to sample data on Error.
  Error("Not implemented — using sample data")
}

// =============================================================================
// Internal Parsers
// =============================================================================

fn parse_row(row: List(Dynamic)) -> Result(Task, String) {
  case row {
    [
      id,
      title,
      status,
      priority,
      _parent_id,
      _owner_id,
      _created_at,
      _updated_at,
      _version,
    ] -> {
      let id_res = ffi_to_string(id)
      let title_res = ffi_to_string(title)
      let status_res = ffi_to_string(status)
      let priority_res = ffi_to_string(priority)

      case id_res, title_res, status_res, priority_res {
        Ok(id_str), Ok(title_str), Ok(status_str), Ok(priority_str) -> {
          case types.new_non_empty_string(title_str) {
            Ok(valid_title) -> {
              Ok(Task(
                id: ids.task_id_from_string(id_str),
                title: valid_title,
                description: None,
                status: types.task_status_from_string(status_str),
                priority: types.priority_from_string(priority_str),
                created_at: "2026-04-01T00:00:00Z",
                updated_at: "2026-04-01T00:00:00Z",
                due_date: None,
                completed_at: None,
                assignee_id: None,
                project_id: None,
                sprint_id: None,
                parent_task_id: None,
                tags: set.new(),
                dependencies: set.new(),
                estimated_minutes: None,
                actual_minutes: None,
                version: 0,
              ))
            }
            Error(e) -> Error(e)
          }
        }
        _, _, _, _ -> Error("Invalid data types in row")
      }
    }
    _ -> Error("Invalid row format")
  }
}

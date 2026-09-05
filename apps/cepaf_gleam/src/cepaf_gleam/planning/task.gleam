import cepaf_gleam/core/ids.{type TaskId}
import cepaf_gleam/core/types

import cepaf_gleam/planning/domain.{type CreateTaskInput, type Task, Task}
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set

// =============================================================================
// Task Domain Types and Logic (Ported from F# Task.fs)
// =============================================================================

// Note: For simplicity in this port, TaskItem is directly translated from F#.
// In a real project, this might be further refined or abstracted.
pub type TaskItem {
  TaskItem(
    id: String,
    title: String,
    status: types.TaskStatus,
    priority: types.Priority,
    parent_id: Option(String),
    owner: Option(String),
    created: String,
    // ISO8601 placeholder
    raw_lines: List(String),
  )
}

// =============================================================================
// Task Module - Functions for manipulating Tasks
// =============================================================================

// Note: A proper timestamp function would be used here in a real scenario.
// For now, we'll use a placeholder.
fn now() -> String {
  "2026-04-01T12:00:00Z"
}

/// Create a new task from an input record.
pub fn create(input: CreateTaskInput) -> Result(Task, String) {
  use title <- result.try(types.new_non_empty_string(input.title))
  let current_time = now()
  Ok(Task(
    id: ids.new_task_id(),
    title: title,
    description: input.description,
    status: types.Pending,
    priority: input.priority,
    created_at: current_time,
    updated_at: current_time,
    due_date: input.due_date,
    completed_at: None,
    assignee_id: None,
    project_id: input.project_id,
    sprint_id: None,
    parent_task_id: input.parent_task_id,
    tags: input.tags,
    dependencies: set.new(),
    estimated_minutes: input.estimated_minutes,
    actual_minutes: None,
    version: 0,
  ))
}

// Private helper to handle common update logic.
fn update(task: Task, f: fn(Task) -> Task) -> Task {
  let updated_task = f(task)
  Task(..updated_task, updated_at: now(), version: task.version + 1)
}

/// Change the task's title.
pub fn set_title(task: Task, title: types.NonEmptyString) -> Task {
  update(task, fn(t) { Task(..t, title: title) })
}

/// Change the task's status.
pub fn set_status(task: Task, status: types.TaskStatus) -> Task {
  let updated_task = update(task, fn(t) { Task(..t, status: status) })
  case status {
    types.Completed -> Task(..updated_task, completed_at: Some(now()))
    _ -> updated_task
  }
}

/// Change the task's priority.
pub fn set_priority(task: Task, priority: types.Priority) -> Task {
  update(task, fn(t) { Task(..t, priority: priority) })
}

/// Assign the task to a user.
pub fn assign(task: Task, assignee: Option(ids.UserId)) -> Task {
  update(task, fn(t) { Task(..t, assignee_id: assignee) })
}

/// Add a tag to the task.
pub fn add_tag(task: Task, tag: String) -> Task {
  update(task, fn(t) { Task(..t, tags: set.insert(t.tags, tag)) })
}

/// Add a dependency to the task.
pub fn add_dependency(task: Task, dependency: TaskId) -> Task {
  update(task, fn(t) {
    Task(..t, dependencies: set.insert(t.dependencies, dependency))
  })
}

// === Higher-level business logic ===

/// Mark a task as started.
pub fn start(task: Task) -> Task {
  set_status(task, types.InProgress)
}

/// Mark a task as completed.
pub fn complete(task: Task, actual_minutes: Option(Int)) -> Task {
  task
  |> set_status(types.Completed)
  |> update(fn(t) { Task(..t, actual_minutes: actual_minutes) })
}

// === Query helpers ===

/// Check if a task is complete.
pub fn is_complete(task: Task) -> Bool {
  task.status == types.Completed
}

/// Get the task's title as a string.
pub fn get_title(task: Task) -> String {
  types.non_empty_string_value(task.title)
}

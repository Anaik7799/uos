// STAMP: SC-PLAN-005, SC-FUNC-001
// AOR: AOR-PLAN-005
// Criticality: Level 1 (CRITICAL) - Foundation
//
// This module defines the core domain entities for the planning system.
// It is kept minimal to avoid circular dependencies.

import cepaf_gleam/core/ids.{
  type ProjectId, type SprintId, type TaskId, type UserId,
}
import cepaf_gleam/core/types.{
  type NonEmptyString, type Priority, type TaskStatus,
}
import gleam/option.{type Option}
import gleam/set.{type Set}

/// Represents a task in the system.
pub type Task {
  Task(
    id: TaskId,
    title: NonEmptyString,
    description: Option(String),
    status: TaskStatus,
    priority: Priority,
    created_at: String,
    updated_at: String,
    due_date: Option(String),
    completed_at: Option(String),
    assignee_id: Option(UserId),
    project_id: Option(ProjectId),
    sprint_id: Option(SprintId),
    parent_task_id: Option(TaskId),
    tags: Set(String),
    dependencies: Set(TaskId),
    estimated_minutes: Option(Int),
    actual_minutes: Option(Int),
    version: Int,
  )
}

/// Input data for creating a new task.
pub type CreateTaskInput {
  CreateTaskInput(
    title: String,
    description: Option(String),
    priority: Priority,
    due_date: Option(String),
    project_id: Option(ProjectId),
    parent_task_id: Option(TaskId),
    tags: Set(String),
    estimated_minutes: Option(Int),
  )
}

/// Represents errors that can occur in the planning system.
pub type PlanningError {
  InvalidTransition(from: TaskStatus, to: TaskStatus)
  TaskNotFound(id: String)
  DatabaseError(reason: String)
  ValidationError(message: String)
  RemoteError(reason: String)
}

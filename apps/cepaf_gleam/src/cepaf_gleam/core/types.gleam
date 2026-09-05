// STAMP: SC-PLAN-001, SC-FUNC-001
// AOR: AOR-PLAN-001
// Criticality: Level 1 (CRITICAL) - Foundation
//
// This file contains the core fundamental types for the Indrajaal system,
// ported from the F# CEPAF codebase.

import gleam/option.{type Option}
import gleam/string

// =============================================================================
// Core Wrapper Types (Smart Constructors)
// =============================================================================

pub type Timestamp =
  String

/// A string that is guaranteed to be not empty or whitespace.
pub opaque type NonEmptyString {
  NonEmptyString(String)
}

pub fn new_non_empty_string(value: String) -> Result(NonEmptyString, String) {
  case string.trim(value) == "" {
    True -> Error("String cannot be empty or whitespace")
    False -> Ok(NonEmptyString(value))
  }
}

pub fn non_empty_string_value(nes: NonEmptyString) -> String {
  let NonEmptyString(value) = nes
  value
}

/// An integer that is guaranteed to be positive (> 0).
pub opaque type PositiveInt {
  PositiveInt(Int)
}

pub fn new_positive_int(value: Int) -> Result(PositiveInt, String) {
  case value > 0 {
    True -> Ok(PositiveInt(value))
    False -> Error("Integer must be positive (> 0)")
  }
}

/// A floating point number guaranteed to be between 0.0 and 1.0.
pub opaque type UnitInterval {
  UnitInterval(Float)
}

pub fn new_unit_interval(value: Float) -> Result(UnitInterval, String) {
  case value >=. 0.0 && value <=. 1.0 {
    True -> Ok(UnitInterval(value))
    False -> Error("Value must be between 0.0 and 1.0")
  }
}

// =============================================================================
// Domain Enum Types
// =============================================================================

/// Represents the criticality of a task.
pub type Priority {
  P0Critical
  P1High
  P2Medium
  P3Low
  P4Minimal
  UnknownPriority(String)
}

pub fn priority_to_string(priority: Priority) -> String {
  case priority {
    P0Critical -> "P0"
    P1High -> "P1"
    P2Medium -> "P2"
    P3Low -> "P3"
    P4Minimal -> "P4"
    UnknownPriority(s) -> s
  }
}

pub fn priority_from_string(s: String) -> Priority {
  case string.uppercase(string.trim(s)) {
    "P0" -> P0Critical
    "P1" -> P1High
    "P2" -> P2Medium
    "P3" -> P3Low
    "P4" -> P4Minimal
    _ -> UnknownPriority(s)
  }
}

/// Represents the lifecycle status of a task.
pub type TaskStatus {
  Pending
  InProgress
  Completed
  Blocked
  UnknownStatus(String)
}

pub fn task_status_to_string(status: TaskStatus) -> String {
  case status {
    Pending -> "pending"
    InProgress -> "in_progress"
    Completed -> "completed"
    Blocked -> "blocked"
    UnknownStatus(s) -> s
  }
}

pub fn task_status_from_string(s: String) -> TaskStatus {
  case string.lowercase(string.trim(s)) {
    "pending" -> Pending
    "in_progress" -> InProgress
    "completed" -> Completed
    "blocked" -> Blocked
    _ -> UnknownStatus(s)
  }
}

// =============================================================================
// Record Types
// =============================================================================

/// Represents a semantic version number.
pub type SemanticVersion {
  SemanticVersion(
    major: Int,
    minor: Int,
    patch: Int,
    prerelease: Option(String),
  )
}

/// Represents a structured domain error.
pub type DomainError {
  DomainError(
    code: String,
    message: String,
    context: List(#(String, String)),
    timestamp: String,
    inner_error: Option(Box(DomainError)),
  )
}

// The `Box` type is used to enable recursive data structures.
pub type Box(a) {
  Box(a)
}

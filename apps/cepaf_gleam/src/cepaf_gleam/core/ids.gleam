// STAMP: SC-PLAN-002
// AOR: AOR-PLAN-002
// Criticality: Level 1 (CRITICAL) - Foundation
//
// This module provides strongly-typed identifiers for the Indrajaal system.
// The generation logic uses a secure random byte generator with hex encoding.

import gleam/crypto
import gleam/int
import gleam/list
import gleam/result
import gleam/string

// --- Private Helpers ---

const hex_chars = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
]

// Converts a single byte (as an Int) to a 2-character hex string.
fn byte_to_hex(byte: Int) -> String {
  let high_nibble = int.bitwise_and(int.bitwise_shift_right(byte, 4), 0x0F)
  let low_nibble = int.bitwise_and(byte, 0x0F)

  let high_char =
    list.drop(hex_chars, high_nibble)
    |> list.first
    |> result.unwrap(or: "0")

  let low_char =
    list.drop(hex_chars, low_nibble)
    |> list.first
    |> result.unwrap(or: "0")

  high_char <> low_char
}

// Recursively builds a list of byte values from a bit array.
fn bit_array_to_byte_list_acc(bits: BitArray, acc: List(Int)) -> List(Int) {
  case bits {
    <<byte:8, rest:bits>> -> bit_array_to_byte_list_acc(rest, [byte, ..acc])
    <<>> -> list.reverse(acc)
    // Handle non-byte-aligned bit arrays by ignoring remaining bits
    _ -> list.reverse(acc)
  }
}

// Generates a cryptographically secure random hex string of a given byte length.
// The final string length will be 2 * byte_length.
fn random_hex_string(byte_length: Int) -> String {
  crypto.strong_random_bytes(byte_length)
  |> bit_array_to_byte_list_acc([])
  |> list.map(byte_to_hex)
  |> string.join(with: "")
}

// --- ID Type Definitions ---

pub opaque type TaskId {
  TaskId(String)
}

/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="surjective" loss="clr-guid-semantics">
///     F# `System.Guid.NewGuid()` ↠ `random_hex_string(13)`
///   </morphism>
///   <formal-proof>
///     <P> System has entropy </P>
///     <C> new_task_id() </C>
///     <Q> Returns a cryptographically random TaskId of 26 chars </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn new_task_id() -> TaskId {
  // 13 bytes * 2 = 26 chars, same length as ULID
  TaskId(random_hex_string(13))
}

pub fn new_hierarchical_task_id(parent: TaskId, index: Int) -> TaskId {
  let TaskId(parent_str) = parent
  TaskId(parent_str <> "." <> int.to_string(index))
}

pub fn new_root_task_id(index: Int) -> TaskId {
  TaskId(int.to_string(index))
}

pub fn task_id_to_string(id: TaskId) -> String {
  let TaskId(value) = id
  value
}

pub fn task_id_from_string(s: String) -> TaskId {
  TaskId(s)
}

pub opaque type ProjectId {
  ProjectId(String)
}

pub fn new_project_id() -> ProjectId {
  ProjectId(random_hex_string(13))
}

pub fn project_id_to_string(id: ProjectId) -> String {
  let ProjectId(value) = id
  value
}

pub fn project_id_from_string(s: String) -> ProjectId {
  ProjectId(s)
}

pub opaque type SprintId {
  SprintId(String)
}

pub fn new_sprint_id() -> SprintId {
  SprintId(random_hex_string(13))
}

pub fn sprint_id_to_string(id: SprintId) -> String {
  let SprintId(value) = id
  value
}

pub fn sprint_id_from_string(s: String) -> SprintId {
  SprintId(s)
}

pub opaque type UserId {
  UserId(String)
}

pub fn new_user_id() -> UserId {
  UserId(random_hex_string(13))
}

pub fn user_id_to_string(id: UserId) -> String {
  let UserId(value) = id
  value
}

pub fn user_id_from_string(s: String) -> UserId {
  UserId(s)
}

pub opaque type HolonId {
  HolonId(String)
}

pub fn new_holon_id() -> HolonId {
  HolonId(random_hex_string(13))
}

pub fn holon_id_to_string(id: HolonId) -> String {
  let HolonId(value) = id
  value
}

pub fn holon_id_from_string(s: String) -> HolonId {
  HolonId(s)
}

pub opaque type OodaCycleId {
  OodaCycleId(String)
}

pub fn new_ooda_cycle_id() -> OodaCycleId {
  OodaCycleId(random_hex_string(13))
}

pub fn ooda_cycle_id_to_string(id: OodaCycleId) -> String {
  let OodaCycleId(value) = id
  value
}

pub fn ooda_cycle_id_from_string(s: String) -> OodaCycleId {
  OodaCycleId(s)
}

pub opaque type EventId {
  EventId(String)
}

pub fn new_event_id() -> EventId {
  // 16 bytes * 2 = 32 chars, same as UUID
  EventId(random_hex_string(16))
}

pub fn event_id_to_string(id: EventId) -> String {
  let EventId(value) = id
  value
}

pub fn event_id_from_string(s: String) -> EventId {
  EventId(s)
}

pub opaque type CorrelationId {
  CorrelationId(String)
}

pub fn new_correlation_id() -> CorrelationId {
  CorrelationId(random_hex_string(16))
}

pub fn correlation_id_to_string(id: CorrelationId) -> String {
  let CorrelationId(value) = id
  value
}

pub fn correlation_id_from_string(s: String) -> CorrelationId {
  CorrelationId(s)
}

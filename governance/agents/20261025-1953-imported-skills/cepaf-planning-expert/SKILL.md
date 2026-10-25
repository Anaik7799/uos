---
name: cepaf-planning-expert
description: Domain-specific expert for the Indrajaal Planning and Task Management system. Use when porting F# Planning logic to Gleam, managing task lifecycles, parsing task markdown, or implementing high-assurance state transitions for the PROJECT_TODOLIST.md.
---
# CEPAF Planning Expert Skill
This skill provides expert guidance for implementing the Indrajaal Planning system in Gleam, ensuring that task management remains robust, validated, and highly available.
# Core Mandates
1.  **Immutability First**: Port the F# `Task` entity to a Gleam record, utilizing pure functions for all state transitions (e.g., `update_status`, `assign_agent`).
2.  **Strict Validation**: Use opaque types for `TaskId` and `NonEmptyString` to enforce domain invariants at the type level.
3.  **Persistence Symmetry**: Port the `DuckDBHub` actor-based architecture to Gleam, ensuring single-writer/multi-reader safety for all task operations.
4.  **Markdown Source of Truth**: Ensure that `PROJECT_TODOLIST.md` remains the authoritative human-readable source, with the Gleam orchestrator providing the automated synchronization logic.
# Task Domain Invariants
- **Status Workflow**: `Pending` -> `InProgress` -> `Completed` | `Blocked`.
- **Priority Scale**: `P0` (Critical), `P1` (High), `P2` (Medium), `P3` (Low).
- **ID Uniqueness**: Every task MUST have a unique hierarchical ID (e.g., `18.4.1`).
# Gleam Persistence Pattern
```gleam
import gleam/otp/actor
pub type DbMessage {
Write(sql: String, params: List(Dynamic))
Read(sql: String, params: List(Dynamic), reply_to: Subject(Result(List(Dynamic), String)))
}
// Single-Writer Database Actor
pub fn start_db_hub() {
actor.start(initial_db_state, handle_db_message)
}
```
# Troubleshooting
- **Markdown Parse Error**: Verify the task line matches the regex `^(\d+\.\d+(\.\d+)*)\s*-\s*(.*)\s*\[(.*)\]`.
- **Database Lock**: Ensure all write operations are routed through the singleton `DbHub` actor.
- **Sync Drift**: Use `GleamSubstrate` to verify the delta between memory state and disk state.
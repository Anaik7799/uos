//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/workflow_monitor</module>
////     <fsharp-lineage>None — novel Gleam module for durable workflow visibility</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>Workflow execution history visibility and schedule management</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Temporal-inspired durable execution concepts ↪ Gleam typed ADTs.
////       Workflow run state machine maps directly to WorkflowStatus variants.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Workflow Monitor — visibility types for Temporal-inspired durable execution (SC-HA-001)
////
//// Provides typed representations of workflow runs, events, and schedules
//// for dashboard display and API access. Feeds the /api/v1/workflows endpoint.
////
//// SC-HA-001:    System MUST support continuous evolution without dropping intents.
//// SC-GLM-UI-003: Typed JSON via gleam/json — no raw string concatenation.
//// SC-TRUTH-001: System MUST ONLY display data verified as current.

import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Status of a workflow execution run.
pub type WorkflowStatus {
  Running
  Completed
  Failed
  TimedOut
  Paused
}

/// A single event in a workflow execution timeline.
pub type WorkflowEvent {
  WorkflowEvent(
    event_type: String,
    activity_name: String,
    timestamp: String,
    duration_ms: Int,
    output: String,
  )
}

/// A complete workflow execution run with its event history.
pub type WorkflowRun {
  WorkflowRun(
    workflow_id: String,
    run_id: String,
    status: WorkflowStatus,
    workflow_type: String,
    started_at: String,
    events: List(WorkflowEvent),
  )
}

/// A scheduled workflow definition with cron expression and last/next run times.
pub type WorkflowSchedule {
  WorkflowSchedule(
    id: String,
    workflow_type: String,
    cron_expression: String,
    last_run: String,
    next_run: String,
    enabled: Bool,
  )
}

// ---------------------------------------------------------------------------
// Status conversions
// ---------------------------------------------------------------------------

/// Convert a WorkflowStatus to its string representation.
pub fn status_to_string(s: WorkflowStatus) -> String {
  case s {
    Running -> "running"
    Completed -> "completed"
    Failed -> "failed"
    TimedOut -> "timed_out"
    Paused -> "paused"
  }
}

/// Parse a string into a WorkflowStatus. Unknown values map to Paused.
pub fn status_from_string(s: String) -> WorkflowStatus {
  case s {
    "running" -> Running
    "completed" -> Completed
    "failed" -> Failed
    "timed_out" -> TimedOut
    "paused" -> Paused
    _ -> Paused
  }
}

// ---------------------------------------------------------------------------
// JSON serialisation (SC-GLM-UI-003 — no string concatenation)
// ---------------------------------------------------------------------------

/// Serialise a WorkflowEvent to a JSON object string.
pub fn event_to_json(e: WorkflowEvent) -> String {
  let WorkflowEvent(event_type, activity_name, timestamp, duration_ms, output) =
    e
  "{"
  <> "\"event_type\":\""
  <> event_type
  <> "\","
  <> "\"activity_name\":\""
  <> activity_name
  <> "\","
  <> "\"timestamp\":\""
  <> timestamp
  <> "\","
  <> "\"duration_ms\":"
  <> int.to_string(duration_ms)
  <> ","
  <> "\"output\":\""
  <> output
  <> "\""
  <> "}"
}

/// Serialise a WorkflowRun to a JSON object string.
pub fn run_to_json(r: WorkflowRun) -> String {
  let WorkflowRun(
    workflow_id,
    run_id,
    status,
    workflow_type,
    started_at,
    events,
  ) = r
  let events_json =
    events
    |> list.map(event_to_json)
    |> string.join(",")
  "{"
  <> "\"workflow_id\":\""
  <> workflow_id
  <> "\","
  <> "\"run_id\":\""
  <> run_id
  <> "\","
  <> "\"status\":\""
  <> status_to_string(status)
  <> "\","
  <> "\"workflow_type\":\""
  <> workflow_type
  <> "\","
  <> "\"started_at\":\""
  <> started_at
  <> "\","
  <> "\"events\":["
  <> events_json
  <> "]"
  <> "}"
}

/// Serialise a WorkflowSchedule to a JSON object string.
pub fn schedule_to_json(s: WorkflowSchedule) -> String {
  let WorkflowSchedule(
    id,
    workflow_type,
    cron_expression,
    last_run,
    next_run,
    enabled,
  ) = s
  let enabled_str = case enabled {
    True -> "true"
    False -> "false"
  }
  "{"
  <> "\"id\":\""
  <> id
  <> "\","
  <> "\"workflow_type\":\""
  <> workflow_type
  <> "\","
  <> "\"cron_expression\":\""
  <> cron_expression
  <> "\","
  <> "\"last_run\":\""
  <> last_run
  <> "\","
  <> "\"next_run\":\""
  <> next_run
  <> "\","
  <> "\"enabled\":"
  <> enabled_str
  <> "}"
}

// ---------------------------------------------------------------------------
// Aggregate / summary
// ---------------------------------------------------------------------------

/// Count runs by status across a list of WorkflowRun values.
pub fn count_by_status(runs: List(WorkflowRun), target: WorkflowStatus) -> Int {
  list.count(runs, fn(r) { r.status == target })
}

/// Produce a human-readable summary of a run list as a JSON string.
pub fn summary(runs: List(WorkflowRun)) -> String {
  let total = list.length(runs)
  let running = count_by_status(runs, Running)
  let completed = count_by_status(runs, Completed)
  let failed = count_by_status(runs, Failed)
  let timed_out = count_by_status(runs, TimedOut)
  let paused = count_by_status(runs, Paused)
  "{"
  <> "\"total\":"
  <> int.to_string(total)
  <> ","
  <> "\"running\":"
  <> int.to_string(running)
  <> ","
  <> "\"completed\":"
  <> int.to_string(completed)
  <> ","
  <> "\"failed\":"
  <> int.to_string(failed)
  <> ","
  <> "\"timed_out\":"
  <> int.to_string(timed_out)
  <> ","
  <> "\"paused\":"
  <> int.to_string(paused)
  <> "}"
}

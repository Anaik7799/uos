//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/evolution_scheduler</module>
////     <fsharp-lineage>None — novel autonomous evolution scheduling (F42)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L7_FEDERATION</layer>
////     <mesh-domain>
////       Autonomous Evolution Scheduler — F42.
////       Determines WHEN to trigger autonomous feature evolution, selects the
////       highest-priority pending page target, records outcomes, and exposes
////       a typed EvolutionPlan for the Rust cortex to execute via MoZ.
////       All state is immutable; the caller (Rust planning_daemon) owns
////       persistence (Smriti.db) and Zenoh publishing (SC-ZMOF-001).
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-HA-001, SC-GLM-UI-003, SC-MUDA-001, SC-ULTRA-001,
////       SC-ZMOF-001, SC-FUNC-003
////     </stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       CI/CD cron-based release automation ↪ Gleam pure scheduler.
////       Timestamps are Unix epoch ints (SC-MSTS §6: F# DateTimeOffset → Int).
////       No mutable state; EvolutionSchedule is passed by value.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// AUTONOMOUS EVOLUTION SCHEDULER — F42
//// बहूनि मे व्यतीतानि जन्मानि — Many births have passed (Gita 4.5)
////
//// Design:
////   The scheduler holds a simple record of when the last autonomous evolution
////   ran and when the next one is due. `should_run/2` is the sole entry point
////   for deciding whether to trigger: it is pure and side-effect-free.
////
////   `next_evolution_plan/0` returns the highest-priority page from the
////   canonical backlog, ordered by Ultrathink Mandate focus areas and PageRank
////   (Dashboard > Cockpit > Verification > ...).  The Rust cortex converts
////   this plan into a task and dispatches it via `sa-plan-daemon`.
////
////   Evolution results are typed (EvolutionResult) so the scheduler can
////   track cumulative quality metrics and make smarter decisions over time
////   (e.g. skip if last run failed due to a Zenoh outage).
////
//// STAMP: SC-HA-001, SC-GLM-UI-003, SC-MUDA-001, SC-ULTRA-001

import gleam/int
import gleam/json
import gleam/list

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

/// Result of a single autonomous evolution run.
pub type EvolutionResult {
  /// No run has been attempted yet (initial state).
  EvolutionNotRun
  /// Run completed successfully.
  EvolutionSuccess(features_evolved: Int, tests_added: Int)
  /// Run failed — see `reason` for diagnostics.
  EvolutionFailed(reason: String)
  /// Run was deliberately skipped (e.g. system unhealthy, high CPU).
  EvolutionSkipped(reason: String)
}

/// A single scheduled evolution run record.
pub type EvolutionSchedule {
  EvolutionSchedule(
    /// How often to run autonomous evolution (hours between runs).
    interval_hours: Int,
    /// Unix epoch timestamp of the next scheduled run.
    next_run_timestamp: Int,
    /// Unix epoch timestamp of the last completed run (0 = never).
    last_run_timestamp: Int,
    /// Total successful runs since system init.
    runs_completed: Int,
    /// Outcome of the most recent run.
    last_result: EvolutionResult,
    /// Whether autonomous scheduling is enabled.
    enabled: Bool,
  )
}

/// Target page + strategy for the next evolution cycle.
pub type EvolutionPlan {
  EvolutionPlan(
    /// Page name matching the Lustre router, e.g. "dashboard"
    target_page: String,
    /// "template" = apply agentic-ui-responsive-design pattern
    /// "genetic"  = mutate existing page toward higher ITQS score
    /// "manual"   = operator override (only via sa-plan task)
    strategy: String,
    /// Estimated wall-clock time for one evolution cycle (seconds).
    estimated_time_seconds: Int,
    /// Planning priority matching sa-plan-daemon semantics.
    priority: String,
  )
}

// ---------------------------------------------------------------------------
// Constructor
// ---------------------------------------------------------------------------

/// Initialise a new schedule.  `current_time` is a Unix epoch integer.
/// The first run is scheduled `interval_hours` from now.
pub fn init(interval_hours: Int, current_time: Int) -> EvolutionSchedule {
  let next = current_time + interval_hours * 3600
  EvolutionSchedule(
    interval_hours: interval_hours,
    next_run_timestamp: next,
    last_run_timestamp: 0,
    runs_completed: 0,
    last_result: EvolutionNotRun,
    enabled: True,
  )
}

// ---------------------------------------------------------------------------
// Scheduling logic
// ---------------------------------------------------------------------------

/// True when the scheduler is enabled AND the current time has passed the
/// next scheduled run timestamp.  Pure; no side-effects.
pub fn should_run(schedule: EvolutionSchedule, current_time: Int) -> Bool {
  schedule.enabled && current_time >= schedule.next_run_timestamp
}

/// Record the outcome of a completed run.  Advances `next_run_timestamp`
/// by `interval_hours`.  Returns an updated schedule.
pub fn record_run(
  schedule: EvolutionSchedule,
  result: EvolutionResult,
  current_time: Int,
) -> EvolutionSchedule {
  let completed = case result {
    EvolutionSuccess(_, _) -> schedule.runs_completed + 1
    _ -> schedule.runs_completed
  }
  let next = current_time + schedule.interval_hours * 3600
  EvolutionSchedule(
    ..schedule,
    last_run_timestamp: current_time,
    next_run_timestamp: next,
    runs_completed: completed,
    last_result: result,
  )
}

/// Enable or disable autonomous scheduling (operator override).
pub fn set_enabled(
  schedule: EvolutionSchedule,
  enabled: Bool,
) -> EvolutionSchedule {
  EvolutionSchedule(..schedule, enabled: enabled)
}

// ---------------------------------------------------------------------------
// Evolution plan selection
// ---------------------------------------------------------------------------

/// The canonical ordered backlog of pages awaiting agentic UI evolution.
/// Ordered by: PageRank priority × Ultrathink focus area criticality.
/// Ref: agentic-ui-responsive-design.md §26 Evolution Order.
fn page_backlog() -> List(EvolutionPlan) {
  [
    EvolutionPlan(
      target_page: "dashboard",
      strategy: "template",
      estimated_time_seconds: 3600,
      priority: "P0",
    ),
    EvolutionPlan(
      target_page: "cockpit",
      strategy: "template",
      estimated_time_seconds: 3600,
      priority: "P0",
    ),
    EvolutionPlan(
      target_page: "verification",
      strategy: "template",
      estimated_time_seconds: 3600,
      priority: "P1",
    ),
    EvolutionPlan(
      target_page: "immune",
      strategy: "template",
      estimated_time_seconds: 3600,
      priority: "P1",
    ),
    EvolutionPlan(
      target_page: "agents",
      strategy: "template",
      estimated_time_seconds: 2700,
      priority: "P1",
    ),
    EvolutionPlan(
      target_page: "zenoh",
      strategy: "template",
      estimated_time_seconds: 2700,
      priority: "P1",
    ),
    EvolutionPlan(
      target_page: "knowledge",
      strategy: "template",
      estimated_time_seconds: 2700,
      priority: "P2",
    ),
    EvolutionPlan(
      target_page: "telemetry",
      strategy: "template",
      estimated_time_seconds: 2700,
      priority: "P2",
    ),
    EvolutionPlan(
      target_page: "podman",
      strategy: "template",
      estimated_time_seconds: 2700,
      priority: "P2",
    ),
    EvolutionPlan(
      target_page: "substrate",
      strategy: "template",
      estimated_time_seconds: 2400,
      priority: "P2",
    ),
    EvolutionPlan(
      target_page: "metabolic",
      strategy: "template",
      estimated_time_seconds: 2400,
      priority: "P2",
    ),
    EvolutionPlan(
      target_page: "smriti",
      strategy: "template",
      estimated_time_seconds: 2400,
      priority: "P2",
    ),
    EvolutionPlan(
      target_page: "mcp",
      strategy: "template",
      estimated_time_seconds: 1800,
      priority: "P3",
    ),
    EvolutionPlan(
      target_page: "kms",
      strategy: "template",
      estimated_time_seconds: 1800,
      priority: "P3",
    ),
    EvolutionPlan(
      target_page: "prajna",
      strategy: "template",
      estimated_time_seconds: 1800,
      priority: "P3",
    ),
  ]
}

/// Returns the next evolution plan: the first P0, else first P1, else P2, P3.
/// If the backlog is empty, returns a sentinel no-op plan.
pub fn next_evolution_plan() -> EvolutionPlan {
  let backlog = page_backlog()
  let find_priority = fn(p: String) -> Result(EvolutionPlan, Nil) {
    list.find(backlog, fn(plan) { plan.priority == p })
  }
  case find_priority("P0") {
    Ok(plan) -> plan
    Error(_) ->
      case find_priority("P1") {
        Ok(plan) -> plan
        Error(_) ->
          case find_priority("P2") {
            Ok(plan) -> plan
            Error(_) ->
              case find_priority("P3") {
                Ok(plan) -> plan
                Error(_) ->
                  EvolutionPlan(
                    target_page: "none",
                    strategy: "manual",
                    estimated_time_seconds: 0,
                    priority: "P3",
                  )
              }
          }
      }
  }
}

/// Full backlog as a list (for dashboard display).
pub fn all_plans() -> List(EvolutionPlan) {
  page_backlog()
}

// ---------------------------------------------------------------------------
// JSON serialisation
// ---------------------------------------------------------------------------

/// Serialise the schedule to a JSON string for Zenoh publishing.
pub fn to_json(schedule: EvolutionSchedule) -> String {
  json.object([
    #("interval_hours", json.int(schedule.interval_hours)),
    #("next_run_timestamp", json.int(schedule.next_run_timestamp)),
    #("last_run_timestamp", json.int(schedule.last_run_timestamp)),
    #("runs_completed", json.int(schedule.runs_completed)),
    #("last_result", json.string(result_to_string(schedule.last_result))),
    #("enabled", json.bool(schedule.enabled)),
  ])
  |> json.to_string()
}

/// Serialise a single EvolutionPlan to a JSON string.
pub fn plan_to_json(plan: EvolutionPlan) -> String {
  json.object([
    #("target_page", json.string(plan.target_page)),
    #("strategy", json.string(plan.strategy)),
    #("estimated_time_seconds", json.int(plan.estimated_time_seconds)),
    #("priority", json.string(plan.priority)),
  ])
  |> json.to_string()
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

/// Seconds until the next scheduled run (may be negative if overdue).
pub fn seconds_until_next_run(
  schedule: EvolutionSchedule,
  current_time: Int,
) -> Int {
  schedule.next_run_timestamp - current_time
}

/// True when the last result was a failure.
pub fn last_run_failed(schedule: EvolutionSchedule) -> Bool {
  case schedule.last_result {
    EvolutionFailed(_) -> True
    _ -> False
  }
}

/// Human-readable summary line for TUI display.
pub fn summary(schedule: EvolutionSchedule) -> String {
  let status = case schedule.enabled {
    True -> "enabled"
    False -> "disabled"
  }
  "EvolutionScheduler: "
  <> status
  <> " | runs="
  <> int.to_string(schedule.runs_completed)
  <> " | interval="
  <> int.to_string(schedule.interval_hours)
  <> "h | last="
  <> result_to_string(schedule.last_result)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn result_to_string(result: EvolutionResult) -> String {
  case result {
    EvolutionNotRun -> "not_run"
    EvolutionSuccess(features, tests) ->
      "success(features="
      <> int.to_string(features)
      <> ",tests="
      <> int.to_string(tests)
      <> ")"
    EvolutionFailed(reason) -> "failed(" <> reason <> ")"
    EvolutionSkipped(reason) -> "skipped(" <> reason <> ")"
  }
}

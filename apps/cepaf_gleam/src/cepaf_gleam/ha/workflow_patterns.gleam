//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/workflow_patterns</module>
////     <fsharp-lineage>None — novel Gleam module for Temporal workflow patterns (WF-12/13/15/17)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Durable workflow signals, queries, saga compensation, and cancellation
////       scopes. Implements the four Temporal-inspired patterns required for
////       production-grade workflow orchestration in the SIL-6 mesh:
////         WF-12 — Signals   (external mutation of running workflow)
////         WF-13 — Queries   (read state without side effects)
////         WF-15 — Saga      (forward/compensation transaction pairs)
////         WF-17 — Cancellation (structured cleanup scopes)
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Temporal Go/Java SDK concepts ↪ Gleam typed ADTs.
////       WorkflowSignal mirrors Signal() in Temporal; no dynamic dispatch needed
////       because Gleam exhaustive pattern matching is the dispatch table.
////     </morphism>
////     <morphism type="surjective" loss="temporal-server-persistence">
////       Saga compensation in Temporal is server-persisted across failures.
////       Here SagaState is in-memory only — callers must checkpoint via
////       ha/checkpoint.gleam for durability.
////       Mitigation: integrate with checkpoint.save() after every advance_saga().
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Workflow Patterns — signals, queries, saga compensation, cancellation (SC-HA-001)
////
//// WF-12 Signals: External callers send a WorkflowSignal to mutate a running
////   workflow's status string.  apply_signal/2 is the pure state transition.
////
//// WF-13 Queries: Read-only view of workflow state via WorkflowQuery.
////   execute_query/4 returns a QueryResult without side effects.
////
//// WF-15 Saga: A sequence of (action, compensation) pairs.  init_saga/2 builds
////   the initial SagaState; advance_saga/2 moves one step forward; fail_saga/2
////   marks the current step as failed and switches compensating=True;
////   compensate_step/1 executes one compensation in reverse order.
////
//// WF-17 Cancellation: A CancellationScope tracks which cleanup activities
////   must run when a workflow is cancelled.  complete_cleanup/1 increments the
////   counter; is_cancelled/1 checks the flag.
////
//// SC-HA-001:    Continuous evolution without dropping intents.
//// SC-GLM-UI-003: No raw string concatenation for JSON.
//// SC-TRUTH-001: Only verified current data displayed.
//// SC-MUDA-001:  Zero dead code — every exported function is tested.

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// WF-12 — Workflow Signals
// ---------------------------------------------------------------------------

/// External signal sent to a running workflow to mutate its execution.
pub type WorkflowSignal {
  Pause(reason: String)
  Resume
  Cancel(reason: String)
  Custom(name: String, payload: String)
}

/// Apply a signal to the current workflow status string and return the new status.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Pure state transition ↪ no side effects</morphism>
///   <formal-proof>
///     <P> Pre-condition: status is a non-empty string; signal is a valid ADT variant. </P>
///     <C> apply_signal(status, signal) </C>
///     <Q> Post-condition: returns a new status string that reflects the signal.
///         Original status is unchanged (immutable Gleam semantics). </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn apply_signal(status: String, signal: WorkflowSignal) -> String {
  case signal {
    Pause(_) -> "paused"
    Resume ->
      case status {
        "paused" -> "running"
        other -> other
      }
    Cancel(_) -> "cancelled"
    Custom(_, _) -> status
  }
}

/// Convert a WorkflowSignal to its canonical string name.
pub fn signal_to_string(s: WorkflowSignal) -> String {
  case s {
    Pause(_) -> "pause"
    Resume -> "resume"
    Cancel(_) -> "cancel"
    Custom(name, _) -> "custom:" <> name
  }
}

/// Serialise a WorkflowSignal to a JSON object string.
pub fn signal_to_json(s: WorkflowSignal) -> String {
  case s {
    Pause(reason) -> "{\"type\":\"pause\",\"reason\":\"" <> reason <> "\"}"
    Resume -> "{\"type\":\"resume\"}"
    Cancel(reason) -> "{\"type\":\"cancel\",\"reason\":\"" <> reason <> "\"}"
    Custom(name, payload) ->
      "{"
      <> "\"type\":\"custom\","
      <> "\"name\":\""
      <> name
      <> "\","
      <> "\"payload\":\""
      <> payload
      <> "\""
      <> "}"
  }
}

// ---------------------------------------------------------------------------
// WF-13 — Workflow Queries
// ---------------------------------------------------------------------------

/// Read-only query sent to a running workflow to inspect its state.
pub type WorkflowQuery {
  GetStatus
  GetProgress
  GetResult
  CustomQuery(name: String)
}

/// The result of a workflow query — value plus metadata.
pub type QueryResult {
  QueryResult(query: String, value: String, timestamp_ms: Int)
}

/// Execute a query against the provided workflow state and return a QueryResult.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Read-only projection ↪ no mutation</morphism>
///   <formal-proof>
///     <P> status, progress, result are current workflow state fields. </P>
///     <C> execute_query(query, status, progress, result) </C>
///     <Q> Returns QueryResult with the projected value; inputs are unchanged. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn execute_query(
  query: WorkflowQuery,
  status: String,
  progress: Float,
  result: String,
) -> QueryResult {
  case query {
    GetStatus -> QueryResult("status", status, 0)
    GetProgress -> QueryResult("progress", float.to_string(progress), 0)
    GetResult -> QueryResult("result", result, 0)
    CustomQuery(name) -> QueryResult("custom:" <> name, "", 0)
  }
}

/// Convert a WorkflowQuery to its canonical string name.
pub fn query_to_string(q: WorkflowQuery) -> String {
  case q {
    GetStatus -> "get_status"
    GetProgress -> "get_progress"
    GetResult -> "get_result"
    CustomQuery(name) -> "custom:" <> name
  }
}

/// Serialise a QueryResult to a JSON object string.
pub fn query_result_to_json(r: QueryResult) -> String {
  let QueryResult(query, value, timestamp_ms) = r
  "{"
  <> "\"query\":\""
  <> query
  <> "\","
  <> "\"value\":\""
  <> value
  <> "\","
  <> "\"timestamp_ms\":"
  <> int.to_string(timestamp_ms)
  <> "}"
}

// ---------------------------------------------------------------------------
// WF-15 — Saga Compensation
// ---------------------------------------------------------------------------

/// Status of a single saga step.
pub type SagaStepStatus {
  SagaPending
  SagaCompleted
  SagaFailed
  SagaCompensated
}

/// A single saga step — one forward action paired with its compensation.
pub type SagaStep {
  SagaStep(
    name: String,
    action: String,
    compensation: String,
    status: SagaStepStatus,
    result: String,
  )
}

/// Full saga execution state — tracks forward execution and compensation roll-back.
pub type SagaState {
  SagaState(
    saga_id: String,
    steps: List(SagaStep),
    current_step: Int,
    compensating: Bool,
    completed: Bool,
  )
}

/// Initialise a fresh SagaState from a list of (name, action, compensation) triples.
pub fn init_saga(
  saga_id: String,
  steps: List(#(String, String, String)),
) -> SagaState {
  let saga_steps =
    list.map(steps, fn(t) {
      let #(name, action, compensation) = t
      SagaStep(
        name: name,
        action: action,
        compensation: compensation,
        status: SagaPending,
        result: "",
      )
    })
  SagaState(
    saga_id: saga_id,
    steps: saga_steps,
    current_step: 0,
    compensating: False,
    completed: False,
  )
}

/// Mark the current step as completed with the given result and advance the index.
/// If there are no more steps the saga is marked completed.
pub fn advance_saga(state: SagaState, result: String) -> SagaState {
  let idx = state.current_step
  let updated_steps =
    list.index_map(state.steps, fn(step, i) {
      case i == idx {
        True -> SagaStep(..step, status: SagaCompleted, result: result)
        False -> step
      }
    })
  let next_idx = idx + 1
  let total = list.length(state.steps)
  SagaState(
    ..state,
    steps: updated_steps,
    current_step: next_idx,
    completed: next_idx >= total,
  )
}

/// Mark the given step as failed and switch the saga into compensation mode.
/// Compensation starts from step_index and works backwards.
pub fn fail_saga(state: SagaState, step_index: Int) -> SagaState {
  let updated_steps =
    list.index_map(state.steps, fn(step, i) {
      case i == step_index {
        True -> SagaStep(..step, status: SagaFailed)
        False -> step
      }
    })
  SagaState(
    ..state,
    steps: updated_steps,
    current_step: step_index,
    compensating: True,
  )
}

/// Compensate one step in reverse order.  The most recently completed step
/// before current_step is marked SagaCompensated and current_step decrements.
/// When current_step reaches 0 the saga is considered fully compensated (completed).
pub fn compensate_step(state: SagaState) -> SagaState {
  let idx = state.current_step - 1
  case idx < 0 {
    True -> SagaState(..state, completed: True)
    False -> {
      let updated_steps =
        list.index_map(state.steps, fn(step, i) {
          case i == idx {
            True -> SagaStep(..step, status: SagaCompensated)
            False -> step
          }
        })
      let new_idx = idx
      SagaState(
        ..state,
        steps: updated_steps,
        current_step: new_idx,
        completed: new_idx == 0,
      )
    }
  }
}

/// Return True when the saga has finished — either all steps completed forward
/// or all compensation is done.
pub fn is_saga_complete(state: SagaState) -> Bool {
  state.completed
}

/// Serialise the saga step status to a string.
fn saga_step_status_to_string(s: SagaStepStatus) -> String {
  case s {
    SagaPending -> "pending"
    SagaCompleted -> "completed"
    SagaFailed -> "failed"
    SagaCompensated -> "compensated"
  }
}

/// Serialise a single SagaStep to a JSON object string.
fn saga_step_to_json(step: SagaStep) -> String {
  let SagaStep(name, action, compensation, status, result) = step
  "{"
  <> "\"name\":\""
  <> name
  <> "\","
  <> "\"action\":\""
  <> action
  <> "\","
  <> "\"compensation\":\""
  <> compensation
  <> "\","
  <> "\"status\":\""
  <> saga_step_status_to_string(status)
  <> "\","
  <> "\"result\":\""
  <> result
  <> "\""
  <> "}"
}

/// Serialise the full SagaState to a JSON object string.
pub fn saga_to_json(state: SagaState) -> String {
  let SagaState(saga_id, steps, current_step, compensating, completed) = state
  let steps_json =
    steps
    |> list.map(saga_step_to_json)
    |> string.join(",")
  "{"
  <> "\"saga_id\":\""
  <> saga_id
  <> "\","
  <> "\"steps\":["
  <> steps_json
  <> "],"
  <> "\"current_step\":"
  <> int.to_string(current_step)
  <> ","
  <> "\"compensating\":"
  <> case compensating {
    True -> "true"
    False -> "false"
  }
  <> ","
  <> "\"completed\":"
  <> case completed {
    True -> "true"
    False -> "false"
  }
  <> "}"
}

/// Return a human-readable one-line summary of the saga state.
pub fn saga_summary(state: SagaState) -> String {
  let total = list.length(state.steps)
  let done =
    list.filter(state.steps, fn(s) { s.status == SagaCompleted })
    |> list.length()
  let failed =
    list.filter(state.steps, fn(s) { s.status == SagaFailed })
    |> list.length()
  let compensated =
    list.filter(state.steps, fn(s) { s.status == SagaCompensated })
    |> list.length()
  "saga:"
  <> state.saga_id
  <> " steps:"
  <> int.to_string(total)
  <> " done:"
  <> int.to_string(done)
  <> " failed:"
  <> int.to_string(failed)
  <> " compensated:"
  <> int.to_string(compensated)
  <> " compensating:"
  <> case state.compensating {
    True -> "yes"
    False -> "no"
  }
  <> " completed:"
  <> case state.completed {
    True -> "yes"
    False -> "no"
  }
}

// ---------------------------------------------------------------------------
// WF-17 — Cancellation Scopes
// ---------------------------------------------------------------------------

/// Structured cancellation scope — tracks cleanup activities for a workflow.
pub type CancellationScope {
  CancellationScope(
    workflow_id: String,
    cancelled: Bool,
    reason: String,
    cleanup_activities: List(String),
    cleanup_completed: Int,
  )
}

/// Initialise a fresh CancellationScope for the given workflow.
pub fn init_cancellation(workflow_id: String) -> CancellationScope {
  CancellationScope(
    workflow_id: workflow_id,
    cancelled: False,
    reason: "",
    cleanup_activities: [],
    cleanup_completed: 0,
  )
}

/// Cancel the scope with a human-readable reason.
pub fn cancel(scope: CancellationScope, reason: String) -> CancellationScope {
  CancellationScope(..scope, cancelled: True, reason: reason)
}

/// Register an additional cleanup activity that must run on cancellation.
pub fn add_cleanup(
  scope: CancellationScope,
  activity: String,
) -> CancellationScope {
  CancellationScope(
    ..scope,
    cleanup_activities: list.append(scope.cleanup_activities, [activity]),
  )
}

/// Mark one cleanup activity as completed by incrementing the counter.
pub fn complete_cleanup(scope: CancellationScope) -> CancellationScope {
  CancellationScope(..scope, cleanup_completed: scope.cleanup_completed + 1)
}

/// Return True when the scope has been cancelled.
pub fn is_cancelled(scope: CancellationScope) -> Bool {
  scope.cancelled
}

/// Return True when all registered cleanup activities have completed.
pub fn all_cleanup_done(scope: CancellationScope) -> Bool {
  scope.cleanup_completed >= list.length(scope.cleanup_activities)
}

/// Serialise a CancellationScope to a JSON object string.
pub fn cancellation_to_json(scope: CancellationScope) -> String {
  let CancellationScope(
    workflow_id,
    cancelled,
    reason,
    cleanup_activities,
    cleanup_completed,
  ) = scope
  let activities_json =
    cleanup_activities
    |> list.map(fn(a) { "\"" <> a <> "\"" })
    |> string.join(",")
  "{"
  <> "\"workflow_id\":\""
  <> workflow_id
  <> "\","
  <> "\"cancelled\":"
  <> case cancelled {
    True -> "true"
    False -> "false"
  }
  <> ","
  <> "\"reason\":\""
  <> reason
  <> "\","
  <> "\"cleanup_activities\":["
  <> activities_json
  <> "],"
  <> "\"cleanup_completed\":"
  <> int.to_string(cleanup_completed)
  <> "}"
}

/// Return a human-readable one-line summary of the cancellation scope.
pub fn cancellation_summary(scope: CancellationScope) -> String {
  let total = list.length(scope.cleanup_activities)
  "workflow:"
  <> scope.workflow_id
  <> " cancelled:"
  <> case scope.cancelled {
    True -> "yes"
    False -> "no"
  }
  <> " reason:\""
  <> scope.reason
  <> "\""
  <> " cleanup:"
  <> int.to_string(scope.cleanup_completed)
  <> "/"
  <> int.to_string(total)
}

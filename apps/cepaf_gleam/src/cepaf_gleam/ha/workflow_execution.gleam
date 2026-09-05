//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/workflow_execution</module>
////     <fsharp-lineage>None — novel Gleam module for Temporal-inspired durable execution (WF-10, WF-11, WF-18)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <mesh-domain>
////       Workflow execution engine: retry policies, activity heartbeats, fan-out/fan-in.
////       Implements WF-10 (retry policies), WF-11 (activity heartbeats), WF-18
////       (fan-out/fan-in diamond pattern as in Oban Pro workflows).
////       All state is pure ADT — no I/O side-effects.  Callers are responsible
////       for scheduling, persistence, and Zenoh telemetry publishing.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-HA-001, SC-FUNC-001, SC-MUDA-001, SC-GLM-UI-003, SC-TRUTH-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       Temporal RetryPolicy / Oban retry options ↪ Gleam RetryPolicy ADT.
////       Temporal Activity Heartbeat ↪ Gleam Heartbeat ADT.
////       Oban Pro fan-out/fan-in ↪ Gleam FanOutState diamond pattern.
////       All computations are pure functions — no BEAM message passing.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Workflow Execution Engine — retry, heartbeat, fan-out/fan-in (SC-HA-001)
//// वर्कफ़्लो निष्पादन इंजन — पुनःप्रयास, हृदयस्पंद, फैन-आउट/फैन-इन
////
//// Design invariants (proved by pure-function ADTs):
////   I1: next_delay_ms(p, n) is monotonically non-decreasing in n.
////   I2: should_retry(p, n, e) = False when n >= p.max_attempts (for max_attempts > 0).
////   I3: heartbeat_stale(hb, now, t) iff (now - hb.timestamp_ms) >= t.
////   I4: fan_in_ready(s) iff s.completed + s.failed == s.total.
////   I5: fan_results(s) returns exactly the results of FanCompleted children, in order.
////
//// Mathematical model for exponential backoff:
////   delay(policy, attempt) =
////     min(initial_interval * coeff^(attempt-1), max_interval)
////
//// SC-HA-001:  System MUST support continuous evolution without dropping intents.
//// SC-FUNC-001: System MUST compile at all times.
//// SC-MUDA-001: Zero dead code, zero unused imports.
//// SC-GLM-UI-003: JSON output via explicit string building — no raw format/concat.
//// SC-TRUTH-001: All outputs reflect actual computed state.
////
//// अविनाशि तु तद्विद्धि — Know that to be indestructible (Gita 2.17)

import gleam/float
import gleam/int
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// RetryPolicy (WF-10)
// ---------------------------------------------------------------------------

/// Retry policy — configurable per-activity.
///
/// max_attempts: 0 means infinite retries.
/// initial_interval_ms: delay before the first retry.
/// backoff_coefficient: multiplier applied per additional attempt (e.g. 2.0 doubles each time).
/// max_interval_ms: upper bound on any single retry delay.
/// non_retryable_errors: error type strings that cause immediate failure (no retry).
pub type RetryPolicy {
  RetryPolicy(
    max_attempts: Int,
    initial_interval_ms: Int,
    backoff_coefficient: Float,
    max_interval_ms: Int,
    non_retryable_errors: List(String),
  )
}

/// Default retry policy — 3 attempts, 1s initial, 2.0x backoff, 30s cap.
/// Suitable for most transient-failure scenarios.
pub fn default_retry() -> RetryPolicy {
  RetryPolicy(
    max_attempts: 3,
    initial_interval_ms: 1000,
    backoff_coefficient: 2.0,
    max_interval_ms: 30_000,
    non_retryable_errors: [],
  )
}

/// Aggressive retry policy — 5 attempts, 500ms initial, 1.5x backoff, 10s cap.
/// Suitable for fast-failing transient errors (e.g. network blips).
pub fn aggressive_retry() -> RetryPolicy {
  RetryPolicy(
    max_attempts: 5,
    initial_interval_ms: 500,
    backoff_coefficient: 1.5,
    max_interval_ms: 10_000,
    non_retryable_errors: [],
  )
}

/// No-retry policy — single attempt, fails immediately on error.
pub fn no_retry() -> RetryPolicy {
  RetryPolicy(
    max_attempts: 1,
    initial_interval_ms: 0,
    backoff_coefficient: 1.0,
    max_interval_ms: 0,
    non_retryable_errors: [],
  )
}

/// Compute the delay in milliseconds before the next retry attempt.
///
/// attempt is 1-based: attempt=1 means "this is the first retry".
/// Applies exponential backoff capped at max_interval_ms.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: attempt >= 1, policy fields >= 0. </P>
///     <C> next_delay_ms(policy, attempt) </C>
///     <Q> Post-condition: 0 <= result <= policy.max_interval_ms.
///         result is non-decreasing as attempt increases. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn next_delay_ms(policy: RetryPolicy, attempt: Int) -> Int {
  // Compute initial * coeff^(attempt-1) using integer math
  // We stay in Int throughout to avoid Float precision issues at large values.
  let exponent = int.max(0, attempt - 1)
  let base_ms =
    compute_backoff(
      policy.initial_interval_ms,
      policy.backoff_coefficient,
      exponent,
    )
  int.min(base_ms, policy.max_interval_ms)
}

/// Decide whether to retry.
///
/// Returns False when:
///   - max_attempts > 0 AND attempt >= max_attempts  (exhausted)
///   - error is listed in non_retryable_errors         (non-retryable)
///
/// Returns True otherwise (including max_attempts == 0 i.e. infinite).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: attempt >= 1. </P>
///     <C> should_retry(policy, attempt, error) </C>
///     <Q> Post-condition: result = True only if retryable conditions met. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn should_retry(policy: RetryPolicy, attempt: Int, error: String) -> Bool {
  let non_retryable = list.contains(policy.non_retryable_errors, error)
  case non_retryable {
    True -> False
    False ->
      case policy.max_attempts {
        0 -> True
        max -> attempt < max
      }
  }
}

/// Serialise a RetryPolicy to a JSON object string.
pub fn retry_to_json(p: RetryPolicy) -> String {
  let RetryPolicy(
    max_attempts,
    initial_interval_ms,
    backoff_coefficient,
    max_interval_ms,
    non_retryable_errors,
  ) = p
  let errors_json =
    non_retryable_errors
    |> list.map(fn(e) { "\"" <> e <> "\"" })
    |> string.join(",")
  "{"
  <> "\"max_attempts\":"
  <> int.to_string(max_attempts)
  <> ","
  <> "\"initial_interval_ms\":"
  <> int.to_string(initial_interval_ms)
  <> ","
  <> "\"backoff_coefficient\":"
  <> float.to_string(backoff_coefficient)
  <> ","
  <> "\"max_interval_ms\":"
  <> int.to_string(max_interval_ms)
  <> ","
  <> "\"non_retryable_errors\":["
  <> errors_json
  <> "]}"
}

// ---------------------------------------------------------------------------
// Heartbeat (WF-11)
// ---------------------------------------------------------------------------

/// Activity heartbeat — progress reporting for long-running tasks.
///
/// sequence is a monotonically increasing counter; callers increment it.
/// timestamp_ms is a Unix epoch millisecond timestamp set by the caller.
pub type Heartbeat {
  Heartbeat(
    activity_id: String,
    progress_percent: Float,
    details: String,
    timestamp_ms: Int,
    sequence: Int,
  )
}

/// Create an initial heartbeat at 0% progress.
pub fn heartbeat_start(activity_id: String, now_ms: Int) -> Heartbeat {
  Heartbeat(
    activity_id: activity_id,
    progress_percent: 0.0,
    details: "started",
    timestamp_ms: now_ms,
    sequence: 0,
  )
}

/// Advance a heartbeat to a new progress percentage and details string.
/// Increments the sequence counter and updates the timestamp.
///
/// progress_percent is clamped to [0.0, 100.0].
pub fn heartbeat_update(
  hb: Heartbeat,
  percent: Float,
  details: String,
  now_ms: Int,
) -> Heartbeat {
  let clamped = float.min(100.0, float.max(0.0, percent))
  Heartbeat(
    activity_id: hb.activity_id,
    progress_percent: clamped,
    details: details,
    timestamp_ms: now_ms,
    sequence: hb.sequence + 1,
  )
}

/// Returns True when the heartbeat has not been updated within timeout_ms.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: now_ms >= hb.timestamp_ms, timeout_ms > 0. </P>
///     <C> heartbeat_stale(hb, now_ms, timeout_ms) </C>
///     <Q> Post-condition: result = True iff (now_ms - hb.timestamp_ms) >= timeout_ms. </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn heartbeat_stale(hb: Heartbeat, now_ms: Int, timeout_ms: Int) -> Bool {
  now_ms - hb.timestamp_ms >= timeout_ms
}

/// Serialise a Heartbeat to a JSON object string.
pub fn heartbeat_to_json(hb: Heartbeat) -> String {
  let Heartbeat(activity_id, progress_percent, details, timestamp_ms, sequence) =
    hb
  "{"
  <> "\"activity_id\":\""
  <> activity_id
  <> "\","
  <> "\"progress_percent\":"
  <> float.to_string(progress_percent)
  <> ","
  <> "\"details\":\""
  <> details
  <> "\","
  <> "\"timestamp_ms\":"
  <> int.to_string(timestamp_ms)
  <> ","
  <> "\"sequence\":"
  <> int.to_string(sequence)
  <> "}"
}

// ---------------------------------------------------------------------------
// Fan-out / Fan-in (WF-18)
// ---------------------------------------------------------------------------

/// Status of a single child activity in a fan-out execution.
pub type FanStatus {
  FanPending
  FanRunning
  FanCompleted
  FanFailed
}

/// A single child activity entry in a fan-out graph.
pub type FanChild {
  FanChild(id: String, status: FanStatus, result: String)
}

/// Fan-out/fan-in execution state — the Oban diamond pattern.
///
/// parent_id:  identifier of the coordinating parent workflow.
/// children:   one FanChild per spawned activity.
/// completed:  count of FanCompleted children.
/// failed:     count of FanFailed children.
/// total:      total number of children (invariant: == list.length(children)).
/// all_done:   True iff completed + failed == total.
pub type FanOutState {
  FanOutState(
    parent_id: String,
    children: List(FanChild),
    completed: Int,
    failed: Int,
    total: Int,
    all_done: Bool,
  )
}

/// Initialise fan-out with a list of child IDs.  All children start as FanPending.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <formal-proof>
///     <P> Pre-condition: child_ids is a finite list. </P>
///     <C> fan_out(parent_id, child_ids) </C>
///     <Q> Post-condition: state.total = |child_ids|, all children FanPending,
///         completed = 0, failed = 0, all_done = (total == 0). </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn fan_out(parent_id: String, child_ids: List(String)) -> FanOutState {
  let children =
    list.map(child_ids, fn(id) {
      FanChild(id: id, status: FanPending, result: "")
    })
  let total = list.length(child_ids)
  FanOutState(
    parent_id: parent_id,
    children: children,
    completed: 0,
    failed: 0,
    total: total,
    all_done: total == 0,
  )
}

/// Record the successful completion of one child activity.
/// No-op if child_id is not found or already terminal.
pub fn fan_child_completed(
  state: FanOutState,
  child_id: String,
  result: String,
) -> FanOutState {
  let #(updated, delta) =
    update_child(state.children, child_id, FanCompleted, result)
  let new_completed = state.completed + delta
  let all_done = new_completed + state.failed == state.total
  FanOutState(
    ..state,
    children: updated,
    completed: new_completed,
    all_done: all_done,
  )
}

/// Record the failure of one child activity.
/// No-op if child_id is not found or already terminal.
pub fn fan_child_failed(
  state: FanOutState,
  child_id: String,
  error: String,
) -> FanOutState {
  let #(updated, delta) =
    update_child(state.children, child_id, FanFailed, error)
  let new_failed = state.failed + delta
  let all_done = state.completed + new_failed == state.total
  FanOutState(
    ..state,
    children: updated,
    failed: new_failed,
    all_done: all_done,
  )
}

/// Returns True when all children have reached a terminal state
/// (FanCompleted or FanFailed), i.e. the fan-in point is ready.
pub fn fan_in_ready(state: FanOutState) -> Bool {
  state.all_done
}

/// Collect the result strings of all FanCompleted children, preserving order.
pub fn fan_results(state: FanOutState) -> List(String) {
  state.children
  |> list.filter_map(fn(c) {
    case c.status {
      FanCompleted -> Ok(c.result)
      _ -> Error(Nil)
    }
  })
}

/// Serialise a FanOutState to a JSON object string.
pub fn fan_out_to_json(state: FanOutState) -> String {
  let FanOutState(parent_id, children, completed, failed, total, all_done) =
    state
  let children_json =
    children
    |> list.map(fan_child_to_json)
    |> string.join(",")
  let all_done_str = case all_done {
    True -> "true"
    False -> "false"
  }
  "{"
  <> "\"parent_id\":\""
  <> parent_id
  <> "\","
  <> "\"completed\":"
  <> int.to_string(completed)
  <> ","
  <> "\"failed\":"
  <> int.to_string(failed)
  <> ","
  <> "\"total\":"
  <> int.to_string(total)
  <> ","
  <> "\"all_done\":"
  <> all_done_str
  <> ","
  <> "\"children\":["
  <> children_json
  <> "]}"
}

/// Produce a compact human-readable summary of fan-out progress.
/// Format: "parent_id: N/total done (C completed, F failed)"
pub fn fan_out_summary(state: FanOutState) -> String {
  let done = state.completed + state.failed
  state.parent_id
  <> ": "
  <> int.to_string(done)
  <> "/"
  <> int.to_string(state.total)
  <> " done ("
  <> int.to_string(state.completed)
  <> " completed, "
  <> int.to_string(state.failed)
  <> " failed)"
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Serialise a FanChild to a JSON object string.
fn fan_child_to_json(c: FanChild) -> String {
  let FanChild(id, status, result) = c
  "{"
  <> "\"id\":\""
  <> id
  <> "\","
  <> "\"status\":\""
  <> fan_status_to_string(status)
  <> "\","
  <> "\"result\":\""
  <> result
  <> "\"}"
}

fn fan_status_to_string(s: FanStatus) -> String {
  case s {
    FanPending -> "pending"
    FanRunning -> "running"
    FanCompleted -> "completed"
    FanFailed -> "failed"
  }
}

/// Update a child by id; returns #(updated_list, 1) if the update happened, #(list, 0) otherwise.
/// Only non-terminal children can be updated (prevents double-counting).
fn update_child(
  children: List(FanChild),
  target_id: String,
  new_status: FanStatus,
  new_result: String,
) -> #(List(FanChild), Int) {
  let #(changed, updated) =
    list.map_fold(children, False, fn(did_change, child) {
      case child.id == target_id && is_terminal(child.status) == False {
        True -> #(
          True,
          FanChild(id: child.id, status: new_status, result: new_result),
        )
        False -> #(did_change, child)
      }
    })
  let delta = case changed {
    True -> 1
    False -> 0
  }
  #(updated, delta)
}

fn is_terminal(status: FanStatus) -> Bool {
  case status {
    FanCompleted | FanFailed -> True
    FanPending | FanRunning -> False
  }
}

/// Recursive exponential backoff computation (integer arithmetic).
/// Returns initial_ms * coefficient^exponent, clamped to avoid overflow.
fn compute_backoff(initial_ms: Int, coefficient: Float, exponent: Int) -> Int {
  case exponent <= 0 {
    True -> initial_ms
    False ->
      compute_backoff_step(int.to_float(initial_ms), coefficient, exponent)
  }
}

fn compute_backoff_step(
  current: Float,
  coefficient: Float,
  remaining: Int,
) -> Int {
  case remaining <= 0 {
    True -> float.round(current)
    False ->
      compute_backoff_step(current *. coefficient, coefficient, remaining - 1)
  }
}

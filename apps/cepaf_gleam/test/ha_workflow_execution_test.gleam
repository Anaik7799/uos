/// Workflow Execution Engine tests — WF-10, WF-11, WF-18
/// Layer: L4_SYSTEM
/// STAMP: SC-HA-001, SC-FUNC-001, SC-MUDA-001
///
/// Covers:
///   RetryPolicy construction + delay math + should_retry logic      (WF-10)
///   Heartbeat lifecycle + staleness detection                        (WF-11)
///   Fan-out / fan-in diamond pattern                                 (WF-18)
///   JSON serialisation for all three subsystems
import cepaf_gleam/ha/workflow_execution.{FanPending, RetryPolicy}
import gleam/list
import gleam/string
import gleeunit/should

// ===========================================================================
// RetryPolicy — construction (WF-10)
// ===========================================================================

pub fn default_retry_max_attempts_test() {
  let p = workflow_execution.default_retry()
  p.max_attempts |> should.equal(3)
}

pub fn default_retry_initial_interval_test() {
  let p = workflow_execution.default_retry()
  p.initial_interval_ms |> should.equal(1000)
}

pub fn default_retry_max_interval_test() {
  let p = workflow_execution.default_retry()
  p.max_interval_ms |> should.equal(30_000)
}

pub fn aggressive_retry_max_attempts_test() {
  let p = workflow_execution.aggressive_retry()
  p.max_attempts |> should.equal(5)
}

pub fn aggressive_retry_initial_interval_test() {
  let p = workflow_execution.aggressive_retry()
  p.initial_interval_ms |> should.equal(500)
}

pub fn no_retry_max_attempts_test() {
  let p = workflow_execution.no_retry()
  p.max_attempts |> should.equal(1)
}

// ===========================================================================
// next_delay_ms (WF-10)
// ===========================================================================

pub fn next_delay_attempt_1_equals_initial_test() {
  let p = workflow_execution.default_retry()
  workflow_execution.next_delay_ms(p, 1) |> should.equal(1000)
}

pub fn next_delay_attempt_2_doubles_test() {
  let p = workflow_execution.default_retry()
  // 1000 * 2.0^1 = 2000
  workflow_execution.next_delay_ms(p, 2) |> should.equal(2000)
}

pub fn next_delay_attempt_3_doubles_again_test() {
  let p = workflow_execution.default_retry()
  // 1000 * 2.0^2 = 4000
  workflow_execution.next_delay_ms(p, 3) |> should.equal(4000)
}

pub fn next_delay_capped_at_max_interval_test() {
  let p = workflow_execution.default_retry()
  // Large attempt: 1000 * 2^10 = 1_024_000, capped to 30_000
  workflow_execution.next_delay_ms(p, 10) |> should.equal(30_000)
}

pub fn next_delay_aggressive_attempt_2_test() {
  let p = workflow_execution.aggressive_retry()
  // 500 * 1.5^1 = 750
  workflow_execution.next_delay_ms(p, 2) |> should.equal(750)
}

pub fn next_delay_no_retry_is_zero_test() {
  let p = workflow_execution.no_retry()
  workflow_execution.next_delay_ms(p, 1) |> should.equal(0)
}

// ===========================================================================
// should_retry (WF-10)
// ===========================================================================

pub fn should_retry_first_attempt_allowed_test() {
  let p = workflow_execution.default_retry()
  workflow_execution.should_retry(p, 1, "timeout") |> should.equal(True)
}

pub fn should_retry_second_attempt_allowed_test() {
  let p = workflow_execution.default_retry()
  workflow_execution.should_retry(p, 2, "timeout") |> should.equal(True)
}

pub fn should_retry_exhausted_test() {
  let p = workflow_execution.default_retry()
  // max_attempts=3, attempt=3 means we've already tried 3 times, no more
  workflow_execution.should_retry(p, 3, "timeout") |> should.equal(False)
}

pub fn should_retry_no_retry_policy_test() {
  let p = workflow_execution.no_retry()
  workflow_execution.should_retry(p, 1, "anything") |> should.equal(False)
}

pub fn should_retry_non_retryable_error_test() {
  let p =
    RetryPolicy(
      max_attempts: 5,
      initial_interval_ms: 1000,
      backoff_coefficient: 2.0,
      max_interval_ms: 30_000,
      non_retryable_errors: ["InvalidArgument", "PermissionDenied"],
    )
  workflow_execution.should_retry(p, 1, "InvalidArgument")
  |> should.equal(False)
}

pub fn should_retry_retryable_error_not_in_list_test() {
  let p =
    RetryPolicy(
      max_attempts: 5,
      initial_interval_ms: 1000,
      backoff_coefficient: 2.0,
      max_interval_ms: 30_000,
      non_retryable_errors: ["InvalidArgument"],
    )
  workflow_execution.should_retry(p, 1, "NetworkTimeout") |> should.equal(True)
}

pub fn should_retry_infinite_when_max_zero_test() {
  let p =
    RetryPolicy(
      max_attempts: 0,
      initial_interval_ms: 1000,
      backoff_coefficient: 2.0,
      max_interval_ms: 30_000,
      non_retryable_errors: [],
    )
  // Attempt 1000 — still retries because max_attempts=0 means infinite
  workflow_execution.should_retry(p, 1000, "transient") |> should.equal(True)
}

// ===========================================================================
// retry_to_json
// ===========================================================================

pub fn retry_to_json_contains_max_attempts_test() {
  let json =
    workflow_execution.retry_to_json(workflow_execution.default_retry())
  string.contains(json, "\"max_attempts\":3") |> should.equal(True)
}

pub fn retry_to_json_contains_initial_interval_test() {
  let json =
    workflow_execution.retry_to_json(workflow_execution.default_retry())
  string.contains(json, "\"initial_interval_ms\":1000") |> should.equal(True)
}

// ===========================================================================
// Heartbeat lifecycle (WF-11)
// ===========================================================================

pub fn heartbeat_start_progress_zero_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  hb.progress_percent |> should.equal(0.0)
}

pub fn heartbeat_start_sequence_zero_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  hb.sequence |> should.equal(0)
}

pub fn heartbeat_start_activity_id_test() {
  let hb = workflow_execution.heartbeat_start("my-activity", 1000)
  hb.activity_id |> should.equal("my-activity")
}

pub fn heartbeat_update_increments_sequence_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  let hb2 = workflow_execution.heartbeat_update(hb, 50.0, "half done", 2000)
  hb2.sequence |> should.equal(1)
}

pub fn heartbeat_update_sets_progress_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  let hb2 =
    workflow_execution.heartbeat_update(hb, 75.0, "three quarters", 2000)
  hb2.progress_percent |> should.equal(75.0)
}

pub fn heartbeat_update_clamps_above_100_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  let hb2 = workflow_execution.heartbeat_update(hb, 150.0, "overflow", 2000)
  hb2.progress_percent |> should.equal(100.0)
}

pub fn heartbeat_update_clamps_below_zero_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  let hb2 = workflow_execution.heartbeat_update(hb, -10.0, "negative", 2000)
  hb2.progress_percent |> should.equal(0.0)
}

pub fn heartbeat_update_sets_timestamp_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  let hb2 = workflow_execution.heartbeat_update(hb, 25.0, "quarter", 9999)
  hb2.timestamp_ms |> should.equal(9999)
}

pub fn heartbeat_multiple_updates_sequence_test() {
  let hb =
    workflow_execution.heartbeat_start("act-1", 0)
    |> workflow_execution.heartbeat_update(25.0, "25%", 1000)
    |> workflow_execution.heartbeat_update(50.0, "50%", 2000)
    |> workflow_execution.heartbeat_update(75.0, "75%", 3000)
  hb.sequence |> should.equal(3)
}

// ===========================================================================
// heartbeat_stale (WF-11)
// ===========================================================================

pub fn heartbeat_not_stale_when_fresh_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  workflow_execution.heartbeat_stale(hb, 1500, 2000) |> should.equal(False)
}

pub fn heartbeat_stale_at_exact_timeout_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  // 1000 + 2000 = 3000 == 3000 → stale
  workflow_execution.heartbeat_stale(hb, 3000, 2000) |> should.equal(True)
}

pub fn heartbeat_stale_beyond_timeout_test() {
  let hb = workflow_execution.heartbeat_start("act-1", 1000)
  workflow_execution.heartbeat_stale(hb, 10_000, 2000) |> should.equal(True)
}

// ===========================================================================
// heartbeat_to_json
// ===========================================================================

pub fn heartbeat_to_json_contains_activity_id_test() {
  let hb = workflow_execution.heartbeat_start("my-act", 0)
  let json = workflow_execution.heartbeat_to_json(hb)
  string.contains(json, "\"activity_id\":\"my-act\"") |> should.equal(True)
}

pub fn heartbeat_to_json_contains_sequence_test() {
  let hb = workflow_execution.heartbeat_start("a", 0)
  let json = workflow_execution.heartbeat_to_json(hb)
  string.contains(json, "\"sequence\":0") |> should.equal(True)
}

// ===========================================================================
// fan_out initialisation (WF-18)
// ===========================================================================

pub fn fan_out_total_equals_child_count_test() {
  let state = workflow_execution.fan_out("p1", ["c1", "c2", "c3"])
  state.total |> should.equal(3)
}

pub fn fan_out_completed_starts_zero_test() {
  let state = workflow_execution.fan_out("p1", ["c1", "c2"])
  state.completed |> should.equal(0)
}

pub fn fan_out_failed_starts_zero_test() {
  let state = workflow_execution.fan_out("p1", ["c1", "c2"])
  state.failed |> should.equal(0)
}

pub fn fan_out_all_done_false_when_children_exist_test() {
  let state = workflow_execution.fan_out("p1", ["c1"])
  state.all_done |> should.equal(False)
}

pub fn fan_out_all_done_true_when_empty_test() {
  let state = workflow_execution.fan_out("p1", [])
  state.all_done |> should.equal(True)
}

pub fn fan_out_children_start_pending_test() {
  let state = workflow_execution.fan_out("p1", ["c1", "c2"])
  let statuses = list.map(state.children, fn(c) { c.status })
  statuses |> should.equal([FanPending, FanPending])
}

// ===========================================================================
// fan_child_completed / fan_child_failed (WF-18)
// ===========================================================================

pub fn fan_child_completed_increments_completed_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2"])
    |> workflow_execution.fan_child_completed("c1", "ok")
  state.completed |> should.equal(1)
}

pub fn fan_child_completed_does_not_change_failed_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2"])
    |> workflow_execution.fan_child_completed("c1", "ok")
  state.failed |> should.equal(0)
}

pub fn fan_child_failed_increments_failed_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2"])
    |> workflow_execution.fan_child_failed("c1", "err")
  state.failed |> should.equal(1)
}

pub fn fan_child_completed_idempotent_test() {
  // Completing the same child twice should not double-count
  let state =
    workflow_execution.fan_out("p1", ["c1"])
    |> workflow_execution.fan_child_completed("c1", "ok")
    |> workflow_execution.fan_child_completed("c1", "ok-again")
  state.completed |> should.equal(1)
}

pub fn fan_child_unknown_id_is_noop_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1"])
    |> workflow_execution.fan_child_completed("unknown", "x")
  state.completed |> should.equal(0)
}

// ===========================================================================
// fan_in_ready (WF-18)
// ===========================================================================

pub fn fan_in_ready_false_when_pending_test() {
  let state = workflow_execution.fan_out("p1", ["c1", "c2"])
  workflow_execution.fan_in_ready(state) |> should.equal(False)
}

pub fn fan_in_ready_true_when_all_complete_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2"])
    |> workflow_execution.fan_child_completed("c1", "r1")
    |> workflow_execution.fan_child_completed("c2", "r2")
  workflow_execution.fan_in_ready(state) |> should.equal(True)
}

pub fn fan_in_ready_true_when_all_failed_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2"])
    |> workflow_execution.fan_child_failed("c1", "e1")
    |> workflow_execution.fan_child_failed("c2", "e2")
  workflow_execution.fan_in_ready(state) |> should.equal(True)
}

pub fn fan_in_ready_true_mixed_complete_and_failed_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2", "c3"])
    |> workflow_execution.fan_child_completed("c1", "r1")
    |> workflow_execution.fan_child_failed("c2", "e2")
    |> workflow_execution.fan_child_completed("c3", "r3")
  workflow_execution.fan_in_ready(state) |> should.equal(True)
}

pub fn fan_in_not_ready_when_one_pending_remains_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2"])
    |> workflow_execution.fan_child_completed("c1", "r1")
  workflow_execution.fan_in_ready(state) |> should.equal(False)
}

// ===========================================================================
// fan_results (WF-18)
// ===========================================================================

pub fn fan_results_empty_when_none_complete_test() {
  let state = workflow_execution.fan_out("p1", ["c1", "c2"])
  workflow_execution.fan_results(state) |> should.equal([])
}

pub fn fan_results_contains_completed_only_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2", "c3"])
    |> workflow_execution.fan_child_completed("c1", "result-1")
    |> workflow_execution.fan_child_failed("c2", "err-2")
    |> workflow_execution.fan_child_completed("c3", "result-3")
  let results = workflow_execution.fan_results(state)
  results |> should.equal(["result-1", "result-3"])
}

pub fn fan_results_order_preserved_test() {
  let state =
    workflow_execution.fan_out("p1", ["c1", "c2", "c3"])
    |> workflow_execution.fan_child_completed("c3", "third")
    |> workflow_execution.fan_child_completed("c1", "first")
    |> workflow_execution.fan_child_completed("c2", "second")
  // Results are in the original child order (c1, c2, c3)
  let results = workflow_execution.fan_results(state)
  results |> should.equal(["first", "second", "third"])
}

// ===========================================================================
// fan_out_to_json / fan_out_summary
// ===========================================================================

pub fn fan_out_to_json_contains_parent_id_test() {
  let state = workflow_execution.fan_out("workflow-42", ["c1"])
  let json = workflow_execution.fan_out_to_json(state)
  string.contains(json, "\"parent_id\":\"workflow-42\"") |> should.equal(True)
}

pub fn fan_out_to_json_all_done_false_test() {
  let state = workflow_execution.fan_out("p1", ["c1"])
  let json = workflow_execution.fan_out_to_json(state)
  string.contains(json, "\"all_done\":false") |> should.equal(True)
}

pub fn fan_out_summary_format_test() {
  let state =
    workflow_execution.fan_out("batch-7", ["c1", "c2", "c3"])
    |> workflow_execution.fan_child_completed("c1", "ok")
    |> workflow_execution.fan_child_failed("c2", "err")
  let summary = workflow_execution.fan_out_summary(state)
  string.contains(summary, "batch-7") |> should.equal(True)
  string.contains(summary, "2/3") |> should.equal(True)
  string.contains(summary, "1 completed") |> should.equal(True)
  string.contains(summary, "1 failed") |> should.equal(True)
}

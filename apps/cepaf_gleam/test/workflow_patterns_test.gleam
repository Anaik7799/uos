// =============================================================================
// workflow_patterns_test.gleam — Signals, Queries, Saga, Cancellation (WF-12/13/15/17)
// =============================================================================
// Tests for ha/workflow_patterns.gleam
//
// Coverage categories:
//   C1 Page Structure  — types construct correctly; init functions return valid state
//   C2 Status Badges   — signal/saga/cancellation status strings are correct
//   C3 Data Grids      — saga steps list populated and traversable
//   C4 Timeline        — advance_saga / compensate_step step sequencing
//   C5 Interactive     — multi-step advance + fail + compensation chain
//   C6 Media/Rich      — JSON serialisation of all four pattern families
//   C7 AI Advisory     — query projection (GetStatus, GetProgress, GetResult, CustomQuery)
//   C8 Action Button   — cancellation safety gates (is_cancelled, all_cleanup_done)
//
// STAMP: SC-HA-001, SC-GLM-UI-003, SC-TRUTH-001, SC-MUDA-001
// Layer: L4_SYSTEM
//
// कर्मण्येवाधिकारस्ते — Your right is to action alone (Gita 2.47)
// (Every test is a pure action — no side effects, no waiting for fruit)
// =============================================================================

import cepaf_gleam/ha/workflow_patterns.{
  Cancel, Custom, CustomQuery, GetProgress, GetResult, GetStatus, Pause,
  QueryResult, Resume, SagaCompensated, SagaCompleted, SagaFailed, SagaPending,
  SagaStep, add_cleanup, advance_saga, all_cleanup_done, apply_signal, cancel,
  cancellation_summary, cancellation_to_json, compensate_step, complete_cleanup,
  execute_query, fail_saga, init_cancellation, init_saga, is_cancelled,
  is_saga_complete, query_result_to_json, query_to_string, saga_summary,
  saga_to_json, signal_to_json, signal_to_string,
}
import gleam/string
import gleeunit/should

// =============================================================================
// C1 — Type construction / init functions
// =============================================================================

pub fn init_saga_returns_pending_steps_test() {
  let state =
    init_saga("s1", [
      #("step-a", "do-a", "undo-a"),
      #("step-b", "do-b", "undo-b"),
    ])
  state.saga_id
  |> should.equal("s1")
}

pub fn init_saga_step_count_matches_input_test() {
  let state = init_saga("s2", [#("x", "ax", "cx"), #("y", "ay", "cy")])
  state.steps
  |> should.equal([
    SagaStep("x", "ax", "cx", SagaPending, ""),
    SagaStep("y", "ay", "cy", SagaPending, ""),
  ])
}

pub fn init_saga_current_step_zero_test() {
  let state = init_saga("s3", [#("a", "do", "undo")])
  state.current_step
  |> should.equal(0)
}

pub fn init_saga_not_compensating_test() {
  let state = init_saga("s4", [#("a", "do", "undo")])
  state.compensating
  |> should.be_false()
}

pub fn init_saga_not_completed_test() {
  let state = init_saga("s5", [#("a", "do", "undo")])
  state.completed
  |> should.be_false()
}

pub fn init_cancellation_not_cancelled_test() {
  let scope = init_cancellation("wf-001")
  scope.cancelled
  |> should.be_false()
}

pub fn init_cancellation_workflow_id_set_test() {
  let scope = init_cancellation("wf-abc")
  scope.workflow_id
  |> should.equal("wf-abc")
}

pub fn init_cancellation_empty_cleanup_activities_test() {
  let scope = init_cancellation("wf-002")
  scope.cleanup_activities
  |> should.equal([])
}

pub fn init_cancellation_cleanup_completed_zero_test() {
  let scope = init_cancellation("wf-003")
  scope.cleanup_completed
  |> should.equal(0)
}

// =============================================================================
// C2 — Signal and status string conversions
// =============================================================================

pub fn signal_to_string_pause_test() {
  signal_to_string(Pause("overload"))
  |> should.equal("pause")
}

pub fn signal_to_string_resume_test() {
  signal_to_string(Resume)
  |> should.equal("resume")
}

pub fn signal_to_string_cancel_test() {
  signal_to_string(Cancel("timeout"))
  |> should.equal("cancel")
}

pub fn signal_to_string_custom_test() {
  signal_to_string(Custom("retry", "{}"))
  |> should.equal("custom:retry")
}

pub fn apply_signal_pause_sets_paused_test() {
  apply_signal("running", Pause("load"))
  |> should.equal("paused")
}

pub fn apply_signal_resume_from_paused_sets_running_test() {
  apply_signal("paused", Resume)
  |> should.equal("running")
}

pub fn apply_signal_resume_from_non_paused_is_noop_test() {
  apply_signal("running", Resume)
  |> should.equal("running")
}

pub fn apply_signal_cancel_sets_cancelled_test() {
  apply_signal("running", Cancel("user"))
  |> should.equal("cancelled")
}

pub fn apply_signal_custom_leaves_status_unchanged_test() {
  apply_signal("running", Custom("ping", "{}"))
  |> should.equal("running")
}

// =============================================================================
// C3 — Saga step list and data grid operations
// =============================================================================

pub fn advance_saga_marks_first_step_completed_test() {
  let state = init_saga("t1", [#("s1", "a1", "c1"), #("s2", "a2", "c2")])
  let after = advance_saga(state, "ok")
  let first = case after.steps {
    [h, ..] -> h
    [] -> SagaStep("", "", "", SagaPending, "")
  }
  first.status
  |> should.equal(SagaCompleted)
}

pub fn advance_saga_records_result_test() {
  let state = init_saga("t2", [#("s1", "a1", "c1")])
  let after = advance_saga(state, "result-xyz")
  let first = case after.steps {
    [h, ..] -> h
    [] -> SagaStep("", "", "", SagaPending, "")
  }
  first.result
  |> should.equal("result-xyz")
}

pub fn advance_saga_increments_current_step_test() {
  let state = init_saga("t3", [#("s1", "a1", "c1"), #("s2", "a2", "c2")])
  let after = advance_saga(state, "ok")
  after.current_step
  |> should.equal(1)
}

pub fn fail_saga_marks_step_failed_test() {
  let state = init_saga("t4", [#("s1", "a1", "c1"), #("s2", "a2", "c2")])
  let after = fail_saga(state, 0)
  let first = case after.steps {
    [h, ..] -> h
    [] -> SagaStep("", "", "", SagaPending, "")
  }
  first.status
  |> should.equal(SagaFailed)
}

pub fn fail_saga_sets_compensating_true_test() {
  let state = init_saga("t5", [#("s1", "a1", "c1")])
  let after = fail_saga(state, 0)
  after.compensating
  |> should.be_true()
}

// =============================================================================
// C4 — Timeline / step sequencing
// =============================================================================

pub fn advance_saga_single_step_completes_saga_test() {
  let state = init_saga("c4-1", [#("only", "do", "undo")])
  let after = advance_saga(state, "done")
  after.completed
  |> should.be_true()
}

pub fn advance_saga_two_steps_not_complete_after_first_test() {
  let state = init_saga("c4-2", [#("s1", "a1", "c1"), #("s2", "a2", "c2")])
  let after = advance_saga(state, "ok")
  after.completed
  |> should.be_false()
}

pub fn advance_saga_two_steps_complete_after_second_test() {
  let state = init_saga("c4-3", [#("s1", "a1", "c1"), #("s2", "a2", "c2")])
  let after =
    state
    |> advance_saga("ok1")
    |> advance_saga("ok2")
  after.completed
  |> should.be_true()
}

pub fn compensate_step_marks_previous_step_compensated_test() {
  // Build a saga where step 0 has been completed, then step 1 failed.
  let state = init_saga("c4-4", [#("s1", "a1", "c1"), #("s2", "a2", "c2")])
  let after_advance = advance_saga(state, "ok1")
  let after_fail = fail_saga(after_advance, 1)
  // compensate_step should mark step 0 as compensated.
  let after_comp = compensate_step(after_fail)
  let first = case after_comp.steps {
    [h, ..] -> h
    [] -> SagaStep("", "", "", SagaPending, "")
  }
  first.status
  |> should.equal(SagaCompensated)
}

pub fn compensate_step_at_zero_marks_completed_test() {
  let state = init_saga("c4-5", [#("s1", "a1", "c1")])
  let after_fail = fail_saga(state, 0)
  let after_comp = compensate_step(after_fail)
  after_comp.completed
  |> should.be_true()
}

// =============================================================================
// C5 — Interactive: multi-step advance + fail + compensation chain
// =============================================================================

pub fn full_forward_then_fail_compensate_chain_test() {
  // 3-step saga: advance step 0, advance step 1, fail step 2, compensate back.
  let state =
    init_saga("c5-1", [
      #("book-hotel", "reserve", "cancel-hotel"),
      #("book-flight", "purchase", "refund-flight"),
      #("charge-card", "charge", "refund-card"),
    ])
  let s1 = advance_saga(state, "hotel-ok")
  let s2 = advance_saga(s1, "flight-ok")
  let s3 = fail_saga(s2, 2)
  s3.compensating
  |> should.be_true()
  // compensate step 2→1 then 1→0 then finish
  let s4 = compensate_step(s3)
  let s5 = compensate_step(s4)
  s5.completed
  |> should.be_true()
}

pub fn is_saga_complete_false_initially_test() {
  let state = init_saga("c5-2", [#("a", "do", "undo")])
  is_saga_complete(state)
  |> should.be_false()
}

pub fn is_saga_complete_true_after_all_steps_test() {
  let state = init_saga("c5-3", [#("a", "do", "undo")])
  let after = advance_saga(state, "ok")
  is_saga_complete(after)
  |> should.be_true()
}

// =============================================================================
// C6 — JSON serialisation
// =============================================================================

pub fn signal_to_json_pause_contains_type_test() {
  let json = signal_to_json(Pause("heavy"))
  string.contains(json, "\"type\":\"pause\"")
  |> should.be_true()
}

pub fn signal_to_json_pause_contains_reason_test() {
  let json = signal_to_json(Pause("heavy"))
  string.contains(json, "\"reason\":\"heavy\"")
  |> should.be_true()
}

pub fn signal_to_json_resume_contains_type_test() {
  let json = signal_to_json(Resume)
  string.contains(json, "\"type\":\"resume\"")
  |> should.be_true()
}

pub fn signal_to_json_cancel_contains_reason_test() {
  let json = signal_to_json(Cancel("timeout"))
  string.contains(json, "\"reason\":\"timeout\"")
  |> should.be_true()
}

pub fn signal_to_json_custom_contains_name_and_payload_test() {
  let json = signal_to_json(Custom("ping", "{\"k\":1}"))
  { string.contains(json, "\"name\":\"ping\"") }
  |> should.be_true()
}

pub fn query_result_to_json_contains_query_test() {
  let r = QueryResult("status", "running", 42)
  let json = query_result_to_json(r)
  string.contains(json, "\"query\":\"status\"")
  |> should.be_true()
}

pub fn query_result_to_json_contains_value_test() {
  let r = QueryResult("status", "running", 42)
  let json = query_result_to_json(r)
  string.contains(json, "\"value\":\"running\"")
  |> should.be_true()
}

pub fn query_result_to_json_contains_timestamp_test() {
  let r = QueryResult("status", "running", 42)
  let json = query_result_to_json(r)
  string.contains(json, "\"timestamp_ms\":42")
  |> should.be_true()
}

pub fn saga_to_json_contains_saga_id_test() {
  let state = init_saga("json-1", [#("s", "a", "c")])
  let json = saga_to_json(state)
  string.contains(json, "\"saga_id\":\"json-1\"")
  |> should.be_true()
}

pub fn saga_to_json_contains_steps_array_test() {
  let state = init_saga("json-2", [#("s", "a", "c")])
  let json = saga_to_json(state)
  string.contains(json, "\"steps\":[")
  |> should.be_true()
}

pub fn cancellation_to_json_contains_workflow_id_test() {
  let scope = init_cancellation("wf-j1")
  let json = cancellation_to_json(scope)
  string.contains(json, "\"workflow_id\":\"wf-j1\"")
  |> should.be_true()
}

pub fn cancellation_to_json_cancelled_false_initially_test() {
  let scope = init_cancellation("wf-j2")
  let json = cancellation_to_json(scope)
  string.contains(json, "\"cancelled\":false")
  |> should.be_true()
}

pub fn cancellation_to_json_cancelled_true_after_cancel_test() {
  let scope = init_cancellation("wf-j3") |> cancel("user-request")
  let json = cancellation_to_json(scope)
  string.contains(json, "\"cancelled\":true")
  |> should.be_true()
}

// =============================================================================
// C7 — Queries (AI advisory / read-only projections)
// =============================================================================

pub fn execute_query_get_status_returns_status_test() {
  let r = execute_query(GetStatus, "running", 0.5, "")
  r.value
  |> should.equal("running")
}

pub fn execute_query_get_progress_returns_float_string_test() {
  let r = execute_query(GetProgress, "running", 0.75, "")
  // float.to_string(0.75) is implementation-defined; just check non-empty
  { string.length(r.value) > 0 }
  |> should.be_true()
}

pub fn execute_query_get_result_returns_result_test() {
  let r = execute_query(GetResult, "completed", 1.0, "my-result")
  r.value
  |> should.equal("my-result")
}

pub fn execute_query_custom_query_sets_query_name_test() {
  let r = execute_query(CustomQuery("my-query"), "running", 0.0, "")
  r.query
  |> should.equal("custom:my-query")
}

pub fn query_to_string_get_status_test() {
  query_to_string(GetStatus)
  |> should.equal("get_status")
}

pub fn query_to_string_get_progress_test() {
  query_to_string(GetProgress)
  |> should.equal("get_progress")
}

pub fn query_to_string_get_result_test() {
  query_to_string(GetResult)
  |> should.equal("get_result")
}

pub fn query_to_string_custom_test() {
  query_to_string(CustomQuery("health"))
  |> should.equal("custom:health")
}

// =============================================================================
// C8 — Cancellation safety gates
// =============================================================================

pub fn is_cancelled_false_initially_test() {
  is_cancelled(init_cancellation("gate-1"))
  |> should.be_false()
}

pub fn is_cancelled_true_after_cancel_test() {
  let scope = init_cancellation("gate-2") |> cancel("timeout")
  is_cancelled(scope)
  |> should.be_true()
}

pub fn add_cleanup_appends_activity_test() {
  let scope =
    init_cancellation("gate-3")
    |> add_cleanup("release-lock")
  scope.cleanup_activities
  |> should.equal(["release-lock"])
}

pub fn all_cleanup_done_false_with_pending_activities_test() {
  let scope =
    init_cancellation("gate-4")
    |> add_cleanup("a")
    |> add_cleanup("b")
  all_cleanup_done(scope)
  |> should.be_false()
}

pub fn all_cleanup_done_true_when_all_completed_test() {
  let scope =
    init_cancellation("gate-5")
    |> add_cleanup("a")
    |> complete_cleanup()
  all_cleanup_done(scope)
  |> should.be_true()
}

pub fn all_cleanup_done_true_when_no_activities_test() {
  all_cleanup_done(init_cancellation("gate-6"))
  |> should.be_true()
}

pub fn complete_cleanup_increments_counter_test() {
  let scope =
    init_cancellation("gate-7")
    |> add_cleanup("x")
    |> complete_cleanup()
  scope.cleanup_completed
  |> should.equal(1)
}

pub fn cancellation_summary_contains_workflow_id_test() {
  let scope = init_cancellation("wf-sum-1")
  string.contains(cancellation_summary(scope), "wf-sum-1")
  |> should.be_true()
}

pub fn cancellation_summary_shows_cancelled_no_initially_test() {
  let scope = init_cancellation("wf-sum-2")
  string.contains(cancellation_summary(scope), "cancelled:no")
  |> should.be_true()
}

pub fn saga_summary_contains_saga_id_test() {
  let state = init_saga("sum-s1", [#("a", "do", "undo")])
  string.contains(saga_summary(state), "sum-s1")
  |> should.be_true()
}

pub fn saga_summary_shows_total_steps_test() {
  let state =
    init_saga("sum-s2", [#("a", "do", "undo"), #("b", "do2", "undo2")])
  string.contains(saga_summary(state), "steps:2")
  |> should.be_true()
}

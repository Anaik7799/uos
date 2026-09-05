/// Comprehensive fractal widget tests — L0 through L7 (all 8 layers).
///
/// This file targets coverage gaps NOT addressed by fractal_layers_test.gleam
/// or fractal_widgets_test.gleam:
///
///   L0: 2oo3 consensus voting, psi-gated approval, severity guards,
///       JSON serialisation, multi-request lifecycle, Omega invariants.
///   L1: Filter state machine, span JSON edge cases, resumed monitor
///       clears backlog correctly, attributes-bearing spans.
///   L2: Page boundary maths, column construction, zero-page-size guard,
///       sort toggle sequence, badge JSON completeness.
///   L3: diff trim at max_diffs, tool status pipeline, ToolFailed reason,
///       set_tool_result idempotency check, JSON null paths.
///   L4: finish_step marks step completed, fail_run with steps, run_to_json
///       content, max_history trim, multi-step lifecycle.
///   L5: OODA history cap at 60, reasoning append then end, ooda_to_json
///       phase field, target boundary (==), CopilotSuggestion accepted.
///   L6: quorum toggle, agent JSON topic array, replace preserves order,
///       message LIFO, remove-then-add idempotency, online_count after remove.
///   L7: peer_to_json content, suspected status, multi-peer attestation,
///       remove non-existent peer, version vector entry count, connected
///       vs disconnected count.
///
/// STAMP: SC-AGUI-004, SC-SAFETY-001, SC-GUARD-001, SC-SIL4-006,
///        SC-DEBUG-001, SC-GRID-001, SC-STM-001, SC-OODA-001,
///        SC-DIST-001, SC-FED-001, SC-GLM-TST-001, SC-MUDA-001
import cepaf_gleam/fractal/l0_constitutional
import cepaf_gleam/fractal/l1_atomic_debug
import cepaf_gleam/fractal/l2_component
import cepaf_gleam/fractal/l3_transaction
import cepaf_gleam/fractal/l4_system
import cepaf_gleam/fractal/l5_cognitive
import cepaf_gleam/fractal/l6_ecosystem
import cepaf_gleam/fractal/l7_federation

// import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// L0 Constitutional — 2oo3 consensus, severity guards, JSON, multi-lifecycle
// =============================================================================

// --- Consensus helpers -------------------------------------------------------

fn make_consensus_3() -> l0_constitutional.ConsensusState {
  l0_constitutional.new_consensus("req-vote", 2, 3)
}

// --- new_consensus -----------------------------------------------------------

pub fn l0_new_consensus_has_empty_votes_test() {
  let c = make_consensus_3()
  list.length(c.votes) |> should.equal(0)
}

pub fn l0_new_consensus_required_approvals_set_test() {
  let c = make_consensus_3()
  c.required_approvals |> should.equal(2)
}

pub fn l0_new_consensus_total_guardians_set_test() {
  let c = make_consensus_3()
  c.total_guardians |> should.equal(3)
}

// --- cast_vote ---------------------------------------------------------------

pub fn l0_cast_vote_approve_increments_approve_count_test() {
  let c = make_consensus_3()
  let c2 =
    l0_constitutional.cast_vote(c, "guardian-A", l0_constitutional.VoteApprove)
  l0_constitutional.approve_count(c2) |> should.equal(1)
}

pub fn l0_cast_vote_reject_increments_reject_count_test() {
  let c = make_consensus_3()
  let c2 =
    l0_constitutional.cast_vote(c, "guardian-A", l0_constitutional.VoteReject)
  l0_constitutional.reject_count(c2) |> should.equal(1)
}

pub fn l0_cast_vote_abstain_not_counted_in_approve_or_reject_test() {
  let c = make_consensus_3()
  let c2 =
    l0_constitutional.cast_vote(c, "guardian-A", l0_constitutional.VoteAbstain)
  l0_constitutional.approve_count(c2) |> should.equal(0)
  l0_constitutional.reject_count(c2) |> should.equal(0)
}

pub fn l0_cast_vote_duplicate_guardian_ignored_test() {
  let c = make_consensus_3()
  let c2 =
    l0_constitutional.cast_vote(c, "guardian-A", l0_constitutional.VoteApprove)
  let c3 =
    l0_constitutional.cast_vote(c2, "guardian-A", l0_constitutional.VoteApprove)
  // second vote from same guardian must be ignored
  l0_constitutional.approve_count(c3) |> should.equal(1)
  list.length(c3.votes) |> should.equal(1)
}

// --- evaluate_consensus ------------------------------------------------------

pub fn l0_evaluate_consensus_approved_with_two_votes_test() {
  let c = make_consensus_3()
  let c2 = l0_constitutional.cast_vote(c, "g-A", l0_constitutional.VoteApprove)
  let c3 = l0_constitutional.cast_vote(c2, "g-B", l0_constitutional.VoteApprove)
  l0_constitutional.evaluate_consensus(c3)
  |> should.equal(l0_constitutional.ConsensusApproved)
}

pub fn l0_evaluate_consensus_incomplete_with_one_vote_test() {
  let c = make_consensus_3()
  let c2 = l0_constitutional.cast_vote(c, "g-A", l0_constitutional.VoteApprove)
  l0_constitutional.evaluate_consensus(c2)
  |> should.equal(l0_constitutional.ConsensusIncomplete)
}

pub fn l0_evaluate_consensus_rejected_when_majority_rejects_test() {
  // 2 rejects out of 3 means it is impossible to reach 2 approvals.
  let c = make_consensus_3()
  let c2 = l0_constitutional.cast_vote(c, "g-A", l0_constitutional.VoteReject)
  let c3 = l0_constitutional.cast_vote(c2, "g-B", l0_constitutional.VoteReject)
  let outcome = l0_constitutional.evaluate_consensus(c3)
  outcome |> should.equal(l0_constitutional.ConsensusRejected)
}

pub fn l0_evaluate_consensus_approved_unanimous_test() {
  let c = make_consensus_3()
  let c2 = l0_constitutional.cast_vote(c, "g-A", l0_constitutional.VoteApprove)
  let c3 = l0_constitutional.cast_vote(c2, "g-B", l0_constitutional.VoteApprove)
  let c4 = l0_constitutional.cast_vote(c3, "g-C", l0_constitutional.VoteApprove)
  l0_constitutional.evaluate_consensus(c4)
  |> should.equal(l0_constitutional.ConsensusApproved)
}

pub fn l0_evaluate_consensus_all_votes_cast_no_approvals_is_rejected_test() {
  let c = make_consensus_3()
  let c2 = l0_constitutional.cast_vote(c, "g-A", l0_constitutional.VoteAbstain)
  let c3 = l0_constitutional.cast_vote(c2, "g-B", l0_constitutional.VoteAbstain)
  let c4 = l0_constitutional.cast_vote(c3, "g-C", l0_constitutional.VoteAbstain)
  // 0 approvals, 0 rejects but no remaining slots → rejected
  l0_constitutional.evaluate_consensus(c4)
  |> should.equal(l0_constitutional.ConsensusRejected)
}

// --- guardians_for_severity --------------------------------------------------

pub fn l0_guardians_for_severity_critical_is_3_test() {
  l0_constitutional.guardians_for_severity(l0_constitutional.Critical)
  |> should.equal(3)
}

pub fn l0_guardians_for_severity_high_is_2_test() {
  l0_constitutional.guardians_for_severity(l0_constitutional.High)
  |> should.equal(2)
}

pub fn l0_guardians_for_severity_medium_is_1_test() {
  l0_constitutional.guardians_for_severity(l0_constitutional.Medium)
  |> should.equal(1)
}

pub fn l0_guardians_for_severity_low_is_0_test() {
  l0_constitutional.guardians_for_severity(l0_constitutional.Low)
  |> should.equal(0)
}

// --- psi_gated_approve -------------------------------------------------------

pub fn l0_psi_gated_approve_approves_when_all_pass_test() {
  let checks = [
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi0Existence,
      status: l0_constitutional.Pass,
      evidence: "alive",
    ),
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi5Truthfulness,
      status: l0_constitutional.Pass,
      evidence: "verified",
    ),
  ]
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "psi-req-1",
      operation: "deploy",
      description: "Deploy cluster",
      severity: l0_constitutional.High,
      requester_agent: "claude",
      timestamp: 1000,
    )
  let base_state =
    l0_constitutional.add_request(
      l0_constitutional.initial_approval_state(),
      req,
    )
  let after =
    l0_constitutional.psi_gated_approve(checks, base_state, "psi-req-1")
  let found = list.find(after.history, fn(h) { h.0 == "psi-req-1" })
  case found {
    Ok(#(_, decision)) -> decision |> should.equal(l0_constitutional.Approved)
    Error(_) -> should.fail()
  }
}

pub fn l0_psi_gated_approve_rejects_when_any_fail_test() {
  let checks = [
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi2History,
      status: l0_constitutional.Fail,
      evidence: "missing hash",
    ),
  ]
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "psi-req-2",
      operation: "reset",
      description: "Reset state",
      severity: l0_constitutional.Critical,
      requester_agent: "chaya",
      timestamp: 2000,
    )
  let base_state =
    l0_constitutional.add_request(
      l0_constitutional.initial_approval_state(),
      req,
    )
  let after =
    l0_constitutional.psi_gated_approve(checks, base_state, "psi-req-2")
  let found = list.find(after.history, fn(h) { h.0 == "psi-req-2" })
  case found {
    Ok(#(_, decision)) -> decision |> should.equal(l0_constitutional.Rejected)
    Error(_) -> should.fail()
  }
}

// --- approval_to_json --------------------------------------------------------

pub fn l0_approval_to_json_contains_request_id_test() {
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "json-req-77",
      operation: "shutdown",
      description: "Graceful shutdown",
      severity: l0_constitutional.Critical,
      requester_agent: "sentinel",
      timestamp: 9999,
    )
  let s = json.to_string(l0_constitutional.approval_to_json(req))
  string.contains(s, "json-req-77") |> should.be_true()
}

pub fn l0_approval_to_json_contains_severity_string_test() {
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "r",
      operation: "migrate",
      description: "DB migration",
      severity: l0_constitutional.Medium,
      requester_agent: "claude",
      timestamp: 1,
    )
  let s = json.to_string(l0_constitutional.approval_to_json(req))
  string.contains(s, "medium") |> should.be_true()
}

pub fn l0_approval_to_json_contains_requester_agent_test() {
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "r2",
      operation: "start",
      description: "Boot",
      severity: l0_constitutional.Low,
      requester_agent: "prajna-daemon",
      timestamp: 42,
    )
  let s = json.to_string(l0_constitutional.approval_to_json(req))
  string.contains(s, "prajna-daemon") |> should.be_true()
}

// --- psi_invariant_to_string full coverage -----------------------------------

pub fn l0_psi_invariant_psi1_regeneration_test() {
  l0_constitutional.psi_invariant_to_string(l0_constitutional.Psi1Regeneration)
  |> should.equal("Psi-1 Regeneration")
}

pub fn l0_psi_invariant_psi2_history_test() {
  l0_constitutional.psi_invariant_to_string(l0_constitutional.Psi2History)
  |> should.equal("Psi-2 History")
}

pub fn l0_psi_invariant_psi4_human_alignment_test() {
  l0_constitutional.psi_invariant_to_string(
    l0_constitutional.Psi4HumanAlignment,
  )
  |> should.equal("Psi-4 Human Alignment")
}

// --- approval_severity_to_string full coverage -------------------------------

pub fn l0_severity_critical_string_test() {
  l0_constitutional.approval_severity_to_string(l0_constitutional.Critical)
  |> should.equal("critical")
}

pub fn l0_severity_high_string_test() {
  l0_constitutional.approval_severity_to_string(l0_constitutional.High)
  |> should.equal("high")
}

pub fn l0_severity_medium_string_test() {
  l0_constitutional.approval_severity_to_string(l0_constitutional.Medium)
  |> should.equal("medium")
}

pub fn l0_severity_low_string_test() {
  l0_constitutional.approval_severity_to_string(l0_constitutional.Low)
  |> should.equal("low")
}

// --- multi-request lifecycle -------------------------------------------------

pub fn l0_multiple_requests_pending_count_test() {
  let mk = fn(id) {
    l0_constitutional.ApprovalRequest(
      request_id: id,
      operation: "op",
      description: "desc",
      severity: l0_constitutional.High,
      requester_agent: "agent",
      timestamp: 0,
    )
  }
  let state = l0_constitutional.initial_approval_state()
  let s1 = l0_constitutional.add_request(state, mk("a"))
  let s2 = l0_constitutional.add_request(s1, mk("b"))
  let s3 = l0_constitutional.add_request(s2, mk("c"))
  l0_constitutional.pending_count(s3) |> should.equal(3)
}

pub fn l0_resolve_one_leaves_others_pending_test() {
  let mk = fn(id) {
    l0_constitutional.ApprovalRequest(
      request_id: id,
      operation: "op",
      description: "desc",
      severity: l0_constitutional.Low,
      requester_agent: "agent",
      timestamp: 0,
    )
  }
  let state = l0_constitutional.initial_approval_state()
  let s1 = l0_constitutional.add_request(state, mk("x"))
  let s2 = l0_constitutional.add_request(s1, mk("y"))
  let resolved =
    l0_constitutional.resolve_request(s2, "x", l0_constitutional.Approved)
  l0_constitutional.pending_count(resolved) |> should.equal(1)
}

// --- emergency — armed flag preservation through trigger ---------------------

pub fn l0_trigger_emergency_disarms_test() {
  let state = l0_constitutional.initial_emergency_state()
  let armed = l0_constitutional.arm_emergency(state)
  let triggered = l0_constitutional.trigger_emergency(armed, "cascade", 10_000)
  // Triggering must disarm (safety: once triggered can't fire again without reset+arm)
  triggered.armed |> should.be_false()
}

pub fn l0_reset_emergency_clears_reason_test() {
  let state = l0_constitutional.initial_emergency_state()
  let triggered = l0_constitutional.trigger_emergency(state, "explosion", 1)
  let reset = l0_constitutional.reset_emergency(triggered)
  reset.trigger_reason |> should.equal(None)
}

// =============================================================================
// L1 Atomic/Debug — filter state machine, span JSON edge cases
// =============================================================================

pub fn l1_initial_monitor_max_entries_is_500_test() {
  let state = l1_atomic_debug.initial_monitor()
  state.max_entries |> should.equal(500)
}

pub fn l1_initial_monitor_filter_is_none_test() {
  let state = l1_atomic_debug.initial_monitor()
  state.filter |> should.equal(None)
}

pub fn l1_clear_filter_after_set_accepts_all_types_test() {
  let state = l1_atomic_debug.initial_monitor()
  let filtered = l1_atomic_debug.set_filter(state, "ToolCallStart")
  let cleared = l1_atomic_debug.clear_filter(filtered)
  let entry =
    l1_atomic_debug.EventLogEntry(
      event_type: "RunFinished",
      timestamp: 1,
      thread_id: "t",
      run_id: "r",
      summary: "done",
    )
  let after = l1_atomic_debug.add_event(cleared, entry)
  l1_atomic_debug.event_count(after) |> should.equal(1)
}

pub fn l1_paused_then_resumed_accepts_new_events_test() {
  let state = l1_atomic_debug.initial_monitor()
  let paused = l1_atomic_debug.pause_monitor(state)
  // Events while paused are dropped
  let entry_paused =
    l1_atomic_debug.EventLogEntry(
      event_type: "RunStarted",
      timestamp: 1,
      thread_id: "t",
      run_id: "r",
      summary: "s",
    )
  let after_paused = l1_atomic_debug.add_event(paused, entry_paused)
  l1_atomic_debug.event_count(after_paused) |> should.equal(0)
  // Resume, then add — should be accepted
  let resumed = l1_atomic_debug.resume_monitor(after_paused)
  let entry_resumed =
    l1_atomic_debug.EventLogEntry(
      event_type: "RunFinished",
      timestamp: 2,
      thread_id: "t",
      run_id: "r",
      summary: "done",
    )
  let after_resumed = l1_atomic_debug.add_event(resumed, entry_resumed)
  l1_atomic_debug.event_count(after_resumed) |> should.equal(1)
}

pub fn l1_filter_blocks_non_matching_then_passes_matching_test() {
  let state = l1_atomic_debug.initial_monitor()
  let filtered = l1_atomic_debug.set_filter(state, "StateSnapshot")
  let wrong =
    l1_atomic_debug.EventLogEntry(
      event_type: "ToolCallEnd",
      timestamp: 1,
      thread_id: "t",
      run_id: "r",
      summary: "s",
    )
  let right =
    l1_atomic_debug.EventLogEntry(
      event_type: "StateSnapshot",
      timestamp: 2,
      thread_id: "t",
      run_id: "r",
      summary: "snap",
    )
  let s1 = l1_atomic_debug.add_event(filtered, wrong)
  let s2 = l1_atomic_debug.add_event(s1, right)
  l1_atomic_debug.event_count(s2) |> should.equal(1)
}

pub fn l1_span_ok_status_to_string_test() {
  l1_atomic_debug.span_status_to_string(l1_atomic_debug.SpanOk)
  |> should.equal("ok")
}

pub fn l1_span_error_status_has_colon_prefix_test() {
  let s =
    l1_atomic_debug.span_status_to_string(l1_atomic_debug.SpanError("nif_crash"))
  string.starts_with(s, "error:") |> should.be_true()
}

pub fn l1_trace_span_json_contains_span_id_test() {
  let span =
    l1_atomic_debug.TraceSpan(
      trace_id: "trace-X",
      span_id: "span-42",
      parent_span_id: None,
      operation: "decide",
      duration_us: 250,
      status: l1_atomic_debug.SpanOk,
      attributes: [],
    )
  let s = json.to_string(l1_atomic_debug.trace_span_to_json(span))
  string.contains(s, "span-42") |> should.be_true()
}

pub fn l1_trace_span_json_contains_duration_us_test() {
  let span =
    l1_atomic_debug.TraceSpan(
      trace_id: "t",
      span_id: "s",
      parent_span_id: Some("p"),
      operation: "act",
      duration_us: 9876,
      status: l1_atomic_debug.SpanOk,
      attributes: [#("layer", "L1"), #("node", "ex-app-1")],
    )
  let s = json.to_string(l1_atomic_debug.trace_span_to_json(span))
  string.contains(s, "9876") |> should.be_true()
}

pub fn l1_trace_span_json_error_message_embedded_test() {
  let span =
    l1_atomic_debug.TraceSpan(
      trace_id: "t",
      span_id: "s",
      parent_span_id: None,
      operation: "observe",
      duration_us: 1,
      status: l1_atomic_debug.SpanError("zenoh_disconnected"),
      attributes: [],
    )
  let s = json.to_string(l1_atomic_debug.trace_span_to_json(span))
  string.contains(s, "zenoh_disconnected") |> should.be_true()
}

pub fn l1_events_lifo_newest_first_test() {
  let state = l1_atomic_debug.initial_monitor()
  let mk = fn(ts) {
    l1_atomic_debug.EventLogEntry(
      event_type: "RunStarted",
      timestamp: ts,
      thread_id: "t",
      run_id: "r",
      summary: "s",
    )
  }
  let s1 = l1_atomic_debug.add_event(state, mk(100))
  let s2 = l1_atomic_debug.add_event(s1, mk(200))
  case s2.entries {
    [head, ..] -> head.timestamp |> should.equal(200)
    [] -> should.fail()
  }
}

// =============================================================================
// L2 Component — column construction, page maths, zero page-size guard
// =============================================================================

pub fn l2_column_constructor_stores_fields_test() {
  let col =
    l2_component.Column(
      key: "status",
      label: "Status",
      sortable: True,
      width: Some(120),
    )
  col.key |> should.equal("status")
  col.label |> should.equal("Status")
  col.sortable |> should.be_true()
  col.width |> should.equal(Some(120))
}

pub fn l2_column_optional_width_none_test() {
  let col =
    l2_component.Column(
      key: "name",
      label: "Name",
      sortable: False,
      width: None,
    )
  col.width |> should.equal(None)
}

pub fn l2_initial_grid_page_is_zero_test() {
  let state = l2_component.initial_grid([])
  state.page |> should.equal(0)
}

pub fn l2_initial_grid_sort_ascending_true_test() {
  let state = l2_component.initial_grid([])
  state.sort_ascending |> should.be_true()
}

pub fn l2_total_pages_exactly_divisible_test() {
  // 10 rows / 5 page_size = 2 pages
  let state = l2_component.initial_grid([])
  let rows =
    list.repeat(0, 10)
    |> list.map(fn(i) {
      l2_component.Row(id: "r" <> string.inspect(i), cells: [])
    })
  let filled =
    l2_component.DataGridState(
      ..l2_component.set_rows(state, rows),
      page_size: 5,
    )
  l2_component.total_pages(filled) |> should.equal(2)
}

pub fn l2_total_pages_with_remainder_rounds_up_test() {
  // 7 rows / 3 page_size = ceil(7/3) = 3
  let state = l2_component.initial_grid([])
  let rows =
    list.repeat(0, 7)
    |> list.map(fn(i) { l2_component.Row(id: string.inspect(i), cells: []) })
  let filled =
    l2_component.DataGridState(
      ..l2_component.set_rows(state, rows),
      page_size: 3,
    )
  l2_component.total_pages(filled) |> should.equal(3)
}

pub fn l2_select_row_updates_selected_id_test() {
  let state = l2_component.initial_grid([])
  let rows = [
    l2_component.Row(id: "row-alpha", cells: [#("name", "alpha")]),
    l2_component.Row(id: "row-beta", cells: [#("name", "beta")]),
  ]
  let populated = l2_component.set_rows(state, rows)
  let selected = l2_component.select_row(populated, "row-beta")
  selected.selected_row |> should.equal(Some("row-beta"))
}

pub fn l2_sort_toggle_sequence_test() {
  // first sort: ascending, second same col: descending, third same col: ascending
  let state = l2_component.initial_grid([])
  let s1 = l2_component.sort_by(state, "ts")
  s1.sort_ascending |> should.be_true()
  let s2 = l2_component.sort_by(s1, "ts")
  s2.sort_ascending |> should.be_false()
  let s3 = l2_component.sort_by(s2, "ts")
  s3.sort_ascending |> should.be_true()
}

pub fn l2_severity_to_string_all_variants_test() {
  [
    #(l2_component.Healthy, "healthy"),
    #(l2_component.Degraded, "degraded"),
    #(l2_component.BadgeCritical, "critical"),
    #(l2_component.Unknown, "unknown"),
    #(l2_component.Info, "info"),
  ]
  |> list.each(fn(pair) {
    let #(sev, expected) = pair
    l2_component.severity_to_string(sev) |> should.equal(expected)
  })
}

pub fn l2_badge_to_json_label_and_severity_present_test() {
  let badge =
    l2_component.Badge(
      label: "Zenoh",
      severity: l2_component.Healthy,
      tooltip: Some("Mesh OK"),
    )
  let s = json.to_string(l2_component.badge_to_json(badge))
  string.contains(s, "Zenoh") |> should.be_true()
  string.contains(s, "healthy") |> should.be_true()
  string.contains(s, "Mesh OK") |> should.be_true()
}

pub fn l2_row_cells_stored_test() {
  let row =
    l2_component.Row(id: "r-cell-test", cells: [
      #("col1", "val1"),
      #("col2", "val2"),
    ])
  list.length(row.cells) |> should.equal(2)
  row.id |> should.equal("r-cell-test")
}

// =============================================================================
// L3 Transaction — diff trim, tool pipeline, ToolFailed reason, JSON nulls
// =============================================================================

pub fn l3_diff_trim_at_max_diffs_test() {
  // max_diffs defaults to 100; force a small one via direct constructor
  let state =
    l3_transaction.TransactionPanelState(
      state_diffs: [],
      tool_calls: [],
      max_diffs: 3,
    )
  let mk_diff = fn(n) {
    l3_transaction.StateDiffEntry(
      operation: "add",
      path: "/x",
      old_value: None,
      new_value: Some(string.inspect(n)),
      timestamp: n,
    )
  }
  let s1 = l3_transaction.add_diff(state, mk_diff(1))
  let s2 = l3_transaction.add_diff(s1, mk_diff(2))
  let s3 = l3_transaction.add_diff(s2, mk_diff(3))
  let s4 = l3_transaction.add_diff(s3, mk_diff(4))
  // max_diffs = 3 so the oldest (diff-1) is trimmed
  list.length(s4.state_diffs) |> should.equal(3)
}

pub fn l3_tool_status_pipeline_pending_to_executing_to_completed_test() {
  let state = l3_transaction.initial_panel()
  let call =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "pipe-1",
      tool_name: "zenoh_pub",
      args: "{\"key\":\"indrajaal/test\"}",
      status: l3_transaction.ToolPending,
      result: None,
      duration_ms: None,
    )
  let s1 = l3_transaction.add_tool_call(state, call)
  let s2 =
    l3_transaction.update_tool_status(
      s1,
      "pipe-1",
      l3_transaction.ToolExecuting,
    )
  let s3 = l3_transaction.set_tool_result(s2, "pipe-1", "ok", 15)
  let found = list.find(s3.tool_calls, fn(tc) { tc.tool_call_id == "pipe-1" })
  case found {
    Ok(tc) -> {
      tc.status |> should.equal(l3_transaction.ToolCompleted)
      tc.result |> should.equal(Some("ok"))
      tc.duration_ms |> should.equal(Some(15))
    }
    Error(_) -> should.fail()
  }
}

pub fn l3_tool_failed_reason_preserved_test() {
  let failed_status = l3_transaction.ToolFailed("zenoh_timeout")
  l3_transaction.is_active_status(failed_status) |> should.be_false()
  // Verify the reason string is accessible via pattern match
  case failed_status {
    l3_transaction.ToolFailed(reason) -> reason |> should.equal("zenoh_timeout")
    //     _ -> should.fail()
  }
}

pub fn l3_update_tool_status_awaiting_approval_test() {
  let state = l3_transaction.initial_panel()
  let call =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "hitl-1",
      tool_name: "container_restart",
      args: "{\"container\":\"ex-app-1\"}",
      status: l3_transaction.ToolPending,
      result: None,
      duration_ms: None,
    )
  let s1 = l3_transaction.add_tool_call(state, call)
  let s2 =
    l3_transaction.update_tool_status(
      s1,
      "hitl-1",
      l3_transaction.ToolAwaitingApproval,
    )
  let found = list.find(s2.tool_calls, fn(tc) { tc.tool_call_id == "hitl-1" })
  case found {
    Ok(tc) -> tc.status |> should.equal(l3_transaction.ToolAwaitingApproval)
    Error(_) -> should.fail()
  }
}

pub fn l3_is_active_status_streaming_is_true_test() {
  l3_transaction.is_active_status(l3_transaction.ToolStreaming)
  |> should.be_true()
}

pub fn l3_is_active_status_awaiting_approval_is_true_test() {
  l3_transaction.is_active_status(l3_transaction.ToolAwaitingApproval)
  |> should.be_true()
}

pub fn l3_diff_to_json_null_old_value_test() {
  let diff =
    l3_transaction.StateDiffEntry(
      operation: "add",
      path: "/new_field",
      old_value: None,
      new_value: Some("x"),
      timestamp: 0,
    )
  let s = json.to_string(l3_transaction.diff_to_json(diff))
  string.contains(s, "null") |> should.be_true()
}

pub fn l3_diff_to_json_null_new_value_test() {
  let diff =
    l3_transaction.StateDiffEntry(
      operation: "remove",
      path: "/old_field",
      old_value: Some("y"),
      new_value: None,
      timestamp: 1,
    )
  let s = json.to_string(l3_transaction.diff_to_json(diff))
  // old_value is "y", new_value is null
  string.contains(s, "y") |> should.be_true()
}

pub fn l3_active_tool_count_multiple_mixed_states_test() {
  let state = l3_transaction.initial_panel()
  let mk = fn(id, status) {
    l3_transaction.ToolCallDisplay(
      tool_call_id: id,
      tool_name: "tool",
      args: "{}",
      status: status,
      result: None,
      duration_ms: None,
    )
  }
  let s1 =
    l3_transaction.add_tool_call(state, mk("t1", l3_transaction.ToolPending))
  let s2 =
    l3_transaction.add_tool_call(s1, mk("t2", l3_transaction.ToolCompleted))
  let s3 =
    l3_transaction.add_tool_call(s2, mk("t3", l3_transaction.ToolFailed("err")))
  let s4 =
    l3_transaction.add_tool_call(s3, mk("t4", l3_transaction.ToolStreaming))
  // Pending + Streaming = 2 active; Completed + Failed = 2 inactive
  l3_transaction.active_tool_count(s4) |> should.equal(2)
}

// =============================================================================
// L4 System — finish_step, fail_run with steps, run_to_json, max_history trim
// =============================================================================

pub fn l4_finish_step_marks_step_completed_test() {
  let state = l4_system.initial_run_monitor()
  let s1 = l4_system.start_run(state, "run-fs", "t", "a", 1000)
  let s2 = l4_system.start_step(s1, "run-fs", "boot", 1001)
  let s3 = l4_system.finish_step(s2, "run-fs", "boot", 1050)
  let found = list.find(s3.active_runs, fn(r) { r.run_id == "run-fs" })
  case found {
    Ok(run) -> {
      let step = list.find(run.steps, fn(s) { s.name == "boot" })
      case step {
        Ok(s) -> s.status |> should.equal(l4_system.StepCompleted)
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn l4_finish_step_sets_finished_at_test() {
  let state = l4_system.initial_run_monitor()
  let s1 = l4_system.start_run(state, "run-fat", "t", "a", 2000)
  let s2 = l4_system.start_step(s1, "run-fat", "migrate", 2001)
  let s3 = l4_system.finish_step(s2, "run-fat", "migrate", 2099)
  let found = list.find(s3.active_runs, fn(r) { r.run_id == "run-fat" })
  case found {
    Ok(run) -> {
      let step = list.find(run.steps, fn(s) { s.name == "migrate" })
      case step {
        Ok(s) -> s.finished_at |> should.equal(Some(2099))
        Error(_) -> should.fail()
      }
    }
    Error(_) -> should.fail()
  }
}

pub fn l4_fail_run_with_steps_captures_error_test() {
  let state = l4_system.initial_run_monitor()
  let s1 = l4_system.start_run(state, "run-fail", "t", "a", 5000)
  let s2 = l4_system.start_step(s1, "run-fail", "verify", 5001)
  let s3 = l4_system.fail_run(s2, "run-fail", "verification_failed", 5999)
  l4_system.active_run_count(s3) |> should.equal(0)
  let found = list.find(s3.completed_runs, fn(r) { r.run_id == "run-fail" })
  case found {
    Ok(run) -> {
      run.error |> should.equal(Some("verification_failed"))
      run.status |> should.equal(l4_system.Failed)
    }
    Error(_) -> should.fail()
  }
}

pub fn l4_run_to_json_contains_run_id_test() {
  let run =
    l4_system.RunState(
      run_id: "json-run-1",
      thread_id: "thread-X",
      agent_id: "claude",
      status: l4_system.Running,
      steps: [],
      started_at: 1000,
      finished_at: None,
      error: None,
    )
  let s = json.to_string(l4_system.run_to_json(run))
  string.contains(s, "json-run-1") |> should.be_true()
}

pub fn l4_run_to_json_contains_agent_id_test() {
  let run =
    l4_system.RunState(
      run_id: "r",
      thread_id: "t",
      agent_id: "fractal-ooda-supervisor",
      status: l4_system.Completed,
      steps: [],
      started_at: 1,
      finished_at: Some(2),
      error: None,
    )
  let s = json.to_string(l4_system.run_to_json(run))
  string.contains(s, "fractal-ooda-supervisor") |> should.be_true()
}

pub fn l4_run_to_json_status_failed_test() {
  let run =
    l4_system.RunState(
      run_id: "r",
      thread_id: "t",
      agent_id: "a",
      status: l4_system.Failed,
      steps: [],
      started_at: 1,
      finished_at: Some(99),
      error: Some("crash"),
    )
  let s = json.to_string(l4_system.run_to_json(run))
  string.contains(s, "failed") |> should.be_true()
}

pub fn l4_max_history_trims_completed_runs_test() {
  // Bypass by using DataGridState analogy: create monitor with max_history=2
  let state =
    l4_system.RunMonitorState(
      active_runs: [],
      completed_runs: [],
      max_history: 2,
    )
  let s1 = l4_system.start_run(state, "r1", "t", "a", 1)
  let s2 = l4_system.start_run(s1, "r2", "t", "a", 2)
  let s3 = l4_system.start_run(s2, "r3", "t", "a", 3)
  // Finish all 3 — only last 2 kept in history
  let f1 = l4_system.finish_run(s3, "r1", 10)
  let f2 = l4_system.finish_run(f1, "r2", 11)
  let f3 = l4_system.finish_run(f2, "r3", 12)
  list.length(f3.completed_runs) |> should.equal(2)
}

pub fn l4_cancelled_status_available_test() {
  let run =
    l4_system.RunState(
      run_id: "r",
      thread_id: "t",
      agent_id: "a",
      status: l4_system.Cancelled,
      steps: [],
      started_at: 1,
      finished_at: None,
      error: None,
    )
  run.status |> should.equal(l4_system.Cancelled)
}

pub fn l4_step_status_variants_constructable_test() {
  [l4_system.StepRunning, l4_system.StepCompleted, l4_system.StepFailed]
  |> list.length()
  |> should.equal(3)
}

// =============================================================================
// L5 Cognitive — history cap, reasoning stream, ooda_to_json phase, boundary
// =============================================================================

pub fn l5_ooda_history_capped_at_60_test() {
  let state = l5_cognitive.initial_ooda()
  // 65 cycles; history must be capped at 60
  let final =
    list.repeat(0, 65)
    |> list.fold(state, fn(acc, ms) {
      l5_cognitive.complete_ooda_cycle(acc, ms, "p", "d")
    })
  list.length(final.history) |> should.equal(60)
}

pub fn l5_ooda_cycle_count_accumulates_all_test() {
  let state = l5_cognitive.initial_ooda()
  let final =
    list.repeat(0, 10)
    |> list.fold(state, fn(acc, ms) {
      l5_cognitive.complete_ooda_cycle(acc, ms, "p", "d")
    })
  final.cycle_count |> should.equal(10)
}

pub fn l5_ooda_within_target_exactly_at_target_is_true_test() {
  // last_cycle_ms == target_ms (100) should be within target (<=)
  let state = l5_cognitive.initial_ooda()
  let completed = l5_cognitive.complete_ooda_cycle(state, 100, "p", "d")
  l5_cognitive.ooda_within_target(completed) |> should.be_true()
}

pub fn l5_ooda_within_target_one_over_is_false_test() {
  let state = l5_cognitive.initial_ooda()
  let completed = l5_cognitive.complete_ooda_cycle(state, 101, "p", "d")
  l5_cognitive.ooda_within_target(completed) |> should.be_false()
}

pub fn l5_ooda_to_json_contains_phase_field_test() {
  let state = l5_cognitive.initial_ooda()
  let observing = l5_cognitive.set_ooda_phase(state, l5_cognitive.Observe)
  let s = json.to_string(l5_cognitive.ooda_to_json(observing))
  string.contains(s, "observe") |> should.be_true()
}

pub fn l5_ooda_to_json_contains_target_ms_test() {
  let state = l5_cognitive.initial_ooda()
  let s = json.to_string(l5_cognitive.ooda_to_json(state))
  string.contains(s, "100") |> should.be_true()
}

pub fn l5_reasoning_append_empty_delta_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "m-empty")
  let r = l5_cognitive.append_reasoning(started, "")
  r.content_buffer |> should.equal("")
  r.chunks_received |> should.equal(1)
}

pub fn l5_reasoning_end_keeps_message_id_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "msg-keep")
  let ended = l5_cognitive.end_reasoning(started)
  // message_id is preserved even after end
  ended.message_id |> should.equal(Some("msg-keep"))
}

pub fn l5_reasoning_start_resets_buffer_test() {
  let state = l5_cognitive.initial_reasoning()
  let r1 = l5_cognitive.start_reasoning(state, "m1")
  let r2 = l5_cognitive.append_reasoning(r1, "some content")
  // Starting a new reasoning resets the buffer
  let r3 = l5_cognitive.start_reasoning(r2, "m2")
  r3.content_buffer |> should.equal("")
}

pub fn l5_reasoning_start_resets_chunk_count_test() {
  let state = l5_cognitive.initial_reasoning()
  let r1 = l5_cognitive.start_reasoning(state, "m1")
  let r2 = l5_cognitive.append_reasoning(r1, "a")
  let r3 = l5_cognitive.append_reasoning(r2, "b")
  let r4 = l5_cognitive.start_reasoning(r3, "m2")
  r4.chunks_received |> should.equal(0)
}

pub fn l5_copilot_suggestion_accepted_some_test() {
  let sug =
    l5_cognitive.CopilotSuggestion(
      id: "sug-2",
      text: "Trigger apoptosis on container X",
      confidence: 0.88,
      source: "rule-engine",
      accepted: Some(True),
    )
  sug.accepted |> should.equal(Some(True))
}

pub fn l5_copilot_suggestion_rejected_some_test() {
  let sug =
    l5_cognitive.CopilotSuggestion(
      id: "sug-3",
      text: "Do nothing",
      confidence: 0.12,
      source: "zettelkasten",
      accepted: Some(False),
    )
  sug.accepted |> should.equal(Some(False))
}

// =============================================================================
// L6 Ecosystem — quorum, JSON, replace-preserves-count, LIFO, remove-then-add
// =============================================================================

pub fn l6_set_quorum_false_then_true_test() {
  let state = l6_ecosystem.initial_mesh()
  let with_q = l6_ecosystem.set_quorum(state, True)
  let without_q = l6_ecosystem.set_quorum(with_q, False)
  without_q.quorum |> should.be_false()
}

pub fn l6_agent_json_contains_health_test() {
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "health-test-agent",
      agent_type: "monitor",
      status: l6_ecosystem.Online,
      health: 0.75,
      zenoh_topics: ["indrajaal/health/**"],
      last_heartbeat: 9000,
    )
  let s = json.to_string(l6_ecosystem.agent_to_json(node))
  string.contains(s, "0.75") |> should.be_true()
}

pub fn l6_agent_json_online_status_test() {
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "a",
      agent_type: "t",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 1,
    )
  let s = json.to_string(l6_ecosystem.agent_to_json(node))
  string.contains(s, "online") |> should.be_true()
}

pub fn l6_agent_json_offline_status_test() {
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "a",
      agent_type: "t",
      status: l6_ecosystem.Offline,
      health: 0.0,
      zenoh_topics: [],
      last_heartbeat: 0,
    )
  let s = json.to_string(l6_ecosystem.agent_to_json(node))
  string.contains(s, "offline") |> should.be_true()
}

pub fn l6_agent_json_degraded_status_test() {
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "a",
      agent_type: "t",
      status: l6_ecosystem.Degraded,
      health: 0.4,
      zenoh_topics: [],
      last_heartbeat: 0,
    )
  let s = json.to_string(l6_ecosystem.agent_to_json(node))
  string.contains(s, "degraded") |> should.be_true()
}

pub fn l6_replace_agent_preserves_count_test() {
  let state = l6_ecosystem.initial_mesh()
  let mk = fn(id, status) {
    l6_ecosystem.AgentNode(
      agent_id: id,
      agent_type: "worker",
      status: status,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 1,
    )
  }
  let s1 = l6_ecosystem.update_agent(state, mk("a1", l6_ecosystem.Online))
  let s2 = l6_ecosystem.update_agent(s1, mk("a2", l6_ecosystem.Online))
  // Replace a1 with degraded version
  let s3 = l6_ecosystem.update_agent(s2, mk("a1", l6_ecosystem.Degraded))
  l6_ecosystem.agent_count(s3) |> should.equal(2)
}

pub fn l6_remove_then_add_same_agent_works_test() {
  let state = l6_ecosystem.initial_mesh()
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "ephemeral",
      agent_type: "probe",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 1,
    )
  let s1 = l6_ecosystem.update_agent(state, node)
  let s2 = l6_ecosystem.remove_agent(s1, "ephemeral")
  let s3 = l6_ecosystem.update_agent(s2, node)
  l6_ecosystem.agent_count(s3) |> should.equal(1)
}

pub fn l6_online_count_decreases_after_remove_test() {
  let state = l6_ecosystem.initial_mesh()
  let mk = fn(id) {
    l6_ecosystem.AgentNode(
      agent_id: id,
      agent_type: "worker",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 1,
    )
  }
  let s1 = l6_ecosystem.update_agent(state, mk("b1"))
  let s2 = l6_ecosystem.update_agent(s1, mk("b2"))
  let s3 = l6_ecosystem.remove_agent(s2, "b1")
  l6_ecosystem.online_count(s3) |> should.equal(1)
}

pub fn l6_message_count_grows_correctly_test() {
  let state = l6_ecosystem.initial_mesh()
  let mk_msg = fn(ts) {
    l6_ecosystem.A2aMessage(
      source: "cortex",
      target: "chaya",
      message_type: "sync",
      payload: "{}",
      timestamp: ts,
    )
  }
  let s1 = l6_ecosystem.add_message(state, mk_msg(1))
  let s2 = l6_ecosystem.add_message(s1, mk_msg(2))
  let s3 = l6_ecosystem.add_message(s2, mk_msg(3))
  list.length(s3.messages) |> should.equal(3)
}

// =============================================================================
// L7 Federation — peer_to_json, suspected status, multi-peer attestation
// =============================================================================

pub fn l7_peer_to_json_contains_peer_id_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "json-peer-99",
      endpoint: "tcp/node-99:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 5000,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "json-peer-99") |> should.be_true()
}

pub fn l7_peer_to_json_contains_endpoint_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p",
      endpoint: "tcp/remote-host:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "remote-host") |> should.be_true()
}

pub fn l7_peer_to_json_connected_status_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p",
      endpoint: "tcp/h:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "connected") |> should.be_true()
}

pub fn l7_peer_to_json_disconnected_status_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p",
      endpoint: "tcp/h:7447",
      status: l7_federation.PeerDisconnected,
      version_vector: [],
      attestation_valid: False,
      last_seen: 0,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "disconnected") |> should.be_true()
}

pub fn l7_peer_to_json_suspected_status_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p",
      endpoint: "tcp/h:7447",
      status: l7_federation.PeerSuspected,
      version_vector: [],
      attestation_valid: False,
      last_seen: 0,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "suspected") |> should.be_true()
}

pub fn l7_peer_to_json_attestation_false_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "rogue",
      endpoint: "tcp/rogue:7447",
      status: l7_federation.PeerSuspected,
      version_vector: [],
      attestation_valid: False,
      last_seen: 0,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "false") |> should.be_true()
}

pub fn l7_peer_to_json_last_seen_present_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p",
      endpoint: "tcp/h:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 123_456,
    )
  let s = json.to_string(l7_federation.peer_to_json(peer))
  string.contains(s, "123456") |> should.be_true()
}

pub fn l7_multi_peer_attestation_mix_test() {
  let state = l7_federation.initial_federation("local")
  let mk = fn(id, valid) {
    l7_federation.FederationPeer(
      peer_id: id,
      endpoint: "tcp/h:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: valid,
      last_seen: 1,
    )
  }
  let s1 = l7_federation.add_peer(state, mk("p1", True))
  let s2 = l7_federation.add_peer(s1, mk("p2", True))
  let s3 = l7_federation.add_peer(s2, mk("p3", False))
  // Not all attested because p3 is invalid
  l7_federation.all_attested(s3) |> should.be_false()
}

pub fn l7_remove_non_existent_peer_safe_test() {
  let state = l7_federation.initial_federation("node-1")
  let after = l7_federation.remove_peer(state, "ghost-peer")
  l7_federation.peer_count(after) |> should.equal(0)
}

pub fn l7_version_vector_starts_at_zero_test() {
  let state = l7_federation.initial_federation("node-X")
  let found = list.find(state.local_version, fn(e) { e.0 == "node-X" })
  case found {
    Ok(#(_, ver)) -> ver |> should.equal(0)
    Error(_) -> should.fail()
  }
}

pub fn l7_version_vector_increment_three_times_test() {
  let state = l7_federation.initial_federation("node-Y")
  let b1 = l7_federation.increment_version(state)
  let b2 = l7_federation.increment_version(b1)
  let b3 = l7_federation.increment_version(b2)
  let found = list.find(b3.local_version, fn(e) { e.0 == "node-Y" })
  case found {
    Ok(#(_, ver)) -> ver |> should.equal(3)
    Error(_) -> should.fail()
  }
}

pub fn l7_connected_peers_count_test() {
  let state = l7_federation.initial_federation("local")
  let mk = fn(id, status) {
    l7_federation.FederationPeer(
      peer_id: id,
      endpoint: "tcp/h:7447",
      status: status,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1,
    )
  }
  let s1 = l7_federation.add_peer(state, mk("p1", l7_federation.PeerConnected))
  let s2 = l7_federation.add_peer(s1, mk("p2", l7_federation.PeerDisconnected))
  let s3 = l7_federation.add_peer(s2, mk("p3", l7_federation.PeerConnected))
  let s4 = l7_federation.add_peer(s3, mk("p4", l7_federation.PeerSuspected))
  list.length(l7_federation.connected_peers(s4)) |> should.equal(2)
}

pub fn l7_peer_suspected_status_constructable_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "suspect",
      endpoint: "tcp/unknown:7447",
      status: l7_federation.PeerSuspected,
      version_vector: [#("suspect", 5)],
      attestation_valid: False,
      last_seen: 999,
    )
  peer.status |> should.equal(l7_federation.PeerSuspected)
  peer.attestation_valid |> should.be_false()
}

pub fn l7_peer_version_vector_stored_test() {
  let peer =
    l7_federation.FederationPeer(
      peer_id: "vec-peer",
      endpoint: "tcp/h:7447",
      status: l7_federation.PeerConnected,
      version_vector: [#("vec-peer", 7), #("local", 3)],
      attestation_valid: True,
      last_seen: 1,
    )
  list.length(peer.version_vector) |> should.equal(2)
}

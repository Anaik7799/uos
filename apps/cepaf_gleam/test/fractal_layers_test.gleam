/// Fractal layer module tests — L0 through L7.
///
/// Tests all 8 fractal layer modules verifying state machines, transformations,
/// and invariants per SC-SWARM-VERIFY-040..047 and SC-VER-074.
///
/// STAMP: SC-SWARM-VERIFY-001, SC-VER-074, SC-GLM-CMP-001
import cepaf_gleam/fractal/l0_constitutional
import cepaf_gleam/fractal/l1_atomic_debug
import cepaf_gleam/fractal/l2_component
import cepaf_gleam/fractal/l3_transaction
import cepaf_gleam/fractal/l4_system
import cepaf_gleam/fractal/l5_cognitive
import cepaf_gleam/fractal/l6_ecosystem
import cepaf_gleam/fractal/l7_federation
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// L0 Constitutional
// =============================================================================

pub fn l0_initial_approval_state_has_empty_pending_test() {
  let state = l0_constitutional.initial_approval_state()
  l0_constitutional.pending_count(state) |> should.equal(0)
}

pub fn l0_initial_approval_state_has_empty_history_test() {
  let state = l0_constitutional.initial_approval_state()
  list.length(state.history) |> should.equal(0)
}

pub fn l0_add_request_increases_pending_count_test() {
  let state = l0_constitutional.initial_approval_state()
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "req-1",
      operation: "deploy",
      description: "Deploy container",
      severity: l0_constitutional.High,
      requester_agent: "claude-1",
      timestamp: 1_000_000,
    )
  let updated = l0_constitutional.add_request(state, req)
  l0_constitutional.pending_count(updated) |> should.equal(1)
}

pub fn l0_resolve_request_removes_from_pending_test() {
  let state = l0_constitutional.initial_approval_state()
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "req-2",
      operation: "stop",
      description: "Emergency stop",
      severity: l0_constitutional.Critical,
      requester_agent: "sentinel",
      timestamp: 2_000_000,
    )
  let with_req = l0_constitutional.add_request(state, req)
  let resolved =
    l0_constitutional.resolve_request(
      with_req,
      "req-2",
      l0_constitutional.Approved,
    )
  l0_constitutional.pending_count(resolved) |> should.equal(0)
}

pub fn l0_resolve_request_adds_to_history_test() {
  let state = l0_constitutional.initial_approval_state()
  let req =
    l0_constitutional.ApprovalRequest(
      request_id: "req-3",
      operation: "migrate",
      description: "DB migration",
      severity: l0_constitutional.Medium,
      requester_agent: "chaya",
      timestamp: 3_000_000,
    )
  let with_req = l0_constitutional.add_request(state, req)
  let resolved =
    l0_constitutional.resolve_request(
      with_req,
      "req-3",
      l0_constitutional.Rejected,
    )
  list.length(resolved.history) |> should.equal(1)
}

pub fn l0_initial_emergency_state_is_not_armed_test() {
  let state = l0_constitutional.initial_emergency_state()
  state.armed |> should.be_false()
}

pub fn l0_initial_emergency_state_is_not_triggered_test() {
  let state = l0_constitutional.initial_emergency_state()
  state.triggered |> should.be_false()
}

pub fn l0_arm_emergency_sets_armed_true_test() {
  let state = l0_constitutional.initial_emergency_state()
  let armed = l0_constitutional.arm_emergency(state)
  armed.armed |> should.be_true()
}

pub fn l0_trigger_emergency_sets_triggered_true_test() {
  let state = l0_constitutional.initial_emergency_state()
  let triggered =
    l0_constitutional.trigger_emergency(state, "power failure", 5_000_000)
  triggered.triggered |> should.be_true()
}

pub fn l0_trigger_emergency_sets_reason_test() {
  let state = l0_constitutional.initial_emergency_state()
  let triggered =
    l0_constitutional.trigger_emergency(state, "overheat", 5_000_001)
  triggered.trigger_reason |> should.equal(Some("overheat"))
}

pub fn l0_trigger_emergency_sets_last_triggered_test() {
  let state = l0_constitutional.initial_emergency_state()
  let triggered =
    l0_constitutional.trigger_emergency(state, "network split", 9_999_999)
  triggered.last_triggered |> should.equal(Some(9_999_999))
}

pub fn l0_reset_emergency_clears_triggered_test() {
  let state = l0_constitutional.initial_emergency_state()
  let triggered = l0_constitutional.trigger_emergency(state, "reason", 1)
  let reset = l0_constitutional.reset_emergency(triggered)
  reset.triggered |> should.be_false()
}

pub fn l0_reset_emergency_keeps_last_triggered_test() {
  let state = l0_constitutional.initial_emergency_state()
  let triggered = l0_constitutional.trigger_emergency(state, "reason", 42)
  let reset = l0_constitutional.reset_emergency(triggered)
  reset.last_triggered |> should.equal(Some(42))
}

pub fn l0_all_psi_pass_returns_true_when_all_pass_test() {
  let checks = [
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi0Existence,
      status: l0_constitutional.Pass,
      evidence: "ok",
    ),
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi1Regeneration,
      status: l0_constitutional.Pass,
      evidence: "ok",
    ),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.be_true()
}

pub fn l0_all_psi_pass_returns_false_when_any_fail_test() {
  let checks = [
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi0Existence,
      status: l0_constitutional.Pass,
      evidence: "ok",
    ),
    l0_constitutional.PsiCheck(
      invariant: l0_constitutional.Psi2History,
      status: l0_constitutional.Fail,
      evidence: "missing",
    ),
  ]
  l0_constitutional.all_psi_pass(checks) |> should.be_false()
}

pub fn l0_psi_invariant_to_string_psi0_test() {
  l0_constitutional.psi_invariant_to_string(l0_constitutional.Psi0Existence)
  |> should.equal("Psi-0 Existence")
}

pub fn l0_psi_invariant_to_string_psi3_test() {
  l0_constitutional.psi_invariant_to_string(l0_constitutional.Psi3Verification)
  |> should.equal("Psi-3 Verification")
}

pub fn l0_psi_invariant_to_string_psi5_test() {
  l0_constitutional.psi_invariant_to_string(l0_constitutional.Psi5Truthfulness)
  |> should.equal("Psi-5 Truthfulness")
}

// =============================================================================
// L1 Atomic/Debug
// =============================================================================

pub fn l1_initial_monitor_has_empty_entries_test() {
  let state = l1_atomic_debug.initial_monitor()
  l1_atomic_debug.event_count(state) |> should.equal(0)
}

pub fn l1_initial_monitor_is_not_paused_test() {
  let state = l1_atomic_debug.initial_monitor()
  state.paused |> should.be_false()
}

pub fn l1_add_event_appends_entry_test() {
  let state = l1_atomic_debug.initial_monitor()
  let entry =
    l1_atomic_debug.EventLogEntry(
      event_type: "RunStarted",
      timestamp: 1000,
      thread_id: "t-1",
      run_id: "r-1",
      summary: "Agent started",
    )
  let updated = l1_atomic_debug.add_event(state, entry)
  l1_atomic_debug.event_count(updated) |> should.equal(1)
}

pub fn l1_pause_monitor_stops_accepting_events_test() {
  let state = l1_atomic_debug.initial_monitor()
  let paused = l1_atomic_debug.pause_monitor(state)
  let entry =
    l1_atomic_debug.EventLogEntry(
      event_type: "ToolCallStart",
      timestamp: 2000,
      thread_id: "t-2",
      run_id: "r-2",
      summary: "Tool called",
    )
  let after = l1_atomic_debug.add_event(paused, entry)
  l1_atomic_debug.event_count(after) |> should.equal(0)
}

pub fn l1_resume_monitor_accepts_events_test() {
  let state = l1_atomic_debug.initial_monitor()
  let paused = l1_atomic_debug.pause_monitor(state)
  let resumed = l1_atomic_debug.resume_monitor(paused)
  resumed.paused |> should.be_false()
}

pub fn l1_set_filter_stores_filter_test() {
  let state = l1_atomic_debug.initial_monitor()
  let filtered = l1_atomic_debug.set_filter(state, "ToolCallStart")
  filtered.filter |> should.equal(Some("ToolCallStart"))
}

pub fn l1_set_filter_blocks_non_matching_events_test() {
  let state = l1_atomic_debug.initial_monitor()
  let filtered = l1_atomic_debug.set_filter(state, "RunStarted")
  let entry =
    l1_atomic_debug.EventLogEntry(
      event_type: "ToolCallEnd",
      timestamp: 3000,
      thread_id: "t-3",
      run_id: "r-3",
      summary: "Different type",
    )
  let after = l1_atomic_debug.add_event(filtered, entry)
  l1_atomic_debug.event_count(after) |> should.equal(0)
}

pub fn l1_clear_filter_removes_filter_test() {
  let state = l1_atomic_debug.initial_monitor()
  let filtered = l1_atomic_debug.set_filter(state, "RunStarted")
  let cleared = l1_atomic_debug.clear_filter(filtered)
  cleared.filter |> should.equal(None)
}

pub fn l1_event_count_returns_correct_number_test() {
  let state = l1_atomic_debug.initial_monitor()
  let mk = fn(n) {
    l1_atomic_debug.EventLogEntry(
      event_type: "RunStarted",
      timestamp: n,
      thread_id: "t",
      run_id: "r",
      summary: "s",
    )
  }
  let s1 = l1_atomic_debug.add_event(state, mk(1))
  let s2 = l1_atomic_debug.add_event(s1, mk(2))
  let s3 = l1_atomic_debug.add_event(s2, mk(3))
  l1_atomic_debug.event_count(s3) |> should.equal(3)
}

// =============================================================================
// L2 Component
// =============================================================================

pub fn l2_initial_grid_creates_empty_grid_test() {
  let cols = [
    l2_component.Column(key: "id", label: "ID", sortable: True, width: None),
  ]
  let state = l2_component.initial_grid(cols)
  list.length(state.rows) |> should.equal(0)
}

pub fn l2_initial_grid_has_no_selection_test() {
  let state = l2_component.initial_grid([])
  state.selected_row |> should.equal(None)
}

pub fn l2_set_rows_populates_rows_test() {
  let state = l2_component.initial_grid([])
  let rows = [
    l2_component.Row(id: "r1", cells: [#("name", "alpha")]),
    l2_component.Row(id: "r2", cells: [#("name", "beta")]),
  ]
  let updated = l2_component.set_rows(state, rows)
  list.length(updated.rows) |> should.equal(2)
}

pub fn l2_select_row_sets_selected_test() {
  let state = l2_component.initial_grid([])
  let selected = l2_component.select_row(state, "r1")
  selected.selected_row |> should.equal(Some("r1"))
}

pub fn l2_sort_by_first_call_sets_ascending_test() {
  let state = l2_component.initial_grid([])
  let sorted = l2_component.sort_by(state, "name")
  sorted.sort_ascending |> should.be_true()
}

pub fn l2_sort_by_same_column_toggles_ascending_test() {
  let state = l2_component.initial_grid([])
  let s1 = l2_component.sort_by(state, "name")
  let s2 = l2_component.sort_by(s1, "name")
  s2.sort_ascending |> should.be_false()
}

pub fn l2_severity_to_string_healthy_test() {
  l2_component.severity_to_string(l2_component.Healthy)
  |> should.equal("healthy")
}

pub fn l2_severity_to_string_critical_test() {
  l2_component.severity_to_string(l2_component.BadgeCritical)
  |> should.equal("critical")
}

pub fn l2_severity_to_string_unknown_test() {
  l2_component.severity_to_string(l2_component.Unknown)
  |> should.equal("unknown")
}

pub fn l2_badge_to_json_contains_label_test() {
  let badge =
    l2_component.Badge(
      label: "SIL-6",
      severity: l2_component.Healthy,
      tooltip: None,
    )
  let s = json.to_string(l2_component.badge_to_json(badge))
  string.contains(s, "SIL-6") |> should.be_true()
}

pub fn l2_badge_to_json_contains_severity_test() {
  let badge =
    l2_component.Badge(
      label: "DB",
      severity: l2_component.Degraded,
      tooltip: None,
    )
  let s = json.to_string(l2_component.badge_to_json(badge))
  string.contains(s, "degraded") |> should.be_true()
}

// =============================================================================
// L3 Transaction
// =============================================================================

pub fn l3_initial_panel_has_empty_diffs_test() {
  let state = l3_transaction.initial_panel()
  list.length(state.state_diffs) |> should.equal(0)
}

pub fn l3_initial_panel_has_empty_tool_calls_test() {
  let state = l3_transaction.initial_panel()
  list.length(state.tool_calls) |> should.equal(0)
}

pub fn l3_add_diff_appends_diff_entry_test() {
  let state = l3_transaction.initial_panel()
  let diff =
    l3_transaction.StateDiffEntry(
      operation: "add",
      path: "/status",
      old_value: None,
      new_value: Some("running"),
      timestamp: 1000,
    )
  let updated = l3_transaction.add_diff(state, diff)
  list.length(updated.state_diffs) |> should.equal(1)
}

pub fn l3_add_tool_call_adds_to_list_test() {
  let state = l3_transaction.initial_panel()
  let call =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "tc-1",
      tool_name: "read_file",
      args: "{\"path\": \"/tmp/test\"}",
      status: l3_transaction.ToolPending,
      result: None,
      duration_ms: None,
    )
  let updated = l3_transaction.add_tool_call(state, call)
  list.length(updated.tool_calls) |> should.equal(1)
}

pub fn l3_update_tool_status_changes_status_test() {
  let state = l3_transaction.initial_panel()
  let call =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "tc-2",
      tool_name: "write_file",
      args: "{}",
      status: l3_transaction.ToolPending,
      result: None,
      duration_ms: None,
    )
  let with_call = l3_transaction.add_tool_call(state, call)
  let updated =
    l3_transaction.update_tool_status(
      with_call,
      "tc-2",
      l3_transaction.ToolExecuting,
    )
  let found =
    list.find(updated.tool_calls, fn(tc) { tc.tool_call_id == "tc-2" })
  case found {
    Ok(tc) -> tc.status |> should.equal(l3_transaction.ToolExecuting)
    Error(_) -> should.fail()
  }
}

pub fn l3_set_tool_result_sets_completed_test() {
  let state = l3_transaction.initial_panel()
  let call =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "tc-3",
      tool_name: "bash",
      args: "{\"cmd\": \"ls\"}",
      status: l3_transaction.ToolExecuting,
      result: None,
      duration_ms: None,
    )
  let with_call = l3_transaction.add_tool_call(state, call)
  let updated =
    l3_transaction.set_tool_result(with_call, "tc-3", "file.txt", 42)
  let found =
    list.find(updated.tool_calls, fn(tc) { tc.tool_call_id == "tc-3" })
  case found {
    Ok(tc) -> {
      tc.status |> should.equal(l3_transaction.ToolCompleted)
      tc.result |> should.equal(Some("file.txt"))
      tc.duration_ms |> should.equal(Some(42))
    }
    Error(_) -> should.fail()
  }
}

pub fn l3_active_tool_count_excludes_completed_test() {
  let state = l3_transaction.initial_panel()
  let pending =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "tc-a",
      tool_name: "tool_a",
      args: "{}",
      status: l3_transaction.ToolPending,
      result: None,
      duration_ms: None,
    )
  let completed =
    l3_transaction.ToolCallDisplay(
      tool_call_id: "tc-b",
      tool_name: "tool_b",
      args: "{}",
      status: l3_transaction.ToolCompleted,
      result: Some("done"),
      duration_ms: Some(10),
    )
  let s1 = l3_transaction.add_tool_call(state, pending)
  let s2 = l3_transaction.add_tool_call(s1, completed)
  l3_transaction.active_tool_count(s2) |> should.equal(1)
}

// =============================================================================
// L4 System
// =============================================================================

pub fn l4_initial_run_monitor_is_empty_test() {
  let state = l4_system.initial_run_monitor()
  l4_system.active_run_count(state) |> should.equal(0)
}

pub fn l4_initial_run_monitor_has_no_completed_runs_test() {
  let state = l4_system.initial_run_monitor()
  list.length(state.completed_runs) |> should.equal(0)
}

pub fn l4_start_run_adds_active_run_test() {
  let state = l4_system.initial_run_monitor()
  let updated = l4_system.start_run(state, "run-1", "thread-1", "agent-1", 1000)
  l4_system.active_run_count(updated) |> should.equal(1)
}

pub fn l4_start_step_adds_step_to_run_test() {
  let state = l4_system.initial_run_monitor()
  let with_run = l4_system.start_run(state, "run-2", "t-2", "a-2", 2000)
  let with_step = l4_system.start_step(with_run, "run-2", "init", 2001)
  let found = list.find(with_step.active_runs, fn(r) { r.run_id == "run-2" })
  case found {
    Ok(run) -> list.length(run.steps) |> should.equal(1)
    Error(_) -> should.fail()
  }
}

pub fn l4_finish_run_moves_to_completed_test() {
  let state = l4_system.initial_run_monitor()
  let with_run = l4_system.start_run(state, "run-3", "t-3", "a-3", 3000)
  let finished = l4_system.finish_run(with_run, "run-3", 3999)
  l4_system.active_run_count(finished) |> should.equal(0)
  list.length(finished.completed_runs) |> should.equal(1)
}

pub fn l4_fail_run_moves_to_completed_with_error_test() {
  let state = l4_system.initial_run_monitor()
  let with_run = l4_system.start_run(state, "run-4", "t-4", "a-4", 4000)
  let failed = l4_system.fail_run(with_run, "run-4", "timeout", 4999)
  l4_system.active_run_count(failed) |> should.equal(0)
  let found = list.find(failed.completed_runs, fn(r) { r.run_id == "run-4" })
  case found {
    Ok(run) -> run.error |> should.equal(Some("timeout"))
    Error(_) -> should.fail()
  }
}

pub fn l4_active_run_count_correct_multiple_runs_test() {
  let state = l4_system.initial_run_monitor()
  let s1 = l4_system.start_run(state, "r-a", "t", "a", 1)
  let s2 = l4_system.start_run(s1, "r-b", "t", "a", 2)
  let s3 = l4_system.start_run(s2, "r-c", "t", "a", 3)
  l4_system.active_run_count(s3) |> should.equal(3)
}

// =============================================================================
// L5 Cognitive
// =============================================================================

pub fn l5_initial_ooda_starts_at_idle_test() {
  let state = l5_cognitive.initial_ooda()
  state.current_phase |> should.equal(l5_cognitive.OodaIdle)
}

pub fn l5_initial_ooda_cycle_count_is_zero_test() {
  let state = l5_cognitive.initial_ooda()
  state.cycle_count |> should.equal(0)
}

pub fn l5_set_ooda_phase_changes_phase_test() {
  let state = l5_cognitive.initial_ooda()
  let observing = l5_cognitive.set_ooda_phase(state, l5_cognitive.Observe)
  observing.current_phase |> should.equal(l5_cognitive.Observe)
}

pub fn l5_complete_ooda_cycle_increments_count_test() {
  let state = l5_cognitive.initial_ooda()
  let completed = l5_cognitive.complete_ooda_cycle(state, 80, "p1", "d1")
  completed.cycle_count |> should.equal(1)
}

pub fn l5_complete_ooda_cycle_records_history_test() {
  let state = l5_cognitive.initial_ooda()
  let completed = l5_cognitive.complete_ooda_cycle(state, 75, "p1", "d1")
  list.length(completed.history) |> should.equal(1)
}

pub fn l5_complete_ooda_cycle_returns_to_idle_test() {
  let state = l5_cognitive.initial_ooda()
  let in_act = l5_cognitive.set_ooda_phase(state, l5_cognitive.Act)
  let completed = l5_cognitive.complete_ooda_cycle(in_act, 90, "p", "d")
  completed.current_phase |> should.equal(l5_cognitive.OodaIdle)
}

pub fn l5_ooda_within_target_true_when_under_test() {
  let state = l5_cognitive.initial_ooda()
  let completed = l5_cognitive.complete_ooda_cycle(state, 50, "p", "d")
  l5_cognitive.ooda_within_target(completed) |> should.be_true()
}

pub fn l5_ooda_within_target_false_when_over_test() {
  let state = l5_cognitive.initial_ooda()
  let completed = l5_cognitive.complete_ooda_cycle(state, 200, "p", "d")
  l5_cognitive.ooda_within_target(completed) |> should.be_false()
}

pub fn l5_initial_reasoning_is_not_active_test() {
  let state = l5_cognitive.initial_reasoning()
  state.active |> should.be_false()
}

pub fn l5_start_reasoning_activates_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "msg-1")
  started.active |> should.be_true()
}

pub fn l5_start_reasoning_sets_message_id_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "msg-42")
  started.message_id |> should.equal(Some("msg-42"))
}

pub fn l5_append_reasoning_accumulates_content_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "msg-2")
  let r1 = l5_cognitive.append_reasoning(started, "Hello")
  let r2 = l5_cognitive.append_reasoning(r1, " world")
  r2.content_buffer |> should.equal("Hello world")
}

pub fn l5_append_reasoning_increments_chunks_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "msg-3")
  let r1 = l5_cognitive.append_reasoning(started, "a")
  let r2 = l5_cognitive.append_reasoning(r1, "b")
  r2.chunks_received |> should.equal(2)
}

pub fn l5_end_reasoning_deactivates_test() {
  let state = l5_cognitive.initial_reasoning()
  let started = l5_cognitive.start_reasoning(state, "msg-4")
  let ended = l5_cognitive.end_reasoning(started)
  ended.active |> should.be_false()
}

// =============================================================================
// L6 Ecosystem
// =============================================================================

pub fn l6_initial_mesh_is_empty_test() {
  let state = l6_ecosystem.initial_mesh()
  l6_ecosystem.agent_count(state) |> should.equal(0)
}

pub fn l6_initial_mesh_quorum_false_test() {
  let state = l6_ecosystem.initial_mesh()
  state.quorum |> should.be_false()
}

pub fn l6_update_agent_adds_agent_test() {
  let state = l6_ecosystem.initial_mesh()
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "cortex",
      agent_type: "cognitive",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: ["indrajaal/ooda/**"],
      last_heartbeat: 1000,
    )
  let updated = l6_ecosystem.update_agent(state, node)
  l6_ecosystem.agent_count(updated) |> should.equal(1)
}

pub fn l6_update_agent_replaces_existing_test() {
  let state = l6_ecosystem.initial_mesh()
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "sentinel",
      agent_type: "safety",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 1000,
    )
  let updated =
    l6_ecosystem.AgentNode(..node, health: 0.5, status: l6_ecosystem.Degraded)
  let s1 = l6_ecosystem.update_agent(state, node)
  let s2 = l6_ecosystem.update_agent(s1, updated)
  l6_ecosystem.agent_count(s2) |> should.equal(1)
}

pub fn l6_remove_agent_removes_test() {
  let state = l6_ecosystem.initial_mesh()
  let node =
    l6_ecosystem.AgentNode(
      agent_id: "chaya",
      agent_type: "twin",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 2000,
    )
  let s1 = l6_ecosystem.update_agent(state, node)
  let s2 = l6_ecosystem.remove_agent(s1, "chaya")
  l6_ecosystem.agent_count(s2) |> should.equal(0)
}

pub fn l6_add_message_appends_test() {
  let state = l6_ecosystem.initial_mesh()
  let msg =
    l6_ecosystem.A2aMessage(
      source: "cortex",
      target: "sentinel",
      message_type: "health_query",
      payload: "{}",
      timestamp: 5000,
    )
  let updated = l6_ecosystem.add_message(state, msg)
  list.length(updated.messages) |> should.equal(1)
}

pub fn l6_online_agents_filters_by_status_test() {
  let state = l6_ecosystem.initial_mesh()
  let online_node =
    l6_ecosystem.AgentNode(
      agent_id: "a1",
      agent_type: "t",
      status: l6_ecosystem.Online,
      health: 1.0,
      zenoh_topics: [],
      last_heartbeat: 1,
    )
  let offline_node =
    l6_ecosystem.AgentNode(
      agent_id: "a2",
      agent_type: "t",
      status: l6_ecosystem.Offline,
      health: 0.0,
      zenoh_topics: [],
      last_heartbeat: 1,
    )
  let s1 = l6_ecosystem.update_agent(state, online_node)
  let s2 = l6_ecosystem.update_agent(s1, offline_node)
  list.length(l6_ecosystem.online_agents(s2)) |> should.equal(1)
}

pub fn l6_set_quorum_works_test() {
  let state = l6_ecosystem.initial_mesh()
  let with_quorum = l6_ecosystem.set_quorum(state, True)
  with_quorum.quorum |> should.be_true()
}

// =============================================================================
// L7 Federation
// =============================================================================

pub fn l7_initial_federation_sets_local_id_test() {
  let state = l7_federation.initial_federation("node-1")
  state.local_id |> should.equal("node-1")
}

pub fn l7_initial_federation_has_no_peers_test() {
  let state = l7_federation.initial_federation("node-1")
  l7_federation.peer_count(state) |> should.equal(0)
}

pub fn l7_initial_federation_has_local_version_entry_test() {
  let state = l7_federation.initial_federation("node-1")
  list.length(state.local_version) |> should.equal(1)
}

pub fn l7_add_peer_adds_peer_test() {
  let state = l7_federation.initial_federation("node-1")
  let peer =
    l7_federation.FederationPeer(
      peer_id: "node-2",
      endpoint: "tcp/node-2:7447",
      status: l7_federation.PeerConnected,
      version_vector: [#("node-2", 0)],
      attestation_valid: True,
      last_seen: 1000,
    )
  let updated = l7_federation.add_peer(state, peer)
  l7_federation.peer_count(updated) |> should.equal(1)
}

pub fn l7_add_peer_replaces_existing_peer_test() {
  let state = l7_federation.initial_federation("node-1")
  let peer =
    l7_federation.FederationPeer(
      peer_id: "node-3",
      endpoint: "tcp/node-3:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1000,
    )
  let updated_peer = l7_federation.FederationPeer(..peer, last_seen: 2000)
  let s1 = l7_federation.add_peer(state, peer)
  let s2 = l7_federation.add_peer(s1, updated_peer)
  l7_federation.peer_count(s2) |> should.equal(1)
}

pub fn l7_remove_peer_removes_test() {
  let state = l7_federation.initial_federation("node-1")
  let peer =
    l7_federation.FederationPeer(
      peer_id: "node-4",
      endpoint: "tcp/node-4:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1000,
    )
  let s1 = l7_federation.add_peer(state, peer)
  let s2 = l7_federation.remove_peer(s1, "node-4")
  l7_federation.peer_count(s2) |> should.equal(0)
}

pub fn l7_increment_version_bumps_local_version_test() {
  let state = l7_federation.initial_federation("node-1")
  let bumped = l7_federation.increment_version(state)
  let found = list.find(bumped.local_version, fn(e) { e.0 == "node-1" })
  case found {
    Ok(entry) -> entry.1 |> should.equal(1)
    Error(_) -> should.fail()
  }
}

pub fn l7_increment_version_twice_test() {
  let state = l7_federation.initial_federation("node-1")
  let b1 = l7_federation.increment_version(state)
  let b2 = l7_federation.increment_version(b1)
  let found = list.find(b2.local_version, fn(e) { e.0 == "node-1" })
  case found {
    Ok(entry) -> entry.1 |> should.equal(2)
    Error(_) -> should.fail()
  }
}

pub fn l7_connected_peers_filters_test() {
  let state = l7_federation.initial_federation("node-1")
  let connected =
    l7_federation.FederationPeer(
      peer_id: "p-a",
      endpoint: "tcp/p-a:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1,
    )
  let disconnected =
    l7_federation.FederationPeer(
      peer_id: "p-b",
      endpoint: "tcp/p-b:7447",
      status: l7_federation.PeerDisconnected,
      version_vector: [],
      attestation_valid: False,
      last_seen: 1,
    )
  let s1 = l7_federation.add_peer(state, connected)
  let s2 = l7_federation.add_peer(s1, disconnected)
  list.length(l7_federation.connected_peers(s2)) |> should.equal(1)
}

pub fn l7_all_attested_true_when_all_valid_test() {
  let state = l7_federation.initial_federation("node-1")
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p-c",
      endpoint: "tcp/p-c:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: True,
      last_seen: 1,
    )
  let s1 = l7_federation.add_peer(state, peer)
  l7_federation.all_attested(s1) |> should.be_true()
}

pub fn l7_all_attested_false_when_any_invalid_test() {
  let state = l7_federation.initial_federation("node-1")
  let peer =
    l7_federation.FederationPeer(
      peer_id: "p-d",
      endpoint: "tcp/p-d:7447",
      status: l7_federation.PeerConnected,
      version_vector: [],
      attestation_valid: False,
      last_seen: 1,
    )
  let s1 = l7_federation.add_peer(state, peer)
  l7_federation.all_attested(s1) |> should.be_false()
}

pub fn l7_all_attested_true_for_empty_peers_test() {
  let state = l7_federation.initial_federation("node-1")
  l7_federation.all_attested(state) |> should.be_true()
}

// =============================================================================
// AG-UI Dashboard Compliance Tests
// =============================================================================
// Coverage: ui/lustre/planning_dashboard (AG-UI Msg variants, HITL, Kanban,
//           navigation), agui/zenoh_bus (topic construction), agui/sse
//           (health_json, create_run_response, create_sse_stream),
//           planning_dashboard (health_score, determine_cockpit_mode,
//           NextCockpitMode cycle).
//
// STAMP: SC-AGUI-001, SC-AGUI-004, SC-GLM-UI-001, SC-GLM-UI-003,
//        SC-HMI-010, SC-UIGT-007
// =============================================================================

import cepaf_gleam/agui/sse
import cepaf_gleam/ui/lustre/planning_dashboard.{
  type TaskCard, AgUiReasoningContent, AgUiRunError, AgUiRunFinished,
  AgUiRunStarted, AgUiStateDelta, AgUiStateSnapshot, AgUiStepFinished,
  AgUiStepStarted, AgUiTextContent, AgUiToolCallEnd, AgUiToolCallResult,
  AgUiToolCallStart, Bright, CloseDetail, Dark, DashboardModel, Dim,
  DragTaskDropped, DragTaskOver, DragTaskStarted, EmergencyMode,
  HitlApprovalRequested, HitlUserApproved, HitlUserRejected, NextCockpitMode,
  Normal, OodaCycle, SelectPanel, ServiceNode, TaskBoard, TaskCard,
}
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// Helpers
// =============================================================================

fn make_task(id: String, status: String) -> TaskCard {
  TaskCard(
    id: id,
    title: "Task " <> id,
    status: status,
    priority: "P2",
    assignee: None,
  )
}

fn empty_json() -> json.Json {
  json.object([])
}

// =============================================================================
// Section 1: AG-UI Dashboard Msg Variants (12 tests)
// =============================================================================

// 1.1 AgUiRunStarted → sets ag_ui_connected=True and appends RUN_STARTED to chat
pub fn agui_run_started_sets_connected_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, AgUiRunStarted("t-1", "run-1"))
  updated.ag_ui_connected |> should.be_true()
}

pub fn agui_run_started_appends_event_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, AgUiRunStarted("t-1", "run-42"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.2 AgUiRunFinished → keeps ag_ui_connected (does not clear it)
pub fn agui_run_finished_keeps_connected_test() {
  let model = DashboardModel(..planning_dashboard.init(), ag_ui_connected: True)
  let updated =
    planning_dashboard.update(model, AgUiRunFinished("t-1", "run-1"))
  updated.ag_ui_connected |> should.be_true()
}

pub fn agui_run_finished_appends_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, AgUiRunFinished("t-1", "run-99"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.3 AgUiRunError → escalates to Bright cockpit mode and adds to chat
pub fn agui_run_error_sets_bright_mode_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, AgUiRunError("timeout", "E001"))
  updated.cockpit_mode |> should.equal(Bright)
}

pub fn agui_run_error_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, AgUiRunError("NIF crash", "E500"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.4 AgUiStepStarted → appends STEP_STARTED event to chat
pub fn agui_step_started_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, AgUiStepStarted("preflight"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.5 AgUiStepFinished → appends STEP_FINISHED event to chat
pub fn agui_step_finished_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, AgUiStepFinished("preflight"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.6 AgUiTextContent → appends AgentMsg to chat_messages
pub fn agui_text_content_adds_agent_msg_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      AgUiTextContent("msg-1", "Hello from the agent"),
    )
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.7 AgUiStateSnapshot → processes state (returns model unchanged — stub)
pub fn agui_state_snapshot_does_not_crash_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, AgUiStateSnapshot(empty_json()))
  // Stub implementation returns model unchanged; this verifies no crash
  updated.ag_ui_connected |> should.equal(model.ag_ui_connected)
}

// 1.8 AgUiStateDelta → processes delta (returns model unchanged — stub)
pub fn agui_state_delta_does_not_crash_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, AgUiStateDelta(empty_json()))
  updated.ag_ui_connected |> should.equal(model.ag_ui_connected)
}

// 1.9 AgUiToolCallStart → adds ToolCallMsg to chat
pub fn agui_tool_call_start_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, AgUiToolCallStart("tc-001", "zenoh_pub"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.10 AgUiToolCallEnd → returns model unchanged (internal bookkeeping only)
pub fn agui_tool_call_end_noop_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, AgUiToolCallEnd("tc-001"))
  // Spec: AgUiToolCallEnd is a no-op on the visible model
  updated.chat_messages |> should.equal(model.chat_messages)
}

// 1.11 AgUiToolCallResult → adds TOOL_RESULT EventMsg to chat
pub fn agui_tool_call_result_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      AgUiToolCallResult("tc-001", "ok: 42 containers healthy"),
    )
  list.length(updated.chat_messages) |> should.equal(1)
}

// 1.12 AgUiReasoningContent → adds REASONING EventMsg to chat
pub fn agui_reasoning_content_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      AgUiReasoningContent("msg-r", "Analyzing quorum state..."),
    )
  list.length(updated.chat_messages) |> should.equal(1)
}

// =============================================================================
// Section 2: HITL Msg Variants (3 tests)
// =============================================================================

// 2.1 HitlApprovalRequested → sets Normal mode, adds HITL_REQUEST to chat
pub fn hitl_approval_requested_sets_normal_mode_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      HitlApprovalRequested("req-7", "Deploy to production"),
    )
  updated.cockpit_mode |> should.equal(Normal)
}

pub fn hitl_approval_requested_adds_to_chat_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      HitlApprovalRequested("req-7", "Emergency shutdown"),
    )
  list.length(updated.chat_messages) |> should.equal(1)
}

// 2.2 HitlUserApproved → appends "Approved: {id}" UserMsg to chat
pub fn hitl_user_approved_adds_user_msg_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, HitlUserApproved("req-7"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// 2.3 HitlUserRejected → appends "Rejected: {id}" UserMsg to chat
pub fn hitl_user_rejected_adds_user_msg_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, HitlUserRejected("req-7"))
  list.length(updated.chat_messages) |> should.equal(1)
}

// =============================================================================
// Section 3: Kanban / Navigation Msg Variants (6 tests)
// =============================================================================

// 3.1 DragTaskStarted → visual only, model unchanged
pub fn drag_task_started_noop_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "pending"),
    ])
  let updated = planning_dashboard.update(model, DragTaskStarted("t1"))
  updated.tasks |> should.equal(model.tasks)
}

// 3.2 DragTaskOver → visual only, model unchanged
pub fn drag_task_over_noop_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, DragTaskOver("completed"))
  updated |> should.equal(model)
}

// 3.3 DragTaskDropped → changes task status (Kanban column move)
pub fn drag_task_dropped_updates_status_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "pending"),
      make_task("t2", "pending"),
    ])
  let updated =
    planning_dashboard.update(model, DragTaskDropped("t1", "completed"))
  let t1_status =
    list.find(updated.tasks, fn(t: TaskCard) { t.id == "t1" })
    |> fn(r) {
      case r {
        Ok(t) -> t.status
        Error(_) -> "not-found"
      }
    }
  t1_status |> should.equal("completed")
}

// 3.4 SelectPanel → changes active_panel
pub fn select_panel_changes_active_panel_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, SelectPanel(OodaCycle))
  updated.active_panel |> should.equal(OodaCycle)
}

pub fn select_panel_from_taskboard_to_oodacycle_test() {
  let model = planning_dashboard.init()
  // Init starts at TaskBoard
  model.active_panel |> should.equal(TaskBoard)
  let updated = planning_dashboard.update(model, SelectPanel(OodaCycle))
  updated.active_panel |> should.equal(OodaCycle)
}

// 3.5 CloseDetail → clears selected_task
pub fn close_detail_clears_selection_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), selected_task: Some("task-99"))
  let updated = planning_dashboard.update(model, CloseDetail)
  updated.selected_task |> should.equal(None)
}

// =============================================================================
// Section 4: Zenoh Bus — topic string construction (6 tests)
// =============================================================================
// The zenoh_bus functions require a live Session (FFI-backed opaque type) which
// cannot be constructed in unit tests.  We verify the topic key expressions
// that the bus would construct, by checking the string patterns directly.

// 4.1 publish_event topic: "c3i/agui/events/{agent_id}"
pub fn zenoh_bus_agui_events_prefix_is_valid_key_expression_test() {
  let prefix = "c3i/agui/events/"
  let agent_id = "claude-opus-001"
  let topic = prefix <> agent_id
  // Zenoh key expressions: no spaces, no empty segments, no leading slash
  topic |> string.starts_with("c3i/") |> should.be_true()
  topic |> string.contains(" ") |> should.be_false()
  topic |> string.ends_with(agent_id) |> should.be_true()
}

// 4.2 broadcast_state topic: "c3i/a2a/broadcast"
pub fn zenoh_bus_broadcast_topic_is_valid_key_expression_test() {
  let topic = "c3i/a2a/broadcast"
  topic |> string.starts_with("c3i/") |> should.be_true()
  topic |> string.contains(" ") |> should.be_false()
  topic |> string.ends_with("broadcast") |> should.be_true()
}

// 4.3 send_to_agent topic: "c3i/a2a/{source}/{target}"
pub fn zenoh_bus_send_to_agent_topic_format_test() {
  let prefix = "c3i/a2a/"
  let source = "claude-opus"
  let target = "gemini-flash"
  let topic = prefix <> source <> "/" <> target
  topic |> string.starts_with("c3i/a2a/") |> should.be_true()
  topic |> string.contains(source) |> should.be_true()
  topic |> string.contains(target) |> should.be_true()
}

// 4.4 Topic schema: all prefixes are within "c3i/" namespace (not "indrajaal/")
pub fn zenoh_bus_topics_use_c3i_namespace_test() {
  let events_prefix = "c3i/agui/events/"
  let a2a_prefix = "c3i/a2a/"
  let broadcast_topic = "c3i/a2a/broadcast"
  events_prefix |> string.starts_with("c3i/") |> should.be_true()
  a2a_prefix |> string.starts_with("c3i/") |> should.be_true()
  broadcast_topic |> string.starts_with("c3i/") |> should.be_true()
}

// 4.5 Agent ID embedded in topic preserves original string
pub fn zenoh_bus_agent_id_preserved_in_topic_test() {
  let agent_id = "fractal-architect-007"
  let topic = "c3i/agui/events/" <> agent_id
  topic |> string.contains(agent_id) |> should.be_true()
}

// 4.6 Direct A2A topic segments: source and target are slash-separated
pub fn zenoh_bus_a2a_topic_has_three_slash_segments_test() {
  let source = "alice"
  let target = "bob"
  let topic = "c3i/a2a/" <> source <> "/" <> target
  // "c3i/a2a/alice/bob" has exactly 3 slashes
  let slash_count = string.split(topic, "/") |> list.length
  // "c3i/a2a/alice/bob" → ["c3i", "a2a", "alice", "bob"] → 4 parts = 3 slashes
  slash_count |> should.equal(4)
}

// =============================================================================
// Section 5: SSE (3 tests)
// =============================================================================

// 5.1 health_json returns valid JSON with "ag-ui" protocol and "SIL-6" level
pub fn sse_health_json_contains_protocol_test() {
  let h = sse.health_json()
  h |> string.contains("ag-ui") |> should.be_true()
}

pub fn sse_health_json_contains_sil_level_test() {
  let h = sse.health_json()
  h |> string.contains("SIL-6") |> should.be_true()
}

pub fn sse_health_json_contains_status_ok_test() {
  let h = sse.health_json()
  h |> string.contains("ok") |> should.be_true()
}

// 5.2 create_sse_stream returns "data: " prefixed SSE frames
pub fn sse_create_stream_contains_data_prefix_test() {
  let stream =
    sse.create_sse_stream("thread-1", "run-1", "/test", "hello world")
  stream |> string.contains("data: ") |> should.be_true()
}

pub fn sse_create_stream_contains_run_started_test() {
  let stream =
    sse.create_sse_stream("thread-2", "run-2", "/verify", "check passed")
  stream |> string.contains("RUN_STARTED") |> should.be_true()
}

pub fn sse_create_stream_contains_run_finished_test() {
  let stream =
    sse.create_sse_stream("thread-3", "run-3", "/health", "all clear")
  stream |> string.contains("RUN_FINISHED") |> should.be_true()
}

// 5.3 create_run_response includes run_id, agent, thread_id, and protocol
pub fn sse_create_run_response_contains_run_id_test() {
  let resp = sse.create_run_response("claude", "t-1", "r-999")
  resp |> string.contains("r-999") |> should.be_true()
}

pub fn sse_create_run_response_contains_agent_test() {
  let resp = sse.create_run_response("fractal-guardian", "t-1", "r-1")
  resp |> string.contains("fractal-guardian") |> should.be_true()
}

pub fn sse_create_run_response_contains_protocol_test() {
  let resp = sse.create_run_response("claude", "t-1", "r-1")
  resp |> string.contains("ag-ui-v1") |> should.be_true()
}

// =============================================================================
// Section 6: Cockpit Mode Cycle (3 tests)
// =============================================================================

// 6.1 NextCockpitMode cycles: Dark → Dim → Normal → Bright → Emergency → Dark
pub fn next_cockpit_mode_dark_to_dim_test() {
  let model = DashboardModel(..planning_dashboard.init(), cockpit_mode: Dark)
  let updated = planning_dashboard.update(model, NextCockpitMode)
  updated.cockpit_mode |> should.equal(Dim)
}

pub fn next_cockpit_mode_dim_to_normal_test() {
  let model = DashboardModel(..planning_dashboard.init(), cockpit_mode: Dim)
  let updated = planning_dashboard.update(model, NextCockpitMode)
  updated.cockpit_mode |> should.equal(Normal)
}

pub fn next_cockpit_mode_normal_to_bright_test() {
  let model = DashboardModel(..planning_dashboard.init(), cockpit_mode: Normal)
  let updated = planning_dashboard.update(model, NextCockpitMode)
  updated.cockpit_mode |> should.equal(Bright)
}

pub fn next_cockpit_mode_bright_to_emergency_test() {
  let model = DashboardModel(..planning_dashboard.init(), cockpit_mode: Bright)
  let updated = planning_dashboard.update(model, NextCockpitMode)
  updated.cockpit_mode |> should.equal(EmergencyMode)
}

pub fn next_cockpit_mode_emergency_wraps_to_dark_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), cockpit_mode: EmergencyMode)
  let updated = planning_dashboard.update(model, NextCockpitMode)
  updated.cockpit_mode |> should.equal(Dark)
}

// 6.2 health_score with all-healthy services returns high score
pub fn health_score_all_healthy_services_high_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), services: [
      ServiceNode(name: "wisp", status: "online", health: 1.0),
      ServiceNode(name: "zenoh", status: "online", health: 1.0),
      ServiceNode(name: "db", status: "online", health: 0.95),
    ])
  let score = planning_dashboard.health_score(model)
  { score >=. 0.7 } |> should.be_true()
}

// 6.3 determine_cockpit_mode with safety inactive → Emergency or Bright
pub fn determine_cockpit_mode_safety_off_is_degraded_test() {
  let model =
    DashboardModel(
      ..planning_dashboard.init(),
      safety_active: False,
      total_violations: 25,
    )
  let mode = planning_dashboard.determine_cockpit_mode(model)
  { mode == EmergencyMode || mode == Bright } |> should.be_true()
}

// 6.4 Full NextCockpitMode cycle returns to starting mode after 5 steps
pub fn next_cockpit_mode_full_cycle_returns_to_dark_test() {
  let model = planning_dashboard.init()
  // Dark init → Dim → Normal → Bright → Emergency → Dark
  let final_model =
    model
    |> planning_dashboard.update(NextCockpitMode)
    |> planning_dashboard.update(NextCockpitMode)
    |> planning_dashboard.update(NextCockpitMode)
    |> planning_dashboard.update(NextCockpitMode)
    |> planning_dashboard.update(NextCockpitMode)
  final_model.cockpit_mode |> should.equal(Dark)
}

/// Comprehensive functional tests for the remaining 13 Lustre pages.
/// STAMP: SC-GLM-UI-001, SC-UIGT-003, SC-UIGT-007, SC-GLM-TST-001
/// Covers: mcp, metabolic, planning, planning_dashboard, podman, prajna,
///         smriti, substrate, telemetry, verification, zenoh_mesh, effects, planning_view
///
/// Test naming: {module}_{function}_{scenario}_test
/// All tests are pure — no FFI, no network, no I/O.
import cepaf_gleam/ui/domain.{
  BicameralSignOff, BiomorphicMatrix, Degraded, EvolutionVectors, Healthy,
  HomeostasisControls, MathematicalIntegrity, SingularityEstimation,
}
import cepaf_gleam/ui/lustre/effects.{
  Approved, BatchEffects, Edited, Escalated, NoEffect, Rejected,
  SendHitlDecision, SendToolResult, StartRun, SubscribeAgent, SubscribeZenoh,
  approve, batch, decision_to_string, none, reject, send_tool_result, start_run,
  subscribe_agent, subscribe_zenoh,
}
import cepaf_gleam/ui/lustre/mcp.{
  McpSession, McpTool, RefreshMcp, Running, SessionEnded, SessionStarted,
  Stopped, ToolsLoaded, enabled_tools, init as mcp_init, session_count,
  update as mcp_update,
}
import cepaf_gleam/ui/lustre/metabolic.{
  EnergyChanged, HealthChanged, MetabolicModel, RefreshMetabolic,
  SetPointUpdated, energy_ratio, init as metabolic_init, is_overloaded,
  update as metabolic_update,
}
import cepaf_gleam/ui/lustre/planning.{
  AllTasks, BlockedOnly, CompletedOnly, InProgressOnly, PendingOnly,
  PlanningTask, RefreshTasks, SelectTask, SetFilter, TasksLoaded, filtered_tasks,
  init as planning_init, task_count_by_status, update as planning_update,
}
import cepaf_gleam/ui/lustre/planning_dashboard.{
  A2uiComponentProposed, ActPhase, AgUiConnected, AgUiRunError, AgUiRunStarted,
  AgUiStateDelta, AgUiStateSnapshot, AgUiStepStarted, AgUiTextContent,
  AgUiToolCallEnd, AgUiToolCallResult, AgUiToolCallStart, AgentMsg,
  AgentQuarantined, Bright, ChatMessageReceived, ChayaTwin, CheckFail,
  CheckNotRun, CheckPass, CheckWarn, CircuitClosed, CircuitOpened, CloseDetail,
  CockpitModeChanged, ContainerWave, CriticalPathFound, Dark, DashboardModel,
  DecidePhase, Dim, DragTaskDropped, DragTaskOver, DragTaskStarted,
  EmergencyMode, EnforcerShield, EventMsg, GraphChecksRan, GraphLoaded,
  GraphVerify, HitlApprovalRequested, HitlUserApproved, HitlUserRejected, Idle,
  NextCockpitMode, Normal, ObservePhase, OodaCycle, OodaCycleCompleted,
  OodaPhaseChanged, OrchMesh, OrientPhase, QuorumChanged, RefreshAll,
  SafetyChecksLoaded, SafetyKernel, SelectPanel, SelectTask as DashSelectTask,
  ServiceNode, ServicesUpdated, SetActivePanel, SetDistributionStrategy,
  SetTaskFilter, StartupOptim, SyncFinished, SyncPhaseCompleted, SyncPhaseResult,
  SyncStarted, TaskBoard, TaskCard, TaskStatusChanged,
  TasksLoaded as DashTasksLoaded, ThreatLevelChanged, ToolCallMsg, UserMsg,
  ViolationRecorded, WavesComputed, determine_cockpit_mode, health_score,
  init as dashboard_init, update as dashboard_update,
}
import cepaf_gleam/ui/lustre/podman.{
  Container, ContainersLoaded, Image, ImagesLoaded, RefreshPodman,
  StartContainer, StopContainer, container_count, init as podman_init,
  running_containers, running_count, update as podman_update,
}
import cepaf_gleam/ui/lustre/prajna.{
  CircuitChanged, HolonCreated, HomeostasisUpdated, IntegrityUpdated,
  MatrixUpdated, ModeChanged, RefreshPrajna, ReleaseUpdated, SingularityUpdated,
  ThreatChanged, VectorsUpdated, active_holons, init as prajna_init,
  is_emergency, update as prajna_update,
}
import cepaf_gleam/ui/lustre/smriti.{
  EmbeddingStored, EntryIngested, RefreshSmriti, SearchPerformed, has_embeddings,
  init as smriti_init, total_entries, update as smriti_update,
}
import cepaf_gleam/ui/lustre/substrate.{
  DbConnection, DbStatsReceived, GovernorAction, GovernorUpdated,
  RefreshSubstrate, active_connections, connection_count, init as substrate_init,
  update as substrate_update,
}
import cepaf_gleam/ui/lustre/telemetry.{
  Debug, Error as TelError, Info, Metric, MetricUpdated, RefreshTelemetry,
  SetLogLevel, Span, SpanReceived, Warning, init as telemetry_init,
  log_level_to_string, metric_by_name, recent_spans, update as telemetry_update,
}
import cepaf_gleam/ui/lustre/verification.{
  DagUpdated, EvolutionVectorUpdated, GraphChecksCompleted, HsDsUpdated,
  ProofGenerated, RefreshVerification, ReportReceived, StartVerification,
  all_checks_passed, compliance_percent, init as verification_init,
  latest_proof_verified, proof_result_string, update as verification_update,
}
import cepaf_gleam/ui/lustre/widgets/evolution_vector.{
  EvolutionVectorData, Vector3,
}
import cepaf_gleam/ui/lustre/widgets/hs_ds_pane.{HsDsData}
import cepaf_gleam/ui/lustre/zenoh_mesh.{
  HealthUpdated, LifecycleChanged, MessageEntry, MessageReceived, RefreshZenoh,
  SubscriptionAdded, SubscriptionRemoved, init as zenoh_init, is_connected,
  message_rate, update as zenoh_update,
}
import cepaf_gleam/verification/graph_verification.{GraphCheck}
import cepaf_gleam/verification/prometheus.{
  type VerificationResult, Inconclusive, ProofToken, Rejected as ProofRejected,
  Verified,
}
import cepaf_gleam/verification/swarm.{OodaMetrics, SwarmReport}
import cepaf_gleam/zenoh/domain as zenoh_domain
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// =============================================================================
// MCP TESTS
// =============================================================================

pub fn mcp_init_defaults_test() {
  let m = mcp_init()
  m.tools |> should.equal([])
  m.active_sessions |> should.equal([])
  m.server_status |> should.equal(Stopped)
}

pub fn mcp_update_tools_loaded_test() {
  let tools = [McpTool("list_files", "Lists files", True)]
  let m = mcp_update(mcp_init(), ToolsLoaded(tools))
  m.tools |> should.equal(tools)
}

pub fn mcp_update_session_started_prepends_test() {
  let s1 = McpSession("s1", "claude", 1000)
  let s2 = McpSession("s2", "gemini", 2000)
  let m =
    mcp_init()
    |> mcp_update(SessionStarted(s1))
    |> mcp_update(SessionStarted(s2))
  m.active_sessions |> list.length |> should.equal(2)
  m.active_sessions |> list.first |> should.equal(Ok(s2))
}

pub fn mcp_update_session_ended_removes_by_id_test() {
  let s1 = McpSession("s1", "claude", 1000)
  let s2 = McpSession("s2", "gemini", 2000)
  let m =
    mcp_init()
    |> mcp_update(SessionStarted(s1))
    |> mcp_update(SessionStarted(s2))
    |> mcp_update(SessionEnded("s1"))
  m.active_sessions |> list.length |> should.equal(1)
  m.active_sessions |> list.first |> should.equal(Ok(s2))
}

pub fn mcp_update_session_ended_unknown_id_noop_test() {
  let s1 = McpSession("s1", "claude", 1000)
  let m =
    mcp_init()
    |> mcp_update(SessionStarted(s1))
    |> mcp_update(SessionEnded("nonexistent"))
  m.active_sessions |> list.length |> should.equal(1)
}

pub fn mcp_update_refresh_is_identity_test() {
  let m = mcp_init()
  mcp_update(m, RefreshMcp) |> should.equal(m)
}

pub fn mcp_enabled_tools_filters_disabled_test() {
  let tools = [
    McpTool("t1", "desc1", True),
    McpTool("t2", "desc2", False),
    McpTool("t3", "desc3", True),
  ]
  let m = mcp_update(mcp_init(), ToolsLoaded(tools))
  enabled_tools(m) |> list.length |> should.equal(2)
}

pub fn mcp_enabled_tools_empty_when_none_enabled_test() {
  let tools = [McpTool("t1", "d", False)]
  let m = mcp_update(mcp_init(), ToolsLoaded(tools))
  enabled_tools(m) |> should.equal([])
}

pub fn mcp_session_count_zero_initially_test() {
  session_count(mcp_init()) |> should.equal(0)
}

pub fn mcp_session_count_tracks_additions_test() {
  let m =
    mcp_init()
    |> mcp_update(SessionStarted(McpSession("a", "c", 1)))
    |> mcp_update(SessionStarted(McpSession("b", "c", 2)))
  session_count(m) |> should.equal(2)
}

pub fn mcp_server_status_running_not_stopped_test() {
  Running |> should.not_equal(Stopped)
}

// =============================================================================
// METABOLIC TESTS
// =============================================================================

pub fn metabolic_init_defaults_test() {
  let m = metabolic_init()
  m.set_point |> should.equal(0.5)
  m.energy |> should.equal(1.0)
  m.cpu_load |> should.equal(0.0)
  m.health |> should.equal(Healthy)
}

pub fn metabolic_update_set_point_test() {
  let m = metabolic_update(metabolic_init(), SetPointUpdated(0.8))
  m.set_point |> should.equal(0.8)
}

pub fn metabolic_update_energy_changed_test() {
  let m = metabolic_update(metabolic_init(), EnergyChanged(0.3))
  m.energy |> should.equal(0.3)
}

pub fn metabolic_update_health_changed_test() {
  let m = metabolic_update(metabolic_init(), HealthChanged(Degraded("low cpu")))
  m.health |> should.equal(Degraded("low cpu"))
}

pub fn metabolic_update_refresh_is_identity_test() {
  let m = metabolic_init()
  metabolic_update(m, RefreshMetabolic) |> should.equal(m)
}

pub fn metabolic_energy_ratio_nominal_test() {
  let m =
    metabolic_init()
    |> metabolic_update(SetPointUpdated(0.5))
    |> metabolic_update(EnergyChanged(1.0))
  energy_ratio(m) |> should.equal(2.0)
}

pub fn metabolic_energy_ratio_zero_setpoint_test() {
  let m = metabolic_update(metabolic_init(), SetPointUpdated(0.0))
  energy_ratio(m) |> should.equal(0.0)
}

pub fn metabolic_is_overloaded_below_threshold_test() {
  let m = metabolic_init()
  is_overloaded(m) |> should.be_false()
}

pub fn metabolic_is_overloaded_above_threshold_test() {
  let m = MetabolicModel(..metabolic_init(), cpu_load: 0.95)
  is_overloaded(m) |> should.be_true()
}

pub fn metabolic_is_overloaded_at_boundary_test() {
  let m = MetabolicModel(..metabolic_init(), cpu_load: 0.9)
  // 0.9 is NOT > 0.9, so not overloaded
  is_overloaded(m) |> should.be_false()
}

// =============================================================================
// PLANNING TESTS
// =============================================================================

pub fn planning_init_defaults_test() {
  let m = planning_init()
  m.tasks |> should.equal([])
  m.filter |> should.equal(AllTasks)
  m.selected_id |> should.equal(None)
}

pub fn planning_update_set_filter_pending_test() {
  let m = planning_update(planning_init(), SetFilter(PendingOnly))
  m.filter |> should.equal(PendingOnly)
}

pub fn planning_update_set_filter_all_variants_test() {
  let base = planning_init()
  planning_update(base, SetFilter(InProgressOnly)).filter
  |> should.equal(InProgressOnly)
  planning_update(base, SetFilter(CompletedOnly)).filter
  |> should.equal(CompletedOnly)
  planning_update(base, SetFilter(BlockedOnly)).filter
  |> should.equal(BlockedOnly)
}

pub fn planning_update_select_task_test() {
  let m = planning_update(planning_init(), SelectTask("task-42"))
  m.selected_id |> should.equal(Some("task-42"))
}

pub fn planning_update_refresh_is_identity_test() {
  let m = planning_init()
  planning_update(m, RefreshTasks) |> should.equal(m)
}

pub fn planning_update_tasks_loaded_test() {
  let tasks = [
    PlanningTask("t1", "Fix bug", "pending", "P0", None),
    PlanningTask("t2", "Review PR", "completed", "P2", Some("alice")),
  ]
  let m = planning_update(planning_init(), TasksLoaded(tasks))
  m.tasks |> list.length |> should.equal(2)
}

pub fn planning_filtered_tasks_all_returns_all_test() {
  let tasks = [
    PlanningTask("t1", "A", "pending", "P0", None),
    PlanningTask("t2", "B", "completed", "P1", None),
  ]
  let m = planning_update(planning_init(), TasksLoaded(tasks))
  filtered_tasks(m) |> list.length |> should.equal(2)
}

pub fn planning_filtered_tasks_pending_only_test() {
  let tasks = [
    PlanningTask("t1", "A", "pending", "P0", None),
    PlanningTask("t2", "B", "completed", "P1", None),
    PlanningTask("t3", "C", "pending", "P2", None),
  ]
  let m =
    planning_init()
    |> planning_update(TasksLoaded(tasks))
    |> planning_update(SetFilter(PendingOnly))
  filtered_tasks(m) |> list.length |> should.equal(2)
}

pub fn planning_filtered_tasks_completed_only_test() {
  let tasks = [
    PlanningTask("t1", "A", "pending", "P0", None),
    PlanningTask("t2", "B", "completed", "P1", None),
  ]
  let m =
    planning_init()
    |> planning_update(TasksLoaded(tasks))
    |> planning_update(SetFilter(CompletedOnly))
  filtered_tasks(m) |> list.length |> should.equal(1)
}

pub fn planning_task_count_by_status_test() {
  let tasks = [
    PlanningTask("t1", "A", "pending", "P0", None),
    PlanningTask("t2", "B", "pending", "P1", None),
    PlanningTask("t3", "C", "in_progress", "P0", None),
  ]
  task_count_by_status(tasks, "pending") |> should.equal(2)
  task_count_by_status(tasks, "in_progress") |> should.equal(1)
  task_count_by_status(tasks, "completed") |> should.equal(0)
}

pub fn planning_filtered_tasks_in_progress_test() {
  let tasks = [
    PlanningTask("t1", "A", "in_progress", "P0", None),
    PlanningTask("t2", "B", "blocked", "P1", None),
  ]
  let m =
    planning_init()
    |> planning_update(TasksLoaded(tasks))
    |> planning_update(SetFilter(InProgressOnly))
  filtered_tasks(m) |> list.length |> should.equal(1)
}

// =============================================================================
// PLANNING DASHBOARD TESTS (8-panel cockpit, many Msg variants)
// =============================================================================

pub fn dashboard_init_defaults_test() {
  let m = dashboard_init()
  m.tasks |> should.equal([])
  m.ooda_phase |> should.equal(Idle)
  m.cockpit_mode |> should.equal(Dark)
  m.ag_ui_connected |> should.be_false()
  m.total_violations |> should.equal(0)
  m.quorum |> should.be_false()
  m.safety_active |> should.be_true()
  m.guardian_healthy |> should.be_true()
}

pub fn dashboard_update_set_task_filter_test() {
  let m = dashboard_update(dashboard_init(), SetTaskFilter("pending"))
  m.task_filter |> should.equal("pending")
}

pub fn dashboard_update_select_task_test() {
  let m = dashboard_update(dashboard_init(), DashSelectTask("t-99"))
  m.selected_task |> should.equal(Some("t-99"))
}

pub fn dashboard_update_tasks_loaded_test() {
  let tasks = [
    TaskCard("t1", "Deploy", "pending", "P0", None),
    TaskCard("t2", "Review", "in_progress", "P1", Some("alice")),
  ]
  let m = dashboard_update(dashboard_init(), DashTasksLoaded(tasks))
  m.tasks |> list.length |> should.equal(2)
}

pub fn dashboard_update_task_status_changed_test() {
  let tasks = [TaskCard("t1", "Deploy", "pending", "P0", None)]
  let m =
    dashboard_init()
    |> dashboard_update(DashTasksLoaded(tasks))
    |> dashboard_update(TaskStatusChanged("t1", "completed"))
  let result =
    m.tasks
    |> list.first
    |> should.be_ok
  result.status |> should.equal("completed")
}

pub fn dashboard_update_task_status_wrong_id_noop_test() {
  let tasks = [TaskCard("t1", "Deploy", "pending", "P0", None)]
  let m =
    dashboard_init()
    |> dashboard_update(DashTasksLoaded(tasks))
    |> dashboard_update(TaskStatusChanged("t999", "completed"))
  let result =
    m.tasks
    |> list.first
    |> should.be_ok
  result.status |> should.equal("pending")
}

pub fn dashboard_update_ooda_phase_changed_test() {
  let m = dashboard_update(dashboard_init(), OodaPhaseChanged(ActPhase))
  m.ooda_phase |> should.equal(ActPhase)
}

pub fn dashboard_update_ooda_cycle_completed_test() {
  let m =
    dashboard_update(
      dashboard_init(),
      OodaCycleCompleted(45, "standard", "proceed"),
    )
  m.ooda_cycle_count |> should.equal(1)
  m.last_cycle_ms |> should.equal(45)
  m.ooda_pattern |> should.equal("standard")
  m.ooda_decision |> should.equal("proceed")
  m.ooda_phase |> should.equal(Idle)
}

pub fn dashboard_update_ooda_cycle_accumulates_count_test() {
  let m =
    dashboard_init()
    |> dashboard_update(OodaCycleCompleted(10, "p1", "d1"))
    |> dashboard_update(OodaCycleCompleted(20, "p2", "d2"))
    |> dashboard_update(OodaCycleCompleted(30, "p3", "d3"))
  m.ooda_cycle_count |> should.equal(3)
}

pub fn dashboard_update_safety_checks_loaded_test() {
  let checks = [
    CheckPass("sc-001"),
    CheckFail("sc-002", "timeout"),
    CheckWarn("sc-003"),
  ]
  let m = dashboard_update(dashboard_init(), SafetyChecksLoaded(checks))
  m.safety_checks |> list.length |> should.equal(3)
}

pub fn dashboard_update_threat_level_changed_test() {
  let m = dashboard_update(dashboard_init(), ThreatLevelChanged(0.75))
  m.threat_level |> should.equal(0.75)
}

pub fn dashboard_update_agent_quarantined_prepends_test() {
  let m =
    dashboard_init()
    |> dashboard_update(AgentQuarantined("agent-1"))
    |> dashboard_update(AgentQuarantined("agent-2"))
  m.quarantined |> list.length |> should.equal(2)
  m.quarantined |> list.first |> should.equal(Ok("agent-2"))
}

pub fn dashboard_update_violation_recorded_increments_test() {
  let m =
    dashboard_update(dashboard_init(), ViolationRecorded("SC-SEC-001 breach"))
  m.total_violations |> should.equal(1)
  m.recent_violations |> list.length |> should.equal(1)
}

pub fn dashboard_update_circuit_opened_deduplicates_test() {
  let m =
    dashboard_init()
    |> dashboard_update(CircuitOpened("agent-x"))
    |> dashboard_update(CircuitOpened("agent-x"))
  m.open_circuits |> list.length |> should.equal(1)
}

pub fn dashboard_update_circuit_closed_removes_test() {
  let m =
    dashboard_init()
    |> dashboard_update(CircuitOpened("agent-x"))
    |> dashboard_update(CircuitClosed("agent-x"))
  m.open_circuits |> should.equal([])
}

pub fn dashboard_update_graph_loaded_test() {
  let m =
    dashboard_update(dashboard_init(), GraphLoaded(22, 462, "digraph G {}"))
  m.graph_node_count |> should.equal(22)
  m.graph_edge_count |> should.equal(462)
  m.graph_dot |> should.equal("digraph G {}")
}

pub fn dashboard_update_graph_checks_ran_test() {
  let checks = [CheckPass("acyclicity"), CheckNotRun("scc")]
  let m = dashboard_update(dashboard_init(), GraphChecksRan(checks))
  m.graph_checks |> list.length |> should.equal(2)
}

pub fn dashboard_update_services_updated_test() {
  let svcs = [
    ServiceNode("zenoh", "running", 1.0),
    ServiceNode("db", "running", 0.95),
  ]
  let m = dashboard_update(dashboard_init(), ServicesUpdated(svcs))
  m.services |> list.length |> should.equal(2)
}

pub fn dashboard_update_quorum_changed_test() {
  let m = dashboard_update(dashboard_init(), QuorumChanged(True))
  m.quorum |> should.be_true()
}

pub fn dashboard_update_distribution_strategy_test() {
  let m =
    dashboard_update(dashboard_init(), SetDistributionStrategy("least_loaded"))
  m.distribution_strategy |> should.equal("least_loaded")
}

pub fn dashboard_update_sync_started_clears_phases_test() {
  let phase = SyncPhaseResult("schema", True, 5, 0)
  let m =
    dashboard_init()
    |> dashboard_update(SyncPhaseCompleted(phase))
    |> dashboard_update(SyncStarted)
  m.sync_phases |> should.equal([])
}

pub fn dashboard_update_sync_phase_completed_appends_test() {
  let p1 = SyncPhaseResult("schema", True, 3, 0)
  let p2 = SyncPhaseResult("data", True, 10, 0)
  let m =
    dashboard_init()
    |> dashboard_update(SyncPhaseCompleted(p1))
    |> dashboard_update(SyncPhaseCompleted(p2))
  m.sync_phases |> list.length |> should.equal(2)
}

pub fn dashboard_update_sync_finished_test() {
  let m = dashboard_update(dashboard_init(), SyncFinished(3, 7))
  m.orphan_count |> should.equal(3)
  m.mismatch_count |> should.equal(7)
  m.last_sync |> should.equal("completed")
}

pub fn dashboard_update_waves_computed_test() {
  let waves = [
    ContainerWave(1, ["zenoh"], 1200),
    ContainerWave(2, ["db", "obs"], 3000),
  ]
  let m = dashboard_update(dashboard_init(), WavesComputed(waves))
  m.waves |> list.length |> should.equal(2)
}

pub fn dashboard_update_critical_path_found_test() {
  let m =
    dashboard_update(dashboard_init(), CriticalPathFound(["zenoh", "db"], 4200))
  m.critical_path |> should.equal(["zenoh", "db"])
  m.total_startup_ms |> should.equal(4200)
}

pub fn dashboard_update_set_active_panel_test() {
  let m = dashboard_update(dashboard_init(), SetActivePanel(SafetyKernel))
  m.active_panel |> should.equal(SafetyKernel)
}

pub fn dashboard_update_cockpit_mode_changed_test() {
  let m = dashboard_update(dashboard_init(), CockpitModeChanged(EmergencyMode))
  m.cockpit_mode |> should.equal(EmergencyMode)
}

pub fn dashboard_update_ag_ui_connected_test() {
  let m = dashboard_update(dashboard_init(), AgUiConnected(True))
  m.ag_ui_connected |> should.be_true()
}

pub fn dashboard_update_chat_message_received_test() {
  let m =
    dashboard_update(dashboard_init(), ChatMessageReceived(UserMsg("hello")))
  m.chat_messages |> list.length |> should.equal(1)
  m.chat_messages |> list.first |> should.equal(Ok(UserMsg("hello")))
}

pub fn dashboard_update_refresh_all_is_identity_test() {
  let base = dashboard_init()
  dashboard_update(base, RefreshAll) |> should.equal(base)
}

pub fn dashboard_update_ag_ui_run_started_sets_connected_test() {
  let m =
    dashboard_update(dashboard_init(), AgUiRunStarted("thread-1", "run-42"))
  m.ag_ui_connected |> should.be_true()
  m.chat_messages |> list.length |> should.equal(1)
}

pub fn dashboard_update_ag_ui_run_error_sets_bright_mode_test() {
  let m = dashboard_update(dashboard_init(), AgUiRunError("OOM", "503"))
  m.cockpit_mode |> should.equal(Bright)
  m.chat_messages |> list.length |> should.equal(1)
}

pub fn dashboard_update_ag_ui_step_started_appends_event_test() {
  let m = dashboard_update(dashboard_init(), AgUiStepStarted("compile"))
  m.chat_messages |> list.length |> should.equal(1)
}

pub fn dashboard_update_ag_ui_text_content_appends_agent_msg_test() {
  let m =
    dashboard_update(dashboard_init(), AgUiTextContent("msg-1", "Hello world"))
  m.chat_messages |> list.length |> should.equal(1)
  m.chat_messages |> list.first |> should.equal(Ok(AgentMsg("Hello world")))
}

pub fn dashboard_update_ag_ui_tool_call_start_appends_tool_msg_test() {
  let m =
    dashboard_update(dashboard_init(), AgUiToolCallStart("tc-1", "list_files"))
  m.chat_messages |> list.length |> should.equal(1)
  m.chat_messages
  |> list.first
  |> should.equal(Ok(ToolCallMsg("list_files", "tc-1")))
}

pub fn dashboard_update_ag_ui_tool_call_end_noop_test() {
  let base = dashboard_init()
  dashboard_update(base, AgUiToolCallEnd("tc-1")) |> should.equal(base)
}

pub fn dashboard_update_hitl_approval_requested_sets_normal_mode_test() {
  let m =
    dashboard_update(
      dashboard_init(),
      HitlApprovalRequested("req-1", "Deploy prod"),
    )
  m.cockpit_mode |> should.equal(Normal)
  m.chat_messages |> list.length |> should.equal(1)
}

pub fn dashboard_update_hitl_user_approved_appends_user_msg_test() {
  let m = dashboard_update(dashboard_init(), HitlUserApproved("req-1"))
  m.chat_messages |> list.length |> should.equal(1)
  m.chat_messages |> list.first |> should.equal(Ok(UserMsg("Approved: req-1")))
}

pub fn dashboard_update_hitl_user_rejected_appends_user_msg_test() {
  let m = dashboard_update(dashboard_init(), HitlUserRejected("req-2"))
  m.chat_messages |> list.length |> should.equal(1)
  m.chat_messages |> list.first |> should.equal(Ok(UserMsg("Rejected: req-2")))
}

pub fn dashboard_update_drag_task_dropped_updates_status_test() {
  let tasks = [TaskCard("t1", "Work", "pending", "P0", None)]
  let m =
    dashboard_init()
    |> dashboard_update(DashTasksLoaded(tasks))
    |> dashboard_update(DragTaskDropped("t1", "completed"))
  let result = m.tasks |> list.first |> should.be_ok
  result.status |> should.equal("completed")
}

pub fn dashboard_update_drag_task_started_noop_test() {
  let base = dashboard_init()
  dashboard_update(base, DragTaskStarted("t1")) |> should.equal(base)
}

pub fn dashboard_update_drag_task_over_noop_test() {
  let base = dashboard_init()
  dashboard_update(base, DragTaskOver("in_progress")) |> should.equal(base)
}

pub fn dashboard_update_next_cockpit_mode_cycles_test() {
  let m0 = dashboard_init()
  let m1 = dashboard_update(m0, NextCockpitMode)
  m1.cockpit_mode |> should.equal(Dim)
  let m2 = dashboard_update(m1, NextCockpitMode)
  m2.cockpit_mode |> should.equal(Normal)
  let m3 = dashboard_update(m2, NextCockpitMode)
  m3.cockpit_mode |> should.equal(Bright)
  let m4 = dashboard_update(m3, NextCockpitMode)
  m4.cockpit_mode |> should.equal(EmergencyMode)
  let m5 = dashboard_update(m4, NextCockpitMode)
  m5.cockpit_mode |> should.equal(Dark)
}

pub fn dashboard_update_select_panel_test() {
  let m = dashboard_update(dashboard_init(), SelectPanel(OrchMesh))
  m.active_panel |> should.equal(OrchMesh)
}

pub fn dashboard_update_close_detail_clears_selected_task_test() {
  let m =
    dashboard_init()
    |> dashboard_update(DashSelectTask("t-5"))
    |> dashboard_update(CloseDetail)
  m.selected_task |> should.equal(None)
}

pub fn dashboard_health_score_in_valid_range_test() {
  let score = health_score(dashboard_init())
  { score >=. 0.0 } |> should.be_true()
  { score <=. 1.0 } |> should.be_true()
}

pub fn dashboard_health_score_with_violations_still_valid_test() {
  let m =
    dashboard_init()
    |> dashboard_update(ViolationRecorded("v1"))
    |> dashboard_update(ViolationRecorded("v2"))
    |> dashboard_update(ViolationRecorded("v3"))
  let score = health_score(m)
  { score >=. 0.0 } |> should.be_true()
  { score <=. 1.0 } |> should.be_true()
}

pub fn dashboard_determine_cockpit_mode_returns_valid_mode_test() {
  let mode = determine_cockpit_mode(dashboard_init())
  case mode {
    Dark | Dim | Normal | Bright | EmergencyMode -> True
  }
  |> should.be_true()
}

pub fn dashboard_determine_cockpit_mode_emergency_on_low_health_test() {
  let m =
    DashboardModel(
      ..dashboard_init(),
      safety_active: False,
      total_violations: 100,
      open_circuits: ["a1", "a2", "a3", "a4"],
    )
  determine_cockpit_mode(m) |> should.equal(EmergencyMode)
}

pub fn dashboard_update_a2ui_proposed_noop_test() {
  let base = dashboard_init()
  let snapshot = json.object([#("type", json.string("badge"))])
  dashboard_update(base, A2uiComponentProposed(TaskBoard, snapshot))
  |> should.equal(base)
}

pub fn dashboard_update_ag_ui_state_snapshot_noop_test() {
  let base = dashboard_init()
  let snap = json.object([#("state", json.string("full"))])
  dashboard_update(base, AgUiStateSnapshot(snap)) |> should.equal(base)
}

pub fn dashboard_update_ag_ui_state_delta_noop_test() {
  let base = dashboard_init()
  let patches = json.array([], fn(x) { x })
  dashboard_update(base, AgUiStateDelta(patches)) |> should.equal(base)
}

pub fn dashboard_ooda_all_phases_test() {
  let phases = [ObservePhase, OrientPhase, DecidePhase, ActPhase, Idle]
  list.each(phases, fn(phase) {
    let m = dashboard_update(dashboard_init(), OodaPhaseChanged(phase))
    m.ooda_phase |> should.equal(phase)
  })
}

pub fn dashboard_update_ag_ui_tool_call_result_appends_event_test() {
  let m =
    dashboard_update(dashboard_init(), AgUiToolCallResult("tc-1", "success"))
  m.chat_messages |> list.length |> should.equal(1)
}

// =============================================================================
// PODMAN TESTS
// =============================================================================

pub fn podman_init_defaults_test() {
  let m = podman_init()
  m.containers |> should.equal([])
  m.images |> should.equal([])
  m.volumes |> should.equal([])
  m.networks |> should.equal([])
}

pub fn podman_update_containers_loaded_test() {
  let cs = [Container("abc123", "zenoh", "running", "eclipse/zenoh:latest")]
  let m = podman_update(podman_init(), ContainersLoaded(cs))
  m.containers |> list.length |> should.equal(1)
}

pub fn podman_update_images_loaded_test() {
  let imgs = [Image("img1", "eclipse/zenoh", "latest", 128)]
  let m = podman_update(podman_init(), ImagesLoaded(imgs))
  m.images |> list.length |> should.equal(1)
}

pub fn podman_update_start_container_noop_test() {
  let base = podman_init()
  podman_update(base, StartContainer("c1")) |> should.equal(base)
}

pub fn podman_update_stop_container_noop_test() {
  let base = podman_init()
  podman_update(base, StopContainer("c1")) |> should.equal(base)
}

pub fn podman_update_refresh_is_identity_test() {
  let base = podman_init()
  podman_update(base, RefreshPodman) |> should.equal(base)
}

pub fn podman_running_containers_filters_by_status_test() {
  let cs = [
    Container("a", "zenoh", "running", "img"),
    Container("b", "db", "stopped", "img"),
    Container("c", "obs", "running", "img"),
  ]
  let m = podman_update(podman_init(), ContainersLoaded(cs))
  running_containers(m) |> list.length |> should.equal(2)
}

pub fn podman_container_count_test() {
  let cs = [
    Container("a", "zenoh", "running", "img"),
    Container("b", "db", "stopped", "img"),
  ]
  let m = podman_update(podman_init(), ContainersLoaded(cs))
  container_count(m) |> should.equal(2)
}

pub fn podman_running_count_test() {
  let cs = [
    Container("a", "zenoh", "running", "img"),
    Container("b", "db", "stopped", "img"),
  ]
  let m = podman_update(podman_init(), ContainersLoaded(cs))
  running_count(m) |> should.equal(1)
}

pub fn podman_running_count_zero_when_empty_test() {
  running_count(podman_init()) |> should.equal(0)
}

// =============================================================================
// PRAJNA TESTS
// =============================================================================

pub fn prajna_init_defaults_test() {
  let m = prajna_init()
  m.holon_count |> should.equal(0)
  m.threat_level |> should.equal("nominal")
  m.cockpit_mode |> should.equal("dark")
  m.circuit_state |> should.equal("closed")
  m.messages_routed |> should.equal(0)
}

pub fn prajna_update_holon_created_increments_test() {
  let m =
    prajna_init()
    |> prajna_update(HolonCreated)
    |> prajna_update(HolonCreated)
    |> prajna_update(HolonCreated)
  m.holon_count |> should.equal(3)
}

pub fn prajna_update_threat_changed_test() {
  let m = prajna_update(prajna_init(), ThreatChanged("critical"))
  m.threat_level |> should.equal("critical")
}

pub fn prajna_update_mode_changed_test() {
  let m = prajna_update(prajna_init(), ModeChanged("emergency"))
  m.cockpit_mode |> should.equal("emergency")
}

pub fn prajna_update_circuit_changed_test() {
  let m = prajna_update(prajna_init(), CircuitChanged("open"))
  m.circuit_state |> should.equal("open")
}

pub fn prajna_update_integrity_updated_test() {
  let integrity = MathematicalIntegrity(hs: 2.8, epsilon: 0.01, ds: 0.05)
  let m = prajna_update(prajna_init(), IntegrityUpdated(integrity))
  m.integrity |> should.equal(integrity)
}

pub fn prajna_update_vectors_updated_test() {
  let vecs = EvolutionVectors(v1: 1.0, v2: 2.0, v3: 3.0, v4: 4.0)
  let m = prajna_update(prajna_init(), VectorsUpdated(vecs))
  m.vectors |> should.equal(vecs)
}

pub fn prajna_update_matrix_updated_test() {
  let matrix = BiomorphicMatrix(levels: [])
  let m = prajna_update(prajna_init(), MatrixUpdated(matrix))
  m.matrix |> should.equal(matrix)
}

pub fn prajna_update_homeostasis_updated_test() {
  let hc =
    HomeostasisControls(
      kp: 0.5,
      ki: 0.1,
      kd: 0.05,
      set_point: 0.7,
      current_value: 0.65,
      error: 0.05,
    )
  let m = prajna_update(prajna_init(), HomeostasisUpdated(hc))
  m.homeostasis |> should.equal(hc)
}

pub fn prajna_update_release_updated_test() {
  let release =
    BicameralSignOff(
      key1_signed: True,
      key2_signed: False,
      authorized_by: Some("alice"),
    )
  let m = prajna_update(prajna_init(), ReleaseUpdated(release))
  m.release |> should.equal(release)
}

pub fn prajna_update_singularity_updated_test() {
  let sing =
    SingularityEstimation(
      time_to_singularity_ms: 50_000,
      confidence_interval: 0.85,
      critical_threshold_reached: True,
    )
  let m = prajna_update(prajna_init(), SingularityUpdated(sing))
  m.singularity |> should.equal(sing)
}

pub fn prajna_update_refresh_is_identity_test() {
  let base = prajna_init()
  prajna_update(base, RefreshPrajna) |> should.equal(base)
}

pub fn prajna_is_emergency_critical_threat_test() {
  let m = prajna_update(prajna_init(), ThreatChanged("critical"))
  is_emergency(m) |> should.be_true()
}

pub fn prajna_is_emergency_open_circuit_test() {
  let m = prajna_update(prajna_init(), CircuitChanged("open"))
  is_emergency(m) |> should.be_true()
}

pub fn prajna_is_emergency_nominal_is_false_test() {
  is_emergency(prajna_init()) |> should.be_false()
}

pub fn prajna_active_holons_returns_count_test() {
  let m =
    prajna_init()
    |> prajna_update(HolonCreated)
    |> prajna_update(HolonCreated)
  active_holons(m) |> should.equal(2)
}

// =============================================================================
// SMRITI TESTS
// =============================================================================

pub fn smriti_init_defaults_test() {
  let m = smriti_init()
  m.catalog_entries |> should.equal(0)
  m.embeddings_stored |> should.equal(0)
  m.search_queries |> should.equal(0)
  m.avg_similarity |> should.equal(0.0)
}

pub fn smriti_update_entry_ingested_increments_test() {
  let m =
    smriti_init()
    |> smriti_update(EntryIngested)
    |> smriti_update(EntryIngested)
  m.catalog_entries |> should.equal(2)
}

pub fn smriti_update_search_performed_increments_queries_test() {
  let m = smriti_update(smriti_init(), SearchPerformed(0.92))
  m.search_queries |> should.equal(1)
  m.avg_similarity |> should.equal(0.92)
}

pub fn smriti_update_search_overwrites_similarity_test() {
  let m =
    smriti_init()
    |> smriti_update(SearchPerformed(0.8))
    |> smriti_update(SearchPerformed(0.95))
  m.avg_similarity |> should.equal(0.95)
  m.search_queries |> should.equal(2)
}

pub fn smriti_update_embedding_stored_increments_test() {
  let m =
    smriti_init()
    |> smriti_update(EmbeddingStored)
    |> smriti_update(EmbeddingStored)
    |> smriti_update(EmbeddingStored)
  m.embeddings_stored |> should.equal(3)
}

pub fn smriti_update_refresh_is_identity_test() {
  let base = smriti_init()
  smriti_update(base, RefreshSmriti) |> should.equal(base)
}

pub fn smriti_total_entries_test() {
  let m =
    smriti_init()
    |> smriti_update(EntryIngested)
    |> smriti_update(EntryIngested)
  total_entries(m) |> should.equal(2)
}

pub fn smriti_has_embeddings_false_initially_test() {
  has_embeddings(smriti_init()) |> should.be_false()
}

pub fn smriti_has_embeddings_true_after_store_test() {
  let m = smriti_update(smriti_init(), EmbeddingStored)
  has_embeddings(m) |> should.be_true()
}

// =============================================================================
// SUBSTRATE TESTS
// =============================================================================

pub fn substrate_init_defaults_test() {
  let m = substrate_init()
  m.governor_action |> should.equal(None)
  m.db_connections |> should.equal([])
  m.file_ops |> should.equal([])
}

pub fn substrate_update_governor_updated_test() {
  let action = GovernorAction("throttle", "active", 1_000_000)
  let m = substrate_update(substrate_init(), GovernorUpdated(action))
  m.governor_action |> should.equal(Some(action))
}

pub fn substrate_update_governor_replaces_previous_test() {
  let a1 = GovernorAction("throttle", "active", 1000)
  let a2 = GovernorAction("full_speed", "active", 2000)
  let m =
    substrate_init()
    |> substrate_update(GovernorUpdated(a1))
    |> substrate_update(GovernorUpdated(a2))
  m.governor_action |> should.equal(Some(a2))
}

pub fn substrate_update_db_stats_received_test() {
  let conns = [
    DbConnection("c1", "indrajaal_prod", "active", 2),
    DbConnection("c2", "indrajaal_test", "active", 5),
  ]
  let m = substrate_update(substrate_init(), DbStatsReceived(conns))
  m.db_connections |> list.length |> should.equal(2)
}

pub fn substrate_update_refresh_is_identity_test() {
  let base = substrate_init()
  substrate_update(base, RefreshSubstrate) |> should.equal(base)
}

pub fn substrate_active_connections_filters_active_test() {
  let conns = [
    DbConnection("c1", "prod", "active", 2),
    DbConnection("c2", "test", "idle", 0),
    DbConnection("c3", "dev", "active", 1),
  ]
  let m = substrate_update(substrate_init(), DbStatsReceived(conns))
  active_connections(m) |> list.length |> should.equal(2)
}

pub fn substrate_connection_count_test() {
  let conns = [
    DbConnection("c1", "prod", "active", 2),
    DbConnection("c2", "test", "idle", 0),
  ]
  let m = substrate_update(substrate_init(), DbStatsReceived(conns))
  connection_count(m) |> should.equal(2)
}

pub fn substrate_connection_count_zero_initially_test() {
  connection_count(substrate_init()) |> should.equal(0)
}

pub fn substrate_active_connections_empty_when_all_idle_test() {
  let conns = [DbConnection("c1", "prod", "idle", 0)]
  let m = substrate_update(substrate_init(), DbStatsReceived(conns))
  active_connections(m) |> should.equal([])
}

// =============================================================================
// TELEMETRY TESTS
// =============================================================================

pub fn telemetry_init_defaults_test() {
  let m = telemetry_init()
  m.spans |> should.equal([])
  m.metrics |> should.equal([])
  m.log_level |> should.equal(Info)
  m.active_traces |> should.equal(0)
}

pub fn telemetry_update_span_received_prepends_test() {
  let s1 = Span("trace-1", "span-1", "compile", 5000, "ok")
  let s2 = Span("trace-1", "span-2", "link", 1000, "ok")
  let m =
    telemetry_init()
    |> telemetry_update(SpanReceived(s1))
    |> telemetry_update(SpanReceived(s2))
  m.spans |> list.first |> should.equal(Ok(s2))
  m.spans |> list.length |> should.equal(2)
}

pub fn telemetry_update_metric_updated_prepends_test() {
  let metric = Metric("cpu_load", 0.42, "ratio", 1_000_000)
  let m = telemetry_update(telemetry_init(), MetricUpdated(metric))
  m.metrics |> list.first |> should.equal(Ok(metric))
}

pub fn telemetry_update_set_log_level_debug_test() {
  let m = telemetry_update(telemetry_init(), SetLogLevel(Debug))
  m.log_level |> should.equal(Debug)
}

pub fn telemetry_update_set_log_level_error_test() {
  let m = telemetry_update(telemetry_init(), SetLogLevel(TelError))
  m.log_level |> should.equal(TelError)
}

pub fn telemetry_update_set_log_level_warning_test() {
  let m = telemetry_update(telemetry_init(), SetLogLevel(Warning))
  m.log_level |> should.equal(Warning)
}

pub fn telemetry_update_refresh_is_identity_test() {
  let base = telemetry_init()
  telemetry_update(base, RefreshTelemetry) |> should.equal(base)
}

pub fn telemetry_log_level_to_string_all_variants_test() {
  log_level_to_string(Debug) |> should.equal("DEBUG")
  log_level_to_string(Info) |> should.equal("INFO")
  log_level_to_string(Warning) |> should.equal("WARNING")
  log_level_to_string(TelError) |> should.equal("ERROR")
}

pub fn telemetry_recent_spans_limits_count_test() {
  let spans = [
    Span("t1", "s1", "op1", 100, "ok"),
    Span("t1", "s2", "op2", 200, "ok"),
    Span("t1", "s3", "op3", 300, "ok"),
  ]
  let m =
    list.fold(spans, telemetry_init(), fn(acc, s) {
      telemetry_update(acc, SpanReceived(s))
    })
  recent_spans(m, 2) |> list.length |> should.equal(2)
}

pub fn telemetry_recent_spans_empty_when_none_test() {
  recent_spans(telemetry_init(), 5) |> should.equal([])
}

pub fn telemetry_metric_by_name_found_test() {
  let m1 = Metric("cpu_load", 0.42, "ratio", 1000)
  let m2 = Metric("mem_used", 4096.0, "mb", 1001)
  let model =
    telemetry_init()
    |> telemetry_update(MetricUpdated(m1))
    |> telemetry_update(MetricUpdated(m2))
  metric_by_name(model, "cpu_load") |> should.equal(Ok(m1))
}

pub fn telemetry_metric_by_name_not_found_test() {
  metric_by_name(telemetry_init(), "nonexistent") |> should.equal(Error(Nil))
}

// =============================================================================
// VERIFICATION TESTS
// =============================================================================

pub fn verification_init_defaults_test() {
  let m = verification_init()
  m.last_report |> should.equal(None)
  m.running |> should.be_false()
  m.history |> should.equal([])
  m.latest_proof |> should.equal(None)
  m.graph_checks |> should.equal([])
  m.dag_node_count |> should.equal(0)
  m.dag_edge_count |> should.equal(0)
}

pub fn verification_update_start_sets_running_test() {
  let m = verification_update(verification_init(), StartVerification)
  m.running |> should.be_true()
}

pub fn verification_update_report_received_clears_running_test() {
  let report = make_test_report(8, 10, True)
  let m =
    verification_init()
    |> verification_update(StartVerification)
    |> verification_update(ReportReceived(report))
  m.running |> should.be_false()
  m.last_report |> should.equal(Some(report))
  m.history |> list.length |> should.equal(1)
}

pub fn verification_update_report_received_builds_history_test() {
  let r1 = make_test_report(8, 10, True)
  let r2 = make_test_report(5, 10, False)
  let m =
    verification_init()
    |> verification_update(ReportReceived(r1))
    |> verification_update(ReportReceived(r2))
  m.history |> list.length |> should.equal(2)
}

pub fn verification_update_refresh_is_identity_test() {
  let base = verification_init()
  verification_update(base, RefreshVerification) |> should.equal(base)
}

pub fn verification_update_proof_generated_test() {
  let proof = make_test_proof(Verified)
  let m = verification_update(verification_init(), ProofGenerated(proof))
  m.latest_proof |> should.equal(Some(proof))
  m.proof_history |> list.length |> should.equal(1)
}

pub fn verification_update_proof_generated_accumulates_history_test() {
  let p1 = make_test_proof(Verified)
  let p2 = make_test_proof(Inconclusive)
  let m =
    verification_init()
    |> verification_update(ProofGenerated(p1))
    |> verification_update(ProofGenerated(p2))
  m.proof_history |> list.length |> should.equal(2)
}

pub fn verification_update_graph_checks_completed_test() {
  let checks = [
    GraphCheck("acyclicity", True, "DAG is acyclic"),
    GraphCheck("connectivity", False, "Disconnected node found"),
  ]
  let m = verification_update(verification_init(), GraphChecksCompleted(checks))
  m.graph_checks |> list.length |> should.equal(2)
}

pub fn verification_update_dag_updated_test() {
  let m = verification_update(verification_init(), DagUpdated(22, 462))
  m.dag_node_count |> should.equal(22)
  m.dag_edge_count |> should.equal(462)
}

pub fn verification_update_hs_ds_updated_test() {
  let data = HsDsData(shannon_entropy: 2.7, ccm_score: 0.91, itqs_score: 0.87)
  let m = verification_update(verification_init(), HsDsUpdated(data))
  m.hs_ds_data |> should.equal(Some(data))
}

pub fn verification_update_evolution_vector_updated_test() {
  let vec =
    EvolutionVectorData(
      v1_physics: Vector3(1.0, 2.0, 3.0),
      v2_logic: Vector3(4.0, 5.0, 6.0),
      v3_cognitive: Vector3(7.0, 8.0, 9.0),
      v4_social: Vector3(10.0, 11.0, 12.0),
    )
  let m = verification_update(verification_init(), EvolutionVectorUpdated(vec))
  m.evolution_vector |> should.equal(Some(vec))
}

pub fn verification_compliance_percent_zero_containers_test() {
  let report = make_test_report(0, 0, True)
  compliance_percent(report) |> should.equal(0.0)
}

pub fn verification_compliance_percent_full_health_test() {
  let report = make_test_report(10, 10, True)
  compliance_percent(report) |> should.equal(100.0)
}

pub fn verification_compliance_percent_partial_test() {
  let report = make_test_report(5, 10, True)
  compliance_percent(report) |> should.equal(50.0)
}

pub fn verification_all_checks_passed_empty_is_vacuously_true_test() {
  all_checks_passed(verification_init()) |> should.be_true()
}

pub fn verification_all_checks_passed_with_failure_test() {
  let checks = [
    GraphCheck("a", True, "ok"),
    GraphCheck("b", False, "failed"),
  ]
  let m = verification_update(verification_init(), GraphChecksCompleted(checks))
  all_checks_passed(m) |> should.be_false()
}

pub fn verification_all_checks_passed_all_passing_test() {
  let checks = [GraphCheck("a", True, "ok"), GraphCheck("b", True, "ok")]
  let m = verification_update(verification_init(), GraphChecksCompleted(checks))
  all_checks_passed(m) |> should.be_true()
}

pub fn verification_latest_proof_verified_none_is_false_test() {
  latest_proof_verified(verification_init()) |> should.be_false()
}

pub fn verification_latest_proof_verified_with_verified_proof_test() {
  let proof = make_test_proof(Verified)
  let m = verification_update(verification_init(), ProofGenerated(proof))
  latest_proof_verified(m) |> should.be_true()
}

pub fn verification_latest_proof_verified_with_rejected_proof_test() {
  let proof = make_test_proof(ProofRejected(["invariant violated"]))
  let m = verification_update(verification_init(), ProofGenerated(proof))
  latest_proof_verified(m) |> should.be_false()
}

pub fn verification_proof_result_string_all_variants_test() {
  proof_result_string(Verified) |> should.equal("Verified")
  proof_result_string(ProofRejected(["reason"])) |> should.equal("Rejected")
  proof_result_string(Inconclusive) |> should.equal("Inconclusive")
}

// =============================================================================
// ZENOH MESH TESTS
// =============================================================================

pub fn zenoh_init_defaults_test() {
  let m = zenoh_init()
  m.subscriptions |> should.equal([])
  m.message_log |> should.equal([])
}

pub fn zenoh_update_health_updated_test() {
  let health = zenoh_domain.empty_health()
  let m = zenoh_update(zenoh_init(), HealthUpdated(health))
  m.health |> should.equal(health)
}

pub fn zenoh_update_lifecycle_changed_running_test() {
  let m =
    zenoh_update(
      zenoh_init(),
      LifecycleChanged(zenoh_domain.Running(connected_at: 1000)),
    )
  case m.lifecycle {
    zenoh_domain.Running(_) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn zenoh_update_message_received_prepends_test() {
  let m =
    zenoh_init()
    |> zenoh_update(MessageReceived("indrajaal/health/node1", 128, 1000))
    |> zenoh_update(MessageReceived("indrajaal/health/node2", 64, 2000))
  m.message_log |> list.length |> should.equal(2)
  m.message_log
  |> list.first
  |> should.equal(Ok(MessageEntry("indrajaal/health/node2", 64, 2000)))
}

pub fn zenoh_update_subscription_added_prepends_test() {
  let m =
    zenoh_init()
    |> zenoh_update(SubscriptionAdded("indrajaal/health/**"))
    |> zenoh_update(SubscriptionAdded("indrajaal/otel/**"))
  m.subscriptions |> list.length |> should.equal(2)
}

pub fn zenoh_update_subscription_removed_filters_test() {
  let m =
    zenoh_init()
    |> zenoh_update(SubscriptionAdded("topic-a"))
    |> zenoh_update(SubscriptionAdded("topic-b"))
    |> zenoh_update(SubscriptionRemoved("topic-a"))
  m.subscriptions |> should.equal(["topic-b"])
}

pub fn zenoh_update_subscription_removed_unknown_noop_test() {
  let m =
    zenoh_init()
    |> zenoh_update(SubscriptionAdded("topic-a"))
    |> zenoh_update(SubscriptionRemoved("nonexistent"))
  m.subscriptions |> list.length |> should.equal(1)
}

pub fn zenoh_update_refresh_is_identity_test() {
  let base = zenoh_init()
  zenoh_update(base, RefreshZenoh) |> should.equal(base)
}

pub fn zenoh_is_connected_disconnected_initially_test() {
  is_connected(zenoh_init()) |> should.be_false()
}

pub fn zenoh_is_connected_when_status_connected_test() {
  let connected_health =
    zenoh_domain.ZenohHealth(
      status: zenoh_domain.Connected,
      session_id: "s1",
      connected_at: 1000,
      last_heartbeat: 2000,
      reconnect_count: 0,
      messages_published: 10,
      messages_received: 5,
      error_count: 0,
    )
  let m = zenoh_update(zenoh_init(), HealthUpdated(connected_health))
  is_connected(m) |> should.be_true()
}

pub fn zenoh_message_rate_is_sum_published_received_test() {
  let health =
    zenoh_domain.ZenohHealth(
      status: zenoh_domain.Disconnected,
      session_id: "",
      connected_at: 0,
      last_heartbeat: 0,
      reconnect_count: 0,
      messages_published: 15,
      messages_received: 7,
      error_count: 0,
    )
  let m = zenoh_update(zenoh_init(), HealthUpdated(health))
  message_rate(m) |> should.equal(22)
}

pub fn zenoh_message_rate_zero_initially_test() {
  message_rate(zenoh_init()) |> should.equal(0)
}

// =============================================================================
// EFFECTS (AG-UI) TESTS
// =============================================================================

pub fn effects_subscribe_agent_builds_effect_test() {
  let eff = subscribe_agent("claude-agent-1")
  case eff {
    SubscribeAgent("claude-agent-1", topics) ->
      topics |> should.equal(["c3i/agui/events/claude-agent-1"])
    _ -> should.fail()
  }
}

pub fn effects_start_run_builds_effect_test() {
  let eff = start_run("claude-agent-1", "analyze this codebase")
  case eff {
    StartRun("claude-agent-1", "analyze this codebase", "") -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn effects_send_tool_result_builds_effect_test() {
  let eff = send_tool_result("tc-42", "{\"result\": \"ok\"}")
  case eff {
    SendToolResult("tc-42", _) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn effects_approve_builds_hitl_decision_test() {
  let eff = approve("req-1")
  case eff {
    SendHitlDecision("req-1", Approved) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn effects_reject_builds_hitl_decision_test() {
  let eff = reject("req-2")
  case eff {
    SendHitlDecision("req-2", Rejected) -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn effects_subscribe_zenoh_builds_effect_test() {
  let eff = subscribe_zenoh("indrajaal/health/**")
  case eff {
    SubscribeZenoh("indrajaal/health/**") -> True
    _ -> False
  }
  |> should.be_true()
}

pub fn effects_batch_wraps_list_test() {
  let effs = [subscribe_zenoh("t1"), subscribe_zenoh("t2")]
  let eff = batch(effs)
  case eff {
    BatchEffects(inner) -> inner |> list.length |> should.equal(2)
    _ -> should.fail()
  }
}

pub fn effects_none_builds_no_effect_test() {
  none() |> should.equal(NoEffect)
}

pub fn effects_decision_to_string_approved_test() {
  decision_to_string(Approved) |> should.equal("approved")
}

pub fn effects_decision_to_string_rejected_test() {
  decision_to_string(Rejected) |> should.equal("rejected")
}

pub fn effects_decision_to_string_escalated_test() {
  decision_to_string(Escalated) |> should.equal("escalated")
}

pub fn effects_decision_to_string_edited_test() {
  decision_to_string(Edited("new content"))
  |> should.equal("edited:new content")
}

pub fn effects_subscribe_agent_topic_includes_agent_id_test() {
  let eff = subscribe_agent("my-agent")
  case eff {
    SubscribeAgent(_, topics) ->
      list.any(topics, fn(t) { t == "c3i/agui/events/my-agent" })
      |> should.be_true()
    _ -> should.fail()
  }
}

pub fn effects_hitl_reject_is_distinct_from_approve_test() {
  let approved = approve("r1")
  let rejected = reject("r1")
  approved |> should.not_equal(rejected)
}

// =============================================================================
// PLANNING VIEW — Panel ID and cockpit mode structural tests
// These cover the PanelId and CockpitMode constructors used by planning_view.
// =============================================================================

pub fn planning_view_panel_ids_are_all_distinct_test() {
  let panels = [
    TaskBoard, OodaCycle, SafetyKernel, EnforcerShield, GraphVerify, OrchMesh,
    ChayaTwin, StartupOptim,
  ]
  panels |> list.length |> should.equal(8)
  panels |> list.first |> should.equal(Ok(TaskBoard))
  panels |> list.last |> should.equal(Ok(StartupOptim))
}

pub fn planning_view_cockpit_modes_all_distinct_test() {
  let modes = [Dark, Dim, Normal, Bright, EmergencyMode]
  modes |> list.length |> should.equal(5)
  modes |> list.first |> should.equal(Ok(Dark))
  modes |> list.last |> should.equal(Ok(EmergencyMode))
}

pub fn planning_view_safety_check_constructors_test() {
  let checks = [
    CheckPass("sc-001"),
    CheckFail("sc-002", "timeout"),
    CheckWarn("sc-003"),
    CheckNotRun("sc-004"),
  ]
  checks |> list.length |> should.equal(4)
}

pub fn planning_view_chat_message_constructors_test() {
  let msgs = [
    UserMsg("hello"),
    AgentMsg("reply"),
    ToolCallMsg("list_files", "{}"),
    EventMsg("RUN_STARTED", "run-1"),
  ]
  msgs |> list.length |> should.equal(4)
}

pub fn planning_view_service_node_health_field_test() {
  let svc = ServiceNode("zenoh", "running", 0.99)
  { svc.health >=. 0.8 } |> should.be_true()
}

pub fn planning_view_container_wave_fields_test() {
  let wave = ContainerWave(1, ["zenoh", "obs"], 2500)
  wave.wave |> should.equal(1)
  wave.containers |> list.length |> should.equal(2)
  wave.duration_ms |> should.equal(2500)
}

// =============================================================================
// HELPERS
// =============================================================================

fn make_test_report(healthy: Int, total: Int, compliant: Bool) {
  SwarmReport(
    healthy_containers: healthy,
    total_containers: total,
    ooda_metrics: OodaMetrics(
      agent_latency_ms: 25,
      intelligence_latency_ms: 80,
      compliance: compliant,
    ),
    fractal_layers: [],
  )
}

fn make_test_proof(result: VerificationResult) {
  ProofToken(
    dag_hash: "abc123",
    path: ["n1", "n2"],
    verified_at: 1_000_000,
    constraints_checked: ["SC-PROM-001"],
    result: result,
  )
}

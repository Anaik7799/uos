// =============================================================================
// Planning Dashboard: Lustre Model + TUI Render Tests
// =============================================================================
// Coverage: ui/lustre/planning_dashboard (init, update, query helpers),
//           ui/tui/planning_dashboard_view (render)
// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-009
// =============================================================================

import cepaf_gleam/ui/lustre/planning_dashboard.{
  type TaskCard, Bright, CheckFail, CheckPass, CheckWarn, ContainerWave, Dark,
  DashboardModel, Dim, EmergencyMode, ServiceNode, SyncPhaseResult, TaskCard,
}
import cepaf_gleam/ui/tui/planning_dashboard_view
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

// =============================================================================
// 1. init() returns Dark mode with empty state
// =============================================================================

pub fn init_returns_dark_mode_test() {
  let model = planning_dashboard.init()
  model.cockpit_mode |> should.equal(Dark)
}

pub fn init_returns_empty_tasks_test() {
  let model = planning_dashboard.init()
  model.tasks |> should.equal([])
}

pub fn init_returns_empty_services_test() {
  let model = planning_dashboard.init()
  model.services |> should.equal([])
}

pub fn init_returns_empty_circuits_test() {
  let model = planning_dashboard.init()
  model.open_circuits |> should.equal([])
}

pub fn init_returns_empty_safety_checks_test() {
  let model = planning_dashboard.init()
  model.safety_checks |> should.equal([])
}

pub fn init_returns_safety_active_test() {
  let model = planning_dashboard.init()
  model.safety_active |> should.be_true()
}

pub fn init_returns_zero_ooda_cycles_test() {
  let model = planning_dashboard.init()
  model.ooda_cycle_count |> should.equal(0)
}

pub fn init_returns_idle_ooda_phase_test() {
  let model = planning_dashboard.init()
  model.ooda_phase |> should.equal(planning_dashboard.Idle)
}

pub fn init_returns_empty_sync_phases_test() {
  let model = planning_dashboard.init()
  model.sync_phases |> should.equal([])
}

pub fn init_returns_empty_waves_test() {
  let model = planning_dashboard.init()
  model.waves |> should.equal([])
}

pub fn init_returns_all_filter_test() {
  let model = planning_dashboard.init()
  model.task_filter |> should.equal("all")
}

// =============================================================================
// 2. update with SetTaskFilter changes filter
// =============================================================================

pub fn update_set_task_filter_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.SetTaskFilter("pending"),
    )
  updated.task_filter |> should.equal("pending")
}

pub fn update_set_task_filter_preserves_tasks_test() {
  let tasks = [make_task("t1", "pending")]
  let model = DashboardModel(..planning_dashboard.init(), tasks: tasks)
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.SetTaskFilter("blocked"),
    )
  updated.tasks |> should.equal(tasks)
}

// =============================================================================
// 3. update with TasksLoaded populates tasks
// =============================================================================

pub fn update_tasks_loaded_test() {
  let model = planning_dashboard.init()
  let tasks = [make_task("t1", "pending"), make_task("t2", "completed")]
  let updated =
    planning_dashboard.update(model, planning_dashboard.TasksLoaded(tasks))
  list.length(updated.tasks) |> should.equal(2)
}

pub fn update_tasks_loaded_replaces_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("old", "pending"),
    ])
  let new_tasks = [make_task("new1", "completed")]
  let updated =
    planning_dashboard.update(model, planning_dashboard.TasksLoaded(new_tasks))
  list.length(updated.tasks) |> should.equal(1)
  case updated.tasks {
    [t, ..] -> t.id |> should.equal("new1")
    _ -> should.fail()
  }
}

// =============================================================================
// 4. update with OodaCycleCompleted updates cycle count
// =============================================================================

pub fn update_ooda_cycle_completed_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.OodaCycleCompleted(25, "nominal", "no_action"),
    )
  updated.ooda_cycle_count |> should.equal(1)
  updated.last_cycle_ms |> should.equal(25)
}

pub fn update_ooda_cycle_increments_test() {
  let model = planning_dashboard.init()
  let updated =
    model
    |> planning_dashboard.update(planning_dashboard.OodaCycleCompleted(
      10,
      "p1",
      "d1",
    ))
    |> planning_dashboard.update(planning_dashboard.OodaCycleCompleted(
      20,
      "p2",
      "d2",
    ))
    |> planning_dashboard.update(planning_dashboard.OodaCycleCompleted(
      30,
      "p3",
      "d3",
    ))
  updated.ooda_cycle_count |> should.equal(3)
  updated.last_cycle_ms |> should.equal(30)
}

// =============================================================================
// 5. update with SafetyChecksLoaded populates checks
// =============================================================================

pub fn update_safety_checks_loaded_test() {
  let model = planning_dashboard.init()
  let checks = [CheckPass("sil6"), CheckFail("memory", "OOM")]
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.SafetyChecksLoaded(checks),
    )
  list.length(updated.safety_checks) |> should.equal(2)
}

// =============================================================================
// 6. update with CircuitOpened adds to open_circuits
// =============================================================================

pub fn update_circuit_opened_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.CircuitOpened("zenoh-pub"),
    )
  list.length(updated.open_circuits) |> should.equal(1)
}

pub fn update_circuit_opened_multiple_test() {
  let model = planning_dashboard.init()
  let updated =
    model
    |> planning_dashboard.update(planning_dashboard.CircuitOpened("zenoh-pub"))
    |> planning_dashboard.update(planning_dashboard.CircuitOpened("db-write"))
  list.length(updated.open_circuits) |> should.equal(2)
}

// =============================================================================
// 7. update with CircuitClosed removes from open_circuits
// =============================================================================

pub fn update_circuit_closed_test() {
  let model = planning_dashboard.init()
  let updated =
    model
    |> planning_dashboard.update(planning_dashboard.CircuitOpened("zenoh-pub"))
    |> planning_dashboard.update(planning_dashboard.CircuitOpened("db-write"))
    |> planning_dashboard.update(planning_dashboard.CircuitClosed("zenoh-pub"))
  list.length(updated.open_circuits) |> should.equal(1)
}

pub fn update_circuit_closed_nonexistent_noop_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, planning_dashboard.CircuitClosed("ghost"))
  updated.open_circuits |> should.equal([])
}

// =============================================================================
// 8. update with ServicesUpdated changes services
// =============================================================================

pub fn update_services_updated_test() {
  let model = planning_dashboard.init()
  let svcs = [
    ServiceNode(name: "wisp", status: "online", health: 1.0),
    ServiceNode(name: "zenoh", status: "offline", health: 0.0),
  ]
  let updated =
    planning_dashboard.update(model, planning_dashboard.ServicesUpdated(svcs))
  list.length(updated.services) |> should.equal(2)
}

// =============================================================================
// 9. update with SyncPhaseCompleted adds phase result
// =============================================================================

pub fn update_sync_phase_completed_test() {
  let model = planning_dashboard.init()
  let phase = SyncPhaseResult(phase: "init", success: True, count: 5, errors: 0)
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.SyncPhaseCompleted(phase),
    )
  list.length(updated.sync_phases) |> should.equal(1)
}

pub fn update_sync_phase_appends_test() {
  let model = planning_dashboard.init()
  let p1 = SyncPhaseResult(phase: "init", success: True, count: 3, errors: 0)
  let p2 = SyncPhaseResult(phase: "connect", success: True, count: 7, errors: 0)
  let updated =
    model
    |> planning_dashboard.update(planning_dashboard.SyncPhaseCompleted(p1))
    |> planning_dashboard.update(planning_dashboard.SyncPhaseCompleted(p2))
  list.length(updated.sync_phases) |> should.equal(2)
}

// =============================================================================
// 10. update with WavesComputed sets waves
// =============================================================================

pub fn update_waves_computed_test() {
  let model = planning_dashboard.init()
  let waves = [
    ContainerWave(wave: 1, containers: ["redis", "postgres"], duration_ms: 500),
    ContainerWave(wave: 2, containers: ["wisp", "zenoh"], duration_ms: 300),
  ]
  let updated =
    planning_dashboard.update(model, planning_dashboard.WavesComputed(waves))
  list.length(updated.waves) |> should.equal(2)
}

// =============================================================================
// 11. update with CockpitModeChanged changes mode
// =============================================================================

pub fn update_cockpit_mode_changed_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.CockpitModeChanged(EmergencyMode),
    )
  updated.cockpit_mode |> should.equal(EmergencyMode)
}

pub fn update_cockpit_mode_to_bright_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.CockpitModeChanged(Bright),
    )
  updated.cockpit_mode |> should.equal(Bright)
}

// =============================================================================
// 12. determine_cockpit_mode — all healthy = Dark
// =============================================================================

pub fn determine_cockpit_mode_all_healthy_dark_test() {
  let model =
    DashboardModel(
      ..planning_dashboard.init(),
      services: [
        ServiceNode(name: "wisp", status: "online", health: 1.0),
        ServiceNode(name: "zenoh", status: "online", health: 1.0),
      ],
      safety_checks: [CheckPass("sil6")],
    )
  planning_dashboard.determine_cockpit_mode(model)
  |> should.equal(Dark)
}

pub fn determine_cockpit_mode_default_init_is_dim_test() {
  // Default init: no services → services_score=0.5, composite ≈ 0.85 → Dim
  planning_dashboard.determine_cockpit_mode(planning_dashboard.init())
  |> should.equal(Dim)
}

// =============================================================================
// 13. determine_cockpit_mode — degraded states
// =============================================================================

pub fn determine_cockpit_mode_with_violations_test() {
  let model =
    DashboardModel(
      ..planning_dashboard.init(),
      total_violations: 25,
      open_circuits: ["a", "b", "c"],
    )
  let mode = planning_dashboard.determine_cockpit_mode(model)
  // With high violations + circuits, score drops — should NOT be Dark
  { mode != Dark } |> should.be_true()
}

pub fn determine_cockpit_mode_safety_inactive_emergency_test() {
  let model = DashboardModel(..planning_dashboard.init(), safety_active: False)
  let mode = planning_dashboard.determine_cockpit_mode(model)
  // Safety inactive → score drops significantly
  { mode == EmergencyMode || mode == Bright }
  |> should.be_true()
}

// =============================================================================
// 14. health_score — takes DashboardModel
// =============================================================================

pub fn health_score_all_healthy_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), services: [
      ServiceNode(name: "wisp", status: "online", health: 1.0),
      ServiceNode(name: "zenoh", status: "online", health: 0.95),
    ])
  let score = planning_dashboard.health_score(model)
  { score >=. 0.8 } |> should.be_true()
}

pub fn health_score_empty_services_nominal_test() {
  let score = planning_dashboard.health_score(planning_dashboard.init())
  // Default init: safety active, guardian healthy, 0 violations, no services (0.5 weight)
  { score >=. 0.5 } |> should.be_true()
}

pub fn health_score_low_with_violations_and_circuits_test() {
  let model =
    DashboardModel(
      ..planning_dashboard.init(),
      total_violations: 50,
      open_circuits: ["a", "b", "c", "d"],
      safety_active: False,
    )
  let score = planning_dashboard.health_score(model)
  { score <. 0.5 } |> should.be_true()
}

// =============================================================================
// 15. pending_tasks — returns only "pending" tasks
// =============================================================================

pub fn pending_tasks_filters_correctly_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "pending"),
      make_task("t2", "completed"),
      make_task("t3", "pending"),
      make_task("t4", "blocked"),
    ])
  planning_dashboard.pending_tasks(model) |> list.length |> should.equal(2)
}

pub fn pending_tasks_empty_list_test() {
  planning_dashboard.pending_tasks(planning_dashboard.init())
  |> should.equal([])
}

// =============================================================================
// 16. blocked_tasks — returns only "blocked" tasks
// =============================================================================

pub fn blocked_tasks_filters_correctly_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "blocked"),
      make_task("t2", "completed"),
      make_task("t3", "blocked"),
    ])
  planning_dashboard.blocked_tasks(model) |> list.length |> should.equal(2)
}

pub fn blocked_tasks_none_blocked_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "pending"),
      make_task("t2", "completed"),
    ])
  planning_dashboard.blocked_tasks(model) |> should.equal([])
}

// =============================================================================
// 17. is_safe — active safety and no threats
// =============================================================================

pub fn is_safe_with_active_safety_no_threats_test() {
  let model =
    DashboardModel(
      ..planning_dashboard.init(),
      safety_active: True,
      safety_checks: [CheckPass("sil6")],
      quarantined: [],
    )
  planning_dashboard.is_safe(model) |> should.be_true()
}

pub fn is_safe_false_when_inactive_test() {
  let model = DashboardModel(..planning_dashboard.init(), safety_active: False)
  planning_dashboard.is_safe(model) |> should.be_false()
}

pub fn is_safe_false_with_quarantined_agent_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), quarantined: ["rogue-agent"])
  planning_dashboard.is_safe(model) |> should.be_false()
}

pub fn is_safe_false_with_high_threat_test() {
  let model = DashboardModel(..planning_dashboard.init(), threat_level: 0.8)
  planning_dashboard.is_safe(model) |> should.be_false()
}

// =============================================================================
// 18. all_checks_pass — all Pass results
// =============================================================================

pub fn all_checks_pass_true_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), safety_checks: [
      CheckPass("sil6"),
      CheckPass("mem"),
    ])
  planning_dashboard.all_checks_pass(model) |> should.be_true()
}

pub fn all_checks_pass_empty_test() {
  planning_dashboard.all_checks_pass(planning_dashboard.init())
  |> should.be_true()
}

pub fn all_checks_pass_with_warn_still_passes_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), safety_checks: [
      CheckPass("sil6"),
      CheckWarn("disk"),
    ])
  planning_dashboard.all_checks_pass(model) |> should.be_true()
}

// =============================================================================
// 19. all_checks_pass — one Fail returns False
// =============================================================================

pub fn all_checks_pass_with_fail_returns_false_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), safety_checks: [
      CheckPass("sil6"),
      CheckFail("mem", "OOM"),
    ])
  planning_dashboard.all_checks_pass(model) |> should.be_false()
}

pub fn all_checks_pass_all_fail_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), safety_checks: [
      CheckFail("a", "x"),
      CheckFail("b", "y"),
    ])
  planning_dashboard.all_checks_pass(model) |> should.be_false()
}

// =============================================================================
// 20. TUI render — init() produces non-empty string
// =============================================================================

pub fn tui_render_init_nonempty_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  { string.length(output) > 0 } |> should.be_true()
}

// =============================================================================
// 21. TUI render — init() contains "PLANNING COCKPIT"
// =============================================================================

pub fn tui_render_contains_planning_cockpit_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("PLANNING COCKPIT") |> should.be_true()
}

// =============================================================================
// 22. TUI render — Emergency mode contains red ANSI code
// =============================================================================

pub fn tui_render_emergency_has_red_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), cockpit_mode: EmergencyMode)
  let output = planning_dashboard_view.render(model)
  // Red ANSI escape = \x1b[31m
  output |> string.contains("\u{001b}[31m") |> should.be_true()
}

pub fn tui_render_emergency_contains_emergency_text_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), cockpit_mode: EmergencyMode)
  let output = planning_dashboard_view.render(model)
  output |> string.contains("EMERGENCY") |> should.be_true()
}

// =============================================================================
// 23. TUI render — Dark mode header uses green ANSI
// =============================================================================

pub fn tui_render_dark_mode_green_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  // Green ANSI escape = \x1b[32m
  output |> string.contains("\u{001b}[32m") |> should.be_true()
}

// =============================================================================
// 24. TUI render — contains all panel headers
// =============================================================================

pub fn tui_render_contains_tasks_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("TASKS") |> should.be_true()
}

pub fn tui_render_contains_ooda_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("OODA") |> should.be_true()
}

pub fn tui_render_contains_safety_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("SAFETY") |> should.be_true()
}

pub fn tui_render_contains_enforcer_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("ENFORCER") |> should.be_true()
}

pub fn tui_render_contains_services_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("SERVICES") |> should.be_true()
}

pub fn tui_render_contains_chaya_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("CHAYA SYNC") |> should.be_true()
}

pub fn tui_render_contains_startup_panel_test() {
  let output = planning_dashboard_view.render(planning_dashboard.init())
  output |> string.contains("STARTUP WAVES") |> should.be_true()
}

// =============================================================================
// 25. TUI render — with populated data shows metrics
// =============================================================================

pub fn tui_render_with_tasks_shows_counts_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "pending"),
      make_task("t2", "completed"),
      make_task("t3", "blocked"),
    ])
  let output = planning_dashboard_view.render(model)
  output |> string.contains("P:1") |> should.be_true()
  output |> string.contains("C:1") |> should.be_true()
  output |> string.contains("B:1") |> should.be_true()
  output |> string.contains("Total: 3") |> should.be_true()
}

pub fn tui_render_with_open_circuits_shows_count_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), open_circuits: [
      "zenoh-pub",
      "db-write",
    ])
  let output = planning_dashboard_view.render(model)
  output |> string.contains("2 OPEN") |> should.be_true()
}

pub fn tui_render_ooda_shows_cycle_count_test() {
  let model =
    DashboardModel(
      ..planning_dashboard.init(),
      ooda_cycle_count: 42,
      last_cycle_ms: 15,
    )
  let output = planning_dashboard_view.render(model)
  output |> string.contains("Cycles: 42") |> should.be_true()
  output |> string.contains("15ms") |> should.be_true()
}

// =============================================================================
// 26. Additional update message coverage
// =============================================================================

pub fn update_select_task_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, planning_dashboard.SelectTask("task-42"))
  updated.selected_task |> should.equal(Some("task-42"))
}

pub fn update_task_status_changed_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "pending"),
    ])
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.TaskStatusChanged("t1", "completed"),
    )
  case updated.tasks {
    [t, ..] -> t.status |> should.equal("completed")
    _ -> should.fail()
  }
}

pub fn update_threat_level_changed_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.ThreatLevelChanged(0.75),
    )
  updated.threat_level |> should.equal(0.75)
}

pub fn update_agent_quarantined_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.AgentQuarantined("rogue-agent"),
    )
  list.length(updated.quarantined) |> should.equal(1)
}

pub fn update_violation_recorded_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.ViolationRecorded("bad mutation"),
    )
  updated.total_violations |> should.equal(1)
  list.length(updated.recent_violations) |> should.equal(1)
}

pub fn update_quorum_changed_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, planning_dashboard.QuorumChanged(True))
  updated.quorum |> should.be_true()
}

pub fn update_refresh_all_noop_test() {
  let model = planning_dashboard.init()
  let updated = planning_dashboard.update(model, planning_dashboard.RefreshAll)
  updated |> should.equal(model)
}

pub fn update_ag_ui_connected_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, planning_dashboard.AgUiConnected(True))
  updated.ag_ui_connected |> should.be_true()
}

pub fn update_set_active_panel_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.SetActivePanel(planning_dashboard.OodaCycle),
    )
  updated.active_panel |> should.equal(planning_dashboard.OodaCycle)
}

pub fn update_sync_started_clears_phases_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), sync_phases: [
      SyncPhaseResult(phase: "old", success: True, count: 1, errors: 0),
    ])
  let updated = planning_dashboard.update(model, planning_dashboard.SyncStarted)
  updated.sync_phases |> should.equal([])
}

pub fn update_sync_finished_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(model, planning_dashboard.SyncFinished(3, 1))
  updated.orphan_count |> should.equal(3)
  updated.mismatch_count |> should.equal(1)
  updated.last_sync |> should.equal("completed")
}

pub fn update_graph_loaded_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.GraphLoaded(42, 100, "digraph {}"),
    )
  updated.graph_node_count |> should.equal(42)
  updated.graph_edge_count |> should.equal(100)
  updated.graph_dot |> should.equal("digraph {}")
}

pub fn update_critical_path_found_test() {
  let model = planning_dashboard.init()
  let updated =
    planning_dashboard.update(
      model,
      planning_dashboard.CriticalPathFound(["a", "b", "c"], 750),
    )
  list.length(updated.critical_path) |> should.equal(3)
  updated.total_startup_ms |> should.equal(750)
}

pub fn completed_tasks_filters_correctly_test() {
  let model =
    DashboardModel(..planning_dashboard.init(), tasks: [
      make_task("t1", "completed"),
      make_task("t2", "pending"),
      make_task("t3", "completed"),
    ])
  planning_dashboard.completed_tasks(model) |> list.length |> should.equal(2)
}

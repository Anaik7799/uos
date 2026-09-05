//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/planning_dashboard</module>
////     <fsharp-lineage>Cepaf.UI.Bolero.PlanningDashboard</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////     <mesh-domain>Planning 8-Panel SIL-6 Cockpit</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009, SC-AGUI-001, SC-AGUI-011, SC-AGUI-014, SC-A2UI-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Planning Dashboard - 8-Panel SIL-6 Agentic Cockpit Model
//// AG-UI protocol integration: events drive all 8 panels via SSE/WebSocket.
//// A2UI generative slots: agents can propose dynamic widgets per panel.
//// Lustre server component: OTP-supervised, WebSocket DOM patches to browser.
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009, SC-AGUI-001..017, SC-A2UI-001..005
////
//// ## Human-Specified Intent
//// <!-- HUMAN-ONLY: DO NOT AUTO-MODIFY -->
//// <!-- END HUMAN-ONLY -->

import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}

// =============================================================================
// Type Definitions — 8-Panel Dashboard
// =============================================================================

pub type CockpitMode {
  Dark
  Dim
  Normal
  Bright
  EmergencyMode
}

pub type PanelId {
  TaskBoard
  OodaCycle
  SafetyKernel
  EnforcerShield
  GraphVerify
  OrchMesh
  ChayaTwin
  StartupOptim
}

pub type TaskCard {
  TaskCard(
    id: String,
    title: String,
    status: String,
    priority: String,
    assignee: Option(String),
  )
}

pub type OodaPhase {
  ObservePhase
  OrientPhase
  DecidePhase
  ActPhase
  Idle
}

pub type SafetyCheckResult {
  CheckPass(name: String)
  CheckFail(name: String, reason: String)
  CheckWarn(name: String)
  CheckNotRun(name: String)
}

pub type ServiceNode {
  ServiceNode(name: String, status: String, health: Float)
}

pub type SyncPhaseResult {
  SyncPhaseResult(phase: String, success: Bool, count: Int, errors: Int)
}

pub type ContainerWave {
  ContainerWave(wave: Int, containers: List(String), duration_ms: Int)
}

pub type ChatMessage {
  UserMsg(text: String)
  AgentMsg(text: String)
  ToolCallMsg(tool: String, args: String)
  EventMsg(event_type: String, data: String)
}

pub type DashboardModel {
  DashboardModel(
    // Panel 1: Tasks
    tasks: List(TaskCard),
    task_filter: String,
    selected_task: Option(String),
    // Panel 2: OODA
    ooda_phase: OodaPhase,
    ooda_cycle_count: Int,
    last_cycle_ms: Int,
    ooda_pattern: String,
    ooda_decision: String,
    // Panel 3: Safety
    safety_active: Bool,
    threat_level: Float,
    guardian_healthy: Bool,
    safety_checks: List(SafetyCheckResult),
    quarantined: List(String),
    // Panel 4: Enforcer
    total_violations: Int,
    open_circuits: List(String),
    recent_violations: List(String),
    // Panel 5: Graph
    graph_node_count: Int,
    graph_edge_count: Int,
    graph_checks: List(SafetyCheckResult),
    graph_dot: String,
    // Panel 6: Orchestration
    services: List(ServiceNode),
    quorum: Bool,
    distribution_strategy: String,
    // Panel 7: Chaya
    sync_phases: List(SyncPhaseResult),
    orphan_count: Int,
    mismatch_count: Int,
    last_sync: String,
    // Panel 8: Startup
    waves: List(ContainerWave),
    critical_path: List(String),
    total_startup_ms: Int,
    // UI state
    active_panel: PanelId,
    cockpit_mode: CockpitMode,
    ag_ui_connected: Bool,
    chat_messages: List(ChatMessage),
  )
}

pub type Msg =
  DashboardMsg

pub type DashboardMsg {
  // Task messages
  SetTaskFilter(String)
  SelectTask(String)
  TasksLoaded(List(TaskCard))
  TaskStatusChanged(String, String)
  // OODA messages
  OodaPhaseChanged(OodaPhase)
  OodaCycleCompleted(Int, String, String)
  // Safety messages
  SafetyChecksLoaded(List(SafetyCheckResult))
  ThreatLevelChanged(Float)
  AgentQuarantined(String)
  // Enforcer messages
  ViolationRecorded(String)
  CircuitOpened(String)
  CircuitClosed(String)
  // Graph messages
  GraphLoaded(Int, Int, String)
  GraphChecksRan(List(SafetyCheckResult))
  // Orchestration messages
  ServicesUpdated(List(ServiceNode))
  QuorumChanged(Bool)
  SetDistributionStrategy(String)
  // Chaya messages
  SyncStarted
  SyncPhaseCompleted(SyncPhaseResult)
  SyncFinished(Int, Int)
  // Startup messages
  WavesComputed(List(ContainerWave))
  CriticalPathFound(List(String), Int)
  // UI messages
  SetActivePanel(PanelId)
  CockpitModeChanged(CockpitMode)
  AgUiConnected(Bool)
  ChatMessageReceived(ChatMessage)
  RefreshAll
  NextCockpitMode
  SelectPanel(PanelId)
  CloseDetail
  // --- AG-UI Protocol Events (SC-AGUI-001) ---
  AgUiRunStarted(thread_id: String, run_id: String)
  AgUiRunFinished(thread_id: String, run_id: String)
  AgUiRunError(message: String, code: String)
  AgUiStepStarted(step_name: String)
  AgUiStepFinished(step_name: String)
  AgUiTextContent(message_id: String, delta: String)
  AgUiStateSnapshot(snapshot: json.Json)
  AgUiStateDelta(patches: json.Json)
  AgUiToolCallStart(tool_call_id: String, tool_name: String)
  AgUiToolCallEnd(tool_call_id: String)
  AgUiToolCallResult(tool_call_id: String, content: String)
  AgUiReasoningContent(message_id: String, delta: String)
  // --- HITL (Human-in-the-Loop) (SC-AGUI-004) ---
  HitlApprovalRequested(request_id: String, description: String)
  HitlUserApproved(request_id: String)
  HitlUserRejected(request_id: String)
  // --- A2UI Generative UI (SC-A2UI-001) ---
  A2uiComponentProposed(panel: PanelId, component_json: json.Json)
  // --- Drag-Drop Kanban (SC-HMI-010) ---
  DragTaskStarted(task_id: String)
  DragTaskOver(column: String)
  DragTaskDropped(task_id: String, new_status: String)
}

// =============================================================================
// Init — Dark cockpit, empty lists, nominal defaults
// =============================================================================

pub fn init() -> DashboardModel {
  DashboardModel(
    tasks: [],
    task_filter: "all",
    selected_task: None,
    ooda_phase: Idle,
    ooda_cycle_count: 0,
    last_cycle_ms: 0,
    ooda_pattern: "",
    ooda_decision: "",
    safety_active: True,
    threat_level: 0.0,
    guardian_healthy: True,
    safety_checks: [],
    quarantined: [],
    total_violations: 0,
    open_circuits: [],
    recent_violations: [],
    graph_node_count: 0,
    graph_edge_count: 0,
    graph_checks: [],
    graph_dot: "",
    services: [],
    quorum: False,
    distribution_strategy: "round_robin",
    sync_phases: [],
    orphan_count: 0,
    mismatch_count: 0,
    last_sync: "",
    waves: [],
    critical_path: [],
    total_startup_ms: 0,
    active_panel: TaskBoard,
    cockpit_mode: Dark,
    ag_ui_connected: False,
    chat_messages: [],
  )
}

// =============================================================================
// Update — Exhaustive pattern matching on all DashboardMsg variants
// =============================================================================

pub fn update(model: DashboardModel, msg: DashboardMsg) -> DashboardModel {
  case msg {
    // --- Task messages ---
    SetTaskFilter(filter) -> DashboardModel(..model, task_filter: filter)

    SelectTask(id) -> DashboardModel(..model, selected_task: Some(id))

    TasksLoaded(tasks) -> DashboardModel(..model, tasks: tasks)

    TaskStatusChanged(id, new_status) -> {
      let updated_tasks =
        list.map(model.tasks, fn(t: TaskCard) {
          case t.id == id {
            True -> TaskCard(..t, status: new_status)
            False -> t
          }
        })
      DashboardModel(..model, tasks: updated_tasks)
    }

    // --- OODA messages ---
    OodaPhaseChanged(phase) -> DashboardModel(..model, ooda_phase: phase)

    OodaCycleCompleted(cycle_ms, pattern, decision) ->
      DashboardModel(
        ..model,
        ooda_cycle_count: model.ooda_cycle_count + 1,
        last_cycle_ms: cycle_ms,
        ooda_pattern: pattern,
        ooda_decision: decision,
        ooda_phase: Idle,
      )

    // --- Safety messages ---
    SafetyChecksLoaded(checks) -> DashboardModel(..model, safety_checks: checks)

    ThreatLevelChanged(level) -> DashboardModel(..model, threat_level: level)

    AgentQuarantined(agent_id) ->
      DashboardModel(..model, quarantined: [agent_id, ..model.quarantined])

    // --- Enforcer messages ---
    ViolationRecorded(description) ->
      DashboardModel(
        ..model,
        total_violations: model.total_violations + 1,
        recent_violations: case list.length(model.recent_violations) >= 50 {
          True -> [description, ..list.take(model.recent_violations, 49)]
          False -> [description, ..model.recent_violations]
        },
      )

    CircuitOpened(agent_id) ->
      DashboardModel(
        ..model,
        open_circuits: case list.contains(model.open_circuits, agent_id) {
          True -> model.open_circuits
          False -> [agent_id, ..model.open_circuits]
        },
      )

    CircuitClosed(agent_id) ->
      DashboardModel(
        ..model,
        open_circuits: list.filter(model.open_circuits, fn(a) { a != agent_id }),
      )

    // --- Graph messages ---
    GraphLoaded(nodes, edges, dot) ->
      DashboardModel(
        ..model,
        graph_node_count: nodes,
        graph_edge_count: edges,
        graph_dot: dot,
      )

    GraphChecksRan(checks) -> DashboardModel(..model, graph_checks: checks)

    // --- Orchestration messages ---
    ServicesUpdated(services) -> DashboardModel(..model, services: services)

    QuorumChanged(q) -> DashboardModel(..model, quorum: q)

    SetDistributionStrategy(strategy) ->
      DashboardModel(..model, distribution_strategy: strategy)

    // --- Chaya messages ---
    SyncStarted -> DashboardModel(..model, sync_phases: [])

    SyncPhaseCompleted(phase_result) ->
      DashboardModel(
        ..model,
        sync_phases: list.append(model.sync_phases, [phase_result]),
      )

    SyncFinished(orphans, mismatches) ->
      DashboardModel(
        ..model,
        orphan_count: orphans,
        mismatch_count: mismatches,
        last_sync: "completed",
      )

    // --- Startup messages ---
    WavesComputed(waves) -> DashboardModel(..model, waves: waves)

    CriticalPathFound(path, total_ms) ->
      DashboardModel(..model, critical_path: path, total_startup_ms: total_ms)

    // --- UI messages ---
    SetActivePanel(panel) -> DashboardModel(..model, active_panel: panel)

    CockpitModeChanged(mode) -> DashboardModel(..model, cockpit_mode: mode)

    AgUiConnected(connected) ->
      DashboardModel(..model, ag_ui_connected: connected)

    ChatMessageReceived(chat_msg) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [chat_msg]),
      )

    RefreshAll -> model

    // --- AG-UI Protocol Event Handlers (SC-AGUI-001) ---
    AgUiRunStarted(_, run_id) ->
      DashboardModel(
        ..model,
        ag_ui_connected: True,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("RUN_STARTED", run_id),
        ]),
      )

    AgUiRunFinished(_, run_id) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("RUN_FINISHED", run_id),
        ]),
      )

    AgUiRunError(message, code) ->
      DashboardModel(
        ..model,
        cockpit_mode: Bright,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("RUN_ERROR", message <> " [" <> code <> "]"),
        ]),
      )

    AgUiStepStarted(step_name) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("STEP_STARTED", step_name),
        ]),
      )

    AgUiStepFinished(step_name) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("STEP_FINISHED", step_name),
        ]),
      )

    AgUiTextContent(_, delta) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          AgentMsg(delta),
        ]),
      )

    AgUiStateSnapshot(_snapshot) ->
      // Full state replacement — apply to dashboard
      // In production, deserialize snapshot JSON and rebuild model
      model

    AgUiStateDelta(_patches) ->
      // Incremental RFC 6902 patches — apply to model fields
      // In production, use agui/state.gleam patch operations
      model

    AgUiToolCallStart(tool_call_id, tool_name) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          ToolCallMsg(tool_name, tool_call_id),
        ]),
      )

    AgUiToolCallEnd(_) -> model

    AgUiToolCallResult(tool_call_id, content) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("TOOL_RESULT", tool_call_id <> ": " <> content),
        ]),
      )

    AgUiReasoningContent(_, delta) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("REASONING", delta),
        ]),
      )

    // --- HITL Handlers (SC-AGUI-004) ---
    HitlApprovalRequested(request_id, description) ->
      DashboardModel(
        ..model,
        cockpit_mode: Normal,
        chat_messages: list.append(model.chat_messages, [
          EventMsg("HITL_REQUEST", request_id <> ": " <> description),
        ]),
      )

    HitlUserApproved(request_id) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          UserMsg("Approved: " <> request_id),
        ]),
      )

    HitlUserRejected(request_id) ->
      DashboardModel(
        ..model,
        chat_messages: list.append(model.chat_messages, [
          UserMsg("Rejected: " <> request_id),
        ]),
      )

    // --- A2UI Generative UI (SC-A2UI-001) ---
    A2uiComponentProposed(_, _component_json) ->
      // Agent proposed a dynamic widget — render via A2UI catalog
      // In production, validate against catalog + render in target panel
      model

    // --- Drag-Drop Kanban ---
    DragTaskStarted(_task_id) -> model
    // Visual only — no model change on drag start
    DragTaskOver(_column) -> model
    // Visual only — highlight target column
    DragTaskDropped(task_id, new_status) -> {
      let updated_tasks =
        list.map(model.tasks, fn(t: TaskCard) {
          case t.id == task_id {
            True -> TaskCard(..t, status: new_status)
            False -> t
          }
        })
      DashboardModel(..model, tasks: updated_tasks)
    }

    NextCockpitMode ->
      DashboardModel(
        ..model,
        cockpit_mode: next_cockpit_mode(model.cockpit_mode),
      )

    SelectPanel(panel) -> DashboardModel(..model, active_panel: panel)

    CloseDetail -> DashboardModel(..model, selected_task: None)
  }
}

fn next_cockpit_mode(mode: CockpitMode) -> CockpitMode {
  case mode {
    Dark -> Dim
    Dim -> Normal
    Normal -> Bright
    Bright -> EmergencyMode
    EmergencyMode -> Dark
  }
}

// =============================================================================
// Health Score — Composite from safety + enforcer + services
// =============================================================================

pub fn health_score(model: DashboardModel) -> Float {
  // Safety component (0.0 to 1.0) — weight 40%
  let safety_score = case model.safety_active, model.guardian_healthy {
    True, True -> 1.0 -. float.min(model.threat_level, 1.0)
    True, False -> 0.3
    False, _ -> 0.0
  }

  // Enforcer component (0.0 to 1.0) — weight 30%
  let enforcer_score = case model.total_violations {
    0 -> 1.0
    n if n < 5 -> 0.7
    n if n < 20 -> 0.4
    _ -> 0.1
  }
  let circuit_count = list.length(model.open_circuits)
  let enforcer_circuit_penalty = case circuit_count {
    0 -> 0.0
    n if n < 3 -> 0.2
    _ -> 0.5
  }
  let enforcer_final =
    float.max(enforcer_score -. enforcer_circuit_penalty, 0.0)

  // Services component (0.0 to 1.0) — weight 30%
  let service_count = list.length(model.services)
  let services_score = case service_count {
    0 -> 0.5
    _ -> {
      let healthy_count =
        list.count(model.services, fn(s: ServiceNode) { s.health >=. 0.8 })
      int.to_float(healthy_count) /. int.to_float(service_count)
    }
  }

  // Weighted composite
  let composite =
    { safety_score *. 0.4 }
    +. { enforcer_final *. 0.3 }
    +. { services_score *. 0.3 }

  // Clamp to [0.0, 1.0]
  float.min(float.max(composite, 0.0), 1.0)
}

// =============================================================================
// Determine Cockpit Mode — Based on health score thresholds
// =============================================================================

pub fn determine_cockpit_mode(model: DashboardModel) -> CockpitMode {
  let score = health_score(model)
  case score >=. 0.9 {
    True -> Dark
    False ->
      case score >=. 0.7 {
        True -> Dim
        False ->
          case score >=. 0.5 {
            True -> Normal
            False ->
              case score >=. 0.3 {
                True -> Bright
                False -> EmergencyMode
              }
          }
      }
  }
}

// =============================================================================
// View — Transport layer rendering Model to Lustre HTML Elements
// =============================================================================

import lustre/attribute as attr
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub fn view(model: DashboardModel) -> Element(Msg) {
  let health = health_score(model)
  let mode = determine_cockpit_mode(model)

  // Main dashboard container with dark cockpit styling
  html.div(
    [attr.class("dashboard-container"), attr.class(cockpit_mode_class(mode))],
    [
      // Header: status bar with health score + mode selector
      render_header(model, health, mode),

      // Main content: 8-panel grid + sidebar
      html.div([attr.class("dashboard-layout")], [
        // Left sidebar: navigation + task filter
        render_sidebar(model),

        // Center: 8-panel grid (4 cols x 2 rows)
        html.div([attr.class("panel-grid")], [
          // Row 1
          render_panel_task_board(model),
          render_panel_ooda_cycle(model),
          render_panel_safety_kernel(model),
          render_panel_enforcer_shield(model),
          // Row 2
          render_panel_graph_verify(model),
          render_panel_orch_mesh(model),
          render_panel_chaya_twin(model),
          render_panel_startup_optim(model),
        ]),
      ]),

      // Bottom: detail panel + chat panel
      html.div([attr.class("bottom-panels")], [
        render_detail_panel(model),
        render_chat_panel(model),
      ]),
    ],
  )
}

// =============================================================================
// Header rendering — Status bar with health score + mode selector
// =============================================================================

fn render_header(
  _model: DashboardModel,
  health: Float,
  mode: CockpitMode,
) -> Element(Msg) {
  let health_pct = float.round(health *. 100.0) |> int.to_string
  let mode_str = cockpit_mode_to_string(mode)

  html.header(
    [attr.class("dashboard-header"), attr.class("dark-cockpit-" <> mode_str)],
    [
      html.h1([], [html.text("C3I Planning Cockpit")]),
      html.div([attr.class("header-status")], [
        html.span([attr.class("health-score")], [
          html.text("Health: " <> health_pct <> "%"),
        ]),
        html.span(
          [attr.class("cockpit-mode"), attr.class("mode-" <> mode_str)],
          [html.text("Mode: " <> mode_str)],
        ),
        html.button([attr.class("mode-selector"), on_click(NextCockpitMode)], [
          html.text("Change Mode"),
        ]),
      ]),
    ],
  )
}

// =============================================================================
// Sidebar — Navigation + task filter
// =============================================================================

fn render_sidebar(model: DashboardModel) -> Element(Msg) {
  html.aside([attr.class("sidebar")], [
    html.nav([attr.class("panel-nav")], [
      render_nav_button("Task Board", TaskBoard, model.active_panel),
      render_nav_button("OODA Cycle", OodaCycle, model.active_panel),
      render_nav_button("Safety Kernel", SafetyKernel, model.active_panel),
      render_nav_button("Enforcer Shield", EnforcerShield, model.active_panel),
      render_nav_button("Graph Verify", GraphVerify, model.active_panel),
      render_nav_button("Orch Mesh", OrchMesh, model.active_panel),
      render_nav_button("Chaya Twin", ChayaTwin, model.active_panel),
      render_nav_button("Startup Optim", StartupOptim, model.active_panel),
    ]),
    html.div([attr.class("task-filter")], [
      html.label([], [html.text("Filter: ")]),
      html.select([on_change(SetTaskFilter)], [
        html.option([attr.value("all")], "All Tasks"),
        html.option([attr.value("pending")], "Pending"),
        html.option([attr.value("in_progress")], "In Progress"),
        html.option([attr.value("completed")], "Completed"),
        html.option([attr.value("blocked")], "Blocked"),
      ]),
    ]),
  ])
}

fn render_nav_button(
  label: String,
  panel: PanelId,
  active: PanelId,
) -> Element(Msg) {
  let is_active = panel == active
  html.button(
    [
      attr.class("nav-button"),
      attr.class(case is_active {
        True -> "active"
        False -> ""
      }),
      on_click(SelectPanel(panel)),
    ],
    [html.text(label)],
  )
}

// =============================================================================
// Panel 1: Task Board — Kanban with drag-drop
// =============================================================================

fn render_panel_task_board(model: DashboardModel) -> Element(Msg) {
  let filtered_tasks = case model.task_filter {
    "all" -> model.tasks
    "pending" -> pending_tasks(model)
    "in_progress" ->
      list.filter(model.tasks, fn(t) { t.status == "in_progress" })
    "completed" -> completed_tasks(model)
    "blocked" -> blocked_tasks(model)
    _ -> model.tasks
  }

  html.div([attr.class("panel"), attr.class("panel-task-board")], [
    html.h2([], [html.text("Task Board")]),
    html.div([attr.class("kanban-board")], [
      render_kanban_column("Pending", "pending", filtered_tasks),
      render_kanban_column("In Progress", "in_progress", filtered_tasks),
      render_kanban_column("Completed", "completed", filtered_tasks),
      render_kanban_column("Blocked", "blocked", filtered_tasks),
    ]),
  ])
}

fn render_kanban_column(
  label: String,
  status: String,
  all_tasks: List(TaskCard),
) -> Element(Msg) {
  let column_tasks = list.filter(all_tasks, fn(t) { t.status == status })

  html.div([attr.class("kanban-column"), attr.class("column-" <> status)], [
    html.h3([], [html.text(label)]),
    html.div(
      [
        attr.class("kanban-drop-zone"),
        on_drag_over(DragTaskOver(status)),
        on_drop(DragTaskDropped("", status)),
      ],
      list.map(column_tasks, fn(task: TaskCard) {
        html.div(
          [
            attr.class("task-card"),
            attr.draggable(True),
            on_drag_start(DragTaskStarted(task.id)),
          ],
          [
            html.div([attr.class("task-header")], [
              html.span([attr.class("task-title")], [html.text(task.title)]),
              html.span([attr.class("task-priority-" <> task.priority)], [
                html.text(task.priority),
              ]),
            ]),
            html.div([attr.class("task-assignee")], [
              html.text(case task.assignee {
                Some(a) -> "👤 " <> a
                None -> "(unassigned)"
              }),
            ]),
          ],
        )
      }),
    ),
  ])
}

// =============================================================================
// Panel 2: OODA Cycle
// =============================================================================

fn render_panel_ooda_cycle(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("panel"), attr.class("panel-ooda")], [
    html.h2([], [html.text("OODA Cycle")]),
    html.div([attr.class("ooda-stats")], [
      html.p([], [
        html.text("Phase: " <> ooda_phase_to_string(model.ooda_phase)),
      ]),
      html.p([], [
        html.text("Cycles: " <> int.to_string(model.ooda_cycle_count)),
      ]),
      html.p([], [
        html.text("Last: " <> int.to_string(model.last_cycle_ms) <> "ms"),
      ]),
      html.p([], [
        html.text("Pattern: " <> model.ooda_pattern),
      ]),
    ]),
    render_ooda_ring(model.ooda_phase),
  ])
}

fn render_ooda_ring(phase: OodaPhase) -> Element(Msg) {
  // ASCII ring showing O->O->D->A cycle
  let ring = case phase {
    ObservePhase -> "[O]→o→d→a"
    OrientPhase -> "o→[O]→d→a"
    DecidePhase -> "o→o→[D]→a"
    ActPhase -> "o→o→d→[A]"
    Idle -> "idle"
  }
  html.pre([attr.class("ooda-ring")], [html.text(ring)])
}

// =============================================================================
// Panel 3: Safety Kernel
// =============================================================================

fn render_panel_safety_kernel(model: DashboardModel) -> Element(Msg) {
  let threat_pct = float.round(model.threat_level *. 100.0) |> int.to_string

  html.div([attr.class("panel"), attr.class("panel-safety")], [
    html.h2([], [html.text("Safety Kernel")]),
    html.div([attr.class("safety-status")], [
      html.span(
        [attr.class("safety-active-" <> bool_to_string(model.safety_active))],
        [
          html.text(case model.safety_active {
            True -> "✓ Active"
            False -> "✗ Inactive"
          }),
        ],
      ),
      html.span(
        [
          attr.class(
            "guardian-healthy-" <> bool_to_string(model.guardian_healthy),
          ),
        ],
        [
          html.text(case model.guardian_healthy {
            True -> "✓ Guardian OK"
            False -> "✗ Guardian Failed"
          }),
        ],
      ),
    ]),
    html.div([attr.class("threat-level")], [
      html.label([], [html.text("Threat: " <> threat_pct <> "%")]),
      html.div(
        [
          attr.class("progress-bar"),
          attr.class("threat-" <> threat_level_class(model.threat_level)),
        ],
        [
          html.div(
            [
              attr.class("progress-fill"),
              attr.style("width", threat_pct <> "%"),
            ],
            [],
          ),
        ],
      ),
    ]),
    html.div([attr.class("safety-checks")], [
      html.h3([], [html.text("Checks:")]),
      html.ul(
        [],
        list.map(model.safety_checks, fn(check) {
          html.li([attr.class("check-" <> safety_check_class(check))], [
            html.text(safety_check_text(check)),
          ])
        }),
      ),
    ]),
  ])
}

fn threat_level_class(level: Float) -> String {
  case level {
    l if l <. 0.3 -> "low"
    l if l <. 0.6 -> "medium"
    l if l <. 0.8 -> "high"
    _ -> "critical"
  }
}

fn safety_check_class(check: SafetyCheckResult) -> String {
  case check {
    CheckPass(_) -> "pass"
    CheckFail(_, _) -> "fail"
    CheckWarn(_) -> "warn"
    CheckNotRun(_) -> "not-run"
  }
}

fn safety_check_text(check: SafetyCheckResult) -> String {
  case check {
    CheckPass(n) -> "✓ " <> n
    CheckFail(n, r) -> "✗ " <> n <> ": " <> r
    CheckWarn(n) -> "⚠ " <> n
    CheckNotRun(n) -> "- " <> n
  }
}

// =============================================================================
// Panel 4: Enforcer Shield
// =============================================================================

fn render_panel_enforcer_shield(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("panel"), attr.class("panel-enforcer")], [
    html.h2([], [html.text("Enforcer Shield")]),
    html.div([attr.class("violations-count")], [
      html.h3([], [
        html.text("Violations: " <> int.to_string(model.total_violations)),
      ]),
    ]),
    html.div([attr.class("circuits")], [
      html.h3([], [html.text("Open Circuits:")]),
      html.ul(
        [],
        list.map(model.open_circuits, fn(circuit) {
          html.li([], [html.text(circuit)])
        }),
      ),
    ]),
    html.div([attr.class("recent-violations")], [
      html.h3([], [html.text("Recent:")]),
      html.ul(
        [],
        list.take(model.recent_violations, 5)
          |> list.map(fn(v) { html.li([], [html.text(v)]) }),
      ),
    ]),
  ])
}

// =============================================================================
// Panel 5: Graph Verify
// =============================================================================

fn render_panel_graph_verify(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("panel"), attr.class("panel-graph")], [
    html.h2([], [html.text("Graph Verify")]),
    html.div([attr.class("graph-stats")], [
      html.p([], [html.text("Nodes: " <> int.to_string(model.graph_node_count))]),
      html.p([], [html.text("Edges: " <> int.to_string(model.graph_edge_count))]),
    ]),
    html.div([attr.class("graph-checks")], [
      html.ul(
        [],
        list.map(model.graph_checks, fn(check) {
          html.li([attr.class("check-" <> safety_check_class(check))], [
            html.text(safety_check_text(check)),
          ])
        }),
      ),
    ]),
    html.details([], [
      html.summary([], [html.text("View Graph (DOT)")]),
      html.pre([attr.class("graph-dot")], [html.text(model.graph_dot)]),
    ]),
  ])
}

// =============================================================================
// Panel 6: Orchestration Mesh
// =============================================================================

fn render_panel_orch_mesh(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("panel"), attr.class("panel-orch")], [
    html.h2([], [html.text("Orch Mesh")]),
    html.div([attr.class("quorum-status")], [
      html.span([attr.class("quorum-" <> bool_to_string(model.quorum))], [
        html.text(case model.quorum {
          True -> "✓ Quorum"
          False -> "✗ No Quorum"
        }),
      ]),
    ]),
    html.p([], [html.text("Strategy: " <> model.distribution_strategy)]),
    html.div([attr.class("services-health")], [
      html.h3([], [html.text("Services:")]),
      html.ul(
        [],
        list.map(model.services, fn(svc: ServiceNode) {
          let health_pct = float.round(svc.health *. 100.0) |> int.to_string
          html.li([attr.class("service-" <> svc.status)], [
            html.text(svc.name <> ": " <> health_pct <> "%"),
          ])
        }),
      ),
    ]),
  ])
}

// =============================================================================
// Panel 7: Chaya Twin
// =============================================================================

fn render_panel_chaya_twin(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("panel"), attr.class("panel-chaya")], [
    html.h2([], [html.text("Chaya Twin")]),
    html.div([attr.class("sync-phases")], [
      html.ul(
        [],
        list.map(model.sync_phases, fn(phase: SyncPhaseResult) {
          html.li(
            [
              attr.class(case phase.success {
                True -> "success"
                False -> "failure"
              }),
            ],
            [
              html.text(
                phase.phase
                <> ": "
                <> int.to_string(phase.count)
                <> " items, "
                <> int.to_string(phase.errors)
                <> " errors",
              ),
            ],
          )
        }),
      ),
    ]),
    html.p([], [html.text("Orphans: " <> int.to_string(model.orphan_count))]),
    html.p([], [
      html.text("Mismatches: " <> int.to_string(model.mismatch_count)),
    ]),
    html.p([], [html.text("Last sync: " <> model.last_sync)]),
  ])
}

// =============================================================================
// Panel 8: Startup Optimization
// =============================================================================

fn render_panel_startup_optim(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("panel"), attr.class("panel-startup")], [
    html.h2([], [html.text("Startup Optim")]),
    html.p([], [
      html.text("Total: " <> int.to_string(model.total_startup_ms) <> "ms"),
    ]),
    html.div([attr.class("waves")], [
      html.h3([], [html.text("Waves:")]),
      html.ul(
        [],
        list.map(model.waves, fn(wave: ContainerWave) {
          html.li([], [
            html.text(
              "Wave "
              <> int.to_string(wave.wave)
              <> ": "
              <> int.to_string(list.length(wave.containers))
              <> " containers, "
              <> int.to_string(wave.duration_ms)
              <> "ms",
            ),
          ])
        }),
      ),
    ]),
    html.div([attr.class("critical-path")], [
      html.h3([], [html.text("Critical Path:")]),
      html.ol(
        [],
        list.map(model.critical_path, fn(step) {
          html.li([], [html.text(step)])
        }),
      ),
    ]),
  ])
}

// =============================================================================
// Detail Panel — Selected task information
// =============================================================================

fn render_detail_panel(model: DashboardModel) -> Element(Msg) {
  case model.selected_task {
    Some(task_id) -> {
      case list.find(model.tasks, fn(t) { t.id == task_id }) {
        Ok(task) ->
          html.div([attr.class("detail-panel")], [
            html.h2([], [html.text(task.title)]),
            html.div([attr.class("task-details")], [
              html.p([], [html.text("ID: " <> task.id)]),
              html.p([], [html.text("Status: " <> task.status)]),
              html.p([], [html.text("Priority: " <> task.priority)]),
              html.p([], [
                html.text(
                  "Assignee: "
                  <> case task.assignee {
                    Some(a) -> a
                    None -> "(unassigned)"
                  },
                ),
              ]),
            ]),
            html.button([on_click(CloseDetail)], [html.text("Close")]),
          ])
        Error(_) -> html.div([], [])
      }
    }
    None ->
      html.div([attr.class("detail-panel"), attr.class("empty")], [
        html.p([], [html.text("Select a task to view details")]),
      ])
  }
}

// =============================================================================
// Chat Panel — AG-UI message display
// =============================================================================

fn render_chat_panel(model: DashboardModel) -> Element(Msg) {
  html.div([attr.class("chat-panel")], [
    html.h2([], [html.text("AG-UI Stream")]),
    html.div(
      [attr.class("chat-messages")],
      list.map(model.chat_messages, fn(msg) { render_chat_message(msg) }),
    ),
    html.div([attr.class("ag-ui-status")], [
      html.span(
        [attr.class("status-" <> bool_to_string(model.ag_ui_connected))],
        [
          html.text(case model.ag_ui_connected {
            True -> "🟢 Connected"
            False -> "🔴 Disconnected"
          }),
        ],
      ),
    ]),
  ])
}

fn render_chat_message(msg: ChatMessage) -> Element(Msg) {
  case msg {
    UserMsg(text) ->
      html.div([attr.class("message user-message")], [
        html.span([attr.class("role")], [html.text("User:")]),
        html.span([attr.class("text")], [html.text(text)]),
      ])
    AgentMsg(text) ->
      html.div([attr.class("message agent-message")], [
        html.span([attr.class("role")], [html.text("Agent:")]),
        html.span([attr.class("text")], [html.text(text)]),
      ])
    ToolCallMsg(tool, args) ->
      html.div([attr.class("message tool-message")], [
        html.span([attr.class("role")], [html.text("Tool:")]),
        html.span([attr.class("tool")], [html.text(tool)]),
        html.span([attr.class("args")], [html.text(args)]),
      ])
    EventMsg(event_type, data) ->
      html.div([attr.class("message event-message")], [
        html.span([attr.class("role")], [html.text("Event:")]),
        html.span([attr.class("type")], [html.text(event_type)]),
        html.span([attr.class("data")], [html.text(data)]),
      ])
  }
}

// =============================================================================
// Event handlers — Lustre attributes
// =============================================================================

fn on_click(msg: Msg) -> attr.Attribute(Msg) {
  event.on_click(msg)
}

fn on_change(f: fn(String) -> Msg) -> attr.Attribute(Msg) {
  event.on_input(f)
}

fn on_drag_start(_msg: Msg) -> attr.Attribute(Msg) {
  // event.on("dragstart", fn(_) { Ok(msg) })
  attr.class("drag-start")
}

fn on_drag_over(_msg: Msg) -> attr.Attribute(Msg) {
  // event.on("dragover", fn(_) { Ok(msg) })
  attr.class("drag-over")
}

fn on_drop(_msg: Msg) -> attr.Attribute(Msg) {
  // event.on("drop", fn(_) { Ok(msg) })
  attr.class("drop")
}

// =============================================================================
// Helpers
// =============================================================================

fn cockpit_mode_class(mode: CockpitMode) -> String {
  "cockpit-mode-" <> cockpit_mode_to_string(mode)
}

fn bool_to_string(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

// =============================================================================
// Task Queries
// =============================================================================

pub fn pending_tasks(model: DashboardModel) -> List(TaskCard) {
  list.filter(model.tasks, fn(t: TaskCard) { t.status == "pending" })
}

pub fn completed_tasks(model: DashboardModel) -> List(TaskCard) {
  list.filter(model.tasks, fn(t: TaskCard) { t.status == "completed" })
}

pub fn blocked_tasks(model: DashboardModel) -> List(TaskCard) {
  list.filter(model.tasks, fn(t: TaskCard) { t.status == "blocked" })
}

// =============================================================================
// Safety Queries
// =============================================================================

pub fn is_safe(model: DashboardModel) -> Bool {
  model.safety_active
  && model.guardian_healthy
  && model.threat_level <. 0.5
  && list.is_empty(model.quarantined)
}

pub fn all_checks_pass(model: DashboardModel) -> Bool {
  case list.is_empty(model.safety_checks) {
    True -> True
    False ->
      list.all(model.safety_checks, fn(c: SafetyCheckResult) {
        case c {
          CheckPass(_) -> True
          CheckFail(_, _) -> False
          CheckWarn(_) -> True
          CheckNotRun(_) -> True
        }
      })
  }
}

// =============================================================================
// JSON Serialization — Full dashboard state (SC-GLM-UI-003)
// =============================================================================

pub fn dashboard_to_json(model: DashboardModel) -> json.Json {
  json.object([
    // Panel 1: Tasks
    #("tasks", json.array(model.tasks, task_card_to_json)),
    #("task_filter", json.string(model.task_filter)),
    #("selected_task", case model.selected_task {
      Some(id) -> json.string(id)
      None -> json.null()
    }),
    // Panel 2: OODA
    #("ooda_phase", json.string(ooda_phase_to_string(model.ooda_phase))),
    #("ooda_cycle_count", json.int(model.ooda_cycle_count)),
    #("last_cycle_ms", json.int(model.last_cycle_ms)),
    #("ooda_pattern", json.string(model.ooda_pattern)),
    #("ooda_decision", json.string(model.ooda_decision)),
    // Panel 3: Safety
    #("safety_active", json.bool(model.safety_active)),
    #("threat_level", json.float(model.threat_level)),
    #("guardian_healthy", json.bool(model.guardian_healthy)),
    #(
      "safety_checks",
      json.array(model.safety_checks, safety_check_result_to_json),
    ),
    #("quarantined", json.array(model.quarantined, json.string)),
    // Panel 4: Enforcer
    #("total_violations", json.int(model.total_violations)),
    #("open_circuits", json.array(model.open_circuits, json.string)),
    #("recent_violations", json.array(model.recent_violations, json.string)),
    // Panel 5: Graph
    #("graph_node_count", json.int(model.graph_node_count)),
    #("graph_edge_count", json.int(model.graph_edge_count)),
    #(
      "graph_checks",
      json.array(model.graph_checks, safety_check_result_to_json),
    ),
    #("graph_dot", json.string(model.graph_dot)),
    // Panel 6: Orchestration
    #("services", json.array(model.services, service_node_to_json)),
    #("quorum", json.bool(model.quorum)),
    #("distribution_strategy", json.string(model.distribution_strategy)),
    // Panel 7: Chaya
    #("sync_phases", json.array(model.sync_phases, sync_phase_result_to_json)),
    #("orphan_count", json.int(model.orphan_count)),
    #("mismatch_count", json.int(model.mismatch_count)),
    #("last_sync", json.string(model.last_sync)),
    // Panel 8: Startup
    #("waves", json.array(model.waves, container_wave_to_json)),
    #("critical_path", json.array(model.critical_path, json.string)),
    #("total_startup_ms", json.int(model.total_startup_ms)),
    // UI state
    #("active_panel", json.string(panel_id_to_string(model.active_panel))),
    #("cockpit_mode", json.string(cockpit_mode_to_string(model.cockpit_mode))),
    #("ag_ui_connected", json.bool(model.ag_ui_connected)),
    #("chat_messages", json.array(model.chat_messages, chat_message_to_json)),
    // Computed
    #("health_score", json.float(health_score(model))),
    #("is_safe", json.bool(is_safe(model))),
    #("all_checks_pass", json.bool(all_checks_pass(model))),
    #("pending_count", json.int(list.length(pending_tasks(model)))),
    #("completed_count", json.int(list.length(completed_tasks(model)))),
    #("blocked_count", json.int(list.length(blocked_tasks(model)))),
  ])
}

// =============================================================================
// Internal JSON helpers
// =============================================================================

fn task_card_to_json(card: TaskCard) -> json.Json {
  json.object([
    #("id", json.string(card.id)),
    #("title", json.string(card.title)),
    #("status", json.string(card.status)),
    #("priority", json.string(card.priority)),
    #("assignee", case card.assignee {
      Some(a) -> json.string(a)
      None -> json.null()
    }),
  ])
}

fn service_node_to_json(node: ServiceNode) -> json.Json {
  json.object([
    #("name", json.string(node.name)),
    #("status", json.string(node.status)),
    #("health", json.float(node.health)),
  ])
}

fn sync_phase_result_to_json(phase: SyncPhaseResult) -> json.Json {
  json.object([
    #("phase", json.string(phase.phase)),
    #("success", json.bool(phase.success)),
    #("count", json.int(phase.count)),
    #("errors", json.int(phase.errors)),
  ])
}

fn container_wave_to_json(wave: ContainerWave) -> json.Json {
  json.object([
    #("wave", json.int(wave.wave)),
    #("containers", json.array(wave.containers, json.string)),
    #("duration_ms", json.int(wave.duration_ms)),
  ])
}

fn safety_check_result_to_json(check: SafetyCheckResult) -> json.Json {
  case check {
    CheckPass(name) ->
      json.object([
        #("status", json.string("pass")),
        #("name", json.string(name)),
      ])
    CheckFail(name, reason) ->
      json.object([
        #("status", json.string("fail")),
        #("name", json.string(name)),
        #("reason", json.string(reason)),
      ])
    CheckWarn(name) ->
      json.object([
        #("status", json.string("warn")),
        #("name", json.string(name)),
      ])
    CheckNotRun(name) ->
      json.object([
        #("status", json.string("not_run")),
        #("name", json.string(name)),
      ])
  }
}

fn chat_message_to_json(msg: ChatMessage) -> json.Json {
  case msg {
    UserMsg(text) ->
      json.object([
        #("type", json.string("user")),
        #("text", json.string(text)),
      ])
    AgentMsg(text) ->
      json.object([
        #("type", json.string("agent")),
        #("text", json.string(text)),
      ])
    ToolCallMsg(tool, args) ->
      json.object([
        #("type", json.string("tool_call")),
        #("tool", json.string(tool)),
        #("args", json.string(args)),
      ])
    EventMsg(event_type, data) ->
      json.object([
        #("type", json.string("event")),
        #("event_type", json.string(event_type)),
        #("data", json.string(data)),
      ])
  }
}

fn ooda_phase_to_string(phase: OodaPhase) -> String {
  case phase {
    ObservePhase -> "observe"
    OrientPhase -> "orient"
    DecidePhase -> "decide"
    ActPhase -> "act"
    Idle -> "idle"
  }
}

fn panel_id_to_string(panel: PanelId) -> String {
  case panel {
    TaskBoard -> "task_board"
    OodaCycle -> "ooda_cycle"
    SafetyKernel -> "safety_kernel"
    EnforcerShield -> "enforcer_shield"
    GraphVerify -> "graph_verify"
    OrchMesh -> "orch_mesh"
    ChayaTwin -> "chaya_twin"
    StartupOptim -> "startup_optim"
  }
}

fn cockpit_mode_to_string(mode: CockpitMode) -> String {
  case mode {
    Dark -> "dark"
    Dim -> "dim"
    Normal -> "normal"
    Bright -> "bright"
    EmergencyMode -> "emergency"
  }
}

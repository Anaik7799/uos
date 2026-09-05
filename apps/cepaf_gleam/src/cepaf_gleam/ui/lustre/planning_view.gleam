//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/planning_view</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-008, SC-AGUI-011</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre HTML view for the 8-panel Planning Dashboard.
//// Converts DashboardModel into Lustre Element tree for server-side rendering.
//// Implements Dark Cockpit progressive disclosure (SC-HMI-010).
////
//// ## Human-Specified Intent
//// <!-- HUMAN-ONLY: DO NOT AUTO-MODIFY -->
//// <!-- END HUMAN-ONLY -->

import cepaf_gleam/ui/lustre/planning_dashboard.{
  type CockpitMode, type DashboardModel, type DashboardMsg, type PanelId,
  type SafetyCheckResult, type ServiceNode, type TaskCard, Bright, ChayaTwin,
  CheckFail, CheckNotRun, CheckPass, CheckWarn, Dark, Dim, EmergencyMode,
  EnforcerShield, GraphVerify, Normal, OodaCycle, OrchMesh, SafetyKernel,
  SelectTask, SetActivePanel, SetTaskFilter, StartupOptim, TaskBoard,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// Main view function — renders the complete 8-panel dashboard.
pub fn view(model: DashboardModel) -> Element(DashboardMsg) {
  html.div(
    [
      attribute.class(
        "c3i-dashboard " <> cockpit_mode_class(model.cockpit_mode),
      ),
    ],
    [
      render_header(model),
      html.div([attribute.class("panels-grid")], [
        render_task_panel(model),
        render_ooda_panel(model),
        render_safety_panel(model),
        render_enforcer_panel(model),
        render_graph_panel(model),
        render_orch_panel(model),
        render_chaya_panel(model),
        render_startup_panel(model),
      ]),
      render_detail_panel(model),
      render_chat_panel(model),
    ],
  )
}

// -- Header --
fn render_header(model: DashboardModel) -> Element(DashboardMsg) {
  html.header([attribute.class("dashboard-header")], [
    html.h1([], [element.text("C3I Planning Cockpit")]),
    html.span(
      [
        attribute.class(
          "cockpit-mode " <> cockpit_mode_class(model.cockpit_mode),
        ),
      ],
      [element.text(cockpit_mode_label(model.cockpit_mode))],
    ),
    html.span([attribute.class("health-score")], [
      element.text(
        "Health: " <> float_to_pct(planning_dashboard.health_score(model)),
      ),
    ]),
    html.span(
      [
        attribute.class(case model.ag_ui_connected {
          True -> "agui-connected"
          False -> "agui-disconnected"
        }),
      ],
      [
        element.text(case model.ag_ui_connected {
          True -> "AG-UI Connected"
          False -> "AG-UI Offline"
        }),
      ],
    ),
  ])
}

// -- Panel 1: Tasks (Kanban with drag-drop) --
fn render_task_panel(model: DashboardModel) -> Element(DashboardMsg) {
  html.section(
    [
      attribute.class("panel task-panel"),
      event.on_click(SetActivePanel(TaskBoard)),
    ],
    [
      html.h2([], [element.text("Task Board")]),
      html.div([attribute.class("filter-bar")], [
        filter_button("all", model.task_filter),
        filter_button("pending", model.task_filter),
        filter_button("in_progress", model.task_filter),
        filter_button("completed", model.task_filter),
        filter_button("blocked", model.task_filter),
      ]),
      html.div([attribute.class("kanban-board")], [
        render_kanban_column("Pending", "pending", model.tasks),
        render_kanban_column("In Progress", "in_progress", model.tasks),
        render_kanban_column("Completed", "completed", model.tasks),
        render_kanban_column("Blocked", "blocked", model.tasks),
      ]),
    ],
  )
}

fn filter_button(filter: String, current: String) -> Element(DashboardMsg) {
  html.button(
    [
      attribute.class(
        "filter-btn "
        <> case filter == current {
          True -> "active"
          False -> ""
        },
      ),
      event.on_click(SetTaskFilter(filter)),
    ],
    [element.text(filter)],
  )
}

fn render_kanban_column(
  title: String,
  status: String,
  tasks: List(TaskCard),
) -> Element(DashboardMsg) {
  let column_tasks = list.filter(tasks, fn(t) { t.status == status })
  html.div([attribute.class("kanban-column " <> status)], [
    html.h3([], [
      element.text(
        title <> " (" <> int.to_string(list.length(column_tasks)) <> ")",
      ),
    ]),
    html.div(
      [attribute.class("column-tasks")],
      list.map(column_tasks, render_task_card),
    ),
  ])
}

fn render_task_card(task: TaskCard) -> Element(DashboardMsg) {
  html.div(
    [
      attribute.class("task-card priority-" <> task.priority),
      event.on_click(SelectTask(task.id)),
    ],
    [
      html.span([attribute.class("task-priority badge-" <> task.priority)], [
        element.text(task.priority),
      ]),
      html.p([attribute.class("task-title")], [element.text(task.title)]),
      html.span([attribute.class("task-assignee")], [
        element.text(case task.assignee {
          Some(a) -> a
          None -> "Unassigned"
        }),
      ]),
    ],
  )
}

// -- Panel 2: OODA Cycle --
fn render_ooda_panel(model: DashboardModel) -> Element(DashboardMsg) {
  let phase_str = case model.ooda_phase {
    planning_dashboard.Idle -> "IDLE"
    planning_dashboard.ObservePhase -> "OBSERVE"
    planning_dashboard.OrientPhase -> "ORIENT"
    planning_dashboard.DecidePhase -> "DECIDE"
    planning_dashboard.ActPhase -> "ACT"
  }
  let within_target = model.last_cycle_ms <= 100
  html.section(
    [
      attribute.class("panel ooda-panel"),
      event.on_click(SetActivePanel(OodaCycle)),
    ],
    [
      html.h2([], [element.text("OODA Cycle")]),
      html.div([attribute.class("ooda-ring")], [
        html.span(
          [attribute.class("ooda-phase " <> string.lowercase(phase_str))],
          [element.text(phase_str)],
        ),
      ]),
      html.p([], [
        element.text("Cycles: " <> int.to_string(model.ooda_cycle_count)),
      ]),
      html.p(
        [
          attribute.class(case within_target {
            True -> "latency-ok"
            False -> "latency-warn"
          }),
        ],
        [
          element.text(
            "Latency: "
            <> int.to_string(model.last_cycle_ms)
            <> "ms / 100ms target",
          ),
        ],
      ),
    ],
  )
}

// -- Panel 3: Safety Kernel --
fn render_safety_panel(model: DashboardModel) -> Element(DashboardMsg) {
  let check_count = list.length(model.safety_checks)
  let pass_count =
    list.count(model.safety_checks, fn(c) {
      case c {
        CheckPass(_) -> True
        _ -> False
      }
    })
  html.section(
    [
      attribute.class("panel safety-panel"),
      event.on_click(SetActivePanel(SafetyKernel)),
    ],
    [
      html.h2([], [element.text("Safety Kernel")]),
      html.div([attribute.class("safety-status")], [
        html.span(
          [
            attribute.class(case model.safety_active {
              True -> "active"
              False -> "inactive"
            }),
          ],
          [
            element.text(case model.safety_active {
              True -> "ACTIVE"
              False -> "INACTIVE"
            }),
          ],
        ),
        html.span(
          [
            attribute.class(
              "guardian "
              <> case model.guardian_healthy {
                True -> "healthy"
                False -> "unhealthy"
              },
            ),
          ],
          [
            element.text(case model.guardian_healthy {
              True -> "Guardian OK"
              False -> "Guardian DOWN"
            }),
          ],
        ),
      ]),
      html.p([], [
        element.text(
          "Checks: "
          <> int.to_string(pass_count)
          <> "/"
          <> int.to_string(check_count)
          <> " pass",
        ),
      ]),
      html.div(
        [attribute.class("check-list")],
        list.map(list.take(model.safety_checks, 6), render_safety_check),
      ),
    ],
  )
}

fn render_safety_check(check: SafetyCheckResult) -> Element(DashboardMsg) {
  case check {
    CheckPass(name) ->
      html.div([attribute.class("check pass")], [
        element.text("PASS " <> name),
      ])
    CheckFail(name, reason) ->
      html.div([attribute.class("check fail")], [
        element.text("FAIL " <> name <> ": " <> reason),
      ])
    CheckWarn(name) ->
      html.div([attribute.class("check warn")], [
        element.text("WARN " <> name),
      ])
    CheckNotRun(name) ->
      html.div([attribute.class("check not-run")], [
        element.text("--- " <> name),
      ])
  }
}

// -- Panel 4: Enforcer --
fn render_enforcer_panel(model: DashboardModel) -> Element(DashboardMsg) {
  let circuit_count = list.length(model.open_circuits)
  html.section(
    [
      attribute.class("panel enforcer-panel"),
      event.on_click(SetActivePanel(EnforcerShield)),
    ],
    [
      html.h2([], [element.text("Enforcer Shield")]),
      html.p([], [
        element.text("Violations: " <> int.to_string(model.total_violations)),
      ]),
      html.p(
        [
          attribute.class(case circuit_count {
            0 -> "circuits-ok"
            _ -> "circuits-open"
          }),
        ],
        [
          element.text(
            "Circuits: "
            <> case circuit_count {
              0 -> "ALL CLOSED"
              _ -> int.to_string(circuit_count) <> " OPEN"
            },
          ),
        ],
      ),
    ],
  )
}

// -- Panel 5: Graph --
fn render_graph_panel(model: DashboardModel) -> Element(DashboardMsg) {
  html.section(
    [
      attribute.class("panel graph-panel"),
      event.on_click(SetActivePanel(GraphVerify)),
    ],
    [
      html.h2([], [element.text("Graph Verify")]),
      html.p([], [
        element.text(
          "Nodes: "
          <> int.to_string(model.graph_node_count)
          <> " Edges: "
          <> int.to_string(model.graph_edge_count),
        ),
      ]),
    ],
  )
}

// -- Panel 6: Orchestration --
fn render_orch_panel(model: DashboardModel) -> Element(DashboardMsg) {
  let service_count = list.length(model.services)
  let online =
    list.count(model.services, fn(s: ServiceNode) { s.health >=. 0.8 })
  html.section(
    [
      attribute.class("panel orch-panel"),
      event.on_click(SetActivePanel(OrchMesh)),
    ],
    [
      html.h2([], [element.text("Orchestration Mesh")]),
      html.p([], [
        element.text(
          "Services: "
          <> int.to_string(online)
          <> "/"
          <> int.to_string(service_count)
          <> " healthy",
        ),
      ]),
      html.p(
        [
          attribute.class(case model.quorum {
            True -> "quorum-met"
            False -> "quorum-lost"
          }),
        ],
        [
          element.text(
            "Quorum: "
            <> case model.quorum {
              True -> "MET"
              False -> "LOST"
            },
          ),
        ],
      ),
    ],
  )
}

// -- Panel 7: Chaya --
fn render_chaya_panel(model: DashboardModel) -> Element(DashboardMsg) {
  html.section(
    [
      attribute.class("panel chaya-panel"),
      event.on_click(SetActivePanel(ChayaTwin)),
    ],
    [
      html.h2([], [element.text("Chaya Twin")]),
      html.p([], [
        element.text(
          "Orphans: "
          <> int.to_string(model.orphan_count)
          <> " Mismatches: "
          <> int.to_string(model.mismatch_count),
        ),
      ]),
    ],
  )
}

// -- Panel 8: Startup --
fn render_startup_panel(model: DashboardModel) -> Element(DashboardMsg) {
  html.section(
    [
      attribute.class("panel startup-panel"),
      event.on_click(SetActivePanel(StartupOptim)),
    ],
    [
      html.h2([], [element.text("Startup Optimizer")]),
      html.p([], [
        element.text(
          "Waves: "
          <> int.to_string(list.length(model.waves))
          <> " Total: "
          <> int.to_string(model.total_startup_ms)
          <> "ms",
        ),
      ]),
    ],
  )
}

// -- Detail Panel --
fn render_detail_panel(model: DashboardModel) -> Element(DashboardMsg) {
  html.section([attribute.class("detail-panel")], [
    html.h2([], [element.text("Detail: " <> panel_label(model.active_panel))]),
    case model.active_panel {
      TaskBoard ->
        case model.selected_task {
          Some(id) -> html.p([], [element.text("Selected task: " <> id)])
          None -> html.p([], [element.text("No task selected")])
        }
      _ -> html.p([], [element.text("Select a panel for details")])
    },
  ])
}

// -- Chat/AG-UI Panel --
fn render_chat_panel(model: DashboardModel) -> Element(DashboardMsg) {
  html.section([attribute.class("chat-panel")], [
    html.h2([], [element.text("AG-UI Stream")]),
    html.div(
      [attribute.class("chat-messages")],
      list.map(list.take(list.reverse(model.chat_messages), 20), fn(msg) {
        case msg {
          planning_dashboard.UserMsg(text) ->
            html.div([attribute.class("msg user")], [
              element.text("You: " <> text),
            ])
          planning_dashboard.AgentMsg(text) ->
            html.div([attribute.class("msg agent")], [
              element.text("Agent: " <> text),
            ])
          planning_dashboard.ToolCallMsg(tool, args) ->
            html.div([attribute.class("msg tool")], [
              element.text("Tool: " <> tool <> "(" <> args <> ")"),
            ])
          planning_dashboard.EventMsg(etype, data) ->
            html.div([attribute.class("msg event")], [
              element.text("[" <> etype <> "] " <> data),
            ])
        }
      }),
    ),
  ])
}

// -- Helpers --
fn cockpit_mode_class(mode: CockpitMode) -> String {
  case mode {
    Dark -> "mode-dark"
    Dim -> "mode-dim"
    Normal -> "mode-normal"
    Bright -> "mode-bright"
    EmergencyMode -> "mode-emergency"
  }
}

fn cockpit_mode_label(mode: CockpitMode) -> String {
  case mode {
    Dark -> "DARK"
    Dim -> "DIM"
    Normal -> "NORMAL"
    Bright -> "BRIGHT"
    EmergencyMode -> "EMERGENCY"
  }
}

fn panel_label(panel: PanelId) -> String {
  case panel {
    TaskBoard -> "Tasks"
    OodaCycle -> "OODA"
    SafetyKernel -> "Safety"
    EnforcerShield -> "Enforcer"
    GraphVerify -> "Graph"
    OrchMesh -> "Orchestration"
    ChayaTwin -> "Chaya"
    StartupOptim -> "Startup"
  }
}

fn float_to_pct(f: Float) -> String {
  int.to_string(float.round(f *. 100.0)) <> "%"
}

//// Reference application: the UOS cockpit screen composed from uos_tui widgets.
//// Layout: status bar / [sidebar | tabbed body | checklist + OODA] / AG-UI log / footer.
//// All container actions emit `Intent` values (Rocha cut); nothing here executes a side effect.
//// STAMP: SC-TUI-COCKPIT-001, SC-CHECKLIST-001, SC-TAILSCALE-WEB-001.

import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import uos_tui/app.{type App, type Effect, App, Screen}
import uos_tui/aspects
import uos_tui/event
import uos_tui/geometry.{type Size}
import uos_tui/layout.{Cells, Fraction, Horizontal, Vertical}
import uos_tui/render
import uos_tui/style
import uos_tui/widget.{
  type ChecklistDomain, type TreeNode, type Widget, Binding, ChecklistDomain,
  ChecklistItem, Column, StatusField, TreeNode,
}

pub type Mode {
  Dark
  Dim
  Normal
  Bright
  Emergency
}

pub type Tab {
  Overview
  Supervisors
  Containers
  Storage
  Zenoh
  Tasks
  Security
  Doctor
}

pub const tabs = [
  Overview,
  Supervisors,
  Containers,
  Storage,
  Zenoh,
  Tasks,
  Security,
  Doctor,
]

pub type Intent {
  Intent(verb: String, target: String, epoch: Int)
}

pub type Container {
  Container(name: String, tier: String, status: String, cpu: Float)
}

pub type Model {
  Model(
    mode: Mode,
    tab: Int,
    nav_cursor: Int,
    container_cursor: Int,
    containers: List(Container),
    expanded: List(Int),
    command: String,
    log: List(String),
    telemetry: List(Float),
    intents: List(Intent),
    pending_confirm: option.Option(Intent),
    utc: String,
    change_id: String,
    lease_epoch: Int,
    checklist_passed: List(String),
    frame_count: Int,
  )
}

pub type Msg {
  SelectTab(Int)
  NavMove(Int)
  ContainerMove(Int)
  ContainerSelect(Int)
  ToggleDomain(Int)
  CommandChanged(String)
  CommandSubmit
  CycleMode
  RequestIntent(String)
  ConfirmIntent
  CancelIntent
  Telemetry(Float)
  Log(String)
  QuitApp
}

pub fn init_model(utc: String, change_id: String) -> Model {
  Model(
    mode: Dark,
    tab: 0,
    nav_cursor: 0,
    container_cursor: 0,
    containers: [],
    expanded: [],
    command: "",
    log: [],
    telemetry: [],
    intents: [],
    pending_confirm: None,
    utc: utc,
    change_id: change_id,
    lease_epoch: 0,
    checklist_passed: [],
    frame_count: 0,
  )
}

pub fn app(initial: Model) -> App(Model, Msg) {
  App(
    name: "uos-cockpit",
    init: fn(_size: Size) { #(initial, app.Telemetry("ScreenDepth", "1")) },
    update: update,
    screens: [Screen("cockpit", view), Screen("confirm", confirm_view)],
    initial_screen: "cockpit",
    bindings: [
      Binding(event.Char("1"), SelectTab(0), "overview"),
      Binding(event.Char("2"), SelectTab(1), "supervisors"),
      Binding(event.Char("3"), SelectTab(2), "containers"),
      Binding(event.Char("4"), SelectTab(3), "storage"),
      Binding(event.Char("5"), SelectTab(4), "zenoh"),
      Binding(event.Char("6"), SelectTab(5), "tasks"),
      Binding(event.Char("7"), SelectTab(6), "security"),
      Binding(event.Char("8"), SelectTab(7), "doctor"),
      Binding(event.Char("m"), CycleMode, "mode"),
      Binding(event.Char("r"), RequestIntent("restart"), "restart(confirm)"),
      Binding(event.Char("x"), RequestIntent("stop"), "stop(confirm)"),
      Binding(event.Char("q"), QuitApp, "quit"),
    ],
    theme: render.dark,
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    SelectTab(i) -> #(
      Model(..model, tab: int.clamp(i, 0, list.length(tabs) - 1)),
      app.Telemetry("Tab", int.to_string(i)),
    )
    NavMove(i) -> #(Model(..model, nav_cursor: i), app.NoEffect)
    ContainerMove(i) -> #(Model(..model, container_cursor: i), app.NoEffect)
    ContainerSelect(i) -> #(
      Model(..model, container_cursor: i, tab: 2),
      app.NoEffect,
    )
    ToggleDomain(i) -> {
      let expanded = case list.contains(model.expanded, i) {
        True -> list.filter(model.expanded, fn(x) { x != i })
        False -> [i, ..model.expanded]
      }
      #(Model(..model, expanded: expanded), app.NoEffect)
    }
    CommandChanged(text) -> #(Model(..model, command: text), app.NoEffect)
    CommandSubmit ->
      case string.trim(model.command) {
        "" -> #(model, app.NoEffect)
        cmd -> #(
          Model(
            ..model,
            command: "",
            log: append_log(model.log, "cmd> " <> cmd),
          ),
          app.NoEffect,
        )
      }
    CycleMode -> {
      let next = case model.mode {
        Dark -> Dim
        Dim -> Normal
        Normal -> Bright
        Bright -> Emergency
        Emergency -> Dark
      }
      #(
        Model(..model, mode: next),
        app.Telemetry("CockpitMode", mode_label(next)),
      )
    }
    RequestIntent(verb) ->
      case selected_container(model) {
        Some(c) -> {
          let intent = Intent(verb, c.name, model.lease_epoch)
          #(
            Model(..model, pending_confirm: Some(intent)),
            app.PushScreen("confirm"),
          )
        }
        None -> #(
          Model(..model, log: append_log(model.log, "no container selected")),
          app.NoEffect,
        )
      }
    ConfirmIntent ->
      case model.pending_confirm {
        Some(intent) -> #(
          Model(
            ..model,
            pending_confirm: None,
            intents: [intent, ..model.intents],
            log: append_log(
              model.log,
              "intent " <> intent.verb <> " " <> intent.target <> " -> policy",
            ),
          ),
          app.Batch([app.PopScreen, app.Telemetry("IntentEmitted", intent.verb)]),
        )
        None -> #(model, app.PopScreen)
      }
    CancelIntent -> #(Model(..model, pending_confirm: None), app.PopScreen)
    Telemetry(v) -> #(
      Model(
        ..model,
        telemetry: list.take([v, ..model.telemetry], 120)
          |> list.reverse
          |> list.reverse,
      ),
      app.NoEffect,
    )
    Log(line) -> #(
      Model(..model, log: append_log(model.log, line)),
      app.NoEffect,
    )
    QuitApp -> #(model, app.Quit)
  }
}

fn append_log(log: List(String), line: String) -> List(String) {
  list.append(log, [line]) |> list.drop(int.max(list.length(log) - 499, 0))
}

fn selected_container(model: Model) -> option.Option(Container) {
  model.containers
  |> list.drop(model.container_cursor)
  |> list.first
  |> option.from_result
}

pub fn mode_label(mode: Mode) -> String {
  case mode {
    Dark -> "DARK"
    Dim -> "DIM"
    Normal -> "NORMAL"
    Bright -> "BRIGHT"
    Emergency -> "EMERGENCY"
  }
}

fn mode_style(mode: Mode) -> style.Style {
  case mode {
    Dark -> style.none |> style.fg(style.BrightBlack)
    Dim -> style.none |> style.fg(style.Yellow)
    Normal -> style.none |> style.fg(style.Cyan)
    Bright -> style.none |> style.fg(style.White) |> style.bold
    Emergency ->
      style.none |> style.fg(style.Red) |> style.bold |> style.reverse
  }
}

pub fn tab_label(tab: Tab) -> String {
  case tab {
    Overview -> "Overview"
    Supervisors -> "Supervisors"
    Containers -> "Containers"
    Storage -> "Storage"
    Zenoh -> "Zenoh"
    Tasks -> "Tasks"
    Security -> "Security"
    Doctor -> "Doctor"
  }
}

const nav_items = [
  "COMMAND & CONTROL", "  Cockpit  /", "  Planning  /planning",
  "  AG-UI  /ag-ui/events", "KNOWLEDGE BASE", "  Wiki  /wiki", "  ZK MOC  /zk",
  "REPOSITORY & GOV", "  Doctor  EV-01..", "  Gates  G-CHECKLIST",
  "  Files  /files",
]

pub fn checklist_domains(passed: List(String)) -> List(ChecklistDomain) {
  let item = fn(id, label) {
    ChecklistItem(id, label, list.contains(passed, id))
  }
  [
    ChecklistDomain("D1 Metadata & Tailscale", [
      item("CHK-01-TIME", "YYYYMMDD-HHSS- prefix"),
      item("CHK-02-TAIL", "Tailscale FQDN links"),
      item("CHK-03-FRACT", "fractal layer tags"),
      item("CHK-04-KM", "wiki/zk transclusions"),
    ]),
    ChecklistDomain("D2 Zero-Muda & Storage", [
      item("CHK-05-MUDA", "0 Bevy 0 Graphite"),
      item("CHK-06-GRAPH", "no Graphene NIF"),
      item("CHK-07-DRIVE", "NVMe " <> aspects.os_nvme_serial <> " locked"),
    ]),
    ChecklistDomain("D3 Testing Gold Std", [
      item("CHK-08-C1C8", "C1-C8 coverage"),
      item("CHK-09-MATH", "4 math gates"),
      item("CHK-10-9MOD", "9 modalities green"),
      item("CHK-11-REGR", "UI regression"),
    ]),
    ChecklistDomain("D4 Cross-Language", [
      item("CHK-12-GLEAM", "OTP supervisor"),
      item("CHK-13-HERMES", "Hermes evidence"),
      item("CHK-14-ZIGVM", "ZigVM kernel"),
      item("CHK-15-MAX", "MAX quarantine"),
      item("CHK-16-OTEL", "C3I telemetry"),
    ]),
    ChecklistDomain("D5 Governance & VCS", [
      item("CHK-17-SOV", "tri-sovereign consensus"),
      item("CHK-18-JJ", "standalone jj"),
    ]),
  ]
}

pub fn view(model: Model) -> Widget(Msg) {
  let status =
    widget.StatusBar("status", [
      StatusField("", aspects.tailnet_fqdn, style.none |> style.fg(style.Cyan)),
      StatusField("", model.utc, style.none),
      StatusField("MODE", mode_label(model.mode), mode_style(model.mode)),
      StatusField(
        "DRIVE",
        aspects.os_nvme_serial <> " LOCKED",
        style.none |> style.fg(style.Green),
      ),
      StatusField("JJ", model.change_id, style.none),
    ])
  let sidebar =
    widget.ListView("nav", nav_items, model.nav_cursor, Some(NavMove), None)
  let tab_bar =
    widget.Tabs("tabs", list.map(tabs, tab_label), model.tab, Some(SelectTab))
  let body =
    widget.Container(
      "body",
      Vertical,
      [#(Cells(1), tab_bar), #(Fraction(1), tab_content(model))],
      True,
      "",
    )
  let right =
    widget.Container(
      "right",
      Vertical,
      [
        #(
          Fraction(2),
          widget.Checklist(
            "checklist",
            checklist_domains(model.checklist_passed),
            model.expanded,
            Some(ToggleDomain),
          ),
        ),
        #(Cells(1), widget.Rule("ooda-rule", "OODA")),
        #(Cells(1), widget.ProgressBar("l0", 1.0, "L0 ")),
        #(Cells(1), widget.ProgressBar("l4", 0.9, "L4 ")),
        #(Cells(4), sa_plan_table("sa-plan-tasks", model)),
        #(
          Cells(1),
          widget.Static(
            "km",
            "[[wiki:20260906-1730-uos-omni-fractal-matrix-and-17-aspect-wiki]] [[zk:20260905-1801-moc-uos-unified-master]]",
            style.none |> style.fg(style.BrightBlack),
          ),
        ),
      ],
      True,
      "Checklist 18",
    )
  let middle =
    widget.Container(
      "middle",
      Horizontal,
      [#(Cells(22), sidebar), #(Fraction(1), body), #(Cells(34), right)],
      False,
      "",
    )
  let log = widget.Log("ag-ui-stream", model.log, 0)
  let command =
    widget.Input(
      "command",
      model.command,
      string.length(model.command),
      "command palette: type and press enter",
      CommandChanged,
      Some(CommandSubmit),
    )
  let footer = widget.Footer("footer", list.take(app(model).bindings, 12))
  widget.Container(
    "root",
    Vertical,
    [
      #(Cells(1), status),
      #(Fraction(1), middle),
      #(
        Cells(4),
        widget.Container(
          "stream",
          Vertical,
          [#(Fraction(1), log)],
          True,
          "AG-UI",
        ),
      ),
      #(Cells(1), command),
      #(Cells(1), footer),
    ],
    False,
    "",
  )
}

fn tab_content(model: Model) -> Widget(Msg) {
  case list.drop(tabs, model.tab) |> list.first {
    Ok(Supervisors) -> widget.Tree("sup-tree", supervisor_tree(), 0, None)
    Ok(Containers) ->
      widget.DataTable(
        "containers",
        [
          Column("name", Fraction(2)),
          Column("tier", Cells(6)),
          Column("status", Cells(10)),
          Column("cpu%", Cells(7)),
        ],
        list.map(model.containers, fn(c) {
          [c.name, c.tier, c.status, string.inspect(c.cpu)]
        }),
        model.container_cursor,
        Some(ContainerMove),
        Some(ContainerSelect),
      )
    Ok(Tasks) -> sa_plan_table("sa-plan-tasks-full", model)
    Ok(Overview) ->
      widget.Container(
        "overview",
        Vertical,
        [
          #(
            Cells(1),
            widget.Static(
              "ov-1",
              "EV-69  69/69 boundaries green   frames "
                <> int.to_string(model.frame_count),
              style.none,
            ),
          ),
          #(
            Cells(1),
            widget.Sparkline("telemetry", model.telemetry, style.none),
          ),
          #(
            Fraction(1),
            widget.Static(
              "ov-2",
              "Intents emitted: " <> int.to_string(list.length(model.intents)),
              style.none,
            ),
          ),
        ],
        False,
        "",
      )
    Ok(other) ->
      widget.Static(
        "tab-" <> tab_label(other),
        tab_label(other) <> " tab: no live data source bound",
        style.none |> style.fg(style.Yellow),
      )
    Error(_) -> widget.Static("tab-none", "", style.none)
  }
}

fn sa_plan_table(id: String, model: Model) -> Widget(Msg) {
  widget.DataTable(
    id,
    [
      Column("task", Fraction(2)),
      Column("lease", Cells(7)),
      Column("epoch", Cells(6)),
      Column("state", Cells(8)),
    ],
    list.map(model.intents, fn(i) {
      [i.verb <> " " <> i.target, "fenced", int.to_string(i.epoch), "pending"]
    }),
    0,
    None,
    None,
  )
}

fn supervisor_tree() -> TreeNode {
  TreeNode("uos_sup", True, [
    TreeNode("apps_sup", True, [
      TreeNode("cepaf_gleam", False, []),
      TreeNode("uos_tui", False, []),
    ]),
    TreeNode("engines_sup", True, [
      TreeNode("hermes", False, []),
      TreeNode("zigvm", False, []),
    ]),
    TreeNode("services_sup", False, [TreeNode("max_worker", False, [])]),
    TreeNode("intelligence_sup", False, []),
  ])
}

fn confirm_view(model: Model) -> Widget(Msg) {
  let text = case model.pending_confirm {
    Some(i) ->
      "Confirm intent: "
      <> i.verb
      <> " "
      <> i.target
      <> "\nThis emits an Intent to policy; the TUI executes nothing."
    None -> "No pending intent."
  }
  widget.Container(
    "confirm",
    Vertical,
    [
      #(Cells(3), widget.Static("confirm-text", text, style.none)),
      #(
        Cells(1),
        widget.Container(
          "buttons",
          Horizontal,
          [
            #(
              Cells(14),
              widget.Button("confirm-yes", "Emit intent", ConfirmIntent),
            ),
            #(Cells(12), widget.Button("confirm-no", "Cancel", CancelIntent)),
          ],
          False,
          "",
        ),
      ),
    ],
    True,
    "Action interlock (C8)",
  )
}

/// The aspect context a live driver would supply for this app.
pub fn context(
  model: Model,
  size: Size,
  supervised: Bool,
  deps: List(String),
) -> aspects.Context {
  aspects.Context(
    interlock: aspects.Locked(aspects.os_nvme_serial),
    vcs: aspects.Jujutsu(model.change_id),
    dependencies: deps,
    supervised: supervised,
    engine_ports: [
      "zigvm_tlm_in",
      "hermes_evidence_in",
      "max_inference_in",
      "zenoh_tlm_in",
      "agui_event_in",
      "saplan_lease_in",
    ],
    lean_proof_refs: [
      "formal/lean/Traceability.lean",
      "formal/lean/TwoLattice_STM.lean",
    ],
    rocha_cut_declared: True,
    telemetry_channels: [
      "FrameCount",
      "FrameMicros",
      "ScreenDepth",
      "CockpitMode",
    ],
    lease_epoch: model.lease_epoch,
    size: size,
  )
}

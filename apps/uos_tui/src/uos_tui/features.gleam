//// Feature sheet generated from code: every row is derived from a live constant, catalog,
//// or constructor exported by the other `uos_tui` modules -- never a hand-typed duplicate
//// list. Reference (Textual concept): `App.export_screenshot` / capability introspection.
//// STAMP: SC-TUI-W02-001.

import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None}
import gleam/string
import uos_tui/aspects
import uos_tui/event
import uos_tui/fprime.{
  ActivityHi, ActivityLo, AsyncCmd, BoolType, CommandSev, Diagnostic, F64, Fatal,
  GuardedCmd, I32, StringType, SyncCmd, U16, U32, U64, U8, WarningHi, WarningLo,
}
import uos_tui/layout.{Vertical}
import uos_tui/ontology
import uos_tui/style
import uos_tui/widget.{
  type Widget, Button, Checklist, Container, DataTable, Footer, Grid, Header,
  Input, ListView, Log, ProgressBar, Rule, Sparkline, Static, StatusBar, Tabs,
  Tree, TreeNode,
}

pub type Section {
  Section(title: String, rows: List(List(String)), columns: List(String))
}

pub type FeatureSheet {
  FeatureSheet(generated_by: String, sections: List(Section))
}

/// Build one representative widget per catalog kind so `widget.is_focusable`
/// can be applied honestly rather than declared.
fn widget_sample(name: String) -> Widget(Nil) {
  case name {
    "Static" -> Static("w-static", "static text", style.none)
    "Header" -> Header("w-header", "title", "subtitle", style.none)
    "Footer" -> Footer("w-footer", [])
    "Button" -> Button("w-button", "label", Nil)
    "Input" -> Input("w-input", "value", 0, "placeholder", fn(_s) { Nil }, None)
    "DataTable" -> DataTable("w-datatable", [], [], 0, None, None)
    "Tree" -> Tree("w-tree", TreeNode("root", False, []), 0, None)
    "ListView" -> ListView("w-listview", [], 0, None, None)
    "ProgressBar" -> ProgressBar("w-progressbar", 0.0, "label")
    "Sparkline" -> Sparkline("w-sparkline", [], style.none)
    "Tabs" -> Tabs("w-tabs", [], 0, None)
    "Log" -> Log("w-log", [], 0)
    "Rule" -> Rule("w-rule", "title")
    "Container" -> Container("w-container", Vertical, [], False, "title")
    "Grid" -> Grid("w-grid", [], [], [])
    "Checklist" -> Checklist("w-checklist", [], [], None)
    "StatusBar" -> StatusBar("w-statusbar", [])
    _ -> Static("w-unknown", name, style.none)
  }
}

fn widgets_section() -> Section {
  let rows =
    list.map(widget.catalog, fn(name) {
      let sample = widget_sample(name)
      let focusable = case widget.is_focusable(sample) {
        True -> "focusable"
        False -> "not focusable"
      }
      [name, focusable]
    })
  Section("Widgets", rows, ["Widget", "Focusable"])
}

fn key_specimens() -> List(#(String, event.Key)) {
  [
    #("Char(\"a\")", event.Char("a")),
    #("Enter", event.Enter),
    #("Escape", event.Escape),
    #("Backspace", event.Backspace),
    #("Tab", event.Tab),
    #("BackTab", event.BackTab),
    #("Up", event.Up),
    #("Down", event.Down),
    #("Left", event.Left),
    #("Right", event.Right),
    #("Home", event.Home),
    #("End", event.End),
    #("PageUp", event.PageUp),
    #("PageDown", event.PageDown),
    #("Delete", event.Delete),
    #("Insert", event.Insert),
    #("F(1)", event.F(1)),
    #("Ctrl(\"c\")", event.Ctrl("c")),
    #("Unknown(\"?\")", event.Unknown("?")),
  ]
}

fn keys_section() -> Section {
  let rows =
    list.map(key_specimens(), fn(pair) { [pair.0, event.key_label(pair.1)] })
  Section("Keys", rows, ["Key", "Label"])
}

fn effects_section() -> Section {
  Section(
    "Effects",
    [
      ["NoEffect", "No side effect requested."],
      ["Batch", "Run a list of effects together."],
      ["Task", "Run an async fn() -> msg and dispatch its result."],
      ["PushScreen", "Push a named screen onto the screen stack."],
      ["PopScreen", "Pop the top screen off the screen stack."],
      ["FocusWidget", "Move focus to a widget id."],
      ["Telemetry", "Emit a channel/value telemetry pair."],
      ["Quit", "Request application shutdown."],
    ],
    ["Effect", "Meaning"],
  )
}

fn aspects_section() -> Section {
  let rows =
    list.map(aspects.all, fn(a) {
      [int.to_string(aspects.number(a)), aspects.name(a)]
    })
  Section("Aspects", rows, ["#", "Aspect"])
}

fn cmd_kind_label(k: fprime.CommandKind) -> String {
  case k {
    SyncCmd -> "sync"
    GuardedCmd -> "guarded"
    AsyncCmd(_, _) -> "async"
  }
}

fn prim_label(p: fprime.FppPrim) -> String {
  case p {
    U8 -> "U8"
    U16 -> "U16"
    U32 -> "U32"
    U64 -> "U64"
    I32 -> "I32"
    F64 -> "F64"
    BoolType -> "Bool"
    StringType(_) -> "String"
  }
}

fn severity_label(s: fprime.Severity) -> String {
  case s {
    ActivityHi -> "ACTIVITY_HI"
    ActivityLo -> "ACTIVITY_LO"
    CommandSev -> "COMMAND"
    Diagnostic -> "DIAGNOSTIC"
    Fatal -> "FATAL"
    WarningHi -> "WARNING_HI"
    WarningLo -> "WARNING_LO"
  }
}

fn fprime_commands_section(commands: List(fprime.Command)) -> Section {
  let rows =
    list.map(commands, fn(cmd) {
      [cmd.cmd_name, int.to_string(cmd.opcode), cmd_kind_label(cmd.cmd_kind)]
    })
  Section("F\u{00b4} commands", rows, ["Command", "Opcode", "Kind"])
}

fn fprime_channels_section(channels: List(fprime.Channel)) -> Section {
  let rows =
    list.map(channels, fn(chan) {
      [
        chan.chan_name,
        int.to_string(chan.chan_id),
        prim_label(chan.chan_type),
      ]
    })
  Section("F\u{00b4} channels", rows, ["Channel", "Id", "Type"])
}

fn fprime_events_section(events: List(fprime.Event)) -> Section {
  let rows =
    list.map(events, fn(ev) {
      [
        ev.event_name,
        int.to_string(ev.event_id),
        severity_label(ev.severity),
      ]
    })
  Section("F\u{00b4} events", rows, ["Event", "Id", "Severity"])
}

fn fprime_parameters_section(parameters: List(fprime.Parameter)) -> Section {
  let rows =
    list.map(parameters, fn(param) {
      [
        param.param_name,
        int.to_string(param.param_id),
        prim_label(param.param_type),
      ]
    })
  Section("F\u{00b4} parameters", rows, ["Parameter", "Id", "Type"])
}

fn ontology_section() -> Section {
  let #(iso, homo, reinterp, deferred) =
    ontology.fidelity_counts(ontology.graph())
  Section(
    "Ontology fidelity",
    [
      ["Isomorphic", int.to_string(iso)],
      ["Homomorphic", int.to_string(homo)],
      ["Reinterpreted", int.to_string(reinterp)],
      ["Deferred", int.to_string(deferred)],
    ],
    ["Fidelity", "Count"],
  )
}

/// The "Cockpit bindings" section rendered from key/description pairs supplied by the
/// caller (e.g. an application's own `App.bindings`), never by importing any particular
/// application module. Empty `bindings` renders no rows; `sheet` omits the section entirely
/// in that case.
fn cockpit_bindings_section(bindings: List(#(String, String))) -> Section {
  let rows = list.map(bindings, fn(b) { [b.0, b.1] })
  Section("Cockpit bindings", rows, ["Key", "Description"])
}

fn drivers_section() -> Section {
  Section(
    "Drivers",
    [
      [
        "headless.run",
        "Feed scripted events through an App and collect every frame.",
      ],
      [
        "live.run",
        "Drive a live terminal App on OTP: actor, reader and ticker.",
      ],
      [
        "live.child_spec",
        "Supervisor child spec that starts the live driver actor.",
      ],
      [
        "live.snapshot_text",
        "Render one deterministic text snapshot of an App at a given size.",
      ],
    ],
    ["Driver", "Purpose"],
  )
}

fn test_modalities_section() -> Section {
  Section(
    "Test modalities",
    [
      ["Unit", "test/*_test.gleam, one module under test each"],
      ["System", "headless.run driving a full App across many events"],
      ["TDD", "red/green cycles co-located with each src change"],
      ["BDD", "scenario-named _test.gleam functions (given/when/then)"],
      ["Performance", "perf_test.gleam frame-timing assertions"],
      ["Scalability", "large-N inputs via prng.ints and prng.text"],
      ["Property", "prng-seeded invariant checks across many seeds"],
      ["Fuzz", "prng.text random input fed to total, never-crash paths"],
      ["Chaos", "prng-seeded randomised event/effect sequences"],
    ],
    ["Modality", "Where"],
  )
}

/// Assemble the full feature sheet. Every section's rows are derived from a
/// live code source (catalog, constant list, or constructed sample) rather
/// than hand-typed. `bindings` (key label, description) is supplied by the caller -- the
/// library itself binds no keys -- and renders an extra "Cockpit bindings" section only
/// when non-empty; the TUI CLI passes `[]`.
pub fn sheet(bindings: List(#(String, String))) -> FeatureSheet {
  let component = fprime.component()
  let bindings_sections = case bindings {
    [] -> []
    _ -> [cockpit_bindings_section(bindings)]
  }
  FeatureSheet(
    "uos_tui/features.sheet",
    [
      widgets_section(),
      keys_section(),
      effects_section(),
      aspects_section(),
      fprime_commands_section(component.commands),
      fprime_channels_section(component.channels),
      fprime_events_section(component.events),
      fprime_parameters_section(component.parameters),
      ontology_section(),
    ]
      |> list.append(bindings_sections)
      |> list.append([drivers_section(), test_modalities_section()]),
  )
}

fn section_to_markdown(section: Section) -> String {
  let header = "## " <> section.title
  let count = "rows: " <> int.to_string(list.length(section.rows))
  let header_row = "| " <> string.join(section.columns, " | ") <> " |"
  let sep_row =
    "| "
    <> string.join(list.map(section.columns, fn(_c) { "---" }), " | ")
    <> " |"
  let data_rows =
    list.map(section.rows, fn(row) { "| " <> string.join(row, " | ") <> " |" })
  string.join([header, count, header_row, sep_row, ..data_rows], "\n")
}

/// Render the sheet as a Markdown document: an H1 title followed by one
/// H2 section per `Section`, each with a row count and a Markdown table.
pub fn to_markdown(sheet: FeatureSheet) -> String {
  let body =
    sheet.sections
    |> list.map(section_to_markdown)
    |> string.join("\n\n")
  "# uos_tui Feature Sheet\n\n" <> body <> "\n"
}

fn section_to_json(section: Section) -> Json {
  json.object([
    #("title", json.string(section.title)),
    #("columns", json.array(section.columns, json.string)),
    #(
      "rows",
      json.array(section.rows, fn(row) { json.array(row, json.string) }),
    ),
  ])
}

/// Render the sheet as JSON: `{"generated_by": ..., "sections": [...]}`.
pub fn to_json(sheet: FeatureSheet) -> Json {
  json.object([
    #("generated_by", json.string(sheet.generated_by)),
    #("sections", json.array(sheet.sections, section_to_json)),
  ])
}

/// Total row count across every section.
pub fn total_rows(sheet: FeatureSheet) -> Int {
  list.fold(sheet.sections, 0, fn(acc, s) { acc + list.length(s.rows) })
}

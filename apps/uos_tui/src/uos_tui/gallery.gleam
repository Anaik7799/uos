//// Reference "gallery" application: mounts one of each uos_tui widget family (header/status
//// bar, checklist, data table, log) plus the markdown, diff, and palette modules, so
//// `snapshot` and the live driver show something real without importing any swarm/cockpit
//// module. Every action emits a pure `Msg`; nothing here executes a side effect.
//// STAMP: SC-TUI-GALLERY-001.

import gleam/int
import gleam/list
import gleam/option
import uos_tui/app
import uos_tui/aspects
import uos_tui/diff
import uos_tui/event
import uos_tui/geometry
import uos_tui/layout
import uos_tui/markdown
import uos_tui/palette
import uos_tui/render
import uos_tui/segment
import uos_tui/style
import uos_tui/widget

pub type Model {
  Model(
    utc: String,
    change_id: String,
    query: String,
    palette_cursor: Int,
    table_cursor: Int,
    expanded: List(Int),
  )
}

pub type Msg {
  QueryChanged(String)
  PaletteMove(Int)
  PaletteSelect(Int)
  TableMove(Int)
  ToggleDomain(Int)
  Quit
}

const sample_markdown = "# uos_tui gallery\n\nA **pure** Gleam TUI library, `Textual`-referenced.\n\n- Header / StatusBar\n- Checklist\n- DataTable\n- Log\n"

fn commands() -> List(palette.Command(Msg)) {
  [
    palette.Command("quit", "Quit", ["exit", "q"], Quit),
    palette.Command(
      "toggle-d1",
      "Toggle checklist domain 1",
      ["checklist"],
      ToggleDomain(0),
    ),
  ]
}

pub fn init_model(utc: String, change_id: String) -> Model {
  Model(utc, change_id, "", 0, 0, [])
}

pub fn app(initial: Model) -> app.App(Model, Msg) {
  app.App(
    name: "uos-tui-gallery",
    init: fn(_size) { #(initial, app.NoEffect) },
    update: update,
    screens: [app.Screen("gallery", view)],
    initial_screen: "gallery",
    bindings: [widget.Binding(event.Char("q"), Quit, "quit")],
    theme: render.dark,
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, app.Effect(Msg)) {
  case msg {
    QueryChanged(q) -> #(Model(..model, query: q), app.NoEffect)
    PaletteMove(i) -> #(Model(..model, palette_cursor: i), app.NoEffect)
    PaletteSelect(i) -> #(Model(..model, palette_cursor: i), app.NoEffect)
    TableMove(i) -> #(Model(..model, table_cursor: i), app.NoEffect)
    ToggleDomain(i) -> {
      let expanded = case list.contains(model.expanded, i) {
        True -> list.filter(model.expanded, fn(x) { x != i })
        False -> [i, ..model.expanded]
      }
      #(Model(..model, expanded: expanded), app.NoEffect)
    }
    Quit -> #(model, app.Quit)
  }
}

/// 5-domain/18-item checklist, the library's own fixture (no cockpit/system_audit evidence
/// source here): every item starts unmet, and domains toggle open via `ToggleDomain`.
fn checklist_domains() -> List(widget.ChecklistDomain) {
  let item = fn(id, label) { widget.ChecklistItem(id, label, False) }
  [
    widget.ChecklistDomain("D1 Metadata & Tailscale", [
      item("CHK-01-TIME", "YYYYMMDD-HHSS- prefix"),
      item("CHK-02-TAIL", "Tailscale FQDN links"),
      item("CHK-03-FRACT", "fractal layer tags"),
      item("CHK-04-KM", "wiki/zk transclusions"),
    ]),
    widget.ChecklistDomain("D2 Zero-Muda & Storage", [
      item("CHK-05-MUDA", "0 Bevy 0 Graphite"),
      item("CHK-06-GRAPH", "no Graphene NIF"),
      item("CHK-07-DRIVE", "NVMe " <> aspects.os_nvme_serial <> " locked"),
    ]),
    widget.ChecklistDomain("D3 Testing Gold Std", [
      item("CHK-08-C1C8", "C1-C8 coverage"),
      item("CHK-09-MATH", "4 math gates"),
      item("CHK-10-9MOD", "9 modalities green"),
      item("CHK-11-REGR", "UI regression"),
    ]),
    widget.ChecklistDomain("D4 Cross-Language", [
      item("CHK-12-GLEAM", "OTP supervisor"),
      item("CHK-13-HERMES", "Hermes evidence"),
      item("CHK-14-ZIGVM", "ZigVM kernel"),
      item("CHK-15-MAX", "MAX quarantine"),
      item("CHK-16-OTEL", "C3I telemetry"),
    ]),
    widget.ChecklistDomain("D5 Governance & VCS", [
      item("CHK-17-SOV", "tri-sovereign consensus"),
      item("CHK-18-JJ", "standalone jj"),
    ]),
  ]
}

/// A short "diff engine" demo: compose two frames and report the dirty-row count, proving
/// `uos_tui/diff` is wired into the library's own reference application.
fn diff_summary() -> String {
  let before =
    render.compose(
      widget.Static("s", "before", style.none),
      geometry.Size(20, 3),
      option.None,
      render.dark,
    )
  let after =
    render.compose(
      widget.Static("s", "after", style.none),
      geometry.Size(20, 3),
      option.None,
      render.dark,
    )
  let #(changed, total, _) = diff.stats(before, after)
  "diff: "
  <> int.to_string(changed)
  <> "/"
  <> int.to_string(total)
  <> " rows changed"
}

pub fn view(model: Model) -> widget.Widget(Msg) {
  let status =
    widget.StatusBar("status", [
      widget.StatusField(
        "",
        aspects.tailnet_fqdn,
        style.none |> style.fg(style.Cyan),
      ),
      widget.StatusField("", model.utc, style.none),
      widget.StatusField("JJ", model.change_id, style.none),
    ])
  let checklist =
    widget.Checklist(
      "checklist",
      checklist_domains(),
      model.expanded,
      option.Some(ToggleDomain),
    )
  let table =
    widget.DataTable(
      "gallery-table",
      [
        widget.Column("widget", layout.Fraction(1)),
        widget.Column("family", layout.Fraction(1)),
      ],
      [["Static", "core"], ["Header", "core"], ["Button", "core"]],
      model.table_cursor,
      option.Some(TableMove),
      option.None,
    )
  let log_lines =
    markdown.render_lines(sample_markdown, 60, render.dark)
    |> list.map(segment.plain_text)
  let log = widget.Log("gallery-log", log_lines, 0)
  let pal =
    palette.view(
      model.query,
      palette.search(commands(), model.query, 5),
      model.palette_cursor,
      QueryChanged,
      PaletteMove,
      PaletteSelect,
    )
  let diff_static = widget.Static("diff-demo", diff_summary(), style.none)
  widget.Container(
    "root",
    layout.Vertical,
    [
      #(layout.Cells(1), status),
      #(layout.Cells(9), checklist),
      #(layout.Cells(6), table),
      #(layout.Cells(6), log),
      #(layout.Fraction(1), pal),
      #(layout.Cells(1), diff_static),
    ],
    False,
    "",
  )
}

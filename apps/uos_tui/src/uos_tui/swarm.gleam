//// Swarm ledger decoding, KPIs, and a dashboard screen.
//// Purpose: decode the uos-tui-swarm JSON ledger into typed data, derive
//// production KPIs (completion, pass rate, first-pass yield, WIP, cycle
//// time, andon), and compose a Textual-style dashboard `Widget`.
//// Reference: Textual `DataTable` + `ProgressBar` dashboard composition.
//// STAMP: SC-TUI-W01-001.

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import uos_tui/layout
import uos_tui/style
import uos_tui/widget.{type Widget}

/// Agent lifecycle status, as it appears in the ledger JSON.
pub type Status {
  Planned
  Running
  Passed
  Failed
  Integrated
}

/// One swarm agent row from the ledger.
pub type Agent {
  Agent(
    id: String,
    layer: String,
    role: String,
    model: String,
    effort: String,
    slice: String,
    workspace: String,
    owned_files: List(String),
    min_tests: Int,
    status: Status,
    started: String,
    finished: String,
    tests_added: Int,
    loc: Int,
    tokens_out: Int,
    verdict: String,
    notes: String,
  )
}

/// The full swarm ledger.
pub type Ledger {
  Ledger(
    swarm: String,
    timestamp: String,
    base_change: String,
    supervisor: String,
    takt_minutes: Int,
    wip_limit: Int,
    andon: String,
    jidoka_stops: Int,
    agents: List(Agent),
  )
}

/// Traffic-light production signal derived from ledger state.
pub type Andon {
  Green
  Yellow
  Red
}

/// Derived production KPIs for the swarm.
pub type Kpis {
  Kpis(
    completion_pct: Int,
    pass_rate_pct: Int,
    first_pass_yield_pct: Int,
    wip: Int,
    tokens_out: Int,
    tests_added: Int,
    loc: Int,
    avg_cycle_minutes: Int,
    jidoka_stops: Int,
    andon: Andon,
  )
}

fn parse_status(raw: String) -> Result(Status, Nil) {
  case raw {
    "planned" -> Ok(Planned)
    "running" -> Ok(Running)
    "passed" -> Ok(Passed)
    "failed" -> Ok(Failed)
    "integrated" -> Ok(Integrated)
    _ -> Error(Nil)
  }
}

/// Human label for a status (used by the dashboard table and markdown).
pub fn status_label(status: Status) -> String {
  case status {
    Planned -> "planned"
    Running -> "running"
    Passed -> "passed"
    Failed -> "failed"
    Integrated -> "integrated"
  }
}

fn status_decoder() -> decode.Decoder(Status) {
  use raw <- decode.then(decode.string)
  case parse_status(raw) {
    Ok(status) -> decode.success(status)
    Error(_) -> decode.failure(Planned, "Status")
  }
}

fn agent_decoder() -> decode.Decoder(Agent) {
  use id <- decode.field("id", decode.string)
  use layer <- decode.field("layer", decode.string)
  use role <- decode.field("role", decode.string)
  use model <- decode.field("model", decode.string)
  use effort <- decode.field("effort", decode.string)
  use slice <- decode.field("slice", decode.string)
  use workspace <- decode.field("workspace", decode.string)
  use owned_files <- decode.field("owned_files", decode.list(decode.string))
  use min_tests <- decode.field("min_tests", decode.int)
  use status <- decode.field("status", status_decoder())
  use started <- decode.field("started", decode.string)
  use finished <- decode.field("finished", decode.string)
  use tests_added <- decode.field("tests_added", decode.int)
  use loc <- decode.field("loc", decode.int)
  use tokens_out <- decode.field("tokens_out", decode.int)
  use verdict <- decode.field("verdict", decode.string)
  use notes <- decode.field("notes", decode.string)
  decode.success(Agent(
    id: id,
    layer: layer,
    role: role,
    model: model,
    effort: effort,
    slice: slice,
    workspace: workspace,
    owned_files: owned_files,
    min_tests: min_tests,
    status: status,
    started: started,
    finished: finished,
    tests_added: tests_added,
    loc: loc,
    tokens_out: tokens_out,
    verdict: verdict,
    notes: notes,
  ))
}

fn ledger_decoder() -> decode.Decoder(Ledger) {
  use swarm <- decode.field("swarm", decode.string)
  use timestamp <- decode.field("timestamp", decode.string)
  use base_change <- decode.field("base_change", decode.string)
  use supervisor <- decode.field("supervisor", decode.string)
  use takt_minutes <- decode.field("takt_minutes", decode.int)
  use wip_limit <- decode.field("wip_limit", decode.int)
  use andon <- decode.field("andon", decode.string)
  use jidoka_stops <- decode.field("jidoka_stops", decode.int)
  use agents <- decode.field("agents", decode.list(agent_decoder()))
  decode.success(Ledger(
    swarm: swarm,
    timestamp: timestamp,
    base_change: base_change,
    supervisor: supervisor,
    takt_minutes: takt_minutes,
    wip_limit: wip_limit,
    andon: andon,
    jidoka_stops: jidoka_stops,
    agents: agents,
  ))
}

/// Decode a swarm ledger JSON document. Unknown extra keys are ignored.
pub fn decode(json_text: String) -> Result(Ledger, String) {
  case json.parse(json_text, ledger_decoder()) {
    Ok(ledger) -> Ok(ledger)
    Error(_) -> Error("swarm ledger: malformed or non-conforming JSON")
  }
}

fn count_status(agents: List(Agent), target: Status) -> Int {
  list.count(agents, fn(a) { a.status == target })
}

fn parse_component(text: String, at: Int, len: Int) -> Result(Int, Nil) {
  text |> string.slice(at, len) |> int.parse
}

/// Minutes-since-epoch-ish projection of an ISO `YYYY-MM-DDTHH:MM:SSZ`
/// timestamp, built by slicing digits (no external time library). Only
/// used for relative cycle-time differences, never absolute time.
fn minutes_of(iso: String) -> Result(Int, Nil) {
  case string.length(iso) >= 16 {
    False -> Error(Nil)
    True -> {
      case parse_component(iso, 0, 4) {
        Error(_) -> Error(Nil)
        Ok(year) ->
          case parse_component(iso, 5, 2) {
            Error(_) -> Error(Nil)
            Ok(month) ->
              case parse_component(iso, 8, 2) {
                Error(_) -> Error(Nil)
                Ok(day) ->
                  case parse_component(iso, 11, 2) {
                    Error(_) -> Error(Nil)
                    Ok(hour) ->
                      case parse_component(iso, 14, 2) {
                        Error(_) -> Error(Nil)
                        Ok(minute) ->
                          Ok(
                            { { year * 372 + month * 31 + day } * 24 + hour }
                            * 60
                            + minute,
                          )
                      }
                  }
              }
          }
      }
    }
  }
}

fn cycle_minutes(agents: List(Agent)) -> Int {
  let #(total, count) =
    list.fold(agents, #(0, 0), fn(acc, a) {
      let #(total, count) = acc
      case a.started == "" || a.finished == "" {
        True -> acc
        False ->
          case minutes_of(a.started), minutes_of(a.finished) {
            Ok(start_m), Ok(finish_m) -> #(
              total + finish_m - start_m,
              count + 1,
            )
            _, _ -> acc
          }
      }
    })
  case count {
    0 -> 0
    _ -> total / count
  }
}

fn andon_of(ledger: Ledger, failed: Int, running: Int) -> Andon {
  case failed >= 2 || ledger.andon == "red" {
    True -> Red
    False ->
      case failed == 1 || { running > 0 && failed > 0 } {
        True -> Yellow
        False -> Green
      }
  }
}

/// Human label for an andon signal.
pub fn andon_label(andon: Andon) -> String {
  case andon {
    Green -> "GREEN"
    Yellow -> "YELLOW"
    Red -> "RED"
  }
}

/// Derive production KPIs from a ledger.
pub fn kpis(ledger: Ledger) -> Kpis {
  let agents = ledger.agents
  let total = list.length(agents)
  let completed =
    count_status(agents, Passed) + count_status(agents, Integrated)
  let failed = count_status(agents, Failed)
  let running = count_status(agents, Running)
  let completion_pct = case total {
    0 -> 0
    _ -> completed * 100 / total
  }
  let denom = completed + failed
  let pass_rate_pct = case denom {
    0 -> 0
    _ -> completed * 100 / denom
  }
  let verdicts_nonempty = list.count(agents, fn(a) { a.verdict != "" })
  let verdicts_pass = list.count(agents, fn(a) { a.verdict == "PASS" })
  let first_pass_yield_pct = case verdicts_nonempty {
    0 -> 0
    _ -> verdicts_pass * 100 / verdicts_nonempty
  }
  let tokens_out = list.fold(agents, 0, fn(acc, a) { acc + a.tokens_out })
  let tests_added = list.fold(agents, 0, fn(acc, a) { acc + a.tests_added })
  let loc = list.fold(agents, 0, fn(acc, a) { acc + a.loc })
  Kpis(
    completion_pct: completion_pct,
    pass_rate_pct: pass_rate_pct,
    first_pass_yield_pct: first_pass_yield_pct,
    wip: running,
    tokens_out: tokens_out,
    tests_added: tests_added,
    loc: loc,
    avg_cycle_minutes: cycle_minutes(agents),
    jidoka_stops: ledger.jidoka_stops,
    andon: andon_of(ledger, failed, running),
  )
}

fn kpi_lines(k: Kpis) -> List(String) {
  [
    "Completion: " <> int.to_string(k.completion_pct) <> "%",
    "Pass rate: " <> int.to_string(k.pass_rate_pct) <> "%",
    "First-pass yield: " <> int.to_string(k.first_pass_yield_pct) <> "%",
    "WIP: " <> int.to_string(k.wip),
    "Tokens out: " <> int.to_string(k.tokens_out),
    "Tests added: " <> int.to_string(k.tests_added),
    "LOC: " <> int.to_string(k.loc),
    "Avg cycle (min): " <> int.to_string(k.avg_cycle_minutes),
    "Jidoka stops: " <> int.to_string(k.jidoka_stops),
    "Andon: " <> andon_label(k.andon),
  ]
}

/// Compose the swarm dashboard: status bar, progress bar, an agent data
/// table, and a KPI summary panel.
pub fn view(ledger: Ledger, cursor: Int) -> Widget(msg) {
  let k = kpis(ledger)
  let status_bar =
    widget.StatusBar("swarm-status", [
      widget.StatusField("Swarm", ledger.swarm, style.none),
      widget.StatusField("Andon", andon_label(k.andon), style.none),
      widget.StatusField("WIP", int.to_string(k.wip), style.none),
      widget.StatusField(
        "Completion",
        int.to_string(k.completion_pct) <> "%",
        style.none,
      ),
    ])
  let progress =
    widget.ProgressBar(
      "swarm-progress",
      int.to_float(k.completion_pct) /. 100.0,
      "Completion",
    )
  let columns = [
    widget.Column("id", layout.Cells(6)),
    widget.Column("layer", layout.Cells(6)),
    widget.Column("model", layout.Cells(8)),
    widget.Column("slice", layout.Fraction(1)),
    widget.Column("status", layout.Cells(10)),
    widget.Column("tests", layout.Cells(6)),
    widget.Column("loc", layout.Cells(6)),
    widget.Column("tokens", layout.Cells(8)),
  ]
  let rows =
    list.map(ledger.agents, fn(a) {
      [
        a.id,
        a.layer,
        a.model,
        a.slice,
        status_label(a.status),
        int.to_string(a.tests_added),
        int.to_string(a.loc),
        int.to_string(a.tokens_out),
      ]
    })
  let table =
    widget.DataTable(
      "swarm-agents",
      columns,
      rows,
      cursor,
      option.None,
      option.None,
    )
  let kpi_static =
    widget.Static("swarm-kpis", string.join(kpi_lines(k), "\n"), style.none)
  let body =
    widget.Container(
      "swarm-body",
      layout.Vertical,
      [#(layout.Fraction(2), table), #(layout.Fraction(1), kpi_static)],
      False,
      "",
    )
  widget.Container(
    "swarm-dashboard",
    layout.Vertical,
    [
      #(layout.Cells(1), status_bar),
      #(layout.Cells(1), progress),
      #(layout.Fraction(1), body),
    ],
    False,
    "swarm",
  )
}

fn agent_markdown_row(a: Agent) -> String {
  "| "
  <> a.id
  <> " | "
  <> a.layer
  <> " | "
  <> a.model
  <> " | "
  <> a.slice
  <> " | "
  <> status_label(a.status)
  <> " | "
  <> int.to_string(a.tests_added)
  <> " | "
  <> int.to_string(a.loc)
  <> " | "
  <> int.to_string(a.tokens_out)
  <> " |"
}

/// Render the ledger as a KPI table plus an agent table, in markdown.
pub fn to_markdown(ledger: Ledger) -> String {
  let k = kpis(ledger)
  let kpi_rows =
    list.map(kpi_lines(k), fn(line) {
      case string.split_once(line, ": ") {
        Ok(#(label, value)) -> "| " <> label <> " | " <> value <> " |"
        Error(_) -> "| " <> line <> " | |"
      }
    })
  let kpi_table = "| KPI | Value |\n|---|---|\n" <> string.join(kpi_rows, "\n")
  let agent_header =
    "| id | layer | model | slice | status | tests | loc | tokens |\n"
    <> "|---|---|---|---|---|---|---|---|"
  let agent_rows = list.map(ledger.agents, agent_markdown_row)
  kpi_table <> "\n\n" <> agent_header <> "\n" <> string.join(agent_rows, "\n")
}

/// A small 3-agent example ledger used by tests.
pub fn sample_ledger() -> Ledger {
  Ledger(
    swarm: "uos-tui-swarm",
    timestamp: "20260907-0440",
    base_change: "vvrtrspvmtqq",
    supervisor: "L1-planner",
    takt_minutes: 12,
    wip_limit: 11,
    andon: "green",
    jidoka_stops: 0,
    agents: [
      Agent(
        id: "W01",
        layer: "L2",
        role: "worker",
        model: "sonnet",
        effort: "medium",
        slice: "swarm ledger, kpis, dashboard",
        workspace: ".uos-workspaces/tui-w01",
        owned_files: ["src/uos_tui/swarm.gleam"],
        min_tests: 10,
        status: Passed,
        started: "2026-09-07T04:40:00Z",
        finished: "2026-09-07T04:55:00Z",
        tests_added: 12,
        loc: 180,
        tokens_out: 9000,
        verdict: "PASS",
        notes: "",
      ),
      Agent(
        id: "W02",
        layer: "L2",
        role: "worker",
        model: "sonnet",
        effort: "medium",
        slice: "widget catalog audit",
        workspace: ".uos-workspaces/tui-w02",
        owned_files: ["src/uos_tui/catalog.gleam"],
        min_tests: 10,
        status: Running,
        started: "2026-09-07T04:40:00Z",
        finished: "",
        tests_added: 0,
        loc: 0,
        tokens_out: 4000,
        verdict: "",
        notes: "",
      ),
      Agent(
        id: "W03",
        layer: "L2",
        role: "worker",
        model: "sonnet",
        effort: "medium",
        slice: "ontology graph extension",
        workspace: ".uos-workspaces/tui-w03",
        owned_files: ["src/uos_tui/ontology2.gleam"],
        min_tests: 10,
        status: Failed,
        started: "2026-09-07T04:40:00Z",
        finished: "2026-09-07T04:50:00Z",
        tests_added: 3,
        loc: 60,
        tokens_out: 5000,
        verdict: "FAIL",
        notes: "compile error",
      ),
    ],
  )
}

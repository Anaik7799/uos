//// Provenance panel — a TUI surface for the KM provenance state (SC-PROVENANCE-001).
////
//// Renders the six machine checks, the admitted-EV ceiling split, and the
//// forecast band for each tracked metric. Composed from uos_tui widgets and
//// pure: it emits `Intent` values and executes no side effect, matching the
//// Rocha cut used by the cockpit.
////
//// The panel deliberately shows HOLD states as prominently as PASS states. A
//// dashboard that renders only greens is a dashboard nobody can use to find a
//// problem.

import gleam/float
import gleam/int
import gleam/list
import gleam/string

/// One machine check and its observed state.
pub type Check {
  Check(rule: String, label: String, state: State, detail: String)
}

pub type State {
  Pass
  Hold
  Andon
}

/// A tracked metric with its forecast band. `decisive` is False when the band
/// spans the threshold, meaning the projection settles nothing.
pub type Metric {
  Metric(
    name: String,
    current: Float,
    threshold: Float,
    slope: Float,
    residual: Float,
    projected: Float,
    decisive: Bool,
  )
}

/// The admitted-EV ceiling, which currently has two disagreeing values.
pub type Ceiling {
  Ceiling(policy: Int, machine: Int, highest_claimed: Int)
}

pub type Model {
  Model(
    checks: List(Check),
    metrics: List(Metric),
    ceiling: Ceiling,
    quarantined: Int,
    corpus_total: Int,
    chain_rows: Int,
    chain_intact: Bool,
  )
}

/// Intents only. Nothing here performs an effect.
pub type Intent {
  RunGate
  RunRete
  RunOoda
  OpenContract
  OpenQuarantineEvidence
}

pub fn state_glyph(state: State) -> String {
  case state {
    Pass -> "PASS"
    Hold -> "HOLD"
    Andon -> "ANDON"
  }
}

/// Overall verdict: any andon dominates, then any hold, else pass.
pub fn verdict(model: Model) -> State {
  case list.any(model.checks, fn(c) { c.state == Andon }) {
    True -> Andon
    False ->
      case list.any(model.checks, fn(c) { c.state == Hold }) {
        True -> Hold
        False -> Pass
      }
  }
}

/// True when the policy ceiling and the machine-verified ceiling disagree.
pub fn ceiling_split(c: Ceiling) -> Bool {
  c.policy != c.machine
}

/// Records claiming a cycle above the policy ceiling are not admitted.
pub fn not_admitted_span(c: Ceiling) -> String {
  case c.highest_claimed > c.policy {
    True ->
      "EV-" <> int.to_string(c.policy + 1) <> ".." <> "EV-"
      <> int.to_string(c.highest_claimed)
    False -> "none"
  }
}

fn fmt(value: Float) -> String {
  float.to_string(value)
}

/// One metric line, showing the band and whether it decides anything.
pub fn metric_line(m: Metric) -> String {
  let band =
    "[" <> fmt(m.projected -. m.residual) <> ", "
    <> fmt(m.projected +. m.residual) <> "]"
  let decisive = case m.decisive {
    True -> "decisive"
    False -> "not decisive"
  }
  m.name
  <> "  now "
  <> fmt(m.current)
  <> "  floor "
  <> fmt(m.threshold)
  <> "  slope "
  <> fmt(m.slope)
  <> "  proj "
  <> band
  <> "  "
  <> decisive
}

/// The rendered panel as lines. Kept as plain text so the same content can go
/// to a terminal frame, an HTML view, or a test assertion unchanged.
pub fn lines(model: Model) -> List(String) {
  let header =
    "KM PROVENANCE  "
    <> state_glyph(verdict(model))
    <> "   corpus "
    <> int.to_string(model.corpus_total)
    <> "   quarantined "
    <> int.to_string(model.quarantined)

  let ceiling_line = case ceiling_split(model.ceiling) {
    True ->
      "CEILING SPLIT  policy EV-"
      <> int.to_string(model.ceiling.policy)
      <> "  machine-verified EV-"
      <> int.to_string(model.ceiling.machine)
      <> "  NOT_ADMITTED "
      <> not_admitted_span(model.ceiling)
    False ->
      "CEILING  EV-"
      <> int.to_string(model.ceiling.policy)
      <> "  NOT_ADMITTED "
      <> not_admitted_span(model.ceiling)
  }

  let chain_line =
    "CYCLE CHAIN  "
    <> int.to_string(model.chain_rows)
    <> " rows  "
    <> case model.chain_intact {
      True -> "INTACT"
      False -> "BROKEN — verdicts suspended"
    }

  let check_lines =
    list.map(model.checks, fn(c) {
      "  " <> state_glyph(c.state) <> "  " <> c.rule <> "  " <> c.detail
    })

  let metric_lines = list.map(model.metrics, fn(m) { "  " <> metric_line(m) })

  list.flatten([
    [header, ceiling_line, chain_line, ""],
    ["CHECKS"],
    check_lines,
    ["", "FORECAST"],
    metric_lines,
  ])
}

/// Plain-text render, for a terminal frame or a snapshot test.
pub fn render(model: Model) -> String {
  string.join(lines(model), "\n")
}

/// The keybindings this panel offers. Each maps to an Intent, never an effect.
pub fn bindings() -> List(#(String, Intent)) {
  [
    #("g", RunGate),
    #("r", RunRete),
    #("o", RunOoda),
    #("c", OpenContract),
    #("q", OpenQuarantineEvidence),
  ]
}

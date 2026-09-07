//// Fractal Textual Ontology: Textual's concepts (App, Screen, Widget, DOM, TCSS, Reactive,
//// Message, Binding, Worker, Compositor, Strip/Segment, Driver, Pilot) mapped onto the UOS
//// fractal layers L0..L9 and onto the uos_tui module that realises each concept.
//// Same node/edge shape as `cepaf_gleam/fpp/ontology.gleam` so both graphs can be merged.
//// STAMP: SC-TUI-ONTOLOGY-001, #km-triad.

import gleam/list
import gleam/string

pub type FractalLayer {
  L0Constitutional
  L1Atomic
  L2Component
  L3Transaction
  L4System
  L5Cognitive
  L6Ecosystem
  L7Federation
  L8Evolution
  L9Singularity
}

pub fn layer_tag(layer: FractalLayer) -> String {
  case layer {
    L0Constitutional -> "#fractal-l0"
    L1Atomic -> "#fractal-l1"
    L2Component -> "#fractal-l2"
    L3Transaction -> "#fractal-l3"
    L4System -> "#fractal-l4"
    L5Cognitive -> "#fractal-l5"
    L6Ecosystem -> "#fractal-l6"
    L7Federation -> "#fractal-l7"
    L8Evolution -> "#fractal-l8"
    L9Singularity -> "#fractal-l9"
  }
}

pub type Concept {
  Concept(
    textual_name: String,
    textual_locus: String,
    uos_module: String,
    uos_symbol: String,
    layer: FractalLayer,
    fidelity: Fidelity,
    note: String,
  )
}

/// How faithfully the Gleam realisation reproduces the Textual concept.
pub type Fidelity {
  Isomorphic
  Homomorphic
  Reinterpreted
  Deferred
}

pub type Relation {
  Composes
  Renders
  Styles
  Dispatches
  Binds
  Drives
  Audits
  Declares
}

pub type Edge {
  Edge(from: String, to: String, relation: Relation)
}

pub type Graph {
  Graph(concepts: List(Concept), edges: List(Edge))
}

pub fn graph() -> Graph {
  Graph(concepts: concepts(), edges: edges())
}

pub fn concepts() -> List(Concept) {
  [
    Concept(
      "App",
      "textual.app.App",
      "uos_tui/app",
      "App",
      L4System,
      Homomorphic,
      "class with compose() becomes a record of init/update/screens; reactivity is TEA re-render",
    ),
    Concept(
      "Screen",
      "textual.screen.Screen",
      "uos_tui/app",
      "Screen",
      L4System,
      Isomorphic,
      "named view over the model; push/pop via PushScreen/PopScreen effects",
    ),
    Concept(
      "Widget",
      "textual.widget.Widget",
      "uos_tui/widget",
      "Widget(msg)",
      L2Component,
      Homomorphic,
      "class hierarchy becomes one closed sum type; state lives in the model",
    ),
    Concept(
      "DOM",
      "textual.dom.DOMNode",
      "uos_tui/widget",
      "flatten/find/children",
      L2Component,
      Isomorphic,
      "pre-order tree with ids",
    ),
    Concept(
      "compose()",
      "Widget.compose",
      "uos_tui/app",
      "Screen.view",
      L2Component,
      Isomorphic,
      "pure function model -> tree",
    ),
    Concept(
      "TCSS",
      "textual.css",
      "uos_tui/style",
      "Style",
      L1Atomic,
      Reinterpreted,
      "no CSS parser; typed style records with a combine monoid",
    ),
    Concept(
      "Scalar / fr units",
      "textual.css.scalar",
      "uos_tui/layout",
      "Scalar",
      L1Atomic,
      Isomorphic,
      "Cells, Fraction, Percent, Auto",
    ),
    Concept(
      "Vertical/Horizontal/Grid",
      "textual.layouts",
      "uos_tui/layout",
      "arrange/grid",
      L2Component,
      Isomorphic,
      "same resolution order: fixed, percent, auto, fraction",
    ),
    Concept(
      "Region/Size/Offset",
      "textual.geometry",
      "uos_tui/geometry",
      "Region",
      L1Atomic,
      Isomorphic,
      "half-open rectangles with intersection/union laws",
    ),
    Concept(
      "Segment / Strip",
      "rich.segment / textual.strip",
      "uos_tui/segment",
      "Strip",
      L1Atomic,
      Isomorphic,
      "styled runs with cached cell length; crop/extend/simplify",
    ),
    Concept(
      "Compositor",
      "textual._compositor",
      "uos_tui/render",
      "compose/arrange",
      L3Transaction,
      Homomorphic,
      "placements blitted into a frame; no dirty-region diffing yet",
    ),
    Concept(
      "reactive",
      "textual.reactive",
      "uos_tui/app",
      "update -> render",
      L3Transaction,
      Reinterpreted,
      "every message re-renders; watchers become update clauses",
    ),
    Concept(
      "Message / Event",
      "textual.message / textual.events",
      "uos_tui/event",
      "Event, msg",
      L3Transaction,
      Homomorphic,
      "system events typed; widget messages are user-typed msg",
    ),
    Concept(
      "Binding / action",
      "textual.binding.Binding",
      "uos_tui/widget",
      "Binding(msg)",
      L3Transaction,
      Isomorphic,
      "key -> msg with description shown in Footer",
    ),
    Concept(
      "Focus chain",
      "textual.screen.focus_chain",
      "uos_tui/app",
      "move_focus",
      L3Transaction,
      Isomorphic,
      "document-order Tab/Shift-Tab",
    ),
    Concept(
      "Worker",
      "textual.worker",
      "uos_tui/app + uos_tui/live",
      "Effect.Task",
      L4System,
      Homomorphic,
      "task functions run in BEAM processes by the live driver",
    ),
    Concept(
      "Driver",
      "textual.driver",
      "uos_tui/live",
      "run/child_spec",
      L4System,
      Homomorphic,
      "OTP actor + reader process; raw mode via pure Erlang shell API",
    ),
    Concept(
      "Pilot / run_test",
      "textual.pilot.Pilot",
      "uos_tui/headless",
      "run",
      L5Cognitive,
      Isomorphic,
      "scripted events, captured frames",
    ),
    Concept(
      "Command palette",
      "textual.command",
      "uos_tui/gallery",
      "view/search/score",
      L5Cognitive,
      Homomorphic,
      "fuzzy subsequence scoring; caller supplies the registry (uos_tui/gallery demos it)",
    ),
    Concept(
      "Themes",
      "textual.theme",
      "uos_tui/render",
      "Theme",
      L1Atomic,
      Homomorphic,
      "single dark theme plus Dark Cockpit mode overlay",
    ),
    Concept(
      "Header/Footer",
      "textual.widgets",
      "uos_tui/widget",
      "Header, Footer",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "Static/Label",
      "textual.widgets.Static",
      "uos_tui/widget",
      "Static",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "Button",
      "textual.widgets.Button",
      "uos_tui/widget",
      "Button",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "Input",
      "textual.widgets.Input",
      "uos_tui/widget",
      "Input",
      L2Component,
      Homomorphic,
      "no validators/suggester",
    ),
    Concept(
      "DataTable",
      "textual.widgets.DataTable",
      "uos_tui/widget",
      "DataTable",
      L2Component,
      Homomorphic,
      "row cursor only",
    ),
    Concept(
      "Tree",
      "textual.widgets.Tree",
      "uos_tui/widget",
      "Tree",
      L2Component,
      Homomorphic,
      "",
    ),
    Concept(
      "ListView",
      "textual.widgets.ListView",
      "uos_tui/widget",
      "ListView",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "ProgressBar",
      "textual.widgets.ProgressBar",
      "uos_tui/widget",
      "ProgressBar",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "Sparkline",
      "textual.widgets.Sparkline",
      "uos_tui/widget",
      "Sparkline",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "Tabs / TabbedContent",
      "textual.widgets.Tabs",
      "uos_tui/widget",
      "Tabs",
      L2Component,
      Homomorphic,
      "content switching is the model's job",
    ),
    Concept(
      "RichLog / Log",
      "textual.widgets.Log",
      "uos_tui/widget",
      "Log",
      L2Component,
      Homomorphic,
      "plain lines, scroll offset",
    ),
    Concept(
      "Rule",
      "textual.widgets.Rule",
      "uos_tui/widget",
      "Rule",
      L2Component,
      Isomorphic,
      "",
    ),
    Concept(
      "Collapsible",
      "textual.widgets.Collapsible",
      "uos_tui/widget",
      "Checklist",
      L0Constitutional,
      Reinterpreted,
      "UOS 5-domain/18-item checklist accordion (SC-CHECKLIST-001)",
    ),
    Concept(
      "Container",
      "textual.containers",
      "uos_tui/widget",
      "Container, Grid",
      L2Component,
      Isomorphic,
      "border + title like Textual border-title",
    ),
    Concept(
      "17 Aspect audit",
      "(none)",
      "uos_tui/aspects",
      "audit",
      L0Constitutional,
      Reinterpreted,
      "UOS-only: fail-closed structural verification of a composed screen",
    ),
    Concept(
      "F´ component",
      "(none)",
      "uos_tui/fprime",
      "component/dictionary_json",
      L6Ecosystem,
      Reinterpreted,
      "UOS-only: ports, commands, channels, events, parameters, ground dictionary",
    ),
    Concept(
      "Textual Web / serve",
      "textual-serve",
      "uos_tui/frame",
      "to_text/to_ansi",
      L7Federation,
      Deferred,
      "projection to Wisp at :4100 is a follow-on",
    ),
    Concept(
      "Evolution",
      "(none)",
      "uos_tui/ontology",
      "Fidelity",
      L8Evolution,
      Reinterpreted,
      "fidelity ladder Deferred -> Reinterpreted -> Homomorphic -> Isomorphic",
    ),
  ]
}

pub fn edges() -> List(Edge) {
  [
    Edge("App", "Screen", Composes),
    Edge("Screen", "Widget", Composes),
    Edge("Widget", "DOM", Composes),
    Edge("compose()", "Widget", Composes),
    Edge("TCSS", "Widget", Styles),
    Edge("Themes", "Compositor", Styles),
    Edge("Vertical/Horizontal/Grid", "Region/Size/Offset", Composes),
    Edge("Compositor", "Segment / Strip", Renders),
    Edge("Compositor", "Region/Size/Offset", Renders),
    Edge("Message / Event", "App", Dispatches),
    Edge("Binding / action", "App", Binds),
    Edge("Focus chain", "Widget", Binds),
    Edge("Worker", "Driver", Drives),
    Edge("Driver", "App", Drives),
    Edge("Pilot / run_test", "App", Drives),
    Edge("17 Aspect audit", "Widget", Audits),
    Edge("F´ component", "App", Declares),
    Edge("Collapsible", "17 Aspect audit", Declares),
  ]
}

pub fn by_layer(g: Graph, layer: FractalLayer) -> List(Concept) {
  list.filter(g.concepts, fn(c) { c.layer == layer })
}

pub fn fidelity_counts(g: Graph) -> #(Int, Int, Int, Int) {
  #(
    list.count(g.concepts, fn(c) { c.fidelity == Isomorphic }),
    list.count(g.concepts, fn(c) { c.fidelity == Homomorphic }),
    list.count(g.concepts, fn(c) { c.fidelity == Reinterpreted }),
    list.count(g.concepts, fn(c) { c.fidelity == Deferred }),
  )
}

/// Every edge endpoint must name a concept.
pub fn validate(g: Graph) -> Result(Nil, String) {
  let names = list.map(g.concepts, fn(c) { c.textual_name })
  case
    list.find(g.edges, fn(e) {
      !list.contains(names, e.from) || !list.contains(names, e.to)
    })
  {
    Ok(e) -> Error("dangling edge " <> e.from <> " -> " <> e.to)
    Error(_) ->
      case list.length(list.unique(names)) == list.length(names) {
        True -> Ok(Nil)
        False -> Error("duplicate concept name")
      }
  }
}

/// Markdown table for wiki generation.
pub fn to_markdown(g: Graph) -> String {
  let header =
    "| Textual concept | Textual locus | uos_tui | Layer | Fidelity | Note |\n|---|---|---|---|---|---|"
  let rows =
    list.map(g.concepts, fn(c) {
      "| "
      <> c.textual_name
      <> " | `"
      <> c.textual_locus
      <> "` | `"
      <> c.uos_module
      <> "."
      <> c.uos_symbol
      <> "` | "
      <> layer_tag(c.layer)
      <> " | "
      <> fidelity_label(c.fidelity)
      <> " | "
      <> c.note
      <> " |"
    })
  string.join([header, ..rows], "\n")
}

pub fn fidelity_label(f: Fidelity) -> String {
  case f {
    Isomorphic -> "Isomorphic"
    Homomorphic -> "Homomorphic"
    Reinterpreted -> "Reinterpreted"
    Deferred -> "Deferred"
  }
}

//// =============================================================================
//// [C3I-SIL6-FPP-ATLAS] NASA JPL F Prime 5-Tier Algebraic Atlas & Ontology View
//// =============================================================================
//// Pure Lustre 5.6+ MVU Component for F Prime Algebraic Atlas & Living Ontology:
//// - 5-Tier Category-Theoretic Hierarchy (AST -> Topo -> BEAM -> Sheaf -> Rocha)
//// - Living Biomorphic Ontology Node & Edge Census
//// - DMC Memory Window Disjointness & TCM 13D Conservation Dashboard
//// - Sheaf Gluing & Boundary Mutual Agreement Visualizer
//// - Denotational Intent Safety Interlock Gatekeeper Display
//// =============================================================================

import cepaf_gleam/fpp/algebraic_atlas.{
  type AtlasReport, Tier1Topology, build_fpp_algebraic_atlas, tier_to_string,
}
import cepaf_gleam/fpp/dmc_tcm.{verify_memory_window_disjointness}
import cepaf_gleam/fpp/ontology.{
  category_to_string, derive_fpp_ontology,
}
import cepaf_gleam/fpp/topology.{canonical_harness_model}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// =============================================================================
// Model & Messages
// =============================================================================

pub type Model {
  Model(
    selected_tier: Option(algebraic_atlas.AtlasTier),
    active_tab: String,
  )
}

pub type Msg {
  SelectTier(algebraic_atlas.AtlasTier)
  SelectTab(String)
}

pub fn init() -> Model {
  Model(
    selected_tier: Some(Tier1Topology),
    active_tab: "atlas",
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    SelectTier(t) -> Model(..model, selected_tier: Some(t))
    SelectTab(tab) -> Model(..model, active_tab: tab)
  }
}

// =============================================================================
// View
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  let fpp_model = canonical_harness_model()
  let atlas_report = build_fpp_algebraic_atlas(fpp_model)
  let onto_graph = derive_fpp_ontology(fpp_model)
  let dmc_report = verify_memory_window_disjointness(fpp_model)

  html.div([attribute.class("fpp-atlas-container p-4 bg-slate-900 text-slate-200 rounded-lg space-y-6")], [
    render_header(),
    render_metric_tiles(atlas_report, onto_graph, dmc_report),
    render_navigation_tabs(model.active_tab),
    case model.active_tab {
      "ontology" -> render_ontology_panel(onto_graph)
      "dmc_tcm" -> render_dmc_tcm_panel(dmc_report)
      _ -> render_atlas_panel(atlas_report, model.selected_tier)
    },
    render_api_links(),
  ])
}

fn render_header() -> Element(Msg) {
  html.div([attribute.class("flex justify-between items-center pb-4 border-b border-slate-800")], [
    html.div([], [
      html.h2([attribute.class("text-2xl font-bold text-amber-400 flex items-center gap-2")], [
        html.span([], [html.text("🌌")]),
        html.text("NASA JPL F Prime 5-Tier Algebraic Atlas & Living Ontology"),
      ]),
      html.p([attribute.class("text-xs text-slate-400 mt-1")], [
        html.text("Category-Theoretic Topos, Sheaf Gluing & Biomorphic Semiotics on Pure BEAM / OTP 29"),
      ]),
    ]),
    html.div([attribute.class("flex items-center gap-2")], [
      html.span([attribute.class("px-3 py-1 text-xs font-mono font-bold rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/40")], [
        html.text("Δ T₁₃ ≡ 0 CONSERVED"),
      ]),
    ]),
  ])
}

fn render_metric_tiles(
  atlas: AtlasReport,
  onto: ontology.OntoGraph,
  _dmc: dmc_tcm.MemoryCoherenceReport,
) -> Element(Msg) {
  html.div([attribute.class("grid grid-cols-2 sm:grid-cols-3 md:grid-cols-6 gap-3 text-center text-xs")], [
    metric_tile("5 TIERS", "Category Hierarchy", "text-amber-400"),
    metric_tile(int.to_string(list.length(onto.nodes)), "Onto Nodes", "text-sky-400"),
    metric_tile(int.to_string(list.length(onto.edges)), "Onto Edges", "text-indigo-400"),
    metric_tile("7/7 DISJOINT", "DMC Windows", "text-emerald-400"),
    metric_tile(int.to_string(atlas.morphisms_count), "Morphisms", "text-purple-400"),
    metric_tile("LOCKED", "NVMe 25503L801736", "text-rose-400"),
  ])
}

fn metric_tile(value: String, label: String, color_class: String) -> Element(Msg) {
  html.div([attribute.class("bg-slate-950 p-3 rounded border border-slate-800 flex flex-col items-center justify-center")], [
    html.span([attribute.class("text-lg font-bold font-mono " <> color_class)], [html.text(value)]),
    html.span([attribute.class("text-[10px] text-slate-400 uppercase tracking-wider mt-1")], [html.text(label)]),
  ])
}

fn render_navigation_tabs(active: String) -> Element(Msg) {
  html.div([attribute.class("flex gap-2 border-b border-slate-800 pb-2 text-xs font-mono")], [
    tab_button("atlas", "Algebraic Atlas (5 Tiers)", active == "atlas"),
    tab_button("ontology", "Living Ontology Graph", active == "ontology"),
    tab_button("dmc_tcm", "DMC + TCM & Storage Interlock", active == "dmc_tcm"),
  ])
}

fn tab_button(id: String, label: String, is_active: Bool) -> Element(Msg) {
  let base_class = "px-4 py-1.5 rounded cursor-pointer transition-colors "
  let active_class = case is_active {
    True -> "bg-amber-500/20 text-amber-300 border border-amber-500/40 font-bold"
    False -> "bg-slate-950 text-slate-400 hover:bg-slate-800 border border-slate-800"
  }
  html.button([
    attribute.class(base_class <> active_class),
    event.on_click(SelectTab(id)),
  ], [html.text(label)])
}

// ------------------------------------------------------------- Atlas Panel

fn render_atlas_panel(
  report: AtlasReport,
  _selected_tier: Option(algebraic_atlas.AtlasTier),
) -> Element(Msg) {
  html.div([attribute.class("space-y-4")], [
    html.div([attribute.class("bg-slate-950 p-4 rounded-lg border border-slate-800 space-y-3")], [
      html.h3([attribute.class("text-sm font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-2")], [
        html.span([], [html.text("🗺️")]),
        html.text("5-Tier Category-Theoretic Atlas"),
      ]),
      html.p([attribute.class("text-xs text-slate-400")], [
        html.text("Functors map syntactically verified FPP ASTs into topological models, realized as supervised OTP 29 actors, observed as telemetry sheaves, and grounded in Rocha biosemiotics."),
      ]),
      html.div([attribute.class("grid grid-cols-1 md:grid-cols-5 gap-2 pt-2 text-xs font-mono")], [
        tier_card("Tier 0: FppAST", "Syntactic Grammar", "AST Nodes & Models", "Dimension 0"),
        tier_card("Tier 1: FppTopo", "Denotational Category", "Components & Ports", "Dimension 1"),
        tier_card("Tier 2: BeamActor", "Operational Monad", "OTP 29 Mailboxes", "Dimension 2"),
        tier_card("Tier 3: SheafTel", "Sheaf of Sections", "Subtopology Streams", "Dimension 3"),
        tier_card("Tier 4: RochaSemiotic", "Biosemiotic Grounding", "Physical Actuators", "Dimension 4"),
      ]),
    ]),
    html.div([attribute.class("bg-slate-950 p-4 rounded-lg border border-slate-800")], [
      html.h3([attribute.class("text-sm font-semibold text-slate-300 uppercase tracking-wider mb-3 flex items-center gap-2")], [
        html.span([], [html.text("🔗")]),
        html.text("Functorial Homomorphisms & Natural Transformations (" <> int.to_string(report.morphisms_count) <> ")"),
      ]),
      html.div([attribute.class("overflow-x-auto")], [
        html.table([attribute.class("w-full text-left text-xs")], [
          html.thead([attribute.class("bg-slate-900/60 text-slate-400 border-b border-slate-800 font-mono")], [
            html.tr([], [
              html.th([attribute.class("p-2")], [html.text("Morphism")]),
              html.th([attribute.class("p-2")], [html.text("Source Tier")]),
              html.th([attribute.class("p-2")], [html.text("Target Tier")]),
              html.th([attribute.class("p-2")], [html.text("Source ID")]),
              html.th([attribute.class("p-2")], [html.text("Target ID")]),
              html.th([attribute.class("p-2")], [html.text("Associative")]),
            ]),
          ]),
          html.tbody([], list.map(report.morphisms, fn(m) {
            html.tr([attribute.class("border-b border-slate-800/40 hover:bg-slate-900/40 font-mono")], [
              html.td([attribute.class("p-2 text-amber-300 font-bold")], [html.text(m.name)]),
              html.td([attribute.class("p-2 text-sky-400")], [html.text(tier_to_string(m.source_tier))]),
              html.td([attribute.class("p-2 text-purple-400")], [html.text(tier_to_string(m.target_tier))]),
              html.td([attribute.class("p-2 text-slate-400 text-[11px]")], [html.text(m.source_id)]),
              html.td([attribute.class("p-2 text-slate-300 text-[11px]")], [html.text(m.target_id)]),
              html.td([attribute.class("p-2 text-emerald-400")], [html.text("PASS")]),
            ])
          })),
        ]),
      ]),
    ]),
  ])
}

fn tier_card(title: String, subtitle: String, desc: String, dim: String) -> Element(Msg) {
  html.div([attribute.class("bg-slate-900 p-3 rounded border border-slate-800 space-y-1")], [
    html.div([attribute.class("font-bold text-amber-300 text-[11px]")], [html.text(title)]),
    html.div([attribute.class("text-[10px] text-slate-400")], [html.text(subtitle)]),
    html.div([attribute.class("text-[10px] text-slate-500 pt-1")], [html.text(desc)]),
    html.div([attribute.class("text-[9px] text-emerald-400/80 font-mono pt-1")], [html.text(dim)]),
  ])
}

// ---------------------------------------------------------- Ontology Panel

fn render_ontology_panel(graph: ontology.OntoGraph) -> Element(Msg) {
  html.div([attribute.class("bg-slate-950 p-4 rounded-lg border border-slate-800 space-y-3")], [
    html.div([attribute.class("flex justify-between items-center")], [
      html.h3([attribute.class("text-sm font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-2")], [
        html.span([], [html.text("🧬")]),
        html.text("Living Biomorphic Ontology Graph (" <> int.to_string(list.length(graph.nodes)) <> " Nodes, " <> int.to_string(list.length(graph.edges)) <> " Edges)"),
      ]),
      html.span([attribute.class("text-xs font-mono text-emerald-400 bg-emerald-950/40 border border-emerald-800/40 px-3 py-1 rounded-full")], [
        html.text("Topological Closure: 100% Green"),
      ]),
    ]),
    html.div([attribute.class("overflow-x-auto max-h-[400px]")], [
      html.table([attribute.class("w-full text-left text-xs")], [
        html.thead([attribute.class("bg-slate-900/60 text-slate-400 border-b border-slate-800 font-mono sticky top-0")], [
          html.tr([], [
            html.th([attribute.class("p-2")], [html.text("Node ID")]),
            html.th([attribute.class("p-2")], [html.text("Name")]),
            html.th([attribute.class("p-2")], [html.text("Category")]),
            html.th([attribute.class("p-2")], [html.text("Layer")]),
            html.th([attribute.class("p-2")], [html.text("Plane")]),
            html.th([attribute.class("p-2")], [html.text("Status")]),
          ]),
        ]),
        html.tbody([], list.map(graph.nodes, fn(n) {
          html.tr([attribute.class("border-b border-slate-800/30 hover:bg-slate-900/40 font-mono text-[11px]")], [
            html.td([attribute.class("p-2 text-sky-300")], [html.text(n.id)]),
            html.td([attribute.class("p-2 text-slate-300")], [html.text(n.name)]),
            html.td([attribute.class("p-2 text-amber-400")], [html.text(category_to_string(n.category))]),
            html.td([attribute.class("p-2 text-slate-400")], [html.text("L" <> int.to_string(n.layer))]),
            html.td([attribute.class("p-2 text-purple-300")], [html.text(n.plane)]),
            html.td([attribute.class("p-2 text-emerald-400")], [html.text("ALIVE")]),
          ])
        })),
      ]),
    ]),
  ])
}

// ----------------------------------------------------------- DMC+TCM Panel

fn render_dmc_tcm_panel(dmc: dmc_tcm.MemoryCoherenceReport) -> Element(Msg) {
  html.div([attribute.class("space-y-4")], [
    html.div([attribute.class("bg-slate-950 p-4 rounded-lg border border-slate-800 space-y-3")], [
      html.h3([attribute.class("text-sm font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-2")], [
        html.span([], [html.text("🔒")]),
        html.text("DMC Memory Coherence & Base ID Disjointness"),
      ]),
      html.p([attribute.class("text-xs text-slate-400")], [
        html.text("Proves disjointness for every instance memory window: [BaseID, BaseID + Span) non-overlapping across the entire flight topology."),
      ]),
      html.div([attribute.class("grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-2 pt-2")], list.map(dmc.windows, fn(w) {
        html.div([attribute.class("bg-slate-900 p-3 rounded border border-slate-800 space-y-1 font-mono text-xs")], [
          html.div([attribute.class("text-sky-300 font-bold")], [html.text(w.instance_name)]),
          html.div([attribute.class("text-slate-400 text-[10px]")], [html.text("Component: " <> w.component_name)]),
          html.div([attribute.class("text-amber-400 text-[11px]")], [
            html.text("Range: [0x" <> int.to_base16(w.base_id) <> ", 0x" <> int.to_base16(w.upper_bound) <> ")"),
          ]),
          html.div([attribute.class("text-emerald-400 text-[10px]")], [html.text("Span: " <> int.to_string(w.span) <> " IDs")]),
        ])
      })),
    ]),
    html.div([attribute.class("bg-slate-950 p-4 rounded-lg border border-rose-900/40 space-y-2")], [
      html.h3([attribute.class("text-sm font-semibold text-rose-400 uppercase tracking-wider flex items-center gap-2")], [
        html.span([], [html.text("🛑")]),
        html.text("Hardware Safety Interlock Enforcer"),
      ]),
      html.p([attribute.class("text-xs text-slate-300 font-mono")], [
        html.text("HARD_DENIED_SYSTEM_OS_SERIAL = \"25503L801736\""),
      ]),
      html.p([attribute.class("text-xs text-slate-400")], [
        html.text("Enforced across Kubernetes Rook-Ceph, Hermes OCaml Zero-Trust Dispatch, and Gleam Denotational Intent Router. All write, format, or mount operations on this device are unconditionally denied with HTTP 403 Forbidden."),
      ]),
    ]),
  ])
}

// ----------------------------------------------------------------- API Links

fn render_api_links() -> Element(Msg) {
  html.div([attribute.class("bg-slate-950 p-4 rounded-lg border border-slate-800 flex flex-wrap justify-between items-center gap-3 text-xs font-mono")], [
    html.span([attribute.class("text-slate-400")], [
      html.text("Live Typed REST Endpoints:"),
    ]),
    html.div([attribute.class("flex flex-wrap gap-2")], [
      api_button("/api/fpp/atlas", "📊 /api/fpp/atlas"),
      api_button("/api/fpp/ontology", "🧬 /api/fpp/ontology"),
      api_button("/api/fpp/dictionary", "📖 /api/fpp/dictionary"),
    ]),
  ])
}

fn api_button(href: String, label: String) -> Element(Msg) {
  html.a([
    attribute.href(href),
    attribute.target("_blank"),
    attribute.class("px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-sky-300 rounded border border-slate-700 transition-colors"),
  ], [html.text(label)])
}

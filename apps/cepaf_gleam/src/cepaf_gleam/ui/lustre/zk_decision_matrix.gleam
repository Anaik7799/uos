//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/zk_decision_matrix</module>
////     <fsharp-lineage>Cepaf.UI.ZkDecisionMatrix.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Lustre MVU ZK Decision Matrix & MOC Explorer</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-GLM-UI-001, SC-GLM-UI-002, SC-ZK-ADR-001, SC-ROCHA-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// =============================================================================
// Types
// =============================================================================

pub type AdrRecord {
  AdrRecord(
    id: String,
    title: String,
    layer: String,
    invariant_summary: String,
    formal_oracle: String,
    file_name: String,
    tailscale_url: String,
  )
}

pub type Model {
  Model(
    search_query: String,
    layer_filter: Option(String),
    selected_adr_id: Option(String),
    adrs: List(AdrRecord),
  )
}

pub type Msg {
  SetSearch(String)
  SetLayerFilter(Option(String))
  SelectAdr(String)
  ClearFilter
}

// =============================================================================
// Canonical 16 ADRs Inventory
// =============================================================================

pub fn all_adrs() -> List(AdrRecord) {
  [
    AdrRecord("ADR-001", "Closed Rete Fact Schema & Strict Typing", "#fractal-l0", "Compile-time closed fact schemas; dynamic shapeless facts barred.", "Lean 4 / Gospel", "20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md"),
    AdrRecord("ADR-002", "Embedded NUL Ingress Trap & Allocation Containment", "#fractal-l1", "Zero-Trust agent dispatch hook trapping NUL bytes (abort code -2).", "Cryptokit SHA-256", "20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md"),
    AdrRecord("ADR-003", "Z3 SMT Solver Isolation via Bounded Worker Subprocess", "#fractal-l2", "Solver execution strictly confined to bounded sub-process with timeout.", "Process Reaper / Z3", "20260904-150145-adr-003-z3-smt-solver-isolation-via-bounded-worker-subprocess.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150145-adr-003-z3-smt-solver-isolation-via-bounded-worker-subprocess.md"),
    AdrRecord("ADR-004", "Two-Lattice STM for Safe Shared Mutex Leases", "#fractal-l3", "Single-writer exclusive lease mutex without lock poisoning.", "TwoLattice_STM.lean", "20260904-150147-adr-004-two-lattice-stm-for-safe-shared-mutex-leases.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150147-adr-004-two-lattice-stm-for-safe-shared-mutex-leases.md"),
    AdrRecord("ADR-005", "Topological Sheaf Consistency Across Distributed Memory Planes", "#fractal-l4", "Gluing axiom satisfied across BEAM, SQLite, and ZigVM VFS.", "Sheaf Algebra", "20260904-150150-adr-005-topological-sheaf-consistency-across-distributed-memory-planes.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150150-adr-005-topological-sheaf-consistency-across-distributed-memory-planes.md"),
    AdrRecord("ADR-006", "13D Spatiotemporal Traceability Vector Space Conservation", "#fractal-l5", "Invariance under coordinate transform; conservation of trace vector.", "Traceability.lean", "20260904-150153-adr-006-13d-spatiotemporal-traceability-vector-space-conservation.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150153-adr-006-13d-spatiotemporal-traceability-vector-space-conservation.md"),
    AdrRecord("ADR-007", "Pure Erlang 2D Vector Math & Zero-Muda Graphene Elimination", "#fractal-l1", "Pure BEAM Erlang math; 0 foreign NIF shared libraries.", "EUnit Parity", "20260904-150155-adr-007-pure-erlang-2d-vector-math-and-zero-muda-graphene-elimination.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150155-adr-007-pure-erlang-2d-vector-math-and-zero-muda-graphene-elimination.md"),
    AdrRecord("ADR-008", "Permanent Hard-Denied Storage Serial Lock for System Root NVMe", "#fractal-l0", "HARD_DENIED_SYSTEM_OS_SERIAL = '25503L801736' enforced in Rust spec.", "Rook-Ceph Guard", "20260904-150158-adr-008-permanent-hard-denied-storage-serial-lock-for-system-root-nvme.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150158-adr-008-permanent-hard-denied-storage-serial-lock-for-system-root-nvme.md"),
    AdrRecord("ADR-009", "Descriptor-Relative Race-Free VFS Backend for Deterministic Engine", "#fractal-l2", "Descriptor-relative openat/unlinkat calls preventing symlink race conditions.", "ZigVM Kernel", "20260904-150201-adr-009-descriptor-relative-race-free-vfs-backend-for-deterministic-engine.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150201-adr-009-descriptor-relative-race-free-vfs-backend-for-deterministic-engine.md"),
    AdrRecord("ADR-010", "Modular MAX Inference Quarantined to Supervised Daemon", "#fractal-l4", "Python interpreter quarantined strictly to MaxWorker daemon over stdio RPC.", "OTP Port Driver", "20260904-150204-adr-010-modular-max-inference-quarantined-to-supervised-daemon.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150204-adr-010-modular-max-inference-quarantined-to-supervised-daemon.md"),
    AdrRecord("ADR-011", "Differential Testing Parity Oracles with Gospel Specifications", "#fractal-l5", "Differential equivalence between Hermes OCaml oracle and pure Gleam engine.", "Dune Oracle", "20260904-150207-adr-011-differential-testing-parity-oracles-with-gospel-specifications.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150207-adr-011-differential-testing-parity-oracles-with-gospel-specifications.md"),
    AdrRecord("ADR-012", "Standalone Non-Colocated Jujutsu Monorepo Architecture", "#fractal-l6", "Standalone .jj/ version control; native git mutation commands strictly barred.", "jj status check", "20260904-150210-adr-012-standalone-non-colocated-jujutsu-monorepo-architecture.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150210-adr-012-standalone-non-colocated-jujutsu-monorepo-architecture.md"),
    AdrRecord("ADR-013", "Multi-Layer OTP 29 Root 4-Domain Supervisor Topology", "#fractal-l3", "Apps, Engines, Services, Intelligence supervised with isolated restart budgets.", "uos_sup.gleam", "20260904-150213-adr-013-multi-layer-otp-29-root-4-domain-supervisor-topology.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150213-adr-013-multi-layer-otp-29-root-4-domain-supervisor-topology.md"),
    AdrRecord("ADR-014", "Zenoh Pub/Sub Sole Transport for Telemetry, OTel & MCP (ZMOF)", "#fractal-l4", "Single unified transport bus indrajaal/** for all mesh communication.", "Zenoh Router", "20260904-150216-adr-014-zenoh-pub-sub-sole-transport-for-telemetry-otel-and-mcp.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150216-adr-014-zenoh-pub-sub-sole-transport-for-telemetry-otel-and-mcp.md"),
    AdrRecord("ADR-015", "Tri-Sovereign Governance Consensus via AGY, Claude & Codex", "#fractal-l6", "Three independent model families advise, audit, and ratify invariants.", "Tri-Key Ledger", "20260904-150219-adr-015-tri-sovereign-governance-consensus-via-agy-claude-and-codex.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150219-adr-015-tri-sovereign-governance-consensus-via-agy-claude-and-codex.md"),
    AdrRecord("ADR-016", "Universal Tailscale FQDN Web Navigation & Clickable URL Parity", "#fractal-l5", "Every screen and document reachable via http://nas-1.tail55d152.ts.net:4100.", "Wisp Router", "20260904-150222-adr-016-universal-tailscale-fqdn-web-navigation-and-clickable-url-parity.md", "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150222-adr-016-universal-tailscale-fqdn-web-navigation-and-clickable-url-parity.md"),
  ]
}

// =============================================================================
// MVU Cycle
// =============================================================================

pub fn init() -> Model {
  Model(
    search_query: "",
    layer_filter: None,
    selected_adr_id: Some("ADR-001"),
    adrs: all_adrs(),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    SetSearch(q) -> Model(..model, search_query: q)
    SetLayerFilter(layer) -> Model(..model, layer_filter: layer)
    SelectAdr(id) -> Model(..model, selected_adr_id: Some(id))
    ClearFilter -> Model(..model, search_query: "", layer_filter: None)
  }
}

// =============================================================================
// View
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  let filtered = filter_adrs(model)

  html.div(
    [attribute.class("zk-decision-matrix bg-slate-900 border border-slate-700 rounded-xl p-6 text-white shadow-2xl")],
    [
      render_header(),
      render_ascii_adr_hierarchy(),
      render_layer_chips(model.layer_filter),
      render_search_bar(model.search_query),
      html.div([attribute.class("grid grid-cols-1 lg:grid-cols-3 gap-6 mt-4")], [
        html.div([attribute.class("lg:col-span-2 overflow-x-auto")], [
          render_adr_table(filtered, model.selected_adr_id),
        ]),
        html.div([attribute.class("lg:col-span-1")], [
          render_adr_detail(model.adrs, model.selected_adr_id),
        ]),
      ]),
    ],
  )
}

fn render_ascii_adr_hierarchy() -> Element(Msg) {
  let ascii_art =
"  +-------------------------------------------------------------------------------------------------+
  |                    ZETTELKASTEN 16 PERMANENT ARCHITECTURAL DECISIONS (L0 - L6)                  |
  +-------------------------------------------------------------------------------------------------+
  | L0 CONSTITUTIONAL | ADR-001 (Closed Rete Schema) & ADR-008 (Root NVMe 25503L801736 Locked)      |
  | L1 BOUNDED ATOMIC | ADR-002 (NUL Ingress Trap -2) & ADR-007 (Zero-Muda Pure Erlang 2D Vector)   |
  | L2 DETERMINISTIC  | ADR-003 (Bounded Z3 Worker) & ADR-009 (Descriptor-Relative Race-Free VFS)   |
  | L3 TRANSACTION    | ADR-004 (Two-Lattice STM Mutex) & ADR-013 (Multi-Layer OTP 29 Root Sup)     |
  | L4 SYSTEM CONTROL | ADR-005 (Topological Sheaf) & ADR-010 (MAX Quarantine) & ADR-014 (ZMOF Bus) |
  | L5 COGNITIVE OODA | ADR-006 (13D Spatiotemporal Vector) & ADR-011 (Dune Gospel Oracles) & ADR-016|
  | L6 ECOSYSTEM GOV  | ADR-012 (Standalone Jujutsu Monorepo) & ADR-015 (Tri-Sovereign Consensus)   |
  +-------------------------------------------------------------------------------------------------+"

  html.div([attribute.class("my-3 bg-slate-950 border border-slate-800 rounded-lg p-3 font-mono text-[11px] overflow-x-auto")], [
    html.pre([attribute.class("text-emerald-300 leading-tight select-all")], [html.text(ascii_art)]),
  ])
}

fn filter_adrs(model: Model) -> List(AdrRecord) {
  model.adrs
  |> list.filter(fn(adr) {
    case model.layer_filter {
      None -> True
      Some(l) -> adr.layer == l
    }
  })
  |> list.filter(fn(adr) {
    case string.trim(model.search_query) {
      "" -> True
      q ->
        string.contains(string.lowercase(adr.title), string.lowercase(q))
        || string.contains(string.lowercase(adr.id), string.lowercase(q))
        || string.contains(string.lowercase(adr.invariant_summary), string.lowercase(q))
    }
  })
}

fn render_header() -> Element(Msg) {
  html.div([attribute.class("flex justify-between items-center mb-5 pb-3 border-b border-slate-800")], [
    html.div([], [
      html.h2([attribute.class("text-xl font-bold text-amber-400 flex items-center gap-2")], [
        html.span([], [html.text("🛡️")]),
        html.text("Zettelkasten Architectural Decision Records (16 ADRs)"),
      ]),
      html.p([attribute.class("text-xs text-slate-400 mt-1")], [
        html.text("Permanent Architectural Invariants, Differential Oracles & Gospel Specifications"),
      ]),
    ]),
    html.div([attribute.class("flex items-center gap-2")], [
      html.span([attribute.class("px-3 py-1 text-xs font-mono font-bold rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/40")], [
        html.text("16/16 RATIFIED"),
      ]),
    ]),
  ])
}

fn render_layer_chips(active_layer: Option(String)) -> Element(Msg) {
  let layers = [
    "#fractal-l0",
    "#fractal-l1",
    "#fractal-l2",
    "#fractal-l3",
    "#fractal-l4",
    "#fractal-l5",
    "#fractal-l6",
  ]

  html.div([attribute.class("flex items-center gap-2 text-xs flex-wrap mb-3")], [
    html.span([attribute.class("text-slate-500 text-[11px]")], [html.text("Fractal Layer:")]),
    html.button(
      [
        attribute.class("px-2.5 py-1 rounded text-[11px] font-mono border " <> case active_layer {
          None -> "bg-slate-700 text-white border-slate-600"
          Some(_) -> "bg-slate-900 text-slate-400 border-slate-800 hover:text-white"
        }),
        event.on_click(SetLayerFilter(None)),
      ],
      [html.text("All Layers (L0-L6)")],
    ),
    ..list.map(layers, fn(l) {
      let is_selected = active_layer == Some(l)
      let cls = case is_selected {
        True -> "bg-emerald-500/30 text-emerald-300 border-emerald-400/80 font-bold"
        False -> "bg-slate-900/80 text-slate-400 border-slate-800 hover:text-emerald-300"
      }
      html.button(
        [
          attribute.class("px-2 py-1 rounded text-[11px] font-mono border transition-all " <> cls),
          event.on_click(SetLayerFilter(Some(l))),
        ],
        [html.text(l)],
      )
    })
  ])
}

fn render_search_bar(query: String) -> Element(Msg) {
  html.div([attribute.class("mb-3")], [
    html.input([
      attribute.type_("text"),
      attribute.placeholder("Search ADR by ID, title, or invariant..."),
      attribute.value(query),
      attribute.class("w-full bg-slate-950 border border-slate-700 rounded-lg px-4 py-2 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-amber-400"),
      event.on_input(SetSearch),
    ]),
  ])
}

fn render_adr_table(adrs: List(AdrRecord), selected_id: Option(String)) -> Element(Msg) {
  html.table([attribute.class("w-full text-left text-xs border-collapse")], [
    html.thead([], [
      html.tr([attribute.class("bg-slate-950 text-slate-400 border-b border-slate-800")], [
        html.th([attribute.class("py-2.5 px-3 font-semibold")], [html.text("ADR ID")]),
        html.th([attribute.class("py-2.5 px-3 font-semibold")], [html.text("Layer")]),
        html.th([attribute.class("py-2.5 px-3 font-semibold")], [html.text("Title & Decision Summary")]),
        html.th([attribute.class("py-2.5 px-3 font-semibold")], [html.text("Formal Oracle")]),
      ]),
    ]),
    html.tbody([], 
      list.map(adrs, fn(adr) {
        let is_sel = selected_id == Some(adr.id)
        let row_cls = case is_sel {
          True -> "bg-amber-500/15 border-amber-500/50"
          False -> "hover:bg-slate-800/40 border-slate-800/60"
        }
        html.tr(
          [
            attribute.class("border-b cursor-pointer transition-colors " <> row_cls),
            event.on_click(SelectAdr(adr.id)),
          ],
          [
            html.td([attribute.class("py-2.5 px-3 font-mono text-amber-400 font-bold")], [html.text(adr.id)]),
            html.td([attribute.class("py-2.5 px-3 font-mono text-slate-400 text-[11px]")], [html.text(adr.layer)]),
            html.td([attribute.class("py-2.5 px-3 text-slate-200 font-medium")], [html.text(adr.title)]),
            html.td([attribute.class("py-2.5 px-3 font-mono text-emerald-400 text-[11px]")], [html.text(adr.formal_oracle)]),
          ],
        )
      })
    ),
  ])
}

fn render_adr_detail(adrs: List(AdrRecord), selected_id: Option(String)) -> Element(Msg) {
  let selected = case selected_id {
    None -> list.first(adrs) |> option.from_result
    Some(id) -> list.find(adrs, fn(a) { a.id == id }) |> option.from_result
  }

  case selected {
    None ->
      html.div([attribute.class("bg-slate-950/80 border border-slate-800 rounded-lg p-6 text-center text-slate-500 text-xs italic")], [
        html.text("Select an ADR to view its full formal invariant."),
      ])
    Some(adr) ->
      html.div([attribute.class("bg-slate-950/90 border border-slate-800 rounded-lg p-5")], [
        html.div([attribute.class("flex justify-between items-center mb-3 pb-2 border-b border-slate-800")], [
          html.span([attribute.class("px-2.5 py-1 text-xs font-mono font-bold rounded bg-amber-500/20 text-amber-300 border border-amber-500/40")], [
            html.text(adr.id),
          ]),
          html.span([attribute.class("px-2 py-0.5 text-xs font-mono rounded bg-blue-500/20 text-blue-300 border border-blue-500/40")], [
            html.text(adr.layer),
          ]),
        ]),
        html.h3([attribute.class("text-sm font-bold text-slate-100 mb-2")], [html.text(adr.title)]),
        html.div([attribute.class("bg-slate-900 border border-slate-800 rounded p-3 mb-4 text-xs text-slate-300 leading-relaxed")], [
          html.div([attribute.class("text-[10px] uppercase font-bold text-amber-400/80 mb-1")], [html.text("Core Invariant")]),
          html.text(adr.invariant_summary),
        ]),
        html.div([attribute.class("mb-4 space-y-2 text-xs")], [
          html.div([attribute.class("flex justify-between text-slate-400")], [
            html.span([], [html.text("Formal Oracle:")]),
            html.span([attribute.class("font-mono text-emerald-400 font-semibold")], [html.text(adr.formal_oracle)]),
          ]),
          html.div([attribute.class("flex justify-between text-slate-400")], [
            html.span([], [html.text("Source Doc:")]),
            html.span([attribute.class("font-mono text-slate-300 text-[10px] truncate max-w-[160px]")], [html.text(adr.file_name)]),
          ]),
        ]),
        html.a([
          attribute.href(adr.tailscale_url),
          attribute.target("_blank"),
          attribute.class("block w-full text-center py-2 px-3 rounded bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-xs transition-colors shadow-lg"),
        ], [
          html.text("View Ratified Markdown Doc ↗"),
        ]),
      ])
  }
}

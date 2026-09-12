//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/knowledge_explorer</module>
////     <fsharp-lineage>Cepaf.UI.KnowledgeExplorer.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Lustre MVU Knowledge & Wiki Transclusion Explorer</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-GLM-UI-001, SC-GLM-UI-002, SC-KM-TRIAD-001, SC-ROCHA-001, SC-MUDA-001
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

pub type KnowledgeTab {
  TabWikiCorpus
  TabZkInvariants
  TabLivingOntology
  TabBiosemiotics
}

pub type KnowledgeItem {
  KnowledgeItem(
    id: String,
    title: String,
    category: String,
    fractal_layer: String,
    summary: String,
    transclusions: List(String),
    tags: List(String),
    tailscale_url: String,
  )
}

pub type Model {
  Model(
    search_query: String,
    active_tab: KnowledgeTab,
    selected_id: Option(String),
    active_tag_filter: Option(String),
    items: List(KnowledgeItem),
  )
}

pub type Msg {
  SetSearch(String)
  SelectTab(KnowledgeTab)
  SelectItem(String)
  FilterByTag(Option(String))
  ClearSelection
}

// =============================================================================
// Initial Knowledge Catalog
// =============================================================================

pub fn default_items() -> List(KnowledgeItem) {
  [
    // =========================================================================
    // 1. Wiki Corpus
    // =========================================================================
    KnowledgeItem(
      id: "WIKI-001",
      title: "Hermes Wiki Master Corpus Index",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l5",
      summary: "Living knowledge graph index with Gospel contract bindings, 623 documents, and 13D trace coordinates.",
      transclusions: [
        "[[wiki:20260905-1801-uos-zk-km-corpus-index]]",
        "[[zk:20260905-1801-moc-uos-unified-master]]",
      ],
      tags: ["#km-triad", "#rocha-semiotics", "#cybernetics", "#zero-muda"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/wiki",
    ),
    KnowledgeItem(
      id: "WIKI-002",
      title: "UOS Holarchy Map of Content & 158-Holon Census",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l6",
      summary: "Multi-agent holonic hierarchy across 158 holons and all 10 fractal layers L0 to L9.",
      transclusions: [
        "[[wiki:20260907-1645-moc-uos-holarchy]]",
        "[[zk:ADR-064]]",
      ],
      tags: ["#km-triad", "#cybernetics", "#fractal-l6"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1645-moc-uos-holarchy.md",
    ),
    KnowledgeItem(
      id: "WIKI-003",
      title: "NASA JPL F Prime Aerospace Agent Ecosystem & Taxonomy",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l4",
      summary: "Transmutation of aerospace flight software patterns into pure BEAM OTP 29 agentic actors.",
      transclusions: [
        "[[wiki:20260906-0955-uos-fprime-agent-ecosystem-and-taxonomy]]",
        "[[zk:ADR-019]]",
      ],
      tags: ["#km-triad", "#cybernetics", "#fractal-l4"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260906-0955-uos-fprime-agent-ecosystem-and-taxonomy.md",
    ),
    KnowledgeItem(
      id: "WIKI-004",
      title: "Harness-Bionic to UOS Agentic Ecosystem Mapping & Integration",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l5",
      summary: "Multi-agent skills, superpowers, and operational SOP mapping into the UOS monorepo.",
      transclusions: [
        "[[wiki:20260906-0955-uos-harness-bionic-import-and-agentic-architecture]]",
        "[[zk:ADR-020]]",
      ],
      tags: ["#km-triad", "#zero-muda", "#fractal-l5"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260906-0955-uos-harness-bionic-import-and-agentic-architecture.md",
    ),
    KnowledgeItem(
      id: "WIKI-005",
      title: "Sa-Plan Fractal Jidoka & TPS Universal Execution Authority Guide",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l0",
      summary: "Andon stop line SC-JIDOKA-001 and canonical task claiming authority var/sa-plan/uos.sqlite3.",
      transclusions: [
        "[[wiki:20260907-1530-uos-sa-plan-fractal-jidoka-tps-guide]]",
        "[[zk:ADR-066]]",
      ],
      tags: ["#km-triad", "#zero-muda", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1530-uos-sa-plan-fractal-jidoka-tps-guide.md",
    ),
    KnowledgeItem(
      id: "WIKI-006",
      title: "Sovereign Telegram Gleam Harness Architecture Guide",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l5",
      summary: "Bi-directional bridge dispatching human Telegram commands into Gleam/OTP 29 cognitive actors.",
      transclusions: [
        "[[wiki:20260909-2035-uos-telegram-gleam-harness-architecture]]",
        "[[zk:ADR-098]]",
      ],
      tags: ["#km-triad", "#cybernetics", "#fractal-l5"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260909-2035-uos-telegram-gleam-harness-architecture.md",
    ),
    KnowledgeItem(
      id: "WIKI-007",
      title: "Maximal Gleam/OTP 29 Autonomous Cognitive Architecture",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l5",
      summary: "In-process OODA loops and Prajna circuit breaker substrate with universal C3I logging.",
      transclusions: [
        "[[wiki:20260909-2100-uos-maximal-gleam-cognitive-architecture]]",
        "[[zk:ADR-099]]",
      ],
      tags: ["#km-triad", "#cybernetics", "#fractal-l5"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260909-2100-uos-maximal-gleam-cognitive-architecture.md",
    ),
    KnowledgeItem(
      id: "WIKI-008",
      title: "High-Performance Native NIFs & AGY Sovereign Cognitive Engine",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l1",
      summary: "Bounded deterministic native C-ABI kernels and Lyapunov-stabilized AGY cognitive copilot.",
      transclusions: [
        "[[wiki:20260909-2200-uos-performance-nifs-telegram-agy-architecture]]",
        "[[zk:ADR-100]]",
      ],
      tags: ["#km-triad", "#zero-muda", "#fractal-l1"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260909-2200-uos-performance-nifs-telegram-agy-architecture.md",
    ),
    KnowledgeItem(
      id: "WIKI-009",
      title: "UOS Universal Risk Prioritization & Safety Checkers Guide",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l0",
      summary: "Criticality x STPA x FMEA x Dependency x Impact matrix with fail-closed preflights.",
      transclusions: [
        "[[wiki:20260907-1559-risk-prioritization-guide]]",
        "[[zk:ADR-UOS-RISK]]",
      ],
      tags: ["#km-triad", "#cybernetics", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260907-1559-risk-prioritization-guide.md",
    ),
    KnowledgeItem(
      id: "WIKI-010",
      title: "Unified System Ontology, Living KM Triad & Dictionary Guide",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l8",
      summary: "Exhaustive semantic dictionary linking Sanskrit holonic terms, formal theorems, and actor IDs.",
      transclusions: [
        "[[wiki:20260909-0640-uos-system-ontology-dictionary-and-glossary-guide]]",
        "[[zk:ADR-097]]",
      ],
      tags: ["#km-triad", "#rocha-semiotics", "#fractal-l8"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/wiki/20260909-0640-uos-system-ontology-dictionary-and-glossary-guide.md",
    ),

    // =========================================================================
    // 2. ZK Invariants & ADRs
    // =========================================================================
    KnowledgeItem(
      id: "MOC-001",
      title: "UOS Unified Master Map of Content (MOC)",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Root Map of Content indexing all 115 ADRs and foundational architectural decisions.",
      transclusions: [
        "[[zk:20260905-1801-moc-uos-unified-master]]",
        "[[wiki:20260905-1801-uos-zk-km-corpus-index]]",
      ],
      tags: ["#zk-adr", "#km-triad", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260905-1801-moc-uos-unified-master.md",
    ),
    KnowledgeItem(
      id: "ADR-001",
      title: "Closed Rete Fact Schema & Strict Typing",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Rejects dynamically shaped facts; compile-time closed Rete-UL typing.",
      transclusions: ["[[zk:ADR-001]]", "[[wiki:dmc-tcm-mandate]]"],
      tags: ["#zk-adr", "#rocha-semiotics", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md",
    ),
    KnowledgeItem(
      id: "ADR-002",
      title: "Embedded NUL Ingress Trap & Allocation Containment",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l1",
      summary: "Zero-Trust agent dispatch hook trapping NUL bytes with immediate abort code -2.",
      transclusions: ["[[zk:ADR-002]]", "[[wiki:agent-dispatch-hook]]"],
      tags: ["#zk-adr", "#cybernetics", "#fractal-l1"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md",
    ),
    KnowledgeItem(
      id: "ADR-003",
      title: "Pure 100-Byte Binary SQLite Header Verification (Rule R31)",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l3",
      summary: "Direct binary file format validation ensuring database integrity without third-party drivers.",
      transclusions: ["[[zk:ADR-003]]", "[[wiki:sqlite-parity]]"],
      tags: ["#zk-adr", "#zero-muda", "#fractal-l3"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-150145-adr-003-pure-100-byte-binary-sqlite-header-verification-rule-r31.md",
    ),
    KnowledgeItem(
      id: "ADR-006",
      title: "Twelve-Pillar Fractal Architecture Composability",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Constitutional composability model across all 12 system pillars with fail-closed safety.",
      transclusions: ["[[zk:ADR-006]]", "[[wiki:twelve-pillars]]"],
      tags: ["#zk-adr", "#cybernetics", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-153122-adr-006-twelve-pillar-fractal-architecture-composability-and-multi-paradigm-integration.md",
    ),
    KnowledgeItem(
      id: "ADR-016",
      title: "Master Fractal System Integration & 7-Level Granularity Closure",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Tripartite ratification across L0 to L7 with full functional mapping KPIs.",
      transclusions: ["[[zk:ADR-016]]", "[[wiki:master-integration]]"],
      tags: ["#zk-adr", "#km-triad", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260904-164632-adr-016-master-fractal-system-integration-7-level-granularity-closure-and-tripartite-ratification.md",
    ),
    KnowledgeItem(
      id: "ADR-048",
      title: "Hermes-Bionic Full Systemic Integration & Multidimensional Actor Ecosystem",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l5",
      summary: "Ingestion of bionic agentic workflows and Gospel contract validation.",
      transclusions: ["[[zk:ADR-048]]", "[[wiki:20260906-1700-uos-hermes-bionic-full-integration-wiki]]"],
      tags: ["#zk-adr", "#cybernetics", "#fractal-l5"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260906-1700-adr-048-hermes-bionic-full-integration-ratification.md",
    ),
    KnowledgeItem(
      id: "ADR-066",
      title: "Sa-Plan Exclusivity, Fractal Jidoka & TPS Universal Authority",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Sole canonical task scheduling authority with fail-closed Andon stop lines.",
      transclusions: ["[[zk:ADR-066]]", "[[wiki:20260907-1530-uos-sa-plan-fractal-jidoka-tps-guide]]"],
      tags: ["#zk-adr", "#zero-muda", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-1530-adr-066-sa-plan-fractal-jidoka-tps-and-universal-execution-authority.md",
    ),
    KnowledgeItem(
      id: "ADR-071",
      title: "ZMOF Zenoh Backplane & Hermes Wiki Transclusion (NOT_ADMITTED)",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l5",
      summary: "Quarantined record asserting EV-94; preserved unmodified per provenance caveat.",
      transclusions: ["[[zk:ADR-071]]", "[[wiki:provenance-integrity]]"],
      tags: ["#zk-adr", "#km-triad", "#fractal-l5"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260907-2030-adr-071-zmof-zenoh-backplane-wiki-transclusion-and-ev94-ratification.md",
    ),
    KnowledgeItem(
      id: "ADR-087",
      title: "Provenance Integrity, the KM Gate & Mojo Metrics Kernel",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Machine enforcement of EV ceiling 93 and ADR sequence contiguity via tools/km-gate.",
      transclusions: ["[[zk:ADR-087]]", "[[wiki:20260908-0927-uos-provenance-integrity-and-km-gate-guide]]"],
      tags: ["#zk-adr", "#km-triad", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260908-0927-adr-087-provenance-integrity-km-gate-and-mojo-metrics-kernel.md",
    ),
    KnowledgeItem(
      id: "ADR-098",
      title: "Sovereign Telegram Message Delegation to UOS Gleam Harness",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l5",
      summary: "Telegram bot daemon delegation to supervised Gleam OTP 29 cognitive actors.",
      transclusions: ["[[zk:ADR-098]]", "[[wiki:20260909-2035-uos-telegram-gleam-harness-architecture]]"],
      tags: ["#zk-adr", "#cybernetics", "#fractal-l5"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260909-2035-adr-098-sovereign-telegram-gleam-harness-delegation.md",
    ),
    KnowledgeItem(
      id: "ADR-111",
      title: "Saṁvid Vajravyūha: Sovereign Defense Holarchy & Zero-Trust Grid",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l6",
      summary: "Multi-layered cybernetic defense mesh with cryptographic ingress interception.",
      transclusions: ["[[zk:ADR-111]]", "[[wiki:sovereign-defense]]"],
      tags: ["#zk-adr", "#cybernetics", "#fractal-l6"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260911-0815-adr-111-samvid-vajravyuha-sovereign-defense-holarchy.md",
    ),
    KnowledgeItem(
      id: "ADR-115",
      title: "SC-JOURNAL-v3: Anticipatory Epistemic Ledger Architecture",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "13-section journal evaluated against 7 verification engines (ACH disconfirmation, Brier scores).",
      transclusions: ["[[zk:ADR-115]]", "[[wiki:sc-journal-v3]]"],
      tags: ["#zk-adr", "#km-triad", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260912-0745-adr-115-sc-journal-v3-anticipatory-epistemic-ledger.md",
    ),

    // =========================================================================
    // 3. Living Ontology
    // =========================================================================
    KnowledgeItem(
      id: "ONTO-001",
      title: "C3I STAMP/STPA Safety Lattice Hub",
      category: "Living Ontology",
      fractal_layer: "#fractal-l4",
      summary: "128-bit W3C OTel trace correlation and hazard control loops across all subcomponents.",
      transclusions: ["[[wiki:stpa-safety-protocol]]", "[[zk:ADR-010]]"],
      tags: ["#km-triad", "#cybernetics", "#fractal-l4"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/ontology",
    ),
    KnowledgeItem(
      id: "ONTO-002",
      title: "Universal 18-Checkpoint Comprehensive Verification Checklist (SC-CHECKLIST-001)",
      category: "Living Ontology",
      fractal_layer: "#fractal-l0",
      summary: "5 domains, 18 checkpoints verified across every screen, document, and release gate.",
      transclusions: ["[[wiki:comprehensive-checklist-contract]]", "[[zk:ADR-087]]"],
      tags: ["#km-triad", "#zero-muda", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/checklist",
    ),
    KnowledgeItem(
      id: "ONTO-003",
      title: "Universal Structured Telemetry & OTel-over-Zenoh (OoZ)",
      category: "Living Ontology",
      fractal_layer: "#fractal-l7",
      summary: "W3C 128-bit trace correlation with microsecond UTC ISO 8601 timestamps ending in 'Z'.",
      transclusions: ["[[wiki:c3i-observability]]", "[[zk:ADR-004]]"],
      tags: ["#km-triad", "#cybernetics", "#fractal-l7"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/telemetry",
    ),
    KnowledgeItem(
      id: "ONTO-004",
      title: "Saṁvid Sarvasādhana: Universal Resource Fabric & Heterogeneous Mesh",
      category: "Living Ontology",
      fractal_layer: "#fractal-l4",
      summary: "Cross-host resource coordination across NAS-1, VM-1, and WSL2 secondary compute nodes.",
      transclusions: ["[[zk:ADR-113]]", "[[wiki:resource-fabric]]"],
      tags: ["#km-triad", "#cybernetics", "#fractal-l4"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260911-0930-adr-113-samvid-sarvasadhana-resource-fabric.md",
    ),
    KnowledgeItem(
      id: "ONTO-005",
      title: "Saṁvid Kendrīkṛta-Vyūha: Centralized Monorepo Authority & Distributed Run",
      category: "Living Ontology",
      fractal_layer: "#fractal-l0",
      summary: "Single immutable Jujutsu monorepo source of truth executing across distributed mesh actors.",
      transclusions: ["[[zk:ADR-114]]", "[[wiki:monorepo-authority]]"],
      tags: ["#km-triad", "#zero-muda", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/zk/20260911-1000-adr-114-centralized-code-distributed-run.md",
    ),

    // =========================================================================
    // 4. Biosemiotics & Cybernetics
    // =========================================================================
    KnowledgeItem(
      id: "BIO-001",
      title: "Rocha Biosemiotic Cybernetics Lattice (SC-ROCHA-001)",
      category: "Biosemiotics",
      fractal_layer: "#fractal-l6",
      summary: "Von Foerster self-referential closure and Pattee epistemic cut with dual token/rate semantics.",
      transclusions: ["[[wiki:rocha-semiotics]]", "[[zk:MOC-BIO]]"],
      tags: ["#rocha-semiotics", "#cybernetics", "#km-triad"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md",
    ),
    KnowledgeItem(
      id: "BIO-002",
      title: "Grand Synthesis Review Tome (Wiki, ZK & KM Triad)",
      category: "Biosemiotics",
      fractal_layer: "#fractal-l5",
      summary: "Exhaustive synthesis of cybernetic feedback, Lustre MVU, and zero-muda knowledge management.",
      transclusions: ["[[wiki:20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km]]", "[[zk:ADR-006]]"],
      tags: ["#rocha-semiotics", "#cybernetics", "#km-triad"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md",
    ),
    KnowledgeItem(
      id: "BIO-003",
      title: "Master Encyclopedia Tome (Universal Knowledge Triad)",
      category: "Biosemiotics",
      fractal_layer: "#fractal-l8",
      summary: "Definitive 10-layer architectural encyclopedia covering all language boundaries and proof kernels.",
      transclusions: ["[[wiki:20260905-2025-uos-master-encyclopedia-tome-wiki-zk-km]]", "[[zk:ADR-016]]"],
      tags: ["#km-triad", "#rocha-semiotics", "#zero-muda"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-2025-uos-master-encyclopedia-tome-wiki-zk-km.md",
    ),
    KnowledgeItem(
      id: "BIO-004",
      title: "State-of-the-Art Web, Wiki & ZK Semantics Specification",
      category: "Biosemiotics",
      fractal_layer: "#fractal-l5",
      summary: "Formal specification of Rocha token/rate decoupling and transclusion card WIKI-001 semantics.",
      transclusions: ["[[wiki:20260912-1050-uos-unified-web-wiki-zk-semantics-and-component-specification]]", "[[zk:ADR-115]]"],
      tags: ["#rocha-semiotics", "#cybernetics", "#zero-muda"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/design/20260912-1050-uos-unified-web-wiki-zk-semantics-and-component-specification.md",
    ),
  ]
}

// =============================================================================
// MVU Cycle
// =============================================================================

pub fn init() -> Model {
  Model(
    search_query: "",
    active_tab: TabWikiCorpus,
    selected_id: None,
    active_tag_filter: None,
    items: default_items(),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    SetSearch(q) -> Model(..model, search_query: q)
    SelectTab(tab) -> Model(..model, active_tab: tab, selected_id: None)
    SelectItem(id) -> Model(..model, selected_id: Some(id))
    FilterByTag(tag) -> Model(..model, active_tag_filter: tag)
    ClearSelection -> Model(..model, selected_id: None)
  }
}

// =============================================================================
// View Functions
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  let filtered = filter_items(model)

  html.div(
    [
      attribute.class(
        "knowledge-explorer bg-slate-900 border border-slate-700 rounded-xl p-6 text-white shadow-2xl",
      ),
    ],
    [
      render_header(),
      render_tabs(model.active_tab),
      render_ascii_triad(),
      render_search_bar(model),
      render_tag_filter_strip(model.active_tag_filter),
      html.div([attribute.class("grid grid-cols-1 md:grid-cols-3 gap-6 mt-6")], [
        html.div(
          [attribute.class("md:col-span-1 border-r border-slate-800 pr-4")],
          [
            render_items_list(filtered, model.selected_id),
          ],
        ),
        html.div([attribute.class("md:col-span-2 pl-2")], [
          render_inspector(model.items, model.selected_id),
        ]),
      ]),
    ],
  )
}

fn render_ascii_triad() -> Element(Msg) {
  let ascii_art =
    "  +-------------------------------------------------------------------------------------------------+
  |                       UNIFIED KNOWLEDGE MANAGEMENT (KM) TRIAD ARCHITECTURE                      |
  +--------------------------------+--------------------------------+-------------------------------+
  |        1. HERMES WIKI          |          2. ZIGVM ZK           |       3. LIVING ONTOLOGY      |
  |  Gospel Verification Contracts |  16 Permanent ADR Decisions    |  STAMP / STPA Safety Lattices |
  |  Transclusion AST & TyXML      |  12 Maps of Content (MOCs)     |  128-bit W3C OTel Tracing     |
  |  [[wiki:...]] Syntax Engine    |  [[zk:...]] Invariant System   |  SQLite Append-Only Ledgers   |
  +--------------------------------+--------------------------------+-------------------------------+
                   ^                                ^                               ^
                   |                                |                               |
                   +==== BIOSEMIOTIC TRANSCLUSION & CYBERNETIC CLOSURE MESH ========+"

  html.div(
    [
      attribute.class(
        "my-3 bg-slate-950 border border-slate-800 rounded-lg p-3 font-mono text-[11px] overflow-x-auto",
      ),
    ],
    [
      html.pre([attribute.class("text-amber-300 leading-tight select-all")], [
        html.text(ascii_art),
      ]),
    ],
  )
}

fn filter_items(model: Model) -> List(KnowledgeItem) {
  let tab_category = case model.active_tab {
    TabWikiCorpus -> "Wiki Corpus"
    TabZkInvariants -> "ZK Invariants"
    TabLivingOntology -> "Living Ontology"
    TabBiosemiotics -> "Biosemiotics"
  }

  model.items
  |> list.filter(fn(item) { item.category == tab_category })
  |> list.filter(fn(item) {
    case model.active_tag_filter {
      None -> True
      Some(tag) -> list.contains(item.tags, tag)
    }
  })
  |> list.filter(fn(item) {
    case string.trim(model.search_query) {
      "" -> True
      q ->
        string.contains(string.lowercase(item.title), string.lowercase(q))
        || string.contains(string.lowercase(item.summary), string.lowercase(q))
        || string.contains(string.lowercase(item.id), string.lowercase(q))
    }
  })
}

fn render_header() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex justify-between items-center mb-5 pb-4 border-b border-slate-800",
      ),
    ],
    [
      html.div([], [
        html.h2(
          [
            attribute.class(
              "text-xl font-bold text-amber-400 flex items-center gap-2",
            ),
          ],
          [
            html.span([], [html.text("🧠")]),
            html.text("Unified Knowledge, Wiki & ZK Explorer"),
          ],
        ),
        html.p([attribute.class("text-xs text-slate-400 mt-1")], [
          html.text(
            "Lustre MVU Living Knowledge Subsystem — Biosemiotic Transclusion Engine",
          ),
        ]),
      ]),
      html.div([attribute.class("flex gap-2")], [
        html.span(
          [
            attribute.class(
              "px-2.5 py-1 text-xs font-mono rounded bg-emerald-500/20 text-emerald-400 border border-emerald-500/40",
            ),
          ],
          [
            html.text("#rocha-semiotics"),
          ],
        ),
        html.span(
          [
            attribute.class(
              "px-2.5 py-1 text-xs font-mono rounded bg-blue-500/20 text-blue-400 border border-blue-500/40",
            ),
          ],
          [
            html.text("#cybernetics"),
          ],
        ),
        html.span(
          [
            attribute.class(
              "px-2.5 py-1 text-xs font-mono rounded bg-amber-500/20 text-amber-400 border border-amber-500/40",
            ),
          ],
          [
            html.text("#km-triad"),
          ],
        ),
      ]),
    ],
  )
}

fn render_tabs(active: KnowledgeTab) -> Element(Msg) {
  let tabs = [
    #(TabWikiCorpus, "Wiki Corpus Index", "📚"),
    #(TabZkInvariants, "ZK Invariants & ADRs", "🔒"),
    #(TabLivingOntology, "Living Ontology Hub", "🧬"),
    #(TabBiosemiotics, "Biosemiotic Lattice", "🌀"),
  ]

  html.div(
    [
      attribute.class(
        "flex space-x-2 border-b border-slate-800 pb-2 mb-4 overflow-x-auto",
      ),
    ],
    list.map(tabs, fn(t) {
      let #(tab_val, label, icon) = t
      let is_active = tab_val == active
      let cls = case is_active {
        True ->
          "bg-amber-500/20 text-amber-300 border-b-2 border-amber-400 font-semibold"
        False -> "text-slate-400 hover:text-slate-200 hover:bg-slate-800/40"
      }
      html.button(
        [
          attribute.class(
            "px-4 py-2 rounded-t text-xs flex items-center gap-2 transition-colors "
            <> cls,
          ),
          event.on_click(SelectTab(tab_val)),
        ],
        [html.span([], [html.text(icon)]), html.text(label)],
      )
    }),
  )
}

fn render_search_bar(model: Model) -> Element(Msg) {
  html.div([attribute.class("mb-3")], [
    html.input([
      attribute.type_("text"),
      attribute.placeholder(
        "Search articles, ADRs, invariants, transclusions...",
      ),
      attribute.value(model.search_query),
      attribute.class(
        "w-full bg-slate-950 border border-slate-700 rounded-lg px-4 py-2 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-amber-400",
      ),
      event.on_input(SetSearch),
    ]),
  ])
}

fn render_tag_filter_strip(active_filter: Option(String)) -> Element(Msg) {
  let tags = [
    "#rocha-semiotics",
    "#cybernetics",
    "#km-triad",
    "#zero-muda",
    "#zk-adr",
  ]

  html.div([attribute.class("flex items-center gap-2 text-xs flex-wrap mb-4")], [
    html.span([attribute.class("text-slate-500 text-[11px]")], [
      html.text("Filter tags:"),
    ]),
    html.button(
      [
        attribute.class(
          "px-2 py-0.5 rounded text-[11px] font-mono border "
          <> case active_filter {
            None -> "bg-slate-700 text-white border-slate-600"
            Some(_) ->
              "bg-slate-900 text-slate-400 border-slate-800 hover:text-white"
          },
        ),
        event.on_click(FilterByTag(None)),
      ],
      [html.text("All")],
    ),
    ..list.map(tags, fn(t) {
      let is_selected = active_filter == Some(t)
      let cls = case is_selected {
        True -> "bg-amber-500/30 text-amber-300 border-amber-400/80 font-bold"
        False ->
          "bg-slate-900/80 text-slate-400 border-slate-800 hover:text-amber-300 hover:border-slate-700"
      }
      html.button(
        [
          attribute.class(
            "px-2 py-0.5 rounded text-[11px] font-mono border transition-all "
            <> cls,
          ),
          event.on_click(FilterByTag(Some(t))),
        ],
        [html.text(t)],
      )
    })
  ])
}

fn render_items_list(
  items: List(KnowledgeItem),
  selected_id: Option(String),
) -> Element(Msg) {
  case items {
    [] ->
      html.div(
        [attribute.class("p-6 text-center text-slate-500 text-xs italic")],
        [
          html.text("No matching knowledge nodes found."),
        ],
      )
    _ ->
      html.div(
        [attribute.class("space-y-2 max-h-[420px] overflow-y-auto pr-1")],
        list.map(items, fn(item) {
          let is_sel = selected_id == Some(item.id)
          let card_cls = case is_sel {
            True -> "border-amber-400/80 bg-amber-500/10"
            False -> "border-slate-800 bg-slate-950/60 hover:border-slate-700"
          }
          html.div(
            [
              attribute.class(
                "p-3 rounded-lg border cursor-pointer transition-all "
                <> card_cls,
              ),
              event.on_click(SelectItem(item.id)),
            ],
            [
              html.div(
                [attribute.class("flex justify-between items-center mb-1")],
                [
                  html.span(
                    [
                      attribute.class(
                        "font-mono text-[11px] text-amber-400 font-semibold",
                      ),
                    ],
                    [html.text(item.id)],
                  ),
                  html.span(
                    [attribute.class("font-mono text-[10px] text-slate-500")],
                    [html.text(item.fractal_layer)],
                  ),
                ],
              ),
              html.div(
                [
                  attribute.class(
                    "text-xs font-semibold text-slate-200 truncate",
                  ),
                ],
                [html.text(item.title)],
              ),
              html.div(
                [
                  attribute.class(
                    "text-[11px] text-slate-400 line-clamp-2 mt-1",
                  ),
                ],
                [html.text(item.summary)],
              ),
            ],
          )
        }),
      )
  }
}

fn render_inspector(
  items: List(KnowledgeItem),
  selected_id: Option(String),
) -> Element(Msg) {
  let selected = case selected_id {
    None -> list.first(items) |> option.from_result
    Some(id) -> list.find(items, fn(i) { i.id == id }) |> option.from_result
  }

  case selected {
    None ->
      html.div(
        [
          attribute.class(
            "h-full flex items-center justify-center p-8 text-slate-500 text-xs italic",
          ),
        ],
        [
          html.text(
            "Select a knowledge node on the left to inspect its invariants and transclusions.",
          ),
        ],
      )
    Some(item) ->
      html.div(
        [
          attribute.class(
            "bg-slate-950/80 border border-slate-800 rounded-lg p-5",
          ),
        ],
        [
          html.div(
            [
              attribute.class(
                "flex justify-between items-start mb-3 pb-3 border-b border-slate-800",
              ),
            ],
            [
              html.div([], [
                html.div([attribute.class("flex items-center gap-2 mb-1")], [
                  html.span(
                    [
                      attribute.class(
                        "px-2 py-0.5 rounded text-[10px] font-mono bg-amber-500/20 text-amber-300 border border-amber-500/40",
                      ),
                    ],
                    [
                      html.text(item.id),
                    ],
                  ),
                  html.span(
                    [
                      attribute.class(
                        "px-2 py-0.5 rounded text-[10px] font-mono bg-blue-500/20 text-blue-300 border border-blue-500/40",
                      ),
                    ],
                    [
                      html.text(item.fractal_layer),
                    ],
                  ),
                ]),
                html.h3(
                  [attribute.class("text-base font-bold text-slate-100")],
                  [html.text(item.title)],
                ),
              ]),
              html.a(
                [
                  attribute.href(item.tailscale_url),
                  attribute.target("_blank"),
                  attribute.class(
                    "px-3 py-1 text-xs rounded bg-blue-600 hover:bg-blue-500 text-white font-medium flex items-center gap-1",
                  ),
                ],
                [
                  html.text("Open Full Doc ↗"),
                ],
              ),
            ],
          ),

          html.div(
            [attribute.class("text-xs text-slate-300 leading-relaxed mb-4")],
            [
              html.text(item.summary),
            ],
          ),

          html.div([attribute.class("mb-4")], [
            html.h4(
              [
                attribute.class(
                  "text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2",
                ),
              ],
              [
                html.text("Bidirectional Transclusions"),
              ],
            ),
            html.div(
              [attribute.class("flex flex-wrap gap-2")],
              list.map(item.transclusions, fn(tr) {
                html.span(
                  [
                    attribute.class(
                      "px-2 py-1 rounded bg-slate-900 border border-slate-700 text-cyan-300 text-xs font-mono",
                    ),
                  ],
                  [
                    html.text(tr),
                  ],
                )
              }),
            ),
          ]),

          html.div([], [
            html.h4(
              [
                attribute.class(
                  "text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2",
                ),
              ],
              [
                html.text("Fractal & Biosemiotic Tags"),
              ],
            ),
            html.div(
              [attribute.class("flex flex-wrap gap-1.5")],
              list.map(item.tags, fn(t) {
                html.span(
                  [
                    attribute.class(
                      "px-2 py-0.5 rounded bg-slate-900/60 border border-slate-800 text-slate-400 text-[11px] font-mono",
                    ),
                  ],
                  [
                    html.text(t),
                  ],
                )
              }),
            ),
          ]),
        ],
      )
  }
}

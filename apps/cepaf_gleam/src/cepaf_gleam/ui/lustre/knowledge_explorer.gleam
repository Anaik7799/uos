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
    KnowledgeItem(
      id: "WIKI-001",
      title: "Hermes Wiki Master Corpus Index",
      category: "Wiki Corpus",
      fractal_layer: "#fractal-l5",
      summary: "Living knowledge graph index with Gospel contract bindings and 13D trace coordinates.",
      transclusions: [
        "[[wiki:20260905-1801-uos-zk-km-corpus-index]]",
        "[[zk:20260905-1801-moc-uos-unified-master]]",
      ],
      tags: ["#km-triad", "#rocha-semiotics", "#cybernetics", "#zero-muda"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/wiki",
    ),
    KnowledgeItem(
      id: "ADR-001",
      title: "Closed Rete Fact Schema & Strict Typing",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l0",
      summary: "Rejects dynamically shaped facts; compile-time closed Rete-UL typing.",
      transclusions: ["[[zk:ADR-001]]", "[[wiki:dmc-tcm-mandate]]"],
      tags: ["#zk-adr", "#rocha-semiotics", "#fractal-l0"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150139-adr-001-closed-rete-fact-schema-and-strict-typing-invariant.md",
    ),
    KnowledgeItem(
      id: "ADR-002",
      title: "Embedded NUL Ingress Trap & Allocation Containment",
      category: "ZK Invariants",
      fractal_layer: "#fractal-l1",
      summary: "Zero-Trust agent dispatch hook trapping NUL bytes with immediate abort code -2.",
      transclusions: ["[[zk:ADR-002]]", "[[wiki:agent-dispatch-hook]]"],
      tags: ["#zk-adr", "#cybernetics", "#fractal-l1"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/zk/20260904-150142-adr-002-embedded-nul-ingress-trap-and-memory-allocation-containment.md",
    ),
    KnowledgeItem(
      id: "ONTO-001",
      title: "C3I STAMP/STPA Safety Lattice Hub",
      category: "Living Ontology",
      fractal_layer: "#fractal-l4",
      summary: "128-bit W3C OTel trace correlation and hazard control loops.",
      transclusions: ["[[wiki:stpa-safety-protocol]]", "[[zk:ADR-010]]"],
      tags: ["#km-triad", "#cybernetics", "#fractal-l4"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/km",
    ),
    KnowledgeItem(
      id: "BIO-001",
      title: "Rocha Biosemiotic Cybernetics Lattice",
      category: "Biosemiotics",
      fractal_layer: "#fractal-l6",
      summary: "Von Foerster self-referential closure and Pattee epistemic cut with dual token/rate semantics.",
      transclusions: ["[[wiki:rocha-semiotics]]", "[[zk:MOC-BIO]]"],
      tags: ["#rocha-semiotics", "#cybernetics", "#km-triad"],
      tailscale_url: "http://nas-1.tail55d152.ts.net:4100/docs/design/20260905-2020-uos-grand-synthesis-review-tome-wiki-zk-km.md",
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

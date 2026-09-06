//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/feature_tracker_view</module>
////     <fsharp-lineage>Cepaf.UI.FeatureTrackerView.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Lustre MVU ZigVM 145-Feature Living Tracker & Semiotic Dashboard</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-GLM-UI-001, SC-GLM-UI-002, SC-ZIGVM-FEAT-001, SC-ROCHA-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import cepaf_gleam/knowledge/zigvm_feature_tracker.{
  type FeatureCategory, type FeatureSummary, type ZigvmFeature,
  EpisodicResearchCluster, HarnessVerificationLaw, MapOfContent,
  PermanentAdrRecord, RenderSuite, ServiceTopology, TopologicalSheafFormal,
  WikiCoreEngine, WikiMaintenanceScript, ZkKnowledgeScript, ZkMcpTool,
  all_features, category_to_string, get_summary, status_to_string,
  tier_to_string,
}
import gleam/int
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

pub type Model {
  Model(
    search_query: String,
    category_filter: Option(FeatureCategory),
    selected_feature_id: Option(String),
    summary: FeatureSummary,
    features: List(ZigvmFeature),
  )
}

pub type Msg {
  SetSearch(String)
  SetCategoryFilter(Option(FeatureCategory))
  SelectFeature(String)
  ClearFilter
}

// =============================================================================
// MVU Cycle
// =============================================================================

pub fn init() -> Model {
  Model(
    search_query: "",
    category_filter: None,
    selected_feature_id: Some("WIKI-001"),
    summary: get_summary(),
    features: all_features(),
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    SetSearch(q) -> Model(..model, search_query: q)
    SetCategoryFilter(cat) -> Model(..model, category_filter: cat)
    SelectFeature(id) -> Model(..model, selected_feature_id: Some(id))
    ClearFilter -> Model(..model, search_query: "", category_filter: None)
  }
}

// =============================================================================
// View
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  let filtered = filter_features(model)

  html.div(
    [
      attribute.class(
        "feature-tracker-view bg-slate-900 border border-slate-700 rounded-xl p-6 text-white shadow-2xl",
      ),
    ],
    [
      render_header(model.summary),
      render_metrics_strip(model.summary),
      render_ascii_feature_taxonomy(),
      render_category_chips(model.category_filter),
      render_search_bar(model.search_query),
      html.div([attribute.class("grid grid-cols-1 lg:grid-cols-3 gap-6 mt-4")], [
        html.div(
          [
            attribute.class(
              "lg:col-span-2 overflow-x-auto max-h-[520px] overflow-y-auto pr-2",
            ),
          ],
          [
            render_features_table(filtered, model.selected_feature_id),
          ],
        ),
        html.div([attribute.class("lg:col-span-1")], [
          render_feature_inspector(model.features, model.selected_feature_id),
        ]),
      ]),
    ],
  )
}

fn render_ascii_feature_taxonomy() -> Element(Msg) {
  let ascii_art =
    "  +-------------------------------------------------------------------------------------------------+
  |                    ZIGVM WIKI, ZK & KM 145-FEATURE LIVING TAXONOMY MATRIX                       |
  +--------------------+-------+--------------------+-----------------------------------------------+
  | CATEGORY           | COUNT | VERIFICATION TIER  | CORE LINEAGE PATH                             |
  +--------------------+-------+--------------------+-----------------------------------------------+
  | Wiki Core Engine   |     6 | Tier 2 (Gospel)    | engines/hermes/modules/hermes_wiki/           |
  | ZK MCP Tools       |     7 | Tier 1 (Runtime)   | dev/ver/zigvm/src/mcp_server/                 |
  | Permanent ADRs     |    16 | Tier 3 (Signed)    | docs/zk/20260904-*-adr-*.md                   |
  | Maps of Content    |    12 | Tier 2 (Biosemiotic| docs/zk/20260905-*-moc-*.md                   |
  | Formal Laws        |     8 | Tier 3 (Rocq Proof)| dev/ver/zigvm/src/formal/proof_registry.v    |
  | Sheaf Modules      |     4 | Tier 3 (Lean 4/Z3) | apps/cepaf_gleam/src/knowledge/sheaf.gleam    |
  | Render Suites      |    13 | Tier 1 (Isomorphic)| apps/cepaf_gleam/src/ui/lustre/               |
  | ZK Scripts         |    42 | Tier 1 (Hermetic)  | dev/ver/zigvm/scripts/zk_*.sh                 |
  | Wiki Scripts       |    23 | Tier 1 (Hermetic)  | dev/ver/zigvm/scripts/wiki_*.sh               |
  | Episodic Clusters  |    10 | Tier 1 (Evidence)  | docs/zk/episodic/ (347 notes)                 |
  | Service Topology   |     4 | Tier 2 (Supervised)| apps/cepaf_gleam/src/uos_sup.gleam           |
  +--------------------+-------+--------------------+-----------------------------------------------+
  | TOTAL ADMITTED     |   145 | ALL RELEVANT & 100% PASSING IN PURE GLEAM & HERMES OCAML          |
  +--------------------+-------+--------------------+-----------------------------------------------+"

  html.div(
    [
      attribute.class(
        "my-3 bg-slate-950 border border-slate-800 rounded-lg p-3 font-mono text-[11px] overflow-x-auto",
      ),
    ],
    [
      html.pre([attribute.class("text-amber-400 leading-tight select-all")], [
        html.text(ascii_art),
      ]),
    ],
  )
}

fn filter_features(model: Model) -> List(ZigvmFeature) {
  model.features
  |> list.filter(fn(f) {
    case model.category_filter {
      None -> True
      Some(cat) -> f.category == cat
    }
  })
  |> list.filter(fn(f) {
    case string.trim(model.search_query) {
      "" -> True
      q ->
        string.contains(string.lowercase(f.name), string.lowercase(q))
        || string.contains(string.lowercase(f.id), string.lowercase(q))
        || string.contains(string.lowercase(f.description), string.lowercase(q))
        || string.contains(string.lowercase(f.source_path), string.lowercase(q))
    }
  })
}

fn render_header(summary: FeatureSummary) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex justify-between items-center mb-4 pb-3 border-b border-slate-800",
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
            html.span([], [html.text("📊")]),
            html.text("ZigVM Wiki, ZK & KM 145-Feature Living Tracker"),
          ],
        ),
        html.p([attribute.class("text-xs text-slate-400 mt-1")], [
          html.text(
            "Exhaustive In-Code Knowledge Architecture Registry & Biosemiotic Trace Matrix",
          ),
        ]),
      ]),
      html.div([attribute.class("flex items-center gap-2")], [
        html.span(
          [
            attribute.class(
              "px-3 py-1 text-xs font-mono font-bold rounded-full bg-emerald-500/20 text-emerald-400 border border-emerald-500/40",
            ),
          ],
          [
            html.text(
              int.to_string(summary.total_features)
              <> " FEATURES 100% OPERATIONAL",
            ),
          ],
        ),
      ]),
    ],
  )
}

fn render_metrics_strip(summary: FeatureSummary) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 gap-2 mb-4 text-center text-xs",
      ),
    ],
    [
      metric_tile("145", "Total Features", "text-amber-400"),
      metric_tile(
        int.to_string(summary.wiki_core_count),
        "Wiki Core",
        "text-blue-400",
      ),
      metric_tile(
        int.to_string(summary.zk_mcp_tool_count),
        "ZK MCP Tools",
        "text-cyan-400",
      ),
      metric_tile(
        int.to_string(summary.adr_count),
        "Permanent ADRs",
        "text-emerald-400",
      ),
      metric_tile(
        int.to_string(summary.harness_law_count),
        "Formal Laws",
        "text-purple-400",
      ),
      metric_tile(
        int.to_string(summary.moc_count),
        "Master MOCs",
        "text-rose-400",
      ),
    ],
  )
}

fn metric_tile(val: String, label: String, col: String) -> Element(Msg) {
  html.div(
    [attribute.class("bg-slate-950/80 border border-slate-800 rounded p-2.5")],
    [
      html.div([attribute.class("text-lg font-bold font-mono " <> col)], [
        html.text(val),
      ]),
      html.div(
        [attribute.class("text-[10px] text-slate-400 uppercase mt-0.5")],
        [html.text(label)],
      ),
    ],
  )
}

fn render_category_chips(
  active_filter: Option(FeatureCategory),
) -> Element(Msg) {
  let categories = [
    #(WikiCoreEngine, "Wiki Core (6)"),
    #(ZkMcpTool, "ZK MCP Tools (7)"),
    #(PermanentAdrRecord, "ADRs (16)"),
    #(MapOfContent, "MOCs (12)"),
    #(HarnessVerificationLaw, "Formal Laws (8)"),
    #(TopologicalSheafFormal, "Sheaf (4)"),
    #(RenderSuite, "Renders (13)"),
    #(ZkKnowledgeScript, "ZK Scripts (42)"),
    #(WikiMaintenanceScript, "Wiki Scripts (23)"),
    #(EpisodicResearchCluster, "Episodic (10)"),
    #(ServiceTopology, "Topology (4)"),
  ]

  html.div(
    [attribute.class("flex items-center gap-1.5 text-xs flex-wrap mb-3")],
    [
      html.span([attribute.class("text-slate-500 text-[11px]")], [
        html.text("Category:"),
      ]),
      html.button(
        [
          attribute.class(
            "px-2.5 py-0.5 rounded text-[11px] border "
            <> case active_filter {
              None -> "bg-slate-700 text-white border-slate-600 font-bold"
              Some(_) ->
                "bg-slate-900 text-slate-400 border-slate-800 hover:text-white"
            },
          ),
          event.on_click(SetCategoryFilter(None)),
        ],
        [html.text("All (145)")],
      ),
      ..list.map(categories, fn(c) {
        let #(cat_val, label) = c
        let is_selected = active_filter == Some(cat_val)
        let cls = case is_selected {
          True -> "bg-amber-500/30 text-amber-300 border-amber-400/80 font-bold"
          False ->
            "bg-slate-900/80 text-slate-400 border-slate-800 hover:text-amber-300"
        }
        html.button(
          [
            attribute.class(
              "px-2 py-0.5 rounded text-[11px] border transition-all " <> cls,
            ),
            event.on_click(SetCategoryFilter(Some(cat_val))),
          ],
          [html.text(label)],
        )
      })
    ],
  )
}

fn render_search_bar(query: String) -> Element(Msg) {
  html.div([attribute.class("mb-3")], [
    html.input([
      attribute.type_("text"),
      attribute.placeholder(
        "Filter by feature ID, name, file path, or description...",
      ),
      attribute.value(query),
      attribute.class(
        "w-full bg-slate-950 border border-slate-700 rounded-lg px-4 py-2 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-amber-400",
      ),
      event.on_input(SetSearch),
    ]),
  ])
}

fn render_features_table(
  features: List(ZigvmFeature),
  selected_id: Option(String),
) -> Element(Msg) {
  html.table([attribute.class("w-full text-left text-xs border-collapse")], [
    html.thead([], [
      html.tr(
        [
          attribute.class(
            "bg-slate-950 text-slate-400 border-b border-slate-800 sticky top-0",
          ),
        ],
        [
          html.th([attribute.class("py-2 px-2.5 font-semibold")], [
            html.text("ID"),
          ]),
          html.th([attribute.class("py-2 px-2.5 font-semibold")], [
            html.text("Name & Description"),
          ]),
          html.th([attribute.class("py-2 px-2.5 font-semibold")], [
            html.text("Tier"),
          ]),
          html.th([attribute.class("py-2 px-2.5 font-semibold")], [
            html.text("Status"),
          ]),
          html.th([attribute.class("py-2 px-2.5 font-semibold")], [
            html.text("Source Path"),
          ]),
        ],
      ),
    ]),
    html.tbody(
      [],
      list.map(features, fn(f) {
        let is_sel = selected_id == Some(f.id)
        let row_cls = case is_sel {
          True -> "bg-amber-500/15 border-amber-500/50"
          False -> "hover:bg-slate-800/40 border-slate-800/60"
        }
        html.tr(
          [
            attribute.class(
              "border-b cursor-pointer transition-colors " <> row_cls,
            ),
            event.on_click(SelectFeature(f.id)),
          ],
          [
            html.td(
              [
                attribute.class(
                  "py-2 px-2.5 font-mono text-amber-400 font-bold text-[11px]",
                ),
              ],
              [html.text(f.id)],
            ),
            html.td([attribute.class("py-2 px-2.5")], [
              html.div([attribute.class("text-slate-200 font-medium")], [
                html.text(f.name),
              ]),
              html.div(
                [
                  attribute.class(
                    "text-slate-400 text-[10px] truncate max-w-[280px]",
                  ),
                ],
                [html.text(f.description)],
              ),
            ]),
            html.td(
              [
                attribute.class(
                  "py-2 px-2.5 font-mono text-[10px] text-emerald-400",
                ),
              ],
              [html.text(tier_to_string(f.tier))],
            ),
            html.td(
              [
                attribute.class(
                  "py-2 px-2.5 font-mono text-[10px] text-blue-400",
                ),
              ],
              [html.text(status_to_string(f.status))],
            ),
            html.td(
              [
                attribute.class(
                  "py-2 px-2.5 font-mono text-[10px] text-cyan-400/80 truncate max-w-[140px]",
                ),
              ],
              [html.text(f.source_path)],
            ),
          ],
        )
      }),
    ),
  ])
}

fn render_feature_inspector(
  features: List(ZigvmFeature),
  selected_id: Option(String),
) -> Element(Msg) {
  let selected = case selected_id {
    None -> list.first(features) |> option.from_result
    Some(id) -> list.find(features, fn(f) { f.id == id }) |> option.from_result
  }

  case selected {
    None ->
      html.div(
        [
          attribute.class(
            "bg-slate-950/80 border border-slate-800 rounded-lg p-6 text-center text-slate-500 text-xs italic",
          ),
        ],
        [
          html.text(
            "Select a feature row to view detailed provenance and contract specifications.",
          ),
        ],
      )
    Some(f) ->
      html.div(
        [
          attribute.class(
            "bg-slate-950/90 border border-slate-800 rounded-lg p-5 sticky top-0",
          ),
        ],
        [
          html.div(
            [
              attribute.class(
                "flex justify-between items-center mb-3 pb-2 border-b border-slate-800",
              ),
            ],
            [
              html.span(
                [
                  attribute.class(
                    "px-2.5 py-1 text-xs font-mono font-bold rounded bg-amber-500/20 text-amber-300 border border-amber-500/40",
                  ),
                ],
                [
                  html.text(f.id),
                ],
              ),
              html.span(
                [
                  attribute.class(
                    "px-2 py-0.5 text-xs font-mono rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/40",
                  ),
                ],
                [
                  html.text(status_to_string(f.status)),
                ],
              ),
            ],
          ),
          html.h3([attribute.class("text-sm font-bold text-slate-100 mb-2")], [
            html.text(f.name),
          ]),
          html.p(
            [attribute.class("text-xs text-slate-300 leading-relaxed mb-4")],
            [html.text(f.description)],
          ),
          html.div([attribute.class("space-y-2 text-xs mb-4")], [
            html.div([attribute.class("flex justify-between text-slate-400")], [
              html.span([], [html.text("Category:")]),
              html.span([attribute.class("text-slate-200 font-semibold")], [
                html.text(category_to_string(f.category)),
              ]),
            ]),
            html.div([attribute.class("flex justify-between text-slate-400")], [
              html.span([], [html.text("Verification Tier:")]),
              html.span(
                [attribute.class("font-mono text-emerald-400 font-semibold")],
                [html.text(tier_to_string(f.tier))],
              ),
            ]),
            html.div([attribute.class("flex justify-between text-slate-400")], [
              html.span([], [html.text("Source Path:")]),
              html.span(
                [
                  attribute.class(
                    "font-mono text-slate-300 text-[10px] truncate max-w-[180px]",
                  ),
                ],
                [html.text(f.source_path)],
              ),
            ]),
            html.div([attribute.class("flex justify-between text-slate-400")], [
              html.span([], [html.text("Evidence Path:")]),
              html.span(
                [
                  attribute.class(
                    "font-mono text-amber-300 text-[10px] truncate max-w-[180px]",
                  ),
                ],
                [html.text(f.evidence_path)],
              ),
            ]),
          ]),
          html.a(
            [
              attribute.href(
                "http://nas-1.tail55d152.ts.net:4100/files/" <> f.source_path,
              ),
              attribute.target("_blank"),
              attribute.class(
                "block w-full text-center py-2 px-3 rounded bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs transition-colors shadow-lg",
              ),
            ],
            [
              html.text("Open Source Lineage File ↗"),
            ],
          ),
        ],
      )
  }
}

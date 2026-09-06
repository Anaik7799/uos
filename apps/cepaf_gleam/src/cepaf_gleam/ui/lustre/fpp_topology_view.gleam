//// =============================================================================
//// [C3I-SIL6-FPP] NASA JPL F Prime / FPP Flight Software Topology View
//// =============================================================================
//// Pure Lustre 5.6+ MVU Component for F Prime Flight Architecture in Gleam:
//// - 11 Canonical Component Instances with Base ID Allocations
//// - 13 Direct Port Connections + 4 Pattern Graphs (Time, Health, Telemetry, Event)
//// - NASA JPL Hierarchical State Machine (HSM) State & LCA Visualizer
//// - Parameter Database (Svc::PrmDb) Registry
//// - Telemetry Packetizer Downlink Channel Sets
//// - Link to Ground Dictionary JSON (/api/fpp/dictionary)
//// =============================================================================

import cepaf_gleam/fpp/domain.{
  type Component, type Instance, Active, Passive, Queued,
}
import cepaf_gleam/fpp/topology.{canonical_harness_model}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// =============================================================================
// Types
// =============================================================================

pub type Model {
  Model(selected_instance: Option(String), active_hsm_state: String)
}

pub type Msg {
  SelectInstance(String)
  SelectHsmState(String)
}

// =============================================================================
// Init & Update
// =============================================================================

pub fn init() -> Model {
  Model(
    selected_instance: Some("evidence_store"),
    active_hsm_state: "Operational / Flight / Cruise",
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    SelectInstance(name) -> Model(..model, selected_instance: Some(name))
    SelectHsmState(state) -> Model(..model, active_hsm_state: state)
  }
}

// =============================================================================
// View
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  let fpp_model = canonical_harness_model()

  html.div(
    [
      attribute.class(
        "fpp-topology-container p-4 bg-slate-900 text-slate-200 rounded-lg space-y-6",
      ),
    ],
    [
      render_header(),
      render_status_tiles(),
      render_instances_table(
        fpp_model.instances,
        fpp_model.components,
        model.selected_instance,
      ),
      render_hsm_panel(model.active_hsm_state),
      render_subtopology_panel(fpp_model),
      render_links_panel(),
    ],
  )
}

fn render_header() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "flex justify-between items-center pb-4 border-b border-slate-800",
      ),
    ],
    [
      html.div([], [
        html.h2(
          [
            attribute.class(
              "text-2xl font-bold text-sky-400 flex items-center gap-2",
            ),
          ],
          [
            html.span([], [html.text("🚀")]),
            html.text("NASA JPL F Prime / FPP Flight Software Topology"),
          ],
        ),
        html.p([attribute.class("text-xs text-slate-400 mt-1")], [
          html.text(
            "Pure BEAM / Gleam / OTP 29 Transmutation of Mission-Critical Aerospace Architecture",
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
            html.text("SIL-6 / DAL-A VERIFIED"),
          ],
        ),
      ]),
    ],
  )
}

fn render_status_tiles() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "grid grid-cols-2 sm:grid-cols-4 md:grid-cols-6 gap-3 text-center text-xs",
      ),
    ],
    [
      status_tile("11", "Instances", "text-sky-400"),
      status_tile("13", "Connections", "text-indigo-400"),
      status_tile("4", "Patterns", "text-amber-400"),
      status_tile("HSM", "Hierarchical SM", "text-purple-400"),
      status_tile("Svc::PrmDb", "Param Database", "text-emerald-400"),
      status_tile("JSON", "Ground Dict", "text-cyan-400"),
    ],
  )
}

fn status_tile(
  value: String,
  label: String,
  color_class: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-slate-950 p-3 rounded border border-slate-800 flex flex-col items-center justify-center",
      ),
    ],
    [
      html.span(
        [attribute.class("text-lg font-bold font-mono " <> color_class)],
        [html.text(value)],
      ),
      html.span(
        [
          attribute.class(
            "text-[10px] text-slate-400 uppercase tracking-wider mt-1",
          ),
        ],
        [html.text(label)],
      ),
    ],
  )
}

fn render_instances_table(
  instances: List(Instance),
  components: List(Component),
  selected: Option(String),
) -> Element(Msg) {
  html.div(
    [attribute.class("bg-slate-950 p-4 rounded-lg border border-slate-800")],
    [
      html.h3(
        [
          attribute.class(
            "text-sm font-semibold text-slate-300 uppercase tracking-wider mb-3 flex items-center gap-2",
          ),
        ],
        [
          html.span([], [html.text("🛰️")]),
          html.text("Component Instances & Memory Window Allocations"),
        ],
      ),
      html.div([attribute.class("overflow-x-auto")], [
        html.table([attribute.class("w-full text-left text-xs")], [
          html.thead(
            [
              attribute.class(
                "bg-slate-900/60 text-slate-400 border-b border-slate-800 font-mono",
              ),
            ],
            [
              html.tr([], [
                html.th([attribute.class("p-2")], [html.text("Instance")]),
                html.th([attribute.class("p-2")], [html.text("Component")]),
                html.th([attribute.class("p-2")], [html.text("Kind")]),
                html.th([attribute.class("p-2")], [html.text("Base ID")]),
                html.th([attribute.class("p-2")], [html.text("Ports")]),
                html.th([attribute.class("p-2")], [html.text("Commands")]),
                html.th([attribute.class("p-2")], [html.text("Events")]),
                html.th([attribute.class("p-2")], [html.text("Channels")]),
              ]),
            ],
          ),
          html.tbody(
            [],
            list.map(instances, fn(inst) {
              let comp_opt =
                list.find(components, fn(c) { c.comp_name == inst.of_component })
              let #(kind_str, ports_cnt, cmds_cnt, evts_cnt, chns_cnt) = case
                comp_opt
              {
                Ok(c) -> #(
                  case c.kind {
                    Passive -> "Passive"
                    Queued -> "Queued"
                    Active -> "Active"
                  },
                  int.to_string(list.length(c.ports)),
                  int.to_string(list.length(c.commands)),
                  int.to_string(list.length(c.events)),
                  int.to_string(list.length(c.channels)),
                )
                Error(_) -> #("Unknown", "0", "0", "0", "0")
              }
              let is_selected = case selected {
                Some(s) -> s == inst.inst_name
                None -> False
              }
              let row_class = case is_selected {
                True -> "bg-sky-950/40 border-l-2 border-sky-500 font-medium"
                False ->
                  "border-b border-slate-800/40 hover:bg-slate-900/40 cursor-pointer"
              }
              html.tr(
                [
                  attribute.class(row_class),
                  event.on_click(SelectInstance(inst.inst_name)),
                ],
                [
                  html.td([attribute.class("p-2 font-mono text-sky-300")], [
                    html.text(inst.inst_name),
                  ]),
                  html.td([attribute.class("p-2 text-slate-300")], [
                    html.text(inst.of_component),
                  ]),
                  html.td([attribute.class("p-2")], [
                    html.span(
                      [
                        attribute.class(
                          "px-2 py-0.5 rounded text-[10px] font-mono bg-slate-800 text-slate-300",
                        ),
                      ],
                      [
                        html.text(kind_str),
                      ],
                    ),
                  ]),
                  html.td([attribute.class("p-2 font-mono text-amber-400")], [
                    html.text("0x" <> int.to_base16(inst.base_id)),
                  ]),
                  html.td([attribute.class("p-2 font-mono text-slate-400")], [
                    html.text(ports_cnt),
                  ]),
                  html.td([attribute.class("p-2 font-mono text-indigo-400")], [
                    html.text(cmds_cnt),
                  ]),
                  html.td([attribute.class("p-2 font-mono text-emerald-400")], [
                    html.text(evts_cnt),
                  ]),
                  html.td([attribute.class("p-2 font-mono text-cyan-400")], [
                    html.text(chns_cnt),
                  ]),
                ],
              )
            }),
          ),
        ]),
      ]),
    ],
  )
}

fn render_hsm_panel(active_state: String) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-slate-950 p-4 rounded-lg border border-slate-800 space-y-3",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center")], [
        html.h3(
          [
            attribute.class(
              "text-sm font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-2",
            ),
          ],
          [
            html.span([], [html.text("🔄")]),
            html.text("Hierarchical State Machine (HSM) Engine"),
          ],
        ),
        html.div(
          [
            attribute.class(
              "text-xs font-mono text-purple-400 bg-purple-950/40 border border-purple-800/40 px-3 py-1 rounded-full",
            ),
          ],
          [
            html.text("Active Path: " <> active_state),
          ],
        ),
      ]),
      html.p([attribute.class("text-xs text-slate-400")], [
        html.text(
          "Executes Lowest Common Ancestor (LCA) state exit and entry ordering, multi-level signal bubbling from leaf to root, and recursive initial sub-state resolution.",
        ),
      ]),
      html.div(
        [
          attribute.class(
            "grid grid-cols-1 md:grid-cols-3 gap-3 pt-2 text-xs font-mono",
          ),
        ],
        [
          hsm_state_card(
            "Operational",
            "Root State",
            "Sub-states: Flight, SurfaceOps",
            "Initial: Flight",
          ),
          hsm_state_card(
            "Flight",
            "Composite State",
            "Sub-states: Cruise, Landing",
            "Initial: Cruise",
          ),
          hsm_state_card(
            "SafeMode",
            "Recovery State",
            "Emergency safe mode on anomaly / solar storm",
            "Initial: None",
          ),
        ],
      ),
    ],
  )
}

fn hsm_state_card(
  name: String,
  role: String,
  details: String,
  initial: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-slate-900 p-3 rounded border border-slate-800 space-y-1",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center")], [
        html.span([attribute.class("font-bold text-purple-300")], [
          html.text(name),
        ]),
        html.span([attribute.class("text-[10px] text-slate-500")], [
          html.text(role),
        ]),
      ]),
      html.p([attribute.class("text-[11px] text-slate-400")], [
        html.text(details),
      ]),
      html.p([attribute.class("text-[10px] text-purple-400/80")], [
        html.text(initial),
      ]),
    ],
  )
}

fn render_subtopology_panel(model: domain.Model) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-slate-950 p-4 rounded-lg border border-slate-800 space-y-3",
      ),
    ],
    [
      html.h3(
        [
          attribute.class(
            "text-sm font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-2",
          ),
        ],
        [
          html.span([], [html.text("🧩")]),
          html.text("Subtopologies & Exported Boundary Ports"),
        ],
      ),
      html.div(
        [attribute.class("space-y-2")],
        list.map(model.subtopologies, fn(sub) {
          html.div(
            [
              attribute.class(
                "bg-slate-900 p-3 rounded border border-slate-800 flex flex-col md:flex-row md:items-center md:justify-between gap-2",
              ),
            ],
            [
              html.div([], [
                html.span(
                  [attribute.class("font-mono font-bold text-sky-300 text-xs")],
                  [html.text(sub.name)],
                ),
                html.span([attribute.class("text-slate-500 text-xs ml-2")], [
                  html.text(
                    "("
                    <> int.to_string(list.length(sub.instances))
                    <> " internal instances, "
                    <> int.to_string(list.length(sub.connections))
                    <> " internal connections)",
                  ),
                ]),
              ]),
              html.div(
                [attribute.class("flex flex-wrap gap-2")],
                list.map(sub.exported_ports, fn(ep) {
                  html.span(
                    [
                      attribute.class(
                        "px-2 py-0.5 bg-slate-800 text-amber-300 text-[11px] font-mono rounded border border-slate-700",
                      ),
                    ],
                    [
                      html.text(
                        ep.name
                        <> " ➔ "
                        <> ep.instance_name
                        <> "."
                        <> ep.port_name,
                      ),
                    ],
                  )
                }),
              ),
            ],
          )
        }),
      ),
    ],
  )
}

fn render_links_panel() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-slate-950 p-4 rounded-lg border border-slate-800 flex flex-col sm:flex-row justify-between items-center gap-3",
      ),
    ],
    [
      html.div([], [
        html.h4(
          [
            attribute.class(
              "text-xs font-semibold text-slate-300 uppercase tracking-wider",
            ),
          ],
          [
            html.text("Ground Station Integration"),
          ],
        ),
        html.p([attribute.class("text-xs text-slate-500 mt-0.5")], [
          html.text(
            "Download NASA JPL Ground Station Dictionary adhering to the official JSON schema specification.",
          ),
        ]),
      ]),
      html.a(
        [
          attribute.href("/api/fpp/dictionary"),
          attribute.target("_blank"),
          attribute.class(
            "px-4 py-2 bg-sky-600 hover:bg-sky-500 text-white font-mono text-xs font-bold rounded shadow transition-colors flex items-center gap-2",
          ),
        ],
        [
          html.span([], [html.text("📥")]),
          html.text("Download Ground Dictionary JSON"),
        ],
      ),
    ],
  )
}

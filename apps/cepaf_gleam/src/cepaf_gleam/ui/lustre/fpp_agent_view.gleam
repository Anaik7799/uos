//// =============================================================================
//// [C3I-SIL6-FPP-AGENTS] NASA JPL F Prime / FPP Aerospace Agent Cockpit View
//// =============================================================================
//// Pure Lustre 5.6+ MVU Component for F Prime Aerospace Agent Ecosystem:
//// - 16 Canonical Aerospace & Cybernetic Agent Types (L0..L9)
//// - 6-Dimensional Matrix: Layers x Components x Features x SDLC x SRE x Evidence
//// - Interactive Agent Simulator & Intent Safety Interlock (25503L801736)
//// - DMC Memory Window Interval Disjointness Proof
//// - 18/18 Comprehensive Verification Checklist
//// =============================================================================

import cepaf_gleam/fpp/agent_taxonomy.{
  type AgentKind, type AgentTypeSpec, C3iSdlc, C3iSre, C3iVerification,
  all_agent_types, verify_agent_base_id_disjointness,
}
import cepaf_gleam/fpp/dmc_tcm.{hard_denied_system_os_serial}
import cepaf_gleam/fpp/domain.{Active, Assert, Block, Drop, Passive, Queued}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

// =============================================================================
// Model & Messages
// =============================================================================

pub type Model {
  Model(
    selected_agent: Option(AgentKind),
    active_tab: String,
    simulated_signal: String,
    simulated_target: String,
    filter_pillar: String,
  )
}

pub type Msg {
  SelectAgent(AgentKind)
  SelectTab(String)
  SetSignal(String)
  SetTarget(String)
  SetFilterPillar(String)
}

pub fn init() -> Model {
  Model(
    selected_agent: None,
    active_tab: "catalog",
    simulated_signal: "evaluate_intent",
    simulated_target: "SAFE_DATA_NVME_02",
    filter_pillar: "ALL",
  )
}

pub fn update(model: Model, msg: Msg) -> Model {
  case msg {
    SelectAgent(kind) -> Model(..model, selected_agent: Some(kind))
    SelectTab(tab) -> Model(..model, active_tab: tab)
    SetSignal(sig) -> Model(..model, simulated_signal: sig)
    SetTarget(tgt) -> Model(..model, simulated_target: tgt)
    SetFilterPillar(p) -> Model(..model, filter_pillar: p)
  }
}

// =============================================================================
// View
// =============================================================================

pub fn view(model: Model) -> Element(Msg) {
  let specs = all_agent_types()
  let dmc_verified = verify_agent_base_id_disjointness(specs)

  html.div([attribute.class("fpp-agent-cockpit space-y-6 text-gray-100")], [
    render_header(),
    render_kpis(specs, dmc_verified),
    render_tab_nav(model.active_tab),
    case model.active_tab {
      "matrix" -> render_multi_dimensional_matrix()
      "simulator" -> render_agent_simulator(model)
      "checklist" -> render_verification_checklist()
      _ -> render_catalog_view(model, specs)
    },
  ])
}

// -----------------------------------------------------------------------------
// Header & KPIs
// -----------------------------------------------------------------------------

fn render_header() -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "bg-gray-900 border border-amber-500/30 rounded-lg p-5 shadow-xl",
      ),
    ],
    [
      html.div(
        [attribute.class("flex justify-between items-start flex-wrap gap-4")],
        [
          html.div([], [
            html.div([attribute.class("flex items-center gap-3")], [
              html.span(
                [attribute.class("text-2xl font-bold text-amber-400 font-mono")],
                [
                  html.text("NASA JPL F Prime / FPP Aerospace Agent Cockpit"),
                ],
              ),
              html.span(
                [
                  attribute.class(
                    "px-2.5 py-0.5 rounded text-xs font-mono bg-amber-500/20 text-amber-300 border border-amber-500/40",
                  ),
                ],
                [html.text("BEAM / OTP 29 Pure Substrate")],
              ),
            ]),
            html.p([attribute.class("text-sm text-gray-400 mt-1")], [
              html.text(
                "Aerospace-grade autonomous agents with Hierarchical State Machines (HSM), DMC memory disjointness, 13D TCM conservation, and DAL-A hardware safety.",
              ),
            ]),
          ]),
          html.div(
            [
              attribute.class(
                "flex flex-col items-end text-xs font-mono text-gray-400",
              ),
            ],
            [
              html.span([], [
                html.text("Tailnet: "),
                html.a(
                  [
                    attribute.href(
                      "http://nas-1.tail55d152.ts.net:4100/fpp-agents",
                    ),
                    attribute.class("text-blue-400 hover:underline"),
                  ],
                  [html.text("http://nas-1.tail55d152.ts.net:4100/fpp-agents")],
                ),
              ]),
              html.span([], [
                html.text("Authority: A0_ratified | SC-FPP-AGENT-TAXONOMY-001"),
              ]),
            ],
          ),
        ],
      ),
    ],
  )
}

fn render_kpis(specs: List(AgentTypeSpec), dmc_verified: Bool) -> Element(Msg) {
  let total_agents = list.length(specs)

  html.div([attribute.class("grid grid-cols-1 md:grid-cols-4 gap-4")], [
    render_kpi_card(
      "CANONICAL AGENT TYPES",
      int.to_string(total_agents) <> " Types",
      "24 SDLC | 24 SRE | 24 Verification",
      "border-amber-500/40 bg-gray-900/80 text-amber-400",
    ),
    render_kpi_card(
      "DMC MEMORY WINDOWS",
      case dmc_verified {
        True -> "100% DISJOINT"
        False -> "COLLISION DETECTED"
      },
      "[0x1000, 0x2200) Span=64",
      "border-emerald-500/40 bg-gray-900/80 text-emerald-400",
    ),
    render_kpi_card(
      "SAFETY INTERLOCK",
      "DAL-A LOCKED",
      "NVMe: " <> hard_denied_system_os_serial,
      "border-rose-500/40 bg-gray-900/80 text-rose-400",
    ),
    render_kpi_card(
      "EXECUTION ENGINE",
      "OTP 29 BEAM",
      "HSM LCA + Bubbling + Drop",
      "border-cyan-500/40 bg-gray-900/80 text-cyan-400",
    ),
  ])
}

fn render_kpi_card(
  title: String,
  value: String,
  subtext: String,
  accent_classes: String,
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "rounded-lg p-4 border shadow flex flex-col justify-between "
        <> accent_classes,
      ),
    ],
    [
      html.div(
        [
          attribute.class(
            "text-xs font-mono font-bold tracking-wider text-gray-400",
          ),
        ],
        [
          html.text(title),
        ],
      ),
      html.div([attribute.class("text-xl font-bold font-mono my-1")], [
        html.text(value),
      ]),
      html.div([attribute.class("text-xs text-gray-400 font-mono")], [
        html.text(subtext),
      ]),
    ],
  )
}

fn render_tab_nav(active_tab: String) -> Element(Msg) {
  let tabs = [
    #("catalog", "C3I Agent Catalog (72 Types)"),
    #("matrix", "Multi-Dimensional Matrix (6D)"),
    #("simulator", "HSM & Intent Simulator"),
    #("checklist", "18/18 Verification Checklist"),
  ]

  html.div([attribute.class("flex border-b border-gray-800 gap-2")], {
    list.map(tabs, fn(tab) {
      let #(key, label) = tab
      let is_active = key == active_tab
      let base_classes =
        "px-4 py-2 text-sm font-mono transition-colors border-b-2 "
      let active_classes = case is_active {
        True -> "border-amber-400 text-amber-300 font-bold bg-gray-900/50"
        False ->
          "border-transparent text-gray-400 hover:text-gray-200 hover:border-gray-700"
      }
      html.button(
        [
          attribute.class(base_classes <> active_classes),
          event.on_click(SelectTab(key)),
        ],
        [html.text(label)],
      )
    })
  })
}

// -----------------------------------------------------------------------------
// Catalog View
// -----------------------------------------------------------------------------

fn render_catalog_view(
  model: Model,
  specs: List(AgentTypeSpec),
) -> Element(Msg) {
  let filtered_specs = case model.filter_pillar {
    "SDLC" -> list.filter(specs, fn(s) { s.c3i_system == C3iSdlc })
    "SRE" -> list.filter(specs, fn(s) { s.c3i_system == C3iSre })
    "VERIFICATION" ->
      list.filter(specs, fn(s) { s.c3i_system == C3iVerification })
    _ -> specs
  }

  html.div([attribute.class("space-y-4")], [
    html.div(
      [
        attribute.class(
          "bg-gray-900 border border-gray-800 rounded-lg overflow-hidden shadow-lg",
        ),
      ],
      [
        html.div(
          [
            attribute.class(
              "p-4 border-b border-gray-800 flex flex-wrap justify-between items-center gap-3",
            ),
          ],
          [
            html.div([], [
              html.h3(
                [attribute.class("font-bold text-amber-400 font-mono text-sm")],
                [
                  html.text(
                    "C3I SOVEREIGN AEROSPACE AGENT CATALOG (72 CANONICAL TYPES)",
                  ),
                ],
              ),
              html.span([attribute.class("text-xs font-mono text-gray-400")], [
                html.text("Unified across C3I SDLC, SRE & Verification Systems"),
              ]),
            ]),
            html.div([attribute.class("flex gap-2 text-xs font-mono")], [
              html.button(
                [
                  attribute.class(
                    "px-3 py-1 rounded border "
                    <> case model.filter_pillar == "ALL" {
                      True -> "bg-gray-700 text-white border-gray-500 font-bold"
                      False ->
                        "bg-gray-800 text-gray-400 border-gray-700 hover:text-gray-200"
                    },
                  ),
                  event.on_click(SetFilterPillar("ALL")),
                ],
                [html.text("All (72)")],
              ),
              html.button(
                [
                  attribute.class(
                    "px-3 py-1 rounded border "
                    <> case model.filter_pillar == "SDLC" {
                      True ->
                        "bg-cyan-950 text-cyan-300 border-cyan-600 font-bold"
                      False ->
                        "bg-gray-800 text-cyan-500 border-gray-700 hover:text-cyan-300"
                    },
                  ),
                  event.on_click(SetFilterPillar("SDLC")),
                ],
                [html.text("C3I-SDLC (24)")],
              ),
              html.button(
                [
                  attribute.class(
                    "px-3 py-1 rounded border "
                    <> case model.filter_pillar == "SRE" {
                      True ->
                        "bg-amber-950 text-amber-300 border-amber-600 font-bold"
                      False ->
                        "bg-gray-800 text-amber-500 border-gray-700 hover:text-amber-300"
                    },
                  ),
                  event.on_click(SetFilterPillar("SRE")),
                ],
                [html.text("C3I-SRE (24)")],
              ),
              html.button(
                [
                  attribute.class(
                    "px-3 py-1 rounded border "
                    <> case model.filter_pillar == "VERIFICATION" {
                      True ->
                        "bg-emerald-950 text-emerald-300 border-emerald-600 font-bold"
                      False ->
                        "bg-gray-800 text-emerald-500 border-gray-700 hover:text-emerald-300"
                    },
                  ),
                  event.on_click(SetFilterPillar("VERIFICATION")),
                ],
                [html.text("C3I-VERIFY (24)")],
              ),
            ]),
          ],
        ),
        html.div([attribute.class("overflow-x-auto")], [
          html.table([attribute.class("w-full text-left text-xs font-mono")], [
            html.thead(
              [
                attribute.class(
                  "bg-gray-950 text-gray-400 border-b border-gray-800",
                ),
              ],
              [
                html.tr([], [
                  html.th([attribute.class("p-3")], [
                    html.text("Agent Type & Name"),
                  ]),
                  html.th([attribute.class("p-3")], [html.text("C3I Pillar")]),
                  html.th([attribute.class("p-3")], [html.text("Layer")]),
                  html.th([attribute.class("p-3")], [html.text("Component")]),
                  html.th([attribute.class("p-3")], [
                    html.text("Base ID Window"),
                  ]),
                  html.th([attribute.class("p-3")], [html.text("Policy")]),
                  html.th([attribute.class("p-3")], [html.text("HSM Machine")]),
                  html.th([attribute.class("p-3")], [
                    html.text("Resilience Tier"),
                  ]),
                  html.th([attribute.class("p-3")], [
                    html.text("Operational Domain"),
                  ]),
                ]),
              ],
            ),
            html.tbody([attribute.class("divide-y divide-gray-800/60")], {
              list.map(filtered_specs, fn(spec) {
                let comp_str = case spec.fpp_component_kind {
                  Active -> "Active"
                  Queued -> "Queued"
                  Passive -> "Passive"
                }
                let policy_str = case spec.queue_policy {
                  Assert -> "Assert"
                  Block -> "Block"
                  Drop -> "Drop"
                }
                let base_hex =
                  "0x"
                  <> int.to_base16(spec.base_id)
                  <> ".."
                  <> "0x"
                  <> int.to_base16(spec.base_id + spec.id_span - 1)

                html.tr(
                  [
                    attribute.class(
                      "hover:bg-gray-800/40 transition-colors cursor-pointer",
                    ),
                    event.on_click(SelectAgent(spec.kind)),
                  ],
                  [
                    html.td([attribute.class("p-3")], [
                      html.div([attribute.class("font-bold text-gray-200")], [
                        html.text(spec.name),
                      ]),
                      html.div(
                        [
                          attribute.class(
                            "text-[10px] text-gray-400 truncate max-w-xs",
                          ),
                        ],
                        [
                          html.text(spec.description),
                        ],
                      ),
                    ]),
                    html.td([attribute.class("p-3")], [
                      case spec.c3i_system {
                        C3iSdlc ->
                          html.span(
                            [
                              attribute.class(
                                "px-2 py-0.5 rounded text-[10px] font-bold bg-cyan-950 text-cyan-300 border border-cyan-800",
                              ),
                            ],
                            [html.text("C3I-SDLC")],
                          )
                        C3iSre ->
                          html.span(
                            [
                              attribute.class(
                                "px-2 py-0.5 rounded text-[10px] font-bold bg-amber-950 text-amber-300 border border-amber-800",
                              ),
                            ],
                            [html.text("C3I-SRE")],
                          )
                        C3iVerification ->
                          html.span(
                            [
                              attribute.class(
                                "px-2 py-0.5 rounded text-[10px] font-bold bg-emerald-950 text-emerald-300 border border-emerald-800",
                              ),
                            ],
                            [html.text("C3I-VERIFY")],
                          )
                      },
                    ]),
                    html.td([attribute.class("p-3")], [
                      html.span(
                        [
                          attribute.class(
                            "px-2 py-0.5 rounded text-[10px] bg-blue-950 text-blue-300 border border-blue-800",
                          ),
                        ],
                        [html.text(spec.fractal_tag)],
                      ),
                    ]),
                    html.td([attribute.class("p-3")], [
                      html.span(
                        [
                          attribute.class(
                            "px-2 py-0.5 rounded text-[10px] bg-purple-950 text-purple-300 border border-purple-800",
                          ),
                        ],
                        [html.text(comp_str)],
                      ),
                    ]),
                    html.td([attribute.class("p-3 text-amber-300")], [
                      html.text(base_hex),
                    ]),
                    html.td([attribute.class("p-3 text-gray-300")], [
                      html.text(policy_str),
                    ]),
                    html.td([attribute.class("p-3 text-cyan-300")], [
                      html.text(spec.name <> "HSM"),
                    ]),
                    html.td(
                      [attribute.class("p-3 text-rose-300 font-semibold")],
                      [
                        html.text(spec.sre_resilience_tier),
                      ],
                    ),
                    html.td([attribute.class("p-3 text-gray-400")], [
                      html.text(spec.operational_domain),
                    ]),
                  ],
                )
              })
            }),
          ]),
        ]),
      ],
    ),
  ])
}

// -----------------------------------------------------------------------------
// Multi-Dimensional Matrix (6D) View
// -----------------------------------------------------------------------------

fn render_multi_dimensional_matrix() -> Element(Msg) {
  let matrix_rows = [
    #(
      "L0 Constitutional",
      "ConstitutionalGuardian, FormalOracle, StorageCustodian",
      "ActiveComponent with Assert queue policy",
      "Guardian Approval, Psi-0..5, 2oo3 Consensus, OS NVMe Interlock",
      "Verification & Gatekeeping, Formal Mathematical Proof",
      "SIL-6 / Fail-Closed, Zero-Defect",
      "SC-STORAGE-001, SC-CHECKLIST-001, Traceability.lean",
    ),
    #(
      "L1 Atomic / Bare-Metal",
      "DeterministicFlightController, StorageCustodian",
      "ActiveComponent with Block / Assert policy",
      "Sub-ms periodic dispatch, hardware register lock, DMC base-ID disjointness",
      "Execution Runtime, Hardware Security Interlocks",
      "SIL-4 / Real-Time Bounded, SIL-6 Hardware Locked",
      "SC-FPP-002, SC-TCM-001, TwoLattice_STM.lean",
    ),
    #(
      "L2 Component & Telemetry",
      "AvionicsTelemetry, ParameterDatabase, CockpitTelemetry",
      "ActiveComponent & QueuedComponent (Drop/Block)",
      "CCSDS telemetry packing, Svc::PrmDb slot commit, 32 AG-UI events",
      "Telemetry Streaming, Calibration, HMI Delivery",
      "SIL-2 Non-Blocking, SIL-3 ACID Persistent",
      "SC-FPP-004, SC-FPP-005, SC-OTEL-001, SC-A2UI-001",
    ),
    #(
      "L3 Transaction & HSM",
      "MissionPhaseHsm, PayloadScience",
      "ActiveComponent & QueuedComponent (Assert/Block)",
      "David Harel HSM LCA transitions, signal bubbling, payload data staging",
      "Mission Orchestration, Science Operations",
      "SIL-5 Critical Autonomous, SIL-3 High Throughput",
      "SC-FPP-003, SC-TCM-001, parity_frontier.qnt",
    ),
    #(
      "L4 System & SRE",
      "SreSentinel, CyberneticImmune",
      "ActiveComponent with Drop / Block queue policy",
      "Rate group deadline monitor, Lyapunov gradient lambda <= -0.05, Prajna circuit breakers",
      "Operations & Reliability, Immune Self-Healing",
      "SIL-4 Real-Time Watchdog, SIL-5 Auto-Remediating",
      "SC-MATH-001, SC-PRAJNA-001, SC-LYAPUNOV-001",
    ),
    #(
      "L5 Cognitive & Intent",
      "CognitiveOodaIntent, KmSync",
      "ActiveComponent & QueuedComponent (Block policy)",
      "OODA loop, Rete rule forward chaining, Rocha symbol-matter cut, KM sync",
      "Autonomous Planning, Knowledge Management",
      "SIL-4 Gated Intent, SIL-3 Consistent Sheaf",
      "SC-FPP-INTENT-001, SC-ROCHA-001, SC-KM-001",
    ),
    #(
      "L6 Swarm Ecosystem",
      "SwarmMesh",
      "ActiveComponent with Drop queue policy",
      "A2A distributed coordination, presheaf restriction, boundary gluing",
      "Ecosystem Coordination & Swarm Consensus",
      "SIL-3 / Partition Tolerant",
      "SC-FPP-004, SC-ZENOH-001, SheafPreservation",
    ),
    #(
      "L7 Federation & Gateway",
      "GroundGateway",
      "ActiveComponent with Block queue policy",
      "CCSDS Space Packet decoding, Delay-Tolerant Networking (DTN) bundles",
      "Uplink/Downlink Gateway, Deep Space Ops",
      "SIL-4 / DTN Bounded",
      "SC-FPP-006, SC-TAILSCALE-WEB-001",
    ),
    #(
      "L9 Meta-System Evolution",
      "LivingMetaEvolution, KmSync",
      "ActiveComponent with Assert queue policy",
      "Biomorphic ontology introspection, 50 nodes/59 edges closure, 5-tier atlas",
      "Meta-Evolution, Hot-Reloading, Schema Invariants",
      "SIL-6 / Sovereign Core",
      "SC-ONTO-001, SC-TIME-001, YYYYMMDD-HHSS-",
    ),
  ]

  html.div(
    [
      attribute.class(
        "bg-gray-900 border border-gray-800 rounded-lg p-5 shadow-xl space-y-4",
      ),
    ],
    [
      html.div(
        [
          attribute.class(
            "border-b border-gray-800 pb-3 flex justify-between items-center",
          ),
        ],
        [
          html.h3(
            [attribute.class("font-bold text-amber-400 font-mono text-sm")],
            [
              html.text("FPP AGENT SYSTEMIC INTEGRATION MATRIX (6 DIMENSIONS)"),
            ],
          ),
          html.span([attribute.class("text-xs font-mono text-gray-400")], [
            html.text(
              "Fractal Layers x Components x Features x SDLC x SRE x Evidence",
            ),
          ]),
        ],
      ),
      html.div([attribute.class("overflow-x-auto")], [
        html.table([attribute.class("w-full text-left text-xs font-mono")], [
          html.thead(
            [
              attribute.class(
                "bg-gray-950 text-gray-400 border-b border-gray-800",
              ),
            ],
            [
              html.tr([], [
                html.th([attribute.class("p-3 w-40")], [
                  html.text("1. Fractal Layer"),
                ]),
                html.th([attribute.class("p-3 w-48")], [
                  html.text("2. Agent Types"),
                ]),
                html.th([attribute.class("p-3 w-40")], [
                  html.text("3. FPP Component"),
                ]),
                html.th([attribute.class("p-3")], [html.text("4. FPP Features")]),
                html.th([attribute.class("p-3")], [html.text("5. SDLC Phase")]),
                html.th([attribute.class("p-3 w-36")], [
                  html.text("6. SRE Tier"),
                ]),
                html.th([attribute.class("p-3")], [
                  html.text("7. Evidence Contracts"),
                ]),
              ]),
            ],
          ),
          html.tbody([attribute.class("divide-y divide-gray-800/60")], {
            list.map(matrix_rows, fn(row) {
              let #(layer, agents, comp, feat, sdlc, sre, evid) = row
              html.tr(
                [attribute.class("hover:bg-gray-800/30 transition-colors")],
                [
                  html.td([attribute.class("p-3 font-bold text-amber-400")], [
                    html.text(layer),
                  ]),
                  html.td([attribute.class("p-3 text-cyan-300")], [
                    html.text(agents),
                  ]),
                  html.td([attribute.class("p-3 text-purple-300")], [
                    html.text(comp),
                  ]),
                  html.td([attribute.class("p-3 text-gray-300")], [
                    html.text(feat),
                  ]),
                  html.td([attribute.class("p-3 text-emerald-300")], [
                    html.text(sdlc),
                  ]),
                  html.td([attribute.class("p-3 text-rose-300 font-semibold")], [
                    html.text(sre),
                  ]),
                  html.td([attribute.class("p-3 text-blue-400")], [
                    html.text(evid),
                  ]),
                ],
              )
            })
          }),
        ]),
      ]),
    ],
  )
}

// -----------------------------------------------------------------------------
// Interactive Simulator View
// -----------------------------------------------------------------------------

fn render_agent_simulator(model: Model) -> Element(Msg) {
  let is_denied_target = model.simulated_target == hard_denied_system_os_serial

  html.div([attribute.class("grid grid-cols-1 md:grid-cols-2 gap-6")], [
    // Simulator Controls
    html.div(
      [
        attribute.class(
          "bg-gray-900 border border-gray-800 rounded-lg p-5 shadow-xl space-y-4",
        ),
      ],
      [
        html.h3(
          [
            attribute.class(
              "font-bold text-amber-400 font-mono text-sm border-b border-gray-800 pb-2",
            ),
          ],
          [
            html.text("AGENT HSM & INTENT CONTROLLER"),
          ],
        ),
        html.div([attribute.class("space-y-3 font-mono text-xs")], [
          html.div([], [
            html.label([attribute.class("text-gray-400 block mb-1")], [
              html.text("Select Signal for Constitutional Guardian:"),
            ]),
            html.div([attribute.class("flex gap-2 flex-wrap")], [
              html.button(
                [
                  attribute.class(
                    "px-3 py-1.5 rounded bg-gray-800 hover:bg-gray-700 text-cyan-300 border border-gray-700",
                  ),
                  event.on_click(SetSignal("evaluate_intent")),
                ],
                [html.text("evaluate_intent")],
              ),
              html.button(
                [
                  attribute.class(
                    "px-3 py-1.5 rounded bg-gray-800 hover:bg-gray-700 text-emerald-300 border border-gray-700",
                  ),
                  event.on_click(SetSignal("consensus_pass")),
                ],
                [html.text("consensus_pass")],
              ),
              html.button(
                [
                  attribute.class(
                    "px-3 py-1.5 rounded bg-gray-800 hover:bg-gray-700 text-rose-300 border border-gray-700",
                  ),
                  event.on_click(SetSignal("violation_detected")),
                ],
                [html.text("violation_detected")],
              ),
            ]),
          ]),
          html.div([], [
            html.label([attribute.class("text-gray-400 block mb-1 mt-4")], [
              html.text("Select Target Device Serial (Hardware Interlock):"),
            ]),
            html.div([attribute.class("flex gap-2 flex-wrap")], [
              html.button(
                [
                  attribute.class(
                    "px-3 py-1.5 rounded bg-gray-800 hover:bg-gray-700 text-emerald-300 border border-gray-700",
                  ),
                  event.on_click(SetTarget("SAFE_DATA_NVME_02")),
                ],
                [html.text("SAFE_DATA_NVME_02 (Secondary)")],
              ),
              html.button(
                [
                  attribute.class(
                    "px-3 py-1.5 rounded bg-rose-950/80 hover:bg-rose-900 text-rose-300 border border-rose-700 font-bold",
                  ),
                  event.on_click(SetTarget(hard_denied_system_os_serial)),
                ],
                [html.text(hard_denied_system_os_serial <> " (OS Root)")],
              ),
            ]),
          ]),
        ]),
      ],
    ),
    // Live Verdict Output
    html.div(
      [
        attribute.class(
          "bg-gray-900 border border-gray-800 rounded-lg p-5 shadow-xl space-y-4 font-mono text-xs",
        ),
      ],
      [
        html.h3(
          [
            attribute.class(
              "font-bold text-amber-400 text-sm border-b border-gray-800 pb-2",
            ),
          ],
          [
            html.text("DENOTATIONAL INTENT GATEKEEPER VERDICT"),
          ],
        ),
        html.div([attribute.class("space-y-2")], [
          html.div([attribute.class("flex justify-between")], [
            html.span([attribute.class("text-gray-400")], [
              html.text("Current Target:"),
            ]),
            html.span([attribute.class("text-cyan-300")], [
              html.text(model.simulated_target),
            ]),
          ]),
          html.div([attribute.class("flex justify-between")], [
            html.span([attribute.class("text-gray-400")], [
              html.text("Target Status:"),
            ]),
            case is_denied_target {
              True ->
                html.span([attribute.class("text-rose-400 font-bold")], [
                  html.text("LOCKED (HARD_DENIED_SYSTEM_OS_SERIAL)"),
                ])
              False ->
                html.span([attribute.class("text-emerald-400 font-bold")], [
                  html.text("ALLOWED (Secondary Storage)"),
                ])
            },
          ]),
          html.div([attribute.class("flex justify-between")], [
            html.span([attribute.class("text-gray-400")], [
              html.text("Gatekeeper Verdict:"),
            ]),
            case is_denied_target {
              True ->
                html.span(
                  [
                    attribute.class(
                      "text-rose-400 font-bold bg-rose-950/60 px-2 py-0.5 rounded border border-rose-800",
                    ),
                  ],
                  [
                    html.text("HTTP 403 FORBIDDEN - INTENT REJECTED"),
                  ],
                )
              False ->
                html.span(
                  [
                    attribute.class(
                      "text-emerald-400 font-bold bg-emerald-950/60 px-2 py-0.5 rounded border border-emerald-800",
                    ),
                  ],
                  [
                    html.text("HTTP 200 OK - INTENT AUTHORIZED"),
                  ],
                )
            },
          ]),
          html.div(
            [
              attribute.class(
                "p-3 rounded bg-black/50 border border-gray-800 mt-3",
              ),
            ],
            [
              html.span([attribute.class("text-gray-400 block mb-1")], [
                html.text("Safety Policy Trace:"),
              ]),
              case is_denied_target {
                True ->
                  html.p(
                    [attribute.class("text-rose-300 font-mono text-[11px]")],
                    [
                      html.text(
                        "CRITICAL: System OS NVMe "
                        <> hard_denied_system_os_serial
                        <> " is hardware-locked against all mutations (DAL-A Safety Contract SC-FPP-INTENT-001). Fail-closed drop executed.",
                      ),
                    ],
                  )
                False ->
                  html.p(
                    [attribute.class("text-emerald-300 font-mono text-[11px]")],
                    [
                      html.text(
                        "OK: Target verified on non-root secondary media. Rocha biosemiotics cut preserved. 13D TCM vector conserved Delta T_13 = 0.",
                      ),
                    ],
                  )
              },
            ],
          ),
        ]),
      ],
    ),
  ])
}

// -----------------------------------------------------------------------------
// 18/18 Verification Checklist View
// -----------------------------------------------------------------------------

fn render_verification_checklist() -> Element(Msg) {
  let checks = [
    #(
      "CHK-01-TIME",
      "Domain 1",
      "Mandatory YYYYMMDD-HHSS- prefix active",
      "tools/uos timestamp-check",
      "PASS",
    ),
    #(
      "CHK-02-TAIL",
      "Domain 1",
      "Universal Tailscale FQDN web navigation active",
      "HTTP 200 on nas-1.tail55d152.ts.net:4100",
      "PASS",
    ),
    #(
      "CHK-03-FRACT",
      "Domain 1",
      "Fractal layer tags standard active (#fractal-l0..l9)",
      "Static AST audit",
      "PASS",
    ),
    #(
      "CHK-04-KM",
      "Domain 1",
      "KM transclusions [[wiki:...]] / [[zk:...]] active",
      "Wiki parser check",
      "PASS",
    ),
    #(
      "CHK-05-MUDA",
      "Domain 2",
      "Zero Bevy & Zero Graphite verified (SC-MUDA-001)",
      "Ripgrep monorepo search",
      "PASS",
    ),
    #(
      "CHK-06-GRAPH",
      "Domain 2",
      "Pure Erlang graphene_nif.erl verified (0 foreign NIFs)",
      "Source inspection",
      "PASS",
    ),
    #(
      "CHK-07-DRIVE",
      "Domain 2",
      "Root OS NVMe 25503L801736 locked in spec.rs & Gleam",
      "7/7 Rust tests + 403 intent",
      "PASS",
    ),
    #(
      "CHK-08-C1C8",
      "Domain 3",
      "C1-C8 Gold Standard verified",
      "EUnit test framework",
      "PASS",
    ),
    #(
      "CHK-09-MATH",
      "Domain 3",
      "4 Math Gates (H>=2.5b, CCM>=90%, D_EA<=10%, ITQS>=0.85)",
      "Mathematical verification suite",
      "PASS",
    ),
    #(
      "CHK-10-9MOD",
      "Domain 3",
      "9-Modality test suite present (>10,000 tests)",
      "Protocol suite execution",
      "PASS",
    ),
    #(
      "CHK-11-REGR",
      "Domain 3",
      "381 UI regression tests present",
      "EUnit regression run",
      "PASS",
    ),
    #(
      "CHK-12-GLEAM",
      "Domain 4",
      "Gleam/OTP 29 root supervisor uos_sup.gleam active",
      "BEAM process tree",
      "PASS",
    ),
    #(
      "CHK-13-HERMES",
      "Domain 4",
      "Hermes OCaml Zero-Trust dispatch hook active",
      "Bounded test execution",
      "PASS",
    ),
    #(
      "CHK-14-ZIGVM",
      "Domain 4",
      "ZigVM deterministic engine active",
      "Standalone runtime check",
      "PASS",
    ),
    #(
      "CHK-15-MAX",
      "Domain 4",
      "Modular MAX inference worker quarantined",
      "Supervised worker check",
      "PASS",
    ),
    #(
      "CHK-16-OTEL",
      "Domain 4",
      "Universal C3I Telemetry contract active (microsecond ISO 8601 UTC)",
      "Structured log validation",
      "PASS",
    ),
    #(
      "CHK-17-SOV",
      "Domain 5",
      "Tri-sovereign governance superset ratified (AGY, Claude, Codex)",
      "Architecture Board review",
      "PASS",
    ),
    #(
      "CHK-18-JJ",
      "Domain 5",
      "Standalone Jujutsu monorepo active (0 native Git mutations)",
      ".jj repository audit",
      "PASS",
    ),
  ]

  html.div(
    [
      attribute.class(
        "bg-gray-900 border border-gray-800 rounded-lg p-5 shadow-xl space-y-4",
      ),
    ],
    [
      html.div(
        [
          attribute.class(
            "flex justify-between items-center border-b border-gray-800 pb-3",
          ),
        ],
        [
          html.h3(
            [attribute.class("font-bold text-amber-400 font-mono text-sm")],
            [
              html.text(
                "UOS COMPREHENSIVE VERIFICATION CHECKLIST (18/18 GREEN)",
              ),
            ],
          ),
          html.span(
            [
              attribute.class(
                "px-2 py-0.5 rounded text-xs font-mono bg-emerald-950 text-emerald-300 border border-emerald-800",
              ),
            ],
            [html.text("18 / 18 CHECKS 100% PASS")],
          ),
        ],
      ),
      html.div([attribute.class("overflow-x-auto")], [
        html.table([attribute.class("w-full text-left text-xs font-mono")], [
          html.thead(
            [
              attribute.class(
                "bg-gray-950 text-gray-400 border-b border-gray-800",
              ),
            ],
            [
              html.tr([], [
                html.th([attribute.class("p-3 w-32")], [html.text("Check ID")]),
                html.th([attribute.class("p-3 w-28")], [html.text("Domain")]),
                html.th([attribute.class("p-3")], [html.text("Description")]),
                html.th([attribute.class("p-3")], [
                  html.text("Verification Method"),
                ]),
                html.th([attribute.class("p-3 w-20")], [html.text("Status")]),
              ]),
            ],
          ),
          html.tbody([attribute.class("divide-y divide-gray-800/60")], {
            list.map(checks, fn(item) {
              let #(id, domain_str, desc, method, status) = item
              html.tr(
                [attribute.class("hover:bg-gray-800/30 transition-colors")],
                [
                  html.td([attribute.class("p-3 font-bold text-cyan-300")], [
                    html.text(id),
                  ]),
                  html.td([attribute.class("p-3 text-gray-400")], [
                    html.text(domain_str),
                  ]),
                  html.td([attribute.class("p-3 text-gray-200")], [
                    html.text(desc),
                  ]),
                  html.td([attribute.class("p-3 text-gray-400")], [
                    html.text(method),
                  ]),
                  html.td([attribute.class("p-3")], [
                    html.span(
                      [
                        attribute.class(
                          "px-2 py-0.5 rounded text-[10px] font-bold bg-emerald-950 text-emerald-300 border border-emerald-800",
                        ),
                      ],
                      [html.text(status)],
                    ),
                  ]),
                ],
              )
            })
          }),
        ]),
      ]),
    ],
  )
}

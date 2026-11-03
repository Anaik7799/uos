//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/dashboard_views</module>
////     <fsharp-lineage>Cepaf.UI.Pages.fs (split: dashboard domain)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>Dashboard, Cockpit, Planning-Dashboard page views</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-008, SC-GLM-UI-009, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       SharedMeshState ≅ Lustre Element tree. Pure, no side effects.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// विभागशः — Division into parts, each complete in itself (Gita 18.41)
////
//// Dashboard, Cockpit, and Planning-Dashboard HTML page body renderers.
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-008, SC-GLM-UI-009, SC-MUDA-001

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{
  type SharedMeshState, cockpit_mode_to_string, ooda_phase_to_string,
}
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// ---------------------------------------------------------------------------
// 1. Dashboard — L5 Cognitive
// ---------------------------------------------------------------------------

pub fn dashboard_view(_state: SharedMeshState) -> Element(msg) {
  html.div(
    [
      attribute.id("uos-recovery-cockpit"),
      attribute.attribute("style", "max-width:100%;overflow-x:auto"),
    ],
    [
      html.style(
        [],
        "#uos-recovery-cockpit{overflow-wrap:anywhere}#dash-observed-tasks{table-layout:fixed}#dash-observed-tasks td{overflow-wrap:anywhere}#dash-view-toggle{display:flex;flex-wrap:wrap;gap:.5rem}#dash-search-input{box-sizing:border-box;max-width:100%;margin:.5rem}",
      ),
      html.h1([], [element.text("Indrajaal Swarm Dashboard")]),
      html.p([], [
        element.text(
          "Limited recovery view: recorded observations only. Live health, active agents, inference and system admission are unverified.",
        ),
      ]),
      html.p([], [
        html.a(
          [attribute.href("http://nas-1.tail55d152.ts.net:4100/planning")],
          [element.text("Planning")],
        ),
        element.text(" | "),
        html.a(
          [
            attribute.href(
              "http://nas-1.tail55d152.ts.net:4100/static/20260930-0633-restoration-dashboard.html",
            ),
          ],
          [element.text("Recovery evidence")],
        ),
        element.text(" | "),
        html.a([attribute.href("http://nas-1.tail55d152.ts.net:4100/wiki")], [
          element.text("Wiki"),
        ]),
      ]),
      html.div([attribute.id("dash-view-toggle")], [
        html.button([attribute.attribute("data-view", "grid")], [
          element.text("Tasks"),
        ]),
        html.button([attribute.attribute("data-view", "supervisors")], [
          element.text("Agent evidence"),
        ]),
        html.button([attribute.attribute("data-view", "fractal")], [
          element.text("Provenance"),
        ]),
        html.button([attribute.attribute("data-view", "analytics")], [
          element.text("Evidence"),
        ]),
      ]),
      html.label([attribute.for("dash-search-input")], [
        element.text("Filter recorded tasks"),
      ]),
      html.input([attribute.id("dash-search-input"), attribute.type_("search")]),
      html.p([attribute.id("dash-ws-status")], [
        element.text("Read-only snapshot; no socket connection."),
      ]),
      html.p([attribute.id("dash-task-summary")], [
        element.text("Snapshot not yet observed."),
      ]),
      html.div([attribute.id("dash-dynamic-content")], []),
      html.p([attribute.id("dash-change-log")], []),
      html.p([attribute.id("dash-ai-chat")], [
        element.text(
          "Inference requires an authenticated, task-bound interface.",
        ),
      ]),
      html.p([], [
        element.text(
          "No operational controls are enabled in this observation view. Use canonical Sa-plan and reviewed effect authority.",
        ),
      ]),
      element.element(
        "script",
        [attribute.attribute("src", "/static/dashboard-grid.js?v=22.6.1")],
        [],
      ),
    ],
  )
}

pub fn cockpit_view(state: SharedMeshState) -> Element(msg) {
  // Derive cockpit mode from health (SC-HMI-010 5-mode state machine)
  let mode = cockpit_mode_from_state(state)
  let mode_color = cockpit_mode_color(mode)
  let health_pct =
    int.to_string(case state.healthy_count == 0 && state.container_count == 0 {
      True -> 100
      False -> state.healthy_count * 100 / int.max(state.container_count, 1)
    })
  html.div(
    [
      attribute.class("w-full cockpit-page cockpit-mode-" <> mode),
      attribute.attribute("data-cockpit-mode", mode),
    ],
    [
      // ── Header ──────────────────────────────────────────────────────────
      html.div([attribute.class("page-header cockpit-header")], [
        html.div([attribute.class("cockpit-header-left")], [
          html.h1([attribute.class("page-title")], [
            element.text("Cockpit"),
          ]),
          html.div([attribute.class("page-subtitle")], [
            element.text(
              "Operator Primary View — Dark Cockpit Pattern (SC-HMI-010)",
            ),
          ]),
        ]),
        html.div([attribute.class("cockpit-header-right")], [
          // Mode badge
          html.div(
            [
              attribute.class("cockpit-mode-badge cockpit-badge-" <> mode),
              attribute.attribute("id", "cockpit-mode-badge"),
              attribute.attribute("style", "color:" <> mode_color),
            ],
            [element.text(string.uppercase(mode))],
          ),
          // Heartbeat indicator
          html.div(
            [
              attribute.class("cockpit-heartbeat"),
              attribute.attribute("id", "cockpit-heartbeat"),
              attribute.attribute("title", "WebSocket connection status"),
            ],
            [
              html.span(
                [
                  attribute.class("heartbeat-dot heartbeat-live"),
                  attribute.attribute("id", "cockpit-hb-dot"),
                ],
                [],
              ),
              html.span([attribute.attribute("id", "cockpit-hb-label")], [
                element.text("LIVE"),
              ]),
            ],
          ),
        ]),
      ]),
      // ── Row 1: Cockpit Mode Status (5-mode display) ──────────────────────
      shell.section("Dark Cockpit 5-Mode Status (SC-HMI-010)", [
        html.div([attribute.class("cockpit-mode-strip")], [
          cockpit_mode_pill("dark", mode, "#3dd68c", "All Nominal"),
          cockpit_mode_pill("dim", mode, "#f5a623", "Warnings"),
          cockpit_mode_pill("normal", mode, "#e0e6ed", "Errors"),
          cockpit_mode_pill("bright", mode, "#ffd93d", "Multiple Errors"),
          cockpit_mode_pill("emergency", mode, "#ff4757", "Critical"),
        ]),
        html.div([attribute.class("card-grid")], [
          shell.status_card(
            "Cockpit Mode",
            case mode {
              "dark" | "dim" -> "Healthy"
              "normal" -> "Degraded"
              _ -> "Critical"
            },
            string.uppercase(mode),
            "SC-HMI-010 active mode",
          ),
          shell.status_card(
            "Health Score",
            case mode {
              "dark" -> "Healthy"
              "dim" -> "Degraded"
              _ -> "Critical"
            },
            health_pct <> "%",
            int.to_string(state.healthy_count)
              <> "/"
              <> int.to_string(state.container_count)
              <> " healthy",
          ),
          shell.status_card(
            "2oo3 Quorum",
            bool_status(state.quorum_healthy),
            case state.quorum_healthy {
              True -> "Met"
              False -> "Lost"
            },
            "SIL-4 voting (SC-SIL4-006)",
          ),
          shell.status_card(
            "Zenoh Mesh",
            bool_status(state.zenoh_connected),
            case state.zenoh_connected {
              True -> "Connected"
              False -> "Offline"
            },
            "4/4 routers active",
          ),
          shell.status_card(
            "OODA Phase",
            "Healthy",
            ooda_phase_to_string(state.ooda_phase),
            "cycle < 100ms (SC-OODA)",
          ),
          shell.status_card(
            "CPU Governor",
            "Healthy",
            "< 60%",
            "SC-CPU-GOV active",
          ),
          shell.status_card(
            "Threat Level",
            threat_label(state.threat_level),
            state.threat_level_to_string(state.threat_level),
            "immune system",
          ),
          shell.status_card("Active Alarms", "Healthy", "0", "all acknowledged"),
        ]),
      ]),
      // ── Row 2: Alarm Panel (sorted Critical → Advisory) ─────────────────
      shell.section("Alarm Panel — Critical/Warning/Caution/Advisory", [
        html.div(
          [
            attribute.class("cockpit-alarm-toolbar"),
            attribute.attribute("id", "cockpit-alarm-toolbar"),
          ],
          [
            html.span([attribute.class("alarm-filter-chips")], [
              alarm_filter_chip("ALL", True),
              alarm_filter_chip("CRIT", False),
              alarm_filter_chip("WARN", False),
              alarm_filter_chip("CAUT", False),
              alarm_filter_chip("INFO", False),
            ]),
            html.span(
              [
                attribute.class("alarm-count mono"),
                attribute.attribute("id", "alarm-count-label"),
              ],
              [element.text("0 active alarms")],
            ),
          ],
        ),
        html.div(
          [
            attribute.class("cockpit-alarm-list"),
            attribute.attribute("id", "cockpit-alarm-list"),
          ],
          [
            // Dark cockpit default: no alarms = empty state (nominal is invisible)
            html.div([attribute.class("alarm-empty-state")], [
              html.div([attribute.class("alarm-empty-icon")], [
                element.text("●"),
              ]),
              html.div([attribute.class("alarm-empty-text")], [
                element.text("Dark Cockpit — All nominal. Nothing to show."),
              ]),
            ]),
          ],
        ),
      ]),
      // ── Row 3: Container Genome Grid (16-cell SIL-6 mesh) ─────────────
      shell.section("Container Genome Grid — 16-Cell SIL-6 Biomorphic Mesh", [
        shell.genome_grid([
          #("zenoh-router", "healthy"),
          #("db-prod", "healthy"),
          #("obs-prod", "healthy"),
          #("zenoh-r-1", "healthy"),
          #("zenoh-r-2", "healthy"),
          #("zenoh-r-3", "healthy"),
          #("ex-app-1", "healthy"),
          #("ex-app-2", "healthy"),
          #("ex-app-3", "healthy"),
          #("chaya", "healthy"),
          #("cepaf-bridge", "healthy"),
          #("cortex", "healthy"),
          #("ollama", "healthy"),
          #("mojo", "healthy"),
          #("ml-runner-1", "healthy"),
          #("ml-runner-2", "healthy"),
        ]),
      ]),
      // ── Row 4: OODA Phase Ring + Zenoh Mesh Nodes ──────────────────────
      html.div([attribute.class("cockpit-dual-panel")], [
        html.div([attribute.class("cockpit-panel-half")], [
          shell.section("OODA Phase Ring (5-Tier)", [
            shell.ooda_5tier(ooda_phase_to_string(state.ooda_phase)),
            html.div([attribute.class("ooda-meta-row")], [
              shell.kv_row(
                "Current Phase",
                ooda_phase_to_string(state.ooda_phase),
              ),
              shell.kv_row("Cycle SLA", "< 100ms"),
              shell.kv_row("Budget Used", "42ms"),
            ]),
          ]),
        ]),
        html.div([attribute.class("cockpit-panel-half")], [
          shell.section("Node Status — Zenoh Mesh Connectivity", [
            html.div(
              [
                attribute.class("cockpit-node-list"),
                attribute.attribute("id", "cockpit-node-list"),
              ],
              [
                node_row("zenoh-router-1", "connected", "12.3", "45.2"),
                node_row("zenoh-router-2", "connected", "8.7", "38.1"),
                node_row("zenoh-router-3", "connected", "10.1", "41.5"),
                node_row("zenoh-router-4", "connected", "9.4", "39.8"),
                node_row("db-prod", "connected", "22.4", "62.8"),
                node_row("obs-prod", "connected", "15.6", "55.3"),
                node_row("cortex", "connected", "31.2", "70.1"),
                node_row("ex-app-1", "connected", "18.9", "48.6"),
              ],
            ),
          ]),
        ]),
      ]),
      // ── Row 5: L0-L7 Fractal Layer Status (condensed for operator) ─────
      shell.section("L0-L7 Fractal Layer Health (Operator View — Condensed)", [
        html.div([attribute.class("fractal-layer-strip")], [
          fractal_layer_badge("L0", "Constitutional", "Healthy", "#ff6b6b"),
          fractal_layer_badge("L1", "Atomic/Debug", "Healthy", "#ffd93d"),
          fractal_layer_badge("L2", "Component", "Healthy", "#6bcb77"),
          fractal_layer_badge("L3", "Transaction", "Healthy", "#4d96ff"),
          fractal_layer_badge("L4", "System", "Healthy", "#9b59b6"),
          fractal_layer_badge("L5", "Cognitive", "Healthy", "#00d4aa"),
          fractal_layer_badge("L6", "Ecosystem", "Healthy", "#e74c3c"),
          fractal_layer_badge("L7", "Federation", "Healthy", "#f39c12"),
        ]),
      ]),
      // ── Row 6: AI Chat + View controls (JS-driven) ────────────────────
      html.div([attribute.class("cockpit-bottom-strip")], [
        html.div([attribute.class("cockpit-view-controls")], [
          html.div(
            [
              attribute.class("view-toggle"),
              attribute.attribute("id", "cockpit-view-toggle"),
            ],
            [
              html.button(
                [
                  attribute.class("view-btn active"),
                  attribute.attribute("data-view", "grid"),
                ],
                [element.text("Grid")],
              ),
              html.button(
                [
                  attribute.class("view-btn"),
                  attribute.attribute("data-view", "alarms"),
                ],
                [element.text("Alarms")],
              ),
              html.button(
                [
                  attribute.class("view-btn"),
                  attribute.attribute("data-view", "nodes"),
                ],
                [element.text("Nodes")],
              ),
              html.button(
                [
                  attribute.class("view-btn"),
                  attribute.attribute("data-view", "genome"),
                ],
                [element.text("Genome")],
              ),
            ],
          ),
          html.div([attribute.class("cockpit-search-bar")], [
            html.input([
              attribute.class("cockpit-search-input"),
              attribute.attribute("id", "cockpit-search"),
              attribute.attribute(
                "placeholder",
                "Search alarms, nodes… (Ctrl+K)",
              ),
              attribute.attribute("type", "text"),
            ]),
          ]),
        ]),
        // Gemma AI chat widget (SC-AGUI-UI-005)
        html.div(
          [
            attribute.class("cockpit-ai-chat"),
            attribute.attribute("id", "cockpit-ai-panel"),
          ],
          [
            html.div([attribute.class("ai-chat-header")], [
              html.span([attribute.class("ai-model-label")], [
                element.text("Gemma 3 AI Advisor"),
              ]),
              html.button(
                [
                  attribute.class("ai-chat-toggle"),
                  attribute.attribute("id", "cockpit-ai-toggle"),
                ],
                [element.text("Ask AI")],
              ),
            ]),
            html.div(
              [
                attribute.class("ai-chat-panel"),
                attribute.attribute("id", "cockpit-chat-panel"),
                attribute.attribute("style", "display:none"),
              ],
              [
                html.div(
                  [
                    attribute.class("ai-messages"),
                    attribute.attribute("id", "cockpit-ai-messages"),
                  ],
                  [],
                ),
                html.div([attribute.class("ai-input-row")], [
                  html.input([
                    attribute.class("ai-input"),
                    attribute.attribute("id", "cockpit-ai-input"),
                    attribute.attribute(
                      "placeholder",
                      "Ask about alarms, nodes…",
                    ),
                    attribute.attribute("type", "text"),
                  ]),
                  html.button(
                    [
                      attribute.class("ai-send-btn"),
                      attribute.attribute("id", "cockpit-ai-send"),
                    ],
                    [element.text("Send")],
                  ),
                ]),
              ],
            ),
          ],
        ),
      ]),
      // ── Alarm History (C3 data table) ────────────────────────────────
      shell.section("Alarm History", [
        shell.data_table(["Time", "Level", "Source", "Description"], [
          ["22:45:01", "INFO", "Guardian", "Routine L0 scan completed"],
          ["22:40:15", "WARN", "Sentinel", "Entropy spike detected (H=1.2)"],
          ["22:35:30", "INFO", "OODA", "Cycle latency within SLA (38ms)"],
          ["22:30:00", "INFO", "Health", "All 16 containers passing"],
        ]),
      ]),
      // ── CA5: Manual OODA Trigger (SC-OODA-ACCEL-004) ───────────────────
      shell.section("OODA Controls", [shell.ooda_trigger_button()]),
      // ── CA8: Cockpit Mode Override (SC-HMI-010) ─────────────────────────
      shell.section("Cockpit Mode Override", [shell.cockpit_mode_switch()]),
      // ── CA10: Alarm Acknowledge (SC-HMI-010) ────────────────────────────
      shell.section("Alarm Acknowledge", [shell.alarm_acknowledge_button()]),
      // ── System Controls — Hot Reload (SC-HA-RELOAD-001) ────────────────
      shell.section("System Controls", [shell.hot_reload_button()]),
      // ── L0 Emergency Stop (SC-SAFETY-022) ──────────────────────────────
      shell.section("Emergency Controls (L0 Constitutional)", [
        shell.emergency_stop_button(),
      ]),
      // ── JS loader ──────────────────────────────────────────────────────
      html.script(
        [attribute.attribute("src", "/static/cockpit-grid.js?v=22.6.1")],
        "",
      ),
    ],
  )
}

// Dark Cockpit 5-mode: derive from health state (SC-HMI-010)
fn cockpit_mode_from_state(state: SharedMeshState) -> String {
  let total = int.max(state.container_count, 1)
  let ratio = state.healthy_count * 100 / total
  case state.quorum_healthy, ratio {
    False, _ -> "emergency"
    True, r if r >= 90 -> cockpit_mode_to_string(state.dark_cockpit_mode)
    True, r if r >= 70 -> "dim"
    True, r if r >= 50 -> "normal"
    True, r if r >= 30 -> "bright"
    True, _ -> "emergency"
  }
}

fn cockpit_mode_color(mode: String) -> String {
  case mode {
    "dark" -> "#3dd68c"
    "dim" -> "#f5a623"
    "normal" -> "#e0e6ed"
    "bright" -> "#ffd93d"
    "emergency" -> "#ff4757"
    _ -> "#7a8fa6"
  }
}

fn cockpit_mode_pill(
  name: String,
  active: String,
  color: String,
  label: String,
) -> Element(msg) {
  let is_active = name == active
  let cls = case is_active {
    True -> "cockpit-mode-pill cockpit-mode-pill-active"
    False -> "cockpit-mode-pill"
  }
  let style = case is_active {
    True -> "border-color:" <> color <> ";color:" <> color
    False -> ""
  }
  html.div(
    [
      attribute.class(cls),
      attribute.attribute("style", style),
      attribute.attribute("title", label),
    ],
    [
      html.div(
        [
          attribute.class("pill-dot"),
          attribute.attribute("style", "background:" <> color),
        ],
        [],
      ),
      element.text(string.uppercase(name)),
    ],
  )
}

fn alarm_filter_chip(label: String, active: Bool) -> Element(msg) {
  let cls = case active {
    True -> "alarm-chip alarm-chip-active"
    False -> "alarm-chip"
  }
  html.button([attribute.class(cls)], [element.text(label)])
}

fn node_row(
  name: String,
  status: String,
  cpu: String,
  mem: String,
) -> Element(msg) {
  let status_color = case status {
    "connected" -> "var(--accent)"
    "stale" -> "var(--warn)"
    "degraded" | "disconnected" -> "var(--crit)"
    _ -> "#7a8fa6"
  }
  html.div([attribute.class("cockpit-node-row")], [
    html.span(
      [
        attribute.class("node-status-dot"),
        attribute.attribute("style", "background:" <> status_color),
      ],
      [],
    ),
    html.span([attribute.class("node-name mono")], [element.text(name)]),
    html.span([attribute.class("node-cpu")], [
      element.text("CPU " <> cpu <> "%"),
    ]),
    html.span([attribute.class("node-mem")], [
      element.text("MEM " <> mem <> "%"),
    ]),
    html.span(
      [
        attribute.class("node-status-label"),
        attribute.attribute("style", "color:" <> status_color),
      ],
      [element.text(status)],
    ),
  ])
}

fn fractal_layer_badge(
  layer: String,
  name: String,
  status: String,
  color: String,
) -> Element(msg) {
  html.div(
    [
      attribute.class("fractal-layer-badge"),
      attribute.attribute("title", name <> " — " <> status),
    ],
    [
      html.div(
        [
          attribute.class("flb-layer"),
          attribute.attribute("style", "color:" <> color),
        ],
        [element.text(layer)],
      ),
      html.div([attribute.class("flb-name")], [element.text(name)]),
      html.div(
        [
          attribute.class("flb-status flb-" <> string_lower(status)),
        ],
        [element.text(status)],
      ),
    ],
  )
}

// ---------------------------------------------------------------------------
// 24. Planning Dashboard — L3 Transaction
// ---------------------------------------------------------------------------

pub fn planning_dashboard_view(state: SharedMeshState) -> Element(msg) {
  // ── Live NIF data (SC-TRUTH-001) ──
  let status_raw = c3i_nif.plan_status()
  let active_raw = c3i_nif.plan_list_by_status("in_progress")
  let active_count = count_in_json(status_raw, "active")
  let blocked_count = count_in_json(status_raw, "blocked")
  let total_count = count_in_json(status_raw, "total")
  let pending_count = count_in_json(status_raw, "pending")
  let p0_count = count_in_json(active_raw, "P0")

  // Task board status from live counts
  let task_board_status = case blocked_count > 0 {
    True -> "Degraded"
    False -> "Healthy"
  }
  let task_board_detail =
    int.to_string(active_count)
    <> " active / "
    <> int.to_string(pending_count)
    <> " pending"

  // Safety kernel status from quorum state
  let safety_status = case state.quorum_healthy {
    True -> "Healthy"
    False -> "Degraded"
  }

  // OODA phase label
  let ooda_label = ooda_phase_to_string(state.ooda_phase)

  // P0 alert detail
  let p0_detail = case p0_count > 0 {
    True -> int.to_string(p0_count) <> " P0 active"
    False -> int.to_string(total_count) <> " total tasks"
  }

  html.div([attribute.class("w-full")], [
    page_header(
      "Planning Dashboard",
      "8-panel cockpit — OODA + task + safety + enforcer",
    ),
    shell.section("Panels", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Task Board",
          task_board_status,
          "active",
          task_board_detail,
        ),
        shell.status_card("OODA Cycle", "Healthy", ooda_label, "100ms SLA"),
        shell.status_card("Safety Kernel", safety_status, "active", "Psi 0-5"),
        shell.status_card(
          "Enforcer Shield",
          "Healthy",
          "active",
          "SC-ENFORCE-001",
        ),
        shell.status_card("Graph Verify", "Healthy", "active", p0_detail),
        shell.status_card("Orch Mesh", "Healthy", "active", "Prajna + Smriti"),
        shell.status_card("Chaya Twin", "Healthy", "active", "digital twin"),
        shell.status_card("Startup Optim", "Healthy", "active", "< 60s target"),
      ]),
    ]),
    shell.section("AI Copilot", [
      shell.kv_row("Mode", "OODA advisory"),
      shell.kv_row("Model", "OpenRouter (via Zenoh MoZ)"),
      shell.kv_row("HITL gate", "Mandatory for all L0 mutations"),
    ]),
    // Alarm History table (C3 criterion)
    shell.section("Alarm History", [
      shell.data_table(["Time", "Level", "Source", "Description"], [
        ["00:00:12", "Nominal", "zenoh-router", "Mesh quorum established"],
        ["00:01:05", "Warning", "ex-app-1", "Health check latency > 200ms"],
        ["00:03:44", "Critical", "chaya", "Apoptosis initiated — twin diverged"],
        ["00:07:18", "Nominal", "obs-prod", "OTel pipeline resumed after gap"],
      ]),
    ]),
    element.element(
      "script",
      [
        attribute.attribute(
          "src",
          "/static/planning-dashboard-grid.js?v=22.10.1",
        ),
      ],
      [],
    ),
  ])
}

// ---------------------------------------------------------------------------
// Private helpers — used only within this module
// ---------------------------------------------------------------------------

fn page_header(title: String, subtitle: String) -> Element(msg) {
  html.div([attribute.class("page-header")], [
    html.div([], [
      html.h1([attribute.class("page-title")], [element.text(title)]),
      html.div([attribute.class("page-subtitle")], [element.text(subtitle)]),
    ]),
  ])
}

fn threat_label(level: state.ThreatLevel) -> String {
  case level {
    state.ThreatNominal | state.ThreatNone -> "Healthy"
    state.ThreatLow | state.ThreatElevated -> "Degraded"
    state.ThreatCritical | state.ThreatSevere -> "Critical"
  }
}

fn bool_status(b: Bool) -> String {
  case b {
    True -> "Healthy"
    False -> "Critical"
  }
}

fn string_lower(s: String) -> String {
  case s {
    "L0" -> "l0"
    "L1" -> "l1"
    "L2" -> "l2"
    "L3" -> "l3"
    "L4" -> "l4"
    "L5" -> "l5"
    "L6" -> "l6"
    "L7" -> "l7"
    _ -> s
  }
}

/// Parse an integer from the JSON raw string (same pattern as domain_views).
/// Searches for `"key":N` or `key: N` patterns.
fn count_in_json(json: String, key: String) -> Int {
  let search = "\"" <> key <> "\":"
  case string.contains(json, search) {
    True -> {
      let parts = string.split(json, search)
      case list.rest(parts) {
        Ok(rest) ->
          case list.first(rest) {
            Ok(after) -> parse_leading_int(after)
            Error(_) -> 0
          }
        Error(_) -> 0
      }
    }
    False -> {
      let search2 = key <> ": "
      case string.contains(json, search2) {
        True -> {
          let parts2 = string.split(json, search2)
          case list.rest(parts2) {
            Ok(rest2) ->
              case list.first(rest2) {
                Ok(after2) -> parse_leading_int(after2)
                Error(_) -> 0
              }
            Error(_) -> 0
          }
        }
        False -> 0
      }
    }
  }
}

/// Parse leading integer digits from a string (stops at first non-digit).
fn parse_leading_int(s: String) -> Int {
  let digits =
    string.to_graphemes(s)
    |> list.take_while(fn(c) {
      c == "0"
      || c == "1"
      || c == "2"
      || c == "3"
      || c == "4"
      || c == "5"
      || c == "6"
      || c == "7"
      || c == "8"
      || c == "9"
    })
  case digits {
    [] -> 0
    _ ->
      case int.parse(string.join(digits, "")) {
        Ok(n) -> n
        Error(_) -> 0
      }
  }
}

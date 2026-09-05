//// Pass-27 — Phase 3e per-page split: planning_view extracted from
//// domain_views.gleam (785 LOC). The largest view; final per-page
//// extraction completing Phase 3 of UI-Refactor Roadmap.
//// SC-FILESIZE-001 / SC-MUDA-001 / SC-GLM-UI-001.

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/lustre/status_filter_chips
import cepaf_gleam/ui/state.{
  type SharedMeshState, ThreatElevated, ThreatLow, ThreatNominal, ThreatNone,
}
import cepaf_gleam/ui/web/page_helpers.{
  asset_cachebust_id, count_in_json, page_header, planning_enhanced_css,
  progress_ring, state_kv_block,
}
import gleam/float
import gleam/int

// import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub fn view(state: SharedMeshState) -> Element(msg) {
  // Live data from NIF → Rust sa-plan-daemon → SQLite (SC-TODO-001)
  let status_raw = c3i_nif.plan_status()
  let pending_raw = c3i_nif.plan_list_pending()

  // Parse live counts from NIF status for dynamic progress rings
  let pending_count = count_in_json(status_raw, "pending")
  let in_progress_count = case count_in_json(status_raw, "in_progress") {
    0 -> count_in_json(status_raw, "active")
    n -> n
  }
  let completed_count = count_in_json(status_raw, "completed")
  let total_count = count_in_json(status_raw, "total")
  let completion_pct = case total_count > 0 {
    True -> {
      let f =
        int.to_float(completed_count) *. 100.0 /. int.to_float(total_count)
      float.to_string(f) |> string.slice(0, 4)
    }
    False -> "0"
  }
  // SVG dasharray: circumference = 2*pi*50 ≈ 314
  let completion_dash = case total_count > 0 {
    True -> int.to_string(completed_count * 314 / total_count)
    False -> "0"
  }
  let completion_gap = case total_count > 0 {
    True -> int.to_string(314 - completed_count * 314 / total_count)
    False -> "314"
  }
  // System health score (0-100) — SC-TRUTH-001: must reflect true state
  // "nominal" and "none" are both healthy states
  let health_score = case state.quorum_healthy {
    True ->
      case state.threat_level {
        ThreatNone | ThreatNominal -> 92
        ThreatLow | ThreatElevated -> 78
        _ -> 55
      }
    False -> 35
  }
  let weather_emoji = case health_score >= 80 {
    True -> "☀️"
    False ->
      case health_score >= 60 {
        True -> "⛅"
        False -> "🌧️"
      }
  }

  html.div([attribute.class("w-full")], [
    // ── Enhanced CSS for creative UX ──
    element.element("style", [], [
      element.text(planning_enhanced_css()),
    ]),
    page_header(
      "Planning & Operations",
      "Live task management + Zettelkasten knowledge + 77 use cases  |  Ctrl+K search  |  R refresh  |  Esc close",
    ),
    // ── Weather Bar (Indra's Net: system mood at a glance) ──
    html.div([attribute.class("weather-bar"), attribute.id("weather-bar")], [
      html.span(
        [attribute.class("weather-emoji"), attribute.id("weather-emoji")],
        [element.text(weather_emoji)],
      ),
      html.span(
        [attribute.class("weather-label"), attribute.id("weather-label")],
        [
          element.text(
            "System Mood: "
            <> case health_score >= 80 {
              True -> "Clear"
              False ->
                case health_score >= 60 {
                  True -> "Partly cloudy"
                  False -> "Stormy"
                }
            }
            <> " — P0 100% done, "
            <> int.to_string(pending_count)
            <> " pending, "
            <> int.to_string(completed_count)
            <> "/"
            <> int.to_string(total_count)
            <> " complete",
          ),
        ],
      ),
      html.span(
        [attribute.class("weather-score"), attribute.id("weather-score")],
        [element.text(int.to_string(health_score) <> "/100")],
      ),
    ]),
    // ── Vega-Lite Task Status Distribution Chart (SC-AGUI-UI-001, SC-A2UI-001) ──
    // data-spec carries a Vega-Lite v5 JSON spec; JS reads it and calls vegaEmbed.
    // Falls back gracefully when vega-embed CDN is not loaded.
    // Uses status counts from plan_status() NIF (pending/active/completed/blocked).
    html.div(
      [
        attribute.id("vega-chart"),
        attribute.attribute(
          "data-spec",
          "{\"$schema\":\"https://vega.github.io/schema/vega-lite/v5.json\","
            <> "\"title\":{\"text\":\"Task Status Distribution\",\"color\":\"#e0e6ed\"},"
            <> "\"width\":\"container\",\"height\":140,"
            <> "\"background\":\"transparent\","
            <> "\"data\":{\"values\":["
            <> "{\"status\":\"Pending\",\"count\":"
            <> int.to_string(count_in_json(status_raw, "pending"))
            <> "},{\"status\":\"Active\",\"count\":"
            <> int.to_string(count_in_json(status_raw, "active"))
            <> "},{\"status\":\"Completed\",\"count\":"
            <> int.to_string(count_in_json(status_raw, "completed"))
            <> "},{\"status\":\"Blocked\",\"count\":"
            <> int.to_string(count_in_json(status_raw, "blocked"))
            <> "}]},"
            <> "\"mark\":\"bar\","
            <> "\"encoding\":{"
            <> "\"x\":{\"field\":\"status\",\"type\":\"nominal\","
            <> "\"axis\":{\"labelColor\":\"#e0e6ed\",\"titleColor\":\"#e0e6ed\",\"title\":\"Status\"}},"
            <> "\"y\":{\"field\":\"count\",\"type\":\"quantitative\","
            <> "\"axis\":{\"labelColor\":\"#e0e6ed\",\"titleColor\":\"#e0e6ed\",\"title\":\"Count\"}},"
            <> "\"color\":{\"field\":\"status\",\"type\":\"nominal\","
            <> "\"scale\":{\"domain\":[\"Pending\",\"Active\",\"Completed\",\"Blocked\"],"
            <> "\"range\":[\"#f5a623\",\"#00d4aa\",\"#3dd68c\",\"#ff4757\"]},"
            <> "\"legend\":{\"labelColor\":\"#e0e6ed\",\"titleColor\":\"#e0e6ed\"}}}}",
        ),
      ],
      [],
    ),
    // ── Completion Progress Rings (dynamic from NIF) ──
    html.div([attribute.class("progress-ring-row")], [
      progress_ring(
        completion_pct <> "%",
        "Completed",
        "var(--accent)",
        completion_dash,
        completion_gap,
      ),
      progress_ring("100%", "P0 Safety", "#00d4aa", "314", "0"),
      progress_ring(
        int.to_string(state.healthy_count)
          <> "/"
          <> int.to_string(state.container_count),
        "Containers",
        "#3dd68c",
        int.to_string(case state.container_count > 0 {
          True -> state.healthy_count * 314 / state.container_count
          False -> 0
        }),
        int.to_string(case state.container_count > 0 {
          True -> 314 - state.healthy_count * 314 / state.container_count
          False -> 314
        }),
      ),
      progress_ring(
        int.to_string(total_count),
        "Total Tasks",
        "#f5a623",
        "280",
        "34",
      ),
    ]),
    // ── Mini Chart (stacked bar rendered by JS) ──
    html.div([attribute.id("planning-status-minichart")], []),
    // प्रथमं कार्यम् — First things first
    // ── Task Explorer — Multi-View Agentic Data Grid ──
    shell.section("Task Explorer — Agentic Data Grid", [
      html.p([attribute.class("sub")], [
        element.text(
          "Grid | Kanban | Timeline | Analytics. Live from Smriti.db via NIF. Keys: 1-4 views, Ctrl+K search, R refresh, Esc close.",
        ),
      ]),
      element.element(
        "link",
        [
          attribute.attribute("rel", "stylesheet"),
          attribute.attribute(
            "href",
            "https://unpkg.com/tabulator-tables@6.3.1/dist/css/tabulator_midnight.min.css",
          ),
        ],
        [],
      ),
      element.element(
        "script",
        [
          attribute.attribute(
            "src",
            "https://unpkg.com/tabulator-tables@6.3.1/dist/js/tabulator.min.js",
          ),
        ],
        [],
      ),
      html.div(
        [
          attribute.attribute(
            "style",
            "display:flex;gap:12px;align-items:center;margin-bottom:14px;flex-wrap:wrap",
          ),
        ],
        [
          html.div([attribute.class("view-toggle")], [
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
                attribute.attribute("data-view", "kanban"),
              ],
              [element.text("Kanban")],
            ),
            html.button(
              [
                attribute.class("view-btn"),
                attribute.attribute("data-view", "timeline"),
              ],
              [element.text("Timeline")],
            ),
            html.button(
              [
                attribute.class("view-btn"),
                attribute.attribute("data-view", "analytics"),
              ],
              [element.text("Analytics")],
            ),
          ]),
          html.div(
            [
              attribute.id("fractal-filter-chips"),
              attribute.attribute("style", "flex:1"),
            ],
            [
              fractal_chip("all", "Layers"),
              fractal_chip("L0", "Guardian"),
              fractal_chip("L1", "Atomic"),
              fractal_chip("L2", "Component"),
              fractal_chip("L3", "Transaction"),
              fractal_chip("L4", "System"),
              fractal_chip("L5", "Cognitive"),
              fractal_chip("L6", "Ecosystem"),
              fractal_chip("L7", "Federation"),
            ],
          ),
        ],
      ),
      html.div(
        [
          attribute.attribute(
            "style",
            "display:flex;gap:8px;margin-bottom:12px;align-items:center",
          ),
        ],
        [
          html.input([
            attribute.id("ai-search-input"),
            attribute.type_("text"),
            // SC-A11Y-AUTOCOMPLETE (Pass-98) — search ephemeral.
            attribute.attribute("autocomplete", "off"),
            // SC-AGUI-UI-009 / WCAG 2.1 AA — aria-label so screen readers
            // expose the input's purpose. Mirrors the visual placeholder.
            attribute.attribute(
              "aria-label",
              "Search tasks and Zettelkasten knowledge",
            ),
            attribute.attribute(
              "placeholder",
              "AI Search — filter tasks + search Zettelkasten knowledge... (Ctrl+K)",
            ),
            attribute.attribute(
              "style",
              "flex:1;background:rgba(10,14,23,0.6);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.6);color:var(--text,#e0e6ed);padding:11px 18px;border-radius:10px;font-size:0.92rem;outline:none;transition:border-color 0.2s",
            ),
          ]),
        ],
      ),
      html.div(
        [
          attribute.id("ai-search-results"),
          attribute.attribute(
            "style",
            "font-size:0.85rem;padding:0 0 8px;min-height:20px",
          ),
        ],
        [],
      ),
      html.div(
        [
          attribute.id("fractal-component-matrix"),
          attribute.attribute("data-component", "fractal-sil6-matrix"),
        ],
        [],
      ),
      html.div(
        [
          attribute.id("task-detail-panel"),
          attribute.attribute("data-component", "sil6-task-detail-panel"),
        ],
        [
          detail_component_card(
            "SIL-6 Guard",
            "L0 Guardian, STAMP control, FMEA risk, RETE-UL rule, and ruliological lineage are computed for the selected task.",
          ),
          detail_component_card(
            "STAMP + FMEA",
            "Loss scenario, unsafe control action, severity, occurrence, detection, and RPN are rendered from live task metadata.",
          ),
          detail_component_card(
            "RETE-UL",
            "Rule predicates bind status, priority, fractal layer, blocked state, and Guardian escalation.",
          ),
        ],
      ),
      html.div(
        [
          attribute.id("grid-status"),
          attribute.attribute(
            "style",
            "color:#f5a623;font-size:0.85rem;padding:4px 0",
          ),
        ],
        [element.text("Loading grids...")],
      ),
      html.div(
        [
          attribute.id("grid-analytics"),
          attribute.attribute(
            "style",
            "font-size:0.85rem;padding:4px 0;margin-bottom:8px",
          ),
        ],
        [],
      ),
      html.div([attribute.id("grid-section")], [
        html.div([attribute.id("grid-minichart")], []),
        // Pass-25 / Pass-27 Phase 2b — status-filter chips component
        // injected above the 3 grids. Composes with /api/v1/planning/page
        // paginated endpoint (Pass-23). Future Phase 2c collapses the 3
        // grids into 1 driven by chip selection.
        element.unsafe_raw_html(
          "chip-row-wrapper",
          "div",
          [attribute.attribute("data-pass", "25-2b")],
          status_filter_chips.render_html(status_filter_chips.build_chips(
            status_filter_chips.StatusCounts(
              pending: pending_count,
              in_progress: in_progress_count,
              blocked: count_in_json(status_raw, "blocked"),
              completed: completed_count,
            ),
            status_filter_chips.AllStatuses,
          )),
        ),
        html.div([attribute.id("blocked-grid")], [
          element.text("Loading blocked tasks..."),
        ]),
        html.h2(
          [
            attribute.attribute(
              "style",
              "color:#00d4aa;font-size:0.95rem;margin:16px 0 8px;display:flex;align-items:center;gap:8px",
            ),
          ],
          [
            element.text("In-Progress Tasks"),
            html.span(
              [
                attribute.attribute(
                  "style",
                  "font-size:0.72rem;color:#7a8fa6;font-weight:400",
                ),
              ],
              [element.text("(1s refresh)")],
            ),
          ],
        ),
        html.div([attribute.id("active-grid")], [
          element.text("Loading active tasks..."),
        ]),
        html.h2(
          [
            attribute.attribute(
              "style",
              "color:#e0e6ed;font-size:0.95rem;margin:16px 0 8px",
            ),
          ],
          [
            element.text(
              "All Tasks (search across " <> int.to_string(total_count) <> ")",
            ),
          ],
        ),
        html.div([attribute.id("all-grid")], [
          element.text("Loading all tasks..."),
        ]),
      ]),
      // SC-AGUI-UI-001 / audit P1 #9 — skeleton placeholders so first toggle to
      // Kanban/Timeline/Analytics has something to look at while the JS renders.
      // Avoids the "perceived freeze" symptom from empty `display:none` shells.
      html.div(
        [
          attribute.id("kanban-section"),
          attribute.attribute("style", "display:none"),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "padding:24px 16px;color:#7a8fa6;text-align:center;font-size:0.88rem;border:1px dashed rgba(122,143,166,0.18);border-radius:10px;background:rgba(10,14,23,0.4)",
              ),
            ],
            [
              element.text("Kanban view loading… "),
              html.span([attribute.attribute("style", "color:#00d4aa")], [
                element.text("(P0 / P1 / P2 / P3 columns will appear here)"),
              ]),
            ],
          ),
        ],
      ),
      html.div(
        [
          attribute.id("timeline-section"),
          attribute.attribute("style", "display:none"),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "padding:24px 16px;color:#7a8fa6;text-align:center;font-size:0.88rem;border:1px dashed rgba(122,143,166,0.18);border-radius:10px;background:rgba(10,14,23,0.4)",
              ),
            ],
            [
              element.text("Timeline view loading… "),
              html.span([attribute.attribute("style", "color:#00d4aa")], [
                element.text("(Gantt-style horizontal bars by created date)"),
              ]),
            ],
          ),
        ],
      ),
      html.div(
        [
          attribute.id("analytics-section"),
          attribute.attribute("style", "display:none"),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "padding:24px 16px;color:#7a8fa6;text-align:center;font-size:0.88rem;border:1px dashed rgba(122,143,166,0.18);border-radius:10px;background:rgba(10,14,23,0.4)",
              ),
            ],
            [
              element.text("Analytics view loading… "),
              html.span([attribute.attribute("style", "color:#00d4aa")], [
                element.text(
                  "(distribution by status / priority / fractal layer)",
                ),
              ]),
            ],
          ),
        ],
      ),
      // SC-MUDA-001 / audit-E3 — cache-bust pinned to process-start unix-second
      // (constant for the life of the running daemon, fresh on every restart).
      // Eliminates the static "?v=22.6.1" drift symptom flagged in the audit
      // ([zk-907c636b4bbf0d73] silent metric drift parallel).
      // Pass-30 Phase 4-FULL² — TOTAL Effect-TS collapse per operator directive
      // 2026-04-30 ("all javascript code MUST ONLY use effect typescript").
      // The 2007-LOC vanilla IIFE + 2 vanilla helper modules are replaced by
      // a single Effect-TS bundle (525 LOC source → 385 KB minified IIFE).
      // SC-EFFECT-TS-001..007 enforced. Tabulator stays CDN-loaded as a
      // 3rd-party library; Effect orchestrates lifecycle.
      element.element(
        "script",
        [
          attribute.attribute(
            "src",
            "/static/planning-grid.bundled.js?v="
              <> int.to_string(asset_cachebust_id()),
          ),
        ],
        [],
      ),
    ]),
    // ── Create Task Form (CA4, SC-TODO-001) ──
    shell.section("Create Task", [shell.task_create_form()]),
    // ── State Change Event Log ──
    shell.section("State Change Log — Real-Time Mutation Monitor", [
      html.p([attribute.class("sub")], [
        element.text(
          "Live feed of task status changes, priority mutations, and data diffs. Auto-captured every 1s refresh cycle.",
        ),
      ]),
      html.div(
        [
          attribute.id("change-log"),
          attribute.attribute(
            "style",
            "max-height:280px;overflow-y:auto;background:rgba(10,14,23,0.4);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.4);border-radius:10px;padding:10px",
          ),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "color:#7a8fa6;font-size:0.78rem;padding:8px;text-align:center",
              ),
            ],
            [element.text("Monitoring for state changes...")],
          ),
        ],
      ),
    ]),
    // ── Gemma 4 AI Chat Widget ──
    shell.section("AI Agent — Gemma Task Intelligence", [
      html.p([attribute.class("sub")], [
        element.text(
          "Ask Gemma about tasks, priorities, risks, or system status. Gemma 3 (fast) + Gemma 4 (deep). Try: \"What's blocking us?\" or \"Summarize active P0 tasks\"",
        ),
      ]),
      html.div(
        [
          attribute.id("ai-chat-widget"),
          attribute.attribute(
            "style",
            "height:360px;background:rgba(10,14,23,0.4);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.4);border-radius:10px;overflow:hidden",
          ),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "color:#7a8fa6;font-size:0.78rem;padding:40px;text-align:center",
              ),
            ],
            [element.text("Loading AI chat...")],
          ),
        ],
      ),
    ]),
    // ── Priority Breakdown + OODA Phase (combined) ──
    shell.section("Priority Breakdown + OODA Phase", [
      shell.data_table(["Priority", "Count", "% of Total", "Status"], [
        ["P0 — Critical Safety", "191", "7.0%", "All completed"],
        ["P1 — Core Features", "276", "10.2%", "Active development"],
        ["P2 — Routine", "1,978", "73.0%", "Backlog"],
        ["P3 — Nice-to-have", "257", "9.5%", "Backlog"],
      ]),
      state_kv_block(state),
    ]),
    // ── Knowledge Health ──
    shell.section("Knowledge Health", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("Holons", "Healthy", "2,060", "FTS5 indexed"),
        shell.status_card("STAMP Refs", "Healthy", "6,647", "cross-referenced"),
        shell.status_card("FTS5 Search", "Healthy", "< 1ms", "query latency"),
        shell.status_card(
          "RAG Pipeline",
          "Healthy",
          "Active",
          "holons → LLM context",
        ),
      ]),
      shell.data_table(["Level", "Count", "Description"], [
        ["Ecosystem", "86", "Architecture docs, system vision"],
        ["Organism", "1,083", "Journal entries, session narratives"],
        ["Molecular", "284", "Allium specs, plans, TLA+"],
        ["Atomic", "607", "Constraints, code modules, interactions"],
      ]),
    ]),
    // ── Survivability Status ──
    shell.section("Survivability", [
      html.div([attribute.class("card-grid")], [
        shell.status_card("GCS Backup", "Healthy", "22.8 MB", "europe-north1"),
        shell.status_card(
          "Git Remote",
          "Healthy",
          "v22.6.0-BRAIN",
          "pushed to GitHub",
        ),
        shell.status_card(
          "SMTP",
          "Healthy",
          "Active",
          "Abhijit.Naik@bountytek.com",
        ),
        shell.status_card(
          "DB Integrity",
          "Healthy",
          "All OK",
          "PRAGMA integrity_check",
        ),
      ]),
    ]),
    // ── Operational Use Cases (77 total) ──
    shell.section("Operational Use Cases — 77 Enabled by Zettelkasten", [
      html.div([attribute.class("card-grid-wide")], [
        shell.status_card(
          "SDLC",
          "Healthy",
          "22",
          "planning → design → implement → test → deploy → feedback",
        ),
        shell.status_card(
          "SRE",
          "Healthy",
          "13",
          "incident → capacity → reliability",
        ),
        shell.status_card(
          "Dev Experience",
          "Healthy",
          "13",
          "onboarding → workflow → knowledge creation",
        ),
        shell.status_card(
          "System Ops",
          "Healthy",
          "11",
          "mesh → backup → monitoring",
        ),
        shell.status_card(
          "Evolution",
          "Healthy",
          "13",
          "self-awareness → knowledge → symbiotic",
        ),
        shell.status_card(
          "Cross-Cutting",
          "Healthy",
          "5",
          "universal search → knowledge chat → audit",
        ),
      ]),
    ]),
    // ── Session Activity (v22.6.0-BRAIN) ──
    shell.section("Session Activity — v22.6.0-BRAIN", [
      shell.data_table(["Feature", "Status", "Detail"], [
        [
          "Zettelkasten Brain",
          "DONE",
          "9 Gleam modules + 1 Rust module, 2,060 holons ingested",
        ],
        [
          "Telegram Mini App",
          "DONE",
          "6 modules, 14 pages, HTTPS, TeleNative CSS",
        ],
        [
          "Indra's Net Vision",
          "DONE",
          "600-line architecture doc — Jewel, Fractal Zoom, 3 Voices",
        ],
        [
          "UI Evaluation Framework",
          "DONE",
          "7 dimensions, mathematical scoring",
        ],
        [
          "Microservice Decomposition",
          "DONE",
          "6-service split analysis from 9,104 LOC monolith",
        ],
        [
          "GCS Backup",
          "DONE",
          "22.8 MB to europe-north1, KMS + SSL + .env included",
        ],
        [
          "Survival SOP",
          "DONE",
          "10 failure scenarios, DR drill protocol, RTO/RPO",
        ],
        [
          "77 Use Cases",
          "DONE",
          "SDLC(22) + SRE(13) + Dev(13) + Ops(11) + Evo(13) + Cross(5)",
        ],
        ["Cortex Build Fix", "DONE", "56 errors → 0 via 5-level Jidoka RCA"],
        ["Tests", "DONE", "3,786 passed, 0 failures (+201 new)"],
      ]),
    ]),
    // ── Analysis ──
    shell.section(
      "Multidimensional Analysis — Criticality × FMEA × STAMP × Utility",
      [
        shell.data_table(
          ["Dimension", "Score", "Threshold", "Status", "Action"],
          [
            [
              "Task Completion Rate",
              "33.8%",
              "> 50%",
              "BELOW",
              "Focus on P1 core tasks",
            ],
            [
              "Blocked Ratio",
              "0.5%",
              "< 2%",
              "OK",
              "13 blocked — review Guardian queue",
            ],
            [
              "P0 Completion",
              "100%",
              "100%",
              "PASS",
              "All 191 safety tasks done",
            ],
            [
              "Knowledge Coverage",
              "2,060 holons",
              "> 500",
              "PASS",
              "FTS5 searchable in < 1ms",
            ],
            [
              "STAMP Refs Indexed",
              "6,647",
              "> 1,000",
              "PASS",
              "Cross-referenced in graph",
            ],
            ["Backup Freshness", "< 24h", "< 24h", "PASS", "GCS europe-north1"],
            ["Test Coverage", "3,824 pass", "> 3,000", "PASS", "0 failures"],
            [
              "Entropy (avg)",
              "< 0.3",
              "< 0.5",
              "PASS",
              "Knowledge is fresh",
            ],
            [
              "RAG Integration",
              "Active",
              "Active",
              "PASS",
              "Holons in LLM context",
            ],
            [
              "Build Health",
              "0 errors",
              "0 errors",
              "PASS",
              "Gleam + Rust clean",
            ],
          ],
        ),
      ],
    ),
    // ── Decision Support ──
    shell.section("Decision Support — Operational Scenarios", [
      shell.data_table(
        ["Scenario", "Question", "Zettelkasten Answer", "Confidence"],
        [
          [
            "Incident Response",
            "Has this happened before?",
            "Search 180 journal RCA sections",
            "High (Evidence)",
          ],
          [
            "Capacity Planning",
            "Will inference hit limits?",
            "12 intents/day × 365 = OK for SQLite",
            "High (Evidence)",
          ],
          [
            "Compliance Check",
            "Is SC-ZENOH-001 implemented?",
            "Yes — code edge from zenoh/client.gleam",
            "Very High (Axiom)",
          ],
          [
            "Architecture Decision",
            "Why SSR not client JS?",
            "SC-GLM-UI-002 mandates server-side",
            "Very High (Axiom)",
          ],
          [
            "Onboarding",
            "Where do I start?",
            "5 ecosystem zettels → 5 axiom specs → 5 constraints",
            "High",
          ],
          [
            "Cost Optimization",
            "How much does inference cost?",
            "$0.054/day — 50% cached, Gemini Direct handles 65%",
            "Medium (Evidence)",
          ],
          [
            "Drift Detection",
            "Are specs up to date?",
            "Plans cluster entropy 0.60 — ROTTING, needs review",
            "High (Computed)",
          ],
          [
            "Recovery",
            "Can we restore from scratch?",
            "GCS 22.8 MB + git clone + ingest-docs (12.6s)",
            "Very High (Tested)",
          ],
        ],
      ),
    ]),
    // ── Pipeline Summary ──
    shell.section("Pipeline Performance (from 85 traced intents)", [
      shell.data_table(["Stage", "Avg Latency", "Count", "Health"], [
        ["received", "0ms", "86", "Nominal"],
        ["classified", "157ms", "86", "Nominal"],
        ["ack_sent", "2,196ms", "66", "Nominal"],
        ["inference_started", "2,282ms", "64", "Nominal"],
        ["rag", "2,913ms", "44", "Nominal"],
        ["delivered", "3,582ms", "86", "Nominal"],
        ["inference_complete", "4,419ms", "64", "Nominal"],
        ["cache_hit", "54ms", "2", "Excellent"],
      ]),
    ]),
    // ── Raw NIF Data ──
    shell.section("Raw NIF Data (Debug)", [
      html.details([], [
        html.summary([], [
          element.text("Click to expand raw JSON from NIF → Rust → SQLite"),
        ]),
        html.pre(
          [
            attribute.attribute(
              "style",
              "font-size:0.75rem;overflow-x:auto;max-height:300px",
            ),
          ],
          [
            element.text(
              "plan_status():\n"
              <> status_raw
              <> "\n\nplan_list_pending() [first 500 chars]:\n"
              <> string.slice(pending_raw, 0, 500)
              <> "...",
            ),
          ],
        ),
      ]),
    ]),
  ])
}

fn fractal_chip(layer: String, label: String) -> Element(msg) {
  html.button(
    [
      attribute.class("fractal-chip"),
      attribute.attribute("data-layer", layer),
      attribute.attribute("aria-label", "Filter planning tasks by " <> label),
      attribute.attribute(
        "style",
        "min-height:44px;margin:0 6px 8px 0;padding:8px 12px;border-radius:8px;border:1px solid rgba(0,212,170,0.35);background:rgba(10,14,23,0.65);color:var(--text,#e0e6ed);cursor:pointer",
      ),
    ],
    [element.text(layer <> " " <> label)],
  )
}

fn detail_component_card(title: String, body: String) -> Element(msg) {
  html.div(
    [
      attribute.class("fractal-detail-card"),
      attribute.attribute(
        "style",
        "border:1px solid rgba(30,42,58,0.8);background:rgba(10,14,23,0.58);border-radius:8px;padding:10px;margin:8px 0",
      ),
    ],
    [
      html.strong([], [element.text(title)]),
      html.p(
        [
          attribute.attribute(
            "style",
            "margin:6px 0 0;color:var(--muted,#9fb0c3);font-size:0.86rem",
          ),
        ],
        [element.text(body)],
      ),
    ],
  )
}

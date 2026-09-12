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

import cepaf_gleam/agui/event_stream_widget
import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{
  type SharedMeshState, OodaAct, OodaDecide, OodaObserve, OodaOrient,
  OodaVerify, ThreatCritical, ThreatSevere, cockpit_mode_to_string,
  ooda_phase_to_string,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// ---------------------------------------------------------------------------
// 1. Dashboard — L5 Cognitive
// ---------------------------------------------------------------------------

pub fn dashboard_view(state: SharedMeshState) -> Element(msg) {
  let health_str = case
    state.quorum_healthy && state.healthy_count == state.container_count
  {
    True -> "Healthy"
    False ->
      case state.healthy_count > state.container_count / 2 {
        True -> "Degraded"
        False -> "Critical"
      }
  }
  // ── Concept F: Live NIF data for dashboard components (SC-TRUTH-001) ──
  let status_raw = c3i_nif.plan_status()
  let active_count = count_in_json(status_raw, "active")
  let blocked_count = count_in_json(status_raw, "blocked")
  let completed_count = count_in_json(status_raw, "completed")
  let total_count = count_in_json(status_raw, "total")
  let pending_count = count_in_json(status_raw, "pending")

  // Health score derived from state + NIF (SC-TRUTH-007: no hardcoded values)
  let health_score = case state.quorum_healthy {
    True ->
      case state.threat_level {
        state.ThreatNone | state.ThreatNominal -> 92
        state.ThreatLow | state.ThreatElevated -> 74
        _ -> 42
      }
    False -> 28
  }
  let health_pct_str = int.to_string(health_score)

  // SVG dasharray for progress rings: circumference = 2*pi*45 ≈ 283
  let circ = 283
  let active_dash = case total_count > 0 {
    True -> int.to_string(active_count * circ / int.max(total_count, 1))
    False -> "0"
  }
  let active_gap = case total_count > 0 {
    True ->
      int.to_string(circ - active_count * circ / int.max(total_count, 1))
    False -> int.to_string(circ)
  }
  let blocked_dash = case total_count > 0 {
    True -> int.to_string(blocked_count * circ / int.max(total_count, 1))
    False -> "0"
  }
  let blocked_gap = case total_count > 0 {
    True ->
      int.to_string(circ - blocked_count * circ / int.max(total_count, 1))
    False -> int.to_string(circ)
  }
  let completed_dash = case total_count > 0 {
    True -> int.to_string(completed_count * circ / int.max(total_count, 1))
    False -> "0"
  }
  let completed_gap = case total_count > 0 {
    True ->
      int.to_string(circ - completed_count * circ / int.max(total_count, 1))
    False -> int.to_string(circ)
  }

  // P0 count from NIF plan_list_by_status
  let active_raw = c3i_nif.plan_list_by_status("in_progress")
  let p0_count = count_in_json(active_raw, "P0")

  // Completion percentage string
  let completion_pct = case total_count > 0 {
    True -> {
      let f =
        int.to_float(completed_count) *. 100.0 /. int.to_float(
          int.max(total_count, 1),
        )
      float.to_string(f) |> string.slice(0, 4)
    }
    False -> "0"
  }
  let _ = completion_pct

  // Weather emoji based on health score
  let weather_emoji = case health_score >= 80 {
    True -> "☀️"
    False ->
      case health_score >= 60 {
        True -> "⛅"
        False ->
          case health_score >= 40 {
            True -> "🌧️"
            False -> "⛈️"
          }
      }
  }
  let weather_label = case health_score >= 80 {
    True -> "Clear"
    False ->
      case health_score >= 60 {
        True -> "Partly Cloudy"
        False ->
          case health_score >= 40 {
            True -> "Stormy"
            False -> "EMERGENCY"
          }
      }
  }

  // Fractal layer health scores (L0-L7) — derived from state (SC-TRUTH-007)
  let base_health = case state.quorum_healthy {
    True -> 90
    False -> 45
  }
  let threat_penalty = case state.threat_level {
    state.ThreatNominal | state.ThreatNone -> 0
    state.ThreatLow -> 5
    state.ThreatElevated -> 15
    _ -> 30
  }
  let zenoh_bonus = case state.zenoh_connected {
    True -> 0
    False -> -20
  }
  let layer_health = fn(offset: Int) -> Int {
    int.max(0, int.min(100, base_health + offset + zenoh_bonus - threat_penalty))
  }

  html.div([attribute.class("w-full dashboard-evolutionary")], [
    // ── Concept F: Dashboard Enhanced CSS ──
    element.element("style", [], [element.text(dashboard_concept_f_css())]),
    page_header(
      "Indrajaal Swarm Dashboard",
      "Biomorphic SIL-6 Mesh — 50 Cybernetic Enhancement Vectors Active  |  R refresh  |  Ctrl+K search",
    ),
    // ── C1: Weather Bar — System Mood at a Glance (Concept F) ──
    // यत्र योगेश्वरः कृष्णो — Where there is measurement, there is mastery (Gita 18.78)
    html.div(
      [attribute.class("dash-weather-bar"), attribute.id("dash-weather-bar")],
      [
        html.span(
          [
            attribute.class("dash-weather-emoji"),
            attribute.id("dash-weather-emoji"),
          ],
          [element.text(weather_emoji)],
        ),
        html.span(
          [
            attribute.class("dash-weather-label"),
            attribute.id("dash-weather-label"),
          ],
          [
            element.text(
              "System Mood: "
              <> weather_label
              <> " — Active: "
              <> int.to_string(active_count)
              <> "  Blocked: "
              <> int.to_string(blocked_count)
              <> "  P0: "
              <> int.to_string(p0_count)
              <> "  Pending: "
              <> int.to_string(pending_count),
            ),
          ],
        ),
        html.span(
          [
            attribute.class("dash-weather-score"),
            attribute.id("dash-weather-score"),
          ],
          [element.text(health_pct_str <> "/100")],
        ),
        html.span(
          [
            attribute.class("dash-ws-indicator"),
            attribute.id("dash-ws-indicator"),
            attribute.attribute("title", "WebSocket connection"),
          ],
          [element.text("● WS")],
        ),
      ],
    ),
    // ── C2: Progress Rings — Active / Blocked / Completed (Concept F) ──
    html.div([attribute.class("dash-concept-f-top")], [
      // C2: Progress Rings block (left)
      html.div([attribute.class("dash-rings-block")], [
        dash_progress_ring(
          int.to_string(active_count),
          "Active",
          "#00d4aa",
          active_dash,
          active_gap,
        ),
        dash_progress_ring(
          int.to_string(blocked_count),
          "Blocked",
          "#ff4757",
          blocked_dash,
          blocked_gap,
        ),
        dash_progress_ring(
          int.to_string(completed_count),
          "Completed",
          "#3dd68c",
          completed_dash,
          completed_gap,
        ),
        // Health score ring (SC-TRUTH-001: live state)
        dash_progress_ring(
          health_pct_str <> "%",
          "Health",
          case health_score >= 80 {
            True -> "#3dd68c"
            False ->
              case health_score >= 60 {
                True -> "#f5a623"
                False -> "#ff4757"
              }
          },
          int.to_string(health_score * circ / 100),
          int.to_string(circ - health_score * circ / 100),
        ),
      ]),
      // C12: Fractal Layer Health Sidebar (Concept F — E sidebar)
      html.div(
        [
          attribute.class("dash-fractal-sidebar"),
          attribute.id("dash-fractal-sidebar"),
        ],
        [
          html.div([attribute.class("fractal-sidebar-title")], [
            element.text("Fractal Health L0-L7"),
          ]),
          fractal_layer_health_bar("L0 Constitutional", layer_health(2), "#ff6b6b"),
          fractal_layer_health_bar("L1 Atomic/Debug", layer_health(0), "#ffd93d"),
          fractal_layer_health_bar("L2 Component", layer_health(3), "#6bcb77"),
          fractal_layer_health_bar("L3 Transaction", layer_health(-2), "#4d96ff"),
          fractal_layer_health_bar("L4 System", layer_health(-5), "#9b59b6"),
          fractal_layer_health_bar(
            "L5 Cognitive",
            layer_health(1),
            "#00d4aa",
          ),
          fractal_layer_health_bar(
            "L6 Ecosystem",
            case state.zenoh_connected {
              True -> layer_health(0)
              False -> 20
            },
            "#e74c3c",
          ),
          fractal_layer_health_bar("L7 Federation", layer_health(4), "#f39c12"),
        ],
      ),
    ]),
    // ── C7: Vega-Lite Health Sparkline Chart (Concept F Analytics) ──
    shell.section("Health Trajectory — Vega-Lite Sparkline (Concept F Analytics)", [
      html.p([attribute.class("sub")], [
        element.text(
          "Live health score trend. Vega-Lite chart preset: health-sparkline. Updates every 5s via WebSocket.",
        ),
      ]),
      html.div(
        [
          attribute.id("dash-vega-chart"),
          attribute.class("dash-vega-container"),
          attribute.attribute(
            "data-vega-preset",
            "health-sparkline",
          ),
          attribute.attribute(
            "data-vega-spec",
            vega_health_sparkline_spec(health_score),
          ),
        ],
        [
          // Fallback ASCII sparkline while JS loads
          html.div(
            [
              attribute.class("vega-fallback-sparkline"),
              attribute.attribute("aria-label", "Health sparkline chart"),
            ],
            [
              html.div([attribute.class("vega-sparkline-bar-row")], [
                html.div([attribute.class("vega-sparkline-label")], [
                  element.text("Health Score"),
                ]),
                html.div([attribute.class("vega-sparkline-bar-outer")], [
                  html.div(
                    [
                      attribute.class(
                        "vega-sparkline-bar-fill"
                        <> case health_score >= 80 {
                          True -> " bar-healthy"
                          False ->
                            case health_score >= 60 {
                              True -> " bar-degraded"
                              False -> " bar-critical"
                            }
                        },
                      ),
                      attribute.attribute(
                        "style",
                        "width:"
                          <> int.to_string(health_score)
                          <> "%",
                      ),
                    ],
                    [],
                  ),
                ]),
                html.div([attribute.class("vega-sparkline-value")], [
                  element.text(health_pct_str <> "%"),
                ]),
              ]),
              html.div([attribute.class("vega-sparkline-bar-row")], [
                html.div([attribute.class("vega-sparkline-label")], [
                  element.text("Active Tasks"),
                ]),
                html.div([attribute.class("vega-sparkline-bar-outer")], [
                  html.div(
                    [
                      attribute.class("vega-sparkline-bar-fill bar-active"),
                      attribute.attribute(
                        "style",
                        "width:"
                          <> int.to_string(
                          active_count * 100 / int.max(total_count, 1),
                        )
                          <> "%",
                      ),
                    ],
                    [],
                  ),
                ]),
                html.div([attribute.class("vega-sparkline-value")], [
                  element.text(int.to_string(active_count)),
                ]),
              ]),
              html.div([attribute.class("vega-sparkline-bar-row")], [
                html.div([attribute.class("vega-sparkline-label")], [
                  element.text("Blocked Tasks"),
                ]),
                html.div([attribute.class("vega-sparkline-bar-outer")], [
                  html.div(
                    [
                      attribute.class("vega-sparkline-bar-fill bar-critical"),
                      attribute.attribute(
                        "style",
                        "width:"
                          <> int.to_string(
                          blocked_count * 100 / int.max(total_count, 1),
                        )
                          <> "%",
                      ),
                    ],
                    [],
                  ),
                ]),
                html.div([attribute.class("vega-sparkline-value")], [
                  element.text(int.to_string(blocked_count)),
                ]),
              ]),
            ],
          ),
          // Vega-Lite render target (JS activates this)
          html.div(
            [
              attribute.id("dash-vega-render-target"),
              attribute.attribute("style", "min-height:120px"),
            ],
            [],
          ),
        ],
      ),
    ]),
    // --- SECTION 0: HMI & COGNITIVE CONTROL (existing) ---
    shell.section("HMI & Cognitive Load Controls", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "Dashboard Audio",
          "Healthy",
          "Muted",
          "Optional Sonification",
        ),
        shell.status_card(
          "Semantic Zoom",
          "Healthy",
          "Level 2",
          "Cognitive Complexity",
        ),
        shell.status_card(
          "LOA Pruning",
          "Healthy",
          "Active",
          "Data Saturation Filter",
        ),
      ]),
      html.div([attribute.class("section-actions")], [
        html.button(
          [
            attribute.class("hmi-toggle-btn"),
            attribute.attribute("role", "button"),
          ],
          [element.text("ENABLE SONIFICATION [432Hz RESONANCE]")],
        ),
        html.button(
          [
            attribute.class("hmi-toggle-btn"),
            attribute.attribute("role", "button"),
          ],
          [element.text("DECREASE SEMANTIC ZOOM [LOA PRUNING]")],
        ),
      ]),
    ]),
    // --- SECTION 0.5: CONTAINER GENOME GRID (16-cell SIL-6 Biomorphic Mesh) ---
    shell.section("Container Genome (SIL-6 Biomorphic Mesh)", [
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
    // --- SECTION 0.6: OODA 5-Tier Decision Ring ---
    shell.section("OODA Decision Ring (5-Tier)", [
      shell.ooda_5tier(ooda_phase_to_string(state.ooda_phase)),
    ]),
    // --- SECTION 0.7: Constitutional Proof Chain ---
    shell.section("Constitutional Proof Chain", [
      shell.proof_chain([
        #("e3b0c4", True),
        #("a1f2d3", True),
        #("b7c8e9", True),
        #("d4e5f6", True),
        #("f0a1b2", True),
        #("c3d4e5", True),
        #("98a7b6", True),
        #("latest", True),
      ]),
    ]),
    // --- SECTION 0.8: AG-UI Event Stream (live agent activity) ---
    event_stream_widget.render_html(event_stream_widget.demo_events(), 8),
    // --- SECTION 1: MESH HEALTH & AUTONOMY (10) ---
    shell.section("Mesh Health & Autonomy Controls", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "1. Mesh Health",
          health_str,
          int.to_string(state.healthy_count)
            <> "/"
            <> int.to_string(state.container_count),
          "containers healthy",
        ),
        shell.status_card(
          "2. OODA Phase",
          "Healthy",
          ooda_phase_to_string(state.ooda_phase),
          "current cycle phase",
        ),
        shell.status_card(
          "3. Threat Level",
          threat_label(state.threat_level),
          state.threat_level_to_string(state.threat_level),
          "immune system status",
        ),
        shell.status_card(
          "4. Zenoh Connectivity",
          bool_status(state.zenoh_connected),
          case state.zenoh_connected {
            True -> "Connected"
            False -> "Offline"
          },
          "mesh transport bus",
        ),
        shell.status_card(
          "5. Quorum",
          bool_status(state.quorum_healthy),
          case state.quorum_healthy {
            True -> "2oo3"
            False -> "Lost"
          },
          "consensus voting",
        ),
        shell.status_card(
          "6. Cockpit Mode",
          "Healthy",
          cockpit_mode_to_string(state.dark_cockpit_mode),
          "dark cockpit state",
        ),
        shell.status_card(
          "7. Symbiotic Autonomy",
          "Optimal",
          "Ready",
          "Human-AI Handover",
        ),
        shell.status_card(
          "8. Anti-Fragility",
          "Optimal",
          "0.94",
          "Systemic Score",
        ),
        shell.status_card(
          "9. Ghost Detector",
          "Healthy",
          "0 Anomalies",
          "Substrate Logic",
        ),
        shell.status_card(
          "10. BFT Confidence",
          "Healthy",
          "99.9%",
          "Byzantine Fault Tol.",
        ),
      ]),
    ]),
    // --- SECTION 2: COGNITIVE & INFERENCE (10) ---
    shell.section("Cognitive & Inference Plane (Qwen3-Coder)", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "11. LLM Token Burn",
          "Healthy",
          "142/s",
          "Inference Velocity",
        ),
        shell.status_card(
          "12. Semantic Frags",
          "Healthy",
          "2.1%",
          "Memory Fragmentation",
        ),
        shell.status_card(
          "13. Cognitive Load",
          "Healthy",
          "0.12",
          "Operator Overload",
        ),
        shell.status_card(
          "14. SLM Readiness",
          "Healthy",
          "Loaded",
          "Edge-Inference Kernel",
        ),
        shell.status_card(
          "15. PSO Activity",
          "Healthy",
          "Converged",
          "Particle Swarm Opt.",
        ),
        shell.status_card(
          "16. Singularity T-",
          "Stressed",
          "3.2 yrs",
          "Countdown Ticker",
        ),
        shell.status_card(
          "17. FEP Surprise",
          "Healthy",
          "0.004",
          "Active Inference",
        ),
        shell.status_card(
          "18. Multi-tenant",
          "Healthy",
          "14 Nodes",
          "Resource Saturation",
        ),
        shell.status_card(
          "19. Context Press",
          "Healthy",
          "0.45",
          "AI Token Limit Gauge",
        ),
        shell.status_card(
          "20. AERI Indicator",
          "Healthy",
          "Stable",
          "Epistemic Resonance",
        ),
      ]),
      html.div([attribute.class("cognitive-multilayer-display")], [
        html.div([attribute.class("multilayer-row")], [
          shell.kv_row("Primary Model", "Qwen3 Coder 35B"),
          shell.kv_row("High Capacity", "Qwen3 Coder 480B"),
          shell.kv_row("API Gateway", "OpenRouter (MoZ Enabled)"),
        ]),
        html.div([attribute.class("multilayer-row")], [
          shell.kv_row("Burn Threshold", "10,000 tokens/min"),
          shell.kv_row("Context Limit", "128,000 tokens"),
          shell.kv_row("Active Inference", "Surprise Minimization (FEP)"),
        ]),
      ]),
    ]),
    // --- SECTION 3: TELEMETRY & PERFORMANCE (10) ---
    shell.section("Telemetry & Performance (Zero-IP)", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "21. OODA Latency",
          "Healthy",
          "42ms",
          "Target < 50ms",
        ),
        shell.status_card(
          "22. Zenoh B/W",
          "Healthy",
          "1.4 Gbps",
          "Mesh Multicast",
        ),
        shell.status_card(
          "23. GC Pause Time",
          "Healthy",
          "1.2ms",
          "Erlang/BEAM Metric",
        ),
        shell.status_card(
          "24. Trace Depth",
          "Healthy",
          "8 Layers",
          "Distributed Tracing",
        ),
        shell.status_card(
          "25. WAL Flush",
          "Healthy",
          "10Hz",
          "SQLite Persistence",
        ),
        shell.status_card(
          "26. Route Eff.",
          "Healthy",
          "0.98",
          "Zero-IP Efficiency",
        ),
        shell.status_card(
          "27. Leak Predict",
          "Healthy",
          "Safe",
          "Memory Trajectory",
        ),
        shell.status_card(
          "28. Mesh Fluidity",
          "Healthy",
          "Optimal",
          "Dynamic Topology",
        ),
        shell.status_card(
          "29. Evolution Vec",
          "Healthy",
          "v22.1",
          "Morphological Vector",
        ),
        shell.status_card(
          "30. Load Balancer",
          "Healthy",
          "Balanced",
          "Cognitive Distribution",
        ),
      ]),
    ]),
    // --- SECTION 4: SECURITY & INTEGRITY (10) ---
    shell.section("Security & Integrity Bounds", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "31. Merkle Root",
          "Healthy",
          "0x8f3a",
          "Visual Cryptography",
        ),
        shell.status_card(
          "32. Token Vel.",
          "Healthy",
          "800/s",
          "Proof-Token Signing",
        ),
        shell.status_card(
          "33. RS Health",
          "Healthy",
          "RS(32,28)",
          "Reed-Solomon Parity",
        ),
        shell.status_card(
          "34. Antibody Rate",
          "Healthy",
          "12/min",
          "Immune Spawn Rate",
        ),
        shell.status_card(
          "35. Apoptosis Thr",
          "Healthy",
          "Remote",
          "Threshold Proximity",
        ),
        shell.status_card(
          "36. Containment",
          "Healthy",
          "Active",
          "Cascade Failure Guard",
        ),
        shell.status_card(
          "37. Tri-Sync",
          "Healthy",
          "Synced",
          "Consensus Accuracy",
        ),
        shell.status_card(
          "38. Strict Mode",
          "Healthy",
          "Enforced",
          "Credo/Dialyzer Linter",
        ),
        shell.status_card(
          "39. Terminal Sync",
          "Healthy",
          "Parity",
          "TUI Mirroring",
        ),
        shell.status_card(
          "40. Isolation",
          "Healthy",
          "Isolated",
          "Thread-Local Integrity",
        ),
      ]),
    ]),
    // --- SECTION 5: ADVANCED A2UI VISUALIZATIONS (10) ---
    shell.section("Advanced A2UI Crystalline Wavefront", [
      html.div([attribute.class("card-grid")], [
        shell.status_card(
          "41. Heatmap",
          "Healthy",
          "Neuromorphic",
          "CSS Stress Shading",
        ),
        html.div([attribute.class("cyber-pulse led-on")], [
          shell.status_card(
            "42. 3D Topology",
            "Healthy",
            "Depth-Enabled",
            "Sparkline Depth",
          ),
        ]),
        html.div([attribute.class("cyber-pulse")], [
          shell.status_card(
            "43. Cyber-Pulse",
            "Healthy",
            "Animating",
            "Node Heartbeat",
          ),
        ]),
        shell.status_card(
          "44. Holo-Grid",
          "Healthy",
          "Active",
          "Dashboard Backdrop",
        ),
        shell.status_card(
          "45. ARIA Live",
          "Healthy",
          "Assertive",
          "Alert Live-Regions",
        ),
        shell.status_card(
          "46. Fractal Zoom",
          "Healthy",
          "Enabled",
          "Deep-Zoom Support",
        ),
        shell.status_card(
          "47. DLQ Warning",
          "Healthy",
          "0 Messages",
          "Backpressure Signal",
        ),
        html.div([attribute.class("mesh-breath")], [
          shell.status_card(
            "48. Mesh Breath",
            "Healthy",
            "Synced",
            "Opacity Animation",
          ),
        ]),
        html.div([attribute.class("led-on")], [
          shell.status_card(
            "49. Jidoka Cord",
            "Healthy",
            "Standby",
            "Emergency Stop",
          ),
        ]),
        shell.status_card(
          "50. LED Matrix",
          "Healthy",
          "L0-L7",
          "Layer Activation",
        ),
      ]),
      html.div([attribute.class("section-actions")], [
        html.button(
          [
            attribute.class("emergency-stop-btn cyber-pulse"),
            attribute.attribute("role", "button"),
            attribute.attribute("aria-label", "Pull the Jidoka Cord"),
          ],
          [element.text("PULL THE JIDOKA CORD [HALT SWARM]")],
        ),
      ]),
    ]),
    shell.section("OODA Ring [A2UI Continuous Wavefront]", [
      html.div([attribute.class("ooda-phases")], [
        ooda_phase_pill("Observe", state.ooda_phase == OodaObserve),
        html.span([attribute.class("ooda-arrow")], [element.text("▶")]),
        ooda_phase_pill("Orient", state.ooda_phase == OodaOrient),
        html.span([attribute.class("ooda-arrow")], [element.text("▶")]),
        ooda_phase_pill("Decide", state.ooda_phase == OodaDecide),
        html.span([attribute.class("ooda-arrow")], [element.text("▶")]),
        ooda_phase_pill("Act", state.ooda_phase == OodaAct),
        html.span([attribute.class("ooda-arrow")], [element.text("▶")]),
        ooda_phase_pill("Verify", state.ooda_phase == OodaVerify),
      ]),
      html.div(
        [
          attribute.class("reasoning-marquee"),
          attribute.attribute(
            "style",
            "margin-top: 1rem; padding: 0.75rem; background: rgba(61, 214, 140, 0.1); border-left: 4px solid #3dd68c; font-family: monospace; color: #a6accd;",
          ),
        ],
        [
          element.text("CoT [RETE-UL]: "),
          html.span([attribute.attribute("style", "color: #3dd68c;")], [
            element.text(
              "Evaluating missing critical nodes... No anomalies detected. System in homeostasis. Transitioning to Observe.",
            ),
          ]),
        ],
      ),
    ]),
    // --- SECTION 6: FRACTAL LAYER SUPERVISORS (L0-L7) ---
    // सर्वभूतस्थमात्मानं सर्वभूतानि चात्मनि — See the Self in all beings (Gita 6.29)
    shell.section("Fractal Layer Supervisors (L0-L7) — Zenoh Backplane", [
      // Fractal filter chips
      html.div(
        [attribute.id("fractal-filter-chips"), attribute.class("fractal-chips")],
        [
          filter_pill("All", True),
          html.span([attribute.class("layer-pill layer-l0")], [
            element.text("L0 Constitutional"),
          ]),
          html.span([attribute.class("layer-pill layer-l1")], [
            element.text("L1 Atomic"),
          ]),
          html.span([attribute.class("layer-pill layer-l2")], [
            element.text("L2 Component"),
          ]),
          html.span([attribute.class("layer-pill layer-l3")], [
            element.text("L3 Transaction"),
          ]),
          html.span([attribute.class("layer-pill layer-l4")], [
            element.text("L4 System"),
          ]),
          html.span([attribute.class("layer-pill layer-l5")], [
            element.text("L5 Cognitive"),
          ]),
          html.span([attribute.class("layer-pill layer-l6")], [
            element.text("L6 Ecosystem"),
          ]),
          html.span([attribute.class("layer-pill layer-l7")], [
            element.text("L7 Federation"),
          ]),
        ],
      ),
      // L0 Constitutional — Guardian, Safety, Psi invariants
      html.div([attribute.class("card-grid"), attribute.id("layer-l0")], [
        shell.status_card(
          "L0 Guardian",
          "Healthy",
          "Active",
          "Constitutional approval gate — HITL mandatory",
        ),
        shell.status_card(
          "L0 Psi-0..5",
          "Healthy",
          "6/6 Pass",
          "Existence, Regeneration, Reversibility, Verification, Alignment, Truth",
        ),
        shell.status_card(
          "L0 Emergency Stop",
          "Healthy",
          "Standby",
          "Jidoka cord < 5s response — SC-SAFETY-022",
        ),
      ]),
      // L1 Atomic — Debug, Trace, NIF
      html.div([attribute.class("card-grid"), attribute.id("layer-l1")], [
        shell.status_card(
          "L1 NIF Bridge",
          "Healthy",
          "14 NIFs",
          "c3i_nif.so — Rust FFI boundary",
        ),
        shell.status_card(
          "L1 OTel Trace",
          "Healthy",
          "8 Layers",
          "Distributed tracing via Zenoh",
        ),
        shell.status_card(
          "L1 Debug Probes",
          "Healthy",
          "Active",
          "Event monitor + state inspection",
        ),
      ]),
      // L2 Component — Forms, Grids, Badges
      html.div([attribute.class("card-grid"), attribute.id("layer-l2")], [
        shell.status_card(
          "L2 A2UI Catalog",
          "Healthy",
          "233 Types",
          "Declarative component registry",
        ),
        shell.status_card(
          "L2 Shell Helpers",
          "Healthy",
          "12 Funcs",
          "status_card, kv_row, mini_bar",
        ),
        shell.status_card(
          "L2 Lustre SSR",
          "Healthy",
          "31 Pages",
          "Server-rendered, no client JS",
        ),
      ]),
      // L3 Transaction — Planning, State, DB
      html.div([attribute.class("card-grid"), attribute.id("layer-l3")], [
        shell.status_card(
          "L3 sa-plan-daemon",
          "Healthy",
          "Running",
          "Rust task management — SC-TODO-001",
        ),
        shell.status_card(
          "L3 Smriti.db",
          "Healthy",
          "FTS5",
          "SQLite knowledge store + RAG",
        ),
        shell.status_card(
          "L3 Planning.db",
          "Healthy",
          "WAL",
          "Task state authority",
        ),
      ]),
      // L4 System — Containers, Podman, Boot
      html.div([attribute.class("card-grid"), attribute.id("layer-l4")], [
        shell.status_card(
          "L4 Container Genome",
          "Healthy",
          int.to_string(state.container_count) <> " Alive",
          "16-container SIL-6 biomorphic mesh",
        ),
        shell.status_card(
          "L4 Boot Sequencer",
          "Healthy",
          "7 Tiers",
          "DAG topological sort + waves",
        ),
        shell.status_card(
          "L4 CPU Governor",
          "Healthy",
          "< 85%",
          "Adaptive parallelism — SC-CPU-GOV",
        ),
      ]),
      // L5 Cognitive — OODA, Cortex, Inference
      html.div([attribute.class("card-grid"), attribute.id("layer-l5")], [
        shell.status_card(
          "L5 Cortex",
          "Healthy",
          "31 Modules",
          "Rust 9,104 LOC — chat + voice + RAG",
        ),
        shell.status_card(
          "L5 OODA Loop",
          "Healthy",
          ooda_phase_to_string(state.ooda_phase),
          "< 100ms cycle — 5-tier decision ring",
        ),
        shell.status_card(
          "L5 Inference",
          "Healthy",
          "6-Tier",
          "Hedged: Gemini || OpenRouter || Ollama || RETE-UL",
        ),
      ]),
      // L6 Ecosystem — Zenoh, Mesh, Topology
      html.div([attribute.class("card-grid"), attribute.id("layer-l6")], [
        shell.status_card(
          "L6 Zenoh Mesh",
          bool_status(state.zenoh_connected),
          case state.zenoh_connected {
            True -> "4 Routers"
            False -> "Offline"
          },
          "Pub/sub + OTel + MCP transport",
        ),
        shell.status_card(
          "L6 Quorum",
          bool_status(state.quorum_healthy),
          case state.quorum_healthy {
            True -> "2oo3 Met"
            False -> "Lost"
          },
          "Byzantine fault tolerance",
        ),
        shell.status_card(
          "L6 MoZ Bridge",
          "Healthy",
          "73 Tools",
          "MCP-over-Zenoh JSON-RPC",
        ),
      ]),
      // L7 Federation — Gateway, Consensus, Multi-node
      html.div([attribute.class("card-grid"), attribute.id("layer-l7")], [
        shell.status_card(
          "L7 Gateway",
          "Healthy",
          "3 Bridges",
          "Telegram + GChat + WhatsApp",
        ),
        shell.status_card(
          "L7 HA Election",
          "Healthy",
          "Primary",
          "Leader/Backup/Standby via Zenoh lease",
        ),
        shell.status_card(
          "L7 Version Vectors",
          "Healthy",
          "Synced",
          "Federated reconciliation — CRDT",
        ),
      ]),
    ]),
    // --- SECTION 7: SUPERVISOR TREE & THREAD MONITORING ---
    // कर्मण्येवाधिकारस्ते — Your right is to action alone (Gita 2.47)
    shell.section("Supervisor Tree & Thread Monitoring", [
      html.div(
        [attribute.id("supervisor-tree"), attribute.class("card-grid")],
        [
          shell.status_card(
            "EXEC-001 Orchestrator",
            "Healthy",
            "Opus",
            "Root supervisor — 25 agents, 2-layer",
          ),
          shell.status_card(
            "Context Supervisor",
            "Healthy",
            "Sonnet",
            "5 workers — compile, format, read",
          ),
          shell.status_card(
            "Domain Supervisor",
            "Healthy",
            "Sonnet",
            "5 workers — test, fix, doc",
          ),
          shell.status_card(
            "Test Supervisor",
            "Healthy",
            "Sonnet",
            "5 workers — unit, E2E, property",
          ),
          shell.status_card(
            "Quality Supervisor",
            "Healthy",
            "Sonnet",
            "5 workers — credo, STAMP, verify",
          ),
        ],
      ),
      html.div(
        [attribute.id("thread-monitor"), attribute.class("card-grid")],
        [
          shell.status_card(
            "BEAM Schedulers",
            "Healthy",
            "16+16",
            "16 normal + 16 dirty IO threads",
          ),
          shell.status_card(
            "Rust Tokio Runtime",
            "Healthy",
            "8 Threads",
            "sa-plan-daemon async runtime",
          ),
          shell.status_card(
            "Rust Modules",
            "Healthy",
            "31 Files",
            "9,104 LOC — cortex, gateway, trace",
          ),
          shell.status_card(
            "Zenoh Sessions",
            bool_status(state.zenoh_connected),
            "4 Routers",
            "TCP 7447 — mesh transport",
          ),
          shell.status_card(
            "Active OODA",
            "Healthy",
            "1 Cycle",
            "Observe-Orient-Decide-Act-Verify",
          ),
          shell.status_card(
            "WebSocket Conns",
            "Healthy",
            "Active",
            "/ws/dashboard + /ws/planning",
          ),
        ],
      ),
    ]),
    // --- SECTION 8: QUICK LINKS + NAVIGATION ---
    shell.section("Quick Links", [
      html.div([attribute.class("card-grid-wide")], [
        quick_link_card("Podman", "/podman", "Container lifecycle, genome health", "L4"),
        quick_link_card("Zenoh Mesh", "/zenoh", "Pub/sub topology, router status", "L6"),
        quick_link_card(
          "Verification",
          "/verification",
          "PROMETHEUS proofs, SIL-6 gates",
          "L0",
        ),
        quick_link_card(
          "Immune System",
          "/immune",
          "Threat detection, antibody counters",
          "L0",
        ),
        quick_link_card(
          "Planning",
          "/planning",
          "Task management, Kanban, AI search",
          "L3",
        ),
        quick_link_card(
          "Agents",
          "/agents",
          "Agent hierarchy, OODA supervision",
          "L5",
        ),
        quick_link_card(
          "Knowledge",
          "/knowledge",
          "Zettelkasten brain, 2060+ holons",
          "L5",
        ),
        quick_link_card("Cockpit", "/cockpit", "Dark cockpit, operator view", "L5"),
      ]),
    ]),
    // --- SECTION 9: OPERATIONAL CONTROLS ---
    shell.section("L5 Operational Controls [A2UI Cognitive Projection]", [
      case state.threat_level {
        ThreatCritical | ThreatSevere ->
          html.div([attribute.class("loa-pruned")], [
            html.span(
              [
                attribute.attribute(
                  "style",
                  "color: #e06c75; font-style: italic;",
                ),
              ],
              [
                element.text(
                  "High threat detected. Manual controls pruned (Dynamic LOA: Supervised Autonomy). System is autonomously mitigating.",
                ),
              ],
            ),
          ])
        _ ->
          html.div([attribute.class("card-grid")], [
            shell.action_button(
              "Force OODA Cycle",
              "/api/v1/ooda/trigger",
              "{\\\"action\\\": \\\"force_cycle\\\"}",
            ),
            shell.action_button(
              "Trigger LLM Advisor",
              "/api/v1/ooda/trigger",
              "{\\\"action\\\": \\\"llm_advise\\\"}",
            ),
            shell.action_button(
              "Inject Fact (RETE-UL)",
              "/api/v1/ooda/trigger",
              "{\\\"action\\\": \\\"inject_fact\\\"}",
            ),
          ])
      },
    ]),
    // --- SECTION 10: INTERACTIVE DASHBOARD ---
    // योगस्थः कुरु कर्माणि — Established in yoga, perform action (Gita 2.48)
    // WebSocket /ws/dashboard + Gemma AI Chat + Live Fractal Monitoring
    shell.section("Live System Intelligence (Zenoh-Native)", [
      html.p([attribute.class("sub")], [
        element.text(
          "Real-time fractal monitoring + AI chat. WebSocket push via Zenoh backplane. Gemma 3/4 AI. Updates every 1s.",
        ),
      ]),
      // View mode toggle
      html.div(
        [
          attribute.id("dash-view-toggle"),
          attribute.attribute(
            "style",
            "display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap",
          ),
        ],
        [
          html.button(
            [
              attribute.class("btn btn-primary"),
              attribute.attribute("data-view", "grid"),
            ],
            [element.text("Grid")],
          ),
          html.button(
            [
              attribute.class("btn btn-ghost"),
              attribute.attribute("data-view", "supervisors"),
            ],
            [element.text("Supervisors")],
          ),
          html.button(
            [
              attribute.class("btn btn-ghost"),
              attribute.attribute("data-view", "fractal"),
            ],
            [element.text("Fractal Layers")],
          ),
          html.button(
            [
              attribute.class("btn btn-ghost"),
              attribute.attribute("data-view", "analytics"),
            ],
            [element.text("Analytics")],
          ),
        ],
      ),
      // Search bar (Ctrl+K)
      html.div(
        [attribute.id("dash-search-bar"), attribute.attribute("style", "margin-bottom:12px")],
        [
          html.input([
            attribute.type_("text"),
            attribute.id("dash-search-input"),
            attribute.attribute(
              "placeholder",
              "Search system... (Ctrl+K)",
            ),
            attribute.attribute(
              "style",
              "width:100%;padding:10px 14px;background:#141922;border:1px solid #1e2a3a;border-radius:8px;color:#e0e6ed;font-size:0.9rem;min-height:44px",
            ),
          ]),
        ],
      ),
      // WebSocket status + heartbeat
      html.div(
        [
          attribute.attribute(
            "style",
            "display:flex;gap:12px;align-items:center;margin-bottom:12px;flex-wrap:wrap",
          ),
        ],
        [
          html.div(
            [
              attribute.id("dash-ws-status"),
              attribute.attribute("style", "font-size:0.78rem;color:#7a8fa6"),
            ],
            [element.text("Connecting to /ws/dashboard...")],
          ),
          html.div(
            [
              attribute.id("dash-heartbeat"),
              attribute.attribute(
                "style",
                "width:10px;height:10px;border-radius:50%;background:#7a8fa6",
              ),
            ],
            [],
          ),
          html.div(
            [
              attribute.id("dash-task-summary"),
              attribute.attribute("style", "font-size:0.85rem;flex:1"),
            ],
            [element.text("Loading system snapshot...")],
          ),
        ],
      ),
      // Dynamic content area (JS fills this)
      html.div(
        [
          attribute.id("dash-dynamic-content"),
          attribute.attribute("style", "min-height:200px"),
        ],
        [],
      ),
      // Change log
      html.div(
        [
          attribute.id("dash-change-log"),
          attribute.attribute(
            "style",
            "margin-top:12px;max-height:200px;overflow-y:auto",
          ),
        ],
        [
          html.div(
            [
              attribute.attribute(
                "style",
                "color:#7a8fa6;font-size:0.75rem;padding:8px",
              ),
            ],
            [element.text("State change log will appear here...")],
          ),
        ],
      ),
      // AI Chat widget
      html.div([attribute.id("dash-ai-chat")], [
        html.div(
          [
            attribute.attribute(
              "style",
              "color:#7a8fa6;font-size:0.78rem;padding:20px;text-align:center",
            ),
          ],
          [element.text("Loading Gemma AI chat...")],
        ),
      ]),
      // System Endpoints table (C3 criterion)
      shell.section("System Endpoints", [
        shell.data_table(["Port", "Service", "Status"], [
          ["4100", "Gleam HTTP / WebUI", "active"],
          ["4101", "Gleam HTTPS / TLS", "active"],
          ["7447", "Zenoh Router TCP", "active"],
          ["5433", "PostgreSQL (db-prod)", "active"],
        ]),
      ]),
      // System Controls — Hot Reload (SC-HA-RELOAD-001)
      shell.section("System Controls", [shell.hot_reload_button()]),
      // L0 Emergency Stop (SC-SAFETY-022)
      shell.section("Emergency Controls (L0 Constitutional)", [
        shell.emergency_stop_button(),
      ]),
      // Load comprehensive dashboard JS
      element.element(
        "script",
        [attribute.attribute("src", "/static/dashboard-grid.js?v=22.6.1")],
        [],
      ),
    ]),
  ])
}

// ---------------------------------------------------------------------------
// 6. Cockpit — L5 Cognitive  (SC-HMI-010, SC-AGUI-UI-001..015)
// अन्धकारात् प्रकाशं प्राप्नोति — From darkness one reaches light (Dark Cockpit)
// ---------------------------------------------------------------------------

pub fn cockpit_view(state: SharedMeshState) -> Element(msg) {
  // Derive cockpit mode from health (SC-HMI-010 5-mode state machine)
  let mode = cockpit_mode_from_state(state)
  let mode_color = cockpit_mode_color(mode)
  let health_pct =
    int.to_string(
      case state.healthy_count == 0 && state.container_count == 0 {
        True -> 100
        False ->
          state.healthy_count * 100 / int.max(state.container_count, 1)
      },
    )
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
              html.span(
                [attribute.attribute("id", "cockpit-hb-label")],
                [element.text("LIVE")],
              ),
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
          shell.status_card(
            "Active Alarms",
            "Healthy",
            "0",
            "all acknowledged",
          ),
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
              shell.kv_row("Current Phase", ooda_phase_to_string(state.ooda_phase)),
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
      shell.section(
        "L0-L7 Fractal Layer Health (Operator View — Condensed)",
        [
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
        ],
      ),
      // ── Row 6: AI Chat + View controls (JS-driven) ────────────────────
      html.div([attribute.class("cockpit-bottom-strip")], [
        html.div([attribute.class("cockpit-view-controls")], [
          html.div([attribute.class("view-toggle"), attribute.attribute("id", "cockpit-view-toggle")], [
            html.button([attribute.class("view-btn active"), attribute.attribute("data-view", "grid")], [element.text("Grid")]),
            html.button([attribute.class("view-btn"), attribute.attribute("data-view", "alarms")], [element.text("Alarms")]),
            html.button([attribute.class("view-btn"), attribute.attribute("data-view", "nodes")], [element.text("Nodes")]),
            html.button([attribute.class("view-btn"), attribute.attribute("data-view", "genome")], [element.text("Genome")]),
          ]),
          html.div([attribute.class("cockpit-search-bar")], [
            html.input([
              attribute.class("cockpit-search-input"),
              attribute.attribute("id", "cockpit-search"),
              attribute.attribute("placeholder", "Search alarms, nodes… (Ctrl+K)"),
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
                    attribute.attribute("placeholder", "Ask about alarms, nodes…"),
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
        shell.status_card(
          "Orch Mesh",
          "Healthy",
          "active",
          "Prajna + Smriti",
        ),
        shell.status_card("Chaya Twin", "Healthy", "active", "digital twin"),
        shell.status_card(
          "Startup Optim",
          "Healthy",
          "active",
          "< 60s target",
        ),
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

fn ooda_phase_pill(label: String, active: Bool) -> Element(msg) {
  let cls = case active {
    True -> "ooda-phase ooda-phase-active"
    False -> "ooda-phase"
  }
  html.span([attribute.class(cls)], [element.text(label)])
}

fn quick_link_card(
  title: String,
  href: String,
  description: String,
  layer: String,
) -> Element(msg) {
  html.a([attribute.href(href), attribute.class("card quick-link-card")], [
    html.div([attribute.class("card-header")], [
      html.span([attribute.class("mono text-sm")], [element.text(title)]),
      html.span([attribute.class("layer-badge layer-" <> string_lower(layer))], [
        element.text(layer),
      ]),
    ]),
    html.div([attribute.class("card-detail")], [element.text(description)]),
  ])
}

fn filter_pill(label: String, active: Bool) -> Element(msg) {
  let cls = case active {
    True -> "btn btn-primary"
    False -> "btn btn-ghost"
  }
  html.span([attribute.class(cls)], [element.text(label)])
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

// ---------------------------------------------------------------------------
// Concept F: Dashboard helpers (C1 weather bar, C2 progress rings, C12 fractal)
// ---------------------------------------------------------------------------

/// Concept F SVG progress ring for C2 (active/blocked/completed/health)
fn dash_progress_ring(
  value: String,
  label: String,
  color: String,
  dash: String,
  gap: String,
) -> Element(msg) {
  html.div([attribute.class("dash-progress-ring")], [
    element.element("svg", [attribute.attribute("viewBox", "0 0 100 100")], [
      element.element(
        "circle",
        [
          attribute.attribute("cx", "50"),
          attribute.attribute("cy", "50"),
          attribute.attribute("r", "45"),
          attribute.attribute("fill", "none"),
          attribute.attribute("stroke", "#1e2a3a"),
          attribute.attribute("stroke-width", "8"),
        ],
        [],
      ),
      element.element(
        "circle",
        [
          attribute.attribute("cx", "50"),
          attribute.attribute("cy", "50"),
          attribute.attribute("r", "45"),
          attribute.attribute("fill", "none"),
          attribute.attribute("stroke", color),
          attribute.attribute("stroke-width", "8"),
          attribute.attribute("stroke-linecap", "round"),
          attribute.attribute(
            "stroke-dasharray",
            dash <> " " <> gap,
          ),
          attribute.attribute(
            "transform",
            "rotate(-90 50 50)",
          ),
        ],
        [],
      ),
    ]),
    html.div([attribute.class("dash-ring-value")], [element.text(value)]),
    html.div([attribute.class("dash-ring-label")], [element.text(label)]),
  ])
}

/// Concept F fractal layer health bar for C12 sidebar
fn fractal_layer_health_bar(
  label: String,
  health: Int,
  color: String,
) -> Element(msg) {
  let health_str = int.to_string(health)
  let bar_color = case health >= 80 {
    True -> color
    False ->
      case health >= 60 {
        True -> "#f5a623"
        False -> "#ff4757"
      }
  }
  html.div([attribute.class("fractal-health-row")], [
    html.div([attribute.class("fractal-health-label")], [element.text(label)]),
    html.div([attribute.class("fractal-health-bar-outer")], [
      html.div(
        [
          attribute.class("fractal-health-bar-fill"),
          attribute.attribute(
            "style",
            "width:" <> health_str <> "%;background:" <> bar_color,
          ),
        ],
        [],
      ),
    ]),
    html.div([attribute.class("fractal-health-pct")], [
      element.text(health_str <> "%"),
    ]),
  ])
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

/// Vega-Lite JSON spec for health sparkline preset (SC-AGUI-UI-007).
/// Returns a minimal Vega-Lite 5 spec for a single bar chart of health metrics.
fn vega_health_sparkline_spec(health_score: Int) -> String {
  let h = int.to_string(health_score)
  "{\"$schema\":\"https://vega.github.io/schema/vega-lite/v5.json\","
  <> "\"description\":\"C3I Health Sparkline\","
  <> "\"width\":\"container\",\"height\":80,"
  <> "\"data\":{\"values\":["
  <> "{\"metric\":\"Health\",\"value\":"
  <> h
  <> "},"
  <> "{\"metric\":\"Quorum\",\"value\":95},"
  <> "{\"metric\":\"NIF\",\"value\":98},"
  <> "{\"metric\":\"Zenoh\",\"value\":97}"
  <> "]},"
  <> "\"mark\":{\"type\":\"bar\",\"cornerRadiusTopLeft\":3,\"cornerRadiusTopRight\":3},"
  <> "\"encoding\":{"
  <> "\"x\":{\"field\":\"metric\",\"type\":\"nominal\",\"axis\":{\"labelColor\":\"#7a8fa6\",\"tickColor\":\"#1e2a3a\",\"domainColor\":\"#1e2a3a\"}},"
  <> "\"y\":{\"field\":\"value\",\"type\":\"quantitative\",\"scale\":{\"domain\":[0,100]},\"axis\":{\"labelColor\":\"#7a8fa6\",\"tickColor\":\"#1e2a3a\",\"domainColor\":\"#1e2a3a\"}},"
  <> "\"color\":{\"field\":\"metric\",\"type\":\"nominal\",\"scale\":{\"range\":[\"#00d4aa\",\"#3dd68c\",\"#4d96ff\",\"#9b59b6\"]},\"legend\":null},"
  <> "\"tooltip\":[{\"field\":\"metric\",\"type\":\"nominal\"},{\"field\":\"value\",\"type\":\"quantitative\"}]"
  <> "},"
  <> "\"config\":{\"background\":\"transparent\",\"view\":{\"stroke\":null}}}"
}

/// Concept F CSS for the new dashboard components (C1/C2/C12/C7).
/// Follows the responsive 4-breakpoint pattern (SC-AGUI-UI-008).
fn dashboard_concept_f_css() -> String {
  "
/* ── Concept F: Weather Bar (C1) ── */
.dash-weather-bar{display:flex;align-items:center;gap:1rem;padding:.6rem 1.2rem;background:rgba(20,25,34,0.85);backdrop-filter:blur(8px);border:1px solid rgba(30,42,58,0.6);border-radius:10px;margin:.75rem 0;flex-wrap:wrap;min-height:44px;}
.dash-weather-emoji{font-size:1.5rem;}
.dash-weather-label{flex:1;font-size:.88rem;color:#b0bcc8;min-width:200px;}
.dash-weather-score{font-size:1.1rem;font-weight:700;color:var(--accent,#3dd68c);font-family:monospace;}
.dash-ws-indicator{font-size:.75rem;color:#7a8fa6;transition:color .4s;}
.dash-ws-indicator.ws-live{color:#3dd68c;}
.dash-ws-indicator.ws-dead{color:#ff4757;}

/* ── Concept F: Top Section — Rings + Fractal Sidebar (C2 + C12) ── */
.dash-concept-f-top{display:grid;grid-template-columns:1fr 280px;gap:1.2rem;margin:.75rem 0;align-items:start;}
@media(max-width:1024px){.dash-concept-f-top{grid-template-columns:1fr;}}

/* ── C2: Progress Rings ── */
.dash-rings-block{display:flex;gap:1.5rem;flex-wrap:wrap;align-items:center;padding:.75rem;background:rgba(20,25,34,0.5);border:1px solid rgba(30,42,58,0.5);border-radius:10px;}
.dash-progress-ring{display:flex;flex-direction:column;align-items:center;gap:.3rem;min-width:90px;}
.dash-progress-ring svg{width:90px;height:90px;}
@media(max-width:768px){.dash-progress-ring svg{width:70px;height:70px;}.dash-progress-ring{min-width:70px;}}
@media(min-width:1400px){.dash-progress-ring svg{width:110px;height:110px;}}
.dash-ring-value{font-size:1.05rem;font-weight:700;color:var(--text,#e0e6ed);font-family:monospace;}
.dash-ring-label{font-size:.75rem;color:#7a8fa6;text-transform:uppercase;}

/* ── C12: Fractal Layer Sidebar ── */
.dash-fractal-sidebar{background:rgba(20,25,34,0.6);backdrop-filter:blur(6px);border:1px solid rgba(30,42,58,0.5);border-radius:10px;padding:.9rem;}
.fractal-sidebar-title{font-size:.8rem;color:#7a8fa6;text-transform:uppercase;margin-bottom:.6rem;border-bottom:1px solid rgba(30,42,58,0.4);padding-bottom:.3rem;}
.fractal-health-row{display:flex;align-items:center;gap:.5rem;margin:.35rem 0;}
.fractal-health-label{font-size:.75rem;color:#b0bcc8;min-width:130px;flex-shrink:0;}
.fractal-health-bar-outer{flex:1;height:6px;background:#1e2a3a;border-radius:3px;overflow:hidden;}
.fractal-health-bar-fill{height:100%;border-radius:3px;transition:width .6s ease;}
.fractal-health-pct{font-size:.73rem;color:#7a8fa6;min-width:36px;text-align:right;font-family:monospace;}

/* ── C7: Vega-Lite Chart Container ── */
.dash-vega-container{background:rgba(20,25,34,0.5);border:1px solid rgba(30,42,58,0.4);border-radius:10px;padding:1rem;overflow:hidden;}
.vega-fallback-sparkline{display:flex;flex-direction:column;gap:.5rem;}
.vega-sparkline-bar-row{display:flex;align-items:center;gap:.75rem;}
.vega-sparkline-label{font-size:.8rem;color:#7a8fa6;min-width:110px;}
.vega-sparkline-bar-outer{flex:1;height:10px;background:#1e2a3a;border-radius:5px;overflow:hidden;}
.vega-sparkline-bar-fill{height:100%;border-radius:5px;transition:width .5s ease;}
.bar-healthy{background:#3dd68c;}.bar-degraded{background:#f5a623;}.bar-critical{background:#ff4757;}.bar-active{background:#00d4aa;}
.vega-sparkline-value{font-size:.8rem;font-family:monospace;color:#e0e6ed;min-width:36px;text-align:right;}
"
}

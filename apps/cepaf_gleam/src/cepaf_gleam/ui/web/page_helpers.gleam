//// =============================================================================
//// [C3I-SIL6-MSTS] PAGE HELPERS — Pass-27 Phase 3b shared module
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/page_helpers</module>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-FILESIZE-001, SC-MUDA-001, SC-GLM-UI-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Shared rendering helpers extracted from `domain_views.gleam` to break
//// the import cycle between `domain_views` and per-page modules. Both
//// `domain_views.gleam` and per-page modules import from THIS module
//// (acyclic).
////
//// Anti-pattern guarded: [zk-3346fc607a1ef9e6] Stub-That-Lies — every
//// function body is a byte-equivalent move from the original.

import cepaf_gleam/ui/state.{
  type SharedMeshState, ThreatElevated, ThreatLow, ThreatNominal, ThreatNone,
  cockpit_mode_to_string, ooda_phase_to_string,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import cepaf_gleam/ui/lustre/shell

// SC-MUDA-001 / audit-E3 — process-start nanosecond clock (Erlang FFI).
// Used as static asset cache-bust suffix so each daemon restart serves a
// fresh static file, while every request within the same process sees the
// same value (idempotent caching). [zk-907c636b4bbf0d73] silent metric
// drift parallel: the cache-bust string is now derived from runtime, not
// hard-coded.
@external(erlang, "erlang", "system_time")
fn erlang_system_time_seconds(unit: Atom) -> Int

@external(erlang, "erlang", "binary_to_atom")
fn binary_to_atom(s: String) -> Atom

type Atom

pub fn asset_cachebust_id() -> Int {
  erlang_system_time_seconds(binary_to_atom("second"))
}

pub fn page_header(title: String, subtitle: String) -> Element(msg) {
  html.div([attribute.class("page-header")], [
    html.div([], [
      html.h1([attribute.class("page-title")], [element.text(title)]),
      html.div([attribute.class("page-subtitle")], [element.text(subtitle)]),
    ]),
  ])
}

pub fn state_kv_block(state: SharedMeshState) -> Element(msg) {
  html.div([attribute.class("card")], [
    shell.kv_row("Containers", int.to_string(state.container_count)),
    shell.kv_row("Healthy", int.to_string(state.healthy_count)),
    shell.kv_row("Threat Level", state.threat_level_to_string(state.threat_level)),
    shell.kv_row("OODA Phase", ooda_phase_to_string(state.ooda_phase)),
    shell.kv_row("Dark Cockpit", cockpit_mode_to_string(state.dark_cockpit_mode)),
    shell.kv_row("Zenoh", case state.zenoh_connected {
      True -> "connected"
      False -> "offline"
    }),
    shell.kv_row("Quorum", case state.quorum_healthy {
      True -> "healthy"
      False -> "lost"
    }),
  ])
}

/// SVG progress ring component — reusable for all ring metrics.
pub fn progress_ring(
  value: String,
  label: String,
  color: String,
  dash: String,
  gap: String,
) -> Element(msg) {
  html.div([attribute.class("ring-item")], [
    element.element(
      "svg",
      [
        attribute.attribute("viewBox", "0 0 120 120"),
        attribute.attribute("width", "80"),
        attribute.attribute("height", "80"),
      ],
      [
        element.element(
          "circle",
          [
            attribute.attribute("cx", "60"),
            attribute.attribute("cy", "60"),
            attribute.attribute("r", "50"),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", "var(--border)"),
            attribute.attribute("stroke-width", "7"),
          ],
          [],
        ),
        element.element(
          "circle",
          [
            attribute.attribute("cx", "60"),
            attribute.attribute("cy", "60"),
            attribute.attribute("r", "50"),
            attribute.attribute("fill", "none"),
            attribute.attribute("stroke", color),
            attribute.attribute("stroke-width", "7"),
            attribute.attribute("stroke-dasharray", dash <> " " <> gap),
            attribute.attribute("stroke-linecap", "round"),
            attribute.attribute("transform", "rotate(-90 60 60)"),
          ],
          [],
        ),
        element.element(
          "text",
          [
            attribute.attribute("x", "60"),
            attribute.attribute("y", "55"),
            attribute.attribute("text-anchor", "middle"),
            attribute.attribute("fill", "var(--text)"),
            attribute.attribute("font-size", "18"),
            attribute.attribute("font-weight", "700"),
          ],
          [element.text(value)],
        ),
        element.element(
          "text",
          [
            attribute.attribute("x", "60"),
            attribute.attribute("y", "75"),
            attribute.attribute("text-anchor", "middle"),
            attribute.attribute("fill", "var(--text)"),
            attribute.attribute("font-size", "10"),
          ],
          [element.text(label)],
        ),
      ],
    ),
  ])
}

/// Extract a numeric count from NIF JSON status output.
pub fn count_in_json(json: String, key: String) -> Int {
  let search = key <> ": "
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
      let search2 = "\"" <> key <> "\":"
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

/// Parse leading integer from a string like "123,\n..." or "42 tasks".
pub fn parse_leading_int(s: String) -> Int {
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
    |> string.join("")
  case int.parse(digits) {
    Ok(n) -> n
    Error(_) -> 0
  }
}

/// Enhanced CSS for creative planning page UX — responsive mobile-first design.
pub fn planning_enhanced_css() -> String {
  "
/* === BASE (Mobile-First, <768px) === */
.weather-bar {
  display:flex; align-items:center; gap:10px; flex-wrap:wrap;
  background:linear-gradient(135deg, rgba(0,212,170,0.06), rgba(61,214,140,0.02));
  backdrop-filter:blur(12px);
  border:1px solid rgba(0,212,170,0.15); border-radius:12px;
  padding:12px 14px; margin:0 0 1rem; font-size:0.85rem;
  transition:all 0.3s ease;
}
.weather-bar:hover { border-color:rgba(0,212,170,0.3); }
.weather-emoji { font-size:1.5rem; }
.weather-label { flex:1; color:var(--text); line-height:1.4; min-width:200px; font-size:0.82rem; }
.weather-score {
  font-size:1.3rem; font-weight:800; color:var(--accent);
  background:linear-gradient(135deg,rgba(0,212,170,0.12),rgba(0,212,170,0.05));
  padding:4px 12px; border-radius:10px;
  border:1px solid rgba(0,212,170,0.15);
}
.progress-ring-row {
  display:grid; grid-template-columns:repeat(2,1fr); gap:0.75rem;
  margin:0 0 1rem;
}
.ring-item {
  display:flex; flex-direction:column; align-items:center;
  background:rgba(10,14,23,0.5); backdrop-filter:blur(8px);
  border:1px solid rgba(30,42,58,0.5); border-radius:10px; padding:0.75rem;
  transition:all 0.3s ease; min-width:0;
}
.ring-item:hover {
  border-color:var(--accent); transform:translateY(-2px);
  box-shadow:0 6px 20px rgba(0,0,0,0.12);
}
.ring-item svg { width:70px; height:70px; }
.ring-value { font-size:1rem; }
.ring-label { font-size:0.7rem; }
@keyframes pulse-glow {
  0%, 100% { box-shadow: 0 0 0 0 rgba(0,212,170,0); }
  50% { box-shadow: 0 0 14px 3px rgba(0,212,170,0.12); }
}
.card { transition:all 0.25s ease; }
.card:hover { border-color:var(--accent); transform:translateY(-1px); box-shadow:0 4px 16px rgba(0,0,0,0.1); }
table { border-collapse:collapse; width:100%; font-size:0.82rem; }
table th { position:sticky; top:0; background:rgba(10,14,23,0.95); backdrop-filter:blur(8px); z-index:1; font-size:0.72rem; padding:6px 8px; }
table td { padding:5px 8px; }
table tr { transition:background 0.15s; }
table tr:hover { background:rgba(0,212,170,0.04); }
.section h2, .section h3 { letter-spacing:0.3px; }
.sub { color:#7a8fa6; font-size:0.8rem; margin-bottom:10px; }
/* Touch-friendly targets (44px min) */
.view-btn, .fractal-chip, .detail-action-btn, button { min-height:44px; min-width:44px; }
/* Responsive card grid — 1 col mobile */
.card-grid { grid-template-columns:1fr !important; }
.card-grid-wide { grid-template-columns:1fr !important; }
/* Responsive tables — horizontal scroll on mobile */
.section { overflow-x:auto; -webkit-overflow-scrolling:touch; }
/* View toggle — horizontal scroll on narrow screens */
.view-toggle { overflow-x:auto; -webkit-overflow-scrolling:touch; white-space:nowrap; }
/* AI search — full width, large touch target */
#ai-search-input { font-size:1rem !important; padding:14px 16px !important; min-height:48px; }
/* Kanban — single column on mobile */
.kanban-board { grid-template-columns:1fr !important; }

/* === TABLET (768px+) === */
@media (min-width:768px) {
  .weather-bar { padding:14px 20px; font-size:0.88rem; gap:14px; flex-wrap:nowrap; }
  .weather-emoji { font-size:1.8rem; }
  .weather-label { font-size:0.88rem; }
  .weather-score { font-size:1.5rem; padding:6px 16px; }
  .progress-ring-row { grid-template-columns:repeat(4,1fr); gap:1.25rem; }
  .ring-item { padding:1rem; }
  .ring-item svg { width:90px; height:90px; }
  .ring-value { font-size:1.2rem; }
  .card-grid { grid-template-columns:repeat(2,1fr) !important; }
  .card-grid-wide { grid-template-columns:repeat(2,1fr) !important; }
  table { font-size:0.85rem; }
  table th { font-size:0.75rem; padding:8px; }
  table td { padding:6px 8px; }
  .kanban-board { grid-template-columns:repeat(2,1fr) !important; }
  #ai-search-input { font-size:0.95rem !important; padding:12px 18px !important; }
}

/* === DESKTOP (1024px+) === */
@media (min-width:1024px) {
  .weather-bar { padding:14px 22px; }
  .progress-ring-row { gap:1.5rem; }
  .ring-item { padding:1rem 1.2rem; }
  .ring-item svg { width:100px; height:100px; }
  .card-grid { grid-template-columns:repeat(auto-fill,minmax(200px,1fr)) !important; }
  .card-grid-wide { grid-template-columns:repeat(auto-fill,minmax(260px,1fr)) !important; }
  table { font-size:0.88rem; }
  .kanban-board { grid-template-columns:repeat(4,1fr) !important; }
  #ai-search-input { font-size:0.92rem !important; padding:11px 18px !important; }
}

/* === WIDE DESKTOP (1400px+) === */
@media (min-width:1400px) {
  .progress-ring-row { gap:2rem; }
  .ring-item svg { width:110px; height:110px; }
  .ring-value { font-size:1.4rem; }
}

/* === Utility === */
html { scroll-behavior:smooth; }
body { overscroll-behavior:none; }
@supports (padding: env(safe-area-inset-bottom)) {
  main { padding-bottom:calc(1.5rem + env(safe-area-inset-bottom)); }
}
"
}

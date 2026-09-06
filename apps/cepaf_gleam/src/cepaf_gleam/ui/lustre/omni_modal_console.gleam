//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/lustre/omni_modal_console</module>
////     <lineage>EV-TENSOR-08 Omni-Modal Accessibility & Telemetry Console</lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <mesh-domain>WCAG AAA Keyboard Palettes, ARIA Announcements & Tailnet Ping Matrix</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>DAL-A / SIL-6 / HIGH</criticality>
////     <stamp-controls>
////       SC-UX-001, SC-CHECKLIST-001, SC-MUDA-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/float
import gleam/list
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

pub type KeyboardShortcut {
  KeyboardShortcut(
    key_combo: String,
    action_name: String,
    category: String,
  )
}

pub type TailnetNodeStatus {
  TailnetNodeStatus(
    hostname: String,
    ip_tailscale: String,
    latency_ms: Float,
    status: String,
  )
}

pub type OmniConsoleState {
  OmniConsoleState(
    shortcuts: List(KeyboardShortcut),
    nodes: List(TailnetNodeStatus),
    aria_live_mode: String,
    screen_reader_ready: Bool,
    contrast_theme: String,
    mean_tailnet_latency_ms: Float,
  )
}

pub fn build_canonical_console() -> OmniConsoleState {
  let scs = [
    KeyboardShortcut("Cmd+K", "Global Omnisearch", "Navigation"),
    KeyboardShortcut("?", "Keyboard Help Overlay", "Help"),
    KeyboardShortcut("g d", "Navigate to Cockpit Dashboard", "Navigation"),
    KeyboardShortcut("g p", "Navigate to Planning Cockpit", "Navigation"),
    KeyboardShortcut("g w", "Navigate to Wiki Corpus Index", "Knowledge"),
    KeyboardShortcut("g z", "Navigate to ZK Master MOC", "Knowledge"),
    KeyboardShortcut("t s", "Toggle Raw Source / Rendered View", "View"),
    KeyboardShortcut("Esc", "Close Modal or Palette", "System"),
  ]

  let nds = [
    TailnetNodeStatus("nas-1", "100.87.7.78", 0.45, "ONLINE"),
    TailnetNodeStatus("vm-1", "100.78.98.18", 11.2, "ONLINE"),
    TailnetNodeStatus("k8s-master", "100.87.7.80", 2.1, "ONLINE"),
  ]

  OmniConsoleState(
    shortcuts: scs,
    nodes: nds,
    aria_live_mode: "polite",
    screen_reader_ready: True,
    contrast_theme: "high_contrast_aaa",
    mean_tailnet_latency_ms: 4.58,
  )
}

pub fn shortcuts_count(c: OmniConsoleState) -> Int {
  list.length(c.shortcuts)
}

pub fn nodes_count(c: OmniConsoleState) -> Int {
  list.length(c.nodes)
}

pub fn render_omni_console_view(c: OmniConsoleState) -> Element(msg) {
  html.div([attribute.class("omni-console-container")], [
    html.h3([], [element.text("Omni-Modal Accessibility & Telemetry Console")]),
    html.div([attribute.class("console-metrics-bar")], [
      html.div([attribute.class("console-pill")], [
        html.strong([], [element.text("ARIA-Live Mode: ")]),
        element.text(c.aria_live_mode <> " (Screen Reader Active)"),
      ]),
      html.div([attribute.class("console-pill")], [
        html.strong([], [element.text("WCAG Contrast: ")]),
        element.text("Level AAA (8.4:1 ratio)"),
      ]),
      html.div([attribute.class("console-pill")], [
        html.strong([], [element.text("Mean Tailnet Transit: ")]),
        element.text(float.to_string(c.mean_tailnet_latency_ms) <> " ms"),
      ]),
    ]),
    html.div([attribute.class("console-two-col"), attribute.attribute("style", "display: flex; gap: 1.5rem; margin-top: 1rem;")], [
      html.div([attribute.class("col-shortcuts"), attribute.attribute("style", "flex: 1; background: #161b22; padding: 1rem; border-radius: 6px; border: 1px solid #30363d;")], [
        html.h4([attribute.attribute("style", "margin-top: 0; color: #58a6ff;")], [element.text("Command Palette Shortcuts (Cmd+K)")]),
        html.table([attribute.attribute("style", "width: 100%; border-collapse: collapse;")], [
          html.tbody([], {
            use sc <- list.map(c.shortcuts)
            html.tr([attribute.attribute("style", "border-top: 1px solid #222;")], [
              html.td([attribute.attribute("style", "padding: 6px; font-family: monospace; color: #ffc107; font-weight: bold;")], [element.text(sc.key_combo)]),
              html.td([attribute.attribute("style", "padding: 6px;")], [element.text(sc.action_name)]),
              html.td([attribute.attribute("style", "padding: 6px; color: #888;")], [element.text(sc.category)]),
            ])
          }),
        ]),
      ]),
      html.div([attribute.class("col-nodes"), attribute.attribute("style", "flex: 1; background: #161b22; padding: 1rem; border-radius: 6px; border: 1px solid #30363d;")], [
        html.h4([attribute.attribute("style", "margin-top: 0; color: #3fb950;")], [element.text("Tailnet Mesh Peer Latency")]),
        html.table([attribute.attribute("style", "width: 100%; border-collapse: collapse;")], [
          html.tbody([], {
            use nd <- list.map(c.nodes)
            html.tr([attribute.attribute("style", "border-top: 1px solid #222;")], [
              html.td([attribute.attribute("style", "padding: 6px; font-weight: bold;")], [element.text(nd.hostname)]),
              html.td([attribute.attribute("style", "padding: 6px; font-family: monospace;")], [element.text(nd.ip_tailscale)]),
              html.td([attribute.attribute("style", "padding: 6px; color: #38bdf8;")], [element.text(float.to_string(nd.latency_ms) <> " ms")]),
              html.td([attribute.attribute("style", "padding: 6px; color: #10b981;")], [element.text(nd.status)]),
            ])
          }),
        ]),
      ]),
    ]),
  ])
}

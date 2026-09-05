//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/shell</module>
////     <fsharp-lineage>Cepaf.UI.Shell.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <mesh-domain>Web HTML Shell — router-facing adapter</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-008, SC-HMI-010, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Thin adapter: normalises active_page path fragment before delegating to
////       cepaf_gleam/ui/lustre/shell.  Zero information loss.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Web-layer adapter for the Lustre HTML shell.
////
//// The Wisp router calls render_page/3 with a bare path fragment such as
//// "dashboard" — without the leading slash.  The Lustre shell compares against
//// domain.page_to_path/1 which returns "/dashboard".  This module normalises
//// the fragment by prepending "/" so the active-nav highlighting works.
////
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-008, SC-MUDA-001

import cepaf_gleam/ui/lustre/shell as lustre_shell
import lustre/element.{type Element}

/// Render a complete HTML document page.
///
/// `title`            — Title suffix for the browser tab / <title> element.
/// `active_page_frag` — URL fragment WITHOUT leading slash (e.g. "dashboard").
///                      A leading "/" is prepended internally so navigation
///                      highlighting works against domain.page_to_path output.
/// `content`          — Lustre element tree to place in <main>.
///
/// Returns a `<!doctype html>` + full HTML string suitable for the HTTP body.
pub fn render_page(
  title: String,
  active_page_frag: String,
  content: Element(msg),
) -> String {
  let active_path = "/" <> active_page_frag
  lustre_shell.render_page(title, active_path, content)
}

/// Re-export status_card for convenience.
pub fn status_card(
  title: String,
  status: String,
  value: String,
  detail: String,
) -> Element(msg) {
  lustre_shell.status_card(title, status, value, detail)
}

/// Re-export container_card for convenience.
pub fn container_card(
  name: String,
  status: String,
  cpu: Float,
  memory: Float,
) -> Element(msg) {
  lustre_shell.container_card(name, status, cpu, memory)
}

/// Re-export mini_bar for convenience.
pub fn mini_bar(value: Float, max: Float, color: String) -> Element(msg) {
  lustre_shell.mini_bar(value, max, color)
}

/// Re-export section for convenience.
pub fn section(title: String, children: List(Element(msg))) -> Element(msg) {
  lustre_shell.section(title, children)
}

/// Re-export kv_row for convenience.
pub fn kv_row(key: String, value: String) -> Element(msg) {
  lustre_shell.kv_row(key, value)
}

/// Re-export alert_banner for convenience.
pub fn alert_banner(severity: String, message: String) -> Element(msg) {
  lustre_shell.alert_banner(severity, message)
}

/// Re-export data_table for convenience.
pub fn data_table(
  headers: List(String),
  rows: List(List(String)),
) -> Element(msg) {
  lustre_shell.data_table(headers, rows)
}

/// Action button that performs an API call via JS fetch.
pub fn action_button(
  label: String,
  endpoint: String,
  payload: String,
) -> Element(msg) {
  lustre_shell.action_button(label, endpoint, payload)
}

/// Apalache Formal Verification Gate (SC-ULTRA-UI-004)
pub fn apalache_guard(
  action: Element(msg),
  safety_status: String,
) -> Element(msg) {
  lustre_shell.apalache_guard(action, safety_status)
}

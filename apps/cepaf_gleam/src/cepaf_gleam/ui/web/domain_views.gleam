//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/domain_views</module>
////     <fsharp-lineage>Cepaf.UI.Web.PageViews.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTION</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-004, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="surjective" loss="none">
////       page_views.gleam ↠ domain_views.gleam (split by domain).
////       Mitigation: All helpers duplicated as private fns — zero public surface change.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// विभागशः — Division into parts, each complete in itself (Gita 18.41)
////
//// Domain-layer views: Planning (L3), Knowledge (L5), Agents (L5),
//// Prajna (L5), Smriti (L5), Holon (L4), Config (L4), Git (L4),
//// Database (L3), Bridge (L6).

import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/ui/lustre/shell
import cepaf_gleam/ui/state.{
  type SharedMeshState, ThreatElevated, ThreatLow, ThreatNominal, ThreatNone,
  cockpit_mode_to_string, ooda_phase_to_string,
}
// Pass-26 — Phase 3a per-page split: bridge view extracted.
// Pass-27 — Phase 3b: shared helpers extracted to page_helpers module.
import cepaf_gleam/ui/web/page_helpers.{asset_cachebust_id, count_in_json, page_header, planning_enhanced_css, progress_ring, state_kv_block}
import cepaf_gleam/ui/web/pages/bridge_page
import cepaf_gleam/ui/web/pages/config_page
import cepaf_gleam/ui/web/pages/database_page
import cepaf_gleam/ui/web/pages/git_page
import cepaf_gleam/ui/web/pages/holon_page
import cepaf_gleam/ui/web/pages/knowledge_page
import cepaf_gleam/ui/web/pages/prajna_page
import cepaf_gleam/ui/web/pages/agents_page
import cepaf_gleam/ui/web/pages/smriti_page
import cepaf_gleam/ui/web/pages/planning_page
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html

// ---------------------------------------------------------------------------
// Public views
// ---------------------------------------------------------------------------

/// Pass-27 Phase 3e: planning_view body extracted to pages/planning_page.gleam.
pub fn planning_view(state: SharedMeshState) -> Element(msg) {
  planning_page.view(state)
}

/// Pass-27 Phase 3d: knowledge_view body extracted to pages/knowledge_page.gleam.
pub fn knowledge_view(state: SharedMeshState) -> Element(msg) {
  knowledge_page.view(state)
}

/// Pass-27 Phase 3d: prajna_view body extracted to pages/prajna_page.gleam.
pub fn prajna_view(state: SharedMeshState) -> Element(msg) {
  prajna_page.view(state)
}

/// Pass-27 Phase 3d: agents_view body extracted to pages/agents_page.gleam.
pub fn agents_view(state: SharedMeshState) -> Element(msg) {
  agents_page.view(state)
}

/// Pass-27 Phase 3c: holon_view body extracted to pages/holon_page.gleam.
pub fn holon_view(state: SharedMeshState) -> Element(msg) {
  holon_page.view(state)
}

/// Pass-27 Phase 3c: config_view body extracted to pages/config_page.gleam.
pub fn config_view(state: SharedMeshState) -> Element(msg) {
  config_page.view(state)
}

/// Pass-27 Phase 3c: git_view body extracted to pages/git_page.gleam.
pub fn git_view(state: SharedMeshState) -> Element(msg) {
  git_page.view(state)
}

/// Pass-27 Phase 3c: database_view body extracted to pages/database_page.gleam.
pub fn database_view(state: SharedMeshState) -> Element(msg) {
  database_page.view(state)
}

pub fn bridge_view(state: SharedMeshState) -> Element(msg) {
  bridge_page.view(state)
}


/// Pass-27 Phase 3d: smriti_view body extracted to pages/smriti_page.gleam.
pub fn smriti_view(state: SharedMeshState) -> Element(msg) {
  smriti_page.view(state)
}

// ---------------------------------------------------------------------------
// Private helpers (duplicated from page_views — SC-MUDA-001 approved)
// ---------------------------------------------------------------------------


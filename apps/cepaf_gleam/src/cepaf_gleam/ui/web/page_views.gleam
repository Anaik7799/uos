//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/web/page_views</module>
////     <fsharp-lineage>Cepaf.UI.Pages.fs</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L2_COMPONENT</layer>
////     <mesh-domain>Re-export facade — delegates to domain-split sub-modules</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-GLM-UI-001, SC-GLM-UI-004, SC-MUDA-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="isomorphic">
////       Thin facade — every public function delegates 1:1 to a domain module.
////       Zero logic lives here; all callers (router, tests) remain unchanged.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// विभागशः — Division into parts, each complete in itself (Gita 18.41)
////
//// Facade module: re-exports all 34 public page-view functions from their
//// domain-split sub-modules. Callers (router.gleam, test files) continue to
//// import cepaf_gleam/ui/web/page_views without change.
////
//// Sub-modules:
////   dashboard_views  — dashboard, cockpit, planning_dashboard
////   system_views     — immune, zenoh, verification, substrate, metabolic,
////                      podman, mcp, kms, telemetry
////   domain_views     — planning, knowledge, prajna, agents, holon, config,
////                      git, database, bridge, smriti
////   special_views    — integrity, evolution, biomorphic, homeostasis,
////                      bicameral, singularity, federation, health_grid,
////                      component_demo, allium_index, allium_spec, not_found

import cepaf_gleam/fractal/l1_atomic_debug
import cepaf_gleam/fractal/l2_component
import cepaf_gleam/fractal/l3_transaction
import cepaf_gleam/fractal/l4_system
import cepaf_gleam/fractal/l6_ecosystem
import cepaf_gleam/ui/state.{type SharedMeshState}
import cepaf_gleam/ui/web/dashboard_views
import cepaf_gleam/ui/web/domain_views
import cepaf_gleam/ui/web/special_views
import cepaf_gleam/ui/web/system_views
import lustre/element.{type Element}

// ---------------------------------------------------------------------------
// Dashboard views (dashboard_views.gleam)
// ---------------------------------------------------------------------------

pub fn dashboard_view(state: SharedMeshState) -> Element(msg) {
  dashboard_views.dashboard_view(state)
}

pub fn cockpit_view(state: SharedMeshState) -> Element(msg) {
  dashboard_views.cockpit_view(state)
}

pub fn planning_dashboard_view(state: SharedMeshState) -> Element(msg) {
  dashboard_views.planning_dashboard_view(state)
}

// ---------------------------------------------------------------------------
// System views (system_views.gleam)
// ---------------------------------------------------------------------------

pub fn immune_view(state: SharedMeshState) -> Element(msg) {
  system_views.immune_view(state)
}

pub fn zenoh_view(state: SharedMeshState) -> Element(msg) {
  system_views.zenoh_view(state)
}

pub fn verification_view(state: SharedMeshState) -> Element(msg) {
  system_views.verification_view(state)
}

pub fn substrate_view(state: SharedMeshState) -> Element(msg) {
  system_views.substrate_view(state)
}

pub fn metabolic_view(state: SharedMeshState) -> Element(msg) {
  system_views.metabolic_view(state)
}

pub fn podman_view(state: SharedMeshState) -> Element(msg) {
  system_views.podman_view(state)
}

pub fn mcp_view(state: SharedMeshState) -> Element(msg) {
  system_views.mcp_view(state)
}

pub fn kms_view(state: SharedMeshState) -> Element(msg) {
  system_views.kms_view(state)
}

pub fn telemetry_view(state: SharedMeshState) -> Element(msg) {
  system_views.telemetry_view(state)
}

// ---------------------------------------------------------------------------
// Domain views (domain_views.gleam)
// ---------------------------------------------------------------------------

pub fn planning_view(state: SharedMeshState) -> Element(msg) {
  domain_views.planning_view(state)
}

pub fn knowledge_view(state: SharedMeshState) -> Element(msg) {
  domain_views.knowledge_view(state)
}

pub fn prajna_view(state: SharedMeshState) -> Element(msg) {
  domain_views.prajna_view(state)
}

pub fn agents_view(state: SharedMeshState) -> Element(msg) {
  domain_views.agents_view(state)
}

pub fn holon_view(state: SharedMeshState) -> Element(msg) {
  domain_views.holon_view(state)
}

pub fn config_view(state: SharedMeshState) -> Element(msg) {
  domain_views.config_view(state)
}

pub fn git_view(state: SharedMeshState) -> Element(msg) {
  domain_views.git_view(state)
}

pub fn database_view(state: SharedMeshState) -> Element(msg) {
  domain_views.database_view(state)
}

pub fn bridge_view(state: SharedMeshState) -> Element(msg) {
  domain_views.bridge_view(state)
}

pub fn smriti_view(state: SharedMeshState) -> Element(msg) {
  domain_views.smriti_view(state)
}

// ---------------------------------------------------------------------------
// Special views (special_views.gleam)
// ---------------------------------------------------------------------------

pub fn integrity_view(state: SharedMeshState) -> Element(msg) {
  special_views.integrity_view(state)
}

pub fn evolution_view(state: SharedMeshState) -> Element(msg) {
  special_views.evolution_view(state)
}

pub fn biomorphic_view(state: SharedMeshState) -> Element(msg) {
  special_views.biomorphic_view(state)
}

pub fn homeostasis_view(state: SharedMeshState) -> Element(msg) {
  special_views.homeostasis_view(state)
}

pub fn bicameral_view(state: SharedMeshState) -> Element(msg) {
  special_views.bicameral_view(state)
}

pub fn singularity_view(state: SharedMeshState) -> Element(msg) {
  special_views.singularity_view(state)
}

pub fn federation_view(state: SharedMeshState) -> Element(msg) {
  special_views.federation_view(state)
}

pub fn health_grid_view(state: SharedMeshState) -> Element(msg) {
  special_views.health_grid_view(state)
}

pub fn component_demo_view(state: SharedMeshState) -> Element(msg) {
  special_views.component_demo_view(state)
}

pub fn allium_index_view() -> Element(msg) {
  special_views.allium_index_view()
}

pub fn allium_spec_view(name: String) -> Element(msg) {
  special_views.allium_spec_view(name)
}

pub fn not_found_view(path: String) -> Element(msg) {
  special_views.not_found_view(path)
}

// ---------------------------------------------------------------------------
// Fractal layer widget factory (L1-L4, L6)
// Wires orphaned fractal modules into the production dependency graph.
// Each fractal layer exposes its initial state for use by the rendering layer.
// STAMP: SC-FRACTAL-001, SC-GLM-UI-001
// ---------------------------------------------------------------------------

/// Returns initial state for all wired fractal layers as a tuple.
/// L1 (atomic/debug), L2 (component), L3 (transaction), L4 (system), L6 (ecosystem).
pub fn fractal_initial_states() -> #(
  l1_atomic_debug.EventMonitorState,
  l2_component.DataGridState,
  l3_transaction.TransactionPanelState,
  l4_system.RunMonitorState,
  l6_ecosystem.MeshState,
) {
  #(
    l1_atomic_debug.initial_monitor(),
    l2_component.initial_grid([]),
    l3_transaction.initial_panel(),
    l4_system.initial_run_monitor(),
    l6_ecosystem.initial_mesh(),
  )
}

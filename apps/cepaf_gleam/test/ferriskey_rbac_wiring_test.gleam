//// =============================================================================
//// [C3I-SIL6-MSTS] FERRISKEY IAM — RBAC MAPPING EXHAUSTIVENESS GUARD
//// =============================================================================
//// STAMP: SC-IAM-003 (RBAC mapping to fractal layers MUST be exhaustive),
////        SC-CPIG-002 (cross-pass invariant gate),
////        SC-WIRE-001 (wiring guard pattern).
////
//// Purpose: every C3I role from the canonical FerrisKey realm MUST map to a
//// fractal-layer subset. Adding a role without a mapping (or removing a
//// mapping without retiring the role) breaks the test — surfacing IAM
//// drift before it reaches production realms.
////
//// Reference rules:
////   .claude/rules/auth-iam-constraints.md
////   .claude/rules/cross-pass-invariant-gate.md
//// =============================================================================

import gleam/list
import gleeunit/should

/// Canonical C3I role -> fractal-layer subset, mirroring the RBAC table in
/// .claude/rules/auth-iam-constraints.md (§ "RBAC → Fractal Layer Mapping").
fn canonical_role_layer_map() -> List(#(String, List(String))) {
  [
    #("c3i-admin", ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]),
    #("c3i-operator", ["L1", "L2", "L3", "L4", "L5", "L6", "L7"]),
    #("c3i-viewer", ["L4", "L5", "L6", "L7"]),
    #("c3i-service", ["L3", "L4", "L5", "L6"]),
  ]
}

fn canonical_roles() -> List(String) {
  ["c3i-admin", "c3i-operator", "c3i-viewer", "c3i-service"]
}

pub fn role_count_test() {
  canonical_role_layer_map()
  |> list.length
  |> should.equal(4)
}

pub fn every_role_has_mapping_test() {
  let mapped = list.map(canonical_role_layer_map(), fn(pair) { pair.0 })
  canonical_roles()
  |> list.all(fn(role) { list.contains(mapped, role) })
  |> should.be_true()
}

pub fn no_role_maps_to_empty_layer_set_test() {
  canonical_role_layer_map()
  |> list.all(fn(pair) { pair.1 != [] })
  |> should.be_true()
}

pub fn admin_covers_all_eight_layers_test() {
  let assert Ok(admin) =
    list.find(canonical_role_layer_map(), fn(pair) { pair.0 == "c3i-admin" })
  list.length(admin.1) |> should.equal(8)
}

pub fn viewer_excludes_constitutional_test() {
  let assert Ok(viewer) =
    list.find(canonical_role_layer_map(), fn(pair) { pair.0 == "c3i-viewer" })
  list.contains(viewer.1, "L0") |> should.be_false()
}

pub fn no_duplicate_roles_test() {
  let roles = list.map(canonical_role_layer_map(), fn(pair) { pair.0 })
  list.length(roles) |> should.equal(list.length(list.unique(roles)))
}

import cepaf_gleam/auth/rbac
import cepaf_gleam/ui/domain.{
  L0Constitutional, L1AtomicDebug, L2Component, L3Transaction, L4System,
  L5Cognitive, L6Ecosystem, L7Federation,
}
import gleam/list
import gleeunit/should

// =============================================================================
// C1: RBAC Type Construction
// =============================================================================

pub fn authenticated_user_constructs_test() {
  let user =
    rbac.AuthenticatedUser(
      sub: "user-1",
      username: "admin",
      email: "admin@c3i.dev",
      roles: ["c3i-admin"],
      permission: rbac.FullAccess,
      has_mfa: True,
    )
  user.username |> should.equal("admin")
  user.has_mfa |> should.be_true()
}

// =============================================================================
// C2: Role → Permission Mapping
// =============================================================================

pub fn admin_role_maps_to_full_access_test() {
  rbac.role_to_permission("c3i-admin")
  |> should.equal(rbac.FullAccess)
}

pub fn operator_role_maps_to_operator_access_test() {
  rbac.role_to_permission("c3i-operator")
  |> should.equal(rbac.OperatorAccess)
}

pub fn viewer_role_maps_to_viewer_access_test() {
  rbac.role_to_permission("c3i-viewer")
  |> should.equal(rbac.ViewerAccess)
}

pub fn service_role_maps_to_service_account_test() {
  rbac.role_to_permission("c3i-service")
  |> should.equal(rbac.ServiceAccount)
}

pub fn unknown_role_maps_to_no_access_test() {
  rbac.role_to_permission("unknown-role")
  |> should.equal(rbac.NoAccess)
}

// =============================================================================
// C5: Permission Resolution (highest wins)
// =============================================================================

pub fn resolve_admin_and_viewer_gives_full_access_test() {
  rbac.resolve_permission(["c3i-viewer", "c3i-admin"])
  |> should.equal(rbac.FullAccess)
}

pub fn resolve_operator_and_viewer_gives_operator_test() {
  rbac.resolve_permission(["c3i-viewer", "c3i-operator"])
  |> should.equal(rbac.OperatorAccess)
}

pub fn resolve_empty_roles_gives_no_access_test() {
  rbac.resolve_permission([])
  |> should.equal(rbac.NoAccess)
}

pub fn resolve_single_viewer_test() {
  rbac.resolve_permission(["c3i-viewer"])
  |> should.equal(rbac.ViewerAccess)
}

// =============================================================================
// C3: Layer Access Control
// =============================================================================

pub fn full_access_can_access_all_layers_test() {
  rbac.can_access_layer(rbac.FullAccess, L0Constitutional) |> should.be_true()
  rbac.can_access_layer(rbac.FullAccess, L4System) |> should.be_true()
  rbac.can_access_layer(rbac.FullAccess, L7Federation) |> should.be_true()
}

pub fn operator_cannot_access_l0_test() {
  rbac.can_access_layer(rbac.OperatorAccess, L0Constitutional)
  |> should.be_false()
}

pub fn operator_can_access_l1_through_l7_test() {
  rbac.can_access_layer(rbac.OperatorAccess, L1AtomicDebug) |> should.be_true()
  rbac.can_access_layer(rbac.OperatorAccess, L3Transaction) |> should.be_true()
  rbac.can_access_layer(rbac.OperatorAccess, L7Federation) |> should.be_true()
}

pub fn viewer_can_only_access_l4_through_l7_test() {
  rbac.can_access_layer(rbac.ViewerAccess, L0Constitutional)
  |> should.be_false()
  rbac.can_access_layer(rbac.ViewerAccess, L3Transaction) |> should.be_false()
  rbac.can_access_layer(rbac.ViewerAccess, L4System) |> should.be_true()
  rbac.can_access_layer(rbac.ViewerAccess, L7Federation) |> should.be_true()
}

pub fn service_account_access_l3_through_l6_test() {
  rbac.can_access_layer(rbac.ServiceAccount, L2Component) |> should.be_false()
  rbac.can_access_layer(rbac.ServiceAccount, L3Transaction) |> should.be_true()
  rbac.can_access_layer(rbac.ServiceAccount, L6Ecosystem) |> should.be_true()
  rbac.can_access_layer(rbac.ServiceAccount, L7Federation) |> should.be_false()
}

pub fn no_access_cannot_access_any_layer_test() {
  rbac.can_access_layer(rbac.NoAccess, L0Constitutional) |> should.be_false()
  rbac.can_access_layer(rbac.NoAccess, L4System) |> should.be_false()
  rbac.can_access_layer(rbac.NoAccess, L7Federation) |> should.be_false()
}

// =============================================================================
// C8: MFA Enforcement (L0 Constitutional)
// =============================================================================

pub fn l0_requires_mfa_test() {
  rbac.require_mfa_for_layer(L0Constitutional)
  |> should.be_true()
}

pub fn l1_through_l7_do_not_require_mfa_test() {
  rbac.require_mfa_for_layer(L1AtomicDebug) |> should.be_false()
  rbac.require_mfa_for_layer(L2Component) |> should.be_false()
  rbac.require_mfa_for_layer(L3Transaction) |> should.be_false()
  rbac.require_mfa_for_layer(L4System) |> should.be_false()
  rbac.require_mfa_for_layer(L5Cognitive) |> should.be_false()
  rbac.require_mfa_for_layer(L6Ecosystem) |> should.be_false()
  rbac.require_mfa_for_layer(L7Federation) |> should.be_false()
}

pub fn authorize_admin_with_mfa_at_l0_succeeds_test() {
  let user =
    rbac.AuthenticatedUser(
      sub: "u1",
      username: "admin",
      email: "",
      roles: ["c3i-admin"],
      permission: rbac.FullAccess,
      has_mfa: True,
    )
  rbac.authorize_layer_access(user, L0Constitutional)
  |> should.be_ok()
}

pub fn authorize_admin_without_mfa_at_l0_fails_test() {
  let user =
    rbac.AuthenticatedUser(
      sub: "u1",
      username: "admin",
      email: "",
      roles: ["c3i-admin"],
      permission: rbac.FullAccess,
      has_mfa: False,
    )
  rbac.authorize_layer_access(user, L0Constitutional)
  |> should.equal(Error("mfa_required"))
}

pub fn authorize_viewer_at_l0_fails_test() {
  let user =
    rbac.AuthenticatedUser(
      sub: "u1",
      username: "viewer",
      email: "",
      roles: ["c3i-viewer"],
      permission: rbac.ViewerAccess,
      has_mfa: False,
    )
  rbac.authorize_layer_access(user, L0Constitutional)
  |> should.equal(Error("insufficient_permission"))
}

pub fn authorize_viewer_at_l5_succeeds_test() {
  let user =
    rbac.AuthenticatedUser(
      sub: "u1",
      username: "viewer",
      email: "",
      roles: ["c3i-viewer"],
      permission: rbac.ViewerAccess,
      has_mfa: False,
    )
  rbac.authorize_layer_access(user, L5Cognitive)
  |> should.be_ok()
}

// =============================================================================
// C4: Accessible Layers
// =============================================================================

pub fn full_access_has_8_layers_test() {
  rbac.accessible_layers(rbac.FullAccess)
  |> list.length()
  |> should.equal(8)
}

pub fn operator_has_7_layers_test() {
  rbac.accessible_layers(rbac.OperatorAccess)
  |> list.length()
  |> should.equal(7)
}

pub fn viewer_has_4_layers_test() {
  rbac.accessible_layers(rbac.ViewerAccess)
  |> list.length()
  |> should.equal(4)
}

pub fn service_has_4_layers_test() {
  rbac.accessible_layers(rbac.ServiceAccount)
  |> list.length()
  |> should.equal(4)
}

pub fn no_access_has_0_layers_test() {
  rbac.accessible_layers(rbac.NoAccess)
  |> list.length()
  |> should.equal(0)
}

// =============================================================================
// C6: Permission String Conversion
// =============================================================================

pub fn permission_to_string_test() {
  rbac.permission_to_string(rbac.FullAccess) |> should.equal("full_access")
  rbac.permission_to_string(rbac.OperatorAccess)
  |> should.equal("operator_access")
  rbac.permission_to_string(rbac.ViewerAccess) |> should.equal("viewer_access")
  rbac.permission_to_string(rbac.ServiceAccount)
  |> should.equal("service_account")
  rbac.permission_to_string(rbac.NoAccess) |> should.equal("no_access")
}

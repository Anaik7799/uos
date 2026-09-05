//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/auth/rbac</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-IAM-003, SC-IAM-004, SC-AUTH-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       FerrisKey realm roles ↪ C3I fractal layer permissions.
////       Exhaustive mapping ensures no role is unmapped (SC-IAM-003).
////       MFA enforcement for L0 Constitutional operations (SC-IAM-004).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// Role-Based Access Control mapping FerrisKey roles to C3I fractal layers.
//// Each role maps to a permission level that determines which fractal layers
//// (L0-L7) the authenticated user can access.
////
//// STAMP: SC-IAM-003, SC-IAM-004, SC-AUTH-001

import cepaf_gleam/ui/domain.{
  type FractalLayer, L0Constitutional, L1AtomicDebug, L2Component, L3Transaction,
  L4System, L5Cognitive, L6Ecosystem, L7Federation,
}
import gleam/list

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Permission level derived from FerrisKey roles.
/// Maps to accessible fractal layers.
pub type FractalPermission {
  /// Full access (L0-L7). MFA required for L0 operations.
  FullAccess
  /// Operator access (L1-L7). Cannot perform L0 Constitutional operations.
  OperatorAccess
  /// Read-only access (L4-L7).
  ViewerAccess
  /// Machine-to-machine service account (L3-L6).
  ServiceAccount
  /// No access (unauthenticated or unrecognized role).
  NoAccess
}

/// Authenticated user context for request handling.
pub type AuthenticatedUser {
  AuthenticatedUser(
    sub: String,
    username: String,
    email: String,
    roles: List(String),
    permission: FractalPermission,
    has_mfa: Bool,
  )
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Map a FerrisKey role name to a C3I fractal permission level.
///
/// Role priority (highest wins):
///   c3i-admin    -> FullAccess (L0-L7, MFA required for L0)
///   c3i-operator -> OperatorAccess (L1-L7)
///   c3i-service  -> ServiceAccount (L3-L6)
///   c3i-viewer   -> ViewerAccess (L4-L7)
///   unknown      -> NoAccess
pub fn role_to_permission(role: String) -> FractalPermission {
  case role {
    "c3i-admin" -> FullAccess
    "c3i-operator" -> OperatorAccess
    "c3i-service" -> ServiceAccount
    "c3i-viewer" -> ViewerAccess
    _ -> NoAccess
  }
}

/// Determine the highest permission level from a list of roles.
/// Higher permission levels take precedence.
pub fn resolve_permission(roles: List(String)) -> FractalPermission {
  roles
  |> list.map(role_to_permission)
  |> list.fold(NoAccess, fn(best, perm) {
    case permission_level(perm) > permission_level(best) {
      True -> perm
      False -> best
    }
  })
}

/// Check if a permission level can access a specific fractal layer.
pub fn can_access_layer(
  permission: FractalPermission,
  layer: FractalLayer,
) -> Bool {
  let level = domain.layer_level(layer)
  case permission {
    FullAccess -> True
    OperatorAccess -> level >= 1
    ServiceAccount -> level >= 3 && level <= 6
    ViewerAccess -> level >= 4
    NoAccess -> False
  }
}

/// Check if MFA is required for operations at a given fractal layer.
///
/// L0 Constitutional operations ALWAYS require MFA (SC-IAM-004).
/// Guardian approval, emergency stop, Psi invariant changes.
pub fn require_mfa_for_layer(layer: FractalLayer) -> Bool {
  case layer {
    L0Constitutional -> True
    L1AtomicDebug -> False
    L2Component -> False
    L3Transaction -> False
    L4System -> False
    L5Cognitive -> False
    L6Ecosystem -> False
    L7Federation -> False
  }
}

/// Verify that an authenticated user can perform an operation at a layer.
///
/// Returns Ok(Nil) if authorized, Error(reason) if not.
/// Checks both layer access AND MFA requirement for L0.
pub fn authorize_layer_access(
  user: AuthenticatedUser,
  layer: FractalLayer,
) -> Result(Nil, String) {
  case can_access_layer(user.permission, layer) {
    False -> Error("insufficient_permission")
    True -> {
      case require_mfa_for_layer(layer) && !user.has_mfa {
        True -> Error("mfa_required")
        False -> Ok(Nil)
      }
    }
  }
}

/// Convert permission to string for logging/display.
pub fn permission_to_string(permission: FractalPermission) -> String {
  case permission {
    FullAccess -> "full_access"
    OperatorAccess -> "operator_access"
    ViewerAccess -> "viewer_access"
    ServiceAccount -> "service_account"
    NoAccess -> "no_access"
  }
}

/// Get the list of accessible fractal layers for a permission level.
pub fn accessible_layers(permission: FractalPermission) -> List(FractalLayer) {
  let all_layers = [
    L0Constitutional, L1AtomicDebug, L2Component, L3Transaction, L4System,
    L5Cognitive, L6Ecosystem, L7Federation,
  ]
  list.filter(all_layers, fn(layer) { can_access_layer(permission, layer) })
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Numeric priority for permission levels (higher = more access).
fn permission_level(perm: FractalPermission) -> Int {
  case perm {
    FullAccess -> 4
    OperatorAccess -> 3
    ServiceAccount -> 2
    ViewerAccess -> 1
    NoAccess -> 0
  }
}

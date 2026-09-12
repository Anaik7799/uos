//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ui/tui/auth_view</module>
////     <fsharp-lineage>New — no F# predecessor</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GLM-UI-001, SC-AUTH-001, SC-IAM-003</stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================
////
//// TUI terminal view for authentication status (ANSI rendering).
//// Part of the triple-interface mandate: Lustre + Wisp + TUI (SC-GLM-UI-001).
////
//// STAMP: SC-GLM-UI-001, SC-AUTH-001, SC-IAM-003

import cepaf_gleam/auth/rbac.{
  type FractalPermission, FullAccess, NoAccess, OperatorAccess, ServiceAccount,
  ViewerAccess,
}
import gleam/list
import gleam/string

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Render auth status for TUI display (ANSI terminal).
pub fn render(
  username: String,
  permission: FractalPermission,
  roles: List(String),
  has_mfa: Bool,
  ferriskey_enabled: Bool,
) -> String {
  let header = "\u{001b}[1;36m=== Authentication Status ===\u{001b}[0m\n"

  let identity_section =
    "\u{001b}[1mIdentity\u{001b}[0m\n"
    <> "  User:       " <> username <> "\n"
    <> "  Permission: " <> permission_colored(permission) <> "\n"
    <> "  MFA:        " <> mfa_colored(has_mfa) <> "\n"

  let roles_section =
    "\u{001b}[1mRoles\u{001b}[0m\n"
    <> case roles {
      [] -> "  (none)\n"
      _ ->
        roles
        |> list.map(fn(r) { "  - " <> r <> "\n" })
        |> string.join("")
    }

  let layers_section =
    "\u{001b}[1mAccessible Layers\u{001b}[0m\n"
    <> "  " <> layers_bar(permission) <> "\n"

  let iam_section =
    "\u{001b}[1mFerrisKey IAM\u{001b}[0m\n"
    <> "  Status: " <> case ferriskey_enabled {
      True -> "\u{001b}[32mConnected\u{001b}[0m"
      False -> "\u{001b}[33mDisabled (static token)\u{001b}[0m"
    } <> "\n"

  header <> "\n" <> identity_section <> "\n" <> roles_section <> "\n"
  <> layers_section <> "\n" <> iam_section
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn permission_colored(perm: FractalPermission) -> String {
  case perm {
    FullAccess -> "\u{001b}[1;31mFull Access (Admin)\u{001b}[0m"
    OperatorAccess -> "\u{001b}[1;33mOperator\u{001b}[0m"
    ViewerAccess -> "\u{001b}[1;32mViewer\u{001b}[0m"
    ServiceAccount -> "\u{001b}[1;35mService Account\u{001b}[0m"
    NoAccess -> "\u{001b}[1;90mNo Access\u{001b}[0m"
  }
}

fn mfa_colored(has_mfa: Bool) -> String {
  case has_mfa {
    True -> "\u{001b}[32mEnrolled\u{001b}[0m"
    False -> "\u{001b}[33mNot Enrolled\u{001b}[0m"
  }
}

fn layers_bar(perm: FractalPermission) -> String {
  let layers = ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"]
  layers
  |> list.index_map(fn(label, idx) {
    let accessible = case perm {
      FullAccess -> True
      OperatorAccess -> idx >= 1
      ServiceAccount -> idx >= 3 && idx <= 6
      ViewerAccess -> idx >= 4
      NoAccess -> False
    }
    case accessible {
      True -> "\u{001b}[42;30m " <> label <> " \u{001b}[0m"
      False -> "\u{001b}[100;37m " <> label <> " \u{001b}[0m"
    }
  })
  |> string.join(" ")
}

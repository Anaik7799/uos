//// Vault migration — pure decision logic for the Slice E caller flip.
////
//// Slice E partial (Pass-27): the 5-module caller flip in
//// `sub-projects/c3i/native/planning_daemon/src/{mcp_inference,gateway,
//// mcp_gworkspace,cortex,audit_log}.rs` will eventually replace direct
//// `db::get_preference("secrets", _)` calls with `vault.get`. Until that
//// flip lands across all 5 callers, callers run this decision function to
//// determine whether to use the vault path or the legacy preference path.
////
//// Per .claude/rules/secrets-vault.md SC-VAULT-003 (all reads via vault.gleam)
//// + SC-VAULT-025 (.pi/ secrets via REST endpoint, never JSON).
////
//// Pure function, no side effects → unit-testable in-process.

// =====================================================================
// Types
// =====================================================================

/// Storage backend a secret currently lives in.
pub type SecretBackend {
  /// Vault NIF storage (target state per SC-VAULT-003).
  VaultBackend
  /// Legacy `UserPreferences[secrets]` SQLite rows (origin pre-vault).
  LegacyPrefsBackend
  /// `.pi/config.json` plaintext (origin; MUST be migrated per SC-VAULT-004).
  PiJsonBackend
  /// Secret not yet known to either side.
  UnknownBackend
}

/// What the migration helper tells the caller to do.
pub type MigrationAction {
  /// Use vault.get — the secret is already migrated.
  UseVault
  /// Vault is sealed but secret exists in legacy prefs; allow controlled fallback.
  /// SC-VAULT-001: this MUST be operator-gated and logged.
  UseLegacyWithGuard(reason: String)
  /// Reject — vault is sealed AND no legacy fallback (or fallback forbidden).
  /// Per SC-VAULT-006 fail-closed semantics.
  RejectFailClosed(reason: String)
  /// Migration trigger: secret found in legacy/PI but not in vault — caller
  /// SHOULD call vault.put + remove from legacy in same audit transaction.
  TriggerMigration(from: SecretBackend)
}

// =====================================================================
// Public API
// =====================================================================

/// Pure decision: given the secret name, where it currently lives, vault state,
/// and operator policy, return the right `MigrationAction`.
///
/// Decision matrix (deliberately exhaustive — every input combo handled):
///
/// vault_active=T:
///   in_vault=T → UseVault                                     (preferred path)
///   in_vault=F, in_legacy=T → TriggerMigration(LegacyPrefsBackend)
///   in_vault=F, in_legacy=F, in_pi=T → TriggerMigration(PiJsonBackend)
///   in_vault=F, all=F → RejectFailClosed("secret unknown")
///
/// vault_active=F:
///   allow_legacy=T:
///     in_legacy=T → UseLegacyWithGuard("vault sealed, legacy fallback gated")
///     in_legacy=F → RejectFailClosed("vault sealed and no legacy")
///   allow_legacy=F → RejectFailClosed("vault sealed and legacy forbidden")
pub fn decide(
  secret_name: String,
  vault_active: Bool,
  in_vault: Bool,
  in_legacy: Bool,
  in_pi: Bool,
  allow_legacy_fallback: Bool,
) -> MigrationAction {
  let _ = secret_name
  case vault_active, in_vault, in_legacy, in_pi, allow_legacy_fallback {
    True, True, _, _, _ -> UseVault
    True, False, True, _, _ -> TriggerMigration(from: LegacyPrefsBackend)
    True, False, False, True, _ -> TriggerMigration(from: PiJsonBackend)
    True, False, False, False, _ ->
      RejectFailClosed(reason: "secret unknown to all backends")
    False, _, True, _, True ->
      UseLegacyWithGuard(reason: "vault sealed, legacy fallback gated")
    False, _, _, _, _ ->
      RejectFailClosed(reason: "vault sealed and no legacy fallback available")
  }
}

/// Convenience: classify the migration action's safety level for the
/// dashboard Andon tile (matches the freshness color taxonomy).
pub fn action_safety(action: MigrationAction) -> String {
  case action {
    UseVault -> "green"
    UseLegacyWithGuard(_) -> "amber"
    TriggerMigration(_) -> "amber"
    RejectFailClosed(_) -> "red"
  }
}

/// Returns True iff this action proceeds (caller serves a value to client).
/// Used by `audit_log.rs` to count successful vs rejected access attempts.
pub fn is_serving(action: MigrationAction) -> Bool {
  case action {
    UseVault -> True
    UseLegacyWithGuard(_) -> True
    TriggerMigration(_) -> True
    RejectFailClosed(_) -> False
  }
}

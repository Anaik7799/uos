//// vault_migration_test — Pass-27 exhaustive coverage of pure decision logic
//// for the Slice E caller flip.

import cepaf_gleam/vault_migration.{
  LegacyPrefsBackend, PiJsonBackend, RejectFailClosed, TriggerMigration,
  UseLegacyWithGuard, UseVault, action_safety, decide, is_serving,
}
import gleeunit/should

// =====================================================================
// Vault active path
// =====================================================================

pub fn vault_active_in_vault_yields_use_vault_test() {
  decide("k1", True, True, False, False, False) |> should.equal(UseVault)
}

pub fn vault_active_in_vault_with_legacy_present_still_uses_vault_test() {
  // Vault is the preferred path (SC-VAULT-003) — even if legacy still has row
  decide("k1", True, True, True, False, True) |> should.equal(UseVault)
}

pub fn vault_active_legacy_only_triggers_migration_test() {
  case decide("k1", True, False, True, False, False) {
    TriggerMigration(from: LegacyPrefsBackend) -> Nil
    _ -> panic as "expected TriggerMigration(LegacyPrefsBackend)"
  }
}

pub fn vault_active_pi_only_triggers_migration_test() {
  case decide("k1", True, False, False, True, False) {
    TriggerMigration(from: PiJsonBackend) -> Nil
    _ -> panic as "expected TriggerMigration(PiJsonBackend)"
  }
}

pub fn vault_active_unknown_secret_rejects_fail_closed_test() {
  case decide("ghost_secret", True, False, False, False, False) {
    RejectFailClosed(reason: r) -> {
      case r {
        "secret unknown to all backends" -> Nil
        _ -> panic as "wrong reject reason"
      }
    }
    _ -> panic as "expected RejectFailClosed"
  }
}

// =====================================================================
// Vault sealed path — operator-gated legacy fallback
// =====================================================================

pub fn vault_sealed_with_legacy_and_fallback_allowed_uses_legacy_test() {
  case decide("k1", False, False, True, False, True) {
    UseLegacyWithGuard(reason: r) -> {
      case r {
        "vault sealed, legacy fallback gated" -> Nil
        _ -> panic as "wrong fallback reason"
      }
    }
    _ -> panic as "expected UseLegacyWithGuard"
  }
}

pub fn vault_sealed_no_legacy_rejects_fail_closed_test() {
  case decide("k1", False, False, False, False, True) {
    RejectFailClosed(_) -> Nil
    _ -> panic as "expected RejectFailClosed when vault sealed and no legacy"
  }
}

pub fn vault_sealed_legacy_forbidden_rejects_fail_closed_test() {
  case decide("k1", False, False, True, False, False) {
    RejectFailClosed(_) -> Nil
    _ -> panic as "expected RejectFailClosed when fallback forbidden"
  }
}

pub fn vault_sealed_pi_present_no_legacy_fallback_rejects_test() {
  // Pi-mono secrets are NOT a legacy fallback — they were the origin source.
  // When vault is sealed and pi is the only backend, must fail-closed.
  case decide("k1", False, False, False, True, True) {
    RejectFailClosed(_) -> Nil
    _ -> panic as "expected RejectFailClosed (Pi is not a legacy fallback)"
  }
}

// =====================================================================
// action_safety — dashboard color mapping
// =====================================================================

pub fn use_vault_is_green_test() {
  action_safety(UseVault) |> should.equal("green")
}

pub fn use_legacy_is_amber_test() {
  action_safety(UseLegacyWithGuard(reason: "x")) |> should.equal("amber")
}

pub fn trigger_migration_is_amber_test() {
  action_safety(TriggerMigration(from: LegacyPrefsBackend))
  |> should.equal("amber")
}

pub fn reject_fail_closed_is_red_test() {
  action_safety(RejectFailClosed(reason: "x")) |> should.equal("red")
}

// =====================================================================
// is_serving — audit accounting
// =====================================================================

pub fn use_vault_serves_test() {
  is_serving(UseVault) |> should.equal(True)
}

pub fn legacy_with_guard_serves_test() {
  is_serving(UseLegacyWithGuard(reason: "x")) |> should.equal(True)
}

pub fn trigger_migration_serves_test() {
  is_serving(TriggerMigration(from: LegacyPrefsBackend)) |> should.equal(True)
}

pub fn reject_fail_closed_does_not_serve_test() {
  is_serving(RejectFailClosed(reason: "x")) |> should.equal(False)
}

// =====================================================================
// Realistic operational scenarios
// =====================================================================

pub fn migrating_anthropic_key_during_pi_phaseout_test() {
  // After Pass-1 vendor + Pass-20 body wiring, anthropic_api_key is in vault
  // AND still in .pi/config.json. Vault active → use vault, ignore pi.
  decide("anthropic_api_key", True, True, False, True, True)
  |> should.equal(UseVault)
}

pub fn migrating_telegram_token_first_time_test() {
  // First use of telegram_token after vault unseal — still only in legacy prefs.
  case decide("telegram_token", True, False, True, False, False) {
    TriggerMigration(from: LegacyPrefsBackend) -> Nil
    _ -> panic as "expected migration trigger from legacy"
  }
}

pub fn vault_unseal_failed_at_boot_rejects_all_reads_test() {
  // SC-VAULT-001 fail-closed: even with legacy fallback enabled, if vault
  // failed to unseal we still reject — operator-gated only.
  case decide("k1", False, False, True, False, False) {
    RejectFailClosed(_) -> Nil
    _ -> panic as "expected hard reject under SC-VAULT-001"
  }
}

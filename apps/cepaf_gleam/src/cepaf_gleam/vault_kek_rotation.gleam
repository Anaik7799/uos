//// Vault KEK rotation policy — pure decision logic for the weekly Oban
//// schedule `vault_kek_rotation_check` (registered Pass-3, cron `0 3 * * 0`).
////
//// Slice C cross-cutting (Pass-31): given the current KEK age, last rotation
//// timestamp, policy threshold (per `secret_policy.RotationDays`), and vault
//// state, decide whether the operator MUST re-seal-tpm now.
////
//// Per .claude/rules/secrets-vault.md:
////   SC-VAULT-007: KEK chain attempts {TPM, passphrase, KMS} ordering
////   SC-VAULT-015: every KEK unseal logged to immutable register
////   SC-VAULT-023: re-seal-tpm CLI MUST be operator-gated (no automation)
////
//// Pure functions, no I/O. Tested against the same boundary table the
//// weekly cron uses to alert the dashboard.

// =====================================================================
// Types
// =====================================================================

/// Rotation urgency tier — drives dashboard color + RETE-UL salience.
pub type RotationDecision {
  /// KEK age well within rotation window. No action needed.
  NotDue
  /// KEK age ≥ 80% of rotation_days. Schedule re-seal in next maintenance window.
  DueSoon(days_remaining: Int)
  /// KEK age ≥ rotation_days. Operator MUST run re-seal-tpm at next opportunity.
  Overdue(days_overdue: Int)
  /// KEK age ≥ 2× rotation_days. P0 alarm; halt OODA until re-seal completes.
  Expired(days_overdue: Int)
  /// Vault sealed at decision time — rotation cannot proceed; report state.
  CannotRotate(reason: String)
}

/// Vault state subset relevant to rotation. Minimal to avoid coupling.
pub type VaultRotationState {
  ActiveState
  SealedState
  CorruptState
}

/// Inputs to the decision function. All times in seconds since epoch.
pub type RotationContext {
  RotationContext(
    current_ts: Int,
    last_rotation_ts: Int,
    rotation_days: Int,
    vault_state: VaultRotationState,
  )
}

// =====================================================================
// Public API
// =====================================================================

/// Pure decision: classify the current rotation status.
///
/// Boundary table:
///   vault_state == Corrupt              → CannotRotate("vault corrupt")
///   vault_state == Sealed               → CannotRotate("vault sealed at decision")
///   age < 0                             → NotDue (clock skew tolerance)
///   age < 0.8 × rotation_days           → NotDue
///   0.8 × rotation_days ≤ age < rotation_days
///                                       → DueSoon(remaining)
///   rotation_days ≤ age < 2 × rotation_days
///                                       → Overdue(over)
///   age ≥ 2 × rotation_days             → Expired(over)  (P0)
pub fn decide_rotation(ctx: RotationContext) -> RotationDecision {
  case ctx.vault_state {
    CorruptState -> CannotRotate(reason: "vault corrupt — rotation impossible")
    SealedState -> CannotRotate(reason: "vault sealed at decision")
    ActiveState -> classify_active(ctx)
  }
}

/// Drive dashboard color (matches Pass-15 freshness palette).
pub fn urgency_color(decision: RotationDecision) -> String {
  case decision {
    NotDue -> "green"
    DueSoon(_) -> "amber"
    Overdue(_) -> "amber"
    Expired(_) -> "red"
    CannotRotate(_) -> "red"
  }
}

/// True iff the decision is severe enough to halt OODA loops.
/// SC-VAULT-006 fail-closed parallel: any Expired or CannotRotate(corrupt) blocks.
pub fn is_blocking(decision: RotationDecision) -> Bool {
  case decision {
    Expired(_) -> True
    CannotRotate(_) -> True
    _ -> False
  }
}

/// Severity tier for SC-VAULT-016 cron alerting.
pub fn severity_tier(decision: RotationDecision) -> String {
  case decision {
    NotDue -> "NONE"
    DueSoon(_) -> "LOW"
    Overdue(_) -> "MEDIUM"
    Expired(_) -> "HIGH"
    CannotRotate(_) -> "HIGH"
  }
}

/// Convenience: True iff caller should propose a re-seal-tpm task.
pub fn should_propose_reseal(decision: RotationDecision) -> Bool {
  case decision {
    DueSoon(_) -> True
    Overdue(_) -> True
    Expired(_) -> True
    NotDue -> False
    CannotRotate(_) -> False
  }
}

// =====================================================================
// Internal — classify only when vault is Active
// =====================================================================

fn classify_active(ctx: RotationContext) -> RotationDecision {
  let raw_age_seconds = ctx.current_ts - ctx.last_rotation_ts
  let age_seconds = case raw_age_seconds < 0 {
    True -> 0
    False -> raw_age_seconds
  }
  let age_days = age_seconds / 86_400
  let rotation_days = ctx.rotation_days
  let due_soon_threshold = rotation_days * 4 / 5
  // floor of 0.8 × rotation_days

  case
    age_days >= rotation_days * 2,
    age_days >= rotation_days,
    age_days >= due_soon_threshold
  {
    True, _, _ -> Expired(days_overdue: age_days - rotation_days)
    False, True, _ -> Overdue(days_overdue: age_days - rotation_days)
    False, False, True -> DueSoon(days_remaining: rotation_days - age_days)
    False, False, False -> NotDue
  }
}

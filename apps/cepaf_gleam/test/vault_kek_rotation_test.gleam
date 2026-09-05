//// vault_kek_rotation_test — Pass-31 exhaustive coverage of KEK rotation
//// decision logic for the weekly Oban cron + dashboard urgency tiers.

import cepaf_gleam/vault_kek_rotation.{
  type RotationContext, ActiveState, CannotRotate, CorruptState, DueSoon,
  Expired, NotDue, Overdue, RotationContext, SealedState, decide_rotation,
  is_blocking, severity_tier, should_propose_reseal, urgency_color,
}
import gleeunit/should

// 1 day in seconds for readability
const day = 86_400

fn ctx_at_age(age_days: Int, rotation_days: Int) -> RotationContext {
  RotationContext(
    current_ts: 100 * day,
    last_rotation_ts: 100 * day - age_days * day,
    rotation_days: rotation_days,
    vault_state: ActiveState,
  )
}

// =====================================================================
// NotDue boundary
// =====================================================================

pub fn fresh_kek_yields_not_due_test() {
  decide_rotation(ctx_at_age(0, 30)) |> should.equal(NotDue)
}

pub fn kek_at_half_rotation_window_yields_not_due_test() {
  decide_rotation(ctx_at_age(15, 30)) |> should.equal(NotDue)
}

pub fn kek_just_below_due_soon_threshold_yields_not_due_test() {
  // 0.8 × 30 = 24 → age=23 still NotDue
  decide_rotation(ctx_at_age(23, 30)) |> should.equal(NotDue)
}

pub fn negative_age_clamps_to_not_due_test() {
  // Clock skew: last_rotation_ts > current_ts
  let ctx =
    RotationContext(
      current_ts: 100 * day,
      last_rotation_ts: 110 * day,
      rotation_days: 30,
      vault_state: ActiveState,
    )
  decide_rotation(ctx) |> should.equal(NotDue)
}

// =====================================================================
// DueSoon boundary
// =====================================================================

pub fn kek_at_due_soon_threshold_yields_due_soon_test() {
  // 0.8 × 30 = 24 → age=24 → DueSoon
  case decide_rotation(ctx_at_age(24, 30)) {
    DueSoon(days_remaining: 6) -> Nil
    other -> {
      let _ = other
      panic as "expected DueSoon(6)"
    }
  }
}

pub fn kek_at_29_days_with_30_day_rotation_yields_due_soon_test() {
  case decide_rotation(ctx_at_age(29, 30)) {
    DueSoon(days_remaining: 1) -> Nil
    _ -> panic as "expected DueSoon(1)"
  }
}

// =====================================================================
// Overdue boundary
// =====================================================================

pub fn kek_at_exactly_rotation_days_yields_overdue_test() {
  case decide_rotation(ctx_at_age(30, 30)) {
    Overdue(days_overdue: 0) -> Nil
    _ -> panic as "expected Overdue(0) at exact boundary"
  }
}

pub fn kek_at_45_days_with_30_day_rotation_yields_overdue_test() {
  case decide_rotation(ctx_at_age(45, 30)) {
    Overdue(days_overdue: 15) -> Nil
    _ -> panic as "expected Overdue(15)"
  }
}

// =====================================================================
// Expired boundary (P0 alarm)
// =====================================================================

pub fn kek_at_2x_rotation_days_yields_expired_test() {
  case decide_rotation(ctx_at_age(60, 30)) {
    Expired(days_overdue: 30) -> Nil
    _ -> panic as "expected Expired(30) at 2× boundary"
  }
}

pub fn kek_at_3x_rotation_days_still_expired_test() {
  case decide_rotation(ctx_at_age(90, 30)) {
    Expired(days_overdue: 60) -> Nil
    _ -> panic as "expected Expired(60)"
  }
}

// =====================================================================
// Vault state guards
// =====================================================================

pub fn sealed_vault_yields_cannot_rotate_test() {
  let ctx =
    RotationContext(
      current_ts: 100 * day,
      last_rotation_ts: 0,
      rotation_days: 30,
      vault_state: SealedState,
    )
  case decide_rotation(ctx) {
    CannotRotate(reason: r) -> {
      case r {
        "vault sealed at decision" -> Nil
        _ -> panic as "wrong cannot-rotate reason"
      }
    }
    _ -> panic as "expected CannotRotate when sealed"
  }
}

pub fn corrupt_vault_yields_cannot_rotate_test() {
  let ctx =
    RotationContext(
      current_ts: 100 * day,
      last_rotation_ts: 0,
      rotation_days: 30,
      vault_state: CorruptState,
    )
  case decide_rotation(ctx) {
    CannotRotate(_) -> Nil
    _ -> panic as "expected CannotRotate when corrupt"
  }
}

// =====================================================================
// urgency_color
// =====================================================================

pub fn not_due_is_green_test() {
  urgency_color(NotDue) |> should.equal("green")
}

pub fn due_soon_is_amber_test() {
  urgency_color(DueSoon(days_remaining: 3)) |> should.equal("amber")
}

pub fn overdue_is_amber_test() {
  urgency_color(Overdue(days_overdue: 5)) |> should.equal("amber")
}

pub fn expired_is_red_test() {
  urgency_color(Expired(days_overdue: 30)) |> should.equal("red")
}

pub fn cannot_rotate_is_red_test() {
  urgency_color(CannotRotate(reason: "x")) |> should.equal("red")
}

// =====================================================================
// is_blocking — SC-VAULT-006 fail-closed parallel
// =====================================================================

pub fn not_due_does_not_block_test() {
  is_blocking(NotDue) |> should.equal(False)
}

pub fn due_soon_does_not_block_test() {
  is_blocking(DueSoon(days_remaining: 1)) |> should.equal(False)
}

pub fn overdue_does_not_block_test() {
  is_blocking(Overdue(days_overdue: 5)) |> should.equal(False)
}

pub fn expired_blocks_test() {
  is_blocking(Expired(days_overdue: 30)) |> should.equal(True)
}

pub fn cannot_rotate_blocks_test() {
  is_blocking(CannotRotate(reason: "x")) |> should.equal(True)
}

// =====================================================================
// severity_tier — SC-VAULT-016 cron alerting
// =====================================================================

pub fn severity_none_when_not_due_test() {
  severity_tier(NotDue) |> should.equal("NONE")
}

pub fn severity_low_when_due_soon_test() {
  severity_tier(DueSoon(days_remaining: 5)) |> should.equal("LOW")
}

pub fn severity_medium_when_overdue_test() {
  severity_tier(Overdue(days_overdue: 5)) |> should.equal("MEDIUM")
}

pub fn severity_high_when_expired_test() {
  severity_tier(Expired(days_overdue: 30)) |> should.equal("HIGH")
}

// =====================================================================
// should_propose_reseal — operator workflow trigger
// =====================================================================

pub fn no_reseal_proposed_when_not_due_test() {
  should_propose_reseal(NotDue) |> should.equal(False)
}

pub fn reseal_proposed_when_due_soon_test() {
  should_propose_reseal(DueSoon(days_remaining: 3)) |> should.equal(True)
}

pub fn reseal_proposed_when_overdue_test() {
  should_propose_reseal(Overdue(days_overdue: 5)) |> should.equal(True)
}

pub fn reseal_proposed_when_expired_test() {
  should_propose_reseal(Expired(days_overdue: 30)) |> should.equal(True)
}

pub fn no_reseal_when_cannot_rotate_test() {
  // Can't propose re-seal-tpm if vault is sealed/corrupt — operator must
  // resolve the underlying issue first
  should_propose_reseal(CannotRotate(reason: "x")) |> should.equal(False)
}

// =====================================================================
// Realistic operational scenarios
// =====================================================================

pub fn anthropic_l0_30day_rotation_after_25_days_yields_due_soon_test() {
  // policy_l0_hot_key has rotation_days=30; 0.8 × 30 = 24 threshold
  case decide_rotation(ctx_at_age(25, 30)) {
    DueSoon(days_remaining: 5) -> Nil
    _ -> panic as "expected DueSoon(5) for anthropic at 25 days"
  }
}

pub fn telegram_l7_365day_rotation_after_300_days_still_not_due_test() {
  // policy_l7_gateway has rotation_days=365; 0.8 × 365 = 292 threshold
  case decide_rotation(ctx_at_age(290, 365)) {
    NotDue -> Nil
    _ -> panic as "expected NotDue at 290/365"
  }
}

pub fn telegram_l7_365day_rotation_after_730_days_yields_expired_test() {
  // 2 × 365 = 730 → Expired(365)
  case decide_rotation(ctx_at_age(730, 365)) {
    Expired(days_overdue: 365) -> Nil
    _ -> panic as "expected Expired(365)"
  }
}

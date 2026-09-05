//// vault_audit_reconcile_test — Pass-24 exhaustive coverage of the pure
//// reconcile() diff function used by the daily SC-VAULT-016 audit cron.

import cepaf_gleam/vault_audit_reconcile.{
  ActualPolicy, Drift, ExpectedPolicy, Missing, Orphan, highest_severity,
  is_clean, reconcile,
}
import gleeunit/should

// =====================================================================
// Happy path — exact match
// =====================================================================

pub fn matching_lists_yield_no_discrepancies_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  r.discrepancies |> should.equal([])
  r.matched_count |> should.equal(1)
  r.expected_count |> should.equal(1)
  r.actual_count |> should.equal(1)
}

pub fn empty_lists_yield_no_discrepancies_test() {
  let r = reconcile([], [])
  r.discrepancies |> should.equal([])
  r.matched_count |> should.equal(0)
}

pub fn is_clean_returns_true_on_empty_discrepancies_test() {
  let r = reconcile([], [])
  is_clean(r) |> should.equal(True)
}

// =====================================================================
// Missing — expected has row, actual doesn't
// =====================================================================

pub fn missing_secret_yields_missing_discrepancy_test() {
  let exp = [
    ExpectedPolicy(
      name: "anthropic_api_key",
      ttl: 300,
      max_ttl: 604_800,
      sensitivity: "L0",
    ),
    ExpectedPolicy(
      name: "telegram_token",
      ttl: 3600,
      max_ttl: 2_592_000,
      sensitivity: "L7",
    ),
  ]
  let act = [
    ActualPolicy(
      name: "anthropic_api_key",
      ttl: 300,
      max_ttl: 604_800,
      sensitivity: "L0",
    ),
  ]
  let r = reconcile(exp, act)
  case r.discrepancies {
    [Missing(name: "telegram_token")] -> Nil
    _ -> panic as "expected single Missing(telegram_token)"
  }
  r.matched_count |> should.equal(1)
}

// =====================================================================
// Orphan — actual has row, expected doesn't
// =====================================================================

pub fn orphan_row_yields_orphan_discrepancy_test() {
  let exp = []
  let act = [
    ActualPolicy(
      name: "old_legacy_key",
      ttl: 60,
      max_ttl: 600,
      sensitivity: "L3",
    ),
  ]
  let r = reconcile(exp, act)
  case r.discrepancies {
    [Orphan(name: "old_legacy_key")] -> Nil
    _ -> panic as "expected single Orphan(old_legacy_key)"
  }
}

// =====================================================================
// Drift — both sides have row but fields differ
// =====================================================================

pub fn ttl_drift_yields_drift_discrepancy_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 600, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  case r.discrepancies {
    [Drift(name: "k1", field: "ttl", expected: "300", actual: "600")] -> Nil
    _ -> panic as "expected single Drift on ttl field"
  }
  r.matched_count |> should.equal(0)
}

pub fn sensitivity_drift_yields_drift_discrepancy_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L7"),
  ]
  let r = reconcile(exp, act)
  case r.discrepancies {
    [Drift(name: "k1", field: "sensitivity", expected: "L0", actual: "L7")] ->
      Nil
    _ -> panic as "expected sensitivity drift"
  }
}

pub fn max_ttl_drift_yields_drift_discrepancy_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 300, max_ttl: 86_400, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  case r.discrepancies {
    [Drift(name: "k1", field: "max_ttl", ..)] -> Nil
    _ -> panic as "expected max_ttl drift"
  }
}

// =====================================================================
// Multi-field drift — single secret with both ttl AND sensitivity drift
// =====================================================================

pub fn multi_field_drift_yields_two_entries_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 604_800, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 600, max_ttl: 604_800, sensitivity: "L7"),
  ]
  let r = reconcile(exp, act)
  case r.discrepancies {
    [_, _] -> Nil
    _ -> panic as "expected exactly 2 drift entries"
  }
}

// =====================================================================
// Severity classification (SC-VAULT-016 alerting)
// =====================================================================

pub fn highest_severity_none_when_clean_test() {
  highest_severity(reconcile([], [])) |> should.equal("NONE")
}

pub fn highest_severity_high_on_missing_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L0"),
  ]
  let r = reconcile(exp, [])
  highest_severity(r) |> should.equal("HIGH")
}

pub fn highest_severity_high_on_orphan_test() {
  let act = [
    ActualPolicy(name: "old", ttl: 60, max_ttl: 600, sensitivity: "L0"),
  ]
  let r = reconcile([], act)
  highest_severity(r) |> should.equal("HIGH")
}

pub fn highest_severity_medium_on_drift_only_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 600, max_ttl: 600, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  highest_severity(r) |> should.equal("MEDIUM")
}

// =====================================================================
// Mixed scenarios — realistic operational cases
// =====================================================================

pub fn mixed_missing_and_drift_yields_high_severity_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L0"),
    ExpectedPolicy(name: "k2", ttl: 60, max_ttl: 86_400, sensitivity: "L3"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 600, max_ttl: 600, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  // 1 Missing(k2) + 1 Drift(k1, ttl) = 2 discrepancies, severity HIGH
  highest_severity(r) |> should.equal("HIGH")
  list_length(r.discrepancies) |> should.equal(2)
}

pub fn count_invariants_test() {
  let exp = [
    ExpectedPolicy(name: "a", ttl: 1, max_ttl: 10, sensitivity: "L0"),
    ExpectedPolicy(name: "b", ttl: 2, max_ttl: 20, sensitivity: "L3"),
    ExpectedPolicy(name: "c", ttl: 3, max_ttl: 30, sensitivity: "L7"),
  ]
  let act = [
    ActualPolicy(name: "a", ttl: 1, max_ttl: 10, sensitivity: "L0"),
    ActualPolicy(name: "b", ttl: 2, max_ttl: 20, sensitivity: "L3"),
    ActualPolicy(name: "z_orphan", ttl: 99, max_ttl: 999, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  r.expected_count |> should.equal(3)
  r.actual_count |> should.equal(3)
  r.matched_count |> should.equal(2)
  // Discrepancies: Missing(c) + Orphan(z_orphan)
  list_length(r.discrepancies) |> should.equal(2)
}

// =====================================================================
// Helpers
// =====================================================================

fn list_length(xs: List(a)) -> Int {
  do_length(xs, 0)
}

fn do_length(xs: List(a), acc: Int) -> Int {
  case xs {
    [] -> acc
    [_, ..tail] -> do_length(tail, acc + 1)
  }
}

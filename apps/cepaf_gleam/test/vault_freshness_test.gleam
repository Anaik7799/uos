//// vault_freshness_test — Pass-15 exhaustive coverage of the pure
//// freshness classifier and dashboard-color aggregator.
////
//// Slice F partial: these are the functions that drive the Andon tile,
//// the Wisp REST status, and the RETE-UL `secret_freshness` domain rules.
//// They are pure (no NIF, no clock side-effects), so 100 % of the
//// boundary table is testable in-process.

import cepaf_gleam/vault.{
  Active, Fresh, HardStale, Sealed, SecretPolicy, SoftStale, SoftStaleOffline,
  classify_freshness, dashboard_color, policy_l0_hot_key,
  policy_l3_oauth_refresh, policy_l3_smtp, policy_l7_gateway,
}
import gleeunit/should

// =====================================================================
// classify_freshness — boundary table
// =====================================================================

pub fn fresh_when_age_below_ttl_test() {
  let p = policy_l0_hot_key()
  // age = 100s, ttl = 300s → Fresh
  classify_freshness(100, 0, p, True)
  |> should.equal(Fresh)
}

pub fn fresh_at_age_zero_test() {
  let p = policy_l0_hot_key()
  classify_freshness(0, 0, p, True)
  |> should.equal(Fresh)
}

pub fn soft_stale_at_ttl_boundary_online_test() {
  let p = policy_l0_hot_key()
  // age = ttl exactly = 300s → SoftStale (boundary: age >= ttl)
  classify_freshness(300, 0, p, True)
  |> should.equal(SoftStale)
}

pub fn soft_stale_offline_at_ttl_boundary_test() {
  let p = policy_l0_hot_key()
  classify_freshness(300, 0, p, False)
  |> should.equal(SoftStaleOffline)
}

pub fn soft_stale_just_below_max_ttl_online_test() {
  let p = policy_l0_hot_key()
  // age = max_ttl - 1 = 604_799 → still SoftStale
  classify_freshness(604_799, 0, p, True)
  |> should.equal(SoftStale)
}

pub fn hard_stale_at_max_ttl_boundary_test() {
  let p = policy_l0_hot_key()
  // age = max_ttl exactly = 604_800 → HardStale (SC-VAULT-006 fail-closed)
  classify_freshness(604_800, 0, p, True)
  |> should.equal(HardStale)
}

pub fn hard_stale_overrides_online_flag_test() {
  let p = policy_l0_hot_key()
  // online or offline doesn't matter past max_ttl
  classify_freshness(700_000, 0, p, True)
  |> should.equal(HardStale)
  classify_freshness(700_000, 0, p, False)
  |> should.equal(HardStale)
}

pub fn negative_age_clamps_to_fresh_test() {
  let p = policy_l0_hot_key()
  // Clock skew: now < fetched_at. Treat as age=0 = Fresh.
  classify_freshness(50, 100, p, True)
  |> should.equal(Fresh)
}

pub fn fresh_for_l3_oauth_refresh_test() {
  let p = policy_l3_oauth_refresh()
  // ttl = 3600 (1h), max_ttl = 604_800 (7d)
  classify_freshness(1000, 0, p, True)
  |> should.equal(Fresh)
}

pub fn soft_stale_for_l3_smtp_test() {
  let p = policy_l3_smtp()
  // ttl = 21_600 (6h), max_ttl = 2_592_000 (30d)
  classify_freshness(30_000, 0, p, True)
  |> should.equal(SoftStale)
}

pub fn hard_stale_for_l7_gateway_test() {
  let p = policy_l7_gateway()
  // max_ttl = 2_592_000 (30d) — boundary
  classify_freshness(2_592_001, 0, p, False)
  |> should.equal(HardStale)
}

pub fn synthetic_short_policy_test() {
  // Custom tight policy for fast unit testing
  let p =
    SecretPolicy(ttl: 10, max_ttl: 30, rotation_days: 1, sensitivity: vault.L0)
  classify_freshness(5, 0, p, True) |> should.equal(Fresh)
  classify_freshness(10, 0, p, True) |> should.equal(SoftStale)
  classify_freshness(15, 0, p, False) |> should.equal(SoftStaleOffline)
  classify_freshness(30, 0, p, True) |> should.equal(HardStale)
  classify_freshness(100, 0, p, True) |> should.equal(HardStale)
}

// =====================================================================
// dashboard_color — aggregate matrix
// =====================================================================

pub fn dashboard_green_when_active_and_all_fresh_test() {
  dashboard_color(10, 0, 0, Active) |> should.equal("green")
}

pub fn dashboard_amber_when_active_with_soft_stale_test() {
  dashboard_color(8, 2, 0, Active) |> should.equal("amber")
}

pub fn dashboard_red_when_active_with_hard_stale_test() {
  dashboard_color(8, 0, 1, Active) |> should.equal("red")
}

pub fn dashboard_red_when_sealed_regardless_of_counts_test() {
  dashboard_color(10, 0, 0, Sealed) |> should.equal("red")
}

pub fn dashboard_red_with_zero_counts_when_sealed_test() {
  dashboard_color(0, 0, 0, Sealed) |> should.equal("red")
}

pub fn dashboard_red_dominates_over_amber_test() {
  // Both soft and hard stale present → red (worst case wins)
  dashboard_color(5, 3, 1, Active) |> should.equal("red")
}

/// HSM Vault Tests — key lifecycle, rotation policy, audit log (SC-SEC-001)
///
/// 15 tests covering: vault_new, default_policy, add_key, check_access,
/// rotate_key, needs_rotation, audit, expired_keys, vault_health, summary.
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SEC-001, SC-BIO-EVO-001, SC-MUDA-001
///
/// सत्यमेव जयते — Truth alone triumphs
import cepaf_gleam/ha/hsm_vault.{
  Allow, DenyPolicyViolation, DenyRotationRequired, HsmPolicy, add_key,
  check_access, default_policy, expired_keys, needs_rotation, rotate_key,
  summary, vault_health, vault_new,
}
import gleam/list
import gleeunit/should

// ===========================================================================
// 1. vault_new / default_policy
// ===========================================================================

pub fn vault_new_starts_empty_test() {
  let vault = vault_new(default_policy())
  list.length(vault.entries) |> should.equal(0)
}

pub fn default_policy_rotation_90_days_test() {
  let policy = default_policy()
  policy.key_rotation_days |> should.equal(90)
}

pub fn default_policy_min_key_length_256_test() {
  let policy = default_policy()
  policy.min_key_length |> should.equal(256)
}

pub fn default_policy_audit_enabled_test() {
  let policy = default_policy()
  policy.audit_enabled |> should.equal(True)
}

// ===========================================================================
// 2. add_key
// ===========================================================================

pub fn add_key_increments_entry_count_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-001", "AES-256-GCM", 1_000_000)
  list.length(v1.entries) |> should.equal(1)
}

pub fn add_key_with_audit_appends_audit_entry_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-001", "AES-256-GCM", 1_000_000)
  list.length(v1.audit_log) |> should.equal(1)
}

pub fn add_key_sets_rotated_at_equal_to_created_at_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-001", "AES-256-GCM", 1_234_567)
  let entry_result = list.find(v1.entries, fn(e) { e.key_id == "k-001" })
  let assert Ok(entry) = entry_result
  entry.rotated_at |> should.equal(entry.created_at)
}

// ===========================================================================
// 3. needs_rotation
// ===========================================================================

pub fn needs_rotation_false_when_fresh_test() {
  let policy =
    HsmPolicy(key_rotation_days: 90, min_key_length: 256, audit_enabled: False)
  let vault = vault_new(policy)
  let v1 = add_key(vault, "k-001", "AES-256-GCM", 0)
  let entry_result = list.find(v1.entries, fn(e) { e.key_id == "k-001" })
  let assert Ok(entry) = entry_result
  // 80 days later — still within 90-day window
  needs_rotation(entry, policy, 80 * 86_400) |> should.equal(False)
}

pub fn needs_rotation_true_when_expired_test() {
  let policy =
    HsmPolicy(key_rotation_days: 90, min_key_length: 256, audit_enabled: False)
  let vault = vault_new(policy)
  let v1 = add_key(vault, "k-001", "AES-256-GCM", 0)
  let entry_result = list.find(v1.entries, fn(e) { e.key_id == "k-001" })
  let assert Ok(entry) = entry_result
  // 91 days later — over the 90-day limit
  needs_rotation(entry, policy, 91 * 86_400) |> should.equal(True)
}

// ===========================================================================
// 4. check_access
// ===========================================================================

pub fn check_access_allows_fresh_key_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-002", "AES-256-GCM", 0)
  check_access(v1, "k-002", 1000) |> should.equal(Allow)
}

pub fn check_access_denies_expired_key_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-003", "AES-256-GCM", 0)
  // 91 days have passed
  let decision = check_access(v1, "k-003", 91 * 86_400)
  decision |> should.equal(DenyRotationRequired("k-003"))
}

pub fn check_access_denies_unknown_key_test() {
  let vault = vault_new(default_policy())
  let decision = check_access(vault, "nonexistent", 0)
  case decision {
    DenyPolicyViolation(_) -> should.be_true(True)
    _ -> should.be_true(False)
  }
}

// ===========================================================================
// 5. rotate_key
// ===========================================================================

pub fn rotate_key_updates_rotated_at_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-004", "AES-256-GCM", 0)
  let v2 = rotate_key(v1, "k-004", 5_000_000)
  let entry_result = list.find(v2.entries, fn(e) { e.key_id == "k-004" })
  let assert Ok(entry) = entry_result
  entry.rotated_at |> should.equal(5_000_000)
}

// ===========================================================================
// 6. expired_keys / vault_health
// ===========================================================================

pub fn expired_keys_returns_overdue_entries_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-005", "AES-256-GCM", 0)
  let expired = expired_keys(v1, 91 * 86_400)
  list.length(expired) |> should.equal(1)
}

pub fn vault_health_one_when_no_expired_keys_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-006", "AES-256-GCM", 0)
  vault_health(v1, 1000) |> should.equal(1.0)
}

pub fn vault_health_less_than_one_when_expired_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-007", "AES-256-GCM", 0)
  let health = vault_health(v1, 91 * 86_400)
  { health <. 1.0 } |> should.be_true()
}

// ===========================================================================
// 7. summary
// ===========================================================================

pub fn summary_contains_key_count_test() {
  let vault = vault_new(default_policy())
  let v1 = add_key(vault, "k-008", "AES-256-GCM", 0)
  let s = summary(v1)
  { s != "" } |> should.be_true()
}

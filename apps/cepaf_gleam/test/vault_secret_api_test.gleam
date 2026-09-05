//// vault_secret_api_test — Pass-25 coverage of the Wisp REST surface
//// for vault status + policy audit.
////
//// SC-VAULT-003 mandates all secret reads through vault.gleam typed wrapper;
//// this test module verifies the JSON envelopes returned by Wisp endpoints
//// are well-formed and reflect the underlying ReconcileResult / freshness
//// counts correctly.

import cepaf_gleam/ui/wisp/secret_api.{
  policy_audit_json, secret_status_summary_json,
}
import cepaf_gleam/vault_audit_reconcile.{
  ActualPolicy, ExpectedPolicy, reconcile,
}
import gleam/string
import gleeunit/should

// =====================================================================
// secret_status_summary_json — Andon dashboard payload
// =====================================================================

pub fn status_summary_json_includes_dashboard_color_test() {
  let body =
    secret_status_summary_json(8, 0, 0, [#("k1", "fresh")], "Active", 12)
  string.contains(body, "\"dashboard_color\":\"green\"") |> should.equal(True)
  string.contains(body, "\"vault_state\":\"Active\"") |> should.equal(True)
  string.contains(body, "\"last_sync_age_seconds\":12") |> should.equal(True)
}

pub fn status_summary_amber_when_soft_stale_present_test() {
  let body = secret_status_summary_json(8, 2, 0, [], "Active", 5)
  string.contains(body, "\"dashboard_color\":\"amber\"") |> should.equal(True)
}

pub fn status_summary_red_when_hard_stale_present_test() {
  let body = secret_status_summary_json(8, 0, 1, [], "Active", 5)
  string.contains(body, "\"dashboard_color\":\"red\"") |> should.equal(True)
}

pub fn status_summary_red_when_sealed_test() {
  let body = secret_status_summary_json(0, 0, 0, [], "Sealed", 0)
  string.contains(body, "\"dashboard_color\":\"red\"") |> should.equal(True)
}

pub fn status_summary_includes_per_secret_array_test() {
  let body =
    secret_status_summary_json(
      2,
      0,
      0,
      [#("anthropic_api_key", "fresh"), #("telegram_token", "fresh")],
      "Active",
      1,
    )
  string.contains(body, "\"name\":\"anthropic_api_key\"") |> should.equal(True)
  string.contains(body, "\"name\":\"telegram_token\"") |> should.equal(True)
}

// =====================================================================
// policy_audit_json — Pass-25 NEW endpoint
// =====================================================================

pub fn policy_audit_clean_returns_severity_none_test() {
  let r = reconcile([], [])
  let body = policy_audit_json(r)
  string.contains(body, "\"severity\":\"NONE\"") |> should.equal(True)
  string.contains(body, "\"discrepancies\":[]") |> should.equal(True)
}

pub fn policy_audit_with_missing_returns_severity_high_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L0"),
  ]
  let r = reconcile(exp, [])
  let body = policy_audit_json(r)
  string.contains(body, "\"severity\":\"HIGH\"") |> should.equal(True)
  string.contains(body, "\"kind\":\"missing\"") |> should.equal(True)
  string.contains(body, "\"name\":\"k1\"") |> should.equal(True)
}

pub fn policy_audit_with_orphan_returns_severity_high_test() {
  let act = [
    ActualPolicy(name: "old_legacy", ttl: 60, max_ttl: 600, sensitivity: "L3"),
  ]
  let r = reconcile([], act)
  let body = policy_audit_json(r)
  string.contains(body, "\"severity\":\"HIGH\"") |> should.equal(True)
  string.contains(body, "\"kind\":\"orphan\"") |> should.equal(True)
  string.contains(body, "\"name\":\"old_legacy\"") |> should.equal(True)
}

pub fn policy_audit_with_drift_only_returns_severity_medium_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 600, max_ttl: 600, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  let body = policy_audit_json(r)
  string.contains(body, "\"severity\":\"MEDIUM\"") |> should.equal(True)
  string.contains(body, "\"kind\":\"drift\"") |> should.equal(True)
  string.contains(body, "\"field\":\"ttl\"") |> should.equal(True)
}

pub fn policy_audit_includes_count_fields_test() {
  let exp = [
    ExpectedPolicy(name: "a", ttl: 1, max_ttl: 10, sensitivity: "L0"),
    ExpectedPolicy(name: "b", ttl: 2, max_ttl: 20, sensitivity: "L3"),
  ]
  let act = [
    ActualPolicy(name: "a", ttl: 1, max_ttl: 10, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  let body = policy_audit_json(r)
  string.contains(body, "\"expected_count\":2") |> should.equal(True)
  string.contains(body, "\"actual_count\":1") |> should.equal(True)
  string.contains(body, "\"matched_count\":1") |> should.equal(True)
}

pub fn policy_audit_drift_includes_field_expected_actual_test() {
  let exp = [
    ExpectedPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L0"),
  ]
  let act = [
    ActualPolicy(name: "k1", ttl: 300, max_ttl: 600, sensitivity: "L7"),
  ]
  let r = reconcile(exp, act)
  let body = policy_audit_json(r)
  string.contains(body, "\"field\":\"sensitivity\"") |> should.equal(True)
  string.contains(body, "\"expected\":\"L0\"") |> should.equal(True)
  string.contains(body, "\"actual\":\"L7\"") |> should.equal(True)
}

pub fn policy_audit_emits_valid_json_array_for_multiple_discrepancies_test() {
  let exp = [
    ExpectedPolicy(name: "missing_one", ttl: 1, max_ttl: 10, sensitivity: "L0"),
    ExpectedPolicy(name: "drifted_one", ttl: 5, max_ttl: 50, sensitivity: "L3"),
  ]
  let act = [
    ActualPolicy(name: "drifted_one", ttl: 99, max_ttl: 50, sensitivity: "L3"),
    ActualPolicy(name: "orphan_one", ttl: 1, max_ttl: 10, sensitivity: "L0"),
  ]
  let r = reconcile(exp, act)
  let body = policy_audit_json(r)
  // 1 Missing + 1 Drift + 1 Orphan = HIGH severity
  string.contains(body, "\"severity\":\"HIGH\"") |> should.equal(True)
  string.contains(body, "\"kind\":\"missing\"") |> should.equal(True)
  string.contains(body, "\"kind\":\"drift\"") |> should.equal(True)
  string.contains(body, "\"kind\":\"orphan\"") |> should.equal(True)
}

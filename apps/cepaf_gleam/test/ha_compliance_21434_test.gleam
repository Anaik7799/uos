/// ISO 21434 Compliance Tests — automotive cybersecurity audit (SC-SEC-001)
///
/// 15 tests covering: run_audit, pii_checks, crypto_checks, access_checks,
/// network_checks, compliance_score, is_compliant, threat_catalog, summary.
///
/// Layer: L0_CONSTITUTIONAL
/// STAMP: SC-SEC-001, SC-BIO-EVO-001, SC-MUDA-001
///
/// सत्यमेव जयते — Truth alone triumphs
import cepaf_gleam/ha/compliance_21434.{
  ComplianceCheck, access_checks, compliance_score, crypto_checks, is_compliant,
  network_checks, pii_checks, run_audit, run_audit_at, summary, threat_catalog,
}
import gleam/list
import gleeunit/should

// ===========================================================================
// 1. Check builders — correct counts
// ===========================================================================

pub fn pii_checks_returns_three_checks_test() {
  list.length(pii_checks()) |> should.equal(3)
}

pub fn crypto_checks_returns_three_checks_test() {
  list.length(crypto_checks()) |> should.equal(3)
}

pub fn access_checks_returns_three_checks_test() {
  list.length(access_checks()) |> should.equal(3)
}

pub fn network_checks_returns_three_checks_test() {
  list.length(network_checks()) |> should.equal(3)
}

// ===========================================================================
// 2. compliance_score
// ===========================================================================

pub fn compliance_score_all_passed_is_one_test() {
  let checks = pii_checks()
  compliance_score(checks) |> should.equal(1.0)
}

pub fn compliance_score_empty_list_is_zero_test() {
  compliance_score([]) |> should.equal(0.0)
}

pub fn compliance_score_partial_is_fractional_test() {
  // Build a list with one failing check to get a partial score
  let failing =
    ComplianceCheck(
      id: "TEST-FAIL",
      name: "deliberate failure",
      category: "test",
      passed: False,
      evidence: "none",
    )
  let passing =
    ComplianceCheck(
      id: "TEST-PASS",
      name: "deliberate pass",
      category: "test",
      passed: True,
      evidence: "ok",
    )
  let score = compliance_score([failing, passing])
  { score <. 1.0 } |> should.be_true()
  { score >. 0.0 } |> should.be_true()
}

// ===========================================================================
// 3. run_audit
// ===========================================================================

pub fn run_audit_returns_twelve_checks_test() {
  let report = run_audit()
  list.length(report.checks) |> should.equal(12)
}

pub fn run_audit_is_compliant_test() {
  let report = run_audit()
  report.compliant |> should.equal(True)
}

pub fn run_audit_score_is_one_test() {
  let report = run_audit()
  report.score |> should.equal(1.0)
}

pub fn run_audit_at_captures_timestamp_test() {
  let report = run_audit_at(9_999_999)
  report.timestamp |> should.equal(9_999_999)
}

// ===========================================================================
// 4. is_compliant
// ===========================================================================

pub fn is_compliant_true_for_full_report_test() {
  let report = run_audit()
  is_compliant(report) |> should.equal(True)
}

// ===========================================================================
// 5. threat_catalog
// ===========================================================================

pub fn threat_catalog_has_eight_threats_test() {
  list.length(threat_catalog()) |> should.equal(8)
}

pub fn threat_catalog_first_threat_is_ota_rce_test() {
  let catalog = threat_catalog()
  let assert Ok(first) = list.first(catalog)
  first.id |> should.equal("T-001")
}

pub fn threat_catalog_all_have_risk_level_above_zero_test() {
  let catalog = threat_catalog()
  let all_positive = list.all(catalog, fn(t) { t.risk_level > 0 })
  all_positive |> should.be_true()
}

// ===========================================================================
// 6. summary
// ===========================================================================

pub fn summary_is_non_empty_string_test() {
  let report = run_audit()
  let s = summary(report)
  { s != "" } |> should.be_true()
}

pub fn summary_contains_compliant_label_test() {
  let report = run_audit()
  let s = summary(report)
  s |> should.equal("ISO 21434 Audit: COMPLIANT | checks=12/12 | score=100%")
}

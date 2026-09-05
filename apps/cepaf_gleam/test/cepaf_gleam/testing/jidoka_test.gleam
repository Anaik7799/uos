//// [C3I-SIL6-MSTS] Recursive TDG for Jidoka Plane
//// STAMP: SC-JIDOKA-001, SC-VER-001

import cepaf_gleam/testing/jidoka.{ValidationIssue}
import gleeunit/should

pub fn jidoka_halt_on_critical_test() {
  let issues = [
    ValidationIssue("SC-CU-001", "CRITICAL", "Arbitrary code on host detected"),
    ValidationIssue("SC-OTEL-001", "INFO", "Span latency normal"),
  ]

  jidoka.halt_on_error(issues)
  |> should.be_error()
}

pub fn jidoka_pass_on_non_critical_test() {
  let issues = [
    ValidationIssue("SC-OTEL-001", "INFO", "Span latency normal"),
    ValidationIssue("SC-QUA-001", "WARNING", "Coverage at 94%"),
  ]

  jidoka.halt_on_error(issues)
  |> should.be_ok()
}

pub fn verify_stamp_compliance_stub_test() {
  jidoka.verify_stamp_compliance("SC-SIL6-001")
  |> should.be_true()
}

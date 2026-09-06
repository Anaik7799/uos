import cepaf_gleam/ui/lustre/ux_dx_cx_auditor
import gleeunit/should

pub fn wcag_contrast_threshold_test() {
  let audit = ux_dx_cx_auditor.build_canonical_audit()
  should.be_true(audit.contrast_ratio >=. 7.0)
  // Level AAA
}

pub fn core_web_vitals_threshold_test() {
  let audit = ux_dx_cx_auditor.build_canonical_audit()
  should.be_true(audit.lcp_seconds <=. 2.5)
  should.be_true(audit.inp_ms <= 200)
  should.be_true(audit.cls_score <=. 0.1)
}

pub fn dx_developer_metrics_test() {
  let audit = ux_dx_cx_auditor.build_canonical_audit()
  should.equal(audit.compiler_warnings, 0)
  should.be_true(audit.compile_time_seconds <=. 2.0)
}

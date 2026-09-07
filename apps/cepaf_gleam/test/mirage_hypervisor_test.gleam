import cepaf_gleam/services/mirage_hypervisor as hyp
import gleam/option.{None}
import gleeunit/should

pub fn default_verified_probe_invariants_test() {
  let probe = hyp.default_verified_probe()
  should.equal(probe.schema, "uos-mirage-hypervisor-probe/v1")
  should.equal(
    probe.overall_readiness,
    "solo5_hardware_virtualized_and_spt_verified",
  )
  should.equal(
    probe.execution_policy,
    "two_key_receipt_required_before_admission",
  )
  should.equal(
    probe.deployment_admission,
    "TENDERS_VERIFIED_PHYSICAL_EXECUTION",
  )
  should.equal(probe.kvm.dev_kvm_present, True)
  should.equal(probe.kvm.dev_kvm_rw_accessible, True)
  should.equal(probe.qemu.microvm_supported, True)
  should.equal(probe.qemu.kvm_accel_supported, True)
  should.be_some(probe.solo5.solo5_hvt_path)
  should.be_some(probe.solo5.solo5_spt_path)
  should.be_some(probe.solo5.solo5_virtio_path)
  should.be_some(probe.solo5.hvt_execution)
  should.be_some(probe.solo5.spt_execution)
  should.be_some(probe.solo5.virtio_execution)

  let json = hyp.probe_report_to_json(probe)
  should.be_ok(Ok(json))
}

pub fn validate_probe_report_positive_test() {
  let probe = hyp.default_verified_probe()
  should.be_ok(hyp.validate_probe_report(probe))
}

pub fn validate_probe_report_stale_timestamp_negative_test() {
  let probe =
    hyp.HypervisorProbeReport(..hyp.default_verified_probe(), timestamp_utc: "2000-01-01T00:00:00Z")
  should.be_error(hyp.validate_probe_report(probe))
}

pub fn validate_probe_report_wrong_host_negative_test() {
  let probe =
    hyp.HypervisorProbeReport(..hyp.default_verified_probe(), host: "untrusted-external-host")
  should.be_error(hyp.validate_probe_report(probe))
}

pub fn validate_probe_report_kvm_false_negative_test() {
  let probe =
    hyp.HypervisorProbeReport(
      ..hyp.default_verified_probe(),
      kvm: hyp.KvmStatus(..hyp.default_verified_probe().kvm, dev_kvm_present: False),
    )
  should.be_error(hyp.validate_probe_report(probe))
}

pub fn validate_probe_report_failed_tender_negative_test() {
  let probe =
    hyp.HypervisorProbeReport(
      ..hyp.default_verified_probe(),
      solo5: hyp.Solo5Status(..hyp.default_verified_probe().solo5, hvt_execution: None),
    )
  should.be_error(hyp.validate_probe_report(probe))
}

pub fn unverified_probe_invariants_test() {
  let unverified = hyp.unverified_probe()
  should.equal(unverified.deployment_admission, "NOT_VERIFIED")
  should.equal(unverified.overall_readiness, "unverified")
  should.be_error(hyp.validate_probe_report(unverified))
}


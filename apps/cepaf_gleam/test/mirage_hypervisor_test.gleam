import cepaf_gleam/services/mirage_hypervisor as hyp
import gleeunit/should

pub fn default_verified_probe_invariants_test() {
  let probe = hyp.default_verified_probe()
  should.equal(probe.schema, "uos-mirage-hypervisor-probe/v1")
  should.equal(probe.overall_readiness, "hardware_kvm_ready")
  should.equal(probe.execution_policy, "two_key_receipt_required_before_admission")
  should.equal(probe.deployment_admission, "NOT_VERIFIED")
  should.equal(probe.kvm.dev_kvm_present, True)
  should.equal(probe.kvm.dev_kvm_rw_accessible, True)
  should.equal(probe.qemu.microvm_supported, True)
  should.equal(probe.qemu.kvm_accel_supported, True)

  let json = hyp.probe_report_to_json(probe)
  should.be_ok(Ok(json))
}

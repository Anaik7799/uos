import cepaf_gleam/services/mirage_hypervisor as hyp
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

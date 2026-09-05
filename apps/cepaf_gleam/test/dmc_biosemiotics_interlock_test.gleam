import cepaf_gleam/verification/dmc_biosemiotics_interlock.{
  AccessDenied, AccessGranted, RochaConflated, RochaDecoupled, Tcm13DCoordinates,
  check_hardware_safety_interlock, verify_coordinate_conservation,
  verify_rocha_cut,
}
import gleeunit/should

pub fn rocha_biosemiotics_cut_test() {
  let status = verify_rocha_cut(True)
  should.equal(status, RochaDecoupled)

  let status_conflated = verify_rocha_cut(False)
  should.equal(status_conflated, RochaConflated)
}

pub fn coordinate_conservation_test() {
  let t0 =
    Tcm13DCoordinates(
      layer: 4,
      domain: "Verification",
      authority: "A0_reference",
      trust_indicator: 1,
    )
  let t1 =
    Tcm13DCoordinates(
      layer: 4,
      domain: "Verification",
      authority: "A0_reference",
      trust_indicator: 1,
    )
  let t2 =
    Tcm13DCoordinates(
      layer: 5,
      domain: "Verification",
      authority: "A0_reference",
      trust_indicator: 1,
    )
  should.equal(verify_coordinate_conservation(t0, t1), True)
  should.equal(verify_coordinate_conservation(t0, t2), False)
}

pub fn hardware_drive_interlock_blocked_test() {
  let serial = "25503L801736"
  let verdict = check_hardware_safety_interlock(serial)
  should.equal(verdict, AccessDenied("OS NVMe 25503L801736 is locked"))
}

pub fn hardware_drive_interlock_allowed_test() {
  let serial = "SAFE_DATA_NVME_9999"
  let verdict = check_hardware_safety_interlock(serial)
  should.equal(verdict, AccessGranted)
}

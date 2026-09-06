//// =============================================================================
//// [UOS-FPP-DMC-TCM-TEST] F Prime DMC + TCM Mathematical Verification Suite
//// =============================================================================
//// Formally tests the DMC + TCM invariants for F Prime on BEAM:
//// 1. Memory window disjointness proof (non-overlapping base ID intervals)
//// 2. Rocha biosemiotics symbol-matter cut preservation
//// 3. Single-writer exclusive lease acquisition & release semantics
//// 4. TCM 13-Dimensional coordinate conservation (Delta T_13 = 0)
//// 5. Hardware storage safety interlock on OS NVMe 25503L801736
//// =============================================================================

import cepaf_gleam/fpp/dmc_tcm.{
  HardDeniedSerialBlocked, RochaCutPreserved, RochaCutViolated,
  SafeOperationApproved, WriterLease, acquire_writer_lease,
  canonical_fpp_tcm_vector, check_fpp_hardware_safety_interlock,
  format_microsecond_utc, hard_denied_system_os_serial, release_writer_lease,
  verify_memory_window_disjointness, verify_rocha_biosemiotic_cut,
  verify_tcm_13d_conservation,
}
import cepaf_gleam/fpp/domain.{Instance}
import cepaf_gleam/fpp/topology.{canonical_harness_model}
import gleam/option.{None}
import gleam/string
import gleeunit/should

// ------------------------------------------------------------- 1. DMC Windows

pub fn fpp_dmc_memory_window_disjointness_test() {
  let model = canonical_harness_model()
  let report = verify_memory_window_disjointness(model)

  report.disjoint |> should.be_true
  report.violations |> should.equal([])
  report.total_instances |> should.equal(7)
}

pub fn fpp_dmc_memory_window_collision_detection_test() {
  let model = canonical_harness_model()
  // Add overlapping instance at 0x602 (collides with evidence_store at 0x600 span 10)
  let colliding_inst =
    Instance("evidence_store_dup", "evidence_store", 0x602, None, None, None, None)
  let bad_model =
    domain.Model(..model, instances: [colliding_inst, ..model.instances])

  let report = verify_memory_window_disjointness(bad_model)
  report.disjoint |> should.be_false
  { report.violations != [] } |> should.be_true
}

// ----------------------------------------------------------- 2. Rocha Cut

pub fn fpp_dmc_rocha_biosemiotic_cut_test() {
  // Raw uninterpreted bytes cannot directly actuate
  let raw_blocked = verify_rocha_biosemiotic_cut(True, False, True)
  case raw_blocked {
    RochaCutViolated(_) -> True |> should.be_true
    RochaCutPreserved -> False |> should.be_true
  }

  // Interpreted and authorized command preserves the cut
  let approved = verify_rocha_biosemiotic_cut(False, True, True)
  approved |> should.equal(RochaCutPreserved)

  // Unauthorized command fails
  let unauth = verify_rocha_biosemiotic_cut(False, True, False)
  case unauth {
    RochaCutViolated(_) -> True |> should.be_true
    RochaCutPreserved -> False |> should.be_true
  }
}

// -------------------------------------------------- 3. Single-Writer Lease

pub fn fpp_dmc_writer_lease_lifecycle_test() {
  let initial =
    WriterLease(
      resource_id: "prm:harness_config",
      holder: "",
      epoch: 0,
      active: False,
    )

  // Holder 1 acquires
  let acq1 = acquire_writer_lease(initial, "actor_1")
  acq1 |> should.be_ok
  let assert Ok(l1) = acq1
  l1.holder |> should.equal("actor_1")
  l1.active |> should.be_true
  l1.epoch |> should.equal(1)

  // Re-acquire by same holder succeeds
  let re_acq = acquire_writer_lease(l1, "actor_1")
  re_acq |> should.be_ok
  let assert Ok(l2) = re_acq
  l2.epoch |> should.equal(2)

  // Conflicting acquire by actor_2 fails
  let conflict = acquire_writer_lease(l2, "actor_2")
  conflict |> should.be_error

  // Release by wrong actor fails
  let bad_rel = release_writer_lease(l2, "actor_2")
  bad_rel |> should.be_error

  // Release by owner succeeds
  let good_rel = release_writer_lease(l2, "actor_1")
  good_rel |> should.be_ok
  let assert Ok(l3) = good_rel
  l3.active |> should.be_false

  // Now actor_2 can acquire
  let acq2 = acquire_writer_lease(l3, "actor_2")
  acq2 |> should.be_ok
}

// --------------------------------------------------------- 4. TCM 13D Vector

pub fn fpp_tcm_13d_conservation_test() {
  let t0 = canonical_fpp_tcm_vector("evidence_store", 1)
  let t1 = canonical_fpp_tcm_vector("evidence_store", 2)

  let conserved = verify_tcm_13d_conservation(t0, t1)
  conserved |> should.be_true

  // Broken trust fails closed
  let t1_bad = dmc_tcm.Tcm13DVector(..t1, trust_indicator: 0)
  verify_tcm_13d_conservation(t0, t1_bad) |> should.be_false
}

pub fn fpp_tcm_timestamp_microsecond_test() {
  let ts = format_microsecond_utc(1_788_679_400_123)
  ts |> string.ends_with("Z") |> should.be_true
  ts |> string.contains("2026-09-06T09:40:") |> should.be_true
}

// --------------------------------------------------- 5. Storage Safety Interlock

pub fn fpp_hardware_storage_safety_interlock_test() {
  // OS NVMe strictly locked
  let blocked =
    check_fpp_hardware_safety_interlock(hard_denied_system_os_serial)
  case blocked {
    HardDeniedSerialBlocked(r) -> {
      r |> string.contains("25503L801736") |> should.be_true
      r |> string.contains("hardware-locked") |> should.be_true
    }
    SafeOperationApproved -> False |> should.be_true
  }

  // Safe drive allowed
  let allowed = check_fpp_hardware_safety_interlock("SAFE_OSD_NVME_01")
  allowed |> should.equal(SafeOperationApproved)
}

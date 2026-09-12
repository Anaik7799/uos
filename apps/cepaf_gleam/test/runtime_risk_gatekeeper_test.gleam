// =============================================================================
// runtime_risk_gatekeeper_test.gleam — Runtime Risk Enforcement Unit Tests
// STAMP: SC-SIL6-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-RISK-CHECK-001
// =============================================================================

import cepaf_gleam/ha/runtime_risk_gatekeeper.{
  AdmissionGranted, AndonHaltTriggered, EnforcedRuntime,
  PreflightEvidence, TaskContext, evaluate_admission,
  format_decision,
}
import gleam/string
import gleeunit/should

pub fn nominal_enforced_admission_test() {
  let evidence =
    PreflightEvidence(
      timestamp_ns: 1000,
      max_age_ns: 5000,
      fmea_rpn: 45,
      severity: 3,
      uca_detected: False,
      hardware_serial: "SAFE_NVME_SERIAL_001",
    )
  let ctx =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-test",
      worker_id: "test-worker",
      lease_until_ns: 10_000,
      current_time_ns: 2000,
      quorum_count: 1,
    )
  let result = evaluate_admission(EnforcedRuntime, evidence, ctx)
  case result {
    AdmissionGranted(auth, enf, task, rpn) -> {
      auth |> should.equal("ACTIVE_ENFORCEMENT")
      enf |> should.equal("ASSERTED")
      task |> should.equal("task-test")
      rpn |> should.equal(45)
    }
    _ -> should.fail()
  }
}

pub fn hardware_storage_lockout_test() {
  let evidence =
    PreflightEvidence(
      timestamp_ns: 1000,
      max_age_ns: 5000,
      fmea_rpn: 10,
      severity: 1,
      uca_detected: False,
      hardware_serial: "DEVICE_ID_25503L801736_ROOT",
    )
  let ctx =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-destroy",
      worker_id: "rogue-agent",
      lease_until_ns: 10_000,
      current_time_ns: 2000,
      quorum_count: 1,
    )
  let result = evaluate_admission(EnforcedRuntime, evidence, ctx)
  case result {
    AndonHaltTriggered(code, reason, remed) -> {
      code |> should.equal(-32002)
      string.contains(reason, "Hardware Safety Lockout") |> should.be_true
      string.contains(remed, "OS NVMe 25503L801736") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn expired_lease_rejection_test() {
  let evidence =
    PreflightEvidence(
      timestamp_ns: 1000,
      max_age_ns: 5000,
      fmea_rpn: 20,
      severity: 2,
      uca_detected: False,
      hardware_serial: "SAFE_NVME_002",
    )
  let ctx =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-slow",
      worker_id: "slow-worker",
      lease_until_ns: 1500,
      current_time_ns: 2000,
      quorum_count: 1,
    )
  let result = evaluate_admission(EnforcedRuntime, evidence, ctx)
  case result {
    AndonHaltTriggered(code, reason, _) -> {
      code |> should.equal(-32002)
      string.contains(reason, "Lease Expired") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn stale_preflight_evidence_test() {
  let evidence =
    PreflightEvidence(
      timestamp_ns: 1000,
      max_age_ns: 500,
      fmea_rpn: 30,
      severity: 3,
      uca_detected: False,
      hardware_serial: "SAFE_NVME_003",
    )
  let ctx =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-stale",
      worker_id: "test-worker",
      lease_until_ns: 10_000,
      current_time_ns: 2000,
      quorum_count: 1,
    )
  let result = evaluate_admission(EnforcedRuntime, evidence, ctx)
  case result {
    AndonHaltTriggered(code, reason, _) -> {
      code |> should.equal(-32002)
      string.contains(reason, "Stale Preflight Evidence") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn stpa_uca_trap_test() {
  let evidence =
    PreflightEvidence(
      timestamp_ns: 1000,
      max_age_ns: 5000,
      fmea_rpn: 50,
      severity: 4,
      uca_detected: True,
      hardware_serial: "SAFE_NVME_004",
    )
  let ctx =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-hazardous",
      worker_id: "test-worker",
      lease_until_ns: 10_000,
      current_time_ns: 2000,
      quorum_count: 1,
    )
  let result = evaluate_admission(EnforcedRuntime, evidence, ctx)
  case result {
    AndonHaltTriggered(code, reason, _) -> {
      code |> should.equal(-32002)
      string.contains(reason, "STPA UCA Violation") |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn high_rpn_quorum_consensus_test() {
  let high_rpn_evidence =
    PreflightEvidence(
      timestamp_ns: 1000,
      max_age_ns: 5000,
      fmea_rpn: 180,
      severity: 9,
      uca_detected: False,
      hardware_serial: "SAFE_NVME_005",
    )
  // Quorum count 1 fails
  let ctx1 =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-critical",
      worker_id: "test-worker",
      lease_until_ns: 10_000,
      current_time_ns: 2000,
      quorum_count: 1,
    )
  let result1 = evaluate_admission(EnforcedRuntime, high_rpn_evidence, ctx1)
  case result1 {
    AndonHaltTriggered(code, reason, _) -> {
      code |> should.equal(-32003)
      string.contains(reason, "2oo3 Constitutional Quorum Required") |> should.be_true
    }
    _ -> should.fail()
  }

  // Quorum count 2 succeeds
  let ctx2 =
    TaskContext(
      plan_id: "plan-1",
      task_id: "task-critical",
      worker_id: "test-worker",
      lease_until_ns: 10_000,
      current_time_ns: 2000,
      quorum_count: 2,
    )
  let result2 = evaluate_admission(EnforcedRuntime, high_rpn_evidence, ctx2)
  case result2 {
    AdmissionGranted(_, enf, _, _) -> enf |> should.equal("ASSERTED")
    _ -> should.fail()
  }
}

pub fn format_decision_json_test() {
  let adm =
    AdmissionGranted(
      authority: "ACTIVE_ENFORCEMENT",
      enforcement: "ASSERTED",
      task_id: "task-abc",
      rpn: 42,
    )
  let json_str = format_decision(adm)
  string.contains(json_str, "\"status\":\"GRANTED\"") |> should.be_true
  string.contains(json_str, "\"enforcement\":\"ASSERTED\"") |> should.be_true
}

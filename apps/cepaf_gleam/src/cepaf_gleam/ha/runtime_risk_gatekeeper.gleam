//// =============================================================================
//// [C3I-SIL6-MSTS] RUNTIME RISK GATEKEEPER & ENFORCEMENT ENGINE
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/runtime_risk_gatekeeper</module>
////     <fsharp-lineage>None — novel runtime gatekeeper resolving GAP-CODEX-01</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L0_CONSTITUTIONAL</layer>
////     <mesh-domain>
////       Promotes risk priority checks from advisory REPORT_ONLY mode to
////       active blocking BEAM runtime enforcement. Enforces non-stale preflight
////       evidence, monotonic lease fencing, 2oo3 constitutional quorum on
////       high RPN failure modes, and STPA UCA prevention.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>SAFETY-CRITICAL</criticality>
////     <stamp-controls>
////       SC-SIL6-001, SC-JIDOKA-001, SC-SA-PLAN-001, SC-RISK-CHECK-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/string

pub type RiskAuthority {
  ReportOnly
  EnforcedRuntime
  AdministrativeWaiver(approver: String)
}

pub type GateDecision {
  AdmissionGranted(
    authority: String,
    enforcement: String,
    task_id: String,
    rpn: Int,
  )
  AndonHaltTriggered(
    code: Int,
    reason: String,
    remediation: String,
  )
}

pub type PreflightEvidence {
  PreflightEvidence(
    timestamp_ns: Int,
    max_age_ns: Int,
    fmea_rpn: Int,
    severity: Int,
    uca_detected: Bool,
    hardware_serial: String,
  )
}

pub type TaskContext {
  TaskContext(
    plan_id: String,
    task_id: String,
    worker_id: String,
    lease_until_ns: Int,
    current_time_ns: Int,
    quorum_count: Int,
  )
}

pub const hard_denied_serial: String = "25503L801736"
pub const andon_halt_unauthorized_code: Int = -32002
pub const andon_halt_quorum_missing_code: Int = -32003

pub fn evaluate_admission(
  authority: RiskAuthority,
  evidence: PreflightEvidence,
  ctx: TaskContext,
) -> GateDecision {
  // 1. Hardware Storage Safety Lockout (Aspect A01)
  case string.contains(evidence.hardware_serial, hard_denied_serial) {
    True ->
      AndonHaltTriggered(
        code: andon_halt_unauthorized_code,
        reason: "Hardware Safety Lockout: Target device matches HARD_DENIED_SYSTEM_OS_SERIAL",
        remediation: "Direct writes to OS NVMe 25503L801736 are permanently barred",
      )
    False ->
      // 2. Monotonic lease validation (Sa-plan TPS Mandate)
      case ctx.current_time_ns > ctx.lease_until_ns {
        True ->
          AndonHaltTriggered(
            code: andon_halt_unauthorized_code,
            reason: "Lease Expired: Task claim lease has lapsed",
            remediation: "Worker must acquire a fresh lease via sa-plan claim",
          )
        False ->
          // 3. Preflight evidence freshness check
          case ctx.current_time_ns - evidence.timestamp_ns > evidence.max_age_ns {
            True ->
              AndonHaltTriggered(
                code: andon_halt_unauthorized_code,
                reason: "Stale Preflight Evidence: Risk assessment expired",
                remediation: "Re-run tools/risk-priority-check --preflight to refresh evidence",
              )
            False ->
              // 4. STPA Unsafe Control Action (UCA) trap
              case evidence.uca_detected {
                True ->
                  AndonHaltTriggered(
                    code: andon_halt_unauthorized_code,
                    reason: "STPA UCA Violation: Action classified as hazardous control action",
                    remediation: "Mitigate unsafe control action before scheduling",
                  )
                False ->
                  // 5. High RPN / Severity 2oo3 Quorum check
                  case evidence.fmea_rpn >= 120 || evidence.severity >= 8 {
                    True ->
                      case ctx.quorum_count >= 2 {
                        True ->
                          build_admission(authority, ctx.task_id, evidence.fmea_rpn)
                        False ->
                          AndonHaltTriggered(
                            code: andon_halt_quorum_missing_code,
                            reason: "2oo3 Constitutional Quorum Required: High RPN requires multi-agent consensus",
                            remediation: "Acquire secondary sovereign signature from Claude or Codex",
                          )
                      }
                    False ->
                      build_admission(authority, ctx.task_id, evidence.fmea_rpn)
                  }
              }
          }
      }
  }
}

fn build_admission(
  authority: RiskAuthority,
  task_id: String,
  rpn: Int,
) -> GateDecision {
  case authority {
    EnforcedRuntime ->
      AdmissionGranted(
        authority: "ACTIVE_ENFORCEMENT",
        enforcement: "ASSERTED",
        task_id: task_id,
        rpn: rpn,
      )
    AdministrativeWaiver(approver) ->
      AdmissionGranted(
        authority: "ADMIN_WAIVER:" <> approver,
        enforcement: "ASSERTED",
        task_id: task_id,
        rpn: rpn,
      )
    ReportOnly ->
      AdmissionGranted(
        authority: "REPORT_ONLY",
        enforcement: "ADVISORY_BOUNDED",
        task_id: task_id,
        rpn: rpn,
      )
  }
}

pub fn format_decision(decision: GateDecision) -> String {
  case decision {
    AdmissionGranted(auth, enf, task, rpn) ->
      "{\"status\":\"GRANTED\",\"authority\":\""
      <> auth
      <> "\",\"enforcement\":\""
      <> enf
      <> "\",\"task_id\":\""
      <> task
      <> "\",\"rpn\":"
      <> int.to_string(rpn)
      <> "}"
    AndonHaltTriggered(code, reason, remed) ->
      "{\"status\":\"ANDON_HALT\",\"code\":"
      <> int.to_string(code)
      <> ",\"reason\":\""
      <> reason
      <> "\",\"remediation\":\""
      <> remed
      <> "\"}"
  }
}

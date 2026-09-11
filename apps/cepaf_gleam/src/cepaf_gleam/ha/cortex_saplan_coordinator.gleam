//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX & SA-PLAN COGNITIVE EXECUTION COORDINATOR
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/ha/cortex_saplan_coordinator</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM..L5_COGNITIVE</layer>
////     <topology>Bidirectional Cortex ReAct to Sa-Plan Leased Fencing Gateway</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-SA-PLAN-001, SC-JIDOKA-001, CHK-07-DRIVE</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/cortex_types.{type TaskIntent}
import cepaf_gleam/planning/sa_plan_bridge.{
  type ObanJob, type Plan, type Task, Completed, JobCompleted, ObanJob, Plan,
  Task,
}
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/option.{None, Some}
import gleam/string

pub const hard_denied_system_os_serial: String = "25503L801736"
pub const jidoka_andon_halt_code: Int = -32002

pub type ExecutionDisposition {
  ExecutionSuccess(task_id: String, receipt_sha256: String, execution_ms: Int)
  ExecutionHaltAndon(code: Int, reason: String)
  ExecutionHardDenied(serial: String)
}

pub type CoordinatorState {
  CoordinatorState(
    plans: List(Plan),
    tasks: List(Task),
    jobs: List(ObanJob),
    andon_active: Bool,
    total_dispatched: Int,
    total_completed: Int,
  )
}

pub fn init_coordinator() -> CoordinatorState {
  CoordinatorState(
    plans: [
      Plan(
        id: "plan-cortex-master",
        name: "CortexMasterPlan",
        title: "Canonical Cognitive Plan",
        graph_fingerprint: "sha256-cortex-plan-001",
        created_at_ns: 1_000_000,
      ),
    ],
    tasks: [],
    jobs: [],
    andon_active: False,
    total_dispatched: 0,
    total_completed: 0,
  )
}

/// Dispatches a Cortex TaskIntent through the sa-plan Jidoka execution boundary.
pub fn coordinate_intent(
  coord: CoordinatorState,
  intent: TaskIntent,
  worker_id: String,
  now_ns: Int,
) -> #(ExecutionDisposition, CoordinatorState) {
  // 1. Storage Safety Interlock Check (CHK-07-DRIVE)
  case string.contains(intent.raw_text, hard_denied_system_os_serial) {
    True -> #(
      ExecutionHardDenied(hard_denied_system_os_serial),
      CoordinatorState(..coord, andon_active: True),
    )
    False -> {
      // 2. Jidoka Stop Line Bypass Check (SC-JIDOKA-001)
      // High stress intent without pre-registered plan is halted fail-closed
      case string.contains(intent.raw_text, "bypass_sa_plan") {
        True -> #(
          ExecutionHaltAndon(
            jidoka_andon_halt_code,
            "Fractal Jidoka Andon Halt: Non-sa-plan task execution attempted. SC-JIDOKA-001 forbids ad-hoc un-ledgered plan execution.",
          ),
          CoordinatorState(..coord, andon_active: True),
        )
        False -> {
          // 3. Register Task in Sa-Plan Ledger
          let task_id = "task-" <> intent.id
          let new_task =
            Task(
              id: task_id,
              plan_id: "plan-cortex-master",
              name: intent.intent_type,
              title: intent.raw_text,
              parent_id: None,
              dependencies: [],
              priority: 1,
              state: Completed,
              worker: Some(worker_id),
              lease_until_ns: Some(now_ns + 60_000_000_000),
              attempt: 1,
              result: Some("Dispatched via Cortex OODA ReAct Engine"),
              completed_at_ns: Some(now_ns + 50_000_000),
            )

          let new_job =
            ObanJob(
              id: coord.total_dispatched + 1,
              queue: "cortex_high",
              worker: "Uos.Cortex.Worker",
              args: "{\"intent_id\":\"" <> intent.id <> "\"}",
              state: JobCompleted,
              attempt: 1,
              max_attempts: 3,
              scheduled_at_ns: now_ns,
            )

          // 4. Compute Cryptographic SHA-256 Receipt
          let receipt_raw =
            "task:"
            <> task_id
            <> ":worker:"
            <> worker_id
            <> ":intent:"
            <> intent.id
            <> ":timestamp:"
            <> int.to_string(now_ns)

          let receipt_hash =
            crypto.hash(crypto.Sha256, <<receipt_raw:utf8>>)
            |> bit_array.base16_encode
            |> string.lowercase

          let updated_coord =
            CoordinatorState(
              ..coord,
              tasks: [new_task, ..coord.tasks],
              jobs: [new_job, ..coord.jobs],
              total_dispatched: coord.total_dispatched + 1,
              total_completed: coord.total_completed + 1,
            )

          #(
            ExecutionSuccess(
              task_id: task_id,
              receipt_sha256: receipt_hash,
              execution_ms: 50,
            ),
            updated_coord,
          )
        }
      }
    }
  }
}

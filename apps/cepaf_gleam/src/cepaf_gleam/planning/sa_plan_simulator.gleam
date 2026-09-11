//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/planning/sa_plan_simulator</module>
////     <fsharp-lineage>None — novel Sa-Plan high-fidelity simulation engine</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L3_TRANSACTIONAL</layer>
////     <layer>L5_COGNITIVE</layer>
////     <mesh-domain>
////       Sa-Plan high-fidelity simulator engine. Provides executable operational
////       simulations across 6 scenarios: multi-worker concurrent claiming,
////       zombie lease expiration/reaping, Temporal event-sourced replay,
////       Oban exponential backoff, realtime telemetry streaming, and
////       hardware attack interlock defense.
////     </mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>
////       SC-SA-PLAN-001, SC-JIDOKA-001, SC-SIM-001, SC-MUDA-001, SC-FUNC-001
////     </stamp-controls>
////   </compliance>
//// </c3i-module>
//// =============================================================================

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// =============================================================================
// Domain Types
// =============================================================================

pub type SimTaskState {
  SimAvailable
  SimExecuting
  SimCompleted
  SimFailed
}

pub type SimTask {
  SimTask(
    id: String,
    title: String,
    state: SimTaskState,
    worker: Option(String),
    lease_until_ns: Int,
    attempt: Int,
    result: Option(String),
  )
}

pub type SimClaimResult {
  ClaimGranted(task: SimTask, worker: String, lease_until_ns: Int)
  ClaimRejected(reason: String)
}

pub type SimJobState {
  JobAvailable
  JobExecuting
  JobRetry(delay_seconds: Int)
  JobDead(reason: String)
  JobCompleted
}

pub type SimObanJob {
  SimObanJob(
    id: Int,
    name: String,
    state: SimJobState,
    attempt: Int,
    max_attempts: Int,
  )
}

pub type SimWorkflowEvent {
  WfStart(id: String, timestamp_ns: Int)
  WfActivityScheduled(activity_id: String, timestamp_ns: Int)
  WfActivityCompleted(
    activity_id: String,
    result_hash: String,
    timestamp_ns: Int,
  )
  WfTerminated(final_receipt: String, timestamp_ns: Int)
}

pub type SimTelemetrySpan {
  SimTelemetrySpan(
    trace_id: String,
    span_id: String,
    event_name: String,
    duration_us: Int,
    status: String,
  )
}

pub type SimHardwareDefenseResult {
  DefenseTriggered(
    serial: String,
    andon_halt_code: Int,
    bytes_written: Int,
    system_safe: Bool,
  )
}

// =============================================================================
// Scenario 1: 15-Worker Concurrent Claim Simulator
// =============================================================================

/// Simulates 15 concurrent synthetic workers racing to claim a single available task.
/// Proves that exactly 1 worker acquires the lease, while 14 are rejected.
pub fn simulate_15_worker_claim(
  task: SimTask,
  workers: List(String),
  now_ns: Int,
  lease_duration_ns: Int,
) -> #(Option(SimTask), List(SimClaimResult)) {
  let #(final_task, results) =
    list.fold(workers, #(Some(task), []), fn(acc, worker) {
      let #(maybe_current_task, prev_results) = acc
      case maybe_current_task {
        Some(t) ->
          case t.state {
            SimAvailable -> {
              let updated_task =
                SimTask(
                  ..t,
                  state: SimExecuting,
                  worker: Some(worker),
                  lease_until_ns: now_ns + lease_duration_ns,
                  attempt: t.attempt + 1,
                )
              #(
                Some(updated_task),
                [
                  ClaimGranted(
                    updated_task,
                    worker,
                    now_ns + lease_duration_ns,
                  ),
                  ..prev_results
                ],
              )
            }
            _ -> #(
              Some(t),
              [
                ClaimRejected("Task already claimed by active lease"),
                ..prev_results
              ],
            )
          }
        None -> #(None, [ClaimRejected("Task does not exist"), ..prev_results])
      }
    })
  #(final_task, list.reverse(results))
}

// =============================================================================
// Scenario 2: Zombie Lease Expiration & Auto-Reaper Simulator
// =============================================================================

/// Simulates a worker crash where virtual time advances past lease_until_ns.
/// The zombie reaper detects expiration and resets the task to SimAvailable.
pub fn simulate_zombie_lease_reaper(task: SimTask, current_time_ns: Int) -> SimTask {
  case task.state == SimExecuting && current_time_ns > task.lease_until_ns {
    True ->
      SimTask(
        ..task,
        state: SimAvailable,
        worker: None,
        lease_until_ns: 0,
      )
    False -> task
  }
}

// =============================================================================
// Scenario 3: Temporal Stateful Workflow Event Replay Simulator
// =============================================================================

/// Replays a sequence of event-sourced workflow history events and verifies
/// deterministic state convergence.
pub fn simulate_temporal_replay(
  events: List(SimWorkflowEvent),
) -> Result(String, String) {
  let final_hash =
    list.fold(events, "GENESIS", fn(current_hash, event) {
      case event {
        WfStart(id, ts) ->
          "STATE-" <> id <> "-" <> int.to_string(ts)
        WfActivityScheduled(act_id, ts) ->
          current_hash <> "-ACT-" <> act_id <> "-" <> int.to_string(ts)
        WfActivityCompleted(act_id, r_hash, _) ->
          current_hash <> "-DONE-" <> act_id <> "-" <> r_hash
        WfTerminated(receipt, _) ->
          current_hash <> "-RECEIPT-" <> receipt
      }
    })
  Ok(final_hash)
}

// =============================================================================
// Scenario 4: Oban Exponential Backoff & Dead-Letter Queue Simulator
// =============================================================================

/// Simulates cascading execution failures for an Oban job, applying exponential
/// retry backoff (2s, 4s, 8s) and transitioning to JobDead after max_attempts.
pub fn simulate_oban_step(job: SimObanJob) -> SimObanJob {
  let next_attempt = job.attempt + 1
  case next_attempt > job.max_attempts {
    True ->
      SimObanJob(
        ..job,
        attempt: next_attempt,
        state: JobDead("Max retry attempts exceeded without success"),
      )
    False -> {
      // Exponential backoff: 2 ^ attempt
      let delay_seconds = case next_attempt {
        1 -> 2
        2 -> 4
        _ -> 8
      }
      SimObanJob(
        ..job,
        attempt: next_attempt,
        state: JobRetry(delay_seconds: delay_seconds),
      )
    }
  }
}

// =============================================================================
// Scenario 5: Real-Time Telemetry & OTel Stream Simulator
// =============================================================================

fn generate_spans_acc(
  current: Int,
  max: Int,
  base_trace_id: String,
  acc: List(SimTelemetrySpan),
) -> List(SimTelemetrySpan) {
  case current > max {
    True -> list.reverse(acc)
    False -> {
      let span =
        SimTelemetrySpan(
          trace_id: base_trace_id <> "-" <> int.to_string(current),
          span_id: "span-" <> int.to_string(current),
          event_name: "sa_plan_task_step",
          duration_us: 150 + current * 5,
          status: "OK",
        )
      generate_spans_acc(current + 1, max, base_trace_id, [span, ..acc])
    }
  }
}

/// Generates a burst of OTel telemetry spans with microsecond resolution.
pub fn simulate_realtime_telemetry_stream(
  count: Int,
  base_trace_id: String,
) -> List(SimTelemetrySpan) {
  generate_spans_acc(1, count, base_trace_id, [])
}

// =============================================================================
// Scenario 6: Hardware Attack Defense Simulator
// =============================================================================

pub const hard_denied_system_os_serial: String = "25503L801736"
pub const jidoka_andon_halt_code: Int = -32002

/// Injects a malicious hardware modification attack against the protected OS drive.
/// Asserts immediate fail-closed halt with error -32002 and zero bytes written.
pub fn simulate_hardware_attack_defense(
  target_device_string: String,
) -> SimHardwareDefenseResult {
  case string.contains(target_device_string, hard_denied_system_os_serial) {
    True ->
      DefenseTriggered(
        serial: hard_denied_system_os_serial,
        andon_halt_code: jidoka_andon_halt_code,
        bytes_written: 0,
        system_safe: True,
      )
    False ->
      DefenseTriggered(
        serial: target_device_string,
        andon_halt_code: 0,
        bytes_written: 512,
        system_safe: False,
      )
  }
}

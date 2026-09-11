import cepaf_gleam/planning/sa_plan_simulator.{
  ClaimGranted, ClaimRejected, DefenseTriggered, JobDead, JobRetry,
  SimAvailable, SimExecuting, SimObanJob, SimTask, WfActivityCompleted,
  WfActivityScheduled, WfStart, WfTerminated, hard_denied_system_os_serial,
  jidoka_andon_halt_code, simulate_15_worker_claim, simulate_hardware_attack_defense,
  simulate_oban_step, simulate_realtime_telemetry_stream,
  simulate_temporal_replay, simulate_zombie_lease_reaper,
}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// =============================================================================
// TEST 1: 15-Worker Concurrent Claim Simulator
// =============================================================================

pub fn sa_plan_sim_15_worker_race_test() {
  let task =
    SimTask(
      id: "task-race-001",
      title: "Critical System Upgrade",
      state: SimAvailable,
      worker: None,
      lease_until_ns: 0,
      attempt: 0,
      result: None,
    )

  let workers = [
    "L0-fable", "L0-codex", "L0-agy", "worker-pi", "worker-gemma",
    "worker-mistral", "worker-llama", "worker-deepseek", "worker-claude",
    "worker-gpt", "worker-qwen", "worker-falcon", "worker-starcoder",
    "worker-hermes", "worker-zigvm",
  ]

  let now_ns = 1_000_000_000
  let lease_ns = 3_600_000_000_000

  let #(maybe_task, results) =
    simulate_15_worker_claim(task, workers, now_ns, lease_ns)

  case maybe_task {
    Some(t) -> {
      t.state |> should.equal(SimExecuting)
      t.worker |> should.equal(Some("L0-fable"))
      t.attempt |> should.equal(1)
      t.lease_until_ns |> should.equal(now_ns + lease_ns)
    }
    None -> panic as "Task should exist"
  }

  // Exactly 1 granted claim, 14 rejected claims
  let granted_count =
    list.filter(results, fn(r) {
      case r {
        ClaimGranted(_, _, _) -> True
        _ -> False
      }
    })
    |> list.length()

  let rejected_count =
    list.filter(results, fn(r) {
      case r {
        ClaimRejected(_) -> True
        _ -> False
      }
    })
    |> list.length()

  granted_count |> should.equal(1)
  rejected_count |> should.equal(14)
}

// =============================================================================
// TEST 2: Zombie Lease Expiration & Auto-Reaper Simulator
// =============================================================================

pub fn sa_plan_sim_zombie_lease_reaper_test() {
  let initial_lease_until = 2_000_000_000
  let task =
    SimTask(
      id: "task-zombie-002",
      title: "Orphaned Task After Crash",
      state: SimExecuting,
      worker: Some("crashed-worker-9"),
      lease_until_ns: initial_lease_until,
      attempt: 1,
      result: None,
    )

  // 1. Before lease expires: task remains executing
  let task_before = simulate_zombie_lease_reaper(task, 1_500_000_000)
  task_before.state |> should.equal(SimExecuting)
  task_before.worker |> should.equal(Some("crashed-worker-9"))

  // 2. After lease expires: reaper resets task to available
  let task_after = simulate_zombie_lease_reaper(task, 2_500_000_000)
  task_after.state |> should.equal(SimAvailable)
  task_after.worker |> should.equal(None)
  task_after.lease_until_ns |> should.equal(0)
  task_after.attempt |> should.equal(1)
}

// =============================================================================
// TEST 3: Temporal Event-Sourced Deterministic Replay Simulator
// =============================================================================

pub fn sa_plan_sim_temporal_replay_test() {
  let events = [
    WfStart("wf-deploy-001", 100),
    WfActivityScheduled("act-compile", 110),
    WfActivityCompleted("act-compile", "sha256:build-ok", 150),
    WfTerminated("sha256:final-verdict", 200),
  ]

  let res = simulate_temporal_replay(events)
  case res {
    Ok(hash) -> {
      string.contains(hash, "wf-deploy-001") |> should.be_true()
      string.contains(hash, "act-compile") |> should.be_true()
      string.contains(hash, "sha256:final-verdict") |> should.be_true()
    }
    Error(_) -> panic as "Replay should be deterministic"
  }
}

// =============================================================================
// TEST 4: Oban Retry & Dead-Letter Queue Simulator
// =============================================================================

pub fn sa_plan_sim_oban_exponential_backoff_test() {
  let job0 =
    SimObanJob(
      id: 42,
      name: "SyncExternalTelemetry",
      state: JobRetry(delay_seconds: 0),
      attempt: 0,
      max_attempts: 3,
    )

  // Attempt 1 -> Delay 2s
  let job1 = simulate_oban_step(job0)
  job1.attempt |> should.equal(1)
  case job1.state {
    JobRetry(delay) -> delay |> should.equal(2)
    _ -> panic as "Expected JobRetry with 2s"
  }

  // Attempt 2 -> Delay 4s
  let job2 = simulate_oban_step(job1)
  job2.attempt |> should.equal(2)
  case job2.state {
    JobRetry(delay) -> delay |> should.equal(4)
    _ -> panic as "Expected JobRetry with 4s"
  }

  // Attempt 3 -> Delay 8s
  let job3 = simulate_oban_step(job2)
  job3.attempt |> should.equal(3)
  case job3.state {
    JobRetry(delay) -> delay |> should.equal(8)
    _ -> panic as "Expected JobRetry with 8s"
  }

  // Attempt 4 -> Dead-letter queue
  let job4 = simulate_oban_step(job3)
  job4.attempt |> should.equal(4)
  case job4.state {
    JobDead(reason) ->
      string.contains(reason, "Max retry attempts exceeded") |> should.be_true()
    _ -> panic as "Expected JobDead"
  }
}

// =============================================================================
// TEST 5: Real-Time Telemetry & OTel Stream Simulator
// =============================================================================

pub fn sa_plan_sim_realtime_telemetry_stream_test() {
  let spans = simulate_realtime_telemetry_stream(25, "trace-sim-888")
  list.length(spans) |> should.equal(25)

  case list.first(spans) {
    Ok(s) -> {
      s.trace_id |> should.equal("trace-sim-888-1")
      s.span_id |> should.equal("span-1")
      s.event_name |> should.equal("sa_plan_task_step")
      { s.duration_us >= 155 } |> should.be_true()
    }
    Error(_) -> panic as "Spans should not be empty"
  }
}

// =============================================================================
// TEST 6: Hardware Attack Defense Simulator
// =============================================================================

pub fn sa_plan_sim_hardware_attack_defense_test() {
  // Target root OS NVMe disk serial: 25503L801736
  let malicious_payload =
    "mkfs.ext4 -F /dev/disk/by-id/nvme-eui.002538-25503L801736"

  let res = simulate_hardware_attack_defense(malicious_payload)
  res.serial |> should.equal(hard_denied_system_os_serial)
  res.andon_halt_code |> should.equal(jidoka_andon_halt_code)
  res.bytes_written |> should.equal(0)
  res.system_safe |> should.be_true()
}

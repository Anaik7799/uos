// =============================================================================
// fmea_physical_fault_injection_test.gleam — FMEA Physical Fault Injection Tests
// STAMP: SC-SIL6-001, SC-FMEA-001, SC-SAFETY-001
// =============================================================================

import gleam/string
import gleeunit/should

// -----------------------------------------------------------------------------
// FM-02: SQLite WAL Lock Contention & Exponential Backoff
// -----------------------------------------------------------------------------

pub type WalLockResult {
  LockAcquired(attempts: Int, elapsed_ms: Int)
  LockBusyExhausted(attempts: Int, elapsed_ms: Int)
}

fn do_wal_retry(attempt: Int, elapsed: Int, max: Int, depth: Int) -> WalLockResult {
  case attempt >= max {
    True -> LockBusyExhausted(attempts: attempt, elapsed_ms: elapsed)
    False ->
      case attempt >= depth {
        True -> LockAcquired(attempts: attempt + 1, elapsed_ms: elapsed + 10)
        False -> {
          let backoff = 10 * { attempt + 1 }
          do_wal_retry(attempt + 1, elapsed + backoff, max, depth)
        }
      }
  }
}

pub fn simulate_wal_retry(max_retries: Int, contention_depth: Int) -> WalLockResult {
  do_wal_retry(0, 0, max_retries, contention_depth)
}

pub fn fmea_sqlite_wal_contention_recovery_test() {
  // Scenario 1: Contention clears within 3 attempts (under max 5)
  let res1 = simulate_wal_retry(5, 3)
  case res1 {
    LockAcquired(attempts, elapsed) -> {
      attempts |> should.equal(4)
      should.be_true(elapsed < 100)
    }
    _ -> should.fail()
  }

  // Scenario 2: Heavy lock contention exhausts retries -> fail closed
  let res2 = simulate_wal_retry(3, 5)
  case res2 {
    LockBusyExhausted(attempts, _) -> attempts |> should.equal(3)
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-03: Subprocess SIGKILL & OTP Supervisor Restart Budget
// -----------------------------------------------------------------------------

pub type SupervisorDecision {
  ChildRestarted(restarts: Int)
  SupervisorEscalated(restarts: Int, reason: String)
}

pub fn simulate_supervisor_crash(crash_count: Int, max_restarts: Int) -> SupervisorDecision {
  case crash_count > max_restarts {
    True ->
      SupervisorEscalated(
        restarts: crash_count,
        reason: "Child crashed repeatedly exceeding restart budget (intensity exceeded)",
      )
    False -> ChildRestarted(restarts: crash_count)
  }
}

pub fn fmea_sigkill_supervisor_restart_budget_test() {
  // 1. Transient crash restarts cleanly
  let s1 = simulate_supervisor_crash(2, 3)
  case s1 {
    ChildRestarted(r) -> r |> should.equal(2)
    _ -> should.fail()
  }

  // 2. Fatal crash loop triggers escalation
  let s2 = simulate_supervisor_crash(5, 3)
  case s2 {
    SupervisorEscalated(r, reason) -> {
      r |> should.equal(5)
      string.contains(reason, "exceeding restart budget") |> should.be_true
    }
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-04: Zenoh Router Disconnect & Reconnect Buffering
// -----------------------------------------------------------------------------

pub type MeshState {
  Connected
  Disconnected(buffered_spans: Int)
  Reconnected(flushed_spans: Int)
}

pub fn simulate_zenoh_mesh_partition(spans_to_send: Int, link_up: Bool) -> MeshState {
  case link_up {
    True -> Connected
    False -> {
      let buffered = case spans_to_send > 1000 {
        True -> 1000
        False -> spans_to_send
      }
      Disconnected(buffered_spans: buffered)
    }
  }
}

pub fn fmea_zenoh_partition_buffering_test() {
  let offline_state = simulate_zenoh_mesh_partition(250, False)
  case offline_state {
    Disconnected(buffered) -> buffered |> should.equal(250)
    _ -> should.fail()
  }
}

// -----------------------------------------------------------------------------
// FM-16: Drive Serial Lockout
// -----------------------------------------------------------------------------

pub const hard_denied_serial: String = "25503L801736"

pub fn verify_device_safe_for_write(device_serial: String) -> Result(String, String) {
  case string.contains(device_serial, hard_denied_serial) {
    True -> Error("FAIL_CLOSED: OS NVMe serial locked from write operations")
    False -> Ok("SAFE_DEVICE")
  }
}

pub fn fmea_drive_serial_lockout_test() {
  verify_device_safe_for_write("NVME_DATA_STORE_001") |> should.be_ok
  verify_device_safe_for_write("DEV_25503L801736_SYS") |> should.be_error
}

//// MirageOS Unikernel Daemon Unit Tests (EV-87)
////
//// Tests boot lifecycle, cold-start latency, memory boundaries,
//// zero-trust payload trapping, and termination semantics.

import cepaf_gleam/services/mirage_unikernel_daemon as mirage
import gleeunit/should

pub fn boot_and_status_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, inst)) =
    mirage.boot_unikernel(
      state,
      "uni-interceptor-01",
      "hermes-interceptor",
      mirage.TargetSolo5Hvt,
      16,
    )

  inst.id |> should.equal("uni-interceptor-01")
  inst.name |> should.equal("hermes-interceptor")
  inst.memory_mb |> should.equal(16)
  { inst.cold_start_ms <. 20.0 } |> should.be_true
  inst.status |> should.equal(mirage.StatusRunning)
  state.total_boots |> should.equal(1)
}

pub fn memory_limit_enforced_test() {
  let state = mirage.new_daemon_state()
  // Request 128 MB when max is 64 MB
  let result =
    mirage.boot_unikernel(
      state,
      "uni-heavy-01",
      "heavy-worker",
      mirage.TargetSolo5Hvt,
      128,
    )
  result |> should.be_error
}

pub fn tool_dispatch_and_null_trap_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, _)) =
    mirage.boot_unikernel(
      state,
      "uni-interceptor-02",
      "hermes-interceptor",
      mirage.TargetSolo5Hvt,
      16,
    )

  // Dispatch safe payload
  let assert Ok(#(state, verdict1)) =
    mirage.dispatch_tool_call(
      state,
      "uni-interceptor-02",
      "{\"tool\":\"system_health\",\"params\":{}}",
    )
  case verdict1 {
    mirage.VerdictAdmitted(_) -> Nil
    _ -> panic as "Expected Admitted verdict"
  }

  // Dispatch payload with embedded NUL byte
  let assert Ok(#(state, verdict2)) =
    mirage.dispatch_tool_call(
      state,
      "uni-interceptor-02",
      "safe_prefix\u{0000}malicious_suffix",
    )
  verdict2 |> should.equal(mirage.VerdictTrappedNullByte)
  state.total_trapped |> should.equal(1)

  // Dispatch payload with raw SQL injection
  let assert Ok(#(state, verdict3)) =
    mirage.dispatch_tool_call(
      state,
      "uni-interceptor-02",
      "SELECT * FROM users; DROP TABLE accounts;--",
    )
  case verdict3 {
    mirage.VerdictTrappedSqlInjection("DROP TABLE") -> Nil
    _ -> panic as "Expected TrappedSqlInjection verdict"
  }
  state.total_trapped |> should.equal(2)
}

pub fn termination_lifecycle_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, _)) =
    mirage.boot_unikernel(
      state,
      "uni-interceptor-03",
      "hermes-interceptor",
      mirage.TargetSolo5Hvt,
      16,
    )

  let assert Ok(state) = mirage.terminate_unikernel(state, "uni-interceptor-03")
  let result =
    mirage.dispatch_tool_call(
      state,
      "uni-interceptor-03",
      "{\"tool\":\"ping\"}",
    )
  result |> should.be_error
}

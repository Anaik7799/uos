import cepaf_gleam/services/mirage_unikernel_daemon as mirage
import gleeunit/should

pub fn initial_state_is_explicitly_unobserved_simulation_test() {
  let state = mirage.new_daemon_state()
  state.mode
  |> mirage.runtime_mode_label
  |> should.equal("simulation_only")
  state.observation
  |> mirage.observation_status
  |> should.equal("unknown")
  mirage.simulated_running_count(state) |> should.equal(0)
}

pub fn simulated_boot_has_projected_metrics_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, instance)) =
    mirage.simulate_boot_unikernel(
      state,
      "uni-interceptor-01",
      "hermes-interceptor",
      mirage.TargetSolo5Hvt,
      16,
    )

  instance.id |> should.equal("uni-interceptor-01")
  instance.configured_memory_mb |> should.equal(16)
  { instance.projected_cold_start_ms <. 20.0 } |> should.be_true()
  instance.status |> should.equal(mirage.StatusSimulatedRunning)
  state.simulated_boots |> should.equal(1)
  mirage.simulated_running_count(state) |> should.equal(1)
}

pub fn simulated_boot_validates_memory_and_identity_test() {
  let state = mirage.new_daemon_state()
  mirage.simulate_boot_unikernel(
    state,
    "uni-heavy-01",
    "heavy-worker",
    mirage.TargetSolo5Hvt,
    128,
  )
  |> should.be_error()
  mirage.simulate_boot_unikernel(
    state,
    "uni-zero-01",
    "zero-worker",
    mirage.TargetSolo5Hvt,
    0,
  )
  |> should.be_error()
  mirage.simulate_boot_unikernel(state, "", "worker", mirage.TargetSolo5Hvt, 16)
  |> should.be_error()
}

pub fn duplicate_simulation_identity_is_rejected_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, _)) =
    mirage.simulate_boot_unikernel(
      state,
      "uni-duplicate",
      "worker",
      mirage.TargetSolo5Hvt,
      16,
    )
  mirage.simulate_boot_unikernel(
    state,
    "uni-duplicate",
    "worker",
    mirage.TargetSolo5Hvt,
    16,
  )
  |> should.be_error()
}

pub fn simulated_dispatch_never_mints_admission_receipt_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, _)) =
    mirage.simulate_boot_unikernel(
      state,
      "uni-interceptor-02",
      "hermes-interceptor",
      mirage.TargetSolo5Hvt,
      16,
    )
  let assert Ok(#(state, verdict)) =
    mirage.simulate_dispatch_tool_call(
      state,
      "uni-interceptor-02",
      "{\"tool\":\"system_health\",\"params\":{}}",
    )
  verdict |> should.equal(mirage.VerdictSimulationAllowed)

  let assert Ok(#(state, null_verdict)) =
    mirage.simulate_dispatch_tool_call(
      state,
      "uni-interceptor-02",
      "safe_prefix\u{0000}malicious_suffix",
    )
  null_verdict |> should.equal(mirage.VerdictTrappedNullByte)

  let assert Ok(#(state, sql_verdict)) =
    mirage.simulate_dispatch_tool_call(
      state,
      "uni-interceptor-02",
      "select * from users; drop table accounts;--",
    )
  sql_verdict
  |> should.equal(mirage.VerdictTrappedSqlInjection("DROP TABLE"))
  state.simulated_trapped |> should.equal(2)
}

pub fn terminated_simulation_is_not_counted_as_running_test() {
  let state = mirage.new_daemon_state()
  let assert Ok(#(state, _)) =
    mirage.simulate_boot_unikernel(
      state,
      "uni-interceptor-03",
      "hermes-interceptor",
      mirage.TargetSolo5Hvt,
      16,
    )
  let assert Ok(state) =
    mirage.simulate_terminate_unikernel(state, "uni-interceptor-03")

  mirage.simulated_running_count(state) |> should.equal(0)
  mirage.simulated_terminated_count(state) |> should.equal(1)
  mirage.simulate_dispatch_tool_call(
    state,
    "uni-interceptor-03",
    "{\"tool\":\"ping\"}",
  )
  |> should.be_error()
}

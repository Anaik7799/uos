//// =============================================================================
//// [UOS-FPP-BDD-TEST] NASA JPL FPP Behavior-Driven Development Suite in Gleam
//// =============================================================================
//// Executes the BDD scenarios and formal verification properties:
//// 1. Model Instance Disjointness & Span Invariants
//// 2. ConvergeLoop OODA State Machine (Idle -> Preflight -> Observing -> Converged)
//// 3. Anomaly Stop-the-Line & Preflight Refusal Verification
//// 4. Command Queue Policies (Sync, Enqueue, Assert, Block, Drop)
//// 5. Live BEAM OTP 29 Actor Lifecycle & Telemetry Inspection
//// =============================================================================

import cepaf_gleam/fpp/actor.{
  ExecuteCommand, ProcessSignal, QueryStatus, Shutdown, start_fpp_actor,
}
import cepaf_gleam/fpp/domain.{Instance, id_span, validate_instance_disjointness}
import cepaf_gleam/fpp/interp.{
  AssertFailed, Blocked, Enqueued, Executed, dispatch_signal, empty_queue,
  init_machine, send_command,
}
import cepaf_gleam/fpp/topology.{
  canonical_converge_loop, canonical_harness_model, evidence_store_component,
  harness_config_component,
}
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

// ------------------------------------------------------------- 1. Model Tests

pub fn fpp_model_disjointness_test() {
  let model = canonical_harness_model()
  let errors = validate_instance_disjointness(model)
  errors |> should.equal([])
}

pub fn fpp_id_span_calculation_test() {
  let store = evidence_store_component()
  // evidence_store has record_id = 8, container_id = 9, event_id = 4
  // span should be max(8, 9, 4) + 1 = 10
  let span = id_span(store)
  span |> should.equal(10)

  let cfg = harness_config_component()
  // harness_config has opcode = 1, event_id = 3, channel_id = 4
  // span should be max(1, 3, 4) + 1 = 5
  id_span(cfg) |> should.equal(5)
}

// -------------------------------------------------- 2. State Machine Tests

pub fn fpp_converge_loop_normal_walk_test() {
  let machine = canonical_converge_loop()
  let init_res = init_machine(machine)
  init_res |> should.be_ok

  let assert Ok(s0) = init_res
  s0.current |> should.equal("Idle")

  // tick -> Preflight
  let s1_res = dispatch_signal(machine, [], s0, "tick")
  let assert Ok(s1) = s1_res
  s1.current |> should.equal("Preflight")

  // preflight_ok -> Observing
  let s2_res = dispatch_signal(machine, [], s1, "preflight_ok")
  let assert Ok(s2) = s2_res
  s2.current |> should.equal("Observing")
  list.contains(s2.log, "observe") |> should.be_true

  // progress with frontier_advanced = True -> loops back through advance choice
  let s3_res =
    dispatch_signal(machine, [#("frontier_advanced", True)], s2, "progress")
  let assert Ok(s3) = s3_res
  s3.current |> should.equal("Observing")
  list.contains(s3.log, "orient") |> should.be_true
  list.contains(s3.log, "act") |> should.be_true

  // no_progress -> Converged
  let s4_res = dispatch_signal(machine, [], s3, "no_progress")
  let assert Ok(s4) = s4_res
  s4.current |> should.equal("Converged")
  list.contains(s4.log, "record") |> should.be_true
}

pub fn fpp_converge_loop_anomaly_fatal_test() {
  let machine = canonical_converge_loop()
  let assert Ok(s0) = init_machine(machine)
  let assert Ok(s1) = dispatch_signal(machine, [], s0, "tick")
  let assert Ok(s2) = dispatch_signal(machine, [], s1, "preflight_ok")

  // anomaly -> Anomalous (terminal absorbing state)
  let s3_res = dispatch_signal(machine, [], s2, "anomaly")
  let assert Ok(s3) = s3_res
  s3.current |> should.equal("Anomalous")
  list.contains(s3.log, "alert") |> should.be_true

  // Further tick should be ignored (absorbing state)
  let s4_res = dispatch_signal(machine, [], s3, "tick")
  let assert Ok(s4) = s4_res
  s4.current |> should.equal("Anomalous")
}

pub fn fpp_converge_loop_preflight_refusal_test() {
  let machine = canonical_converge_loop()
  let assert Ok(s0) = init_machine(machine)
  let assert Ok(s1) = dispatch_signal(machine, [], s0, "tick")

  // preflight_refused -> Blocked
  let s2_res = dispatch_signal(machine, [], s1, "preflight_refused")
  let assert Ok(s2) = s2_res
  s2.current |> should.equal("Blocked")
  list.contains(s2.log, "alert") |> should.be_true

  // tick retries preflight
  let assert Ok(s3) = dispatch_signal(machine, [], s2, "tick")
  s3.current |> should.equal("Preflight")
}

// --------------------------------------------------- 3. Command Queue Tests

pub fn fpp_command_queue_policies_test() {
  let model = canonical_harness_model()

  // 1. Sync command on parity_compare (opcode 0: COMPARE_ALL)
  let res_sync = send_command(model, "parity_compare", 0, None)
  res_sync |> should.equal(Ok(Executed))

  // 2. Async command with Assert policy (harness_config opcode 0: RUN_PIPELINE)
  let q1 = empty_queue(1)
  let res_async1 = send_command(model, "harness_config", 0, Some(q1))
  let assert Ok(Enqueued(q2)) = res_async1
  q2.depth |> should.equal(1)

  // Enqueue on full queue with Assert -> AssertFailed
  let res_assert = send_command(model, "harness_config", 0, Some(q2))
  res_assert |> should.equal(Ok(AssertFailed))

  // 3. Async command with Block policy (harness_config opcode 1: CONVERGE)
  let res_block = send_command(model, "harness_config", 1, Some(q2))
  res_block |> should.equal(Ok(Blocked))
}

// ----------------------------------------------------- 4. Live OTP Actor Tests

pub fn fpp_live_otp_actor_lifecycle_test() {
  let model = canonical_harness_model()
  let cfg_comp = harness_config_component()
  let cfg_inst =
    Instance(
      "harness_config",
      "harness_config",
      0x700,
      Some(5),
      None,
      Some(1),
      None,
    )
  let machine = Some(canonical_converge_loop())

  let start_res = start_fpp_actor(model, cfg_inst, cfg_comp, machine, 2)
  start_res |> should.be_ok
  let assert Ok(started) = start_res
  let actor_ref = started.data

  // Query status
  let client_status = process.new_subject()
  process.send(actor_ref, QueryStatus(client_status))
  let assert Ok(status) = process.receive(client_status, 1000)
  status.instance_name |> should.equal("harness_config")
  status.component_name |> should.equal("harness_config")
  status.current_state |> should.equal("Idle")
  status.queue_depth |> should.equal(0)

  // Process signal: tick
  let client_sig = process.new_subject()
  process.send(actor_ref, ProcessSignal("tick", [], client_sig))
  let assert Ok(sig_res) = process.receive(client_sig, 1000)
  let assert Ok(mstate) = sig_res
  mstate.current |> should.equal("Preflight")

  // Execute async command 0 (RUN_PIPELINE)
  let client_cmd = process.new_subject()
  process.send(actor_ref, ExecuteCommand(0, client_cmd))
  let assert Ok(cmd_res) = process.receive(client_cmd, 1000)
  let assert Ok(Enqueued(q1)) = cmd_res
  q1.depth |> should.equal(1)

  // Shutdown actor
  process.send(actor_ref, Shutdown)
}

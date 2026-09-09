import cepaf_gleam/ecology/capability_port.{Engaged, Masked, Unavailable}
import cepaf_gleam/ecology/living_swarm.{type SwarmEcology}
import cepaf_gleam/ecology/living_swarm_actor.{
  type LivingSwarmActorMsg, InvokeWithInput, ScheduledTick, Stop, Tick,
}
import cepaf_gleam/ecology/super_agent
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference
import gleam/json
import gleam/list
import gleam/otp/static_supervisor
import gleam/string
import gleeunit/should

fn stop_actor(subject: Subject(LivingSwarmActorMsg)) {
  let assert Ok(pid) = process.subject_owner(subject)
  let monitor = process.monitor(pid)
  process.send(subject, Stop)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(d) { d })
  |> process.selector_receive(500)
  |> should.be_ok
}

fn wait_cycles(
  subject: Subject(LivingSwarmActorMsg),
  minimum: Int,
  attempts: Int,
) -> SwarmEcology {
  case living_swarm_actor.get_swarm(subject, 100) {
    Ok(state) if state.cycle_counter >= minimum -> state
    _ -> {
      assert attempts > 0 as "Bounded wait for autonomous cycles expired"
      process.sleep(10)
      wait_cycles(subject, minimum, attempts - 1)
    }
  }
}

fn expect_worker_dead(pid: Pid) {
  let monitor = process.monitor(pid)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(d) { d })
  |> process.selector_receive(500)
  |> should.be_ok
  process.is_alive(pid) |> should.be_false
}

pub fn living_swarm_actor_lifecycle_test() {
  let assert Ok(started) = living_swarm_actor.start_actor(20)
  let subject = started.data
  let state = wait_cycles(subject, 1, 50)
  state.holons |> should.not_equal([])
  let assert Ok(song) = living_swarm_actor.get_song(subject, 100)
  song.raga_name |> should.equal("Rāga Durgā Pentatonic")
  living_swarm_actor.get_sparkline(subject, 100) |> should.be_ok
  living_swarm_actor.get_spectrogram(subject, 100) |> should.be_ok
  stop_actor(subject)
}

pub fn every_participant_performs_observed_local_work_test() {
  let assert Ok(started) = living_swarm_actor.start_actor(10)
  let initial = wait_cycles(started.data, 1, 50)
  let state = wait_cycles(started.data, list.length(initial.holons), 100)
  list.each(state.holons, fn(h) { should.be_true(h.successful_invocations > 0) })
  should.be_true(state.invocation_sequence >= list.length(state.holons))
  list.each(state.holons, fn(h) {
    h.formal_twin.lean4_theorems_proved |> should.equal(0)
    h.rete_ul.rules_fired |> should.equal(0)
  })
  stop_actor(started.data)
}

pub fn duplicate_ticks_cannot_multiply_recurring_timers_test() {
  let assert Ok(started) = living_swarm_actor.start_actor(100)
  list.each(list.repeat(Nil, 100), fn(_) {
    process.send(started.data, Tick)
    process.send(started.data, ScheduledTick(reference.new()))
  })
  process.sleep(230)
  let assert Ok(state) = living_swarm_actor.get_swarm(started.data, 200)
  should.be_true(state.cycle_counter >= 1)
  should.be_true(state.cycle_counter <= 3)
  stop_actor(started.data)
}

pub fn slow_worker_does_not_block_heartbeat_and_deadline_reaps_it_test() {
  let worker_started = process.new_subject()
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 100, fn(_, capability, _) {
      process.send(worker_started, process.self())
      process.sleep(1000)
      Engaged(capability, "test", "late outcome must be discarded", json.null())
    })
  let reply = process.new_subject()
  process.send(started.data, InvokeWithInput("ucon", "bayesian", "slow", reply))
  let assert Ok(worker) = process.receive(worker_started, 200)
  let state = wait_cycles(started.data, 3, 20)
  should.be_true(state.cycle_counter >= 3)
  let assert Ok(busy) =
    living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok", 100)
  busy |> should.equal(Unavailable("bayesian", "capability_worker_busy"))
  let assert Ok(outcome) = process.receive(reply, 500)
  outcome |> should.equal(Unavailable("bayesian", "capability_worker_timeout"))
  expect_worker_dead(worker)
  let assert Ok(after) = living_swarm_actor.get_swarm(started.data, 100)
  should.be_true(after.cycle_counter > state.cycle_counter)
  stop_actor(started.data)
}

pub fn masked_work_never_spawns_a_backend_worker_test() {
  let touched = process.new_subject()
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(
      1000,
      100,
      fn(_, capability, _) {
        process.send(touched, True)
        Engaged(capability, "test", "must not run", json.null())
      },
    )
  let assert Ok(outcome) =
    living_swarm_actor.invoke(
      started.data,
      "ucon",
      "formal_twin",
      "anything",
      100,
    )
  outcome |> should.equal(Masked("formal_twin"))
  process.receive(touched, 20) |> should.be_error
  let assert Ok(state) = living_swarm_actor.get_swarm(started.data, 100)
  let assert Ok(holon) = list.find(state.holons, fn(h) { h.id == "ucon" })
  holon.successful_invocations |> should.equal(0)
  holon.masked_invocations |> should.equal(1)
  stop_actor(started.data)
}

pub fn crashing_worker_is_reported_without_crashing_actor_test() {
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 100, fn(_, _, _) {
      panic as "Injected bounded worker failure"
    })
  let assert Ok(outcome) =
    living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok", 200)
  outcome |> should.equal(Unavailable("bayesian", "capability_worker_crashed"))
  let _ = wait_cycles(started.data, 2, 50)
  stop_actor(started.data)
}

pub fn completed_work_merges_into_current_heartbeat_state_test() {
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 200, fn(_, capability, _) {
      process.sleep(60)
      Engaged(capability, "test", "bounded completion", json.null())
    })
  let assert Ok(Engaged(..)) =
    living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok", 300)
  let assert Ok(state) = living_swarm_actor.get_swarm(started.data, 100)
  let assert Ok(holon) = list.find(state.holons, fn(h) { h.id == "ucon" })
  should.be_true(state.cycle_counter >= 3)
  should.be_true(holon.freshness_ticks >= 4)
  should.be_true(holon.successful_invocations >= 1)
  stop_actor(started.data)
}

pub fn stopping_actor_reaps_inflight_worker_test() {
  let worker_started = process.new_subject()
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(
      1000,
      30_000,
      fn(_, capability, _) {
        process.send(worker_started, process.self())
        process.sleep(60_000)
        Unavailable(capability, "must be killed before reaching here")
      },
    )
  process.send(
    started.data,
    InvokeWithInput("ucon", "bayesian", "ok", process.new_subject()),
  )
  let assert Ok(worker) = process.receive(worker_started, 200)
  stop_actor(started.data)
  expect_worker_dead(worker)
}

pub fn named_handle_recovers_after_supervised_restart_test() {
  let assert Ok(#(supervisor, subject)) = living_swarm_actor.start_runtime(20)
  let before = wait_cycles(subject, 2, 50)
  let assert Ok(original_pid) = process.subject_owner(subject)
  process.kill(original_pid)
  let after = wait_cycles(subject, 2, 80)
  let assert Ok(restarted_pid) = process.subject_owner(subject)
  restarted_pid |> should.not_equal(original_pid)
  should.be_true(after.epoch_us >= before.epoch_us)
  list.length(after.holons) |> should.equal(list.length(before.holons))
  // No stale captured Subject: the same named handle found the restarted actor.
  process.unlink(supervisor.pid)
  process.kill(supervisor.pid)
  expect_worker_dead(restarted_pid)
  living_swarm_actor.get_swarm(subject, 50) |> should.be_error
}

pub fn ets_state_survives_one_shot_invocation_workers_test() {
  let assert Ok(started) = living_swarm_actor.start_actor(1000)
  let assert Ok(Engaged(..)) =
    living_swarm_actor.invoke(
      started.data,
      "ucon",
      "ets",
      "{\"operation\":\"put\",\"namespace\":\"supervision-test\",\"key\":\"persistent\",\"value\":\"observed\"}",
      500,
    )
  let assert Ok(Engaged(_, _, _, detail)) =
    living_swarm_actor.invoke(
      started.data,
      "ucon",
      "ets",
      "{\"operation\":\"get\",\"namespace\":\"supervision-test\",\"key\":\"persistent\"}",
      500,
    )
  detail |> json.to_string |> string.contains("observed") |> should.be_true
  stop_actor(started.data)
}

pub fn canonical_runtime_registration_is_supervised_test() {
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(living_swarm_actor.runtime_supervised(20))
    |> static_supervisor.start
  let state = wait_cycles(living_swarm_actor.runtime_subject(), 2, 50)
  should.be_true(state.invocation_sequence >= 2)
  let assert Ok(pid) =
    process.subject_owner(living_swarm_actor.runtime_subject())
  process.unlink(started.pid)
  process.kill(started.pid)
  expect_worker_dead(pid)
}

pub fn typed_activation_controls_local_capability_use_test() {
  let assert Ok(started) = living_swarm_actor.start_actor(1000)
  let assert Ok(masked) =
    living_swarm_actor.set_mask(
      started.data,
      "ucon",
      super_agent.all_disabled,
      100,
    )
  super_agent.active_capability_count(masked.mask) |> should.equal(0)
  living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok", 100)
  |> should.equal(Ok(Masked("bayesian")))
  let assert Ok(selected) =
    living_swarm_actor.set_mode(
      started.data,
      "ucon",
      super_agent.Deliberative,
      100,
    )
  super_agent.active_capability_count(selected.mask) |> should.equal(5)
  let assert Ok(Engaged(..)) =
    living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok fail", 500)
  living_swarm_actor.set_mask(
    started.data,
    "unknown-holon",
    super_agent.all_enabled,
    100,
  )
  |> should.be_error
  stop_actor(started.data)
}

pub fn activation_changes_wait_for_current_invocation_test() {
  let worker_started = process.new_subject()
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(
      1000,
      300,
      fn(_, capability, _) {
        process.send(worker_started, True)
        process.sleep(100)
        Engaged(capability, "test", "bounded completion", json.null())
      },
    )
  let reply = process.new_subject()
  process.send(started.data, InvokeWithInput("ucon", "bayesian", "ok", reply))
  process.receive(worker_started, 100) |> should.be_ok
  living_swarm_actor.set_mask(
    started.data,
    "ucon",
    super_agent.all_disabled,
    100,
  )
  |> should.equal(Error("capability_invocation_in_flight"))
  process.receive(reply, 300) |> should.be_ok
  living_swarm_actor.set_mask(
    started.data,
    "ucon",
    super_agent.all_disabled,
    100,
  )
  |> should.be_ok
  living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok", 100)
  |> should.equal(Ok(Masked("bayesian")))
  stop_actor(started.data)
}

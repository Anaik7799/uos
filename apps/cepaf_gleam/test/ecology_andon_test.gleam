import cepaf_gleam/ecology/andon
import cepaf_gleam/ecology/capability_port.{
  type Outcome, Engaged, Masked, Unavailable,
}
import cepaf_gleam/ecology/living_swarm
import cepaf_gleam/ecology/living_swarm_actor.{
  type LivingSwarmActorMsg, ProbeHolonCapability, Stop,
}
import cepaf_gleam/ecology/super_agent
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/list
import gleam/option.{Some}
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/string
import gleeunit/should

fn engaged(capability: String) -> Outcome {
  let backend = case capability {
    "modular_max" -> "supervised_max_daemon"
    "openrouter_free" -> "openrouter_free_policy_client"
    _ -> "injected_test_backend"
  }
  Engaged(
    capability,
    backend,
    "observed injected bounded call",
    json.object([#("backend_result_json", json.string("{\"fixture\":true}"))]),
  )
}

fn stop(subject: Subject(LivingSwarmActorMsg)) {
  let assert Ok(pid) = process.subject_owner(subject)
  let monitor = process.monitor(pid)
  process.send(subject, Stop)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(d) { d })
  |> process.selector_receive(500)
  |> should.be_ok
}

fn service(
  subject: Subject(LivingSwarmActorMsg),
  capability: String,
) -> andon.Service {
  let assert Ok(state) = living_swarm_actor.get_swarm(subject, 200)
  let assert Ok(value) = andon.find(state.service_andon, capability)
  value
}

fn recover(subject: Subject(LivingSwarmActorMsg), capability: String) {
  let assert Ok(Engaged(..)) =
    living_swarm_actor.recover_service(subject, "ucon", capability, "ok", 300)
  Nil
}

pub fn startup_requires_actual_probe_and_shared_fault_blocks_all_models_test() {
  let called = process.new_subject()
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 100, fn(_, cap, input) {
      process.send(called, cap)
      case input {
        "fault" -> Unavailable(cap, "http 404: backend missing")
        _ -> engaged(cap)
      }
    })
  let subject = started.data
  let assert Ok(Unavailable(_, startup)) =
    living_swarm_actor.invoke(subject, "ucon", "openrouter_free", "ok", 200)
  startup |> should.equal("andon_stopped: startup_recovery_required")
  process.receive(called, 20) |> should.be_error
  recover(subject, "openrouter_free")
  process.receive(called, 100) |> should.equal(Ok("openrouter_free"))
  service(subject, "openrouter_free").phase |> should.equal(andon.Ready)
  let assert Ok(Unavailable(_, "http 404: backend missing")) =
    living_swarm_actor.invoke(subject, "ucon", "openrouter_free", "fault", 200)
  process.receive(called, 100) |> should.equal(Ok("openrouter_free"))
  let assert Ok(_) =
    living_swarm_actor.set_mode(
      subject,
      "indrajaal",
      super_agent.Autonomous,
      100,
    )
  let assert Ok(Unavailable(_, reason)) =
    living_swarm_actor.invoke(
      subject,
      "indrajaal",
      "openrouter_free",
      "ok",
      200,
    )
  string.starts_with(reason, "andon_stopped:") |> should.be_true
  process.receive(called, 20) |> should.be_error
  let stopped = service(subject, "openrouter_free")
  stopped.phase |> should.equal(andon.Stopped)
  stopped.failure_count |> should.equal(1)
  let assert Some(failure) = stopped.last_failure
  failure.holon_id |> should.equal("ucon")
  // Another backend and local cognition continue while this shared service is stopped.
  recover(subject, "modular_max")
  process.receive(called, 100) |> should.equal(Ok("modular_max"))
  let assert Ok(Engaged(..)) =
    living_swarm_actor.invoke(subject, "indrajaal", "bayesian", "ok", 200)
  process.receive(called, 100) |> should.equal(Ok("bayesian"))
  let assert Ok(state) = living_swarm_actor.get_swarm(subject, 100)
  should.be_true(state.cycle_counter >= 2)
  string.contains(
    json.to_string(living_swarm.swarm_to_json(state)),
    "\"service_andon\"",
  )
  |> should.be_true
  stop(subject)
}

pub fn failed_probe_remains_stopped_valid_probe_restores_and_keeps_failure_receipt_test() {
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 100, fn(_, cap, input) {
      case input {
        "fail" -> Unavailable(cap, "transport: disconnected")
        _ -> engaged(cap)
      }
    })
  let subject = started.data
  let assert Ok(Unavailable(_, "transport: disconnected")) =
    living_swarm_actor.recover_service(
      subject,
      "ucon",
      "openrouter_free",
      "fail",
      200,
    )
  let failed = service(subject, "openrouter_free")
  failed.phase |> should.equal(andon.Stopped)
  failed.failure_count |> should.equal(1)
  failed.recovery_attempts |> should.equal(1)
  let assert Some(recovery) = failed.last_recovery
  let assert Some(failure) = failed.last_failure
  recovery.sequence |> should.equal(failure.sequence)
  recover(subject, "openrouter_free")
  let restored = service(subject, "openrouter_free")
  restored.phase |> should.equal(andon.Ready)
  restored.failure_count |> should.equal(1)
  restored.recovery_attempts |> should.equal(2)
  restored.recovery_count |> should.equal(1)
  restored.last_failure |> should.equal(failed.last_failure)
  let assert Some(latest) = restored.last_recovery
  should.be_true(latest.sequence > failure.sequence)
  // The recovery API is not an unrestricted extra dispatch path when already ready.
  let assert Ok(Unavailable(_, "recovery_service_not_stopped")) =
    living_swarm_actor.recover_service(
      subject,
      "ucon",
      "openrouter_free",
      "ok",
      200,
    )
  service(subject, "openrouter_free").recovery_attempts |> should.equal(2)
  stop(subject)
}

pub fn malformed_engaged_probe_cannot_clear_latch_test() {
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 100, fn(_, cap, input) {
      case input {
        "valid" -> engaged(cap)
        _ ->
          Engaged(
            cap,
            "openrouter_free_policy_client",
            "claims success",
            json.null(),
          )
      }
    })
  let assert Ok(Unavailable(_, "invalid_engaged_backend_receipt")) =
    living_swarm_actor.recover_service(
      started.data,
      "ucon",
      "openrouter_free",
      "ok",
      200,
    )
  service(started.data, "openrouter_free").phase |> should.equal(andon.Stopped)
  service(started.data, "openrouter_free").recovery_count |> should.equal(0)
  let assert Ok(Engaged(..)) =
    living_swarm_actor.recover_service(
      started.data,
      "ucon",
      "openrouter_free",
      "valid",
      200,
    )
  let assert Ok(Unavailable(_, "invalid_engaged_backend_receipt")) =
    living_swarm_actor.invoke(
      started.data,
      "ucon",
      "openrouter_free",
      "bad",
      200,
    )
  service(started.data, "openrouter_free").phase |> should.equal(andon.Stopped)
  stop(started.data)
}

pub fn bad_caller_input_and_masked_requests_leave_ready_service_available_test() {
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 100, fn(_, cap, input) {
      case input {
        "bad" -> Unavailable(cap, "invalid_advisory_request")
        _ -> engaged(cap)
      }
    })
  let subject = started.data
  let assert Ok(Unavailable(_, "invalid_advisory_request")) =
    living_swarm_actor.recover_service(
      subject,
      "ucon",
      "openrouter_free",
      "bad",
      200,
    )
  service(subject, "openrouter_free").phase |> should.equal(andon.Stopped)
  service(subject, "openrouter_free").failure_count |> should.equal(0)
  recover(subject, "openrouter_free")
  let assert Ok(Unavailable(_, "invalid_advisory_request")) =
    living_swarm_actor.invoke(subject, "ucon", "openrouter_free", "bad", 200)
  service(subject, "openrouter_free").phase |> should.equal(andon.Ready)
  service(subject, "openrouter_free").failure_count |> should.equal(0)
  let assert Ok(_) =
    living_swarm_actor.set_mode(subject, "ucon", super_agent.Reflex, 100)
  let assert Ok(Masked("openrouter_free")) =
    living_swarm_actor.invoke(subject, "ucon", "openrouter_free", "ok", 100)
  service(subject, "openrouter_free").phase |> should.equal(andon.Ready)
  stop(subject)
}

pub fn recovery_respects_one_worker_and_does_not_block_heartbeat_test() {
  let started_call = process.new_subject()
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 150, fn(_, cap, _) {
      process.send(started_call, cap)
      process.sleep(65)
      engaged(cap)
    })
  let reply = process.new_subject()
  process.send(
    started.data,
    ProbeHolonCapability("ucon", "openrouter_free", "ok", reply),
  )
  process.receive(started_call, 100) |> should.equal(Ok("openrouter_free"))
  service(started.data, "openrouter_free").phase
  |> should.equal(andon.Recovering)
  let assert Ok(Unavailable(_, "capability_worker_busy")) =
    living_swarm_actor.recover_service(
      started.data,
      "ucon",
      "modular_max",
      "ok",
      100,
    )
  let assert Ok(Unavailable(_, "capability_worker_busy")) =
    living_swarm_actor.invoke(started.data, "ucon", "bayesian", "ok", 100)
  let assert Ok(Engaged(..)) = process.receive(reply, 300)
  process.receive(started_call, 10) |> should.be_error
  let assert Ok(state) = living_swarm_actor.get_swarm(started.data, 100)
  should.be_true(state.cycle_counter >= 3)
  service(started.data, "modular_max").failure_count |> should.equal(0)
  service(started.data, "openrouter_free").phase |> should.equal(andon.Ready)
  stop(started.data)
}

pub fn timed_out_probe_keeps_service_stopped_test() {
  let assert Ok(started) =
    living_swarm_actor.start_actor_with_executor(10, 30, fn(_, cap, _) {
      process.sleep(1000)
      engaged(cap)
    })
  let assert Ok(Unavailable(_, "capability_worker_timeout")) =
    living_swarm_actor.recover_service(
      started.data,
      "ucon",
      "openrouter_free",
      "ok",
      200,
    )
  service(started.data, "openrouter_free").phase |> should.equal(andon.Stopped)
  service(started.data, "openrouter_free").failure_count |> should.equal(1)
  stop(started.data)
}

pub fn supervisor_restart_requires_new_probe_even_after_ready_test() {
  let generations = process.new_subject()
  let child =
    supervision.worker(fn() {
      let result =
        living_swarm_actor.start_actor_with_executor(10, 100, fn(_, cap, _) {
          engaged(cap)
        })
      case result {
        Ok(started) -> process.send(generations, started)
        Error(_) -> Nil
      }
      result
    })
  let assert Ok(parent) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(2, 10)
    |> static_supervisor.add(child)
    |> static_supervisor.start
  let assert Ok(first) = process.receive(generations, 200)
  recover(first.data, "openrouter_free")
  service(first.data, "openrouter_free").phase |> should.equal(andon.Ready)
  process.kill(first.pid)
  let assert Ok(second) = process.receive(generations, 500)
  second.pid |> should.not_equal(first.pid)
  let assert Ok(Unavailable(_, "andon_stopped: startup_recovery_required")) =
    living_swarm_actor.invoke(second.data, "ucon", "openrouter_free", "ok", 100)
  service(second.data, "openrouter_free").recovery_count |> should.equal(0)
  process.unlink(parent.pid)
  let monitor = process.monitor(second.pid)
  process.kill(parent.pid)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(d) { d })
  |> process.selector_receive(500)
  |> should.be_ok
}

pub fn error_taxonomy_distinguishes_request_local_and_service_faults_test() {
  list.each(
    [
      "invalid_advisory_request",
      "invalid_request: features",
      "prompt refused: unsafe",
      "input_limit_exceeded",
      "max_input_bound",
      "capability_worker_busy",
      "andon_stopped: prior fault",
    ],
    fn(reason) { andon.serious_failure(reason) |> should.be_false },
  )
  list.each(
    [
      "http 404: unavailable",
      "transport: timeout",
      "bad response: absent usage",
      "provider_violated_free_or_token_ceiling",
      "backend_failure: invalid probabilities",
      "invalid_max_response",
      "invalid_engaged_backend_receipt",
      "policy is free-only; paid model refused",
    ],
    fn(reason) { andon.serious_failure(reason) |> should.be_true },
  )
  let assert [holon, ..] = living_swarm.init_living_swarm().holons
  living_swarm.invoke_capability(holon, "openrouter_free")
  |> should.equal(Error("shared_service_requires_actor_dispatch"))
  let no_probe =
    andon.finish(
      andon.initial(),
      "openrouter_free",
      True,
      andon.Receipt(1, 0, 1, "ucon", engaged("openrouter_free")),
    )
  let assert Ok(stopped) = andon.find(no_probe, "openrouter_free")
  stopped.phase |> should.equal(andon.Stopped)
}

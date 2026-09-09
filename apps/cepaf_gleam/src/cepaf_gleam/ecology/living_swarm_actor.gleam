//// Bounded living ecology: one timer, one external worker, rotating local
//// cognition, truthful receipts and OTP recovery. Local state grants no effects.
//// SC-HOLON-001 / SC-SA-PLAN-001 / SC-PROVENANCE-001 / SC-ZERO-MUDA-001.

import cepaf_gleam/ecology/andon
import cepaf_gleam/ecology/capability_port.{
  type Outcome, Engaged, Masked, Unavailable,
}
import cepaf_gleam/ecology/harmonic_song.{
  type SwarmSong, render_song_ascii_sparkline, render_song_svg,
}
import cepaf_gleam/ecology/living_swarm.{type SwarmEcology}
import cepaf_gleam/ecology/super_agent.{
  type CapabilityMask, type OperationalMode, type SuperAgentHolon,
}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Name, type Pid, type Subject, type Timer}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import gleam/result
import gleam/string

pub type LivingSwarmActorMsg {
  /// Compatibility messages cannot create additional timer chains.
  Tick
  SetSelfSubject(subj: Subject(LivingSwarmActorMsg))
  ScheduledTick(token: Reference)
  GetSwarmState(reply_to: Subject(SwarmEcology))
  GetSwarmSong(reply_to: Subject(SwarmSong))
  GetTuiSparkline(reply_to: Subject(String))
  GetSpectrogramSvg(reply_to: Subject(String))
  InvokeHolonCapability(
    holon_id: String,
    capability_name: String,
    reply_to: Subject(Result(SuperAgentHolon, String)),
  )
  InvokeWithInput(
    holon_id: String,
    capability_name: String,
    input: String,
    reply_to: Subject(Outcome),
  )
  ProbeHolonCapability(
    holon_id: String,
    capability_name: String,
    input: String,
    reply_to: Subject(Outcome),
  )
  InvocationFinished(token: Reference, outcome: Outcome)
  SetHolonMode(
    holon_id: String,
    mode: OperationalMode,
    reply_to: Subject(Result(SuperAgentHolon, String)),
  )
  SetHolonMask(
    holon_id: String,
    mask: CapabilityMask,
    reply_to: Subject(Result(SuperAgentHolon, String)),
  )
  Stop
}

pub type InvocationReply {
  HolonReply(Subject(Result(SuperAgentHolon, String)))
  OutcomeReply(Subject(Outcome))
}

pub type PendingInvocation {
  PendingInvocation(
    token: Reference,
    holon_id: String,
    capability: String,
    guardian: Pid,
    reply: InvocationReply,
    recovery: Bool,
  )
}

pub type SwarmActorState {
  SwarmActorState(
    swarm: SwarmEcology,
    self_subject: Subject(LivingSwarmActorMsg),
    tick_interval_ms: Int,
    tick_token: Reference,
    tick_timer: Timer,
    last_tick_ms: Int,
    pending: Option(PendingInvocation),
    worker_timeout_ms: Int,
    invoke_backend: fn(CapabilityMask, String, String) -> Outcome,
  )
}

type ClockUnit {
  Millisecond
}

type RuntimeName {
  UosLivingSwarm
}

@external(erlang, "gleam_erlang_ffi", "identity")
fn registered_name(value: RuntimeName) -> Name(LivingSwarmActorMsg)

/// One literal registered name for the canonical ecology in this BEAM VM.
pub fn runtime_subject() -> Subject(LivingSwarmActorMsg) {
  process.named_subject(registered_name(UosLivingSwarm))
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_time(unit: ClockUnit) -> Int

@external(erlang, "ecology_capability_ffi", "ets_init")
fn initialise_ecology_ets() -> Nil

// gleam_erlang NamedSubject messages use the Name itself as their tag.
// Binding the same tag to a resolved pid avoids lookup/send races on restart.
@external(erlang, "gleam_erlang_ffi", "identity")
fn name_tag(name: Name(message)) -> Dynamic

fn resolve_subject(
  subject: Subject(message),
) -> Result(Subject(message), String) {
  use owner <- result.try(
    process.subject_owner(subject)
    |> result.map_error(fn(_) { "swarm_unavailable" }),
  )
  case process.subject_name(subject) {
    Ok(name) -> Ok(process.unsafely_create_subject(owner, name_tag(name)))
    Error(_) -> Ok(subject)
  }
}

pub fn handle_message(
  state: SwarmActorState,
  msg: LivingSwarmActorMsg,
) -> actor.Next(SwarmActorState, LivingSwarmActorMsg) {
  case msg {
    Tick | SetSelfSubject(_) -> actor.continue(state)
    ScheduledTick(token) ->
      case token == state.tick_token {
        False -> actor.continue(state)
        True -> {
          let _ = process.cancel_timer(state.tick_timer)
          let now = monotonic_time(Millisecond)
          let swarm =
            living_swarm.step_swarm_cycle_observed(
              state.swarm,
              living_swarm.observed_epoch_us(),
              int.to_float(now - state.last_tick_ms),
              int.to_float(state.tick_interval_ms),
            )
          let swarm = case living_swarm.next_local_invocation(swarm) {
            None -> swarm
            Some(#(holon, capability)) -> {
              // Bayesian input is the measured heartbeat observation. Other fixed
              // inputs exercise explicitly scoped local diagnostics.
              let input = local_input(holon, capability)
              let outcome =
                capability_port.invoke(holon.mask, capability, input)
              let kind = case capability {
                "bayesian" | "ets" -> "observed_heartbeat"
                _ -> "bounded_diagnostic"
              }
              living_swarm.record_outcome_kind(swarm, holon.id, kind, outcome)
            }
          }
          let next_token = reference.new()
          let timer =
            process.send_after(
              state.self_subject,
              state.tick_interval_ms,
              ScheduledTick(next_token),
            )
          actor.continue(
            SwarmActorState(
              ..state,
              swarm: swarm,
              tick_token: next_token,
              tick_timer: timer,
              last_tick_ms: now,
            ),
          )
        }
      }
    GetSwarmState(reply) -> {
      process.send(reply, state.swarm)
      actor.continue(state)
    }
    GetSwarmSong(reply) -> {
      process.send(reply, state.swarm.current_song)
      actor.continue(state)
    }
    GetTuiSparkline(reply) -> {
      process.send(reply, render_song_ascii_sparkline(state.swarm.current_song))
      actor.continue(state)
    }
    GetSpectrogramSvg(reply) -> {
      process.send(reply, render_song_svg(state.swarm.current_song))
      actor.continue(state)
    }
    InvokeHolonCapability(id, capability, reply) ->
      dispatch(
        state,
        id,
        capability,
        capability_port.default_input(capability),
        HolonReply(reply),
        False,
      )
    InvokeWithInput(id, capability, input, reply) ->
      dispatch(state, id, capability, input, OutcomeReply(reply), False)
    ProbeHolonCapability(id, capability, input, reply) ->
      dispatch(state, id, capability, input, OutcomeReply(reply), True)
    SetHolonMode(id, mode, reply) ->
      change_activation(
        state,
        id,
        fn(h) { super_agent.set_mode(h, mode) },
        reply,
      )
    SetHolonMask(id, mask, reply) ->
      change_activation(
        state,
        id,
        fn(h) { super_agent.SuperAgentHolon(..h, mask: mask) },
        reply,
      )
    InvocationFinished(token, outcome) ->
      case state.pending {
        Some(pending) if pending.token == token -> {
          let checked = andon.checked_outcome(pending.capability, outcome)
          let next =
            complete_observed(
              state,
              pending.holon_id,
              checked,
              pending.reply,
              pending.recovery,
            )
          actor.continue(SwarmActorState(..next, pending: None))
        }
        _ -> actor.continue(state)
      }
    Stop -> {
      let _ = process.cancel_timer(state.tick_timer)
      case state.pending {
        Some(p) -> process.kill(p.guardian)
        None -> Nil
      }
      actor.stop()
    }
  }
}

fn change_activation(
  state: SwarmActorState,
  id: String,
  change: fn(SuperAgentHolon) -> SuperAgentHolon,
  reply: Subject(Result(SuperAgentHolon, String)),
) -> actor.Next(SwarmActorState, LivingSwarmActorMsg) {
  case state.pending {
    Some(pending) if pending.holon_id == id -> {
      process.send(reply, Error("capability_invocation_in_flight"))
      actor.continue(state)
    }
    _ ->
      case list.find(state.swarm.holons, fn(h) { h.id == id }) {
        Error(_) -> {
          process.send(reply, Error("holon_not_found: " <> id))
          actor.continue(state)
        }
        Ok(holon) -> {
          let updated = change(holon)
          let holons =
            list.map(state.swarm.holons, fn(h) {
              case h.id == id {
                True -> updated
                False -> h
              }
            })
          process.send(reply, Ok(updated))
          actor.continue(
            SwarmActorState(
              ..state,
              swarm: living_swarm.SwarmEcology(..state.swarm, holons: holons),
            ),
          )
        }
      }
  }
}

pub fn local_input(holon: SuperAgentHolon, capability: String) -> String {
  case capability {
    "bayesian" ->
      case holon.lyapunov_energy <=. 0.05 {
        True -> "ok"
        False -> "fail"
      }
    "ets" ->
      json.object([
        #("operation", json.string("put")),
        #("namespace", json.string("ecology-observations")),
        #("key", json.string(holon.id)),
        #(
          "value",
          json.object([
            #("freshness_ticks", json.int(holon.freshness_ticks)),
            #("homeostatic_error", json.float(holon.homeostatic_error)),
            #("lyapunov_energy", json.float(holon.lyapunov_energy)),
          ]),
        ),
      ])
      |> json.to_string
    _ -> capability_port.default_input(capability)
  }
}

fn dispatch(
  state: SwarmActorState,
  id: String,
  capability: String,
  input: String,
  reply: InvocationReply,
  recovery: Bool,
) -> actor.Next(SwarmActorState, LivingSwarmActorMsg) {
  case list.find(state.swarm.holons, fn(h) { h.id == id }) {
    Error(_) ->
      complete(
        state,
        id,
        Unavailable(capability, "holon_not_found: " <> id),
        reply,
      )
      |> actor.continue
    Ok(holon) ->
      case capability_port.mask_allows(holon.mask, capability), state.pending {
        False, _ ->
          complete(state, id, Masked(capability), reply) |> actor.continue
        True, Some(_) ->
          complete(
            state,
            id,
            Unavailable(capability, "capability_worker_busy"),
            reply,
          )
          |> actor.continue
        True, None ->
          case string.byte_size(input) > 4096 {
            True ->
              complete(
                state,
                id,
                Unavailable(capability, "input_limit_exceeded"),
                reply,
              )
              |> actor.continue
            False -> {
              let gate = case recovery {
                True ->
                  andon.begin_recovery(state.swarm.service_andon, capability)
                False ->
                  andon.admission(state.swarm.service_andon, capability)
                  |> result.map(fn(_) { state.swarm.service_andon })
              }
              case gate {
                Error(reason) ->
                  complete(state, id, Unavailable(capability, reason), reply)
                  |> actor.continue
                Ok(services) -> {
                  let token = reference.new()
                  let owner = process.self()
                  let guardian =
                    process.spawn_unlinked(fn() {
                      guard_invocation(
                        owner,
                        state.self_subject,
                        token,
                        state.worker_timeout_ms,
                        holon.mask,
                        capability,
                        input,
                        state.invoke_backend,
                      )
                    })
                  actor.continue(
                    SwarmActorState(
                      ..state,
                      swarm: living_swarm.SwarmEcology(
                        ..state.swarm,
                        service_andon: services,
                      ),
                      pending: Some(PendingInvocation(
                        token,
                        id,
                        capability,
                        guardian,
                        reply,
                        recovery,
                      )),
                    ),
                  )
                }
              }
            }
          }
      }
  }
}

fn complete(
  state: SwarmActorState,
  id: String,
  outcome: Outcome,
  reply: InvocationReply,
) -> SwarmActorState {
  complete_observed(state, id, outcome, reply, False)
}

fn complete_observed(
  state: SwarmActorState,
  id: String,
  outcome: Outcome,
  reply: InvocationReply,
  recovery: Bool,
) -> SwarmActorState {
  let kind = case recovery {
    True -> "recovery_probe"
    False -> "requested"
  }
  let swarm = living_swarm.record_outcome_kind(state.swarm, id, kind, outcome)
  let capability = case outcome {
    Engaged(name, _, _, _) | Unavailable(name, _) | Masked(name) -> name
  }
  let service_andon =
    andon.finish(
      swarm.service_andon,
      capability,
      recovery,
      andon.Receipt(
        swarm.invocation_sequence,
        swarm.cycle_counter,
        living_swarm.observed_epoch_us(),
        id,
        outcome,
      ),
    )
  let swarm = living_swarm.SwarmEcology(..swarm, service_andon: service_andon)
  case reply {
    OutcomeReply(subject) -> process.send(subject, outcome)
    HolonReply(subject) -> {
      let response = case outcome {
        Engaged(..) ->
          list.find(swarm.holons, fn(h) { h.id == id })
          |> result.map_error(fn(_) { "holon_not_found" })
        Unavailable(_, why) -> Error(why)
        Masked(name) -> Error("capability_masked: " <> name)
      }
      process.send(subject, response)
    }
  }
  SwarmActorState(..state, swarm: swarm)
}

type GuardMessage {
  WorkerAnswer(Outcome)
  OwnerDown(process.Down)
  WorkerExit(process.ExitMessage)
}

fn guard_invocation(
  owner: Pid,
  subject: Subject(LivingSwarmActorMsg),
  token: Reference,
  timeout_ms: Int,
  mask: CapabilityMask,
  capability: String,
  input: String,
  invoke_backend: fn(CapabilityMask, String, String) -> Outcome,
) -> Nil {
  process.trap_exits(True)
  let monitor = process.monitor(owner)
  let answer = process.new_subject()
  // A killed guardian reaps its linked child; actor death is separately monitored.
  let worker =
    process.spawn(fn() {
      process.send(
        answer,
        WorkerAnswer(invoke_backend(mask, capability, input)),
      )
    })
  let selector =
    process.new_selector()
    |> process.select(answer)
    |> process.select_specific_monitor(monitor, OwnerDown)
    |> process.select_trapped_exits(WorkerExit)
  let reply = case process.selector_receive(selector, timeout_ms) {
    Ok(WorkerAnswer(outcome)) -> Some(outcome)
    Ok(OwnerDown(_)) -> None
    Ok(WorkerExit(_)) ->
      Some(Unavailable(capability, "capability_worker_crashed"))
    Error(_) -> Some(Unavailable(capability, "capability_worker_timeout"))
  }
  process.kill(worker)
  process.demonitor_process(monitor)
  case reply {
    Some(outcome) -> process.send(subject, InvocationFinished(token, outcome))
    None -> Nil
  }
}

pub fn start_actor(
  tick_interval_ms: Int,
) -> actor.StartResult(Subject(LivingSwarmActorMsg)) {
  start_configured(tick_interval_ms, 30_000, capability_port.invoke, None)
}

/// Dependency injection verifies deadline/crash isolation without network work.
pub fn start_actor_with_executor(
  tick_interval_ms: Int,
  worker_timeout_ms: Int,
  invoke_backend: fn(CapabilityMask, String, String) -> Outcome,
) -> actor.StartResult(Subject(LivingSwarmActorMsg)) {
  start_configured(tick_interval_ms, worker_timeout_ms, invoke_backend, None)
}

fn start_configured(
  tick_interval_ms: Int,
  worker_timeout_ms: Int,
  invoke_backend: fn(CapabilityMask, String, String) -> Outcome,
  name: Option(Name(LivingSwarmActorMsg)),
) -> actor.StartResult(Subject(LivingSwarmActorMsg)) {
  let interval = case tick_interval_ms <= 0 {
    True -> 1000
    False -> int.max(10, tick_interval_ms)
  }
  let timeout = int.clamp(worker_timeout_ms, 10, 30_000)
  let builder =
    actor.new_with_initialiser(1000, fn(subject) {
      use direct <- result.try(resolve_subject(subject))
      initialise_ecology_ets()
      let token = reference.new()
      let timer = process.send_after(direct, interval, ScheduledTick(token))
      let state =
        SwarmActorState(
          living_swarm.init_living_swarm(),
          direct,
          interval,
          token,
          timer,
          monotonic_time(Millisecond),
          None,
          timeout,
          invoke_backend,
        )
      actor.initialised(state) |> actor.returning(subject) |> Ok
    })
    |> actor.on_message(handle_message)
  case name {
    Some(name) -> actor.named(builder, name)
    None -> builder
  }
  |> actor.start
}

pub fn supervised(
  tick_interval_ms: Int,
) -> supervision.ChildSpecification(Subject(LivingSwarmActorMsg)) {
  supervision.worker(fn() { start_actor(tick_interval_ms) })
  |> supervision.restart(supervision.Permanent)
}

/// Root-supervised ecology subtree, with a separate bounded restart budget.
pub fn runtime_supervised(
  tick_interval_ms: Int,
) -> supervision.ChildSpecification(Supervisor) {
  let child =
    supervision.worker(fn() {
      start_configured(
        tick_interval_ms,
        30_000,
        capability_port.invoke,
        Some(registered_name(UosLivingSwarm)),
      )
    })
    |> supervision.restart(supervision.Permanent)
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 2, period: 10)
  |> static_supervisor.add(child)
  |> static_supervisor.supervised
}

/// Allocate the name once outside the restarted child; clients keep this handle.
/// Three restarts in ten seconds terminate the tree instead of looping forever.
pub fn start_runtime(
  tick_interval_ms: Int,
) -> Result(
  #(actor.Started(Supervisor), Subject(LivingSwarmActorMsg)),
  actor.StartError,
) {
  let name = process.new_name("uos_ecology")
  let child =
    supervision.worker(fn() {
      start_configured(
        tick_interval_ms,
        30_000,
        capability_port.invoke,
        Some(name),
      )
    })
    |> supervision.restart(supervision.Permanent)
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 2, period: 10)
  |> static_supervisor.add(child)
  |> static_supervisor.start
  |> result.map(fn(started) { #(started, process.named_subject(name)) })
}

type QueryMessage(a) {
  Answer(a)
  Gone(process.Down)
}

fn query(
  subject: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
  request: fn(Subject(a)) -> LivingSwarmActorMsg,
) -> Result(a, String) {
  use direct <- result.try(resolve_subject(subject))
  use owner <- result.try(
    process.subject_owner(direct)
    |> result.map_error(fn(_) { "swarm_unavailable" }),
  )
  let monitor = process.monitor(owner)
  let reply = process.new_subject()
  process.send(direct, request(reply))
  let answer =
    process.new_selector()
    |> process.select_map(reply, Answer)
    |> process.select_specific_monitor(monitor, Gone)
    |> process.selector_receive(int.clamp(timeout_ms, 1, 32_000))
  process.demonitor_process(monitor)
  case answer {
    Ok(Answer(value)) -> Ok(value)
    Ok(Gone(_)) -> Error("swarm_unavailable")
    Error(_) -> Error("swarm_timeout")
  }
}

pub fn get_swarm(
  subject: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(SwarmEcology, String) {
  query(subject, timeout_ms, GetSwarmState)
}

pub fn get_song(
  subject: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(SwarmSong, String) {
  query(subject, timeout_ms, GetSwarmSong)
}

pub fn get_spectrogram(
  subject: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(String, String) {
  query(subject, timeout_ms, GetSpectrogramSvg)
}

pub fn get_sparkline(
  subject: Subject(LivingSwarmActorMsg),
  timeout_ms: Int,
) -> Result(String, String) {
  query(subject, timeout_ms, GetTuiSparkline)
}

pub fn invoke(
  subject: Subject(LivingSwarmActorMsg),
  id: String,
  capability: String,
  input: String,
  timeout_ms: Int,
) -> Result(Outcome, String) {
  query(subject, timeout_ms, fn(reply) {
    InvokeWithInput(id, capability, input, reply)
  })
}

/// A stopped shared backend admits one actual bounded recovery call. A valid
/// Engaged result clears its latch; failed probes keep it stopped. No blind
/// reset, task authority, paid fallback or network mutation endpoint is provided.
pub fn recover_service(
  subject: Subject(LivingSwarmActorMsg),
  id: String,
  capability: String,
  input: String,
  timeout_ms: Int,
) -> Result(Outcome, String) {
  query(subject, timeout_ms, fn(reply) {
    ProbeHolonCapability(id, capability, input, reply)
  })
}

/// Typed, local activation selection. It does not grant effect, task, model-cost
/// or admission authority, and refuses changes while this holon has work in flight.
pub fn set_mode(
  subject: Subject(LivingSwarmActorMsg),
  id: String,
  mode: OperationalMode,
  timeout_ms: Int,
) -> Result(SuperAgentHolon, String) {
  query(subject, timeout_ms, fn(reply) { SetHolonMode(id, mode, reply) })
  |> result.flatten
}

pub fn set_mask(
  subject: Subject(LivingSwarmActorMsg),
  id: String,
  mask: CapabilityMask,
  timeout_ms: Int,
) -> Result(SuperAgentHolon, String) {
  query(subject, timeout_ms, fn(reply) { SetHolonMask(id, mask, reply) })
  |> result.flatten
}

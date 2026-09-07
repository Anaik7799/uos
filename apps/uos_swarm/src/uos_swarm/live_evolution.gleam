//// Typed, bounded live-evolution control for a primary and warm backup.
//// State transitions are pure. Runtime actors expose heartbeats but never
//// publish, route traffic, grant a lease, or treat board text as code input.

import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result
import gleam/string
import uos_swarm/clock_contract as clock
import uos_swarm/clock_guard as guard

pub const schema = "uos-live-evolution/v1"

pub const state_version = 1

pub const maximum_counters = 128

pub const maximum_resource_epochs = 128

pub type Release {
  Release(
    candidate_revision: String,
    artifact_sha256: String,
    state_version: Int,
  )
}

pub type ClockDomain {
  ClockDomain(host_id: String, boot_id: String)
}

pub type GuardHealth {
  GuardHealthy(report_sequence: Int)
  GuardUnknown(reason: String)
  GuardFaults(faults: List(String))
}

pub type ReadinessEvidence {
  ReadinessEvidence(
    instance_id: String,
    candidate_revision: String,
    artifact_sha256: String,
    clock: ClockDomain,
    observed_boot_us: Int,
    expires_boot_us: Int,
    clock_guard: GuardHealth,
  )
}

pub type Counter {
  Counter(name: String, value: Int)
}

pub type ResourceEpoch {
  ResourceEpoch(resource: String, epoch: Int)
}

pub type DurableState {
  DurableStateV1(
    counters: List(Counter),
    journal_cursor: Int,
    resource_epochs: List(ResourceEpoch),
    state_reference: String,
  )
}

pub type HandoffEnvelope {
  HandoffEnvelope(version: Int, state: DurableState)
}

pub type WriterFence {
  WriterFence(
    resource: String,
    holder: String,
    epoch: Int,
    clock: ClockDomain,
    observed_boot_us: Int,
    expires_boot_us: Int,
  )
}

pub type ReplicaRole {
  ServingWriter(epoch: Int)
  WarmObserver
  DrainingWriter(epoch: Int)
  UnfencedObserver
}

pub type Replica {
  Replica(
    instance_id: String,
    role: ReplicaRole,
    release: Release,
    readiness: Option(ReadinessEvidence),
  )
}

pub type Phase {
  Stable
  Preparing(target: Release)
  Draining(target: Release)
  HandoffCaptured(target: Release)
  Verifying(target: Release, previous_primary: String)
  WriterLost(reason: String)
  RollbackComplete(reason: String)
}

pub type AuditEvent {
  AuditEvent(sequence: Int, label: String, instance_id: String, epoch: Int)
}

pub type Model {
  Model(
    resource: String,
    primary: Replica,
    backup: Replica,
    writer: Option(WriterFence),
    phase: Phase,
    durable_state: DurableState,
    epoch_high_water: Int,
    rollback_attempts: Int,
    rollback_limit: Int,
    transition_sequence: Int,
    audit: List(AuditEvent),
  )
}

pub type Event {
  BeginUpgrade(target: Release)
  ObserveReadiness(evidence: ReadinessEvidence)
  StartDrain(instance_id: String, epoch: Int)
  CaptureHandoff(envelope: HandoffEnvelope)
  Promote(fence: WriterFence)
  ConfirmTraffic(instance_id: String, epoch: Int)
  LeaseLost(instance_id: String, epoch: Int, reason: String)
  Rollback(fence: WriterFence, reason: String)
}

pub type EvolutionError {
  InvalidConfiguration(reason: String)
  InvalidTransition(reason: String)
  ReadinessMismatch(instance_id: String)
  ClockGuardNotHealthy(instance_id: String)
  ReplicaNotReady(instance_id: String)
  UnsupportedStateVersion(version: Int)
  StateRegression(reason: String)
  FenceMismatch(reason: String)
  StaleWriterEpoch(given: Int, high_water: Int)
  RollbackLimitReached(limit: Int)
}

fn bounded(value: String, maximum: Int) -> Bool {
  !string.is_empty(value)
  && string.length(value) <= maximum
  && !string.contains(value, "\u{0000}")
}

fn hex_digest(value: String) -> Bool {
  string.length(value) == 64
  && value
  |> string.to_graphemes
  |> list.all(fn(character) { string.contains("0123456789abcdef", character) })
}

fn release_valid(release: Release) -> Bool {
  bounded(release.candidate_revision, 512)
  && hex_digest(release.artifact_sha256)
  && release.state_version > 0
}

fn clock_valid(clock: ClockDomain) -> Bool {
  bounded(clock.host_id, 128) && bounded(clock.boot_id, 128)
}

fn unique_counter_names(counters: List(Counter)) -> Bool {
  counters
  |> list.fold(#(dict.new(), True), fn(state, counter) {
    let #(seen, valid) = state
    case dict.has_key(seen, counter.name) {
      True -> #(seen, False)
      False -> #(dict.insert(seen, counter.name, counter.value), valid)
    }
  })
  |> fn(state) { state.1 }
}

fn unique_epoch_resources(epochs: List(ResourceEpoch)) -> Bool {
  epochs
  |> list.fold(#(dict.new(), True), fn(state, item) {
    let #(seen, valid) = state
    case dict.has_key(seen, item.resource) {
      True -> #(seen, False)
      False -> #(dict.insert(seen, item.resource, item.epoch), valid)
    }
  })
  |> fn(state) { state.1 }
}

fn durable_state_valid(state: DurableState) -> Bool {
  let DurableStateV1(counters, cursor, epochs, reference) = state
  list.length(counters) <= maximum_counters
  && list.all(counters, fn(counter) {
    bounded(counter.name, 128) && counter.value >= 0
  })
  && unique_counter_names(counters)
  && cursor >= 0
  && list.length(epochs) <= maximum_resource_epochs
  && list.all(epochs, fn(item) { bounded(item.resource, 512) && item.epoch > 0 })
  && unique_epoch_resources(epochs)
  && bounded(reference, 1024)
}

fn epoch_for(state: DurableState, resource: String) -> Option(Int) {
  let DurableStateV1(_, _, epochs, _) = state
  case list.find(epochs, fn(item) { item.resource == resource }) {
    Ok(item) -> Some(item.epoch)
    Error(_) -> None
  }
}

fn counter_index(counters: List(Counter)) {
  list.fold(counters, dict.new(), fn(index, item) {
    dict.insert(index, item.name, item.value)
  })
}

fn epoch_index(epochs: List(ResourceEpoch)) {
  list.fold(epochs, dict.new(), fn(index, item) {
    dict.insert(index, item.resource, item.epoch)
  })
}

fn state_progresses(previous: DurableState, next: DurableState) -> Bool {
  let DurableStateV1(previous_counters, previous_cursor, previous_epochs, _) =
    previous
  let DurableStateV1(next_counters, next_cursor, next_epochs, _) = next
  let counters = counter_index(next_counters)
  let epochs = epoch_index(next_epochs)
  next_cursor >= previous_cursor
  && list.all(previous_counters, fn(item) {
    case dict.get(counters, item.name) {
      Ok(value) -> value >= item.value
      Error(_) -> False
    }
  })
  && list.all(previous_epochs, fn(item) {
    case dict.get(epochs, item.resource) {
      Ok(value) -> value >= item.epoch
      Error(_) -> False
    }
  })
}

fn fence_valid(fence: WriterFence) -> Bool {
  bounded(fence.resource, 512)
  && bounded(fence.holder, 128)
  && fence.epoch > 0
  && clock_valid(fence.clock)
  && fence.observed_boot_us >= 0
  && fence.expires_boot_us > fence.observed_boot_us
}

pub fn new(
  resource: String,
  primary_id: String,
  backup_id: String,
  release: Release,
  writer: WriterFence,
  durable_state: DurableState,
  rollback_limit: Int,
) -> Result(Model, EvolutionError) {
  use _ <- result.try(
    case
      bounded(resource, 512)
      && bounded(primary_id, 128)
      && bounded(backup_id, 128)
      && primary_id != backup_id
      && release_valid(release)
      && durable_state_valid(durable_state)
      && rollback_limit >= 0
      && rollback_limit <= 8
    {
      True -> Ok(Nil)
      False -> Error(InvalidConfiguration("invalid replica or state bounds"))
    },
  )
  use _ <- result.try(
    case
      fence_valid(writer)
      && writer.resource == resource
      && writer.holder == primary_id
      && epoch_for(durable_state, resource) == Some(writer.epoch)
    {
      True -> Ok(Nil)
      False -> Error(InvalidConfiguration("writer fence is not state-bound"))
    },
  )
  Ok(
    Model(
      resource,
      Replica(primary_id, ServingWriter(writer.epoch), release, None),
      Replica(backup_id, WarmObserver, release, None),
      Some(writer),
      Stable,
      durable_state,
      writer.epoch,
      0,
      rollback_limit,
      0,
      [],
    ),
  )
}

fn expected_release(model: Model, instance_id: String) -> Option(Release) {
  case model.phase, instance_id == model.backup.instance_id {
    Preparing(target), True
    | Draining(target), True
    | HandoffCaptured(target), True
    -> Some(target)
    _, _ if instance_id == model.primary.instance_id ->
      Some(model.primary.release)
    _, _ if instance_id == model.backup.instance_id ->
      Some(model.backup.release)
    _, _ -> None
  }
}

fn readiness_valid(
  evidence: ReadinessEvidence,
  release: Release,
) -> Result(Nil, EvolutionError) {
  use _ <- result.try(
    case
      evidence.candidate_revision == release.candidate_revision
      && evidence.artifact_sha256 == release.artifact_sha256
      && clock_valid(evidence.clock)
      && evidence.observed_boot_us >= 0
      && evidence.expires_boot_us > evidence.observed_boot_us
    {
      True -> Ok(Nil)
      False -> Error(ReadinessMismatch(evidence.instance_id))
    },
  )
  case evidence.clock_guard {
    GuardHealthy(sequence) if sequence > 0 -> Ok(Nil)
    _ -> Error(ClockGuardNotHealthy(evidence.instance_id))
  }
}

/// Convert an observed clock-guard snapshot into candidate-bound readiness.
/// Missing reports, faults, future readings, stale readings, and invalid TTLs
/// all remain unhealthy. This adapter performs no publication or action.
pub fn readiness_from_clock_guard(
  instance_id: String,
  release: Release,
  state: guard.State,
  now_boot_us: Int,
  readiness_ttl_us: Int,
) -> Result(ReadinessEvidence, EvolutionError) {
  case state.previous {
    Some(reading) -> {
      let clock.Reading(domain, _, observed_boot_us) = reading
      let clock.Domain(host_id, boot_id) = domain
      case
        state.sequence > 0
        && list.is_empty(state.last_faults)
        && now_boot_us >= observed_boot_us
        && readiness_ttl_us > 0
        && readiness_ttl_us <= 3_600_000_000
        && now_boot_us - observed_boot_us <= readiness_ttl_us
      {
        False -> Error(ClockGuardNotHealthy(instance_id))
        True ->
          Ok(ReadinessEvidence(
            instance_id,
            release.candidate_revision,
            release.artifact_sha256,
            ClockDomain(host_id, boot_id),
            observed_boot_us,
            observed_boot_us + readiness_ttl_us,
            GuardHealthy(state.sequence),
          ))
      }
    }
    None -> Error(ClockGuardNotHealthy(instance_id))
  }
}

fn ready_for(replica: Replica, release: Release) -> Bool {
  case replica.readiness {
    Some(evidence) -> readiness_valid(evidence, release) == Ok(Nil)
    None -> False
  }
}

fn ready_for_fence(
  replica: Replica,
  release: Release,
  fence: WriterFence,
) -> Result(Nil, EvolutionError) {
  case replica.readiness {
    None -> Error(ReplicaNotReady(replica.instance_id))
    Some(evidence) -> {
      use _ <- result.try(readiness_valid(evidence, release))
      use _ <- result.try(case evidence.clock == fence.clock {
        True -> Ok(Nil)
        False ->
          Error(FenceMismatch(
            "readiness and writer fence use different clock domains",
          ))
      })
      case
        fence.observed_boot_us >= evidence.observed_boot_us
        && fence.observed_boot_us < evidence.expires_boot_us
      {
        True -> Ok(Nil)
        False -> Error(ReplicaNotReady(replica.instance_id))
      }
    }
  }
}

fn set_replica_readiness(
  replica: Replica,
  release: Release,
  evidence: ReadinessEvidence,
) -> Replica {
  Replica(..replica, release: release, readiness: Some(evidence))
}

fn add_audit(
  model: Model,
  label: String,
  instance: String,
  epoch: Int,
) -> Model {
  let sequence = model.transition_sequence + 1
  Model(
    ..model,
    transition_sequence: sequence,
    audit: [AuditEvent(sequence, label, instance, epoch), ..model.audit]
      |> list.take(128),
  )
}

fn check_new_fence(
  model: Model,
  fence: WriterFence,
  expected_holder: String,
) -> Result(Nil, EvolutionError) {
  use _ <- result.try(
    case
      fence_valid(fence)
      && fence.resource == model.resource
      && fence.holder == expected_holder
    {
      True -> Ok(Nil)
      False -> Error(FenceMismatch("resource or holder does not match"))
    },
  )
  case fence.epoch > model.epoch_high_water {
    True -> Ok(Nil)
    False -> Error(StaleWriterEpoch(fence.epoch, model.epoch_high_water))
  }
}

fn replica_by_id(model: Model, instance_id: String) -> Option(Replica) {
  case
    instance_id == model.primary.instance_id,
    instance_id == model.backup.instance_id
  {
    True, _ -> Some(model.primary)
    _, True -> Some(model.backup)
    _, _ -> None
  }
}

fn promote_target(
  model: Model,
  target: Replica,
  other: Replica,
  fence: WriterFence,
  phase: Phase,
) -> Model {
  Model(
    ..model,
    primary: Replica(..target, role: ServingWriter(fence.epoch)),
    backup: Replica(..other, role: WarmObserver),
    writer: Some(fence),
    phase: phase,
    epoch_high_water: fence.epoch,
  )
}

pub fn transition(model: Model, event: Event) -> Result(Model, EvolutionError) {
  case event {
    BeginUpgrade(target) ->
      case release_valid(target) {
        False -> Error(InvalidConfiguration("invalid target release"))
        True ->
          case model.phase {
            Stable | RollbackComplete(_) ->
              Ok(
                Model(..model, phase: Preparing(target))
                |> add_audit("begin_upgrade", model.backup.instance_id, 0),
              )
            _ -> Error(InvalidTransition("upgrade already in progress"))
          }
      }
    ObserveReadiness(evidence) ->
      case expected_release(model, evidence.instance_id) {
        None -> Error(ReadinessMismatch(evidence.instance_id))
        Some(release) -> {
          use _ <- result.try(readiness_valid(evidence, release))
          let next = case evidence.instance_id == model.primary.instance_id {
            True ->
              Model(
                ..model,
                primary: set_replica_readiness(model.primary, release, evidence),
              )
            False ->
              Model(
                ..model,
                backup: set_replica_readiness(model.backup, release, evidence),
              )
          }
          Ok(add_audit(next, "readiness", evidence.instance_id, 0))
        }
      }
    StartDrain(instance, epoch) ->
      case model.phase, model.writer {
        Preparing(target), Some(writer)
          if instance == model.primary.instance_id
          && writer.holder == instance
          && writer.epoch == epoch
        ->
          case ready_for(model.backup, target) {
            True ->
              Ok(
                Model(
                  ..model,
                  primary: Replica(..model.primary, role: DrainingWriter(epoch)),
                  phase: Draining(target),
                )
                |> add_audit("drain", instance, epoch),
              )
            False -> Error(ReplicaNotReady(model.backup.instance_id))
          }
        _, _ -> Error(InvalidTransition("drain requires the current writer"))
      }
    CaptureHandoff(envelope) ->
      case model.phase {
        Draining(target) -> {
          use _ <- result.try(case envelope.version == target.state_version {
            True -> Ok(Nil)
            False -> Error(UnsupportedStateVersion(envelope.version))
          })
          use _ <- result.try(case durable_state_valid(envelope.state) {
            True -> Ok(Nil)
            False -> Error(StateRegression("handoff state is invalid"))
          })
          use _ <- result.try(
            case state_progresses(model.durable_state, envelope.state) {
              True -> Ok(Nil)
              False ->
                Error(StateRegression(
                  "counters, journal cursor, or resource epochs regressed",
                ))
            },
          )
          Ok(
            Model(
              ..model,
              durable_state: envelope.state,
              phase: HandoffCaptured(target),
            )
            |> add_audit("handoff", model.primary.instance_id, 0),
          )
        }
        _ -> Error(InvalidTransition("handoff requires a drained primary"))
      }
    Promote(fence) ->
      case model.phase {
        HandoffCaptured(target) -> {
          use _ <- result.try(check_new_fence(
            model,
            fence,
            model.backup.instance_id,
          ))
          use _ <- result.try(ready_for_fence(model.backup, target, fence))
          Ok(
            promote_target(
              model,
              model.backup,
              model.primary,
              fence,
              Verifying(target, model.primary.instance_id),
            )
            |> add_audit("promote", fence.holder, fence.epoch),
          )
        }
        WriterLost(_) -> {
          use target <- result.try(case replica_by_id(model, fence.holder) {
            Some(replica) -> Ok(replica)
            None -> Error(ReplicaNotReady(fence.holder))
          })
          use _ <- result.try(check_new_fence(model, fence, target.instance_id))
          use _ <- result.try(ready_for_fence(target, target.release, fence))
          let other = case target.instance_id == model.primary.instance_id {
            True -> model.backup
            False -> model.primary
          }
          Ok(
            promote_target(
              model,
              target,
              other,
              fence,
              Verifying(target.release, other.instance_id),
            )
            |> add_audit("failover_promote", fence.holder, fence.epoch),
          )
        }
        _ ->
          Error(InvalidTransition("promotion requires handoff or lease loss"))
      }
    ConfirmTraffic(instance, epoch) ->
      case model.phase, model.writer {
        Verifying(_, _), Some(fence)
          if fence.holder == instance
          && fence.epoch == epoch
          && model.primary.instance_id == instance
        ->
          Ok(
            Model(..model, phase: Stable)
            |> add_audit("traffic_confirmed", instance, epoch),
          )
        _, _ -> Error(InvalidTransition("traffic confirmation is not fenced"))
      }
    LeaseLost(instance, epoch, reason) ->
      case model.writer {
        Some(fence) if fence.holder == instance && fence.epoch == epoch ->
          Ok(
            Model(
              ..model,
              primary: Replica(..model.primary, role: UnfencedObserver),
              backup: Replica(..model.backup, role: WarmObserver),
              writer: None,
              phase: WriterLost(reason),
            )
            |> add_audit("lease_lost", instance, epoch),
          )
        _ -> Error(FenceMismatch("lease loss does not match current writer"))
      }
    Rollback(fence, reason) ->
      case model.phase {
        Verifying(_, previous_primary) -> {
          use _ <- result.try(
            case model.rollback_attempts < model.rollback_limit {
              True -> Ok(Nil)
              False -> Error(RollbackLimitReached(model.rollback_limit))
            },
          )
          use target <- result.try(case replica_by_id(model, previous_primary) {
            Some(replica) -> Ok(replica)
            None -> Error(ReplicaNotReady(previous_primary))
          })
          use _ <- result.try(check_new_fence(model, fence, previous_primary))
          use _ <- result.try(ready_for_fence(target, target.release, fence))
          let other = case target.instance_id == model.primary.instance_id {
            True -> model.backup
            False -> model.primary
          }
          Ok(
            promote_target(
              Model(..model, rollback_attempts: model.rollback_attempts + 1),
              target,
              other,
              fence,
              RollbackComplete(reason),
            )
            |> add_audit("rollback", previous_primary, fence.epoch),
          )
        }
        _ -> Error(InvalidTransition("rollback requires a verifying release"))
      }
  }
}

pub type InstanceConfig {
  InstanceConfig(
    instance_id: String,
    role: ReplicaRole,
    release: Release,
    writer: Option(WriterFence),
    heartbeat_ms: Int,
  )
}

pub type InstanceHeartbeat {
  InstanceHeartbeat(
    instance_id: String,
    sequence: Int,
    role: ReplicaRole,
    release: Release,
    writer: Option(WriterFence),
    readiness: Option(ReadinessEvidence),
    last_error: Option(String),
  )
}

pub type InstanceMessage {
  Tick
  Snapshot(Subject(InstanceHeartbeat))
  Configure(
    role: ReplicaRole,
    release: Release,
    writer: Option(WriterFence),
    reply: Subject(Result(Nil, String)),
  )
  Stop
}

type InstanceRuntime {
  InstanceRuntime(
    heartbeat: InstanceHeartbeat,
    heartbeat_ms: Int,
    probe: fn() -> Result(ReadinessEvidence, String),
    self: Subject(InstanceMessage),
  )
}

fn instance_config_valid(config: InstanceConfig) -> Bool {
  let writer_matches = case config.role, config.writer {
    ServingWriter(epoch), Some(fence) ->
      fence_valid(fence)
      && fence.holder == config.instance_id
      && fence.epoch == epoch
    DrainingWriter(epoch), Some(fence) ->
      fence_valid(fence)
      && fence.holder == config.instance_id
      && fence.epoch == epoch
    WarmObserver, None | UnfencedObserver, None -> True
    _, _ -> False
  }
  bounded(config.instance_id, 128)
  && release_valid(config.release)
  && config.heartbeat_ms >= 50
  && config.heartbeat_ms <= 60_000
  && writer_matches
}

pub fn start_instance(
  config: InstanceConfig,
  probe: fn() -> Result(ReadinessEvidence, String),
) -> Result(actor.Started(Subject(InstanceMessage)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(self) {
    case instance_config_valid(config) {
      False -> Error("invalid live evolution instance")
      True -> {
        process.send_after(self, config.heartbeat_ms, Tick)
        Ok(
          actor.initialised(InstanceRuntime(
            InstanceHeartbeat(
              config.instance_id,
              0,
              config.role,
              config.release,
              config.writer,
              None,
              None,
            ),
            config.heartbeat_ms,
            probe,
            self,
          ))
          |> actor.returning(self),
        )
      }
    }
  })
  |> actor.on_message(handle_instance)
  |> actor.start
}

pub fn instance_child_spec(
  config: InstanceConfig,
  probe: fn() -> Result(ReadinessEvidence, String),
) -> ChildSpecification(Subject(InstanceMessage)) {
  supervision.worker(fn() { start_instance(config, probe) })
}

fn probe_heartbeat(runtime: InstanceRuntime) -> InstanceHeartbeat {
  let current = runtime.heartbeat
  case runtime.probe() {
    Error(reason) ->
      InstanceHeartbeat(
        ..current,
        sequence: current.sequence + 1,
        readiness: None,
        last_error: Some(reason),
      )
    Ok(evidence) ->
      case
        evidence.instance_id == current.instance_id
        && readiness_valid(evidence, current.release) == Ok(Nil)
      {
        True ->
          InstanceHeartbeat(
            ..current,
            sequence: current.sequence + 1,
            readiness: Some(evidence),
            last_error: None,
          )
        False ->
          InstanceHeartbeat(
            ..current,
            sequence: current.sequence + 1,
            readiness: None,
            last_error: Some(
              "readiness probe did not bind instance and release",
            ),
          )
      }
  }
}

fn handle_instance(
  runtime: InstanceRuntime,
  message: InstanceMessage,
) -> actor.Next(InstanceRuntime, InstanceMessage) {
  case message {
    Tick -> {
      let heartbeat = probe_heartbeat(runtime)
      process.send_after(runtime.self, runtime.heartbeat_ms, Tick)
      actor.continue(InstanceRuntime(..runtime, heartbeat: heartbeat))
    }
    Snapshot(reply) -> {
      process.send(reply, runtime.heartbeat)
      actor.continue(runtime)
    }
    Configure(role, release, writer, reply) -> {
      let config =
        InstanceConfig(
          runtime.heartbeat.instance_id,
          role,
          release,
          writer,
          runtime.heartbeat_ms,
        )
      case instance_config_valid(config) {
        False -> {
          process.send(reply, Error("invalid live evolution instance update"))
          actor.continue(runtime)
        }
        True -> {
          process.send(reply, Ok(Nil))
          actor.continue(
            InstanceRuntime(
              ..runtime,
              heartbeat: InstanceHeartbeat(
                config.instance_id,
                runtime.heartbeat.sequence,
                role,
                release,
                writer,
                None,
                None,
              ),
            ),
          )
        }
      }
    }
    Stop -> actor.stop()
  }
}

pub fn heartbeat_json(heartbeat: InstanceHeartbeat) -> Json {
  let role = case heartbeat.role {
    ServingWriter(_) -> "serving-writer"
    WarmObserver -> "warm-observer"
    DrainingWriter(_) -> "draining-writer"
    UnfencedObserver -> "unfenced-observer"
  }
  json.object([
    #("schema", json.string(schema)),
    #("instance_id", json.string(heartbeat.instance_id)),
    #("sequence", json.int(heartbeat.sequence)),
    #("role", json.string(role)),
    #("candidate_revision", json.string(heartbeat.release.candidate_revision)),
    #("artifact_sha256", json.string(heartbeat.release.artifact_sha256)),
    #("ready", json.bool(heartbeat.readiness != None)),
    #("writer", json.bool(heartbeat.writer != None)),
    #(
      "authority",
      json.string(
        "observer only; traffic and writes require external fence check",
      ),
    ),
  ])
}

pub fn allowed_modules() -> List(String) {
  ["clock_guard", "coord", "live_evolution", "manager"]
}

@external(erlang, "live_evolution_ffi", "loaded_artifact")
pub fn loaded_artifact(label: String) -> Result(#(String, String), String)

@external(erlang, "live_evolution_ffi", "verify_artifact")
pub fn verify_artifact(
  artifact_root: String,
  label: String,
  expected_sha256: String,
) -> Result(String, String)

@external(erlang, "live_evolution_ffi", "load_verified")
pub fn load_verified(
  artifact_root: String,
  label: String,
  expected_sha256: String,
) -> Result(String, String)

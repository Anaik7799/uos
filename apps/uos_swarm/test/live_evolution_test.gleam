import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should
import uos_swarm/clock_contract as clock
import uos_swarm/clock_guard as guard
import uos_swarm/live_evolution as evolution

const resource = "runtime:cockpit-4100"

const old_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

const new_digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

fn old_release() -> evolution.Release {
  evolution.Release("candidate-old", old_digest, 1)
}

fn new_release() -> evolution.Release {
  evolution.Release("candidate-new", new_digest, 1)
}

fn durable_state() -> evolution.DurableState {
  evolution.DurableStateV1(
    [
      evolution.Counter("requests", 91),
      evolution.Counter("accepted", 80),
    ],
    44,
    [
      evolution.ResourceEpoch(resource, 7),
      evolution.ResourceEpoch("journal:swarm", 12),
    ],
    "state-snapshot:44",
  )
}

fn fence(
  holder: String,
  epoch: Int,
  observed_boot_us: Int,
  expires_boot_us: Int,
) -> evolution.WriterFence {
  evolution.WriterFence(
    resource,
    holder,
    epoch,
    evolution.ClockDomain("nas-1", "boot-a"),
    observed_boot_us,
    expires_boot_us,
  )
}

fn initial() -> evolution.Model {
  evolution.new(
    resource,
    "primary-a",
    "backup-b",
    old_release(),
    fence("primary-a", 7, 100, 10_000),
    durable_state(),
    2,
  )
  |> should.be_ok
}

fn healthy_ready(instance: String, release: evolution.Release) {
  evolution.ReadinessEvidence(
    instance,
    release.candidate_revision,
    release.artifact_sha256,
    evolution.ClockDomain("nas-1", "boot-a"),
    500,
    1000,
    evolution.GuardHealthy(3),
  )
}

fn prepare_backup(model: evolution.Model) -> evolution.Model {
  model
  |> evolution.transition(evolution.BeginUpgrade(new_release()))
  |> should.be_ok
  |> evolution.transition(
    evolution.ObserveReadiness(healthy_ready("backup-b", new_release())),
  )
  |> should.be_ok
}

pub fn primary_and_warm_backup_start_with_one_fenced_writer_test() {
  let model = initial()
  model.primary.role |> should.equal(evolution.ServingWriter(7))
  model.backup.role |> should.equal(evolution.WarmObserver)
  model.writer
  |> should.equal(Some(fence("primary-a", 7, 100, 10_000)))
  model.durable_state |> should.equal(durable_state())
}

pub fn readiness_is_bound_to_instance_candidate_digest_and_clock_guard_test() {
  let preparing =
    initial()
    |> evolution.transition(evolution.BeginUpgrade(new_release()))
    |> should.be_ok
  preparing
  |> evolution.transition(
    evolution.ObserveReadiness(healthy_ready("backup-b", old_release())),
  )
  |> should.equal(Error(evolution.ReadinessMismatch("backup-b")))
  let unknown =
    evolution.ReadinessEvidence(
      "backup-b",
      "candidate-new",
      new_digest,
      evolution.ClockDomain("nas-1", "boot-a"),
      500,
      1000,
      evolution.GuardUnknown("clock source unavailable"),
    )
  preparing
  |> evolution.transition(evolution.ObserveReadiness(unknown))
  |> should.equal(Error(evolution.ClockGuardNotHealthy("backup-b")))
}

pub fn upgrade_handoff_preserves_counters_journal_and_resource_epochs_test() {
  let state = durable_state()
  let upgraded =
    initial()
    |> prepare_backup
    |> evolution.transition(evolution.StartDrain("primary-a", 7))
    |> should.be_ok
    |> evolution.transition(
      evolution.CaptureHandoff(evolution.HandoffEnvelope(1, state)),
    )
    |> should.be_ok
    |> evolution.transition(
      evolution.Promote(fence("backup-b", 8, 600, 20_000)),
    )
    |> should.be_ok
    |> evolution.transition(evolution.ConfirmTraffic("backup-b", 8))
    |> should.be_ok
  upgraded.primary.instance_id |> should.equal("backup-b")
  upgraded.primary.release |> should.equal(new_release())
  upgraded.primary.role |> should.equal(evolution.ServingWriter(8))
  upgraded.backup.instance_id |> should.equal("primary-a")
  upgraded.backup.release |> should.equal(old_release())
  upgraded.backup.role |> should.equal(evolution.WarmObserver)
  upgraded.durable_state |> should.equal(state)
  upgraded.epoch_high_water |> should.equal(8)
}

pub fn stale_or_duplicate_writer_epoch_cannot_promote_backup_test() {
  let ready =
    initial()
    |> prepare_backup
    |> evolution.transition(evolution.StartDrain("primary-a", 7))
    |> should.be_ok
    |> evolution.transition(
      evolution.CaptureHandoff(evolution.HandoffEnvelope(1, durable_state())),
    )
    |> should.be_ok
  ready
  |> evolution.transition(evolution.Promote(fence("backup-b", 7, 600, 20_000)))
  |> should.equal(Error(evolution.StaleWriterEpoch(7, 7)))
}

pub fn lease_loss_removes_writer_and_failover_needs_fresh_readiness_test() {
  let lost =
    initial()
    |> evolution.transition(evolution.LeaseLost("primary-a", 7, "expired"))
    |> should.be_ok
  lost.writer |> should.equal(None)
  lost.primary.role |> should.equal(evolution.UnfencedObserver)
  lost
  |> evolution.transition(evolution.Promote(fence("backup-b", 8, 600, 20_000)))
  |> should.equal(Error(evolution.ReplicaNotReady("backup-b")))
}

pub fn rollback_is_bounded_and_returns_traffic_to_retained_old_release_test() {
  let verifying =
    initial()
    |> prepare_backup
    |> evolution.transition(evolution.StartDrain("primary-a", 7))
    |> should.be_ok
    |> evolution.transition(
      evolution.CaptureHandoff(evolution.HandoffEnvelope(1, durable_state())),
    )
    |> should.be_ok
    |> evolution.transition(
      evolution.Promote(fence("backup-b", 8, 600, 20_000)),
    )
    |> should.be_ok
  let old_ready = healthy_ready("primary-a", old_release())
  let rolled_back =
    verifying
    |> evolution.transition(evolution.ObserveReadiness(old_ready))
    |> should.be_ok
    |> evolution.transition(evolution.Rollback(
      fence("primary-a", 9, 700, 30_000),
      "candidate health regression",
    ))
    |> should.be_ok
  rolled_back.primary.instance_id |> should.equal("primary-a")
  rolled_back.primary.release |> should.equal(old_release())
  rolled_back.rollback_attempts |> should.equal(1)
  rolled_back.durable_state |> should.equal(durable_state())
  rolled_back
  |> evolution.transition(evolution.Rollback(
    fence("backup-b", 10, 800, 40_000),
    "second",
  ))
  |> should.be_error
}

pub fn incompatible_handoff_requires_a_supported_state_version_test() {
  prepare_backup(initial())
  |> evolution.transition(evolution.StartDrain("primary-a", 7))
  |> should.be_ok
  |> evolution.transition(
    evolution.CaptureHandoff(evolution.HandoffEnvelope(2, durable_state())),
  )
  |> should.equal(Error(evolution.UnsupportedStateVersion(2)))
}

pub fn two_runtime_instances_heartbeat_but_only_primary_advertises_writer_test() {
  let primary_config =
    evolution.InstanceConfig(
      "primary-a",
      evolution.ServingWriter(7),
      old_release(),
      Some(fence("primary-a", 7, 100, 10_000)),
      50,
    )
  let backup_config =
    evolution.InstanceConfig(
      "backup-b",
      evolution.WarmObserver,
      old_release(),
      None,
      50,
    )
  let primary =
    evolution.start_instance(primary_config, fn() {
      Ok(healthy_ready("primary-a", old_release()))
    })
    |> should.be_ok
  let backup =
    evolution.start_instance(backup_config, fn() {
      Ok(healthy_ready("backup-b", old_release()))
    })
    |> should.be_ok
  process.send(primary.data, evolution.Tick)
  process.send(backup.data, evolution.Tick)
  let primary_reply = process.new_subject()
  let backup_reply = process.new_subject()
  process.send(primary.data, evolution.Snapshot(primary_reply))
  process.send(backup.data, evolution.Snapshot(backup_reply))
  let primary_heartbeat = process.receive(primary_reply, 1000) |> should.be_ok
  let backup_heartbeat = process.receive(backup_reply, 1000) |> should.be_ok
  primary_heartbeat.sequence |> should.equal(1)
  backup_heartbeat.sequence |> should.equal(1)
  primary_heartbeat.writer
  |> should.equal(Some(fence("primary-a", 7, 100, 10_000)))
  backup_heartbeat.writer |> should.equal(None)
  process.send(primary.data, evolution.Stop)
  process.send(backup.data, evolution.Stop)
}

pub fn loader_allowlist_and_digest_verification_are_fixed_test() {
  evolution.allowed_modules()
  |> should.equal(["clock_guard", "coord", "live_evolution", "manager"])
  let #(root, digest) = evolution.loaded_artifact("manager") |> should.be_ok
  evolution.verify_artifact(root, "manager", digest) |> should.be_ok
  evolution.verify_artifact(root, "manager", old_digest) |> should.be_error
  evolution.verify_artifact(root, "not-allowlisted", digest) |> should.be_error
}

pub fn readiness_adapter_requires_a_fresh_fault_free_clock_guard_report_test() {
  let reading = clock.Reading(clock.Domain("nas-1", "boot-a"), 500, 500)
  let sample =
    guard.Sample(clock.Evidence(reading, "chronyc", True, 1, 1, 0), reading)
  let healthy =
    guard.audit(
      guard.new(guard.strict_config(), 0),
      Ok(sample),
      Ok(guard.BoardSnapshot([], [])),
    )
  evolution.readiness_from_clock_guard(
    "backup-b",
    new_release(),
    healthy,
    550,
    100,
  )
  |> should.equal(
    Ok(evolution.ReadinessEvidence(
      "backup-b",
      "candidate-new",
      new_digest,
      evolution.ClockDomain("nas-1", "boot-a"),
      500,
      600,
      evolution.GuardHealthy(1),
    )),
  )
  evolution.readiness_from_clock_guard(
    "backup-b",
    new_release(),
    guard.new(guard.strict_config(), 0),
    550,
    100,
  )
  |> should.equal(Error(evolution.ClockGuardNotHealthy("backup-b")))
  evolution.readiness_from_clock_guard(
    "backup-b",
    new_release(),
    healthy,
    499,
    100,
  )
  |> should.equal(Error(evolution.ClockGuardNotHealthy("backup-b")))
}

pub fn promotion_rejects_expired_readiness_and_cross_clock_fence_test() {
  let ready =
    initial()
    |> prepare_backup
    |> evolution.transition(evolution.StartDrain("primary-a", 7))
    |> should.be_ok
    |> evolution.transition(
      evolution.CaptureHandoff(evolution.HandoffEnvelope(1, durable_state())),
    )
    |> should.be_ok
  ready
  |> evolution.transition(evolution.Promote(fence("backup-b", 8, 1001, 20_000)))
  |> should.equal(Error(evolution.ReplicaNotReady("backup-b")))
  ready
  |> evolution.transition(
    evolution.Promote(evolution.WriterFence(
      resource,
      "backup-b",
      8,
      evolution.ClockDomain("nas-1", "boot-other"),
      600,
      20_000,
    )),
  )
  |> should.equal(
    Error(evolution.FenceMismatch(
      "readiness and writer fence use different clock domains",
    )),
  )
}

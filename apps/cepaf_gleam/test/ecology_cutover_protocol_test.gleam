//// Pure model controls; fabricated grants below confer no live authority.

import cepaf_gleam/ecology/cutover_protocol as p
import cepaf_gleam/mcp/admission as a
import cepaf_gleam/mcp/principal
import cepaf_gleam/mcp/types
import gleam/dict
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

const digest = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

const other = "sha256:2222222222222222222222222222222222222222222222222222222222222222"

fn range(low: Int, high: Int) -> List(Int) {
  case low > high {
    True -> []
    False -> [low, ..range(low + 1, high)]
  }
}

fn transaction(count: Int) -> p.Transaction {
  let assert Ok(t) = p.new(digest, digest, other, digest, count, 7, execution())
  t
}

fn execution() -> p.ExecutionBinding {
  p.ExecutionBinding("plan", "OI02", "worker", 1, "/fixture", "runtime-owner")
}

fn succeed(t: p.Transaction) -> p.Transaction {
  let assert Ok(command) = p.next(t)
  let observation = case command {
    p.StageFiles -> p.Prepared(digest, p.physical_count(t))
    p.VerifyCandidate -> p.Verified(digest)
    p.VerifyPrevious -> p.Verified(other)
    _ -> p.Succeeded
  }
  let assert Ok(next) = p.observe(t, ack(t, command, observation))
  next
}

fn fail(t: p.Transaction) -> p.Transaction {
  let assert Ok(command) = p.next(t)
  let assert Ok(next) = p.observe(t, ack(t, command, p.Failed))
  next
}

fn walk(t: p.Transaction, steps: Int) -> p.Transaction {
  case steps {
    0 -> t
    _ -> walk(succeed(t), steps - 1)
  }
}

fn ack(
  t: p.Transaction,
  command: p.Command,
  observation: p.Observation,
) -> p.Acknowledgement {
  p.Acknowledgement(
    digest,
    digest,
    p.epoch(t),
    p.generation(t),
    command,
    observation,
  )
}

pub fn success_requires_all_files_verification_and_reader_resume_test() {
  list.each([14, 15], fn(count) {
    let t = walk(transaction(count), count + 2)
    p.phase(t) |> should.equal(p.CheckingCandidate)
    p.phase(succeed(t)) |> should.equal(p.ResumingCandidate)
    let done = walk(t, 2)
    p.phase(done) |> should.equal(p.Committed)
    p.next(done) |> should.equal(Error("TRANSACTION_TERMINAL"))
  })
}

pub fn every_partial_rename_and_failed_health_restores_the_entire_set_test() {
  list.each([14, 15], fn(count) {
    list.each(range(0, count), fn(applied) {
      let partial = walk(transaction(count), 2 + applied)
      let rollback = fail(partial)
      p.next(rollback) |> should.equal(Ok(p.RestoreFile(count - 1)))
      let verified = walk(rollback, count)
      p.phase(verified) |> should.equal(p.CheckingPrevious)
      p.phase(succeed(verified)) |> should.equal(p.ResumingPrevious)
      p.phase(walk(verified, 2)) |> should.equal(p.RolledBack)
    })
  })
}

pub fn acknowledgement_order_and_failed_recovery_fail_closed_test() {
  let t = transaction(14)
  p.observe(t, ack(t, p.ReplaceFile(0), p.Succeeded))
  |> should.equal(Error("OUT_OF_ORDER_ACKNOWLEDGEMENT"))
  p.phase(fail(t)) |> should.equal(p.RecoveryHeld)
  p.phase(fail(succeed(t))) |> should.equal(p.RecoveryHeld)
  let assert Ok(recovering) = p.recover(walk(t, 7), 8)
  p.next(recovering) |> should.equal(Ok(p.FenceReaders))
  let held = fail(recovering)
  p.phase(held) |> should.equal(p.RecoveryHeld)
  p.next(held) |> should.equal(Error("RECOVERY_REQUIRES_RECONCILIATION"))
  p.phase(fail(walk(t, 17))) |> should.equal(p.RecoveryHeld)
  p.recover(walk(t, 18), 8) |> should.equal(Error("TRANSACTION_TERMINAL"))
  p.recover(walk(recovering, 17), 9)
  |> should.equal(Error("TRANSACTION_TERMINAL"))
  p.recover(t, 7) |> should.equal(Error("RECOVERY_REQUIRES_NEW_EPOCH"))
  p.recover(t, 6) |> should.equal(Error("RECOVERY_REQUIRES_NEW_EPOCH"))
  p.recover(t, 8) |> should.equal(Error("BACKUP_SET_NOT_VERIFIED"))
  p.recover(fail(t), 8) |> should.equal(Error("BACKUP_SET_NOT_VERIFIED"))
}

pub fn transaction_binding_rejects_invalid_inventory_and_epoch_test() {
  list.each([0, 11, 13, 16, 100], fn(count) {
    p.new(digest, digest, other, digest, count, 7, execution())
    |> should.equal(Error("INVALID_CUTOVER_BINDING"))
  })
  p.new(digest, digest, other, digest, 14, 0, execution())
  |> should.equal(Error("INVALID_CUTOVER_BINDING"))
  p.new("not-a-digest", digest, other, digest, 14, 7, execution())
  |> should.equal(Error("INVALID_CUTOVER_BINDING"))
}

fn task() -> a.TaskFence {
  a.TaskFence(
    "plan",
    "OI02",
    "worker",
    1,
    a.TaskExecuting,
    10_000,
    Some(a.GrantTicket(
      "grant",
      types.ReleaseAuthority,
      False,
      10_000,
      "/fixture",
    )),
  )
}

fn context() -> a.AdmissionContext {
  a.AdmissionContext(
    principal.from_launcher_env(
      "worker",
      types.ClientProfile("codex"),
      "/fixture",
      "test",
    ),
    a.EnforcedMode,
    100,
    "/fixture",
    Some(task()),
  )
}

fn call(t: p.Transaction) -> a.ValidatedCall {
  let assert Ok(command) = p.next(t)
  let spec =
    types.ToolSpec(
      "private_test",
      "cutover",
      "model only",
      p.family(t),
      "OI02",
      1,
      json.object([]),
      digest,
      types.ControlActuation,
      "model",
      1000,
    )
  let assert Ok(call) =
    a.admit(
      context(),
      spec,
      dict.from_list([
        #("transaction_id", digest),
        #("candidate", digest),
        #("manifest", digest),
        #("runtime_epoch", int.to_string(p.epoch(t))),
        #("generation", int.to_string(p.generation(t))),
        #("command", p.command_key(command)),
      ]),
    )
  call
}

fn runtime() -> p.RuntimeObservation {
  p.RuntimeObservation(
    digest,
    digest,
    digest,
    7,
    "runtime-owner",
    100,
    10_000,
    True,
    True,
    True,
  )
}

fn authorize(
  t: p.Transaction,
  task: a.TaskFence,
  runtime: p.RuntimeObservation,
  now: Int,
) -> Result(p.Command, String) {
  p.authorize_next(
    t,
    context(),
    call(t),
    fn() { Some(task) },
    fn() { now },
    fn() { runtime },
  )
}

pub fn effect_time_reuses_admission_and_binds_original_attempt_and_grant_test() {
  let t = walk(transaction(14), 2)
  authorize(t, task(), runtime(), 100) |> should.equal(Ok(p.ReplaceFile(0)))
  authorize(t, a.TaskFence(..task(), attempt: 2), runtime(), 100)
  |> should.equal(Error("RELEASE_CALL_BINDING_MISMATCH"))
  authorize(t, a.TaskFence(..task(), lease_until_ms: 100), runtime(), 100)
  |> should.equal(Error("TASK_LEASE_EXPIRED"))
  authorize(t, a.TaskFence(..task(), grant: None), runtime(), 100)
  |> should.equal(Error("MISSING_AUTHORITY_GRANT"))
  let assert Some(grant) = task().grant
  authorize(
    t,
    a.TaskFence(
      ..task(),
      grant: Some(a.GrantTicket(..grant, scope: types.ControlMutation)),
    ),
    runtime(),
    100,
  )
  |> should.equal(Error("RELEASE_CALL_BINDING_MISMATCH"))
  authorize(
    t,
    a.TaskFence(..task(), grant: Some(a.GrantTicket(..grant, revoked: True))),
    runtime(),
    100,
  )
  |> should.equal(Error("GRANT_REVOKED_AT_EFFECT_TIME"))
}

pub fn stale_future_mismatched_unadmitted_or_unfenced_runtime_refuses_test() {
  let t = walk(transaction(14), 2)
  let r = runtime()
  let bad = [
    p.RuntimeObservation(..r, candidate: other),
    p.RuntimeObservation(..r, manifest: other),
    p.RuntimeObservation(..r, transaction_id: other),
    p.RuntimeObservation(..r, epoch: 6),
    p.RuntimeObservation(..r, owner: "foreign-owner"),
    p.RuntimeObservation(..r, observed_ms: -1),
    p.RuntimeObservation(..r, observed_ms: 101),
    p.RuntimeObservation(..r, lease_until_ms: 100),
    p.RuntimeObservation(..r, source_and_risk_current: False),
    p.RuntimeObservation(..r, ingress_admitted: False),
  ]
  list.each(bad, fn(observation) {
    authorize(t, task(), observation, 100)
    |> should.equal(Error("RUNTIME_OBSERVATION_NOT_AUTHORITATIVE"))
  })
  authorize(t, task(), r, 1101)
  |> should.equal(Error("RUNTIME_OBSERVATION_NOT_AUTHORITATIVE"))
  authorize(
    t,
    task(),
    p.RuntimeObservation(..r, all_readers_fenced: False),
    100,
  )
  |> should.equal(Error("READERS_NOT_FENCED"))
}

pub fn every_data_effect_and_resume_requires_reader_fence_test() {
  let t = transaction(14)
  let r = p.RuntimeObservation(..runtime(), all_readers_fenced: False)
  authorize(t, task(), r, 100) |> should.equal(Ok(p.StageFiles))
  authorize(succeed(t), task(), r, 100) |> should.equal(Ok(p.FenceReaders))
  list.each(range(2, 17), fn(step) {
    authorize(walk(t, step), task(), r, 100)
    |> should.equal(Error("READERS_NOT_FENCED"))
  })
  let assert Ok(recovering) = p.recover(succeed(t), 8)
  let r = p.RuntimeObservation(..r, epoch: 8)
  list.each(range(1, 16), fn(step) {
    authorize(walk(recovering, step), task(), r, 100)
    |> should.equal(Error("READERS_NOT_FENCED"))
  })
}

pub fn old_command_and_epoch_cannot_be_reused_for_recovery_test() {
  let t = walk(transaction(14), 2)
  let old_call = call(t)
  let assert Ok(recovering) = p.recover(t, 8)
  let r = p.RuntimeObservation(..runtime(), epoch: 8)
  p.authorize_next(
    recovering,
    context(),
    old_call,
    fn() { Some(task()) },
    fn() { 100 },
    fn() { r },
  )
  |> should.equal(Error("RELEASE_CALL_BINDING_MISMATCH"))
  authorize(recovering, task(), runtime(), 100)
  |> should.equal(Error("RUNTIME_OBSERVATION_NOT_AUTHORITATIVE"))
  authorize(recovering, task(), r, 100) |> should.equal(Ok(p.FenceReaders))
  authorize(succeed(recovering), task(), r, 100)
  |> should.equal(Ok(p.RestoreFile(13)))
  p.authorize_next(
    succeed(t),
    context(),
    old_call,
    fn() { Some(task()) },
    fn() { 100 },
    fn() { runtime() },
  )
  |> should.equal(Error("RELEASE_CALL_BINDING_MISMATCH"))
}

pub fn acknowledgement_binding_and_verification_identity_controls_test() {
  let t = transaction(14)
  let good = ack(t, p.StageFiles, p.Prepared(digest, 14))
  list.each(
    [
      p.Acknowledgement(..good, transaction_id: other),
      p.Acknowledgement(..good, manifest: other),
      p.Acknowledgement(..good, generation: 1),
      p.Acknowledgement(..good, epoch: 6),
    ],
    fn(bad) {
      p.observe(t, bad)
      |> should.equal(Error("STALE_OR_FOREIGN_ACKNOWLEDGEMENT"))
    },
  )
  p.observe(t, ack(t, p.StageFiles, p.Succeeded))
  |> should.equal(Error("OBSERVATION_EVIDENCE_REQUIRED"))
  p.observe(t, ack(t, p.StageFiles, p.Prepared(other, 14)))
  |> should.equal(Error("OBSERVATION_BINDING_MISMATCH"))
  p.observe(t, ack(t, p.StageFiles, p.Prepared(digest, 15)))
  |> should.equal(Error("OBSERVATION_BINDING_MISMATCH"))
  let staged = succeed(t)
  p.observe(staged, good)
  |> should.equal(Error("STALE_OR_FOREIGN_ACKNOWLEDGEMENT"))
  let candidate_check = walk(t, 16)
  p.observe(
    candidate_check,
    ack(candidate_check, p.VerifyCandidate, p.Verified(other)),
  )
  |> should.equal(Error("OBSERVATION_BINDING_MISMATCH"))
  let previous_check = walk(fail(candidate_check), 14)
  p.observe(
    previous_check,
    ack(previous_check, p.VerifyPrevious, p.Verified(digest)),
  )
  |> should.equal(Error("OBSERVATION_BINDING_MISMATCH"))
  let assert Ok(recovering) = p.recover(staged, 8)
  p.observe(recovering, ack(staged, p.FenceReaders, p.Succeeded))
  |> should.equal(Error("STALE_OR_FOREIGN_ACKNOWLEDGEMENT"))
}

//// T24 staged-release and rollback rehearsal verification.
////
//// These tests exercise the in-memory rehearsal primitives only. They do not
//// deploy anything, do not mutate the host, and never admit the system.

import cepaf_gleam/mcp/adapters/planning_read
import cepaf_gleam/mcp/admission
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/receipts
import cepaf_gleam/mcp/release_rehearsal
import cepaf_gleam/mcp/types.{
  type AuthorityScope, type ToolError, AuditOnly, Complete, ControlMutation,
  EvidenceRecord, ReleaseAuthority, TaskScopedMutation,
}
import gleeunit/should

const previous_candidate = "sha256:1111111111111111111111111111111111111111111111111111111111111111"

const rollback_commit_locator = "b5dfbe78d0fec1211ba08c0f3bb019fbb4c573ae"

const now_ms = 1_000_000

const canary_lease_until_ms = 8_000_000

const rollback_lease_until_ms = 8_500_000

fn sample_tasks() -> List(planning_read.CanonicalTaskRow) {
  [
    planning_read.CanonicalTaskRow(
      plan_id: "20261029-1913-mcp-server-completion",
      task_id: "T23",
      title: "Final Dev Acceptance",
      state: "completed",
      worker: "pi-session-20261030",
      attempt: 1,
    ),
    planning_read.CanonicalTaskRow(
      plan_id: "20261029-1913-mcp-server-completion",
      task_id: "T24",
      title: "Staged Release and Rollback Rehearsal",
      state: "executing",
      worker: "pi-session-20261030",
      attempt: 1,
    ),
  ]
}

fn committed_ledger(candidate: String) -> receipts.ReceiptLedger {
  let ledger = receipts.new_ledger(candidate)
  let intent_id = "t24-intent-001"
  let payload_hash =
    receipts.hash_payload("sa_task_complete", [
      #("plan_id", "20261029-1913-mcp-server-completion"),
      #("task_id", "T23"),
    ])
  let assert Ok(recorded) =
    receipts.record_intent(
      ledger,
      intent_id: intent_id,
      route: "public",
      tool: "sa_task_complete",
      payload_hash: payload_hash,
    )
  receipts.mark_complete(
    recorded,
    intent_id: intent_id,
    outcome: Complete(
      "completed",
      EvidenceRecord(
        candidate: candidate,
        route: "public",
        tool: "sa_task_complete",
        declaration_state: "declared",
        implementation_state: "implemented",
        execution_state: "observed",
        formal_state: "unrun",
        admission_state: "not_admitted",
        output_sha256: "0",
      ),
    ),
  )
}

fn snapshot() -> release_rehearsal.ReleaseSnapshot {
  release_rehearsal.ReleaseSnapshot(
    snapshot_id: "snap-t24",
    previous_candidate: previous_candidate,
    rollback_commit_locator: rollback_commit_locator,
    compatible_tasks: sample_tasks(),
    ledger: committed_ledger(previous_candidate),
    runtime_lease: release_rehearsal.RuntimeLease(
      service_id: "c3i-gleam-server",
      owner_id: "owner-v1",
      epoch: 1,
      lease_until_ms: canary_lease_until_ms,
    ),
  )
}

fn grant(scope: AuthorityScope, revoked: Bool) -> admission.GrantTicket {
  admission.GrantTicket(
    grant_id: "grant-t24",
    scope: scope,
    revoked: revoked,
    expires_at_ms: canary_lease_until_ms,
    workspace_root: "/home/an/NAS-setup/uos",
  )
}

fn attempt_cutover(
  scope: AuthorityScope,
  revoked: Bool,
  next_candidate: String,
  next_epoch: Int,
) -> Result(release_rehearsal.StagedCanaryState, ToolError) {
  release_rehearsal.stage_canary_cutover(
    grant: grant(scope, revoked),
    now_ms: now_ms,
    snapshot: snapshot(),
    next_candidate: next_candidate,
    next_commit_locator: "candidate-t24-cutover",
    next_owner: "owner-v2",
    next_epoch: next_epoch,
    next_lease_until_ms: canary_lease_until_ms,
  )
}

fn assert_refused(
  result: Result(release_rehearsal.StagedCanaryState, ToolError),
  expected_code: String,
) -> Nil {
  case result {
    Ok(_) -> should.fail()
    Error(err) -> err.code |> should.equal(expected_code)
  }
}

pub fn rollback_restores_compatible_tasks_and_receipts_test() {
  let snap = snapshot()
  let assert Ok(canary) =
    attempt_cutover(ReleaseAuthority, False, candidate_id.current(), 2)

  // Mutate canary tasks and receipts away from the snapshot, then simulate a
  // canary that has exhausted its restart budget.
  let mutated_canary =
    release_rehearsal.StagedCanaryState(
      ..canary,
      tasks: [],
      ledger: receipts.new_ledger("canary-mutated-candidate"),
    )
  let degraded =
    release_rehearsal.StagedCanaryState(..mutated_canary, restart_count: 4)

  case release_rehearsal.evaluate_canary_health(degraded, max_errors: 0) {
    Ok(_) -> should.fail()
    Error(err) ->
      err.code
      |> should.equal("RESTART_BUDGET_EXHAUSTED_ROLLBACK_REQUIRED")
  }

  let assert Ok(rolled_back) =
    release_rehearsal.rollback_to_snapshot(
      degraded,
      snap,
      rollback_owner: "owner-rollback",
      rollback_lease_until_ms: rollback_lease_until_ms,
      now_ms: now_ms,
    )

  rolled_back.tasks |> should.equal(snap.compatible_tasks)
  rolled_back.ledger |> should.equal(snap.ledger)
  rolled_back.active_candidate |> should.equal(snap.previous_candidate)
  rolled_back.commit_locator |> should.equal(rollback_commit_locator)
  rolled_back.runtime_lease.epoch |> should.equal(3)
  rolled_back.system_admission |> should.equal("NOT_ADMITTED")
}

pub fn old_runtime_cannot_resume_after_lease_loss_test() {
  let snap = snapshot()
  let assert Ok(canary) =
    attempt_cutover(ReleaseAuthority, False, candidate_id.current(), 2)

  case release_rehearsal.fence_runtime_effect(canary, "owner-v1", 1, now_ms) {
    Ok(_) -> should.fail()
    Error(err) -> err.code |> should.equal("STALE_RUNTIME_EPOCH_FENCED")
  }

  let assert Ok(_) =
    release_rehearsal.fence_runtime_effect(canary, "owner-v2", 2, now_ms)

  let assert Ok(rolled_back) =
    release_rehearsal.rollback_to_snapshot(
      canary,
      snap,
      rollback_owner: "owner-rollback",
      rollback_lease_until_ms: rollback_lease_until_ms,
      now_ms: now_ms,
    )

  case
    release_rehearsal.fence_runtime_effect(rolled_back, "owner-v1", 1, now_ms)
  {
    Ok(_) -> should.fail()
    Error(err) -> err.code |> should.equal("STALE_RUNTIME_EPOCH_FENCED")
  }

  case
    release_rehearsal.fence_runtime_effect(rolled_back, "owner-v2", 2, now_ms)
  {
    Ok(_) -> should.fail()
    Error(err) -> err.code |> should.equal("STALE_RUNTIME_EPOCH_FENCED")
  }

  case
    release_rehearsal.fence_runtime_effect(
      rolled_back,
      "owner-rollback",
      3,
      rollback_lease_until_ms,
    )
  {
    Ok(_) -> should.fail()
    Error(err) -> err.code |> should.equal("RUNTIME_LEASE_EXPIRED")
  }
}

pub fn cutover_refused_without_explicit_release_authority_test() {
  let candidate = candidate_id.current()

  assert_refused(
    attempt_cutover(TaskScopedMutation, False, candidate, 2),
    "RELEASE_AUTHORITY_REQUIRED",
  )
  assert_refused(
    attempt_cutover(ControlMutation, False, candidate, 2),
    "RELEASE_AUTHORITY_REQUIRED",
  )
  assert_refused(
    attempt_cutover(AuditOnly, False, candidate, 2),
    "RELEASE_AUTHORITY_REQUIRED",
  )
  assert_refused(
    attempt_cutover(ReleaseAuthority, True, candidate, 2),
    "RELEASE_GRANT_INACTIVE",
  )
  assert_refused(
    attempt_cutover(ReleaseAuthority, False, "uos-mcp", 2),
    "INVALID_RELEASE_CANDIDATE",
  )
  assert_refused(
    attempt_cutover(ReleaseAuthority, False, candidate, 1),
    "NON_MONOTONIC_RUNTIME_EPOCH",
  )
}

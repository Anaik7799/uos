//// T24 Staged-release and rollback rehearsal primitives.
////
//// This module is a purely in-memory rehearsal harness for a separately
//// authorized staged release. It encodes the two invariants that must hold
//// before any live cutover may be attempted: (1) a staged canary cutover
//// requires an explicit, unexpired `ReleaseAuthority` grant and a real
//// six-source SHA-256 candidate digest, and (2) once a runtime lease epoch has
//// advanced (including by rollback) every prior owner/epoch is fenced out.
////
//// The module performs no host deployment, writes no service state, and never
//// admits the system on its own: `system_admission` stays `"NOT_ADMITTED"`.

import cepaf_gleam/mcp/adapters/planning_read.{type CanonicalTaskRow}
import cepaf_gleam/mcp/admission.{type GrantTicket}
import cepaf_gleam/mcp/candidate_id
import cepaf_gleam/mcp/receipts.{type ReceiptLedger}
import cepaf_gleam/mcp/types.{
  type ToolError, NonRetryable, ReleaseAuthority, ToolError,
}

pub type RuntimeLease {
  RuntimeLease(
    service_id: String,
    owner_id: String,
    epoch: Int,
    lease_until_ms: Int,
  )
}

pub type ReleaseSnapshot {
  ReleaseSnapshot(
    snapshot_id: String,
    previous_candidate: String,
    rollback_commit_locator: String,
    compatible_tasks: List(CanonicalTaskRow),
    ledger: ReceiptLedger,
    runtime_lease: RuntimeLease,
  )
}

pub type StagedCanaryState {
  StagedCanaryState(
    active_candidate: String,
    commit_locator: String,
    tasks: List(CanonicalTaskRow),
    ledger: ReceiptLedger,
    runtime_lease: RuntimeLease,
    canary_window_ms: Int,
    error_count: Int,
    restart_count: Int,
    restart_budget: Int,
    system_admission: String,
  )
}

pub const default_canary_window_ms = 1_800_000

fn authority_error(code: String, reason: String) -> ToolError {
  ToolError(code: code, reason: reason, retryability: NonRetryable)
}

pub fn stage_canary_cutover(
  grant grant: GrantTicket,
  now_ms now_ms: Int,
  snapshot snapshot: ReleaseSnapshot,
  next_candidate next_candidate: String,
  next_commit_locator next_commit_locator: String,
  next_owner next_owner: String,
  next_epoch next_epoch: Int,
  next_lease_until_ms next_lease_until_ms: Int,
) -> Result(StagedCanaryState, ToolError) {
  case grant.revoked || grant.expires_at_ms <= now_ms {
    True ->
      Error(authority_error(
        "RELEASE_GRANT_INACTIVE",
        "Release grant is revoked or expired",
      ))
    False ->
      case grant.scope == ReleaseAuthority {
        False ->
          Error(authority_error(
            "RELEASE_AUTHORITY_REQUIRED",
            "Staged release cutover requires explicit ReleaseAuthority scope",
          ))
        True ->
          case candidate_id.is_sha256_digest(next_candidate) {
            False ->
              Error(authority_error(
                "INVALID_RELEASE_CANDIDATE",
                "Release candidate must carry a valid 6-source SHA-256 digest",
              ))
            True ->
              case
                next_epoch > snapshot.runtime_lease.epoch
                && next_lease_until_ms > now_ms
                && next_owner != ""
              {
                False ->
                  Error(authority_error(
                    "NON_MONOTONIC_RUNTIME_EPOCH",
                    "Runtime cutover requires monotonic epoch and unexpired owner lease",
                  ))
                True ->
                  Ok(StagedCanaryState(
                    active_candidate: next_candidate,
                    commit_locator: next_commit_locator,
                    tasks: snapshot.compatible_tasks,
                    ledger: snapshot.ledger,
                    runtime_lease: RuntimeLease(
                      service_id: snapshot.runtime_lease.service_id,
                      owner_id: next_owner,
                      epoch: next_epoch,
                      lease_until_ms: next_lease_until_ms,
                    ),
                    canary_window_ms: default_canary_window_ms,
                    error_count: 0,
                    restart_count: 0,
                    restart_budget: 3,
                    system_admission: "NOT_ADMITTED",
                  ))
              }
          }
      }
  }
}

pub fn fence_runtime_effect(
  state state: StagedCanaryState,
  caller_owner caller_owner: String,
  caller_epoch caller_epoch: Int,
  now_ms now_ms: Int,
) -> Result(RuntimeLease, ToolError) {
  case
    caller_epoch < state.runtime_lease.epoch
    || caller_owner != state.runtime_lease.owner_id
  {
    True ->
      Error(authority_error(
        "STALE_RUNTIME_EPOCH_FENCED",
        "Old or non-owning runtime instance cannot resume effects after lease transition",
      ))
    False ->
      case caller_epoch > state.runtime_lease.epoch {
        True ->
          Error(authority_error(
            "UNCOMMITTED_FUTURE_EPOCH",
            "Caller epoch exceeds committed runtime state",
          ))
        False ->
          case state.runtime_lease.lease_until_ms <= now_ms {
            True ->
              Error(authority_error(
                "RUNTIME_LEASE_EXPIRED",
                "Runtime owner lease has expired",
              ))
            False ->
              case state.restart_count > state.restart_budget {
                True ->
                  Error(authority_error(
                    "RESTART_BUDGET_EXHAUSTED_ROLLBACK_REQUIRED",
                    "Canary restart budget exhausted; rollback required",
                  ))
                False -> Ok(state.runtime_lease)
              }
          }
      }
  }
}

pub fn evaluate_canary_health(
  state state: StagedCanaryState,
  max_errors max_errors: Int,
) -> Result(Nil, ToolError) {
  case candidate_id.is_sha256_digest(state.active_candidate) {
    False ->
      Error(authority_error(
        "CANARY_CANDIDATE_INVALID",
        "Canary active candidate is not a valid six-source SHA-256 digest",
      ))
    True ->
      case state.restart_count > state.restart_budget {
        True ->
          Error(authority_error(
            "RESTART_BUDGET_EXHAUSTED_ROLLBACK_REQUIRED",
            "Canary restart budget exhausted; rollback required",
          ))
        False ->
          case state.error_count > max_errors {
            True ->
              Error(authority_error(
                "CANARY_ERROR_BUDGET_EXCEEDED",
                "Canary error count exceeds the allowed error budget",
              ))
            False -> Ok(Nil)
          }
      }
  }
}

pub fn rollback_to_snapshot(
  state state: StagedCanaryState,
  snapshot snapshot: ReleaseSnapshot,
  rollback_owner rollback_owner: String,
  rollback_lease_until_ms rollback_lease_until_ms: Int,
  now_ms now_ms: Int,
) -> Result(StagedCanaryState, ToolError) {
  case rollback_lease_until_ms <= now_ms || rollback_owner == "" {
    True ->
      Error(authority_error(
        "INVALID_ROLLBACK_LEASE",
        "Rollback requires an unexpired lease and a non-empty owner",
      ))
    False ->
      Ok(StagedCanaryState(
        active_candidate: snapshot.previous_candidate,
        commit_locator: snapshot.rollback_commit_locator,
        tasks: snapshot.compatible_tasks,
        ledger: snapshot.ledger,
        runtime_lease: RuntimeLease(
          service_id: state.runtime_lease.service_id,
          owner_id: rollback_owner,
          epoch: state.runtime_lease.epoch + 1,
          lease_until_ms: rollback_lease_until_ms,
        ),
        canary_window_ms: state.canary_window_ms,
        error_count: 0,
        restart_count: 0,
        restart_budget: state.restart_budget,
        system_admission: "NOT_ADMITTED",
      ))
  }
}

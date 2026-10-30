//// T17 negotiated MCP durable task extension. Durable handles are projected
//// strictly onto the canonical Sa-plan task record; there is no alternate
//// in-memory scheduler. A handle may only be issued after Sa-plan persistence
//// is confirmed, and a cancellation ACK never claims the effect has stopped
//// until an explicit worker stop receipt is recorded.

import cepaf_gleam/harness/files
import cepaf_gleam/mcp/principal.{type Principal}
import cepaf_gleam/mcp/types.{
  type ProtocolProfile, type ToolError, Modern20260728, NonRetryable, ToolError,
}
import gleam/dict.{type Dict}
import gleam/int
import gleam/result
import gleam/string

pub const max_task_handles = 1024

pub type SaTaskState {
  PendingTask
  RunningTask
  CancelRequested
  CancelledStopped
  CompletedTask
  FailedTask
}

/// Canonical Sa-plan task record. This is the only durable authority for a
/// task's existence; the library never maintains a parallel scheduler.
pub type SaPlanTaskRecord {
  SaPlanTaskRecord(
    plan_id: String,
    task_id: String,
    owner_actor: String,
    attempt: Int,
    persisted_in_sa_plan: Bool,
    lifecycle: SaTaskState,
  )
}

pub type DurableTaskHandle {
  DurableTaskHandle(
    handle_id: String,
    plan_id: String,
    task_id: String,
    owner_actor: String,
    attempt: Int,
    expires_at_ms: Int,
  )
}

pub type CancelReceipt {
  CancelReceipt(
    handle_id: String,
    cancel_acknowledged: Bool,
    effect_stopped: Bool,
  )
}

pub type StopConfirmation {
  StopConfirmation(
    handle_id: String,
    stop_receipt_digest: String,
    effect_stopped: Bool,
    lifecycle: SaTaskState,
  )
}

pub type TaskExtensionStore {
  TaskExtensionStore(records: Dict(String, SaPlanTaskRecord))
}

pub fn empty_store() -> TaskExtensionStore {
  TaskExtensionStore(dict.new())
}

pub fn size(store: TaskExtensionStore) -> Int {
  dict.size(store.records)
}

pub fn has_handle(store: TaskExtensionStore, handle_id: String) -> Bool {
  dict.has_key(store.records, handle_id)
}

pub fn register(
  store: TaskExtensionStore,
  handle_id: String,
  record: SaPlanTaskRecord,
) -> TaskExtensionStore {
  TaskExtensionStore(dict.insert(store.records, handle_id, record))
}

pub fn lookup(
  store: TaskExtensionStore,
  handle_id: String,
) -> Result(SaPlanTaskRecord, ToolError) {
  dict.get(store.records, handle_id)
  |> result.map_error(fn(_) {
    ToolError(
      "TASK_HANDLE_NOT_FOUND",
      "No durable task handle registered with id " <> handle_id,
      NonRetryable,
    )
  })
}

/// The durable extension is only available on the modern profile and only when
/// explicitly negotiated. The handle is returned only after the Sa-plan
/// persisted flag, owner binding, and future expiry have all been verified.
pub fn issue_durable_handle(
  profile: ProtocolProfile,
  extension_negotiated: Bool,
  principal: Principal,
  record: SaPlanTaskRecord,
  expires_at_ms: Int,
  now_ms: Int,
) -> Result(DurableTaskHandle, ToolError) {
  case profile == Modern20260728 && extension_negotiated {
    False ->
      Error(ToolError(
        "TASK_EXTENSION_NOT_NEGOTIATED",
        "Durable task extension requires the modern profile and explicit negotiation",
        NonRetryable,
      ))
    True ->
      case record.persisted_in_sa_plan {
        False ->
          Error(ToolError(
            "UNPERSISTED_TASK_HANDLE_FORBIDDEN",
            "Durable task handles may only be issued after Sa-plan persistence is confirmed",
            NonRetryable,
          ))
        True ->
          case record.owner_actor == principal.actor_id(principal) {
            False ->
              Error(ToolError(
                "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN",
                "Task record is owned by another principal",
                NonRetryable,
              ))
            True ->
              case expires_at_ms > now_ms {
                False ->
                  Error(ToolError(
                    "TASK_HANDLE_EXPIRED",
                    "Durable task handle expiry must be in the future",
                    NonRetryable,
                  ))
                True ->
                  Ok(DurableTaskHandle(
                    handle_id: record.plan_id
                      <> ":"
                      <> record.task_id
                      <> ":"
                      <> int.to_string(record.attempt),
                    plan_id: record.plan_id,
                    task_id: record.task_id,
                    owner_actor: record.owner_actor,
                    attempt: record.attempt,
                    expires_at_ms: expires_at_ms,
                  ))
              }
          }
      }
  }
}

/// Returns the digest the worker must present to prove it stopped the effect
/// for a given handle attempt and candidate stop receipt.
pub fn expected_stop_receipt_digest(
  handle_id: String,
  attempt: Int,
  candidate: String,
) -> String {
  files.digest(
    "stop|" <> handle_id <> "|" <> int.to_string(attempt) <> "|" <> candidate,
  )
}

/// Transitions `RunningTask` to `CancelRequested` and returns an acknowledgement
/// only. The acknowledgement deliberately never sets `effect_stopped`. The
/// calling principal must own the task handle.
pub fn request_cancel(
  store: TaskExtensionStore,
  principal: Principal,
  handle_id: String,
) -> Result(#(CancelReceipt, TaskExtensionStore), ToolError) {
  use record <- result.try(lookup(store, handle_id))
  case record.owner_actor == principal.actor_id(principal) {
    False ->
      Error(ToolError(
        "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN",
        "Task record is owned by another principal",
        NonRetryable,
      ))
    True ->
      case record.lifecycle {
        RunningTask -> {
          let receipt =
            CancelReceipt(
              handle_id: handle_id,
              cancel_acknowledged: True,
              effect_stopped: False,
            )
          let updated = SaPlanTaskRecord(..record, lifecycle: CancelRequested)
          Ok(#(receipt, register(store, handle_id, updated)))
        }
        _ ->
          Error(ToolError(
            "TASK_CANCEL_INVALID_STATE",
            "Only a running task may be cancelled",
            NonRetryable,
          ))
      }
  }
}

/// Transitions `CancelRequested` to `CancelledStopped` and only then reports
/// `effect_stopped: True`. The calling principal must own the task handle and
/// the presented digest must match the expected stop receipt digest.
pub fn confirm_worker_stopped(
  store: TaskExtensionStore,
  principal: Principal,
  handle_id: String,
  candidate: String,
  stop_receipt_digest: String,
) -> Result(#(StopConfirmation, TaskExtensionStore), ToolError) {
  use record <- result.try(lookup(store, handle_id))
  case record.owner_actor == principal.actor_id(principal) {
    False ->
      Error(ToolError(
        "CROSS_PRINCIPAL_TASK_HANDLE_FORBIDDEN",
        "Task record is owned by another principal",
        NonRetryable,
      ))
    True ->
      case record.lifecycle {
        CancelRequested ->
          case string.trim(stop_receipt_digest) {
            "" ->
              Error(ToolError(
                "EMPTY_STOP_RECEIPT",
                "A non-empty worker stop receipt digest is required",
                NonRetryable,
              ))
            digest ->
              case
                digest
                == expected_stop_receipt_digest(
                  handle_id,
                  record.attempt,
                  candidate,
                )
              {
                False ->
                  Error(ToolError(
                    "INVALID_STOP_RECEIPT_DIGEST",
                    "Worker stop receipt digest does not match the expected digest",
                    NonRetryable,
                  ))
                True -> {
                  let confirmation =
                    StopConfirmation(
                      handle_id: handle_id,
                      stop_receipt_digest: digest,
                      effect_stopped: True,
                      lifecycle: CancelledStopped,
                    )
                  let updated =
                    SaPlanTaskRecord(..record, lifecycle: CancelledStopped)
                  Ok(#(confirmation, register(store, handle_id, updated)))
                }
              }
          }
        _ ->
          Error(ToolError(
            "TASK_STOP_INVALID_STATE",
            "Worker stop may only be confirmed after a cancel request",
            NonRetryable,
          ))
      }
  }
}

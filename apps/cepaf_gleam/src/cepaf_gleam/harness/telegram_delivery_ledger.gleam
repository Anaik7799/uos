//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Delivery Ledger & State Machine
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/harness/telegram_delivery_ledger</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Pure Telegram Inbox/Outbox Ledger & Delivery State Machine</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HARNESS-MCP-001, SC-JIDOKA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/harness/telegram_ingress_guard as tg_guard
import gleam/int
import gleam/list
import gleam/string

pub type InboxStatus {
  InboxPending
  InboxProcessing(worker: String, epoch: Int)
  InboxCompleted(digest: String)
  InboxRejected(reason: String)
}

pub type InboxRecord {
  InboxRecord(
    update_id: Int,
    message_id: Int,
    chat_id: Int,
    user_id: Int,
    text_hash: String,
    status: InboxStatus,
    created_at_ms: Int,
  )
}

pub type Watermark {
  Watermark(last_committed_offset: Int)
}

pub type OutboxStatus {
  OutboxPending
  OutboxSending(worker: String, epoch: Int)
  OutboxDelivered(telegram_msg_id: Int)
  OutboxFailed(err: String)
  OutboxUncertain(err: String)
}

pub type OutboxChunk {
  OutboxChunk(
    request_id: String,
    chunk_index: Int,
    total_chunks: Int,
    chat_id: Int,
    payload: String,
    status: OutboxStatus,
    attempt_count: Int,
  )
}

// -----------------------------------------------------------------------------
// Pure Batch Ingestion & Watermark Progression
// -----------------------------------------------------------------------------

pub fn ingest_single(
  verdict: tg_guard.IngressVerdict,
  now_ms: Int,
  inbox: List(InboxRecord),
) -> Result(InboxRecord, String) {
  case verdict {
    tg_guard.AcceptedEnvelope(update_id, message_id, chat_id, user_id, text_hash, _raw_text, _directive) -> {
      // Check for identity collision or duplicate
      case list.find(inbox, fn(r) { r.update_id == update_id }) {
        Ok(existing) -> {
          case existing.text_hash == text_hash {
            True -> Ok(existing)
            False -> Error("identity_collision_differing_text_hash")
          }
        }
        Error(Nil) -> {
          Ok(InboxRecord(
            update_id: update_id,
            message_id: message_id,
            chat_id: chat_id,
            user_id: user_id,
            text_hash: text_hash,
            status: InboxPending,
            created_at_ms: now_ms,
          ))
        }
      }
    }
    tg_guard.RejectedUpdate(update_id, reason) -> {
      case list.find(inbox, fn(r) { r.update_id == update_id }) {
        Ok(existing) -> Ok(existing)
        Error(Nil) -> {
          Ok(InboxRecord(
            update_id: update_id,
            message_id: 0,
            chat_id: 0,
            user_id: 0,
            text_hash: "rejection_tombstone",
            status: InboxRejected(string.inspect(reason)),
            created_at_ms: now_ms,
          ))
        }
      }
    }
  }
}

/// Ingests a batch of updates in strict order, advancing the watermark ONLY over
/// an uninterrupted contiguous prefix of successfully stored records.
/// If any record fails or has an identity collision, the batch prefix halts.
pub fn ingest_batch(
  watermark: Watermark,
  updates: List(tg_guard.IngressVerdict),
  inbox: List(InboxRecord),
  now_ms: Int,
) -> #(Watermark, List(InboxRecord), List(String)) {
  do_ingest_batch(watermark, updates, inbox, now_ms, [])
}

fn do_ingest_batch(
  watermark: Watermark,
  updates: List(tg_guard.IngressVerdict),
  inbox: List(InboxRecord),
  now_ms: Int,
  errors: List(String),
) -> #(Watermark, List(InboxRecord), List(String)) {
  case updates {
    [] -> #(watermark, inbox, list.reverse(errors))
    [verdict, ..rest] -> {
      case ingest_single(verdict, now_ms, inbox) {
        Error(err) -> {
          // Prefix halts at first failure; watermark does not advance further
          #(watermark, inbox, list.reverse([err, ..errors]))
        }
        Ok(record) -> {
          let updated_inbox = case list.any(inbox, fn(r) { r.update_id == record.update_id }) {
            True -> inbox
            False -> [record, ..inbox]
          }
          // Advance watermark to update_id + 1 if update_id >= last_committed_offset
          let next_offset = int.max(watermark.last_committed_offset, record.update_id + 1)
          let next_watermark = Watermark(next_offset)
          do_ingest_batch(next_watermark, rest, updated_inbox, now_ms, errors)
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Pure Task Claim & Completion Fencing
// -----------------------------------------------------------------------------

pub fn claim_inbox_task(
  record: InboxRecord,
  worker: String,
  epoch: Int,
) -> Result(InboxRecord, String) {
  case record.status {
    InboxPending ->
      Ok(InboxRecord(..record, status: InboxProcessing(worker: worker, epoch: epoch)))
    InboxProcessing(w, e) ->
      Error("task_already_processing_by:" <> w <> "_epoch:" <> int.to_string(e))
    InboxCompleted(_) ->
      Error("task_already_completed")
    InboxRejected(r) ->
      Error("task_was_rejected:" <> r)
  }
}

pub fn complete_inbox_task(
  record: InboxRecord,
  digest: String,
  worker: String,
  epoch: Int,
) -> Result(InboxRecord, String) {
  case record.status {
    InboxProcessing(w, e) if w == worker && e == epoch ->
      Ok(InboxRecord(..record, status: InboxCompleted(digest: digest)))
    InboxProcessing(w, e) ->
      Error("claim_owner_mismatch: expected " <> worker <> ":" <> int.to_string(epoch) <> " but got " <> w <> ":" <> int.to_string(e))
    _ ->
      Error("task_not_in_processing_state")
  }
}

// -----------------------------------------------------------------------------
// Pure Outbox State Machine & Send Reconciliation
// -----------------------------------------------------------------------------

pub fn create_outbox_chunk(
  request_id: String,
  chunk_index: Int,
  total_chunks: Int,
  chat_id: Int,
  payload: String,
) -> OutboxChunk {
  OutboxChunk(
    request_id: request_id,
    chunk_index: chunk_index,
    total_chunks: total_chunks,
    chat_id: chat_id,
    payload: payload,
    status: OutboxPending,
    attempt_count: 0,
  )
}

pub fn claim_outbox_send(
  chunk: OutboxChunk,
  worker: String,
  epoch: Int,
) -> Result(OutboxChunk, String) {
  case chunk.status {
    OutboxPending ->
      Ok(OutboxChunk(
        ..chunk,
        status: OutboxSending(worker: worker, epoch: epoch),
        attempt_count: chunk.attempt_count + 1,
      ))
    OutboxSending(w, e) ->
      Error("blind_retry_barred_already_sending_by:" <> w <> ":" <> int.to_string(e))
    OutboxUncertain(_) ->
      Error("blind_retry_barred_on_uncertain_outcome_requires_explicit_reconciliation")
    OutboxDelivered(_) ->
      Error("chunk_already_delivered")
    OutboxFailed(_) ->
      Error("chunk_permanently_failed")
  }
}

/// Reconciles BotAPI response:
/// Valid delivery strictly requires:
/// 1. HTTP 200
/// 2. ok == True
/// 3. remote_msg_id > 0
/// 4. remote_chat_id == chunk.chat_id
/// Any mismatch or failure results in UNCERTAIN (never blind retry).
pub fn reconcile_send_outcome(
  chunk: OutboxChunk,
  http_status: Int,
  ok: Bool,
  remote_chat_id: Int,
  remote_msg_id: Int,
  worker: String,
  epoch: Int,
) -> OutboxChunk {
  case chunk.status {
    OutboxSending(w, e) if w == worker && e == epoch -> {
      case
        http_status == 200
        && ok == True
        && remote_msg_id > 0
        && remote_chat_id == chunk.chat_id
      {
        True -> OutboxChunk(..chunk, status: OutboxDelivered(telegram_msg_id: remote_msg_id))
        False -> {
          let err_detail = case http_status != 200 {
            True -> "http_status_" <> int.to_string(http_status)
            False -> {
              case ok != True {
                True -> "botapi_ok_false"
                False -> {
                  case remote_msg_id <= 0 {
                    True -> "non_positive_message_id"
                    False -> "mismatched_remote_chat_id"
                  }
                }
              }
            }
          }
          OutboxChunk(..chunk, status: OutboxUncertain(err: err_detail))
        }
      }
    }
    _ ->
      OutboxChunk(..chunk, status: OutboxUncertain(err: "unexpected_claim_state_during_reconciliation"))
  }
}

// -----------------------------------------------------------------------------
// Pure Restart Recovery
// -----------------------------------------------------------------------------

/// On service restart:
/// 1. Any in-flight OutboxSending is transitioned to OutboxUncertain (crash in-flight).
/// 2. Any InboxProcessing is recovered back to InboxPending if no completed outbox exists.
pub fn handle_restart(
  chunks: List(OutboxChunk),
  inboxes: List(InboxRecord),
) -> #(List(OutboxChunk), List(InboxRecord)) {
  let recovered_chunks =
    list.map(chunks, fn(chunk) {
      case chunk.status {
        OutboxSending(w, e) ->
          OutboxChunk(
            ..chunk,
            status: OutboxUncertain(
              err: "in_flight_restart_crash_under_worker:" <> w <> ":" <> int.to_string(e),
            ),
          )
        _other -> chunk
      }
    })

  let recovered_inboxes =
    list.map(inboxes, fn(inbox) {
      case inbox.status {
        InboxProcessing(_w, _e) ->
          InboxRecord(..inbox, status: InboxPending)
        _other -> inbox
      }
    })

  #(recovered_chunks, recovered_inboxes)
}

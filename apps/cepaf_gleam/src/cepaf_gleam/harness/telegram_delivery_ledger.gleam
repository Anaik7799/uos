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

pub const max_queue_capacity = 1000
pub const max_chunk_payload_bytes = 4096

pub type InboxStatus {
  InboxPending
  InboxProcessing(worker: String, epoch: Int)
  InboxCompleted(digest: String)
  InboxRejected(reason: String)
  InboxHold(reason: String)
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
    bot_id: Int,
    request_id: String,
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

pub fn make_request_id(update_id: Int) -> String {
  "req-tg-" <> int.to_string(update_id)
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
    tg_guard.AcceptedEnvelope(
      update_id,
      message_id,
      chat_id,
      user_id,
      text_hash,
      _raw_text,
      _directive,
      bot_id,
    ) -> {
      case list.find(inbox, fn(r) { r.update_id == update_id }) {
        Ok(existing) -> {
          // Idempotency requires complete equality across all envelope identity coordinates
          case
            existing.message_id == message_id
            && existing.chat_id == chat_id
            && existing.user_id == user_id
            && existing.bot_id == bot_id
            && existing.text_hash == text_hash
          {
            True -> Ok(existing)
            False -> Error("identity_collision_envelope_mismatch")
          }
        }
        Error(Nil) -> {
          case list.length(inbox) >= max_queue_capacity {
            True -> Error("queue_capacity_exceeded_max_1000")
            False -> {
              Ok(InboxRecord(
                update_id: update_id,
                message_id: message_id,
                chat_id: chat_id,
                user_id: user_id,
                text_hash: text_hash,
                status: InboxPending,
                created_at_ms: now_ms,
                bot_id: bot_id,
                request_id: make_request_id(update_id),
              ))
            }
          }
        }
      }
    }
    tg_guard.RejectedUpdate(update_id, reason) -> {
      let reason_str = string.inspect(reason)
      case list.find(inbox, fn(r) { r.update_id == update_id }) {
        Ok(existing) -> {
          case existing.status {
            InboxRejected(r) if r == reason_str -> Ok(existing)
            _ -> Error("identity_collision_rejection_mismatch")
          }
        }
        Error(Nil) -> {
          case list.length(inbox) >= max_queue_capacity {
            True -> Error("queue_capacity_exceeded_max_1000")
            False -> {
              Ok(InboxRecord(
                update_id: update_id,
                message_id: 0,
                chat_id: 0,
                user_id: 0,
                text_hash: "rejection_tombstone",
                status: InboxRejected(reason_str),
                created_at_ms: now_ms,
                bot_id: 0,
                request_id: make_request_id(update_id),
              ))
            }
          }
        }
      }
    }
  }
}

fn get_update_id(verdict: tg_guard.IngressVerdict) -> Int {
  case verdict {
    tg_guard.AcceptedEnvelope(update_id: uid, ..) -> uid
    tg_guard.RejectedUpdate(update_id: uid, ..) -> uid
  }
}

/// Ingests a batch of updates in strict ascending order, advancing the watermark ONLY
/// over an uninterrupted contiguous prefix of successfully stored records.
/// Batches are sorted safely by update_id before evaluation.
/// If any collision, queue overflow, or failure occurs, advancement halts immediately.
pub fn ingest_batch(
  watermark: Watermark,
  updates: List(tg_guard.IngressVerdict),
  inbox: List(InboxRecord),
  now_ms: Int,
) -> #(Watermark, List(InboxRecord), List(String)) {
  let sorted_updates =
    list.sort(updates, fn(a, b) {
      int.compare(get_update_id(a), get_update_id(b))
    })

  do_ingest_batch(watermark, sorted_updates, inbox, now_ms, [])
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
          // Prefix halts at first failure; watermark does not advance past failed update
          #(watermark, inbox, list.reverse([err, ..errors]))
        }
        Ok(record) -> {
          let updated_inbox = case list.any(inbox, fn(r) { r.update_id == record.update_id }) {
            True -> inbox
            False -> [record, ..inbox]
          }
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
  let trimmed_worker = string.trim(worker)
  case trimmed_worker == "" {
    True -> Error("worker_must_not_be_empty")
    False -> {
      case epoch <= 0 {
        True -> Error("epoch_must_be_positive")
        False -> {
          case record.status {
            InboxPending ->
              Ok(InboxRecord(..record, status: InboxProcessing(worker: trimmed_worker, epoch: epoch)))
            InboxProcessing(w, e) ->
              Error("task_already_processing_by:" <> w <> "_epoch:" <> int.to_string(e))
            InboxCompleted(_) ->
              Error("task_already_completed")
            InboxRejected(r) ->
              Error("task_was_rejected:" <> r)
            InboxHold(r) ->
              Error("task_in_hold:" <> r)
          }
        }
      }
    }
  }
}

pub fn complete_inbox_task(
  record: InboxRecord,
  digest: String,
  worker: String,
  epoch: Int,
) -> Result(InboxRecord, String) {
  let trimmed_worker = string.trim(worker)
  let trimmed_digest = string.trim(digest)
  case trimmed_worker == "" {
    True -> Error("worker_must_not_be_empty")
    False -> {
      case epoch <= 0 {
        True -> Error("epoch_must_be_positive")
        False -> {
          case trimmed_digest == "" {
            True -> Error("digest_must_not_be_empty")
            False -> {
              case record.status {
                InboxProcessing(w, e) if w == trimmed_worker && e == epoch ->
                  Ok(InboxRecord(..record, status: InboxCompleted(digest: trimmed_digest)))
                InboxProcessing(w, e) ->
                  Error("claim_owner_mismatch: expected " <> trimmed_worker <> ":" <> int.to_string(epoch) <> " but got " <> w <> ":" <> int.to_string(e))
                _ ->
                  Error("task_not_in_processing_state")
              }
            }
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Pure Outbox State Machine & Send Reconciliation
// -----------------------------------------------------------------------------

pub fn validate_chunk(chunk: OutboxChunk) -> Result(Nil, String) {
  case string.trim(chunk.request_id) == "" {
    True -> Error("request_id_must_not_be_empty")
    False -> {
      case chunk.chunk_index < 0 {
        True -> Error("chunk_index_must_be_non_negative")
        False -> {
          case chunk.total_chunks <= 0 {
            True -> Error("total_chunks_must_be_positive")
            False -> {
              case chunk.chunk_index >= chunk.total_chunks {
                True -> Error("chunk_index_out_of_bounds")
                False -> {
                  case chunk.chat_id == 0 {
                    True -> Error("chat_id_must_be_non_zero")
                    False -> {
                      case string.byte_size(chunk.payload) > max_chunk_payload_bytes {
                        True -> Error("payload_exceeds_max_4096_bytes")
                        False -> Ok(Nil)
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

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
  let trimmed_worker = string.trim(worker)
  case trimmed_worker == "" {
    True -> Error("worker_must_not_be_empty")
    False -> {
      case epoch <= 0 {
        True -> Error("epoch_must_be_positive")
        False -> {
          case validate_chunk(chunk) {
            Error(err) -> Error(err)
            Ok(Nil) -> {
              case chunk.status {
                OutboxPending ->
                  Ok(OutboxChunk(
                    ..chunk,
                    status: OutboxSending(worker: trimmed_worker, epoch: epoch),
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
          }
        }
      }
    }
  }
}

/// Reconciles BotAPI response:
/// Valid delivery strictly requires:
/// 1. HTTP 200
/// 2. ok == True
/// 3. remote_msg_id > 0
/// 4. remote_chat_id == chunk.chat_id
/// Any mismatch or failure results in UNCERTAIN (never blind retry).
/// Wrong owner/epoch or terminal states return Error with chunk state preserved unchanged.
pub fn reconcile_send_outcome(
  chunk: OutboxChunk,
  http_status: Int,
  ok: Bool,
  remote_chat_id: Int,
  remote_msg_id: Int,
  worker: String,
  epoch: Int,
) -> Result(OutboxChunk, String) {
  case chunk.status {
    OutboxDelivered(_) ->
      Error("terminal_state_already_delivered_state_unchanged")
    OutboxUncertain(_) ->
      Error("terminal_state_uncertain_state_unchanged")
    OutboxFailed(_) ->
      Error("terminal_state_failed_state_unchanged")
    OutboxPending ->
      Error("invalid_prior_state_pending_state_unchanged")
    OutboxSending(w, e) -> {
      case w == worker && e == epoch {
        False ->
          Error("owner_or_epoch_mismatch: expected " <> w <> ":" <> int.to_string(e) <> " but got " <> worker <> ":" <> int.to_string(epoch))
        True -> {
          case
            http_status == 200
            && ok == True
            && remote_msg_id > 0
            && remote_chat_id == chunk.chat_id
          {
            True ->
              Ok(OutboxChunk(..chunk, status: OutboxDelivered(telegram_msg_id: remote_msg_id)))
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
              Ok(OutboxChunk(..chunk, status: OutboxUncertain(err: err_detail)))
            }
          }
        }
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Pure Restart Recovery
// -----------------------------------------------------------------------------

/// On service restart:
/// 1. Any in-flight OutboxSending is transitioned to OutboxUncertain (crash in-flight).
/// 2. Any InboxProcessing is correlated with corresponding outbox chunks:
///    - If an outbox chunk exists and was DELIVERED, inbox is marked InboxCompleted.
///    - If an outbox chunk exists and was UNCERTAIN or SENDING, inbox is marked InboxHold.
///    - If an outbox chunk exists and was PENDING, inbox is marked InboxCompleted (result produced).
///    - If NO outbox chunk exists, inbox is marked InboxHold (missing linkage after crash).
///    In ALL cases, an interrupted processing request NEVER requeues to InboxPending.
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
        InboxProcessing(w, e) -> {
          let matching_chunk =
            list.find(recovered_chunks, fn(c) { c.request_id == inbox.request_id })
          case matching_chunk {
            Ok(chunk) -> {
              case chunk.status {
                OutboxDelivered(msg_id) ->
                  InboxRecord(..inbox, status: InboxCompleted("delivered:" <> int.to_string(msg_id)))
                OutboxUncertain(err) ->
                  InboxRecord(..inbox, status: InboxHold("uncertain_outbox:" <> err))
                OutboxSending(_, _) ->
                  InboxRecord(..inbox, status: InboxHold("in_flight_outbox_crash"))
                OutboxPending ->
                  InboxRecord(..inbox, status: InboxCompleted("outbox_pending"))
                OutboxFailed(err) ->
                  InboxRecord(..inbox, status: InboxHold("outbox_failed:" <> err))
              }
            }
            Error(Nil) -> {
              InboxRecord(
                ..inbox,
                status: InboxHold("crash_during_processing_missing_outbox:" <> w <> ":" <> int.to_string(e)),
              )
            }
          }
        }
        _other -> inbox
      }
    })

  #(recovered_chunks, recovered_inboxes)
}

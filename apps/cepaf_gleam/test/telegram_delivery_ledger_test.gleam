//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Delivery Ledger Test Suite
//// =============================================================================

import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as tg_guard
import gleeunit/should
import gleam/list

fn make_accepted(update_id: Int, hash: String) -> tg_guard.IngressVerdict {
  tg_guard.AcceptedEnvelope(
    update_id: update_id,
    message_id: update_id * 10,
    chat_id: 1001,
    user_id: 501,
    text_hash: hash,
    raw_text: "/doctor",
    directive: tg_guard.DirectReadTool("query_doctor"),
  )
}

fn make_rejected(update_id: Int) -> tg_guard.IngressVerdict {
  tg_guard.RejectedUpdate(update_id, tg_guard.MissingMessage)
}

// -----------------------------------------------------------------------------
// Unit Tests
// -----------------------------------------------------------------------------

pub fn batch_prefix_advancement_test() {
  let initial_wm = ledger.Watermark(last_committed_offset: 100)
  let updates = [
    make_accepted(100, "hash100"),
    make_accepted(101, "hash101"),
    make_rejected(102),
  ]

  let #(next_wm, inbox, errors) = ledger.ingest_batch(initial_wm, updates, [], 1000)

  errors |> should.equal([])
  list.length(inbox) |> should.equal(3)
  next_wm.last_committed_offset |> should.equal(103)
}

pub fn prefix_halt_on_identity_collision_test() {
  let initial_wm = ledger.Watermark(last_committed_offset: 100)
  // Pre-existing update 101 with hash "original"
  let existing = [
    ledger.InboxRecord(
      update_id: 101,
      message_id: 10,
      chat_id: 1001,
      user_id: 501,
      text_hash: "original_hash",
      status: ledger.InboxPending,
      created_at_ms: 500,
    ),
  ]

  // Batch arrives with 100 (new), 101 (collision with different hash), 102 (new)
  let updates = [
    make_accepted(100, "hash100"),
    make_accepted(101, "colliding_tampered_hash"),
    make_accepted(102, "hash102"),
  ]

  let #(next_wm, inbox, errors) = ledger.ingest_batch(initial_wm, updates, existing, 1000)

  // Prefix halts at 101! 100 was stored, 101 collided, 102 was NOT stored.
  errors |> should.equal(["identity_collision_differing_text_hash"])
  list.length(inbox) |> should.equal(2)
  // Watermark only advanced to 101, NOT past the colliding 101
  next_wm.last_committed_offset |> should.equal(101)
}

pub fn idempotent_duplicate_ingest_test() {
  let initial_wm = ledger.Watermark(last_committed_offset: 100)
  let updates = [
    make_accepted(100, "hash100"),
    make_accepted(100, "hash100"), // Identical duplicate
  ]

  let #(next_wm, inbox, errors) = ledger.ingest_batch(initial_wm, updates, [], 1000)

  errors |> should.equal([])
  list.length(inbox) |> should.equal(1)
  next_wm.last_committed_offset |> should.equal(101)
}

pub fn task_claim_and_completion_test() {
  let rec = ledger.InboxRecord(
    update_id: 100,
    message_id: 1,
    chat_id: 1001,
    user_id: 501,
    text_hash: "hash",
    status: ledger.InboxPending,
    created_at_ms: 1000,
  )

  // 1. Claim task
  let assert Ok(claimed) = ledger.claim_inbox_task(rec, "worker-1", 1)
  claimed.status |> should.equal(ledger.InboxProcessing("worker-1", 1))

  // Claiming already claimed task fails
  ledger.claim_inbox_task(claimed, "worker-2", 1)
  |> should.equal(Error("task_already_processing_by:worker-1_epoch:1"))

  // 2. Complete with matching worker and epoch
  let assert Ok(completed) = ledger.complete_inbox_task(claimed, "result_digest_hex", "worker-1", 1)
  completed.status |> should.equal(ledger.InboxCompleted("result_digest_hex"))

  // Complete with wrong worker fails
  ledger.complete_inbox_task(claimed, "digest", "wrong-worker", 1)
  |> should.equal(Error("claim_owner_mismatch: expected wrong-worker:1 but got worker-1:1"))
}

pub fn outbox_send_claim_and_retry_refusal_test() {
  let chunk = ledger.create_outbox_chunk("req-100", 0, 1, 1001, "{\"admitted\":93}")

  // 1. First claim succeeds
  let assert Ok(sending) = ledger.claim_outbox_send(chunk, "worker-1", 1)
  sending.attempt_count |> should.equal(1)
  sending.status |> should.equal(ledger.OutboxSending("worker-1", 1))

  // 2. Blind retry while sending is refused
  ledger.claim_outbox_send(sending, "worker-1", 1)
  |> should.equal(Error("blind_retry_barred_already_sending_by:worker-1:1"))

  // 3. Blind retry after uncertain outcome is refused
  let uncertain = ledger.OutboxChunk(..sending, status: ledger.OutboxUncertain("http_timeout"))
  ledger.claim_outbox_send(uncertain, "worker-1", 1)
  |> should.equal(Error("blind_retry_barred_on_uncertain_outcome_requires_explicit_reconciliation"))
}

pub fn outbox_reconciliation_verified_delivery_test() {
  let chunk = ledger.OutboxChunk(
    request_id: "req-100",
    chunk_index: 0,
    total_chunks: 1,
    chat_id: 1001,
    payload: "text",
    status: ledger.OutboxSending("worker-1", 1),
    attempt_count: 1,
  )

  // Valid 200 ok with positive message_id and matching chat_id
  let delivered = ledger.reconcile_send_outcome(chunk, 200, True, 1001, 777, "worker-1", 1)
  delivered.status |> should.equal(ledger.OutboxDelivered(777))
}

pub fn outbox_reconciliation_uncertain_disposition_test() {
  let chunk = ledger.OutboxChunk(
    request_id: "req-100",
    chunk_index: 0,
    total_chunks: 1,
    chat_id: 1001,
    payload: "text",
    status: ledger.OutboxSending("worker-1", 1),
    attempt_count: 1,
  )

  // 1. HTTP 502 Bad Gateway
  let res_502 = ledger.reconcile_send_outcome(chunk, 502, False, 1001, 0, "worker-1", 1)
  res_502.status |> should.equal(ledger.OutboxUncertain("http_status_502"))

  // 2. HTTP 200 with ok: false
  let res_ok_false = ledger.reconcile_send_outcome(chunk, 200, False, 1001, 0, "worker-1", 1)
  res_ok_false.status |> should.equal(ledger.OutboxUncertain("botapi_ok_false"))

  // 3. HTTP 200 with non-positive message_id
  let res_bad_msg_id = ledger.reconcile_send_outcome(chunk, 200, True, 1001, 0, "worker-1", 1)
  res_bad_msg_id.status |> should.equal(ledger.OutboxUncertain("non_positive_message_id"))

  // 4. HTTP 200 with mismatched chat_id
  let res_bad_chat = ledger.reconcile_send_outcome(chunk, 200, True, 9999, 123, "worker-1", 1)
  res_bad_chat.status |> should.equal(ledger.OutboxUncertain("mismatched_remote_chat_id"))
}

pub fn restart_recovery_test() {
  let chunks = [
    ledger.OutboxChunk("req-1", 0, 1, 1001, "txt", ledger.OutboxSending("w1", 1), 1),
    ledger.OutboxChunk("req-2", 0, 1, 1001, "txt", ledger.OutboxDelivered(55), 1),
  ]

  let inboxes = [
    ledger.InboxRecord(1, 10, 1001, 501, "h1", ledger.InboxProcessing("w1", 1), 100),
    ledger.InboxRecord(2, 20, 1001, 501, "h2", ledger.InboxCompleted("dig"), 100),
  ]

  let #(recovered_chunks, recovered_inboxes) = ledger.handle_restart(chunks, inboxes)

  // In-flight sending recovered as UNCERTAIN
  case list.first(recovered_chunks) {
    Ok(c) -> {
      c.request_id |> should.equal("req-1")
      case c.status {
        ledger.OutboxUncertain(_) -> Nil
        _ -> panic as "Expected OutboxUncertain after restart"
      }
    }
    Error(_) -> panic as "Expected chunk"
  }

  // Already delivered chunk untouched
  case list.last(recovered_chunks) {
    Ok(c) -> c.status |> should.equal(ledger.OutboxDelivered(55))
    Error(_) -> panic as "Expected chunk"
  }

  // In-flight processing inbox reset to Pending
  case list.first(recovered_inboxes) {
    Ok(i) -> i.status |> should.equal(ledger.InboxPending)
    Error(_) -> panic as "Expected inbox record"
  }
}

pub fn main() {
  batch_prefix_advancement_test()
  prefix_halt_on_identity_collision_test()
  idempotent_duplicate_ingest_test()
  task_claim_and_completion_test()
  outbox_send_claim_and_retry_refusal_test()
  outbox_reconciliation_verified_delivery_test()
  outbox_reconciliation_uncertain_disposition_test()
  restart_recovery_test()
}

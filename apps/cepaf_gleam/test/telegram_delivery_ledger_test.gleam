//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Delivery Ledger Test Suite
//// =============================================================================

import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as tg_guard
import gleeunit/should
import gleam/list
import gleam/string

fn make_range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..make_range(start + 1, end)]
  }
}

fn make_envelope(
  update_id: Int,
  message_id: Int,
  chat_id: Int,
  user_id: Int,
  text: String,
) -> tg_guard.IngressVerdict {
  tg_guard.AcceptedEnvelope(
    update_id: update_id,
    message_id: message_id,
    chat_id: chat_id,
    user_id: user_id,
    text_hash: "hash_" <> text,
    raw_text: text,
    directive: tg_guard.DirectReadTool("query_doctor"),
    bot_id: 123_456,
  )
}

pub fn batch_prefix_advancement_test() {
  let initial_watermark = ledger.Watermark(100)
  let updates = [
    make_envelope(100, 1, 1001, 501, "/doctor"),
    make_envelope(101, 2, 1001, 501, "/doctor"),
    make_envelope(102, 3, 1001, 501, "/doctor"),
  ]

  let #(new_watermark, inbox, errors) =
    ledger.ingest_batch(initial_watermark, updates, [], 1000)

  errors |> should.equal([])
  list.length(inbox) |> should.equal(3)
  new_watermark.last_committed_offset |> should.equal(103)
}

pub fn prefix_halt_on_identity_collision_test() {
  let initial_watermark = ledger.Watermark(100)
  let existing = [
    ledger.InboxRecord(
      update_id: 101,
      message_id: 2,
      chat_id: 1001,
      user_id: 501,
      text_hash: "existing_hash",
      status: ledger.InboxPending,
      created_at_ms: 500,
      bot_id: 123_456,
      request_id: "req-tg-101",
    ),
  ]

  let updates = [
    make_envelope(100, 1, 1001, 501, "/doctor"),
    make_envelope(101, 2, 1001, 501, "different_conflicting_text"),
    make_envelope(102, 3, 1001, 501, "/doctor"),
  ]

  let #(new_watermark, inbox, errors) =
    ledger.ingest_batch(initial_watermark, updates, existing, 1000)

  list.length(errors) |> should.equal(1)
  new_watermark.last_committed_offset |> should.equal(101)
  list.length(inbox) |> should.equal(2)
}

pub fn identity_collision_full_envelope_mismatch_test() {
  let initial_record = ledger.InboxRecord(
    update_id: 100,
    message_id: 10,
    chat_id: 1001,
    user_id: 501,
    text_hash: "hash_/doctor",
    status: ledger.InboxPending,
    created_at_ms: 100,
    bot_id: 123_456,
    request_id: "req-tg-100",
  )

  // 1. Same update_id and text_hash but changed message_id, chat_id, user_id
  let forged = tg_guard.AcceptedEnvelope(
    update_id: 100,
    message_id: 888,
    chat_id: 9999,
    user_id: 999,
    text_hash: "hash_/doctor",
    raw_text: "/doctor",
    directive: tg_guard.DirectReadTool("query_doctor"),
    bot_id: 123_456,
  )

  ledger.ingest_single(forged, 200, [initial_record])
  |> should.equal(Error("identity_collision_envelope_mismatch"))

  // 2. Exact match succeeds
  let exact = make_envelope(100, 10, 1001, 501, "/doctor")
  ledger.ingest_single(exact, 200, [initial_record])
  |> should.equal(Ok(initial_record))
}

pub fn unsorted_batch_halt_and_reordering_test() {
  let original = ledger.InboxRecord(
    update_id: 100,
    message_id: 10,
    chat_id: 1001,
    user_id: 501,
    text_hash: "hash_original",
    status: ledger.InboxPending,
    created_at_ms: 100,
    bot_id: 123_456,
    request_id: "req-tg-100",
  )

  // Descending batch: new update 101 followed by conflicting update 100
  let new_101 = make_envelope(101, 11, 1001, 501, "/doctor")
  let conflict_100 = make_envelope(100, 10, 1001, 501, "different_hash")

  let #(watermark, inbox, errors) =
    ledger.ingest_batch(ledger.Watermark(100), [new_101, conflict_100], [original], 200)

  // Batch must refuse without advancing past unresolved 100
  watermark.last_committed_offset |> should.equal(100)
  list.length(errors) |> should.equal(1)
  list.length(inbox) |> should.equal(1)
}

pub fn queue_capacity_limit_1000_test() {
  let updates =
    list.map(make_range(1, 1001), fn(i) {
      make_envelope(i, i, 1001, 501, "/doctor")
    })

  let #(watermark, inbox, errors) =
    ledger.ingest_batch(ledger.Watermark(1), updates, [], 100)

  // Must accept exactly 1000 rows, refusing the 1001st
  list.length(inbox) |> should.equal(1000)
  watermark.last_committed_offset |> should.equal(1001)
  list.length(errors) |> should.equal(1)
}

pub fn task_claim_and_completion_checked_constructors_test() {
  let record = ledger.InboxRecord(
    update_id: 100,
    message_id: 10,
    chat_id: 1001,
    user_id: 501,
    text_hash: "h",
    status: ledger.InboxPending,
    created_at_ms: 100,
    bot_id: 123_456,
    request_id: "req-tg-100",
  )

  // Empty worker refused
  ledger.claim_inbox_task(record, "", 1)
  |> should.equal(Error("worker_must_not_be_empty"))

  // Zero epoch refused
  ledger.claim_inbox_task(record, "w", 0)
  |> should.equal(Error("epoch_must_be_positive"))

  // Negative epoch refused
  ledger.claim_inbox_task(record, "w", -1)
  |> should.equal(Error("epoch_must_be_positive"))

  // Valid claim succeeds
  let assert Ok(claimed) = ledger.claim_inbox_task(record, "worker-1", 1)

  // Empty digest on completion refused
  ledger.complete_inbox_task(claimed, "", "worker-1", 1)
  |> should.equal(Error("digest_must_not_be_empty"))

  // Valid complete succeeds
  let assert Ok(completed) = ledger.complete_inbox_task(claimed, "digest_hex", "worker-1", 1)
  completed.status |> should.equal(ledger.InboxCompleted("digest_hex"))
}

pub fn outbox_chunk_checked_constructor_and_claim_test() {
  // Empty request_id
  let bad1 = ledger.create_outbox_chunk("", 0, 1, 1001, "payload")
  ledger.claim_outbox_send(bad1, "w", 1)
  |> should.equal(Error("request_id_must_not_be_empty"))

  // Negative chunk_index
  let bad2 = ledger.create_outbox_chunk("req-1", -1, 1, 1001, "payload")
  ledger.claim_outbox_send(bad2, "w", 1)
  |> should.equal(Error("chunk_index_must_be_non_negative"))

  // Zero total_chunks
  let bad3 = ledger.create_outbox_chunk("req-1", 0, 0, 1001, "payload")
  ledger.claim_outbox_send(bad3, "w", 1)
  |> should.equal(Error("total_chunks_must_be_positive"))

  // Zero chat_id
  let bad4 = ledger.create_outbox_chunk("req-1", 0, 1, 0, "payload")
  ledger.claim_outbox_send(bad4, "w", 1)
  |> should.equal(Error("chat_id_must_be_non_zero"))

  // Oversized payload > 4096
  let huge_payload = string.repeat("x", 4097)
  let bad5 = ledger.create_outbox_chunk("req-1", 0, 1, 1001, huge_payload)
  ledger.claim_outbox_send(bad5, "w", 1)
  |> should.equal(Error("payload_exceeds_max_4096_bytes"))

  // Empty worker or negative epoch
  let valid_chunk = ledger.create_outbox_chunk("req-1", 0, 1, 1001, "ok")
  ledger.claim_outbox_send(valid_chunk, "", 1)
  |> should.equal(Error("worker_must_not_be_empty"))

  ledger.claim_outbox_send(valid_chunk, "w", -1)
  |> should.equal(Error("epoch_must_be_positive"))
}

pub fn outbox_send_claim_and_retry_refusal_test() {
  let chunk = ledger.create_outbox_chunk("req-100", 0, 1, 1001, "{\"admitted\":93}")

  let assert Ok(sending) = ledger.claim_outbox_send(chunk, "worker-1", 1)
  sending.attempt_count |> should.equal(1)
  sending.status |> should.equal(ledger.OutboxSending("worker-1", 1))

  // Blind retry while sending is refused
  ledger.claim_outbox_send(sending, "worker-1", 1)
  |> should.equal(Error("blind_retry_barred_already_sending_by:worker-1:1"))

  // Blind retry after uncertain outcome is refused
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

  let assert Ok(delivered) =
    ledger.reconcile_send_outcome(chunk, 200, True, 1001, 777, "worker-1", 1)
  delivered.status |> should.equal(ledger.OutboxDelivered(777))
}

pub fn outbox_reconciliation_authority_and_terminal_preservation_test() {
  let delivered = ledger.OutboxChunk(
    request_id: "req-100",
    chunk_index: 0,
    total_chunks: 1,
    chat_id: 1001,
    payload: "text",
    status: ledger.OutboxDelivered(777),
    attempt_count: 1,
  )

  // Calling reconciliation on already DELIVERED chunk returns Error and preserves state
  ledger.reconcile_send_outcome(delivered, 200, True, 1001, 777, "wrong-worker", 99)
  |> should.equal(Error("terminal_state_already_delivered_state_unchanged"))

  let sending = ledger.OutboxChunk(
    request_id: "req-100",
    chunk_index: 0,
    total_chunks: 1,
    chat_id: 1001,
    payload: "text",
    status: ledger.OutboxSending("worker-1", 1),
    attempt_count: 1,
  )

  // Wrong worker returns Error and preserves state
  ledger.reconcile_send_outcome(sending, 200, True, 1001, 777, "wrong-worker", 1)
  |> should.equal(Error("owner_or_epoch_mismatch: expected worker-1:1 but got wrong-worker:1"))

  // Wrong epoch returns Error and preserves state
  ledger.reconcile_send_outcome(sending, 200, True, 1001, 777, "worker-1", 2)
  |> should.equal(Error("owner_or_epoch_mismatch: expected worker-1:1 but got worker-1:2"))

  // Matching worker/epoch with HTTP 502 yields Ok(OutboxUncertain)
  let assert Ok(res_502) =
    ledger.reconcile_send_outcome(sending, 502, False, 1001, 0, "worker-1", 1)
  res_502.status |> should.equal(ledger.OutboxUncertain("http_status_502"))
}

pub fn restart_recovery_never_reexecutes_committed_or_uncertain_test() {
  let chunks = [
    ledger.OutboxChunk("req-1", 0, 1, 1001, "txt", ledger.OutboxSending("w1", 1), 1),
    ledger.OutboxChunk("req-2", 0, 1, 1001, "txt", ledger.OutboxDelivered(55), 1),
  ]

  let inboxes = [
    ledger.InboxRecord(1, 10, 1001, 501, "h1", ledger.InboxProcessing("w1", 1), 100, 123_456, "req-1"),
    ledger.InboxRecord(2, 20, 1001, 501, "h2", ledger.InboxProcessing("w1", 1), 100, 123_456, "req-2"),
    ledger.InboxRecord(3, 30, 1001, 501, "h3", ledger.InboxProcessing("w1", 1), 100, 123_456, "req-3"),
  ]

  let #(recovered_chunks, recovered_inboxes) = ledger.handle_restart(chunks, inboxes)

  // In-flight sending chunk recovered as UNCERTAIN
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

  // Matching req-1 inbox must NOT be InboxPending (it must be InboxHold because chunk was sending/uncertain)
  case list.find(recovered_inboxes, fn(i) { i.request_id == "req-1" }) {
    Ok(i) -> {
      case i.status {
        ledger.InboxHold(_) -> Nil
        _ -> panic as "req-1 must be in InboxHold, never requeued to pending"
      }
    }
    Error(_) -> panic as "Expected req-1"
  }

  // Matching req-2 inbox must be InboxCompleted (because chunk was DELIVERED)
  case list.find(recovered_inboxes, fn(i) { i.request_id == "req-2" }) {
    Ok(i) -> i.status |> should.equal(ledger.InboxCompleted("delivered:55"))
    Error(_) -> panic as "Expected req-2"
  }

  // req-3 with missing chunk linkage must be InboxHold, NEVER InboxPending
  case list.find(recovered_inboxes, fn(i) { i.request_id == "req-3" }) {
    Ok(i) -> {
      case i.status {
        ledger.InboxHold(_) -> Nil
        _ -> panic as "req-3 must be in InboxHold, never requeued to pending"
      }
    }
    Error(_) -> panic as "Expected req-3"
  }
}

pub fn main() {
  batch_prefix_advancement_test()
  prefix_halt_on_identity_collision_test()
  identity_collision_full_envelope_mismatch_test()
  unsorted_batch_halt_and_reordering_test()
  queue_capacity_limit_1000_test()
  task_claim_and_completion_checked_constructors_test()
  outbox_chunk_checked_constructor_and_claim_test()
  outbox_send_claim_and_retry_refusal_test()
  outbox_reconciliation_verified_delivery_test()
  outbox_reconciliation_authority_and_terminal_preservation_test()
  restart_recovery_never_reexecutes_committed_or_uncertain_test()
}

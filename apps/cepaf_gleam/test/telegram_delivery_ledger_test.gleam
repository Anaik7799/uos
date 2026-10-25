import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_delivery_ledger as l
import cepaf_gleam/harness/telegram_ingress_guard as g
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should

fn envelope(id: Int, text: String) {
  g.AcceptedEnvelope(
    id,
    id + 1,
    1001,
    501,
    files.digest(text),
    text,
    g.classify_directive(text),
    123,
    None,
  )
}

fn record() {
  let assert Ok(r) = l.ingest_single(envelope(100, "/doctor"), 1000, [])
  r
}

fn processing() {
  let assert Ok(r) = l.claim_inbox_task(record(), "worker", 1)
  r
}

fn ready(payloads: List(String)) {
  let assert Ok(pair) = l.record_result(processing(), payloads, "worker", 1)
  pair
}

fn error(value: Result(a, String)) {
  case value {
    Error(_) -> Nil
    Ok(_) -> panic as "expected refusal"
  }
}

fn held(r: l.InboxRecord) {
  case r.status {
    l.InboxHold(_) -> Nil
    _ -> panic as "expected HOLD"
  }
}

fn delivered(c: l.OutboxChunk, id: Int) {
  l.OutboxChunk(..c, status: l.OutboxDelivered(id), attempt_count: 1)
}

fn uncertain(c: l.OutboxChunk) {
  l.OutboxChunk(..c, status: l.OutboxUncertain("timeout"), attempt_count: 1)
}

fn permutations(xs: List(a)) -> List(List(a)) {
  case xs {
    [a, b, c] -> [
      [a, b, c],
      [a, c, b],
      [b, a, c],
      [b, c, a],
      [c, a, b],
      [c, b, a],
    ]
    _ -> [xs, list.reverse(xs)]
  }
}

pub fn basic_prefix_test() {
  let #(wm, rows, errors) =
    l.ingest_batch(
      l.Watermark(100),
      [envelope(101, "a"), envelope(100, "b")],
      [],
      1,
    )
  wm |> should.equal(l.Watermark(102))
  list.length(rows) |> should.equal(2)
  errors |> should.equal([])
}

pub fn same_batch_collision_test() {
  list.each(
    [
      [envelope(100, "a"), envelope(101, "c"), envelope(100, "b")],
      [envelope(100, "b"), envelope(100, "a"), envelope(101, "c")],
    ],
    fn(batch) {
      let #(wm, rows, errors) = l.ingest_batch(l.Watermark(100), batch, [], 1)
      wm |> should.equal(l.Watermark(100))
      rows |> should.equal([])
      list.length(errors) |> should.equal(1)
    },
  )
}

pub fn exact_duplicate_and_gap_test() {
  let a = envelope(100, "a")
  let #(wm, rows, errors) =
    l.ingest_batch(l.Watermark(100), [a, envelope(103, "b"), a], [], 1)
  wm |> should.equal(l.Watermark(104))
  list.length(rows) |> should.equal(2)
  errors |> should.equal([])
}

pub fn existing_collision_test() {
  let old = record()
  let #(wm, rows, errors) =
    l.ingest_batch(
      l.Watermark(100),
      [envelope(101, "a"), envelope(100, "changed")],
      [old],
      1,
    )
  wm |> should.equal(l.Watermark(100))
  rows |> should.equal([old])
  list.length(errors) |> should.equal(1)
}

pub fn identity_and_rejection_collision_test() {
  let a = envelope(100, "/doctor")
  let assert g.AcceptedEnvelope(..) = a
  l.ingest_single(g.AcceptedEnvelope(..a, chat_id: 9999), 1, [record()])
  |> error
  let reject_a = g.RejectedUpdate(100, 123, files.digest("a"), "denied")
  let reject_b = g.RejectedUpdate(100, 123, files.digest("b"), "denied")
  let #(wm, rows, _) =
    l.ingest_batch(l.Watermark(100), [reject_a, reject_b], [], 1)
  wm |> should.equal(l.Watermark(100))
  rows |> should.equal([])
  let #(wm2, rows2, _) = l.ingest_batch(l.Watermark(100), [a, reject_a], [], 1)
  wm2 |> should.equal(l.Watermark(100))
  rows2 |> should.equal([])
}

pub fn mixed_bot_and_fabricated_hash_test() {
  let a = envelope(100, "a")
  let assert g.AcceptedEnvelope(..) = a
  let b = g.AcceptedEnvelope(..a, bot_id: 124)
  let #(wm, rows, _) = l.ingest_batch(l.Watermark(100), [a, b], [], 1)
  wm |> should.equal(l.Watermark(100))
  rows |> should.equal([])
  l.ingest_single(
    g.AcceptedEnvelope(..a, text_hash: files.digest("not a")),
    1,
    [],
  )
  |> error
}

pub fn unidentified_never_advances_test() {
  let #(wm, rows, _) =
    l.ingest_batch(
      l.Watermark(100),
      [envelope(101, "a"), g.UnidentifiedRejection("malformed")],
      [],
      1,
    )
  wm |> should.equal(l.Watermark(100))
  rows |> should.equal([])
}

fn range(n: Int) -> List(Int) {
  case n {
    0 -> []
    _ -> [n, ..range(n - 1)]
  }
}

pub fn queue_and_batch_bounds_test() {
  let initial =
    list.map(range(999), fn(id) {
      let assert Ok(r) = l.ingest_single(envelope(id, "a"), 1, [])
      r
    })
  let #(wm, rows, errors) =
    l.ingest_batch(
      l.Watermark(1000),
      [envelope(1000, "a"), envelope(1001, "a")],
      initial,
      1,
    )
  wm |> should.equal(l.Watermark(1001))
  list.length(rows) |> should.equal(1000)
  list.length(errors) |> should.equal(1)
  let #(wm2, rows2, _) =
    l.ingest_batch(
      l.Watermark(1),
      list.map(range(1001), fn(i) { envelope(i, "a") }),
      [],
      1,
    )
  wm2 |> should.equal(l.Watermark(1))
  rows2 |> should.equal([])
}

pub fn claim_owner_and_record_bounds_test() {
  l.claim_inbox_task(record(), "", 1) |> error
  l.claim_inbox_task(record(), "worker", 0) |> error
  l.claim_inbox_task(record(), "worker", g.max_identity + 1) |> error
  l.claim_inbox_task(record(), "../worker", 1) |> error
  l.claim_inbox_task(l.InboxRecord(..record(), message_id: 0), "worker", 1)
  |> error
}

pub fn result_owner_and_payload_bounds_test() {
  l.record_result(processing(), ["a"], "wrong", 1) |> error
  l.record_result(processing(), ["a"], "worker", 2) |> error
  l.record_result(processing(), [], "worker", 1) |> error
  l.record_result(processing(), [""], "worker", 1) |> error
  l.record_result(processing(), [string.repeat("x", 4097)], "worker", 1)
  |> error
  l.record_result(processing(), list.repeat("x", 17), "worker", 1) |> error
  let #(r, cs) = ready(list.repeat(string.repeat("x", 4096), 16))
  l.validate_result(r, cs) |> should.be_ok
}

pub fn digest_is_real_and_immutable_test() {
  let #(r, cs) = ready(["first", "second"])
  let assert l.InboxResultReady(d) = r.status
  g.valid_digest(d) |> should.be_true
  d |> should.equal(expected_digest(r, ["first", "second"]))
  l.validate_result(
    l.InboxRecord(..r, status: l.InboxResultReady("not-a-digest")),
    cs,
  )
  |> error
  let assert [a, b] = cs
  l.validate_result(r, [l.OutboxChunk(..a, payload: "tampered"), b]) |> error
  l.record_result(r, ["different"], "worker", 1) |> error
}

pub fn chunk_set_falsifiers_test() {
  let #(r, cs) = ready(["a", "b"])
  let assert [a, b] = cs
  list.each(
    [
      [a],
      [a, a],
      [l.OutboxChunk(..a, total_chunks: 3), b],
      [l.OutboxChunk(..a, chat_id: 9999), b],
      [l.OutboxChunk(..a, bot_id: 999), b],
      [l.OutboxChunk(..a, request_id: "wrong"), b],
      [l.OutboxChunk(..a, chunk_index: 100), b],
      [l.OutboxChunk(..a, result_digest: files.digest("other")), b],
    ],
    fn(bad) {
      l.validate_result(r, bad) |> error
      let #(recovered, _) = l.recover_request(r, bad)
      held(recovered)
    },
  )
}

pub fn outbox_claim_full_set_and_order_test() {
  let #(r, cs) = ready(["a", "b"])
  l.claim_outbox_send(r, cs, 1, "worker", 1) |> error
  l.claim_outbox_send(r, cs, 0, "", 1) |> error
  l.claim_outbox_send(r, cs, 0, "worker", 0) |> error
  let assert Ok(sending) = l.claim_outbox_send(r, cs, 0, "worker", 1)
  l.claim_outbox_send(r, sending, 0, "worker", 1) |> error
}

pub fn wrong_owner_and_terminal_reconcile_test() {
  let #(r, cs) = ready(["a"])
  let assert Ok(sending) = l.claim_outbox_send(r, cs, 0, "worker", 1)
  l.reconcile_send_outcome(r, sending, 0, 200, True, 1001, 77, "wrong", 1)
  |> error
  l.reconcile_send_outcome(r, sending, 0, 200, True, 1001, 77, "worker", 2)
  |> error
  let assert Ok(done) =
    l.reconcile_send_outcome(r, sending, 0, 200, True, 1001, 77, "worker", 1)
  l.reconcile_send_outcome(r, done, 0, 200, True, 1001, 77, "worker", 1)
  |> error
  l.complete_inbox_task(r, done) |> should.be_ok
}

pub fn failed_remote_outcome_no_retry_test() {
  let #(r, cs) = ready(["a"])
  let assert Ok(sending) = l.claim_outbox_send(r, cs, 0, "worker", 1)
  let assert Ok(unclear) =
    l.reconcile_send_outcome(r, sending, 0, 200, True, 9999, 77, "worker", 1)
  l.claim_outbox_send(r, unclear, 0, "worker", 2) |> error
  l.complete_inbox_task(r, unclear) |> error
}

pub fn multipart_uncertainty_permutations_test() {
  let #(r, cs) = ready(["a", "b", "c"])
  let assert [a, b, c] = cs
  list.each(permutations([delivered(a, 77), uncertain(b), c]), fn(order) {
    let #(recovered, _) = l.recover_request(r, order)
    held(recovered)
  })
}

pub fn multipart_pending_permutations_test() {
  let #(r, cs) = ready(["a", "b", "c"])
  let assert [a, b, c] = cs
  list.each(permutations([delivered(a, 77), b, c]), fn(order) {
    let #(recovered, ordered) = l.recover_request(r, order)
    recovered.status |> should.equal(r.status)
    l.claim_outbox_send(recovered, ordered, 1, "new-worker", 2) |> should.be_ok
    l.claim_inbox_task(recovered, "new-worker", 2) |> error
  })
}

pub fn all_delivered_permutations_test() {
  let #(r, cs) = ready(["a", "b", "c"])
  let done = list.index_map(cs, fn(c, i) { delivered(c, i + 1) })
  list.each(permutations(done), fn(order) {
    let #(recovered, _) = l.recover_request(r, order)
    recovered.status
    |> should.equal(l.InboxCompleted(expected_digest(r, ["a", "b", "c"])))
  })
}

pub fn impossible_delivery_order_test() {
  let #(r, cs) = ready(["a", "b"])
  let assert [a, b] = cs
  let #(recovered, _) = l.recover_request(r, [a, delivered(b, 77)])
  held(recovered)
}

pub fn crash_sending_missing_result_and_no_reexecute_test() {
  let #(r, cs) = ready(["a"])
  let assert Ok(sending) = l.claim_outbox_send(r, cs, 0, "worker", 1)
  let #(held_r, recovered) = l.recover_request(r, sending)
  held(held_r)
  l.claim_outbox_send(held_r, recovered, 0, "worker", 2) |> error
  l.claim_inbox_task(held_r, "worker", 2) |> error
  let #(missing, _) = l.recover_request(processing(), [])
  held(missing)
}

pub fn restart_processing_durable_result_test() {
  let #(r, cs) = ready(["a"])
  let #(recovered, _) = l.recover_request(processing(), cs)
  recovered.status |> should.equal(r.status)
  l.claim_inbox_task(recovered, "worker", 2) |> error
}

pub fn completion_requires_whole_delivery_test() {
  let #(r, cs) = ready(["a", "b"])
  l.complete_inbox_task(r, cs) |> error
  let assert [a, b] = cs
  l.complete_inbox_task(r, [delivered(a, 77), b]) |> error
  let assert Ok(done) =
    l.complete_inbox_task(r, [delivered(a, 77), delivered(b, 78)])
  let #(bad, _) = l.recover_request(done, cs)
  held(bad)
}

fn expected_digest(r: l.InboxRecord, payloads: List(String)) {
  // Independent reference encoding of the documented digest schema, not the ledger helper.
  json.object([
    #("schema", json.string("uos.telegram-result.v2")),
    #("request_id", json.string(r.request_id)),
    #("bot_id", json.int(r.bot_id)),
    #("chat_id", json.int(r.chat_id)),
    #("update_id", json.int(r.update_id)),
    #("message_id", json.int(r.message_id)),
    #("user_id", json.int(r.user_id)),
    #("text_hash", json.string(r.text_hash)),
    #("created_at_ms", json.int(r.created_at_ms)),
    #("payloads", json.array(payloads, json.string)),
  ])
  |> json.to_string
  |> files.digest
}

pub fn impossible_snapshot_send_refused_test() {
  let #(r, cs) = ready(["a", "b"])
  let assert [a, b] = cs
  l.claim_outbox_send(r, [a, uncertain(b)], 0, "worker", 1) |> error
  l.claim_outbox_send(r, [a, delivered(b, 77)], 0, "worker", 1) |> error
  let sending_b =
    l.OutboxChunk(..b, status: l.OutboxSending("worker", 1), attempt_count: 1)
  l.reconcile_send_outcome(
    r,
    [a, sending_b],
    1,
    200,
    True,
    1001,
    77,
    "worker",
    1,
  )
  |> error
}

pub fn corrupted_existing_queue_refused_test() {
  let r = record()
  let #(wm, rows, errors) =
    l.ingest_batch(l.Watermark(101), [envelope(101, "a")], [r, r], 1)
  wm |> should.equal(l.Watermark(101))
  rows |> should.equal([r, r])
  list.length(errors) |> should.equal(1)
  let corrupt = l.InboxRecord(..r, status: l.InboxProcessing("", 0))
  l.ingest_single(envelope(100, "/doctor"), 1, [corrupt]) |> error
}

pub fn unseen_below_watermark_refuses_without_insertion_test() {
  let old = record()
  let #(wm, rows, errors) =
    l.ingest_batch(l.Watermark(101), [envelope(99, "old")], [old], 1)
  wm |> should.equal(l.Watermark(101))
  rows |> should.equal([old])
  errors |> should.equal(["unseen_update_below_committed_offset"])
  let #(wm2, rows2, errors2) =
    l.ingest_batch(
      l.Watermark(101),
      [envelope(100, "/doctor"), envelope(101, "new")],
      [old],
      1,
    )
  wm2 |> should.equal(l.Watermark(102))
  list.length(rows2) |> should.equal(2)
  errors2 |> should.equal([])
}

pub fn untouched_pending_and_tombstone_recovery_test() {
  let pending = record()
  l.recover_request(pending, []) |> should.equal(#(pending, []))
  let assert Ok(rejected) =
    l.ingest_single(
      g.RejectedUpdate(99, 123, files.digest("raw"), "denied"),
      1,
      [],
    )
  l.recover_request(rejected, []) |> should.equal(#(rejected, []))
  let #(wm, rows, errors) =
    l.ingest_batch(l.Watermark(100), [envelope(100, "new")], [rejected], 2)
  wm |> should.equal(l.Watermark(101))
  list.length(rows) |> should.equal(2)
  errors |> should.equal([])
  let #(with_result, chunks) = ready(["result"])
  let #(bad_pending, _) = l.recover_request(pending, chunks)
  held(bad_pending)
  let #(bad_rejected, _) = l.recover_request(rejected, chunks)
  held(bad_rejected)
  let #(processing_lost, _) = l.recover_request(processing(), [])
  held(processing_lost)
  l.recover_request(processing_lost, []) |> should.equal(#(processing_lost, []))
  l.validate_result(with_result, chunks) |> should.be_ok
}

pub fn result_binds_all_immutable_ingress_fields_test() {
  let #(r, chunks) = ready(["result"])
  list.each(
    [
      l.InboxRecord(..r, message_id: 200),
      l.InboxRecord(..r, user_id: 999),
      l.InboxRecord(..r, text_hash: files.digest("altered")),
      l.InboxRecord(..r, created_at_ms: 1001),
      l.InboxRecord(
        ..r,
        update_id: 101,
        request_id: l.make_request_id(123, 101),
      ),
      l.InboxRecord(..r, chat_id: 999),
      l.InboxRecord(..r, bot_id: 124, request_id: l.make_request_id(124, 100)),
    ],
    fn(changed) {
      l.validate_result(changed, chunks) |> error
      let #(recovered, _) = l.recover_request(changed, chunks)
      held(recovered)
    },
  )
}

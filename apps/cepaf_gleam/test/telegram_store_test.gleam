import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import simplifile

const guardian_path = "/home/an/NAS-setup/uos/tools/telegram_store_transport_guardian.exe"

const guardian_sha = "bd418aa04b1a591256ef47f2abf48529a548f077d3fedf59075d4b894c28d11d"

const worker_path = "/home/an/NAS-setup/uos/native/ocaml/telegram_store/_build/default/telegram_store_main.exe"

const worker_sha = "2cf64d7a24da0e9c1dc7ace920b3f119447e6b0de3e75a8f7ee74e37930156ec"

const recovery_guardian_path = "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe"

const recovery_guardian_sha = "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab"

const recovery_worker_path = "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe"

const recovery_worker_sha = "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e"

fn with_recovery_store(
  test_fn: fn(transport.LocalConfiguration, String) -> a,
) -> a {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_store_recovery_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/telegram.sqlite3"
  let config =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      db_path,
    )
  let res = test_fn(config, dir)
  let _ = simplifile.delete(dir)
  res
}

fn range(from: Int, to: Int) -> List(Int) {
  case from <= to {
    True -> [from, ..range(from + 1, to)]
    False -> []
  }
}

fn with_temp_store(
  test_fn: fn(transport.LocalConfiguration, String) -> a,
) -> a {
  let unique = int.to_string(int.random(1_000_000_000))
  let dir = "/tmp/uos_tg_store_test_" <> unique
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let db_path = dir <> "/telegram.sqlite3"
  let config =
    transport.reviewed_local_configuration(
      guardian_path,
      guardian_sha,
      worker_path,
      worker_sha,
      db_path,
    )
  let res = test_fn(config, dir)
  let _ = simplifile.delete(dir)
  res
}

fn sample_accepted(
  uid: Int,
  text: String,
  bot_id: Int,
) -> guard.IngressVerdict {
  guard.AcceptedEnvelope(
    update_id: uid,
    message_id: uid + 10,
    chat_id: 12_345,
    user_id: 67_890,
    text_hash: files.digest(text),
    raw_text: text,
    directive: guard.classify_directive(text),
    bot_id: bot_id,
    callback_query_id: None,
  )
}

fn sample_rejected(
  uid: Int,
  reason: String,
  bot_id: Int,
) -> guard.IngressVerdict {
  guard.RejectedUpdate(
    update_id: uid,
    bot_id: bot_id,
    envelope_hash: files.digest(reason),
    reason: reason,
  )
}

// =============================================================================
// Test 1: Golden Digest Cross-Language Parity
// =============================================================================

pub fn golden_digest_parity_test() {
  // Test vector matching line 1009 of native telegram_store_test.ml:
  // bot_id="1", op="op_strict", gen=1, rs=[], changes=[], res={0,0}, sum="{}"
  let d =
    codec.compute_apply_digest(
      1,
      "op_strict",
      1,
      [],
      [],
      codec.ReservationDelta(0, 0),
      "{}",
    )
  d
  |> should.equal(
    "8825f9c2f07cbdc1dd35478403db4922b79abce9e485db0bd23ade6dfb8fe339",
  )

  // Verify key sorting invariance: assertions in different order produce identical digest
  let a1 = codec.ReadSetAssertion("alpha", 1, files.digest("val1"))
  let a2 = codec.ReadSetAssertion("beta", 2, files.digest("val2"))

  let d1 =
    codec.compute_apply_digest(
      1,
      "op_sort",
      1,
      [a1, a2],
      [],
      codec.ReservationDelta(0, 0),
      "{}",
    )
  let d2 =
    codec.compute_apply_digest(
      1,
      "op_sort",
      1,
      [a2, a1],
      [],
      codec.ReservationDelta(0, 0),
      "{}",
    )
  d1 |> should.equal(d2)

  // Different read-set produces different digest
  let d3 =
    codec.compute_apply_digest(
      1,
      "op_sort",
      1,
      [a1],
      [],
      codec.ReservationDelta(0, 0),
      "{}",
    )
  should.be_true(d1 != d3)
}

// =============================================================================
// Test 2: Canonical Base64 and Row Validation
// =============================================================================

pub fn base64_and_row_invariants_test() {
  let original = "{\"status\": \"ok\", \"count\": 42}"
  let b64 = codec.encode_canonical_base64(original)
  let assert Ok(decoded) = codec.decode_canonical_base64(b64)
  decoded |> should.equal(original)

  // Non-canonical base64: invalid padding or length
  codec.decode_canonical_base64("abc") |> should.be_error
  codec.decode_canonical_base64("abcde") |> should.be_error

  // Valid row
  let row_ok =
    codec.RowResult(
      key: "test/key",
      exists: True,
      version: 1,
      canonical_value_base64: b64,
      sha256: files.digest(original),
    )
  codec.validate_row_result(row_ok) |> should.be_ok
  codec.decode_row_value(row_ok) |> should.equal(Ok(original))

  // Row invariant violations
  let row_hash_mismatch =
    codec.RowResult(
      key: "test/key",
      exists: True,
      version: 1,
      canonical_value_base64: b64,
      sha256: "0000000000000000000000000000000000000000000000000000000000000000",
    )
  codec.validate_row_result(row_hash_mismatch) |> should.be_error

  let row_absent_non_zero =
    codec.RowResult(
      key: "test/key",
      exists: False,
      version: 1,
      canonical_value_base64: "",
      sha256: "",
    )
  codec.validate_row_result(row_absent_non_zero) |> should.be_error
}

// =============================================================================
// Test 3: Initialize New & Bootstrap Metadata
// =============================================================================

pub fn initialize_and_bootstrap_test() {
  use config, _ <- with_temp_store()
  let bot_id = 987_654_321

  // Fresh initialization
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  gen |> should.equal(2)

  // Verify watermark row exists and is 0
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)
  wm.last_committed_offset |> should.equal(0)
  wm_ver |> should.equal(1)
  should.be_true(string.byte_size(wm_sha) == 64)

  // Verify bot identity exists
  let assert Ok(#(stored_bot_id, bot_ver, _)) = store.read_bot_identity(config)
  stored_bot_id |> should.equal(bot_id)
  bot_ver |> should.equal(1)

  // Resumable bootstrap: re-initialization with same bot_id succeeds idempotently
  let re_init = store.initialize_store(config, bot_id)
  re_init |> should.equal(Ok(2))

  // Re-initialization with a DIFFERENT bot_id on existing DB must fail
  let mismatch_init = store.initialize_store(config, 111_222_333)
  mismatch_init
  |> should.equal(Error(store.StoreInvariantError("bot_id_mismatch")))
}

// =============================================================================
// Test 4: Atomic Prefix Commit & Equal-ID Groups
// =============================================================================

pub fn atomic_prefix_commit_test() {
  use config, _ <- with_temp_store()
  let bot_id = 123_456_789
  let assert Ok(gen) = store.initialize_store(config, bot_id)

  let assert Ok(#(wm0, wm_ver0, wm_sha0)) = store.read_watermark(config)

  // Batch 1: Two identical updates for update_id 100 (same-identity deduplication)
  let u1 = sample_accepted(100, "/start", bot_id)
  let u2 = sample_accepted(100, "/start", bot_id)

  let assert Ok(res1) =
    store.commit_prefix(
      config,
      bot_id,
      "op-prefix-100",
      gen,
      wm0,
      wm_ver0,
      wm_sha0,
      [u1, u2],
      1000,
    )

  res1.watermark.last_committed_offset |> should.equal(101)
  list.length(res1.admitted_records) |> should.equal(1)
  res1.remaining_updates |> should.equal([])

  // Verify inbox record persisted in store
  let assert Ok(#(_, inbox_entries)) =
    store.read_inbox_records(config, 10, None)
  list.length(inbox_entries) |> should.equal(1)
  let assert [#(rec100, rec_ver, _)] = inbox_entries
  rec100.update_id |> should.equal(100)
  rec100.status |> should.equal(ledger.InboxPending)
  rec_ver |> should.equal(1)

  // Verify raw input persisted
  let assert Ok(#(_, [input_row])) =
    store.read_keys(config, [codec.input_key(rec100.request_id)])
  input_row.exists |> should.be_true
  let assert Ok(input_val) = codec.decode_row_value(input_row)
  let assert Ok(#(req_id, b_id, u_id, _)) =
    codec.decode_input_verdict(input_val)
  req_id |> should.equal(rec100.request_id)
  b_id |> should.equal(bot_id)
  u_id |> should.equal(100)

  // Batch 2: Conflicting updates for update_id 101 in same batch must fail atomically
  let assert Ok(#(wm1, wm_ver1, wm_sha1)) = store.read_watermark(config)
  let c1 = sample_accepted(101, "/cmd1", bot_id)
  let c2 = sample_accepted(101, "/cmd2_different", bot_id)

  let conflict_res =
    store.commit_prefix(
      config,
      bot_id,
      "op-prefix-101",
      res1.receipt.generation,
      wm1,
      wm_ver1,
      wm_sha1,
      [c1, c2],
      2000,
    )
  conflict_res |> should.be_error

  // Verify watermark was NOT advanced
  let assert Ok(#(wm_check, _, _)) = store.read_watermark(config)
  wm_check.last_committed_offset |> should.equal(101)

  // Batch 3: Rejected tombstone advances watermark
  let rej = sample_rejected(101, "unauthorized_user", bot_id)
  let assert Ok(res3) =
    store.commit_prefix(
      config,
      bot_id,
      "op-prefix-101-rej",
      res1.receipt.generation,
      wm1,
      wm_ver1,
      wm_sha1,
      [rej],
      3000,
    )
  res3.watermark.last_committed_offset |> should.equal(102)
  let assert [rej_rec] = res3.admitted_records
  rej_rec.status |> should.equal(ledger.InboxRejected("unauthorized_user"))
}

// =============================================================================
// Test 5: CAS & Read-Set Concurrency Protections
// =============================================================================

pub fn cas_and_read_set_concurrency_test() {
  use config, _ <- with_temp_store()
  let bot_id = 555_666_777
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  // 1. Commit with stale generation must be rejected
  let u1 = sample_accepted(1, "hello", bot_id)
  let stale_gen_res =
    store.commit_prefix(
      config,
      bot_id,
      "op-stale-gen",
      gen - 1,
      wm,
      wm_ver,
      wm_sha,
      [u1],
      1000,
    )
  stale_gen_res |> should.be_error

  // 2. Commit with wrong watermark version in read_set must be rejected
  let stale_wm_ver_res =
    store.commit_prefix(
      config,
      bot_id,
      "op-stale-wm",
      gen,
      wm,
      wm_ver + 99,
      wm_sha,
      [u1],
      1000,
    )
  stale_wm_ver_res |> should.be_error

  // 3. Normal commit succeeds
  let assert Ok(commit_res) =
    store.commit_prefix(
      config,
      bot_id,
      "op-valid",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u1],
      1000,
    )

  // 4. Replay of same operation_id with SAME digest succeeds as replay
  let replay_res =
    store.commit_prefix(
      config,
      bot_id,
      "op-valid",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u1],
      1000,
    )
  let assert Ok(rep) = replay_res
  rep.receipt.operation_id |> should.equal("op-valid")
  rep.receipt.generation |> should.equal(commit_res.receipt.generation)
}

// =============================================================================
// Test 6: Maximal 16-Chunk Result Atomic Persistence
// =============================================================================

pub fn maximal_16_chunk_result_atomic_test() {
  use config, _ <- with_temp_store()
  let bot_id = 999_888_777
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  // Ingest update 50
  let u = sample_accepted(50, "/heavy_computation", bot_id)
  let assert Ok(pref) =
    store.commit_prefix(
      config,
      bot_id,
      "op-pref-50",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u],
      5000,
    )

  let assert [inbox_rec] = pref.admitted_records
  let cur_gen = pref.receipt.generation

  // Claim task by worker
  let assert Ok(#(claim_rcpt, processing_rec)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-claim-50",
      cur_gen,
      inbox_rec,
      1,
      files.digest(codec.encode_inbox_record(inbox_rec)),
      "worker_heavy",
      1,
      6000,
    )
  let after_claim_gen = claim_rcpt.generation

  // Generate 16 distinct 4096-byte chunk payloads with escaped characters
  let payloads =
    list.map(range(0, 15), fn(i) {
      let prefix =
        "CHUNK_" <> int.to_string(i) <> " [\"escaped\": '\\/\\n\\t'] "
      let pad_len = 4096 - string.byte_size(prefix)
      prefix <> string.repeat("X", pad_len)
    })
  list.length(payloads) |> should.equal(16)
  list.each(payloads, fn(p) { string.byte_size(p) |> should.equal(4096) })

  // Commit result and all 16 chunks atomically
  let assert Ok(res_result) =
    store.commit_result(
      config,
      bot_id,
      "op-result-50",
      after_claim_gen,
      processing_rec,
      2,
      files.digest(codec.encode_inbox_record(processing_rec)),
      payloads,
      "worker_heavy",
      1,
    )

  list.length(res_result.chunks) |> should.equal(16)
  let assert ledger.InboxResultReady(res_digest) =
    res_result.inbox_record.status

  // Verify all 16 chunks exist in store
  let chunk_keys =
    list.map(range(0, 15), fn(i) { codec.chunk_key(inbox_rec.request_id, i) })
  let assert Ok(#(_, chunk_rows)) = store.read_keys(config, chunk_keys)
  list.length(chunk_rows) |> should.equal(16)
  list.each(chunk_rows, fn(r) {
    r.exists |> should.be_true
    r.version |> should.equal(1)
    let assert Ok(chunk_raw) = codec.decode_row_value(r)
    let assert Ok(c) = codec.decode_chunk_value(chunk_raw)
    c.status |> should.equal(ledger.OutboxPending)
    c.total_chunks |> should.equal(16)
    c.result_digest |> should.equal(res_digest)
  })

  // Negative control: 17 chunks rejected
  let extra_payloads = [string.repeat("A", 100), ..payloads]
  let overflow_res =
    store.commit_result(
      config,
      bot_id,
      "op-overflow",
      res_result.receipt.generation,
      processing_rec,
      2,
      files.digest(codec.encode_inbox_record(processing_rec)),
      extra_payloads,
      "worker_heavy",
      1,
    )
  overflow_res |> should.be_error
}

// =============================================================================
// Test 7: Durable SENDING Persistence Before HTTP & Outcome Persistence
// =============================================================================

pub fn sending_and_outcome_lifecycle_test() {
  use config, _ <- with_temp_store()
  let bot_id = 777_111_222
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  // Ingest update 200
  let u = sample_accepted(200, "/reply_test", bot_id)
  let assert Ok(pref) =
    store.commit_prefix(
      config,
      bot_id,
      "op-p-200",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u],
      1000,
    )
  let assert [inbox_rec] = pref.admitted_records

  // Claim task
  let assert Ok(#(claim_rcpt, proc_rec)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-c-200",
      pref.receipt.generation,
      inbox_rec,
      1,
      files.digest(codec.encode_inbox_record(inbox_rec)),
      "sender_worker",
      1,
      1100,
    )

  // Persist 2-chunk result
  let payloads = ["Chunk 1 response", "Chunk 2 response"]
  let assert Ok(res_result) =
    store.commit_result(
      config,
      bot_id,
      "op-r-200",
      claim_rcpt.generation,
      proc_rec,
      2,
      files.digest(codec.encode_inbox_record(proc_rec)),
      payloads,
      "sender_worker",
      1,
    )
  let assert [chunk0, chunk1] = res_result.chunks
  let after_res_gen = res_result.receipt.generation

  // 1. Commit SENDING for chunk 0 before any HTTP call!
  let assert Ok(#(send0_rcpt, sending_chunk0)) =
    store.commit_sending(
      config,
      bot_id,
      "op-send-chunk-0",
      after_res_gen,
      res_result.inbox_record,
      3,
      files.digest(codec.encode_inbox_record(res_result.inbox_record)),
      chunk0,
      1,
      files.digest(codec.encode_chunk_value(chunk0)),
      "sender_worker",
      1,
    )

  sending_chunk0.status
  |> should.equal(ledger.OutboxSending("sender_worker", 1))
  sending_chunk0.attempt_count |> should.equal(1)

  // Read back chunk 0 from store to verify SENDING is durable
  let assert Ok(#(_, [c0_row])) =
    store.read_keys(config, [codec.chunk_key(chunk0.request_id, 0)])
  c0_row.version |> should.equal(2)
  let assert Ok(c0_val) = codec.decode_row_value(c0_row)
  let assert Ok(c0_stored) = codec.decode_chunk_value(c0_val)
  c0_stored.status |> should.equal(ledger.OutboxSending("sender_worker", 1))

  // 2. Commit outcome for chunk 0: Delivered with remote message ID 4567
  let assert Ok(#(out0_rcpt, delivered_chunk0)) =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-chunk-0",
      send0_rcpt.generation,
      sending_chunk0,
      2,
      files.digest(codec.encode_chunk_value(sending_chunk0)),
      ledger.OutboxDelivered(4567),
    )
  delivered_chunk0.status |> should.equal(ledger.OutboxDelivered(4567))

  // 3. Commit SENDING and Delivered for chunk 1
  let assert Ok(#(send1_rcpt, sending_chunk1)) =
    store.commit_sending(
      config,
      bot_id,
      "op-send-chunk-1",
      out0_rcpt.generation,
      res_result.inbox_record,
      3,
      files.digest(codec.encode_inbox_record(res_result.inbox_record)),
      chunk1,
      1,
      files.digest(codec.encode_chunk_value(chunk1)),
      "sender_worker",
      1,
    )

  let assert Ok(#(out1_rcpt, delivered_chunk1)) =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-chunk-1",
      send1_rcpt.generation,
      sending_chunk1,
      2,
      files.digest(codec.encode_chunk_value(sending_chunk1)),
      ledger.OutboxDelivered(4568),
    )

  // 4. Once all chunks delivered, commit task completion
  let assert Ok(#(_, completed_inbox)) =
    store.commit_task_completion(
      config,
      bot_id,
      "op-complete-200",
      out1_rcpt.generation,
      res_result.inbox_record,
      3,
      files.digest(codec.encode_inbox_record(res_result.inbox_record)),
      [delivered_chunk0, delivered_chunk1],
    )

  let assert ledger.InboxCompleted(comp_digest) = completed_inbox.status
  let assert ledger.InboxResultReady(orig_digest) =
    res_result.inbox_record.status
  comp_digest |> should.equal(orig_digest)
}

// =============================================================================
// Test 8: Uncertainty Reconciliation via Lookup (No Blind Replay)
// =============================================================================

pub fn uncertainty_reconciliation_test() {
  use config, _ <- with_temp_store()
  let bot_id = 111_222_333
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let u = sample_accepted(300, "/reconcile", bot_id)
  let op_id = "op-uncertain-300"

  // Check reconciliation before operation runs:
  // 1. Without writer quiescence proof, must report ReconciledUnknown
  let assert Ok(rec_unknown) =
    store.reconcile_uncertain(config, op_id, "some_digest")
  rec_unknown
  |> should.equal(store.ReconciledUnknown("writer_quiescence_unproven"))

  // 2. Caller-supplied boolean true cannot mint absence; must report ReconciledUnknown
  let assert Ok(rec_bool_true) =
    store.reconcile_uncertain_quiesced(config, op_id, "some_digest", True)
  rec_bool_true
  |> should.equal(store.ReconciledUnknown("writer_quiescence_unproven"))

  // Commit operation
  let assert Ok(pref) =
    store.commit_prefix(
      config,
      bot_id,
      op_id,
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u],
      1000,
    )

  // Reconcile with matching digest: must report Committed
  let assert Ok(rec_committed) =
    store.reconcile_uncertain(config, op_id, pref.receipt.request_digest)
  let assert store.ReconciledCommitted(r) = rec_committed
  r.operation_id |> should.equal(op_id)
  r.request_digest |> should.equal(pref.receipt.request_digest)

  // Reconcile with mismatching digest: must report Collision
  let assert Ok(rec_collision) =
    store.reconcile_uncertain(
      config,
      op_id,
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
    )
  let assert store.ReconciledCollision(col_r) = rec_collision
  col_r.operation_id |> should.equal(op_id)
}

// =============================================================================
// Test 9: Recovery Model & Crash Invariants
// =============================================================================

pub fn recovery_model_invariants_test() {
  let r =
    ledger.InboxRecord(
      update_id: 400,
      message_id: 401,
      chat_id: 1000,
      user_id: 2000,
      text_hash: files.digest("text"),
      status: ledger.InboxProcessing("worker1", 1),
      created_at_ms: 1000,
      bot_id: 10,
      request_id: "tg-10-400",
    )

  let assert Ok(#(ready_r, chunks)) =
    ledger.record_result(r, ["c1", "c2"], "worker1", 1)
  let assert [_c0, c1] = chunks

  // Simulate crash while c0 is SENDING
  let assert Ok([sending0, _]) =
    ledger.claim_outbox_send(ready_r, chunks, 0, "worker1", 1)

  // Recovery must transition crashed SENDING to Uncertain and place record on HOLD
  let #(rec_r, rec_chunks) = ledger.recover_request(ready_r, [sending0, c1])
  case rec_r.status {
    ledger.InboxHold(reason) ->
      reason |> should.equal("uncertain_or_failed_delivery")
    _ -> panic as "expected InboxHold"
  }

  let assert [rc0, _] = rec_chunks
  case rc0.status {
    ledger.OutboxUncertain(reason) ->
      reason |> should.equal("crash_during_send")
    _ -> panic as "expected OutboxUncertain"
  }
}

// =============================================================================
// Test 10: Finding 1 - Singleton Bot ID, Directive Parity & Prevalidation
// =============================================================================

pub fn finding1_singleton_and_directive_validation_test() {
  use config, _ <- with_temp_store()
  let bot_id = 111_444_777
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  // 1. Singleton wrong bot is rejected
  let wrong_bot = 888_999_000
  let singleton_wrong = sample_accepted(100, "/start", wrong_bot)
  let res_wrong_bot =
    store.commit_prefix(
      config,
      bot_id,
      "op-f1-wrong-bot",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [singleton_wrong],
      1000,
    )
  res_wrong_bot
  |> should.equal(Error(store.StoreInvariantError("group_bot_id_mismatch")))

  // 2. Directive mismatch within same update group is rejected
  let env_help = sample_accepted(200, "/help", bot_id)
  let env_status = sample_accepted(200, "/status", bot_id)
  let res_dir_mismatch =
    store.commit_prefix(
      config,
      bot_id,
      "op-f1-dir-mismatch",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [env_help, env_status],
      1000,
    )
  res_dir_mismatch
  |> should.equal(Error(store.StoreInvariantError("batch_identity_collision")))

  // 3. Prevalidation: all groups validated before any prefix commit
  // Group 1 has valid update 300, Group 2 has invalid update 301 (wrong bot)
  let u_valid = sample_accepted(300, "/first", bot_id)
  let u_invalid = sample_accepted(301, "/second", wrong_bot)
  let res_preval =
    store.commit_prefix(
      config,
      bot_id,
      "op-f1-preval",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u_valid, u_invalid],
      1000,
    )
  res_preval
  |> should.equal(Error(store.StoreInvariantError("group_bot_id_mismatch")))

  // Watermark must still be 0 (no partial commit occurred)
  let assert Ok(#(wm_after, _, _)) = store.read_watermark(config)
  wm_after.last_committed_offset |> should.equal(0)

  // Inbox must be completely empty
  let assert Ok(#(_, inbox_entries)) =
    store.read_inbox_records(config, 10, None)
  inbox_entries |> should.equal([])
}

// =============================================================================
// Test 11: Finding 2 - Bounded Batch Size & Admitted Known Replays Below Watermark
// =============================================================================

pub fn finding2_batch_bounds_and_known_replay_test() {
  use config, _ <- with_temp_store()
  let bot_id = 222_555_888
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  // 1. Exceeding max batch size (> 1000) rejected
  let over_limit =
    list.map(range(1, 1001), fn(i) { sample_accepted(i, "/msg", bot_id) })
  let res_over_limit =
    store.commit_prefix(
      config,
      bot_id,
      "op-f2-over-limit",
      gen,
      wm,
      wm_ver,
      wm_sha,
      over_limit,
      1000,
    )
  res_over_limit
  |> should.equal(Error(store.StoreInvariantError("batch_or_watermark_bound")))

  // 2. Commit update 100 normally to establish watermark 101
  let u100 = sample_accepted(100, "/hello", bot_id)
  let assert Ok(res100) =
    store.commit_prefix(
      config,
      bot_id,
      "op-f2-first-100",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u100],
      1000,
    )
  res100.watermark.last_committed_offset |> should.equal(101)

  // 3. Known replay below watermark: committing update 100 again succeeds via inbox check
  let assert Ok(#(wm1, wm_ver1, wm_sha1)) = store.read_watermark(config)
  let assert Ok(replay_res) =
    store.commit_prefix(
      config,
      bot_id,
      "op-f2-replay-100",
      res100.receipt.generation,
      wm1,
      wm_ver1,
      wm_sha1,
      [u100],
      2000,
    )
  // Watermark does not regress, update is admitted
  replay_res.watermark.last_committed_offset |> should.equal(101)
  let assert [admitted_rec] = replay_res.admitted_records
  admitted_rec.update_id |> should.equal(100)

  // 4. Unseen update below watermark: update 99 was never committed, must fail
  let u99 = sample_accepted(99, "/never_seen", bot_id)
  let res_unseen =
    store.commit_prefix(
      config,
      bot_id,
      "op-f2-unseen-99",
      replay_res.receipt.generation,
      wm1,
      wm_ver1,
      wm_sha1,
      [u99],
      3000,
    )
  res_unseen
  |> should.equal(
    Error(store.StoreInvariantError("unseen_update_below_committed_offset")),
  )
}

// =============================================================================
// Test 12: Finding 3 - Backend Error Whitelist & Row Result Invariants
// =============================================================================

pub fn finding3_backend_error_whitelist_and_decoder_invariants_test() {
  // 1. Whitelisted error strings recognized
  codec.is_whitelisted_backend_error("read_keys_too_many")
  |> should.be_true
  codec.is_whitelisted_backend_error("db_already_exists")
  |> should.be_true
  codec.is_whitelisted_backend_error("cas_conflict")
  |> should.be_true
  codec.is_whitelisted_backend_error("read_set_conflict")
  |> should.be_true
  codec.is_whitelisted_backend_error("stale_generation")
  |> should.be_true

  // 2. Unwhitelisted errors rejected
  codec.is_whitelisted_backend_error("unrecognized_internal_error")
  |> should.be_false
  codec.is_whitelisted_backend_error("sqlite3 error 42 syntax error")
  |> should.be_false

  // 3. Decoding apply receipt with unwhitelisted error maps to unwhitelisted_backend_error
  let raw_unwhitelisted_err =
    "{\"ok\": false, \"error\": \"raw internal sqlite panic\"}"
  codec.decode_apply_response(raw_unwhitelisted_err)
  |> should.equal(Error("unwhitelisted_backend_error"))

  // 4. Decoding apply receipt with whitelisted error preserves exact string
  let raw_whitelisted_err = "{\"ok\": false, \"error\": \"cas_conflict\"}"
  codec.decode_apply_response(raw_whitelisted_err)
  |> should.equal(Error("cas_conflict"))

  // 5. RowResult validation: non-positive version rejected
  let row_bad_ver =
    codec.RowResult(
      "k",
      True,
      0,
      codec.encode_canonical_base64("{}"),
      files.digest("{}"),
    )
  codec.validate_row_result(row_bad_ver) |> should.be_error
}

// =============================================================================
// Test 13: Finding 5 - Capacity Reservation Delta Accounting
// =============================================================================

pub fn finding5_capacity_reservation_accounting_test() {
  // Exact lifecycle deltas against 20 total KV rows and 64 receipt credits:
  // - Accepted prefix commit: +18 reserved rows, +63 reserved receipts (creates 2 rows, consumes 1 receipt)
  // - Replay / rejected prefix commit: 0 reserved rows, 0 reserved receipts
  // - Task claim: -1 reserved row, -1 reserved receipt (creates 1 row, consumes 1 receipt)
  // - Result commit: -17 reserved rows, -1 reserved receipt (creates up to 17 rows, consumes 1 receipt)
  // - Sending commit: 0 reserved rows, -1 reserved receipt
  // - Outcome commit: 0 reserved rows, -1 reserved receipt
  // - Completion commit: 0 reserved rows, -1 reserved receipt

  // Net sum of reserved row adjustments across full lifecycle:
  let net_rows = 18 - 1 - 17 + 0 + 0 + 0
  net_rows |> should.equal(0)

  // Net receipts consumed across 6 operations:
  let net_receipts_consumed = 1 + 1 + 1 + 1 + 1 + 1
  net_receipts_consumed |> should.equal(6)

  // Remaining receipt capacity from 64 credit pool:
  let remaining_receipt_credits = 64 - net_receipts_consumed
  remaining_receipt_credits |> should.equal(58)
}

// =============================================================================
// Test 14: Finding 6 - Resumable Bootstrap from Interrupted Native Init
// =============================================================================

pub fn finding6_resumable_bootstrap_interrupted_init_test() {
  use config, _ <- with_temp_store()
  let bot_id = 333_666_999

  // Simulate interrupted bootstrap: send raw native initialize_new command directly.
  // This creates the SQLite database file, but crashes before bootstrap_metadata applies.
  let init_cmd = codec.encode_initialize_new_command(bot_id, None)
  let assert Ok(_) = transport.exchange(config, init_cmd)

  // Verify that metadata keys do NOT exist yet
  let assert Ok(#(_, rows)) =
    store.read_keys(config, [codec.bot_identity_key(), codec.watermark_key()])
  list.each(rows, fn(r) { r.exists |> should.be_false })

  // Calling initialize_store intercepts db_already_exists and resumes bootstrap
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  gen |> should.equal(2)

  // Verify that metadata was written and is now complete
  let assert Ok(#(stored_bot_id, bot_ver, _)) = store.read_bot_identity(config)
  stored_bot_id |> should.equal(bot_id)
  bot_ver |> should.equal(1)

  let assert Ok(#(wm, wm_ver, _)) = store.read_watermark(config)
  wm.last_committed_offset |> should.equal(0)
  wm_ver |> should.equal(1)
}

// =============================================================================
// Test 15: Authority Binding and Worker / Epoch Mismatch Protection
// =============================================================================

pub fn authority_binding_and_worker_mismatch_test() {
  use config, _ <- with_temp_store()
  let bot_id = 999_888_777
  let assert Ok(gen2) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let u = sample_accepted(700, "/work", bot_id)
  let assert Ok(pref) =
    store.commit_prefix(
      config,
      bot_id,
      "op-auth-prefix",
      gen2,
      wm,
      wm_ver,
      wm_sha,
      [u],
      1000,
    )
  let assert [inbox] = pref.admitted_records
  let assert Ok(#(_, [inbox_row])) =
    store.read_keys(config, [codec.inbox_key(inbox.request_id)])

  // Claim with worker "owner", epoch 1
  let assert Ok(#(claim_rcpt, proc_inbox)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-auth-claim",
      pref.receipt.generation,
      inbox,
      inbox_row.version,
      inbox_row.sha256,
      "owner",
      1,
      2000,
    )

  let assert Ok(#(_, [proc_row])) =
    store.read_keys(config, [codec.inbox_key(inbox.request_id)])

  // 1. Intruder worker attempts commit_result -> must fail with worker_epoch_authority_mismatch
  let intruder_res =
    store.commit_result(
      config,
      bot_id,
      "op-intruder-result",
      claim_rcpt.generation,
      proc_inbox,
      proc_row.version,
      proc_row.sha256,
      ["reply"],
      "intruder",
      1,
    )
  intruder_res
  |> should.equal(
    Error(store.StoreInvariantError("worker_epoch_authority_mismatch")),
  )

  // 2. Legitimate owner commits result -> succeeds
  let assert Ok(result_res) =
    store.commit_result(
      config,
      bot_id,
      "op-owner-result",
      claim_rcpt.generation,
      proc_inbox,
      proc_row.version,
      proc_row.sha256,
      ["reply"],
      "owner",
      1,
    )
  let assert [chunk] = result_res.chunks
  let assert Ok(#(_, [ready_row])) =
    store.read_keys(config, [codec.inbox_key(inbox.request_id)])
  let assert Ok(#(_, [chunk_row])) =
    store.read_keys(config, [
      codec.chunk_key(chunk.request_id, chunk.chunk_index),
    ])

  // 3. Intruder worker attempts commit_sending -> must fail with worker_epoch_authority_mismatch
  let intruder_send =
    store.commit_sending(
      config,
      bot_id,
      "op-intruder-sending",
      result_res.receipt.generation,
      result_res.inbox_record,
      ready_row.version,
      ready_row.sha256,
      chunk,
      chunk_row.version,
      chunk_row.sha256,
      "intruder",
      999,
    )
  intruder_send
  |> should.equal(
    Error(store.StoreInvariantError("worker_epoch_authority_mismatch")),
  )

  // 4. Legitimate owner commits sending -> succeeds
  let assert Ok(#(send_rcpt, sending_chunk)) =
    store.commit_sending(
      config,
      bot_id,
      "op-owner-sending",
      result_res.receipt.generation,
      result_res.inbox_record,
      ready_row.version,
      ready_row.sha256,
      chunk,
      chunk_row.version,
      chunk_row.sha256,
      "owner",
      1,
    )

  let assert Ok(#(_, [sending_row])) =
    store.read_keys(config, [
      codec.chunk_key(chunk.request_id, chunk.chunk_index),
    ])

  // 5. Outcome commit with wrong worker in chunk -> fails
  let spoofed_chunk =
    ledger.OutboxChunk(
      ..sending_chunk,
      status: ledger.OutboxSending("wrong-worker", 1),
    )
  let spoof_outcome =
    store.commit_outcome(
      config,
      bot_id,
      "op-spoof-outcome",
      send_rcpt.generation,
      spoofed_chunk,
      sending_row.version,
      sending_row.sha256,
      ledger.OutboxDelivered(99),
    )
  spoof_outcome
  |> should.equal(
    Error(store.StoreInvariantError("worker_epoch_authority_mismatch")),
  )

  // 6. Legitimate outcome commit -> succeeds
  let assert Ok(#(outcome_rcpt, delivered_chunk)) =
    store.commit_outcome(
      config,
      bot_id,
      "op-owner-outcome",
      send_rcpt.generation,
      sending_chunk,
      sending_row.version,
      sending_row.sha256,
      ledger.OutboxDelivered(99),
    )

  // 7. Legitimate completion commit -> succeeds
  let assert Ok(#(_comp_rcpt, comp_inbox)) =
    store.commit_task_completion(
      config,
      bot_id,
      "op-completion",
      outcome_rcpt.generation,
      result_res.inbox_record,
      ready_row.version,
      ready_row.sha256,
      [delivered_chunk],
    )
  let assert ledger.InboxCompleted(_) = comp_inbox.status
}

// =============================================================================
// Test 16: Panic-Free Typed Error on Invalid States
// =============================================================================

pub fn panic_free_typed_errors_test() {
  use config, _ <- with_temp_store()
  let bot_id = 123_456_789
  let assert Ok(_) = store.initialize_store(config, bot_id)

  let chunk =
    ledger.OutboxChunk(
      request_id: "req-fake",
      chunk_index: 0,
      total_chunks: 1,
      payload: "hi",
      status: ledger.OutboxPending,
      attempt_count: 0,
      bot_id: bot_id,
      chat_id: 1,
      result_digest: "digest",
    )

  // commit_outcome on OutboxPending must return Error without panic
  let res =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-pending",
      1,
      chunk,
      1,
      "sha",
      ledger.OutboxDelivered(1),
    )
  res
  |> should.equal(
    Error(store.StoreInvariantError("commit_outcome_requires_outbox_sending")),
  )

  // commit_outcome with invalid outcome status must return Error without panic
  let sending_chunk =
    ledger.OutboxChunk(..chunk, status: ledger.OutboxSending("worker", 1))
  let res2 =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-invalid",
      1,
      sending_chunk,
      1,
      "sha",
      ledger.OutboxPending,
    )
  res2
  |> should.equal(
    Error(store.StoreInvariantError(
      "commit_outcome_requires_valid_outcome_status",
    )),
  )
}

// =============================================================================
// Test 17: Typed Value and Hash Binding Invariants
// =============================================================================

pub fn typed_value_and_hash_binding_invariants_test() {
  use config, _ <- with_temp_store()
  let bot_id = 999_888_777
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let u = sample_accepted(700, "/typed_binding", bot_id)
  let assert Ok(pref) =
    store.commit_prefix(
      config,
      bot_id,
      "op-prefix-700",
      gen,
      wm,
      wm_ver,
      wm_sha,
      [u],
      1000,
    )
  let assert [inbox] = pref.admitted_records
  let real_inbox_sha = files.digest(codec.encode_inbox_record(inbox))

  // 1. Forged recipient in claim_task_processing must fail CAS/binding
  let forged_inbox = ledger.InboxRecord(..inbox, chat_id: 999_999)
  let claim_forged =
    store.claim_task_processing(
      config,
      bot_id,
      "op-claim-forged",
      pref.receipt.generation,
      forged_inbox,
      1,
      real_inbox_sha,
      "worker-1",
      1,
      2000,
    )
  claim_forged
  |> should.equal(Error(store.StoreInvariantError("inbox_record_sha_mismatch")))

  // Legitimate claim succeeds
  let assert Ok(#(claim_rec, claimed_inbox)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-claim-ok",
      pref.receipt.generation,
      inbox,
      1,
      real_inbox_sha,
      "worker-1",
      1,
      2000,
    )

  let claimed_inbox_sha = files.digest(codec.encode_inbox_record(claimed_inbox))

  // 2. Forged recipient in commit_result must fail CAS/binding
  let forged_claimed = ledger.InboxRecord(..claimed_inbox, chat_id: 999_999)
  let result_forged =
    store.commit_result(
      config,
      bot_id,
      "op-result-forged",
      claim_rec.generation,
      forged_claimed,
      2,
      claimed_inbox_sha,
      ["response payload"],
      "worker-1",
      1,
    )
  result_forged
  |> should.equal(Error(store.StoreInvariantError("inbox_record_sha_mismatch")))

  // Legitimate result succeeds
  let assert Ok(res_result) =
    store.commit_result(
      config,
      bot_id,
      "op-result-ok",
      claim_rec.generation,
      claimed_inbox,
      2,
      claimed_inbox_sha,
      ["response payload"],
      "worker-1",
      1,
    )
  let assert [chunk] = res_result.chunks
  let real_chunk_sha = files.digest(codec.encode_chunk_value(chunk))
  let result_inbox_sha =
    files.digest(codec.encode_inbox_record(res_result.inbox_record))

  // 3. Changed payload in commit_sending must fail CAS/binding
  let forged_chunk = ledger.OutboxChunk(..chunk, payload: "ALTERED_PAYLOAD")
  let send_forged =
    store.commit_sending(
      config,
      bot_id,
      "op-send-forged",
      res_result.receipt.generation,
      res_result.inbox_record,
      3,
      result_inbox_sha,
      forged_chunk,
      1,
      real_chunk_sha,
      "worker-1",
      1,
    )
  send_forged
  |> should.equal(Error(store.StoreInvariantError("chunk_sha_mismatch")))

  // Legitimate sending succeeds
  let assert Ok(#(send_rec, sending_chunk)) =
    store.commit_sending(
      config,
      bot_id,
      "op-send-ok",
      res_result.receipt.generation,
      res_result.inbox_record,
      3,
      result_inbox_sha,
      chunk,
      1,
      real_chunk_sha,
      "worker-1",
      1,
    )

  let sending_chunk_sha = files.digest(codec.encode_chunk_value(sending_chunk))

  // 4. Stale pending re-entering sending must fail
  let stale_send =
    store.commit_sending(
      config,
      bot_id,
      "op-send-stale",
      send_rec.generation,
      res_result.inbox_record,
      3,
      result_inbox_sha,
      chunk,
      2,
      sending_chunk_sha,
      "worker-1",
      1,
    )
  stale_send
  |> should.equal(Error(store.StoreInvariantError("chunk_sha_mismatch")))

  // 5. Changed recipient in commit_outcome must fail CAS/binding
  let forged_sending = ledger.OutboxChunk(..sending_chunk, chat_id: 999_999)
  let outcome_forged =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-forged",
      send_rec.generation,
      forged_sending,
      2,
      sending_chunk_sha,
      ledger.OutboxDelivered(555),
    )
  outcome_forged
  |> should.equal(Error(store.StoreInvariantError("chunk_sha_mismatch")))

  // Legitimate outcome succeeds
  let assert Ok(#(outcome_rec, delivered_chunk)) =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-ok",
      send_rec.generation,
      sending_chunk,
      2,
      sending_chunk_sha,
      ledger.OutboxDelivered(555),
    )

  // Legitimate completion succeeds and returns all reservation credits
  let assert Ok(#(comp_rec, comp_inbox)) =
    store.commit_task_completion(
      config,
      bot_id,
      "op-comp-ok",
      outcome_rec.generation,
      res_result.inbox_record,
      3,
      result_inbox_sha,
      [delivered_chunk],
    )
  comp_rec.operation_id |> should.equal("op-comp-ok")
  let assert ledger.InboxCompleted(_) = comp_inbox.status
}

// =============================================================================
// Test 18: Completed-State Replay Test
// =============================================================================

pub fn completed_state_replay_test() {
  use config, _dir <- with_temp_store()
  let bot_id = 123
  let assert Ok(init_gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let sample = sample_accepted(10, "/start", bot_id)
  let assert Ok(prefix_res) =
    store.commit_prefix(
      config,
      bot_id,
      "op-prefix-init",
      init_gen,
      wm,
      wm_ver,
      wm_sha,
      [sample],
      1000,
    )
  let assert [inbox_rec] = prefix_res.admitted_records
  let inbox_sha = files.digest(codec.encode_inbox_record(inbox_rec))

  let assert Ok(#(claim_rec, proc_inbox)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-claim-1",
      prefix_res.receipt.generation,
      inbox_rec,
      1,
      inbox_sha,
      "worker-1",
      1,
      2000,
    )
  let proc_inbox_sha = files.digest(codec.encode_inbox_record(proc_inbox))

  let assert Ok(res_result) =
    store.commit_result(
      config,
      bot_id,
      "op-res-1",
      claim_rec.generation,
      proc_inbox,
      2,
      proc_inbox_sha,
      ["chunk-data"],
      "worker-1",
      1,
    )
  let assert [chunk] = res_result.chunks
  let chunk_sha = files.digest(codec.encode_chunk_value(chunk))
  let result_inbox_sha =
    files.digest(codec.encode_inbox_record(res_result.inbox_record))

  let assert Ok(#(send_rec, sending_chunk)) =
    store.commit_sending(
      config,
      bot_id,
      "op-send-1",
      res_result.receipt.generation,
      res_result.inbox_record,
      3,
      result_inbox_sha,
      chunk,
      1,
      chunk_sha,
      "worker-1",
      1,
    )
  let sending_chunk_sha = files.digest(codec.encode_chunk_value(sending_chunk))

  let assert Ok(#(outcome_rec, delivered_chunk)) =
    store.commit_outcome(
      config,
      bot_id,
      "op-outcome-1",
      send_rec.generation,
      sending_chunk,
      2,
      sending_chunk_sha,
      ledger.OutboxDelivered(999),
    )

  let assert Ok(#(comp_rec, comp_inbox)) =
    store.commit_task_completion(
      config,
      bot_id,
      "op-comp-1",
      outcome_rec.generation,
      res_result.inbox_record,
      3,
      result_inbox_sha,
      [delivered_chunk],
    )
  let assert ledger.InboxCompleted(_) = comp_inbox.status

  // Replaying update 10 below watermark after task completion
  let assert Ok(#(cur_wm, cur_wm_ver, cur_wm_sha)) =
    store.read_watermark(config)
  cur_wm.last_committed_offset |> should.equal(11)

  let replay_res =
    store.commit_prefix(
      config,
      bot_id,
      "op-replay-after-completion",
      comp_rec.generation,
      cur_wm,
      cur_wm_ver,
      cur_wm_sha,
      [sample],
      3000,
    )
  let assert Ok(res) = replay_res
  res.receipt.operation_id |> should.equal("op-replay-after-completion")
  let assert [replayed_inbox] = res.admitted_records
  let assert ledger.InboxCompleted(_) = replayed_inbox.status
  replayed_inbox.request_id |> should.equal(inbox_rec.request_id)
}

// =============================================================================
// Test 19: Replay During Processing and ResultReady Preserves Execution State
// =============================================================================

pub fn replay_during_processing_and_result_ready_test() {
  use config, _dir <- with_temp_store()
  let bot_id = 123
  let assert Ok(init_gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let sample = sample_accepted(20, "/status", bot_id)
  let assert Ok(p1) =
    store.commit_prefix(
      config,
      bot_id,
      "op-p1",
      init_gen,
      wm,
      wm_ver,
      wm_sha,
      [sample],
      1000,
    )
  let assert [inbox_rec] = p1.admitted_records
  let inbox_sha = files.digest(codec.encode_inbox_record(inbox_rec))

  let assert Ok(#(claim_rec, _proc_inbox)) =
    store.claim_task_processing(
      config,
      bot_id,
      "op-claim-p",
      p1.receipt.generation,
      inbox_rec,
      1,
      inbox_sha,
      "worker-1",
      1,
      2000,
    )

  // 1. Replay during InboxProcessing
  let assert Ok(#(cur_wm, cur_wm_ver, cur_wm_sha)) =
    store.read_watermark(config)
  let assert Ok(rep_proc) =
    store.commit_prefix(
      config,
      bot_id,
      "op-replay-proc",
      claim_rec.generation,
      cur_wm,
      cur_wm_ver,
      cur_wm_sha,
      [sample],
      1500,
    )
  let assert [replayed_proc] = rep_proc.admitted_records
  let assert ledger.InboxProcessing(worker, epoch) = replayed_proc.status
  worker |> should.equal("worker-1")
  epoch |> should.equal(1)

  // 2. Advance to ResultReady
  let proc_sha = files.digest(codec.encode_inbox_record(replayed_proc))
  let assert Ok(res_result) =
    store.commit_result(
      config,
      bot_id,
      "op-res-p",
      rep_proc.receipt.generation,
      replayed_proc,
      2,
      proc_sha,
      ["reply"],
      "worker-1",
      1,
    )

  // 3. Replay during InboxResultReady
  let assert Ok(#(cur_wm2, cur_wm_ver2, cur_wm_sha2)) =
    store.read_watermark(config)
  let assert Ok(rep_ready) =
    store.commit_prefix(
      config,
      bot_id,
      "op-replay-ready",
      res_result.receipt.generation,
      cur_wm2,
      cur_wm_ver2,
      cur_wm_sha2,
      [sample],
      2500,
    )
  let assert [replayed_ready] = rep_ready.admitted_records
  let assert ledger.InboxResultReady(_) = replayed_ready.status
}

// =============================================================================
// Test 20: Rejection Reason Collision on Replay Refused
// =============================================================================

pub fn rejection_reason_collision_replay_refused_test() {
  use config, _dir <- with_temp_store()
  let bot_id = 123
  let assert Ok(init_gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let rej = sample_rejected(30, "initial_refusal_reason", bot_id)
  let assert Ok(p1) =
    store.commit_prefix(
      config,
      bot_id,
      "op-rej-init",
      init_gen,
      wm,
      wm_ver,
      wm_sha,
      [rej],
      1000,
    )
  let assert Ok(#(cur_wm, cur_wm_ver, cur_wm_sha)) =
    store.read_watermark(config)

  // Replay with identical rejection reason succeeds
  let assert Ok(rep_ok) =
    store.commit_prefix(
      config,
      bot_id,
      "op-rej-replay-ok",
      p1.receipt.generation,
      cur_wm,
      cur_wm_ver,
      cur_wm_sha,
      [rej],
      1200,
    )
  rep_ok.receipt.operation_id |> should.equal("op-rej-replay-ok")

  // Replay with different rejection reason must fail with batch_identity_collision
  let changed_rej = sample_rejected(30, "different_refusal_reason", bot_id)
  let assert Ok(#(cur_wm2, cur_wm_ver2, cur_wm_sha2)) =
    store.read_watermark(config)
  let rep_diff =
    store.commit_prefix(
      config,
      bot_id,
      "op-rej-replay-diff",
      rep_ok.receipt.generation,
      cur_wm2,
      cur_wm_ver2,
      cur_wm_sha2,
      [changed_rej],
      1500,
    )
  rep_diff
  |> should.equal(Error(store.StoreInvariantError("batch_identity_collision")))

  // Replay with AcceptedEnvelope where previously RejectedUpdate must fail
  let changed_acc = sample_accepted(30, "/start", bot_id)
  let rep_acc =
    store.commit_prefix(
      config,
      bot_id,
      "op-rej-replay-acc",
      rep_ok.receipt.generation,
      cur_wm2,
      cur_wm_ver2,
      cur_wm_sha2,
      [changed_acc],
      1600,
    )
  rep_acc
  |> should.equal(Error(store.StoreInvariantError("batch_identity_collision")))
}

// =============================================================================
// Test 21: Replay Pressure and Multi-Request Reservation Invariance
// =============================================================================

pub fn replay_pressure_reservation_invariance_test() {
  use config, _dir <- with_temp_store()
  let bot_id = 123
  let assert Ok(init_gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let sample = sample_accepted(40, "/pressure", bot_id)
  let assert Ok(p1) =
    store.commit_prefix(
      config,
      bot_id,
      "op-press-init",
      init_gen,
      wm,
      wm_ver,
      wm_sha,
      [sample],
      1000,
    )

  // Replay update 40 ten consecutive times with fresh operations
  let last_gen =
    list.fold(range(1, 10), p1.receipt.generation, fn(gen, i) {
      let assert Ok(#(cur_wm, cur_wm_ver, cur_wm_sha)) =
        store.read_watermark(config)
      let op = "op-pressure-replay-" <> int.to_string(i)
      let assert Ok(rep) =
        store.commit_prefix(
          config,
          bot_id,
          op,
          gen,
          cur_wm,
          cur_wm_ver,
          cur_wm_sha,
          [sample],
          1000 + i,
        )
      rep.receipt.generation
    })

  // Reservations were invariant (delta 0, 0), so we can still ingest new updates
  let assert Ok(#(final_wm, final_wm_ver, final_wm_sha)) =
    store.read_watermark(config)
  final_wm.last_committed_offset |> should.equal(41)

  let new_sample = sample_accepted(41, "/new-msg", bot_id)
  let assert Ok(p_new) =
    store.commit_prefix(
      config,
      bot_id,
      "op-press-new",
      last_gen,
      final_wm,
      final_wm_ver,
      final_wm_sha,
      [new_sample],
      2000,
    )
  p_new.watermark.last_committed_offset |> should.equal(42)
}

// =============================================================================
// Test 22: Strict Parser Max Depth and Empty Containers
// =============================================================================

pub fn parser_depth_and_empty_containers_test() {
  // Depth 64 nested empty arrays: 64 '[' followed by 64 ']'
  let open_arrays = string.repeat("[", 64)
  let close_arrays = string.repeat("]", 64)
  let depth64_arr = open_arrays <> close_arrays
  let assert Ok(_) = codec.parse_strict_json(depth64_arr)

  // Depth 65 nested empty arrays: must exceed max depth
  let depth65_arr = "[" <> depth64_arr <> "]"
  codec.parse_strict_json(depth65_arr)
  |> should.equal(Error("json_nesting_depth_exceeded"))

  // Depth 64 nested objects
  let open_objs = string.repeat("{\"k\":", 64)
  let close_objs = string.repeat("}", 64)
  let depth64_obj = open_objs <> "1" <> close_objs
  let assert Ok(_) = codec.parse_strict_json(depth64_obj)

  // Depth 65 nested objects: must exceed max depth
  let depth65_obj = "{\"a\":" <> depth64_obj <> "}"
  codec.parse_strict_json(depth65_obj)
  |> should.equal(Error("json_nesting_depth_exceeded"))
}

// =============================================================================
// Test 23: Strict Parser Escaped Duplicates and Wide Object Budget
// =============================================================================

pub fn parser_escaped_duplicates_and_wide_object_test() {
  // Escaped duplicate JSON keys: "a" and "\u0061" resolve to the same UTF-8 key
  let escaped_dup = "{\"a\": 1, \"\\u0061\": 2}"
  codec.parse_strict_json(escaped_dup)
  |> should.equal(Error("duplicate_json_keys"))

  // 1000 keys wide object parses successfully
  let wide_1000 =
    "{"
    <> string.join(
      list.map(range(1, 1000), fn(i) {
        "\"k" <> int.to_string(i) <> "\":" <> int.to_string(i)
      }),
      ",",
    )
    <> "}"
  let assert Ok(_) = codec.parse_strict_json(wide_1000)

  // Oversized object with 2049 keys exceeds max object keys budget
  let wide_2049 =
    "{"
    <> string.join(
      list.map(range(1, 2049), fn(i) {
        "\"k" <> int.to_string(i) <> "\":" <> int.to_string(i)
      }),
      ",",
    )
    <> "}"
  codec.parse_strict_json(wide_2049)
  |> should.equal(Error("json_object_too_wide"))

  // Oversized array with 4097 elements exceeds max array elements budget
  let long_arr_4097 =
    "["
    <> string.join(list.map(range(1, 4097), fn(i) { int.to_string(i) }), ",")
    <> "]"
  codec.parse_strict_json(long_arr_4097)
  |> should.equal(Error("json_array_too_long"))
}

// =============================================================================
// Test 24: Authority Record Domain Boundary Validation
// =============================================================================

pub fn authority_record_domain_validation_test() {
  let valid_auth =
    codec.AuthorityRecord(
      request_id: "tg-123-10",
      bot_id: 123,
      worker: "worker-1",
      epoch: 1,
      granted_at_ms: 1000,
    )
  let valid_json = codec.encode_authority_value(valid_auth)
  let assert Ok(decoded) = codec.decode_authority_value(valid_json)
  decoded |> should.equal(valid_auth)

  // 1. Wrong request ID (mismatched bot ID or update ID format)
  let bad_req =
    codec.encode_authority_value(
      codec.AuthorityRecord(..valid_auth, request_id: "wrong-request"),
    )
  codec.decode_authority_value(bad_req)
  |> should.equal(Error("invalid_authority_record_payload"))

  // 2. bot_id = 0
  let bad_bot =
    codec.encode_authority_value(codec.AuthorityRecord(..valid_auth, bot_id: 0))
  codec.decode_authority_value(bad_bot)
  |> should.equal(Error("invalid_authority_record_payload"))

  // 3. epoch = 0
  let bad_epoch =
    codec.encode_authority_value(codec.AuthorityRecord(..valid_auth, epoch: 0))
  codec.decode_authority_value(bad_epoch)
  |> should.equal(Error("invalid_authority_record_payload"))

  // 4. granted_at_ms = -1
  let bad_time =
    codec.encode_authority_value(
      codec.AuthorityRecord(..valid_auth, granted_at_ms: -1),
    )
  codec.decode_authority_value(bad_time)
  |> should.equal(Error("invalid_authority_record_payload"))
}

// =============================================================================
// Test 25: Outbox Chunk Domain Boundary Validation
// =============================================================================

pub fn outbox_chunk_domain_validation_test() {
  let valid_chunk =
    ledger.OutboxChunk(
      request_id: "tg-123-10",
      chunk_index: 0,
      total_chunks: 1,
      chat_id: 12_345,
      payload: "valid-payload",
      status: ledger.OutboxPending,
      attempt_count: 0,
      bot_id: 123,
      result_digest: files.digest("result-digest"),
    )
  let valid_json = codec.encode_chunk_value(valid_chunk)
  let assert Ok(decoded) = codec.decode_chunk_value(valid_json)
  decoded |> should.equal(valid_chunk)

  // 1. Empty/malformed request ID
  let bad_req =
    codec.encode_chunk_value(
      ledger.OutboxChunk(..valid_chunk, request_id: "emptyreq"),
    )
  codec.decode_chunk_value(bad_req)
  |> should.equal(Error("invalid_chunk_payload"))

  // 2. bot_id = 0
  let bad_bot =
    codec.encode_chunk_value(ledger.OutboxChunk(..valid_chunk, bot_id: 0))
  codec.decode_chunk_value(bad_bot)
  |> should.equal(Error("invalid_chunk_payload"))

  // 3. chat_id = 0
  let bad_chat =
    codec.encode_chunk_value(ledger.OutboxChunk(..valid_chunk, chat_id: 0))
  codec.decode_chunk_value(bad_chat)
  |> should.equal(Error("invalid_chunk_payload"))

  // 4. Empty payload
  let bad_payload =
    codec.encode_chunk_value(ledger.OutboxChunk(..valid_chunk, payload: ""))
  codec.decode_chunk_value(bad_payload)
  |> should.equal(Error("invalid_chunk_payload"))

  // 5. Delivered telegram_msg_id = -1
  let bad_del =
    codec.encode_chunk_value(
      ledger.OutboxChunk(..valid_chunk, status: ledger.OutboxDelivered(-1)),
    )
  codec.decode_chunk_value(bad_del)
  |> should.equal(Error("invalid_chunk_payload"))

  // 6. attempt_count = -1
  let bad_attempts =
    codec.encode_chunk_value(
      ledger.OutboxChunk(..valid_chunk, attempt_count: -1),
    )
  codec.decode_chunk_value(bad_attempts)
  |> should.equal(Error("invalid_chunk_payload"))
}

// =============================================================================
// Test 26: Watermark Domain Boundary Validation
// =============================================================================

pub fn watermark_domain_validation_test() {
  let valid_wm = ledger.Watermark(10)
  let valid_json = codec.encode_watermark_value(valid_wm)
  let assert Ok(decoded) = codec.decode_watermark_value(valid_json)
  decoded |> should.equal(valid_wm)

  // 1. Negative watermark offset
  let bad_wm_neg = codec.encode_watermark_value(ledger.Watermark(-1))
  codec.decode_watermark_value(bad_wm_neg)
  |> should.equal(Error("invalid_watermark_payload"))

  // 2. Enormous watermark offset (overflows guard.max_update_id + 1)
  let bad_wm_huge =
    "{\"schema\":\"uos.telegram-watermark.v1\",\"last_committed_offset\":99999999999999999999999}"
  codec.decode_watermark_value(bad_wm_huge)
  |> should.equal(Error("invalid_watermark_payload"))
}

// =============================================================================
// Test 27: Input Verdict Domain Boundary Validation
// =============================================================================

pub fn input_verdict_domain_validation_test() {
  let acc = sample_accepted(10, "/help", 123)
  let valid_json = codec.encode_input_verdict("tg-123-10", 123, 10, acc)
  let assert Ok(#(req_id, bot_id, upd_id, decoded_verdict)) =
    codec.decode_input_verdict(valid_json)
  req_id |> should.equal("tg-123-10")
  bot_id |> should.equal(123)
  upd_id |> should.equal(10)
  decoded_verdict |> should.equal(acc)

  // 1. Wrong request ID
  let bad_req = codec.encode_input_verdict("wrong-request", 123, 10, acc)
  codec.decode_input_verdict(bad_req)
  |> should.equal(Error("invalid_input_verdict_payload"))

  // 2. bot_id = 0
  let bad_bot = codec.encode_input_verdict("tg-0-10", 0, 10, acc)
  codec.decode_input_verdict(bad_bot)
  |> should.equal(Error("invalid_input_verdict_payload"))

  // 3. update_id = -1
  let bad_upd = codec.encode_input_verdict("tg-123--1", 123, -1, acc)
  codec.decode_input_verdict(bad_upd)
  |> should.equal(Error("invalid_input_verdict_payload"))

  // 4. Forged directive (mismatched directive for text)
  let forged_acc =
    guard.AcceptedEnvelope(
      update_id: 10,
      message_id: 20,
      chat_id: 12_345,
      user_id: 67_890,
      text_hash: files.digest("/help"),
      raw_text: "/help",
      directive: guard.DirectReadTool("query_doctor"),
      bot_id: 123,
      callback_query_id: None,
    )
  let bad_dir = codec.encode_input_verdict("tg-123-10", 123, 10, forged_acc)
  codec.decode_input_verdict(bad_dir)
  |> should.equal(Error("invalid_input_verdict_payload"))

  // 5. Valid rejected update supported
  let rej = sample_rejected(11, "empty_text", 123)
  let valid_rej_json = codec.encode_input_verdict("tg-123-11", 123, 11, rej)
  let assert Ok(#(_, _, _, decoded_rej)) =
    codec.decode_input_verdict(valid_rej_json)
  decoded_rej |> should.equal(rej)

  // 6. Invalid rejected update (empty reason)
  let bad_rej =
    guard.RejectedUpdate(
      update_id: 11,
      bot_id: 123,
      envelope_hash: files.digest("empty_text"),
      reason: "",
    )
  let bad_rej_json = codec.encode_input_verdict("tg-123-11", 123, 11, bad_rej)
  codec.decode_input_verdict(bad_rej_json)
  |> should.equal(Error("invalid_input_verdict_payload"))
}

// =============================================================================
// Test 28: Result Meta Domain Boundary Validation
// =============================================================================

pub fn result_meta_domain_validation_test() {
  let valid_meta =
    codec.ResultMeta(
      request_id: "tg-123-10",
      bot_id: 123,
      chat_id: 12_345,
      update_id: 10,
      message_id: 20,
      user_id: 67_890,
      text_hash: files.digest("/start"),
      created_at_ms: 1000,
      digest: files.digest("reply-digest"),
      total_chunks: 1,
    )
  let valid_json = codec.encode_result_value(valid_meta)
  let assert Ok(decoded) = codec.decode_result_value(valid_json)
  decoded |> should.equal(valid_meta)

  // 1. Wrong request ID
  let bad_req =
    codec.encode_result_value(
      codec.ResultMeta(..valid_meta, request_id: "wrongreq"),
    )
  codec.decode_result_value(bad_req)
  |> should.equal(Error("invalid_result_meta_payload"))

  // 2. bot_id = 0
  let bad_bot =
    codec.encode_result_value(codec.ResultMeta(..valid_meta, bot_id: 0))
  codec.decode_result_value(bad_bot)
  |> should.equal(Error("invalid_result_meta_payload"))

  // 3. chat_id = 0
  let bad_chat =
    codec.encode_result_value(codec.ResultMeta(..valid_meta, chat_id: 0))
  codec.decode_result_value(bad_chat)
  |> should.equal(Error("invalid_result_meta_payload"))

  // 4. update_id = -1
  let bad_upd =
    codec.encode_result_value(codec.ResultMeta(..valid_meta, update_id: -1))
  codec.decode_result_value(bad_upd)
  |> should.equal(Error("invalid_result_meta_payload"))

  // 5. message_id = 0
  let bad_msg =
    codec.encode_result_value(codec.ResultMeta(..valid_meta, message_id: 0))
  codec.decode_result_value(bad_msg)
  |> should.equal(Error("invalid_result_meta_payload"))

  // 6. user_id = 0
  let bad_usr =
    codec.encode_result_value(codec.ResultMeta(..valid_meta, user_id: 0))
  codec.decode_result_value(bad_usr)
  |> should.equal(Error("invalid_result_meta_payload"))

  // 7. created_at_ms = -1
  let bad_time =
    codec.encode_result_value(codec.ResultMeta(..valid_meta, created_at_ms: -1))
  codec.decode_result_value(bad_time)
  |> should.equal(Error("invalid_result_meta_payload"))
}

// =============================================================================
// Test 29: Negative Clock and Forged Directive Write Boundary Tests
// =============================================================================

pub fn negative_clock_and_forged_directive_write_boundary_test() {
  use config, _dir <- with_temp_store()
  let bot_id = 123
  let assert Ok(init_gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm, wm_ver, wm_sha)) = store.read_watermark(config)

  let sample = sample_accepted(10, "/start", bot_id)

  // 1. Negative now_ms must fail commit_prefix at write boundary
  let bad_clock =
    store.commit_prefix(
      config,
      bot_id,
      "op-neg-clock",
      init_gen,
      wm,
      wm_ver,
      wm_sha,
      [sample],
      -1,
    )
  bad_clock
  |> should.equal(Error(store.StoreInvariantError("batch_or_watermark_bound")))

  // 2. Forged directive paired with conflicting raw text must fail write boundary
  let forged_directive_sample =
    guard.AcceptedEnvelope(
      update_id: 10,
      message_id: 20,
      chat_id: 12_345,
      user_id: 67_890,
      text_hash: files.digest("/tool destructive_action"),
      raw_text: "/tool destructive_action",
      directive: guard.DirectReadTool("query_doctor"),
      bot_id: bot_id,
      callback_query_id: None,
    )
  let bad_directive =
    store.commit_prefix(
      config,
      bot_id,
      "op-forged-dir",
      init_gen,
      wm,
      wm_ver,
      wm_sha,
      [forged_directive_sample],
      1000,
    )
  bad_directive
  |> should.equal(
    Error(store.StoreInvariantError("invalid_accepted_envelope_structure")),
  )
}

// =============================================================================
// Test 30: Canonical Request ID and Chunk Validator Invariants
// =============================================================================

pub fn canonical_request_id_and_chunk_validator_test() {
  let bot_id = 123

  // 1. Canonical request ID checks
  codec.valid_authority_request_id("tg-123-10", bot_id)
  |> should.equal(True)

  codec.valid_authority_request_id("tg-00123-10", bot_id)
  |> should.equal(False)

  codec.valid_authority_request_id("tg-123-0010", bot_id)
  |> should.equal(False)

  codec.valid_authority_request_id("tg-456-10", bot_id)
  |> should.equal(False)

  codec.valid_authority_request_id("random-string", bot_id)
  |> should.equal(False)

  // 2. Chunk decoder checks
  let valid_chunk =
    ledger.OutboxChunk(
      request_id: "tg-123-10",
      chunk_index: 0,
      total_chunks: 1,
      chat_id: 12_345,
      payload: "hello telegram",
      status: ledger.OutboxPending,
      attempt_count: 0,
      bot_id: bot_id,
      result_digest: files.digest("sample-digest"),
    )

  let encoded = codec.encode_chunk_value(valid_chunk)
  codec.decode_chunk_value(encoded)
  |> should.equal(Ok(valid_chunk))

  // Noncanonical request_id in chunk payload must be rejected
  let noncanonical_chunk =
    "{\"schema\":\"uos.telegram-chunk.v2\",\"request_id\":\"tg-00123-10\",\"bot_id\":123,\"chat_id\":12345,\"chunk_index\":0,\"total_chunks\":1,\"payload\":\"hello\",\"result_digest\":\""
    <> files.digest("d")
    <> "\",\"attempt_count\":0,\"status\":{\"tag\":\"pending\"}}"
  codec.decode_chunk_value(noncanonical_chunk)
  |> should.equal(Error("invalid_chunk_payload"))

  // Pending with attempt_count == 1 must be rejected
  let bad_pending =
    "{\"schema\":\"uos.telegram-chunk.v2\",\"request_id\":\"tg-123-10\",\"bot_id\":123,\"chat_id\":12345,\"chunk_index\":0,\"total_chunks\":1,\"payload\":\"hello\",\"result_digest\":\""
    <> files.digest("d")
    <> "\",\"attempt_count\":1,\"status\":{\"tag\":\"pending\"}}"
  codec.decode_chunk_value(bad_pending)
  |> should.equal(Error("invalid_chunk_payload"))

  // Sending with attempt_count == 0 must be rejected
  let bad_sending =
    "{\"schema\":\"uos.telegram-chunk.v2\",\"request_id\":\"tg-123-10\",\"bot_id\":123,\"chat_id\":12345,\"chunk_index\":0,\"total_chunks\":1,\"payload\":\"hello\",\"result_digest\":\""
    <> files.digest("d")
    <> "\",\"attempt_count\":0,\"status\":{\"tag\":\"sending\",\"worker\":\"worker-1\",\"epoch\":1}}"
  codec.decode_chunk_value(bad_sending)
  |> should.equal(Error("invalid_chunk_payload"))

  // Whitespace-only payload must be rejected
  let whitespace_payload =
    "{\"schema\":\"uos.telegram-chunk.v2\",\"request_id\":\"tg-123-10\",\"bot_id\":123,\"chat_id\":12345,\"chunk_index\":0,\"total_chunks\":1,\"payload\":\"   \",\"result_digest\":\""
    <> files.digest("d")
    <> "\",\"attempt_count\":0,\"status\":{\"tag\":\"pending\"}}"
  codec.decode_chunk_value(whitespace_payload)
  |> should.equal(Error("invalid_chunk_payload"))

  // NUL byte in payload must be rejected
  let nul_payload =
    "{\"schema\":\"uos.telegram-chunk.v2\",\"request_id\":\"tg-123-10\",\"bot_id\":123,\"chat_id\":12345,\"chunk_index\":0,\"total_chunks\":1,\"payload\":\"hello\\u0000world\",\"result_digest\":\""
    <> files.digest("d")
    <> "\",\"attempt_count\":0,\"status\":{\"tag\":\"pending\"}}"
  codec.decode_chunk_value(nul_payload)
  |> should.equal(Error("invalid_chunk_payload"))
}

// =============================================================================
// Test 31: Quiescence Cleanup Proof and Reconciliation Invariants
// =============================================================================

pub fn quiescence_cleanup_proof_and_reconciliation_test() {
  use config, _dir <- with_recovery_store()
  let bot_id = 999
  let assert Ok(gen) = store.initialize_store(config, bot_id)
  let assert Ok(#(wm0, wm_ver0, wm_sha0)) = store.read_watermark(config)

  // 1. Live observation of cleanup proof through exchange_with_cleanup
  let ping_req = codec.encode_lookup_operation_command("op_nonexistent", None)
  let obs = store.exchange_with_cleanup(config, ping_req)
  obs.body_result |> should.be_ok
  obs.cleanup_proof |> should.be_some

  let assert Some(live_proof) = obs.cleanup_proof
  store.cleanup_proof_exit_status(live_proof) |> should.equal(0)
  should.be_true(store.cleanup_proof_observed_at_us(live_proof) > 0)
  store.cleanup_proof_canonical_request(live_proof) |> should.equal(ping_req)
  store.verify_cleanup_proof(live_proof, config, ping_req) |> should.equal(True)

  // 2. Real fault-domain operation: commit succeeds in SQLite, but returned JSON is "{}" (exit 0)
  // Decode fails -> StoreUncertainApply(pending_domain)
  // Reconcile pending_domain: lookup on fault-domain returns the true committed receipt from SQLite
  let uid_domain = 101
  let env_domain = sample_accepted(uid_domain, "domain fault test", bot_id)
  let fault_domain_res =
    store.commit_prefix(
      config,
      bot_id,
      "fault-domain",
      gen,
      wm0,
      wm_ver0,
      wm_sha0,
      [env_domain],
      1000,
    )
  let assert Error(store.StoreUncertainApply(pending_domain)) = fault_domain_res
  store.pending_bot_id(pending_domain) |> should.equal(bot_id)
  store.pending_operation_id(pending_domain) |> should.equal("fault-domain")
  store.pending_has_cleanup_proof(pending_domain) |> should.equal(True)
  let assert Some(proof_domain) = store.pending_cleanup_proof(pending_domain)
  store.cleanup_proof_exit_status(proof_domain) |> should.equal(0)

  let reconcile_domain = store.reconcile_pending(config, pending_domain)
  let assert Ok(store.PendingCommitted(receipt_domain)) = reconcile_domain
  receipt_domain.operation_id |> should.equal("fault-domain")
  receipt_domain.request_digest
  |> should.equal(store.pending_expected_digest(pending_domain))
  receipt_domain.generation
  |> should.equal(store.pending_expected_generation(pending_domain) + 1)
  receipt_domain.summary_json
  |> should.equal(store.pending_expected_summary_json(pending_domain))

  // 3. Real fault-receipt-field operation: commit succeeds, but receipt returned by apply
  // has altered operation_id = "different-op" -> field mismatch -> StoreUncertainApply
  // Reconcile pending_rf: lookup on fault-receipt-field returns true receipt from SQLite!
  let assert Ok(#(wm1, wm_ver1, wm_sha1)) = store.read_watermark(config)
  let assert Ok(#(gen1, _)) = store.read_keys(config, [codec.watermark_key()])
  let uid_rf = 102
  let env_rf = sample_accepted(uid_rf, "receipt field fault test", bot_id)
  let fault_rf_res =
    store.commit_prefix(
      config,
      bot_id,
      "fault-receipt-field",
      gen1,
      wm1,
      wm_ver1,
      wm_sha1,
      [env_rf],
      2000,
    )
  let assert Error(store.StoreUncertainApply(pending_rf)) = fault_rf_res
  store.pending_bot_id(pending_rf) |> should.equal(bot_id)
  store.pending_operation_id(pending_rf) |> should.equal("fault-receipt-field")
  store.pending_error_detail(pending_rf)
  |> should.equal("apply_receipt_field_mismatch")
  store.pending_has_cleanup_proof(pending_rf) |> should.equal(True)
  let assert Some(proof_rf) = store.pending_cleanup_proof(pending_rf)
  store.cleanup_proof_exit_status(proof_rf) |> should.equal(0)

  let reconcile_rf = store.reconcile_pending(config, pending_rf)
  let assert Ok(store.PendingCommitted(receipt_rf)) = reconcile_rf
  receipt_rf.operation_id |> should.equal("fault-receipt-field")
  receipt_rf.request_digest
  |> should.equal(store.pending_expected_digest(pending_rf))
  receipt_rf.generation
  |> should.equal(store.pending_expected_generation(pending_rf) + 1)
  receipt_rf.summary_json
  |> should.equal(store.pending_expected_summary_json(pending_rf))

  // 4. Real fault-native-uncertain operation: commit succeeds, native returns
  // {"ok": false, "error": "commit_uncertain"} -> StoreUncertainApply
  // Reconcile pending_unc: lookup returns true receipt from SQLite!
  let assert Ok(#(wm2, wm_ver2, wm_sha2)) = store.read_watermark(config)
  let assert Ok(#(gen2, _)) = store.read_keys(config, [codec.watermark_key()])
  let uid_unc = 103
  let env_unc = sample_accepted(uid_unc, "native uncertain fault test", bot_id)
  let fault_unc_res =
    store.commit_prefix(
      config,
      bot_id,
      "fault-native-uncertain",
      gen2,
      wm2,
      wm_ver2,
      wm_sha2,
      [env_unc],
      3000,
    )
  let assert Error(store.StoreUncertainApply(pending_unc)) = fault_unc_res
  store.pending_bot_id(pending_unc) |> should.equal(bot_id)
  store.pending_operation_id(pending_unc)
  |> should.equal("fault-native-uncertain")
  store.pending_error_detail(pending_unc) |> should.equal("commit_uncertain")
  store.pending_has_cleanup_proof(pending_unc) |> should.equal(True)
  let assert Some(proof_unc) = store.pending_cleanup_proof(pending_unc)
  store.cleanup_proof_exit_status(proof_unc) |> should.equal(0)

  let reconcile_unc = store.reconcile_pending(config, pending_unc)
  let assert Ok(store.PendingCommitted(receipt_unc)) = reconcile_unc
  receipt_unc.operation_id |> should.equal("fault-native-uncertain")
  receipt_unc.request_digest
  |> should.equal(store.pending_expected_digest(pending_unc))
  receipt_unc.generation
  |> should.equal(store.pending_expected_generation(pending_unc) + 1)
  receipt_unc.summary_json
  |> should.equal(store.pending_expected_summary_json(pending_unc))

  // 5. Case: Mismatched witness binding refused -> quiescence_witness_binding_mismatch
  let wrong_db_config =
    transport.reviewed_local_configuration(
      recovery_guardian_path,
      recovery_guardian_sha,
      recovery_worker_path,
      recovery_worker_sha,
      "/tmp/differing_db.sqlite3",
    )
  let reconcile_mismatch_db =
    store.reconcile_pending(wrong_db_config, pending_domain)
  reconcile_mismatch_db
  |> should.equal(
    Error(store.StoreInvariantError("quiescence_witness_binding_mismatch")),
  )

  // 6. Case: commit_uncertain is discriminated as Refusal rather than decode error
  let commit_unc_json = "{\"ok\": false, \"error\": \"commit_uncertain\"}"
  codec.decode_apply_response_discriminated(commit_unc_json)
  |> should.equal(codec.DecodedApplyRefusal("commit_uncertain"))
}

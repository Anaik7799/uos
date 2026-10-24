import cepaf_gleam/harness/telegram_action_proposal as proposal
import cepaf_gleam/harness/telegram_approval as approval
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_intent as action
import cepaf_gleam/harness/telegram_cancellation as cancel
import cepaf_gleam/harness/telegram_cancellation_record as record
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import gleeunit/should
import simplifile
import telegram_cancellation_test as signed

const bot = 333_444

const worker = "controller"

const reason = "Operator requested cancellation"

fn binding(update: Int) {
  action.Binding(
    bot,
    100,
    200,
    update,
    "cancel-plan",
    "controller",
    worker,
    1,
    9,
    string.repeat("a", 64),
    "nas-1.tail55d152.ts.net",
    "test-boot",
    action.Execution("mapping-1", "control-lease", 1, string.repeat("d", 64)),
  )
}

fn target() {
  action.Target("cancel-plan/job1", "job-worker", 1, 2_000_000_000_000)
}

fn fixture(update: Int) {
  signed.fixture(binding(update), target(), 1_000_000, 1_030_000, reason)
}

fn text() {
  "/tool cancel_job_lease cancel-plan/job1 -- " <> reason
}

fn config(path: String) {
  transport.reviewed_local_configuration(
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
    "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
    "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",
    path,
  )
}

fn with_store(run: fn(transport.LocalConfiguration) -> a) -> a {
  let dir =
    "/tmp/uos-cancel-durable-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let c = config(dir <> "/telegram.sqlite3")
  let assert Ok(_) = store.initialize_store(c, bot)
  run(c)
}

fn processing(c, update, raw) {
  let assert Ok(#(gen, _)) = store.read_keys(c, [codec.watermark_key()])
  let assert Ok(#(wm, v, h)) = store.read_watermark(c)
  let verdict =
    guard.AcceptedEnvelope(
      update,
      update + 1,
      100,
      200,
      files.digest(raw),
      raw,
      guard.classify_directive(raw),
      bot,
      None,
    )
  let assert Ok(prefix) =
    store.commit_prefix(
      c,
      bot,
      "prefix-" <> int.to_string(update),
      gen,
      wm,
      v,
      h,
      [verdict],
      1000,
    )
  let assert [inbox] = prefix.admitted_records
  let assert Ok(#(receipt, rec)) =
    store.claim_task_processing(
      c,
      bot,
      "claim-" <> int.to_string(update),
      prefix.receipt.generation,
      inbox,
      1,
      files.digest(codec.encode_inbox_record(inbox)),
      worker,
      1,
      2000,
    )
  #(receipt.generation, rec)
}

fn row(c, key) {
  let assert Ok(#(_, [r])) = store.read_keys(c, [key])
  r
}

fn save(c, gen, inbox, p) {
  store.persist_cancellation(
    c,
    gen,
    inbox,
    2,
    files.digest(codec.encode_inbox_record(inbox)),
    worker,
    1,
    p,
  )
}

pub fn recovery_record_round_trip_and_exact_lookup_test() {
  let #(p, _, _, _, _) = fixture(10)
  let rec = cancel.recovery_record(p)
  let assert Ok(restored) = record.decode(record.encode(rec))
  record.same_request(rec, restored) |> should.be_true
  cancel.recovery_envelope(restored)
  |> should.equal(cancel.envelope(p, cancel.Lookup))
  record.deadline_ms(restored) |> should.equal(1_030_000)
}

fn encoded(i, deadline, request, hash) {
  json.object([
    #("schema", json.string("uos.telegram.cancellation-record.v1")),
    #("intent_json", json.string(i)),
    #("deadline_ms", json.int(deadline)),
    #("request_json", json.string(request)),
    #("request_hash", json.string(hash)),
  ])
  |> json.to_string
}

pub fn recovery_record_rejects_tamper_and_noncanonical_intent_test() {
  let #(p, i, _, _, _) = fixture(10)
  let rec = cancel.recovery_record(p)
  let raw = record.encode(rec)
  let intent = action.canonical_json(i)
  list.each(
    [
      "",
      "{}",
      "[]",
      string.repeat("x", 16_385),
      string.replace(
        raw,
        "\"deadline_ms\":1030000",
        "\"deadline_ms\":1030000,\"deadline_ms\":1030000",
      ),
      string.replace(
        raw,
        "\"deadline_ms\":1030000",
        "\"deadline_ms\":1030000.0",
      ),
      string.replace(
        raw,
        "\"deadline_ms\":1030000",
        "\"deadline_ms\":1030000,\"extra\":0",
      ),
      encoded(
        intent,
        1_030_000,
        record.request_json(rec),
        string.repeat("f", 64),
      ),
      encoded(
        intent,
        1_040_000,
        record.request_json(rec),
        record.request_hash(rec),
      ),
      encoded(
        " " <> intent,
        1_030_000,
        record.request_json(rec),
        record.request_hash(rec),
      ),
      encoded(
        string.replace(intent, "action-intent.v2", "action-intent.v1"),
        1_030_000,
        record.request_json(rec),
        record.request_hash(rec),
      ),
      encoded(
        intent,
        1_030_000,
        record.request_json(rec) <> " ",
        record.request_hash(rec),
      ),
    ],
    fn(bad) { record.decode(bad) |> result.is_error |> should.be_true },
  )
}

pub fn native_persistence_replay_and_collision_test() {
  use c <- with_store()
  let #(gen, inbox) = processing(c, 10, text())
  let #(p, i, _, _, _) = fixture(10)
  let assert Ok(saved) = save(c, gen, inbox, p)
  let key = store.cancellation_key(inbox.request_id)
  let before = row(c, key)
  let assert Ok(again) = save(c, store.cancellation_generation(saved), inbox, p)
  store.cancellation_generation(again)
  |> should.equal(store.cancellation_generation(saved))
  row(c, key) |> should.equal(before)
  let #(changed, _, _, _, _) =
    signed.fixture(binding(10), target(), 1_000_000, 1_020_000, reason)
  save(c, store.cancellation_generation(saved), inbox, changed)
  |> should.be_error
  row(c, key) |> should.equal(before)
  let assert Ok(restored) =
    store.load_cancellation(
      c,
      store.cancellation_generation(saved),
      inbox,
      2,
      files.digest(codec.encode_inbox_record(inbox)),
      worker,
      1,
    )
  let rec = store.cancellation_record_value(restored)
  record.intent(rec) |> action.digest |> should.equal(action.digest(i))
  record.request_json(rec) |> should.equal(cancel.request_json(p))
  row(c, codec.result_key(inbox.request_id)).exists |> should.be_false
}

pub fn native_stale_authority_identity_and_input_refuse_test() {
  use c <- with_store()
  let #(gen, inbox) = processing(c, 10, text())
  let #(p, _, _, _, _) = fixture(10)
  let sha = files.digest(codec.encode_inbox_record(inbox))
  store.persist_cancellation(c, gen, inbox, 2, sha, "other", 1, p)
  |> should.be_error
  store.persist_cancellation(c, gen, inbox, 2, sha, worker, 2, p)
  |> should.be_error
  save(c, gen - 1, inbox, p) |> should.be_error
  let #(wrong, _, _, _, _) = fixture(11)
  save(c, gen, inbox, wrong) |> should.be_error
  row(c, store.cancellation_key(inbox.request_id)).exists |> should.be_false
  let #(nextgen, other) = processing(c, 11, "/status")
  let #(otherp, _, _, _, _) = fixture(11)
  save(c, nextgen, other, otherp) |> should.be_error
  row(c, store.cancellation_key(other.request_id)).exists |> should.be_false
}

pub fn native_unresolved_lookup_does_not_create_reply_test() {
  use c <- with_store()
  let #(gen, inbox) = processing(c, 10, text())
  let #(p, _, _, _, _) = fixture(10)
  let assert Ok(saved) = save(c, gen, inbox, p)
  let absent =
    "{\"schema\":\"uos.telegram.cancel-transport-response.v1\",\"status\":\"ok\",\"error\":null,\"result\":{\"schema\":\"uos.sa-plan.cancel-job-response.v1\",\"found\":false,\"historical\":true,\"receipt\":null}}"
  store.commit_cancellation_lookup(saved, absent, 1_090_000) |> should.be_error
  store.commit_cancellation_lookup(saved, "{}", 1_090_000) |> should.be_error
  row(c, codec.result_key(inbox.request_id)).exists |> should.be_false
  row(c, codec.chunk_key(inbox.request_id, 0)).exists |> should.be_false
}

pub fn native_exact_lookup_commits_truthful_outbox_test() {
  use c <- with_store()
  let #(gen, inbox) = processing(c, 10, text())
  let #(p, i, _, _, _) = fixture(10)
  let assert Ok(saved) = save(c, gen, inbox, p)
  let lookup = signed.receipt(p, i, True)
  let assert Ok(done) =
    store.commit_cancellation_lookup(saved, lookup, 1_090_000)
  let assert ledger.InboxResultReady(_) = done.inbox_record.status
  let assert Ok(raw) =
    codec.decode_row_value(row(c, codec.chunk_key(inbox.request_id, 0)))
  let assert Ok(chunk) = codec.decode_chunk_value(raw)
  chunk.status |> should.equal(ledger.OutboxPending)
  chunk.payload
  |> should.equal(
    "Cancellation recorded: the job lease was revoked. Worker termination is not confirmed.",
  )
  let assert Ok(replay) =
    store.commit_cancellation_lookup(saved, lookup, 1_090_000)
  replay.receipt.generation |> should.equal(done.receipt.generation)
}

pub fn native_unrelated_generation_change_refuses_stale_reply_test() {
  use c <- with_store()
  let #(gen, inbox) = processing(c, 10, text())
  let #(p, i, _, _, _) = fixture(10)
  let assert Ok(saved) = save(c, gen, inbox, p)
  let _ = processing(c, 11, "/status")
  store.commit_cancellation_lookup(saved, signed.receipt(p, i, True), 1_090_000)
  |> should.be_error
  row(c, codec.result_key(inbox.request_id)).exists |> should.be_false
}

type TimeUnit {
  Millisecond
}

@external(erlang, "erlang", "system_time")
fn time(unit: TimeUnit) -> Int

/// First isolated BEAM process: durable request then actual effect; no outbox.
pub fn execute_without_reply(
  native: transport.LocalConfiguration,
  tg_path: String,
  mapping: String,
  fence: Int,
  lease: Int,
  artifact: String,
) {
  let c = config(tg_path)
  let assert Ok(_) = store.initialize_store(c, bot)
  let #(gen, inbox) = processing(c, 10, text())
  let created = time(Millisecond)
  let b =
    action.Binding(
      ..binding(10),
      candidate_sha256: artifact,
      execution: action.Execution(
        mapping,
        "control-lease",
        fence,
        string.repeat("d", 64),
      ),
    )
  let t = action.Target(..target(), lease_until_ns: lease)
  let #(p, _, roster, _, observation) =
    signed.fixture(b, t, created, created + 30_000, reason)
  let assert Ok(saved) = save(c, gen, inbox, p)
  cancel.ready(p, roster, b, t, observation) |> should.be_true
  record.request_json(store.cancellation_record_value(saved))
  |> should.equal(cancel.request_json(p))
  let assert Ok(raw) =
    transport.exchange(native, cancel.envelope(p, cancel.Cancel))
  let assert Ok(cancel.LeaseRevoked(_, _, False)) =
    cancel.decode_response(p, cancel.Cancel, raw, time(Millisecond))
  row(c, codec.result_key(inbox.request_id)).exists |> should.be_false
  "effect_committed_reply_absent"
}

/// Fresh isolated BEAM process: no key generation, signatures or Prepared.
pub fn recover_and_reply(
  native: transport.LocalConfiguration,
  tg_path: String,
) {
  let c = config(tg_path)
  let assert Ok(#(gen, [#(inbox, v, h)])) =
    store.read_inbox_records(c, 10, None)
  let assert Ok(saved) = store.load_cancellation(c, gen, inbox, v, h, worker, 1)
  let data = store.cancellation_record_value(saved)
  let assert Ok(response) =
    transport.exchange(native, cancel.recovery_envelope(data))
  let assert Ok(done) =
    store.commit_cancellation_lookup(saved, response, time(Millisecond))
  let assert ledger.InboxResultReady(_) = done.inbox_record.status
  let assert Ok(raw) =
    codec.decode_row_value(row(c, codec.chunk_key(inbox.request_id, 0)))
  let assert Ok(chunk) = codec.decode_chunk_value(raw)
  chunk.status |> should.equal(ledger.OutboxPending)
  chunk.payload
}

fn pending_proposal_input(c,update,raw) {
  let assert Ok(#(gen,_))=store.read_keys(c,[codec.watermark_key()])
  let assert Ok(#(wm,v,h))=store.read_watermark(c)
  let verdict=guard.AcceptedEnvelope(update,update+1,100,200,files.digest(raw),raw,
    guard.classify_directive(raw),bot,None)
  let assert Ok(prefix)=store.commit_prefix(c,bot,"proposal-prefix-"<>int.to_string(update),
    gen,wm,v,h,[verdict],1000)
  let assert [inbox]=prefix.admitted_records
  #(prefix.receipt.generation,inbox)
}
fn proposal_fixture(update) {
  let #(_,i,r,_,_)=fixture(update)
  let assert Ok(p)=proposal.new(ledger.make_request_id(bot,update),i,approval.roster_digest(r))
  p
}
pub fn proposal_codec_roundtrip_bounds_and_non_authority_test() {
  let p=proposal_fixture(10)
  let raw=proposal.encode(p)
  let assert Ok(decoded)=proposal.decode(raw)
  proposal.encode(decoded) |> should.equal(raw)
  proposal.receipts(decoded) |> should.equal([])
  let one=approval.Receipt(approval.Codex,"data-not-authority")
  let assert Ok(p1)=proposal.with_receipts(p,[one])
  proposal.extends(p,p1) |> should.be_true
  proposal.extends(p1,p) |> should.be_false
  proposal.with_receipts(p,[one,one]) |> should.be_error
  proposal.with_receipts(p,[approval.Receipt(approval.Codex,string.repeat("x",8193))])
    |> should.be_error
  list.each(["","{}",raw<>"[]",string.replace(raw,"action-proposal.v1","unknown"),
    string.repeat("x",65537)],fn(x){proposal.decode(x) |> should.be_error})
  proposal.new("tg-wrong",proposal.intent(p),proposal.roster_digest(p)) |> should.be_error
}
pub fn native_proposal_preserves_pending_and_reopens_exact_bytes_test() {
  use c <- with_store()
  let #(gen,inbox)=pending_proposal_input(c,10,text())
  let p=proposal_fixture(10)
  let assert Ok(next)=store.save_proposal(c,gen,inbox,p)
  let saved=row(c,store.proposal_key(inbox.request_id))
  let assert Ok(raw)=codec.decode_row_value(saved)
  raw |> should.equal(proposal.encode(p))
  // Every read is a new bounded native worker opening the same SQLite store.
  row(c,store.proposal_key(inbox.request_id)) |> should.equal(saved)
  store.save_proposal(c,next,inbox,p) |> should.equal(Ok(next))
  row(c,codec.inbox_key(inbox.request_id)).sha256
    |> should.equal(files.digest(codec.encode_inbox_record(inbox)))
  row(c,codec.authority_key(inbox.request_id)).exists |> should.be_false
  row(c,store.cancellation_key(inbox.request_id)).exists |> should.be_false
  row(c,codec.result_key(inbox.request_id)).exists |> should.be_false
}
pub fn native_proposal_receipt_append_is_monotonic_and_idempotent_test() {
  use c <- with_store()
  let #(gen,inbox)=pending_proposal_input(c,10,text())
  let p=proposal_fixture(10)
  let assert Ok(p1)=proposal.with_receipts(p,[approval.Receipt(approval.Codex,"first")])
  store.save_proposal(c,gen,inbox,p1) |> should.be_error
  let assert Ok(g1)=store.save_proposal(c,gen,inbox,p)
  let assert Ok(g2)=store.save_proposal(c,g1,inbox,p1)
  let before=row(c,store.proposal_key(inbox.request_id))
  store.save_proposal(c,g2,inbox,p1) |> should.equal(Ok(g2))
  store.save_proposal(c,g2,inbox,p) |> should.be_error
  let assert Ok(replaced)=proposal.with_receipts(p,[approval.Receipt(approval.Codex,"other")])
  store.save_proposal(c,g2,inbox,replaced) |> should.be_error
  row(c,store.proposal_key(inbox.request_id)) |> should.equal(before)
  let assert Ok(p2)=proposal.with_receipts(p,[approval.Receipt(approval.Codex,"first"),
    approval.Receipt(approval.Operator,"second")])
  let assert Ok(_)=store.save_proposal(c,g2,inbox,p2)
  let assert Ok(raw)=codec.decode_row_value(row(c,store.proposal_key(inbox.request_id)))
  let assert Ok(restored)=proposal.decode(raw)
  proposal.receipts(restored) |> should.equal(proposal.receipts(p2))
}
pub fn native_proposal_changed_intent_generation_user_and_input_refused_test() {
  use c <- with_store()
  let #(gen,inbox)=pending_proposal_input(c,10,text())
  let p=proposal_fixture(10)
  store.save_proposal(c,gen-1,inbox,p) |> should.be_error
  store.save_proposal(c,gen,ledger.InboxRecord(..inbox,user_id:201),p) |> should.be_error
  store.save_proposal(c,gen,inbox,proposal_fixture(11)) |> should.be_error
  let assert Ok(g1)=store.save_proposal(c,gen,inbox,p)
  let before=row(c,store.proposal_key(inbox.request_id))
  let #(_,changed,_,_,_)=signed.fixture(binding(10),target(),1_000_000,1_020_000,"other reason")
  let assert Ok(replaced)=proposal.new(inbox.request_id,changed,proposal.roster_digest(p))
  store.save_proposal(c,g1,inbox,replaced) |> should.be_error
  row(c,store.proposal_key(inbox.request_id)) |> should.equal(before)
  let #(g2,other)=pending_proposal_input(c,11,"/status")
  store.save_proposal(c,g2,other,proposal_fixture(11)) |> should.be_error
  row(c,store.proposal_key(other.request_id)).exists |> should.be_false
}
pub fn native_proposal_cannot_modify_claimed_request_test() {
  use c <- with_store()
  let #(gen,inbox)=pending_proposal_input(c,10,text())
  let p=proposal_fixture(10)
  let assert Ok(g1)=store.save_proposal(c,gen,inbox,p)
  let before=row(c,store.proposal_key(inbox.request_id))
  let assert Ok(#(receipt,claimed))=store.claim_task_processing(c,bot,"proposal-claim",
    g1,inbox,1,files.digest(codec.encode_inbox_record(inbox)),worker,1,2000)
  store.save_proposal(c,receipt.generation,claimed,p) |> should.be_error
  store.save_proposal(c,receipt.generation,inbox,p) |> should.be_error
  row(c,store.proposal_key(inbox.request_id)) |> should.equal(before)
}
pub fn native_proposal_semantic_whitespace_command_matches_test() {
  use c <- with_store()
  let #(gen,inbox)=pending_proposal_input(c,10,
    "/action  cancel_job_lease  cancel-plan/job1 -- "<>reason)
  let assert Ok(_)=store.save_proposal(c,gen,inbox,proposal_fixture(10))
}

pub fn native_cancellation_semantic_whitespace_matches_test() {
 use c <- with_store()
 let #(gen,inbox)=processing(c,10,"/action  cancel_job_lease  cancel-plan/job1 -- "<>reason)
 let #(p,_,_,_,_)=fixture(10)
 let assert Ok(_)=save(c,gen,inbox,p)
}

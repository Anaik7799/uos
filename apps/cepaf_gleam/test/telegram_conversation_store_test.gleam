import gleam/string
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_delivery_ledger as ledger
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import simplifile

const bot = 333_444
const day = 20000
const worker = "conversation-test"

fn with_store(run: fn(transport.LocalConfiguration) -> a) -> a {
  let dir = "/tmp/uos-conversation-store-" <> int.to_string(int.random(1_000_000_000))
  let assert Ok(_) = simplifile.create_directory_all(dir)
  let assert Ok(_) = simplifile.set_permissions_octal(dir, 0o700)
  let config = transport.reviewed_local_configuration(
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
    "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
    "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",
    dir <> "/telegram.sqlite3",
  )
  let assert Ok(_) = store.initialize_store(config, bot)
  run(config)
}

fn processing(config: transport.LocalConfiguration, update: Int, chat: Int, user: Int, text: String) {
  let assert Ok(#(gen, _)) = store.read_keys(config, [codec.watermark_key()])
  let assert Ok(#(wm, ver, sha)) = store.read_watermark(config)
  let verdict = guard.AcceptedEnvelope(
    update, update + 1, chat, user, files.digest(text), text,
    guard.classify_directive(text), bot, None,
  )
  let assert Ok(prefix) = store.commit_prefix(
    config, bot, "prefix-" <> int.to_string(update), gen, wm, ver, sha, [verdict], 1000,
  )
  let assert [inbox] = prefix.admitted_records
  let assert Ok(#(receipt, rec)) = store.claim_task_processing(
    config, bot, "claim-" <> int.to_string(update), prefix.receipt.generation,
    inbox, 1, files.digest(codec.encode_inbox_record(inbox)), worker, 1, 2000,
  )
  #(receipt.generation, rec)
}

fn reserve(config: transport.LocalConfiguration, gen: Int, rec: ledger.InboxRecord, limit: Int) {
  store.reserve_conversation(config, gen, rec, 2,
    files.digest(codec.encode_inbox_record(rec)), worker, 1, day, limit)
}

fn row(config: transport.LocalConfiguration, key: String) {
  let assert Ok(#(_, [r])) = store.read_keys(config, [key])
  r
}

fn context(config: transport.LocalConfiguration, chat: Int, user: Int) {
  let scope = conv.Scope(bot, chat, user)
  let assert Ok(key) = conv.context_key(scope)
  let assert Ok(raw) = codec.decode_row_value(row(config, key))
  let assert Ok(c) = conv.decode_context(raw, scope)
  c
}

fn budget(config: transport.LocalConfiguration) {
  let assert Ok(key) = conv.budget_key(bot, day)
  let assert Ok(raw) = codec.decode_row_value(row(config, key))
  let assert Ok(b) = conv.decode_budget(raw, bot, day)
  b
}

pub fn native_reservation_precedes_context_and_atomic_reply_test() {
  use config <- with_store()
  let #(gen, rec) = processing(config, 10, 100, 200, "Hello")
  let assert Ok(reservation) = reserve(config, gen, rec, 10)
  budget(config).reserved_requests |> should.equal(1)
  let assert Ok(key) = conv.context_key(conv.Scope(bot,100,200))
  row(config,key).exists |> should.equal(False)
  store.conversation_context(reservation).turns |> should.equal([])
  store.conversation_prompt(reservation) |> should.equal("Hello")
  let assert Ok(committed) = store.commit_conversation_result(reservation, ["Hi"], Some("Hi"))
  context(config,100,200).turns |> should.equal([conv.Turn(10,"Hello","Hi")])
  let chunk_row = row(config,codec.chunk_key(rec.request_id,0))
  let assert Ok(raw) = codec.decode_row_value(chunk_row)
  let assert Ok(chunk) = codec.decode_chunk_value(raw)
  chunk.payload |> should.equal("Hi")
  chunk.status |> should.equal(ledger.OutboxPending)
  let assert ledger.InboxResultReady(_) = committed.inbox_record.status
}

pub fn native_failed_model_consumes_budget_without_partial_memory_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let assert Ok(reservation) = reserve(config,gen,rec,1)
  let assert Ok(_) = store.commit_conversation_result(reservation,["Assistant unavailable"],None)
  let assert Ok(key) = conv.context_key(conv.Scope(bot,100,200))
  row(config,key).exists |> should.equal(False)
  budget(config).reserved_requests |> should.equal(1)
  let #(gen2,rec2) = processing(config,11,100,200,"Try again")
  let assert Error(_) = reserve(config,gen2,rec2,1)
  budget(config).reserved_requests |> should.equal(1)
  row(config,codec.result_key(rec2.request_id)).exists |> should.equal(False)
}

pub fn native_context_isolation_and_persisted_history_test() {
  use config <- with_store()
  let #(gen,a) = processing(config,10,100,200,"User A")
  let assert Ok(ra) = reserve(config,gen,a,10)
  let assert Ok(_) = store.commit_conversation_result(ra,["Reply A"],Some("Reply A"))
  let #(gen2,b) = processing(config,11,100,201,"User B")
  let assert Ok(rb) = reserve(config,gen2,b,10)
  store.conversation_context(rb).turns |> should.equal([])
  let assert Ok(_) = store.commit_conversation_result(rb,["Reply B"],Some("Reply B"))
  let #(gen3,a2) = processing(config,12,100,200,"User A again")
  let assert Ok(ra2) = reserve(config,gen3,a2,10)
  store.conversation_context(ra2).turns |> should.equal([conv.Turn(10,"User A","Reply A")])
  let assert Ok(_) = store.commit_conversation_result(ra2,["Reply A2"],Some("Reply A2"))
  list.length(context(config,100,200).turns) |> should.equal(2)
  context(config,100,201).turns |> should.equal([conv.Turn(11,"User B","Reply B")])
  budget(config).reserved_requests |> should.equal(3)
}

pub fn native_stale_worker_hash_and_generation_reservations_refused_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let sha = files.digest(codec.encode_inbox_record(rec))
  store.reserve_conversation(config,gen,rec,2,sha,"wrong-worker",1,day,10) |> should.be_error
  store.reserve_conversation(config,gen,rec,2,files.digest("wrong"),worker,1,day,10) |> should.be_error
  reserve(config,gen-1,rec,10) |> should.be_error
  let assert Ok(key) = conv.budget_key(bot,day)
  row(config,key).exists |> should.equal(False)
  let assert Ok(_) = reserve(config,gen,rec,10)
  budget(config).reserved_requests |> should.equal(1)
}

pub fn native_memory_outbox_mismatch_refuses_atomic_result_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let assert Ok(r) = reserve(config,gen,rec,10)
  store.commit_conversation_result(r,["Actual reply"],Some("Different memory")) |> should.be_error
  let assert Ok(key) = conv.context_key(conv.Scope(bot,100,200))
  row(config,key).exists |> should.equal(False)
  row(config,codec.result_key(rec.request_id)).exists |> should.equal(False)
  let assert Ok(_) = store.commit_conversation_result(r,["Actual reply"],Some("Actual reply"))
  context(config,100,200).turns |> should.equal([conv.Turn(10,"Hello","Actual reply")])
}

pub fn native_replayed_result_does_not_append_or_charge_twice_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let assert Ok(r) = reserve(config,gen,rec,10)
  let assert Ok(first) = store.commit_conversation_result(r,["Hi"],Some("Hi"))
  let assert Ok(second) = store.commit_conversation_result(r,["Hi"],Some("Hi"))
  first.receipt.generation |> should.equal(second.receipt.generation)
  list.length(context(config,100,200).turns) |> should.equal(1)
  budget(config).reserved_requests |> should.equal(1)
  reserve(config,gen,rec,10) |> should.be_error
}

pub fn native_generation_conflict_leaves_no_partial_memory_or_reply_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let assert Ok(r) = reserve(config,gen,rec,10)
  let _ = processing(config,11,100,201,"Concurrent input")
  store.commit_conversation_result(r,["Hi"],Some("Hi")) |> should.be_error
  let assert Ok(key) = conv.context_key(conv.Scope(bot,100,200))
  row(config,key).exists |> should.equal(False)
  row(config,codec.result_key(rec.request_id)).exists |> should.equal(False)
  row(config,codec.chunk_key(rec.request_id,0)).exists |> should.equal(False)
  budget(config).reserved_requests |> should.equal(1)
}

pub fn native_agy_prompt_is_bound_to_persisted_input_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"/agy explain leases")
  let assert Ok(r) = reserve(config,gen,rec,10)
  store.conversation_prompt(r) |> should.equal("explain leases")
  let assert Ok(_) = store.commit_conversation_result(r,["A lease expires."],Some("A lease expires."))
  context(config,100,200).turns |> should.equal([conv.Turn(10,"explain leases","A lease expires.")])
  let #(gen2,rec2) = processing(config,11,100,200,"/doctor")
  reserve(config,gen2,rec2,10) |> should.be_error
  budget(config).reserved_requests |> should.equal(1)
}

pub fn with_reserved_for_model_test(run: fn(store.ConversationReservation) -> a) -> a {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let assert Ok(r) = reserve(config,gen,rec,10)
  run(r)
}

fn memory(config: transport.LocalConfiguration, gen: Int, rec: ledger.InboxRecord) {
  store.prepare_memory_command(config,gen,rec,2,
    files.digest(codec.encode_inbox_record(rec)),worker,1)
}

fn seed_memory(config: transport.LocalConfiguration) {
  let #(gen,rec) = processing(config,10,100,200,"Hello")
  let assert Ok(r) = reserve(config,gen,rec,10)
  let assert Ok(_) = store.commit_conversation_result(r,["Hi"],Some("Hi"))
  Nil
}

pub fn native_memory_clear_and_confirmation_are_atomic_test() {
  use config <- with_store()
  seed_memory(config)
  let #(gen,rec) = processing(config,11,100,200,"/memory clear")
  let assert Ok(observation) = memory(config,gen,rec)
  list.length(context(config,100,200).turns) |> should.equal(1)
  let text = store.memory_reply(observation)
  let assert Ok(first) = store.commit_memory_result(observation,[text])
  context(config,100,200).turns |> should.equal([])
  budget(config).reserved_requests |> should.equal(1)
  let assert Ok(raw) = codec.decode_row_value(row(config,codec.chunk_key(rec.request_id,0)))
  let assert Ok(chunk) = codec.decode_chunk_value(raw)
  chunk.payload |> should.equal(text)
  let assert Ok(replay) = store.commit_memory_result(observation,[text])
  replay.receipt.generation |> should.equal(first.receipt.generation)
}

pub fn native_memory_history_is_scoped_and_does_not_charge_test() {
  use config <- with_store()
  seed_memory(config)
  let #(gen,rec) = processing(config,11,100,201,"/history")
  let assert Ok(other) = memory(config,gen,rec)
  string.contains(store.memory_reply(other),"No stored conversation history") |> should.equal(True)
  let assert Ok(_) = store.commit_memory_result(other,[store.memory_reply(other)])
  let #(gen2,rec2) = processing(config,12,100,200,"/messages 1")
  let assert Ok(own) = memory(config,gen2,rec2)
  string.contains(store.memory_reply(own),"You: Hello") |> should.equal(True)
  string.contains(store.memory_reply(own),"Assistant: Hi") |> should.equal(True)
  let assert Ok(_) = store.commit_memory_result(own,[store.memory_reply(own)])
  budget(config).reserved_requests |> should.equal(1)
  list.length(context(config,100,200).turns) |> should.equal(1)
}

pub fn native_memory_clear_conflict_keeps_history_and_no_confirmation_test() {
  use config <- with_store()
  seed_memory(config)
  let #(gen,rec) = processing(config,11,100,200,"/memory reset")
  let assert Ok(observation) = memory(config,gen,rec)
  let _ = processing(config,12,100,201,"/memory")
  store.commit_memory_result(observation,[store.memory_reply(observation)]) |> should.be_error
  list.length(context(config,100,200).turns) |> should.equal(1)
  row(config,codec.result_key(rec.request_id)).exists |> should.equal(False)
  row(config,codec.chunk_key(rec.request_id,0)).exists |> should.equal(False)
}

pub fn native_memory_reply_mismatch_and_forged_scope_refused_test() {
  use config <- with_store()
  seed_memory(config)
  let #(gen,rec) = processing(config,11,100,200,"/memory clear")
  let forged = ledger.InboxRecord(..rec,user_id:201)
  memory(config,gen,forged) |> should.be_error
  let assert Ok(observation) = memory(config,gen,rec)
  store.commit_memory_result(observation,["False confirmation"]) |> should.be_error
  list.length(context(config,100,200).turns) |> should.equal(1)
  row(config,codec.result_key(rec.request_id)).exists |> should.equal(False)
}

pub fn native_memory_empty_clear_allocates_no_context_or_quota_test() {
  use config <- with_store()
  let #(gen,rec) = processing(config,10,100,200,"/memory clear")
  let assert Ok(observation) = memory(config,gen,rec)
  let assert Ok(_) = store.commit_memory_result(observation,[store.memory_reply(observation)])
  let assert Ok(ctx_key) = conv.context_key(conv.Scope(bot,100,200))
  let assert Ok(quota_key) = conv.budget_key(bot,day)
  row(config,ctx_key).exists |> should.equal(False)
  row(config,quota_key).exists |> should.equal(False)
}

pub fn native_memory_invalid_arguments_leave_context_unchanged_test() {
  use config <- with_store()
  seed_memory(config)
  let #(gen,rec) = processing(config,11,100,200,"/memory clear everything")
  let assert Ok(observation) = memory(config,gen,rec)
  string.contains(store.memory_reply(observation),"Usage:") |> should.equal(True)
  let assert Ok(_) = store.commit_memory_result(observation,[store.memory_reply(observation)])
  list.length(context(config,100,200).turns) |> should.equal(1)
  budget(config).reserved_requests |> should.equal(1)
}

// Test-only mixed-schema seed through the actual native CAS protocol.
fn seed_mixed(config: transport.LocalConfiguration) {
  seed_memory(config)
  let scope=conv.Scope(bot,100,200)
  let assert Ok(key)=conv.context_key(scope)
  let assert Ok(#(gen,[before]))=store.read_keys(config,[key])
  let assert Ok(mixed)=conv.append(context(config,100,200),
    conv.MiniTurn("0123456789abcdef0123456789abcdef","Mini prompt","Mini reply"))
  let assert Ok(raw)=conv.encode_context(mixed)
  let rs=[codec.ReadSetAssertion(key,before.version,before.sha256)]
  let changes=[codec.Change(key,before.version,before.sha256,codec.encode_canonical_base64(raw))]
  let delta=codec.ReservationDelta(0,0)
  let op="test-seed-mixed"
  let digest=codec.compute_apply_digest(bot,op,gen,rs,changes,delta,"{}")
  let req=codec.encode_apply_command(bot,op,digest,gen,rs,changes,delta,"{}",None)
  let assert Ok(response)=transport.exchange(config,req)
  let assert codec.DecodedApplySuccess(_)=codec.decode_apply_response_discriminated(response)
  mixed
}
pub fn native_v2_poll_append_preserves_mini_history_test() {
  use config <- with_store()
  let mixed=seed_mixed(config)
  let #(gen,rec)=processing(config,11,100,200,"Continue from Telegram")
  let assert Ok(res)=reserve(config,gen,rec,10)
  store.conversation_context(res) |> should.equal(mixed)
  let assert Ok(_)=store.commit_conversation_result(res,["Continued"],Some("Continued"))
  let actual=context(config,100,200)
  actual.turns |> should.equal(list.append(mixed.turns,[conv.Turn(11,"Continue from Telegram","Continued")]))
  budget(config).reserved_requests |> should.equal(2)
}
pub fn native_v2_memory_history_then_reset_test() {
  use config <- with_store()
  let _=seed_mixed(config)
  let #(gen,rec)=processing(config,11,100,200,"/history")
  let assert Ok(obs)=memory(config,gen,rec)
  string.contains(store.memory_reply(obs),"Mini prompt") |> should.be_true
  let assert Ok(_)=store.commit_memory_result(obs,[store.memory_reply(obs)])
  let #(gen2,rec2)=processing(config,12,100,200,"/memory reset")
  let assert Ok(reset)=memory(config,gen2,rec2)
  let assert Ok(_)=store.commit_memory_result(reset,[store.memory_reply(reset)])
  context(config,100,200).turns |> should.equal([])
  let assert Ok(key)=conv.context_key(conv.Scope(bot,100,200))
  let assert Ok(raw)=codec.decode_row_value(row(config,key))
  string.contains(raw,"conversation.v1") |> should.be_true
  budget(config).reserved_requests |> should.equal(1)
}
pub fn native_v2_mini_clear_fences_poll_completion_test() {
  use config <- with_store()
  let _=seed_mixed(config)
  let #(gen,rec)=processing(config,11,100,200,"Inflight")
  let assert Ok(res)=reserve(config,gen,rec,10)
  let scope=conv.Scope(bot,100,200)
  let assert Ok(key)=conv.context_key(scope)
  let r=row(config,key)
  let assert Ok(clear)=store.prepare_mini_clear(config,scope,
    "mini-clear-"<>files.digest("mixed-clear"),r.version,r.sha256)
  let assert Ok(_)=store.commit_mini_clear(clear)
  store.commit_conversation_result(res,["Late"],Some("Late")) |> should.be_error
  context(config,100,200).turns |> should.equal([])
  budget(config).reserved_requests |> should.equal(2)
  row(config,codec.result_key(rec.request_id)).exists |> should.be_false
}


const mini_nonce = "0123456789abcdef0123456789abcdef"
const mini_nonce2 = "1123456789abcdef0123456789abcdef"
fn mini_job(nonce: String) { "mini-control/" <> files.digest(nonce) }
fn mini_prepare(config: transport.LocalConfiguration, nonce: String, limit: Int) {
  let scope=conv.Scope(bot,100,200)
  let assert Ok(key)=conv.context_key(scope)
  let r=row(config,key)
  store.prepare_mini_chat(config,scope,nonce,mini_job(nonce),"Mini question",
    r.version,r.sha256,day,limit)
}
pub fn mini_native_reservation_single_owner_and_receipt_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  budget(config).reserved_requests |> should.equal(1)
  store.mini_chat_context(res).turns |> should.equal([])
  store.mini_chat_prompt(res) |> should.equal("Mini question")
  // Same generation/operation bytes yield native replay, never a second capability.
  store.commit_mini_chat_reservation(draft) |> should.be_error
  mini_prepare(config,mini_nonce,10) |> should.be_error
  let assert Ok(done)=store.complete_mini_chat(res,Some("Mini answer"))
  context(config,100,200).turns |> should.equal([conv.MiniTurn(mini_nonce,"Mini question","Mini answer")])
  let assert Ok(found)=store.mini_chat_receipt(config,conv.Scope(bot,100,200),mini_nonce)
  found.receipt |> should.equal(Some(done.receipt))
  string.contains(done.receipt.summary_json,"\"status\":\"completed\"") |> should.be_true
  store.complete_mini_chat(res,Some("Mini answer")) |> should.be_error
  budget(config).reserved_requests |> should.equal(1)
}
pub fn mini_native_failed_model_no_history_and_no_refund_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,1)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  let assert Ok(done)=store.complete_mini_chat(res,None)
  string.contains(done.receipt.summary_json,"\"status\":\"model_failed\"") |> should.be_true
  let assert Ok(key)=conv.context_key(conv.Scope(bot,100,200))
  row(config,key).exists |> should.be_false
  budget(config).reserved_requests |> should.equal(1)
  mini_prepare(config,mini_nonce2,1) |> should.be_error
}
pub fn mini_native_unrelated_activity_does_not_lose_reply_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  let _=processing(config,10,100,201,"Other user")
  let assert Ok(_)=store.complete_mini_chat(res,Some("Answer"))
  context(config,100,200).turns |> should.equal([conv.MiniTurn(mini_nonce,"Mini question","Answer")])
}
pub fn mini_native_clear_during_model_records_terminal_conflict_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  let scope=conv.Scope(bot,100,200)
  let assert Ok(clear)=store.prepare_mini_clear(config,scope,
    "mini-clear-"<>files.digest("clear-during-mini"),0,"")
  let assert Ok(_)=store.commit_mini_clear(clear)
  let assert Ok(done)=store.complete_mini_chat(res,Some("Late answer"))
  string.contains(done.receipt.summary_json,"\"status\":\"context_changed\"") |> should.be_true
  string.contains(done.receipt.summary_json,"Late answer") |> should.be_false
  context(config,100,200).turns |> should.equal([])
  budget(config).reserved_requests |> should.equal(1)
  let assert Ok(found)=store.mini_chat_receipt(config,scope,mini_nonce)
  found.receipt |> should.equal(Some(done.receipt))
}
pub fn mini_native_competing_requests_only_one_history_append_test() {
  use config <- with_store()
  let assert Ok(a)=mini_prepare(config,mini_nonce,10)
  let assert Ok(ra)=store.commit_mini_chat_reservation(a)
  let assert Ok(b)=mini_prepare(config,mini_nonce2,10)
  let assert Ok(rb)=store.commit_mini_chat_reservation(b)
  let assert Ok(_)=store.complete_mini_chat(ra,Some("Winner"))
  let assert Ok(late)=store.complete_mini_chat(rb,Some("Not appended"))
  string.contains(late.receipt.summary_json,"context_changed") |> should.be_true
  context(config,100,200).turns |> should.equal([conv.MiniTurn(mini_nonce,"Mini question","Winner")])
  budget(config).reserved_requests |> should.equal(2)
}
pub fn mini_native_invalid_input_never_charges_test() {
  use config <- with_store()
  let scope=conv.Scope(bot,100,200)
  list.each(["", "invalid",string.repeat("a",33)],fn(n) {
    store.prepare_mini_chat(config,scope,n,mini_job(n),"Prompt",0,"",day,10) |> should.be_error
  })
  list.each(["",string.repeat("x",4097),"/home/private/secret.txt"],fn(prompt) {
    store.prepare_mini_chat(config,scope,mini_nonce,mini_job(mini_nonce),prompt,0,"",day,10) |> should.be_error
  })
  store.prepare_mini_chat(config,scope,mini_nonce,"bad-job","Prompt",0,"",day,10) |> should.be_error
  store.prepare_mini_chat(config,scope,mini_nonce,mini_job(mini_nonce),"Prompt",1,files.digest("stale"),day,10) |> should.be_error
  store.prepare_mini_chat(config,conv.Scope(999,100,200),mini_nonce,mini_job(mini_nonce),"Prompt",0,"",day,10) |> should.be_error
  mini_prepare(config,mini_nonce,0) |> should.be_error
  let assert Ok(key)=conv.budget_key(bot,day)
  row(config,key).exists |> should.be_false
}
pub fn mini_native_stale_preparation_never_authorizes_model_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let _=processing(config,10,100,201,"Other activity")
  store.commit_mini_chat_reservation(draft) |> should.be_error
  let assert Ok(key)=conv.budget_key(bot,day)
  row(config,key).exists |> should.be_false
  let assert Ok(request)=store.mini_chat_key(conv.Scope(bot,100,200),mini_nonce)
  row(config,request).exists |> should.be_false
}
pub fn mini_native_invalid_reply_and_other_scope_receipt_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  store.complete_mini_chat(res,Some("")) |> should.be_error
  let assert Ok(key)=conv.context_key(conv.Scope(bot,100,200))
  row(config,key).exists |> should.be_false
  let assert Ok(_)=store.complete_mini_chat(res,None)
  let assert Ok(other)=store.mini_chat_receipt(config,conv.Scope(bot,100,201),mini_nonce)
  other.found |> should.be_false
}

pub fn with_mini_reserved_for_model_test(run: fn(store.MiniChatReservation) -> a) -> a {
  use config <- with_store()
  let _=seed_mixed(config)
  let assert Ok(draft)=mini_prepare(config,mini_nonce2,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  run(res)
}

pub fn mini_native_abandon_releases_capacity_and_fences_late_reply_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  let scope=conv.Scope(bot,100,200)
  let assert Ok(close)=store.prepare_mini_chat_abandon(config,scope,mini_nonce,mini_job(mini_nonce),"Mini question",0,"")
  let assert Ok(done)=store.commit_mini_chat_abandon(close)
  string.contains(done.receipt.summary_json,"abandoned") |> should.be_true
  store.complete_mini_chat(res,Some("Late answer")) |> should.be_error
  budget(config).reserved_requests |> should.equal(1)
  let assert Ok(ctx)=conv.context_key(scope)
  row(config,ctx).exists |> should.be_false
  let assert Ok(found)=store.mini_chat_receipt(config,scope,mini_nonce)
  found.receipt |> should.equal(Some(done.receipt))
  let assert Ok(next)=mini_prepare(config,mini_nonce2,10)
  let assert Ok(next_res)=store.commit_mini_chat_reservation(next)
  let assert Ok(_)=store.complete_mini_chat(next_res,Some("Next explicit request"))
  list.length(context(config,100,200).turns) |> should.equal(1)
}
pub fn mini_native_abandon_binding_and_completion_race_test() {
  use config <- with_store()
  let assert Ok(draft)=mini_prepare(config,mini_nonce,10)
  let assert Ok(res)=store.commit_mini_chat_reservation(draft)
  let scope=conv.Scope(bot,100,200)
  store.prepare_mini_chat_abandon(config,scope,mini_nonce,mini_job(mini_nonce),"Changed prompt",0,"") |> should.be_error
  store.prepare_mini_chat_abandon(config,conv.Scope(bot,100,201),mini_nonce,mini_job(mini_nonce),"Mini question",0,"") |> should.be_error
  let assert Ok(close)=store.prepare_mini_chat_abandon(config,scope,mini_nonce,mini_job(mini_nonce),"Mini question",0,"")
  let assert Ok(_)=store.complete_mini_chat(res,Some("Completed first"))
  store.commit_mini_chat_abandon(close) |> should.be_error
  context(config,100,200).turns |> should.equal([conv.MiniTurn(mini_nonce,"Mini question","Completed first")])
}

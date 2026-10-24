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

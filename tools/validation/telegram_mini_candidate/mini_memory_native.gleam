//// Actual native-store falsifiers using an isolated, newly initialized fixture.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import gleam/io
import gleam/int
import gleam/option.{None, Some}
import mini_history_fixture as fixture

fn row(path: String, user: Int) {
  let assert Ok(key)=conv.context_key(conv.Scope(333444,user,user))
  let assert Ok(#(_, [r]))=store.read_keys(fixture.config(path),[key])
  r
}
fn clear(path: String,user: Int,id: String) {
  let r=row(path,user)
  let assert Ok(res)=store.prepare_mini_clear(fixture.config(path),conv.Scope(333444,user,user),
    "mini-clear-"<>files.digest(id),r.version,r.sha256)
  let assert Ok(done)=store.commit_mini_clear(res)
  done
}
fn reserve(path: String,update: Int,user: Int) {
  let c=fixture.config(path)
  let assert Ok(#(gen,_))=store.read_keys(c,[codec.watermark_key()])
  let assert Ok(#(wm,v,sha))=store.read_watermark(c)
  let prompt="inflight prompt"
  let verdict=guard.AcceptedEnvelope(update,update+1,user,user,files.digest(prompt),prompt,
    guard.classify_directive(prompt),333444,None)
  let assert Ok(p)=store.commit_prefix(c,333444,"prefix-"<>int.to_string(update),gen,wm,v,sha,[verdict],1000)
  let assert [r]=p.admitted_records
  let assert Ok(#(receipt,claimed))=store.claim_task_processing(c,333444,"claim-"<>int.to_string(update),
    p.receipt.generation,r,1,files.digest(codec.encode_inbox_record(r)),"memory-test",1,2000)
  let assert Ok(res)=store.reserve_conversation(c,receipt.generation,claimed,2,
    files.digest(codec.encode_inbox_record(claimed)),"memory-test",1,20000,100)
  res
}
pub fn run(path: String) {
  fixture.seed(path)
  let other=row(path,43)
  let assert Ok(budget)=conv.budget_key(333444,0)
  let assert Ok(#(_,untouched))=store.read_keys(fixture.config(path),[budget,codec.watermark_key()])
  let before=row(path,42)
  let first=clear(path,42,"first")
  let after=row(path,42)
  let assert Ok(#(_,untouched_after))=store.read_keys(fixture.config(path),[budget,codec.watermark_key()])
  let assert True = untouched_after == untouched
  let assert True=after.exists && after.version == before.version+1
  let assert Ok(raw)=codec.decode_row_value(after)
  let assert Ok(conv.Context(_,[]))=conv.decode_context(raw,conv.Scope(333444,42,42))
  let assert True=row(path,43)==other
  let assert Ok(found)=store.lookup_operation(fixture.config(path),first.receipt.operation_id)
  let assert True = found.receipt == Some(first.receipt)
  let _=clear(path,42,"empty-again")
  let assert True=row(path,42).version == after.version+1
  let assert Error(_)=store.prepare_mini_clear(fixture.config(path),conv.Scope(333444,42,42),
    "mini-clear-"<>files.digest("stale"),before.version,before.sha256)
  let populated_res=reserve(path,20,42)
  let _=clear(path,42,"fence-existing")
  let assert Error(_)=store.commit_conversation_result(populated_res,["late reply"],Some("late reply"))
  let absent_res=reserve(path,21,44)
  let absent=row(path,44)
  let assert False=absent.exists
  let _=clear(path,44,"fence-absent")
  let assert True=row(path,44).exists && row(path,44).version==1
  let assert Error(_)=store.commit_conversation_result(absent_res,["late reply"],Some("late reply"))
  let assert Error(_)=store.prepare_mini_clear(fixture.config(path),conv.Scope(999999,42,42),
    "mini-clear-"<>files.digest("wrongbot"),0,"")
  let r=row(path,42)
  let assert Ok(competing)=store.prepare_mini_clear(fixture.config(path),conv.Scope(333444,42,42),
    "mini-clear-"<>files.digest("competing"),r.version,r.sha256)
  let _=clear(path,42,"winner")
  let assert Error(_)=store.commit_mini_clear(competing)
  io.println("{\"status\":\"PASS\",\"checks\":11,\"scope\":\"actual_private_native_store\",\"cases\":[\"quota_and_watermark_unchanged\",\"populated_clear\",\"other_user_isolation\",\"native_receipt\",\"empty_advances_version\",\"stale_expected_refused\",\"inflight_existing_fenced\",\"absent_row_created\",\"inflight_absent_fenced\",\"wrong_bot_refused\",\"competing_generation_refused\"]}")
}

/// Test-only cut point: native commit without Sa-plan terminal result.
pub fn commit_for_job(path: String, job: String, version: Int, sha: String) {
  let assert Ok(r)=store.prepare_mini_clear(fixture.config(path),conv.Scope(333444,42,42),
    "mini-clear-"<>files.digest(job),version,sha)
  let assert Ok(_)=store.commit_mini_clear(r)
  Nil
}

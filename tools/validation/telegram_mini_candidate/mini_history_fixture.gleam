//// Private fixture writer only; no live Telegram or production state.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/telegram/mini_history
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import simplifile

fn config(path: String) {
  let assert True = string.starts_with(path,"/home/an/uos-agent-runtime/20261024-0555/mini-history-")
    && string.ends_with(path,"/history.sqlite3") && !string.contains(path,"..")
  transport.reviewed_local_configuration(
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
    "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
    "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
    "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",path)
}

pub fn initialize(path: String) {
  let assert Error(simplifile.Enoent) = simplifile.link_info(path)
  let assert Ok(_) = store.initialize_store(config(path),333444)
  Nil
}

pub fn append(path: String, update: Int, chat: Int, user: Int, prompt: String, reply: String) {
  let conf=config(path)
  let assert Ok(#(gen,_))=store.read_keys(conf,[codec.watermark_key()])
  let assert Ok(#(wm,version,sha))=store.read_watermark(conf)
  let verdict=guard.AcceptedEnvelope(update,update+1,chat,user,files.digest(prompt),prompt,guard.classify_directive(prompt),333444,None)
  let assert Ok(prefix)=store.commit_prefix(conf,333444,"prefix-"<>int.to_string(update),gen,wm,version,sha,[verdict],1000)
  let assert [inbox]=prefix.admitted_records
  let assert Ok(#(receipt,rec))=store.claim_task_processing(conf,333444,"claim-"<>int.to_string(update),
    prefix.receipt.generation,inbox,1,files.digest(codec.encode_inbox_record(inbox)),"mini-history-fixture",1,2000)
  let assert Ok(res)=store.reserve_conversation(conf,receipt.generation,rec,2,files.digest(codec.encode_inbox_record(rec)),
    "mini-history-fixture",1,20000,100)
  let assert Ok(_)=store.commit_conversation_result(res,mini_history.chunks(reply),Some(reply))
  Nil
}

pub fn seed(path: String) {
  initialize(path)
  append(path,10,42,42,"Private prompt owned by user42","Retained private reply42")
  append(path,11,43,43,"OTHER_USER_SECRET","Other user reply")
  append(path,12,-100123,42,"Granted group prompt","Granted group reply")
  append(path,13,-100124,42,"UNGRANTED_GROUP_SECRET","Ungrant group reply")
  append(path,14,42,43,"SAME_CHAT_OTHER_USER_SECRET","Other participant reply")
}

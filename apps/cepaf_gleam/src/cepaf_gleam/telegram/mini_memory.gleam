//// Development memory adapter: one profile binds reads and clear/reset writes.
import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_store as store
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/telegram_store_transport as transport
import cepaf_gleam/telegram/mini_history as history
import cepaf_gleam/harness/telegram_conversation as conv
import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub opaque type Configuration {
  Configuration(history: history.Configuration, transport: transport.LocalConfiguration)
}

pub fn configuration(raw: String, token: String) -> Result(Option(Configuration), String) {
  let grant = {
    use user <- decode.field("user_id",decode.int)
    use chat <- decode.field("chat_id",decode.int)
    decode.success(history.Grant(user,chat))
  }
  let memory = {
    use db <- decode.field("database",decode.string)
    use grants <- decode.field("grants",decode.list(grant))
    decode.success(#(db,grants))
  }
  let decoder = {
    use data <- decode.optional_field("memory",None,decode.optional(memory))
    decode.success(data)
  }
  use data <- result.try(json.parse(raw,decoder) |> result.replace_error("memory_profile_invalid"))
  case data {
    None -> Ok(None)
    Some(#(db,grants)) -> {
      use _ <- result.try(case string.starts_with(db,"/home/an/uos-agent-runtime/20261024-0555/mini-history-")
        && string.ends_with(db,"/history.sqlite3") && !string.contains(db,"..") {
        True -> Ok(Nil)
        False -> Error("memory_fixture_database_invalid")
      })
      use h <- result.try(history.configuration(token,grants))
      Ok(Some(Configuration(h,transport.reviewed_local_configuration(
        "/home/an/NAS-setup/uos/tools/validation/telegram_store_transport_guardian.exe",
        "06a278afd304bb4752522bd632004eb35ecff8a1b65459a3607a70b24e67f0ab",
        "/home/an/NAS-setup/uos/tools/validation/telegram_store_recovery_worker.exe",
        "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",db))))
    }
  }
}

pub fn scope(c: Configuration, user: Int, chat: Option(Int)) -> Result(conv.Scope,String) {
  history.resolve_scope(c.history,user,chat)
}

pub fn observe(c: Configuration, user: Int, chat: Option(Int), at: Int) {
  use s <- result.try(scope(c,user,chat))
  use key <- result.try(conv.context_key(s))
  use #(generation,rows) <- result.try(store.read_keys(c.transport,[codec.bot_identity_key(),key])
    |> result.replace_error("history_store_unavailable"))
  history.from_rows(s,generation,rows,at)
}

pub fn operation(job: String) -> String { "mini-clear-" <> files.digest(job) }

pub fn prepare(c: Configuration, user: Int, chat: Option(Int), job: String, version: Int, sha: String) {
  use s <- result.try(scope(c,user,chat))
  store.prepare_mini_clear(c.transport,s,operation(job),version,sha)
    |> result.replace_error("history_snapshot_mismatch_or_unavailable")
}

pub fn receipt(c: Configuration, user: Int, chat: Option(Int), job: String, version: Int, sha: String) {
  use s <- result.try(scope(c,user,chat))
  let op = operation(job)
  use found <- result.try(store.lookup_operation(c.transport,op)
    |> result.replace_error("history_receipt_unavailable"))
  let expected = store.mini_clear_summary(s,version,sha)
  case found.receipt {
    Some(r) if r.operation_id == op && r.summary_json == expected ->
      Ok(Some(r.summary_json))
    Some(_) -> Error("history_receipt_mismatch")
    None -> Ok(None)
  }
}

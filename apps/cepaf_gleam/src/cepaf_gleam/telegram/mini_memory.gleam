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
  Configuration(history: history.Configuration, transport: transport.LocalConfiguration, binding: String)
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
        "f4f249eaa6ff2c9f4b1bf8c6587426f283ec1754892e847568b5dd1712a55b1e",db),files.digest(db))))
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

pub fn storage_binding(c: Configuration) -> String { c.binding }
pub fn prepare_chat(c: Configuration,user: Int,chat: Option(Int),nonce: String,
  job: String,prompt: String,version: Int,sha: String,day: Int,limit: Int) {
  use s <- result.try(scope(c,user,chat))
  store.prepare_mini_chat(c.transport,s,nonce,job,prompt,version,sha,day,limit)
    |> result.replace_error("chat_snapshot_quota_or_store_refused")
}
/// Read-only recovery authenticates the current grant and every request field.
pub fn chat_receipt(c: Configuration,user: Int,chat: Option(Int),nonce: String,
  job: String,prompt: String,version: Int,sha: String) {
  use s <- result.try(scope(c,user,chat))
  use found <- result.try(store.mini_chat_receipt(c.transport,s,nonce)
    |> result.replace_error("chat_receipt_unavailable"))
  case found.receipt {
    None -> Ok(None)
    Some(r) -> {
      use _ <- result.try(validate_chat_receipt(r.summary_json,s,nonce,job,prompt,version,sha))
      Ok(Some(r.summary_json))
    }
  }
}
pub fn validate_chat_receipt(raw: String,s: conv.Scope,nonce: String,job: String,
  prompt: String,version: Int,sha: String) -> Result(Nil,String) {
  let decoder = {
    use schema <- decode.field("schema",decode.string)
    use bot <- decode.field("bot",decode.int)
    use chat <- decode.field("chat",decode.int)
    use user <- decode.field("user",decode.int)
    use request <- decode.field("request_id",decode.string)
    use bound_job <- decode.field("job",decode.string)
    use digest <- decode.field("prompt_sha256",decode.string)
    use v <- decode.field("context_version",decode.int)
    use hash <- decode.field("context_sha256",decode.string)
    use day <- decode.field("day",decode.int)
    use status <- decode.field("status",decode.string)
    use reply <- decode.field("reply",decode.optional(decode.string))
    decode.success(schema == "uos.telegram.mini-chat.v1" && bot == s.bot_id
      && chat == s.chat_id && user == s.user_id && request == nonce && bound_job == job
      && digest == files.digest(prompt) && v == version && hash == sha && day >= 0
      && case status,reply {
        "completed",Some(text) -> conv.append(conv.Context(s,[]),conv.MiniTurn(nonce,prompt,text))
          |> result.is_ok
        "model_failed",None | "context_changed",None | "abandoned",None -> True
        _,_ -> False
      })
  }
  case json.parse(raw,decoder) { Ok(True) -> Ok(Nil) _ -> Error("chat_receipt_mismatch") }
}

pub fn prepare_chat_abandon(c: Configuration,user: Int,chat: Option(Int),nonce: String,
  job: String,prompt: String,version: Int,sha: String) {
  use s <- result.try(scope(c,user,chat))
  store.prepare_mini_chat_abandon(c.transport,s,nonce,job,prompt,version,sha)
    |> result.replace_error("chat_not_pending_or_binding_mismatch")
}

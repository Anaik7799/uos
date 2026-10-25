//// Authenticated conversation-history projection over the existing durable store.
//// Reads only: no model request, history mutation, task claim or send.
import cepaf_gleam/harness/telegram_conversation as conv
import cepaf_gleam/harness/telegram_ingress_guard as guard
import cepaf_gleam/harness/telegram_store_codec as codec
import cepaf_gleam/harness/files
import cepaf_gleam/telegram/mini_api as api
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Grant {
  Grant(user_id: Int, chat_id: Int)
}

pub opaque type Configuration {
  Configuration(bot_id: Int, grants: List(Grant))
}

/// The bot identity comes from the same server token used by initData auth.
/// No token, arbitrary database key or unsigned chat selector is exposed.
pub fn configuration(token: String, grants: List(Grant)) -> Result(Configuration, String) {
  use prefix <- result.try(case string.split(token, ":") {
    [prefix, secret] if secret != "" -> Ok(prefix)
    _ -> Error("invalid_bot_token_identity")
  })
  use bot <- result.try(int.parse(prefix) |> result.replace_error("invalid_bot_identity"))
  case guard.valid_positive_id(bot) && int.to_string(bot) == prefix
    && grants != [] && list.length(grants) <= 256
    && list.length(list.unique(grants)) == list.length(grants)
    && list.all(grants, fn(g) { guard.valid_positive_id(g.user_id) && guard.valid_chat_id(g.chat_id) }) {
    True -> Ok(Configuration(bot, grants))
    False -> Error("invalid_history_configuration")
  }
}

/// Missing signed chat permits only an explicit private-chat grant for this user.
pub fn resolve_scope(config: Configuration, user: Int, chat: Option(Int)) -> Result(conv.Scope, String) {
  use target <- result.try(case chat {
    Some(id) -> case guard.valid_chat_id(id) { True -> Ok(id) False -> Error("invalid_chat") }
    None -> Ok(user)
  })
  case guard.valid_positive_id(user)
    && list.contains(config.grants, Grant(user, target))
    && case chat { None -> target == user Some(_) -> True } {
    True -> Ok(conv.Scope(config.bot_id, target, user))
    False -> Error("history_scope_not_granted")
  }
}

fn row(rows: List(codec.RowResult), key: String) -> Result(codec.RowResult, String) {
  list.find(rows, fn(r) { r.key == key }) |> result.replace_error("missing_history_row")
}

fn checked_value(r: codec.RowResult) -> Result(String, String) {
  use raw <- result.try(codec.decode_row_value(r))
  case r.exists && r.version > 0 && guard.valid_digest(r.sha256) && files.digest(raw) == r.sha256 {
    True -> Ok(raw)
    False -> Error("invalid_history_row")
  }
}

fn pad(n: Int) -> String {
  case n < 10 { True -> "0" <> int.to_string(n) False -> int.to_string(n) }
}

/// Preserve every codepoint; never silently truncate a stored exchange.
pub fn chunks(text: String) -> List(String) {
  let #(done, pending, _) = list.fold(string.to_utf_codepoints(text), #([], "", 0), fn(state, cp) {
    let #(done, pending, size) = state
    let next = string.from_utf_codepoints([cp])
    let bytes = string.byte_size(next)
    case size + bytes > 2048 {
      True -> #([pending, ..done], next, bytes)
      False -> #(done, pending <> next, size + bytes)
    }
  })
  list.reverse(case pending { "" -> done _ -> [pending, ..done] })
}

fn turn_fields(turn: conv.Turn, index: Int) -> List(#(String, String)) {
  let source = case turn {
    conv.Turn(id, ..) -> " update " <> int.to_string(id)
    conv.MiniTurn(id, ..) -> " Mini request " <> id
  }
  let prefix = "Exchange " <> pad(index + 1) <> source
  list.append(
    list.index_map(chunks(turn.prompt), fn(text, part) { #(prefix <> " · 1 You · " <> pad(part + 1), text) }),
    list.index_map(chunks(turn.reply), fn(text, part) { #(prefix <> " · 2 Assistant · " <> pad(part + 1), text) }),
  )
}

pub fn from_rows(scope: conv.Scope, generation: Int, rows: List(codec.RowResult), at: Int) -> Result(api.Observation, String) {
  use key <- result.try(conv.context_key(scope))
  let bot_key = codec.bot_identity_key()
  use _ <- result.try(case generation > 0 && at > 0 && list.length(rows) == 2
    && list.sort(list.map(rows, fn(r) { r.key }), string.compare)
      == list.sort([bot_key, key], string.compare) {
    True -> Ok(Nil)
    False -> Error("history_snapshot_binding")
  })
  use bot_row <- result.try(row(rows, bot_key))
  use bot_raw <- result.try(checked_value(bot_row))
  use bot <- result.try(codec.decode_bot_identity_value(bot_raw))
  use _ <- result.try(case bot == scope.bot_id { True -> Ok(Nil) False -> Error("history_database_bot_mismatch") })
  use context_row <- result.try(row(rows, key))
  use context <- result.try(case context_row.exists {
    False -> case context_row.version == 0 && context_row.sha256 == "" && context_row.canonical_value_base64 == "" {
      True -> Ok(conv.Context(scope, []))
      False -> Error("invalid_absent_history")
    }
    True -> {
      use raw <- result.try(checked_value(context_row))
      conv.decode_context(raw, scope)
    }
  })
  let fields = list.append([
    #("Bot", int.to_string(scope.bot_id)),
    #("Chat", int.to_string(scope.chat_id)),
    #("User", int.to_string(scope.user_id)),
    #("Generation", int.to_string(generation)),
    #("Context version", int.to_string(context_row.version)),
    #("Context SHA256", context_row.sha256),
    #("Stored exchanges", int.to_string(list.length(context.turns))),
    #("Maximum exchanges", int.to_string(conv.max_turns)),
    #("History", case context.turns { [] -> "No stored complete exchanges" _ -> "Complete retained exchanges, oldest first; long text is split into numbered parts" }),
    #("Scope", "Only this user in this chat with this bot; retained history is bounded, not an archive"),
    #("Runtime admission", "NOT_GRANTED"),
  ], list.index_map(context.turns, turn_fields) |> list.flatten)
  Ok(api.Observed(at, "durable_telegram_conversation", dict.from_list(fields)))
}

pub fn observe(
  config: Configuration,
  read: api.AuthorizedRead,
  fetch: fn(List(String)) -> Result(#(Int, List(codec.RowResult)), String),
  clock: fn() -> Int,
) -> Result(api.Observation, String) {
  use scope <- result.try(resolve_scope(config, api.user_id(read), api.chat_id(read)))
  use key <- result.try(conv.context_key(scope))
  use #(generation, rows) <- result.try(fetch([codec.bot_identity_key(), key]))
  from_rows(scope, generation, rows, clock())
}

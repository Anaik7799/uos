//// Pure bounded Telegram decoder. Configuration is trusted local input, not
//// authentication. Transport must bind the configured bot to its real identity.

import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_task_command as task_command
import cepaf_gleam/harness/files
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const max_payload_bytes = 65_536

pub const max_text_bytes = 4096

pub const max_identity = 4_503_599_627_370_495

pub const max_update_id = 2_147_483_647

pub type Allowlist {
  Allowlist(bot_id: Int, allowed_pairs: List(#(Int, Int)))
}

pub type ParsedDirective {
  DirectReadTool(tool_name: String)
  PreservedDirective(name: String, args: List(String))
  DeniedMutation(tool_name: String, reason: String)
  UnknownDirective(name: String)
}

pub type IngressVerdict {
  AcceptedEnvelope(
    update_id: Int,
    message_id: Int,
    chat_id: Int,
    user_id: Int,
    text_hash: String,
    raw_text: String,
    directive: ParsedDirective,
    bot_id: Int,
    callback_query_id: Option(String),
  )
  // A tombstone binds the exact received bytes and trusted bot, not just a reason.
  RejectedUpdate(
    update_id: Int,
    bot_id: Int,
    envelope_hash: String,
    reason: String,
  )
  // Unidentifiable input must not become a fabricated update-0 tombstone.
  UnidentifiedRejection(reason: String)
}

type Identity {
  Identity(
    update_id: Int,
    message_id: Int,
    chat_id: Int,
    user_id: Int,
    chat_type: String,
    is_bot: Bool,
    callback_query_id: Option(String),
    text: String,
  )
}

pub fn valid_positive_id(value: Int) -> Bool {
  value > 0 && value <= max_identity
}

pub fn valid_chat_id(value: Int) -> Bool {
  value != 0 && value >= 0 - max_identity && value <= max_identity
}

pub fn valid_update_id(value: Int) -> Bool {
  value >= 0 && value <= max_update_id
}

pub fn valid_digest(value: String) -> Bool {
  string.byte_size(value) == 64
  && list.all(string.to_graphemes(value), fn(c) {
    string.contains("0123456789abcdef", c)
  })
}

pub fn valid_text(value: String) -> Bool {
  string.trim(value) != ""
  && string.byte_size(value) <= max_text_bytes
  && !string.contains(value, "\u{0}")
}

fn empty_args(args: String) -> Bool {
  case string.trim(args) {
    "" -> True
    text ->
      case json.parse(text, decode.dict(decode.string, decode.dynamic)) {
        Ok(entries) -> dict.size(entries) == 0
        Error(_) -> False
      }
  }
}

fn read_directive(tool: String, args: String) -> ParsedDirective {
  case string.byte_size(args) <= 256 && empty_args(args) {
    True -> DirectReadTool(tool)
    False ->
      DeniedMutation(
        tool,
        "Read arguments must be absent or an empty JSON object.",
      )
  }
}

pub fn classify_directive(raw_text: String) -> ParsedDirective {
  let text = string.trim(raw_text)
  case string.starts_with(text, "/") {
    False -> PreservedDirective("conversational", [text])
    True -> case commands.parse(raw_text) {
      Error(commands.InvalidInput) -> DeniedMutation("invalid_input", "Invalid bounded command input.")
      Error(commands.UnknownCommand(name)) -> UnknownDirective(name)
      Ok(invocation) -> {
        let name = invocation.definition.canonical
        let args = invocation.args
        case name {
          "/doctor" -> read_directive("query_doctor", args)
          "/plan" -> read_directive("query_saplan", args)
          "/task" -> case task_command.parse_task_id(args) {
            Ok(task_id) -> PreservedDirective("/task", [task_id])
            Error(_) -> DeniedMutation("/task", "Usage: /task <task_id>; reads only the configured plan.")
          }
          "/tool" -> {
            let #(tool, tail) = case string.split_once(args, " ") {
              Ok(#(t, a)) -> #(t, string.trim(a))
              Error(_) -> #(args, "")
            }
            case tool {
              "query_doctor" | "query_saplan" -> read_directive(tool, tail)
              "" -> UnknownDirective("/tool")
              _ -> DeniedMutation(tool, "Tool has no admitted Telegram adapter.")
            }
          }
          _ -> case invocation.definition.kind {
            commands.ControlledAction -> DeniedMutation(name, "Action is not implemented yet; current effect authority will also be required.")
            _ -> PreservedDirective(name, case args { "" -> [] _ -> [args] })
          }
        }
      }
    }
  }
}

fn update_id_decoder() -> decode.Decoder(Int) {
  use id <- decode.field("update_id", decode.int)
  decode.success(id)
}

fn message_identity_decoder() -> decode.Decoder(Identity) {
  use uid <- decode.field("update_id", decode.int)
  use mid <- decode.subfield(["message", "message_id"], decode.int)
  use cid <- decode.subfield(["message", "chat", "id"], decode.int)
  use kind <- decode.subfield(["message", "chat", "type"], decode.string)
  use user <- decode.subfield(["message", "from", "id"], decode.int)
  use bot <- decode.subfield(["message", "from", "is_bot"], decode.bool)
  use text <- decode.subfield(["message", "text"], decode.string)
  decode.success(Identity(uid, mid, cid, user, kind, bot, None, text))
}

fn callback_query_identity_decoder() -> decode.Decoder(Identity) {
  use uid <- decode.field("update_id", decode.int)
  use cb_id <- decode.subfield(["callback_query", "id"], decode.string)
  use user <- decode.subfield(["callback_query", "from", "id"], decode.int)
  use bot <- decode.subfield(["callback_query", "from", "is_bot"], decode.bool)
  use mid <- decode.subfield(
    ["callback_query", "message", "message_id"],
    decode.int,
  )
  use cid <- decode.subfield(
    ["callback_query", "message", "chat", "id"],
    decode.int,
  )
  use kind <- decode.subfield(
    ["callback_query", "message", "chat", "type"],
    decode.string,
  )
  use text <- decode.subfield(["callback_query", "data"], decode.string)
  decode.success(Identity(uid, mid, cid, user, kind, bot, Some(cb_id), text))
}

fn has_sender_chat(raw: String) -> Bool {
  let decoder = {
    use message <- decode.optional_field(
      "message",
      dict.new(),
      decode.dict(decode.string, decode.dynamic),
    )
    use cb <- decode.optional_field(
      "callback_query",
      dict.new(),
      decode.dict(decode.string, decode.dynamic),
    )
    let msg_has = dict.has_key(message, "sender_chat")
    let cb_has = case dict.get(cb, "message") {
      Ok(dyn) -> {
        case decode.run(dyn, decode.dict(decode.string, decode.dynamic)) {
          Ok(sub) -> dict.has_key(sub, "sender_chat")
          Error(_) -> False
        }
      }
      Error(_) -> False
    }
    decode.success(msg_has || cb_has)
  }
  case json.parse(raw, decoder) {
    Ok(present) -> present
    Error(_) -> True
  }
}

pub fn evaluate_update(raw: String, allow: Allowlist) -> IngressVerdict {
  case
    valid_positive_id(allow.bot_id)
    && allow.allowed_pairs != []
    && list.length(list.take(allow.allowed_pairs, 101)) <= 100
    && list.all(allow.allowed_pairs, fn(pair) {
      valid_chat_id(pair.0) && valid_positive_id(pair.1)
    })
  {
    False -> UnidentifiedRejection("invalid_local_allowlist")
    True ->
      case string.byte_size(raw) <= max_payload_bytes {
        False -> UnidentifiedRejection("payload_bound")
        True ->
          case json.parse(raw, update_id_decoder()) {
            Error(_) -> UnidentifiedRejection("malformed_update_identity")
            Ok(uid) ->
              case valid_update_id(uid) {
                False -> UnidentifiedRejection("invalid_update_id")
                True -> evaluate_identified(raw, allow, uid)
              }
          }
      }
  }
}

fn evaluate_identified(
  raw: String,
  allow: Allowlist,
  uid: Int,
) -> IngressVerdict {
  let reject = fn(reason) {
    RejectedUpdate(uid, allow.bot_id, files.digest(raw), reason)
  }
  let id_result = case json.parse(raw, message_identity_decoder()) {
    Ok(id) -> Ok(id)
    Error(_) -> json.parse(raw, callback_query_identity_decoder())
  }
  case id_result {
    Error(_) -> reject("missing_or_malformed_message_identity")
    Ok(id) ->
      case
        valid_positive_id(id.message_id)
        && valid_positive_id(id.user_id)
        && valid_chat_id(id.chat_id)
        && list.contains(["private", "group", "supergroup"], id.chat_type)
        && !id.is_bot
        && !has_sender_chat(raw)
        && list.contains(allow.allowed_pairs, #(id.chat_id, id.user_id))
      {
        False -> reject("unsupported_or_unauthorized_identity")
        True ->
          case valid_text(id.text) {
            False -> reject("invalid_text")
            True ->
              AcceptedEnvelope(
                uid,
                id.message_id,
                id.chat_id,
                id.user_id,
                files.digest(id.text),
                id.text,
                classify_directive(id.text),
                allow.bot_id,
                id.callback_query_id,
              )
          }
      }
  }
}

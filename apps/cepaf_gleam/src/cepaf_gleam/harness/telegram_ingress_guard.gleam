//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Ingress Guard & Identity Filter
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/harness/telegram_ingress_guard</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L5_COGNITIVE</layer>
////     <topology>Pure Telegram BotAPI Ingress Allowlist & Directive Classifier</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-HARNESS-MCP-001, SC-JIDOKA-001, SC-ZMOF-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/harness/files
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub const max_payload_bytes = 65_536
pub const max_text_bytes = 4096

pub type User {
  User(
    id: Int,
    is_bot: Bool,
    username: Option(String),
    first_name: Option(String),
  )
}

pub type Chat {
  Chat(
    id: Int,
    chat_type: String,
  )
}

pub type Message {
  Message(
    message_id: Int,
    date: Int,
    chat: Chat,
    from: Option(User),
    sender_chat: Option(Chat),
    text: Option(String),
  )
}

pub type Update {
  Update(
    update_id: Int,
    message: Option(Message),
  )
}

pub type Allowlist {
  Allowlist(
    bot_id: Int,
    allowed_pairs: List(#(Int, Int)),
  )
}

pub type RejectionReason {
  OversizedPayload(size: Int)
  MalformedUpdateJson(detail: String)
  MissingMessage
  ChannelOrAnonymousSenderBarred
  MissingSenderUser
  BotSenderBarred
  UnauthorizedSenderPair(chat_id: Int, user_id: Int)
  EmptyOrMissingText
  OversizedText(size: Int)
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
  )
  RejectedUpdate(
    update_id: Int,
    reason: RejectionReason,
  )
}

// -----------------------------------------------------------------------------
// Pure Decoders
// -----------------------------------------------------------------------------

fn user_decoder() -> decode.Decoder(User) {
  use id <- decode.field("id", decode.int)
  use is_bot <- decode.optional_field("is_bot", False, decode.bool)
  use username <- decode.optional_field("username", None, decode.optional(decode.string))
  use first_name <- decode.optional_field("first_name", None, decode.optional(decode.string))
  decode.success(User(id: id, is_bot: is_bot, username: username, first_name: first_name))
}

fn chat_decoder() -> decode.Decoder(Chat) {
  use id <- decode.field("id", decode.int)
  use chat_type <- decode.optional_field("type", "private", decode.string)
  decode.success(Chat(id: id, chat_type: chat_type))
}

fn message_decoder() -> decode.Decoder(Message) {
  use message_id <- decode.field("message_id", decode.int)
  use date <- decode.optional_field("date", 0, decode.int)
  use chat <- decode.field("chat", chat_decoder())
  use from <- decode.optional_field("from", None, decode.optional(user_decoder()))
  use sender_chat <- decode.optional_field("sender_chat", None, decode.optional(chat_decoder()))
  use text <- decode.optional_field("text", None, decode.optional(decode.string))
  decode.success(Message(
    message_id: message_id,
    date: date,
    chat: chat,
    from: from,
    sender_chat: sender_chat,
    text: text,
  ))
}

pub fn update_decoder() -> decode.Decoder(Update) {
  use update_id <- decode.field("update_id", decode.int)
  use message <- decode.optional_field("message", None, decode.optional(message_decoder()))
  decode.success(Update(update_id: update_id, message: message))
}

// -----------------------------------------------------------------------------
// Pure Directive Classification
// -----------------------------------------------------------------------------

pub fn classify_directive(raw_text: String) -> ParsedDirective {
  let trimmed = string.trim(raw_text)
  case string.starts_with(trimmed, "/") {
    False -> PreservedDirective("conversational", [trimmed])
    True -> {
      let parts = string.split(trimmed, " ")
      let cmd = case parts {
        [c, ..] -> c
        [] -> ""
      }
      let args = case parts {
        [_, ..rest] -> rest
        [] -> []
      }

      case cmd {
        // Direct safe bounded read tools
        "/doctor" | "/ev" -> DirectReadTool("query_doctor")
        "/plan" | "/saplan" -> DirectReadTool("query_saplan")

        "/tool" | "/action" -> {
          case args {
            ["query_doctor", ..] -> DirectReadTool("query_doctor")
            ["query_saplan", ..] -> DirectReadTool("query_saplan")
            [mutating, ..] ->
              DeniedMutation(
                mutating,
                "Mutating tool execution requires canonical Sa-plan task lease and 2oo3 constitutional quorum approved via /approval.",
              )
            [] -> UnknownDirective(cmd)
          }
        }

        // Truthful preserved informational directives
        "/status" | "/checklist" | "/storage" | "/start" | "/help" | "/cockpit" ->
          PreservedDirective(cmd, args)

        // Refused mutating directives (unsupported until authentic 2oo3 quorum implementation)
        "/approval" ->
          DeniedMutation(
            "approval",
            "Direct approval execution refused: authentic 2oo3 quorum workflow requires signed coordinator lease.",
          )
        "/andon" ->
          DeniedMutation(
            "andon",
            "Emergency Andon stop line requires coordinator confirmation lease.",
          )
        "/resuscitate" | "/chaos" | "/rotate_keys" | "/repro" | "/merge" ->
          DeniedMutation(
            cmd,
            "Mutating cluster directive requires offline operator authorization.",
          )
        "/zigvm" ->
          DeniedMutation(
            "zigvm",
            "Subprocess shell invocation barred under SC-ZMOF-001.",
          )

        _ -> UnknownDirective(cmd)
      }
    }
  }
}

// -----------------------------------------------------------------------------
// Ingress Evaluation Engine
// -----------------------------------------------------------------------------

pub fn evaluate_update(raw_json: String, allowlist: Allowlist) -> IngressVerdict {
  let byte_size = string.byte_size(raw_json)
  case byte_size <= max_payload_bytes {
    False -> RejectedUpdate(0, OversizedPayload(byte_size))
    True -> {
      case json.parse(raw_json, update_decoder()) {
        Error(err) -> RejectedUpdate(0, MalformedUpdateJson(string.inspect(err)))
        Ok(update) -> {
          case update.message {
            None -> RejectedUpdate(update.update_id, MissingMessage)
            Some(msg) -> {
              case msg.sender_chat {
                Some(_) -> RejectedUpdate(update.update_id, ChannelOrAnonymousSenderBarred)
                None -> {
                  case msg.from {
                    None -> RejectedUpdate(update.update_id, MissingSenderUser)
                    Some(user) -> {
                      case user.is_bot {
                        True -> RejectedUpdate(update.update_id, BotSenderBarred)
                        False -> {
                          let pair = #(msg.chat.id, user.id)
                          case list.contains(allowlist.allowed_pairs, pair) {
                            False ->
                              RejectedUpdate(
                                update.update_id,
                                UnauthorizedSenderPair(msg.chat.id, user.id),
                              )
                            True -> {
                              case msg.text {
                                None -> RejectedUpdate(update.update_id, EmptyOrMissingText)
                                Some(txt) -> {
                                  let txt_len = string.byte_size(txt)
                                  case txt_len == 0 {
                                    True -> RejectedUpdate(update.update_id, EmptyOrMissingText)
                                    False -> {
                                      case txt_len <= max_text_bytes {
                                        False ->
                                          RejectedUpdate(
                                            update.update_id,
                                            OversizedText(txt_len),
                                          )
                                        True -> {
                                          let text_hash = files.digest(txt)
                                          let directive = classify_directive(txt)
                                          AcceptedEnvelope(
                                            update_id: update.update_id,
                                            message_id: msg.message_id,
                                            chat_id: msg.chat.id,
                                            user_id: user.id,
                                            text_hash: text_hash,
                                            raw_text: txt,
                                            directive: directive,
                                          )
                                        }
                                      }
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

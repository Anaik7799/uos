//// Pure bounded Telegram decoder. Configuration is trusted local input, not
//// authentication. Transport must bind the configured bot to its real identity.

import cepaf_gleam/harness/files
import cepaf_gleam/harness/telegram_action_adapters as action_adapters
import cepaf_gleam/harness/telegram_commands as commands
import cepaf_gleam/harness/telegram_dialogue_command as dialogue
import cepaf_gleam/harness/telegram_impact_report as impact
import cepaf_gleam/harness/telegram_knowledge_report as knowledge
import cepaf_gleam/harness/telegram_rete_report as rete
import cepaf_gleam/harness/telegram_task_command as task_command
import cepaf_gleam/harness/telegram_tool_command as tool_command
import cepaf_gleam/harness/telegram_verification_report as verification
import cepaf_gleam/harness/telegram_zenoh_report as zenoh_report
import gleam/dict
import cepaf_gleam/harness/telegram_media_ref as media_ref
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
    True ->
      case commands.parse(raw_text) {
        Error(commands.InvalidInput) ->
          DeniedMutation("invalid_input", "Invalid bounded command input.")
        Error(commands.UnknownCommand(name)) -> UnknownDirective(name)
        Ok(invocation) -> {
          let name = invocation.definition.canonical
          let args = invocation.args
          case name {
            "/socratic" ->
              case dialogue.topic(args) {
                Ok(topic) -> PreservedDirective("/socratic", [topic])
                Error(e) -> DeniedMutation("/socratic", e)
              }
            "/approval" -> approval_directive(args)
            "/doctor" -> read_directive("query_doctor", args)
            "/rete" ->
              case rete.canonicalize(args) {
                Ok(facts) -> PreservedDirective("/rete", [facts])
                Error(_) ->
                  DeniedMutation(
                    "/rete",
                    "Supply comma-separated watchdog, mesh_running, e_stop, high_drift or divergent boolean facts; evaluation grants no authority.",
                  )
              }
            "/checklist" -> read_directive("query_checklist", args)
            "/aspects" ->
              case verification.valid_scope("aspects", args) {
                True -> PreservedDirective("/aspects", [args])
                False ->
                  DeniedMutation(
                    "/aspects",
                    "Use /aspects or /aspects A01 through A17.",
                  )
              }
            "/storage" -> read_directive("query_storage", args)
            "/ecology" -> read_directive("query_ecology", args)
            "/sutra" -> read_directive("query_matrix_versions", args)
            "/exec-brief" -> read_directive("query_exec_brief", args)
            "/status" | "/health" -> read_directive("query_system_health", args)
            "/finops" | "/budget" ->
              case args {
                "" -> DirectReadTool("query_finops")
                _ ->
                  DeniedMutation(
                    "/finops",
                    "Use /finops or /budget without arguments; ledger scope is fixed.",
                  )
              }
            "/blast-radius" ->
              case impact.selector(args) {
                Ok(module) -> PreservedDirective("/blast-radius", [module])
                Error(e) -> DeniedMutation("/blast-radius", e)
              }
            "/zenoh" ->
              case zenoh_report.valid_topic(args) {
                True -> PreservedDirective("/zenoh", [args])
                False ->
                  DeniedMutation(
                    "/zenoh",
                    "Use /zenoh or /zenoh <exact-topic>; wildcards, URLs and scope overrides are refused.",
                  )
              }
            "/ha" -> read_directive("query_ha", args)
            "/fmea" ->
              case read_directive("query_fmea", args) {
                DirectReadTool(_) -> DirectReadTool("query_fmea")
                _ ->
                  case task_command.parse_task_id(args) {
                    Ok(task) -> PreservedDirective("/fmea", [task])
                    Error(_) ->
                      DeniedMutation(
                        "/fmea",
                        "Use /fmea or /fmea <task_id>; source and plan are fixed.",
                      )
                  }
              }
            "/search" ->
              case knowledge.validate_query(args) {
                Ok(query) -> PreservedDirective("/search", [query])
                Error(_) ->
                  DeniedMutation(
                    name,
                    "Use a literal query of at most 128 bytes.",
                  )
              }
            "/wiki" | "/zk" | "/km" -> {
              let view = case name {
                "/wiki" -> "wiki"
                "/zk" -> "zk"
                _ -> "all"
              }
              case knowledge.validate_query(args) {
                Ok(query) -> PreservedDirective("/knowledge", [view, query])
                Error(_) ->
                  DeniedMutation(
                    name,
                    "Use a literal query of at most 128 bytes.",
                  )
              }
            }
            "/peers" -> read_directive("query_peers", args)
            "/board" -> read_directive("query_board", args)
            "/zigvm" ->
              case args {
                "" | "version" -> DirectReadTool("query_zigvm_version")
                _ ->
                  DeniedMutation(
                    "/zigvm",
                    "Only version observation is available; evaluation is not integrated.",
                  )
              }
            "/plan" -> read_directive("query_saplan", args)
            "/task" ->
              case task_command.parse_task_id(args) {
                Ok(task_id) -> PreservedDirective("/task", [task_id])
                Error(_) ->
                  DeniedMutation(
                    "/task",
                    "Usage: /task <task_id>; reads only the configured plan.",
                  )
              }
            "/tool" -> {
              case tool_command.parse(args) {
                Ok(tool_command.CancelLease(job, reason)) ->
                  PreservedDirective("/cancel_job_lease", [job, reason])
                Ok(tool_command.Help) -> PreservedDirective("/tool_help", [])
                Ok(tool_command.Doctor) -> DirectReadTool("query_doctor")
                Ok(tool_command.Rete(facts)) ->
                  PreservedDirective("/rete", [facts])
                Ok(tool_command.Checklist) -> DirectReadTool("query_checklist")
                Ok(tool_command.Aspects(selector)) ->
                  PreservedDirective("/aspects", [selector])
                Ok(tool_command.Storage) -> DirectReadTool("query_storage")
                Ok(tool_command.Ecology) -> DirectReadTool("query_ecology")
                Ok(tool_command.Matrix) ->
                  DirectReadTool("query_matrix_versions")
                Ok(tool_command.ExecBrief) -> DirectReadTool("query_exec_brief")
                Ok(tool_command.SystemHealth) ->
                  DirectReadTool("query_system_health")
                Ok(tool_command.Socratic(topic)) ->
                  PreservedDirective("/socratic", [topic])
                Ok(tool_command.BlastRadius(module)) ->
                  PreservedDirective("/blast-radius", [module])
                Ok(tool_command.Zenoh(topic)) ->
                  PreservedDirective("/zenoh", [topic])
                Ok(tool_command.Finops) -> DirectReadTool("query_finops")
                Ok(tool_command.Ha) -> DirectReadTool("query_ha")
                Ok(tool_command.Fmea("")) -> DirectReadTool("query_fmea")
                Ok(tool_command.Fmea(task)) ->
                  PreservedDirective("/fmea", [task])
                Ok(tool_command.Search(query)) ->
                  PreservedDirective("/search", [query])
                Ok(tool_command.Knowledge(view, query)) ->
                  PreservedDirective("/knowledge", [view, query])
                Ok(tool_command.Peers) -> DirectReadTool("query_peers")
                Ok(tool_command.Board) -> DirectReadTool("query_board")
                Ok(tool_command.KernelVersion) ->
                  DirectReadTool("query_zigvm_version")
                Ok(tool_command.Plan) -> DirectReadTool("query_saplan")
                Ok(tool_command.Task(task_id)) ->
                  PreservedDirective("/task", [task_id])
                Error(reason) -> DeniedMutation("/tool", reason)
              }
            }
            _ ->
              case invocation.definition.kind {
                // A ControlledAction with an adapter is preserved for its read-only
                // preview; execution still requires the signed approval flow.
                // /verify is owned by the service's VerifyDispatch: a signed verify
                // packet executes it, otherwise the service answers truthfully that
                // verification is not configured. Nothing executes from this text.
                commands.ControlledAction ->
                  case
                    name == "/verify"
                    || list.contains(action_adapters.literals(), name)
                  {
                    True ->
                      PreservedDirective(name, case args {
                        "" -> []
                        _ -> [args]
                      })
                    False ->
                      DeniedMutation(
                        name,
                        "Action is not implemented yet; current effect authority will also be required.",
                      )
                  }
                _ ->
                  PreservedDirective(name, case args {
                    "" -> []
                    _ -> [args]
                  })
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
  use text <- decode.subfield(["message"], message_text_decoder())
  decode.success(Identity(uid, mid, cid, user, kind, bot, None, text))
}

/// The command text of a message: `text`, or the `caption` of a media message
/// when `text` is absent (wave 6h). A message with neither is not identified
/// here; `evaluate_identified` then names bare media explicitly.
fn message_text_decoder() -> decode.Decoder(String) {
  use text <- decode.optional_field(
    "text",
    None,
    decode.optional(decode.string),
  )
  use caption <- decode.optional_field(
    "caption",
    None,
    decode.optional(decode.string),
  )
  case text, caption {
    Some(t), _ -> decode.success(t)
    None, Some(c) -> decode.success(c)
    None, None -> decode.failure("", "text_or_caption")
  }
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
    Error(_) ->
      // A media message without a caption is identified as such, so the
      // tombstone says why it was refused instead of hiding it behind a
      // generic identity failure (wave 6h). No command text is invented.
      case media_ref.from_update(raw) {
        Ok(Some(_)) -> reject("media_without_caption")
        _ -> reject("missing_or_malformed_message_identity")
      }
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

fn approval_request_id(id: String) -> Bool {
  string.byte_size(id) > 3
  && string.byte_size(id) <= 64
  && string.starts_with(id, "tg-")
  && list.all(string.to_graphemes(string.drop_start(id, 3)), fn(c) {
    string.contains("0123456789-", c)
  })
}

fn approval_directive(args: String) -> ParsedDirective {
  case args {
    "" | "list" -> PreservedDirective("/approval", [])
    _ ->
      case string.split(args, " ") {
        [id] ->
          case approval_request_id(id) {
            True -> PreservedDirective("/approval", [id])
            False ->
              DeniedMutation(
                "/approval",
                "Usage: /approval [request_id], propose <request_id>, withdraw <request_id>, or submit <request_id> <role> <signed_receipt>.",
              )
          }
        ["withdraw", id] ->
          case approval_request_id(id) {
            True -> PreservedDirective("/approval_manage", ["withdraw", id])
            False -> DeniedMutation("/approval", "Invalid request identifier.")
          }
        ["propose", id] if id != "" ->
          case approval_request_id(id) {
            True -> PreservedDirective("/approval_manage", ["propose", id])
            False -> DeniedMutation("/approval", "Invalid request identifier.")
          }
        ["submit", id, role, token] ->
          case
            approval_request_id(id)
            && list.contains(["codex", "agy", "claude", "operator"], role)
            && token != ""
            && string.byte_size(token) <= 8192
          {
            True ->
              PreservedDirective("/approval_manage", ["submit", id, role, token])
            False ->
              DeniedMutation("/approval", "Invalid signed receipt submission.")
          }
        _ ->
          DeniedMutation(
            "/approval",
            "Use propose, submit, or withdraw with an exact request identifier; unsigned approve text cannot authorize an action.",
          )
      }
  }
}

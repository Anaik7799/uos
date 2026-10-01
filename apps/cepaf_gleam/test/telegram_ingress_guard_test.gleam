//// =============================================================================
//// [UOS-L5-COG] Pure Telegram Ingress Guard Test Suite
//// =============================================================================

import cepaf_gleam/harness/telegram_ingress_guard as tg_guard
import gleeunit/should
import gleam/string

fn standard_allowlist() -> tg_guard.Allowlist {
  tg_guard.Allowlist(
    bot_id: 123_456,
    allowed_pairs: [
      #(1001, 501),
      #(1001, 502),
      #(1002, 503),
    ],
  )
}

fn make_update_json(
  update_id: Int,
  message_id: Int,
  chat_id: Int,
  user_id: Int,
  is_bot: Bool,
  username: String,
  text: String,
) -> String {
  "{\"update_id\":"
  <> string.inspect(update_id)
  <> ",\"message\":{\"message_id\":"
  <> string.inspect(message_id)
  <> ",\"date\":1727780000,\"chat\":{\"id\":"
  <> string.inspect(chat_id)
  <> ",\"type\":\"private\"},\"from\":{\"id\":"
  <> string.inspect(user_id)
  <> ",\"is_bot\":"
  <> case is_bot {
    True -> "true"
    False -> "false"
  }
  <> ",\"username\":\""
  <> username
  <> "\"},\"text\":\""
  <> text
  <> "\"}}"
}

// -----------------------------------------------------------------------------
// Unit Tests
// -----------------------------------------------------------------------------

pub fn valid_envelope_accepted_test() {
  let json_str = make_update_json(100, 1, 1001, 501, False, "authorized_user", "/doctor")
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.AcceptedEnvelope(update_id, message_id, chat_id, user_id, text_hash, raw_text, directive) -> {
      update_id |> should.equal(100)
      message_id |> should.equal(1)
      chat_id |> should.equal(1001)
      user_id |> should.equal(501)
      raw_text |> should.equal("/doctor")
      string.length(text_hash) |> should.equal(64)
      directive |> should.equal(tg_guard.DirectReadTool("query_doctor"))
    }
    _ -> panic as "Expected AcceptedEnvelope"
  }
}

pub fn adversarial_identity_swap_rejected_test() {
  // Attacker uses same allowed username "authorized_user" but different numeric user_id (999)
  let json_str = make_update_json(101, 2, 1001, 999, False, "authorized_user", "/doctor")
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(update_id, tg_guard.UnauthorizedSenderPair(chat_id, user_id)) -> {
      update_id |> should.equal(101)
      chat_id |> should.equal(1001)
      user_id |> should.equal(999)
    }
    _ -> panic as "Expected RejectedUpdate due to unauthorized pair"
  }
}

pub fn wrong_chat_user_pair_rejected_test() {
  // User 503 is allowed in chat 1002, but NOT in chat 1001
  let json_str = make_update_json(102, 3, 1001, 503, False, "user3", "/status")
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(update_id, tg_guard.UnauthorizedSenderPair(1001, 503)) -> {
      update_id |> should.equal(102)
    }
    _ -> panic as "Expected RejectedUpdate due to mismatched chat/user pair"
  }
}

pub fn bot_sender_barred_test() {
  let json_str = make_update_json(103, 4, 1001, 501, True, "bot_user", "/doctor")
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(103, tg_guard.BotSenderBarred) -> Nil
    _ -> panic as "Expected BotSenderBarred"
  }
}

pub fn channel_post_sender_chat_barred_test() {
  let json_str = "{\"update_id\":104,\"message\":{\"message_id\":5,\"date\":1727780000,\"chat\":{\"id\":1001,\"type\":\"channel\"},\"sender_chat\":{\"id\":-100222,\"type\":\"channel\"},\"text\":\"/doctor\"}}"
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(104, tg_guard.ChannelOrAnonymousSenderBarred) -> Nil
    _ -> panic as "Expected ChannelOrAnonymousSenderBarred"
  }
}

pub fn missing_sender_user_barred_test() {
  let json_str = "{\"update_id\":105,\"message\":{\"message_id\":6,\"date\":1727780000,\"chat\":{\"id\":1001,\"type\":\"group\"},\"text\":\"/doctor\"}}"
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(105, tg_guard.MissingSenderUser) -> Nil
    _ -> panic as "Expected MissingSenderUser"
  }
}

pub fn empty_text_barred_test() {
  let json_str = make_update_json(106, 7, 1001, 501, False, "user", "")
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(106, tg_guard.EmptyOrMissingText) -> Nil
    _ -> panic as "Expected EmptyOrMissingText"
  }
}

pub fn oversized_payload_barred_test() {
  // Payload exceeds 65536 bytes
  let long_filler = string.repeat("a", 65_600)
  let json_str = "{\"update_id\":107,\"dummy\":\"" <> long_filler <> "\"}"
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(0, tg_guard.OversizedPayload(_)) -> Nil
    _ -> panic as "Expected OversizedPayload"
  }
}

pub fn malformed_json_barred_test() {
  let json_str = "{not_json: 123}"
  let verdict = tg_guard.evaluate_update(json_str, standard_allowlist())

  case verdict {
    tg_guard.RejectedUpdate(0, tg_guard.MalformedUpdateJson(_)) -> Nil
    _ -> panic as "Expected MalformedUpdateJson"
  }
}

pub fn directive_classification_test() {
  // Safe reads
  tg_guard.classify_directive("/doctor")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))
  tg_guard.classify_directive("/ev")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))
  tg_guard.classify_directive("/plan")
  |> should.equal(tg_guard.DirectReadTool("query_saplan"))
  tg_guard.classify_directive("/saplan")
  |> should.equal(tg_guard.DirectReadTool("query_saplan"))
  tg_guard.classify_directive("/tool query_doctor")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))
  tg_guard.classify_directive("/tool query_saplan")
  |> should.equal(tg_guard.DirectReadTool("query_saplan"))

  // Preserved truthful informational directives
  tg_guard.classify_directive("/status")
  |> should.equal(tg_guard.PreservedDirective("/status", []))
  tg_guard.classify_directive("/checklist")
  |> should.equal(tg_guard.PreservedDirective("/checklist", []))
  tg_guard.classify_directive("/storage")
  |> should.equal(tg_guard.PreservedDirective("/storage", []))
  tg_guard.classify_directive("/start")
  |> should.equal(tg_guard.PreservedDirective("/start", []))
  tg_guard.classify_directive("/help")
  |> should.equal(tg_guard.PreservedDirective("/help", []))

  // Denied mutating directives
  case tg_guard.classify_directive("/tool resuscitate_node") {
    tg_guard.DeniedMutation("resuscitate_node", _) -> Nil
    _ -> panic as "Expected DeniedMutation for resuscitate_node"
  }
  case tg_guard.classify_directive("/approval 1 2 title") {
    tg_guard.DeniedMutation("approval", _) -> Nil
    _ -> panic as "Expected DeniedMutation for /approval"
  }
  case tg_guard.classify_directive("/andon") {
    tg_guard.DeniedMutation("andon", _) -> Nil
    _ -> panic as "Expected DeniedMutation for /andon"
  }
  case tg_guard.classify_directive("/zigvm version") {
    tg_guard.DeniedMutation("zigvm", _) -> Nil
    _ -> panic as "Expected DeniedMutation for /zigvm"
  }

  // Unknown directive
  tg_guard.classify_directive("/unknown_cmd")
  |> should.equal(tg_guard.UnknownDirective("/unknown_cmd"))
}

pub fn main() {
  valid_envelope_accepted_test()
  adversarial_identity_swap_rejected_test()
  wrong_chat_user_pair_rejected_test()
  bot_sender_barred_test()
  channel_post_sender_chat_barred_test()
  missing_sender_user_barred_test()
  empty_text_barred_test()
  oversized_payload_barred_test()
  malformed_json_barred_test()
  directive_classification_test()
}

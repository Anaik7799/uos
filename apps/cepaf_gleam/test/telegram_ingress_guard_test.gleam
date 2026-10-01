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
    ],
  )
}

pub fn valid_allowlisted_envelope_test() {
  let allowlist = standard_allowlist()
  let payload = "{\"update_id\": 100, \"message\": {\"message_id\": 10, \"date\": 1700000000, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"from\": {\"id\": 501, \"is_bot\": false, \"username\": \"alice\"}, \"text\": \"/doctor\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.AcceptedEnvelope(
      update_id: 100,
      message_id: 10,
      chat_id: 1001,
      user_id: 501,
      directive: tg_guard.DirectReadTool("query_doctor"),
      bot_id: 123_456,
      ..,
    ) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn adversarial_identity_swap_attack_test() {
  let allowlist = standard_allowlist()
  // Attacker puts admin username in body or text, but real user is unauthorized 999
  let payload = "{\"update_id\": 101, \"message\": {\"message_id\": 11, \"date\": 1700000000, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"from\": {\"id\": 999, \"is_bot\": false, \"username\": \"admin_alice\"}, \"text\": \"/tool query_doctor\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(101, tg_guard.UnauthorizedSenderPair(1001, 999)) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn unauthorized_pair_chat_match_user_mismatch_test() {
  let allowlist = standard_allowlist()
  // Chat 1001 matches, but user 888 is not allowlisted
  let payload = "{\"update_id\": 102, \"message\": {\"message_id\": 12, \"date\": 1700000000, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"from\": {\"id\": 888, \"is_bot\": false}, \"text\": \"/ev\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(102, tg_guard.UnauthorizedSenderPair(1001, 888)) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn bot_sender_rejection_test() {
  let allowlist = standard_allowlist()
  let payload = "{\"update_id\": 103, \"message\": {\"message_id\": 13, \"date\": 1700000000, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"from\": {\"id\": 501, \"is_bot\": true}, \"text\": \"/status\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(103, tg_guard.BotSenderBarred) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn channel_post_rejection_test() {
  let allowlist = standard_allowlist()
  let payload = "{\"update_id\": 104, \"channel_post\": {\"message_id\": 14, \"chat\": {\"id\": -100123, \"type\": \"channel\"}, \"text\": \"/doctor\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(104, tg_guard.MissingMessage) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn channel_chat_with_user_rejection_test() {
  let allowlist = standard_allowlist()
  // Message has allowed user 501, but chat type is "channel"
  let payload = "{\"update_id\": 105, \"message\": {\"message_id\": 15, \"chat\": {\"id\": 1001, \"type\": \"channel\"}, \"from\": {\"id\": 501, \"is_bot\": false}, \"text\": \"/doctor\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(105, tg_guard.ChannelOrAnonymousSenderBarred) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn sender_chat_rejection_test() {
  let allowlist = standard_allowlist()
  // Message has sender_chat (anonymous channel forward)
  let payload = "{\"update_id\": 106, \"message\": {\"message_id\": 16, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"sender_chat\": {\"id\": 123, \"type\": \"channel\"}, \"from\": {\"id\": 501, \"is_bot\": false}, \"text\": \"/doctor\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(106, tg_guard.ChannelOrAnonymousSenderBarred) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn configured_bot_id_variation_test() {
  let allow1 = standard_allowlist()
  let allow2 = tg_guard.Allowlist(bot_id: 999_999, allowed_pairs: [#(1001, 501)])
  let payload = "{\"update_id\": 107, \"message\": {\"message_id\": 17, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"from\": {\"id\": 501, \"is_bot\": false}, \"text\": \"/doctor\"}}"

  let res1 = tg_guard.evaluate_update(payload, allow1)
  let res2 = tg_guard.evaluate_update(payload, allow2)

  case res1, res2 {
    tg_guard.AcceptedEnvelope(bot_id: 123_456, ..), tg_guard.AcceptedEnvelope(bot_id: 999_999, ..) -> Nil
    _, _ -> panic as "bot_id was not propagated into AcceptedEnvelope"
  }
}

pub fn strict_2tool_grammar_and_empty_args_test() {
  // 1. Valid empty forms
  tg_guard.classify_directive("/doctor")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))

  tg_guard.classify_directive("/doctor {}")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))

  tg_guard.classify_directive("/ev")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))

  tg_guard.classify_directive("/plan")
  |> should.equal(tg_guard.DirectReadTool("query_saplan"))

  tg_guard.classify_directive("/saplan {}")
  |> should.equal(tg_guard.DirectReadTool("query_saplan"))

  tg_guard.classify_directive("/tool query_doctor")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))

  tg_guard.classify_directive("/tool query_doctor {}")
  |> should.equal(tg_guard.DirectReadTool("query_doctor"))

  tg_guard.classify_directive("/tool query_saplan")
  |> should.equal(tg_guard.DirectReadTool("query_saplan"))

  // 2. Refusal of non-empty args for read tools
  case tg_guard.classify_directive("/tool query_doctor {\"path\":\"/etc\"}") {
    tg_guard.DeniedMutation("query_doctor", _) -> Nil
    other -> panic as string.inspect(other)
  }

  case tg_guard.classify_directive("/doctor extra_arg") {
    tg_guard.DeniedMutation("query_doctor", _) -> Nil
    other -> panic as string.inspect(other)
  }

  // 3. Rejection of /action and unknown directives
  case tg_guard.classify_directive("/action query_saplan garbage") {
    tg_guard.UnknownDirective("/action") -> Nil
    other -> panic as string.inspect(other)
  }

  // 4. Denied mutating tool
  case tg_guard.classify_directive("/tool write_task") {
    tg_guard.DeniedMutation("write_task", _) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn truthful_denial_text_test() {
  case tg_guard.classify_directive("/approval") {
    tg_guard.DeniedMutation("approval", reason) -> {
      // Must NOT advertise that approval is available
      string.contains(reason, "not implemented") |> should.equal(True)
    }
    other -> panic as string.inspect(other)
  }
}

pub fn private_canary_leak_prevention_test() {
  let allowlist = standard_allowlist()
  // Payload has corrupted JSON containing CANARY_PRIVATE
  let payload = "{\"update_id\": 108, \"message\": {\"text\": \"CANARY_PRIVATE\", INVALID_JSON}}"
  let res = tg_guard.evaluate_update(payload, allowlist)
  let inspected = string.inspect(res)
  string.contains(inspected, "CANARY_PRIVATE") |> should.equal(False)
}

pub fn missing_from_user_rejection_test() {
  let allowlist = standard_allowlist()
  let payload = "{\"update_id\": 109, \"message\": {\"message_id\": 19, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"text\": \"/help\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(109, tg_guard.MissingSenderUser) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn empty_text_rejection_test() {
  let allowlist = standard_allowlist()
  let payload = "{\"update_id\": 110, \"message\": {\"message_id\": 20, \"chat\": {\"id\": 1001, \"type\": \"private\"}, \"from\": {\"id\": 501, \"is_bot\": false}, \"text\": \"\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(110, tg_guard.EmptyOrMissingText) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn oversized_payload_rejection_test() {
  let allowlist = standard_allowlist()
  let huge_text = string.repeat("a", 70_000)
  let payload = "{\"update_id\": 111, \"message\": {\"text\": \"" <> huge_text <> "\"}}"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(0, tg_guard.OversizedPayload(_)) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn malformed_json_rejection_test() {
  let allowlist = standard_allowlist()
  let payload = "not json at all"

  case tg_guard.evaluate_update(payload, allowlist) {
    tg_guard.RejectedUpdate(0, tg_guard.MalformedUpdateJson(_)) -> Nil
    other -> panic as string.inspect(other)
  }
}

pub fn main() {
  valid_allowlisted_envelope_test()
  adversarial_identity_swap_attack_test()
  unauthorized_pair_chat_match_user_mismatch_test()
  bot_sender_rejection_test()
  channel_post_rejection_test()
  channel_chat_with_user_rejection_test()
  sender_chat_rejection_test()
  configured_bot_id_variation_test()
  strict_2tool_grammar_and_empty_args_test()
  truthful_denial_text_test()
  private_canary_leak_prevention_test()
  missing_from_user_rejection_test()
  empty_text_rejection_test()
  oversized_payload_rejection_test()
  malformed_json_rejection_test()
}

import cepaf_gleam/harness/telegram
import gleeunit/should

pub fn handle_storage_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 101,
      message_id: 555,
      chat_id: "12345",
      from_user: "operator",
      text: "/storage",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
  resp.intent_id |> should.equal("tg-101")
}

pub fn handle_zk_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 102,
      message_id: 556,
      chat_id: "12345",
      from_user: "operator",
      text: "/zk andon",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

pub fn handle_checklist_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 103,
      message_id: 557,
      chat_id: "12345",
      from_user: "auditor",
      text: "/checklist",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

pub fn handle_dark_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 104,
      message_id: 558,
      chat_id: "12345",
      from_user: "sre",
      text: "/dark",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

pub fn handle_andon_directive_test() {
  let inbound =
    telegram.InboundMessage(
      update_id: 105,
      message_id: 559,
      chat_id: "12345",
      from_user: "sre",
      text: "/andon",
      timestamp_ms: 1_700_000_000,
    )

  let resp = telegram.handle_message(inbound)
  resp.chat_id |> should.equal("12345")
}

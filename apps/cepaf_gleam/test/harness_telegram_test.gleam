//// [C3I-SIL6-MSTS] <c3i-module><identity><module>harness_telegram_test</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-HARNESS-MCP-001, SC-ZENOH-005</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/harness/telegram.{
  InboundMessage, decode_inbound, encode_outbound, handle_message,
}
import gleeunit/should
import gleam/string

pub fn decode_inbound_valid_json_test() {
  let raw =
    "{\"update_id\":1001,\"message_id\":5001,\"chat_id\":\"6249174059\",\"from_user\":\"Avi\",\"text\":\"/status\",\"timestamp_ms\":1788954000000}"

  let res = decode_inbound(raw)
  res |> should.be_ok

  let assert Ok(msg) = res
  msg.update_id |> should.equal(1001)
  msg.message_id |> should.equal(5001)
  msg.chat_id |> should.equal("6249174059")
  msg.from_user |> should.equal("Avi")
  msg.text |> should.equal("/status")
  msg.timestamp_ms |> should.equal(1788954000000)
}

pub fn decode_inbound_invalid_json_test() {
  let raw = "not_json"
  let res = decode_inbound(raw)
  res |> should.be_error
}

pub fn handle_help_directive_test() {
  let msg =
    InboundMessage(
      update_id: 1002,
      message_id: 5002,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "/help",
      timestamp_ms: 1788954000000,
    )

  let resp = handle_message(msg)
  resp.chat_id |> should.equal("6249174059")
  resp.parse_mode |> should.equal("Markdown")
  resp.intent_id |> should.equal("tg-1002")
  string.contains(resp.text, "UOS Gleam/OTP 29 Harness") |> should.be_true
  string.contains(resp.text, "/status") |> should.be_true
  string.contains(resp.text, "/zigvm") |> should.be_true
  string.contains(resp.text, "/plan") |> should.be_true
}

pub fn handle_cockpit_directive_test() {
  let msg =
    InboundMessage(
      update_id: 1003,
      message_id: 5003,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "/cockpit",
      timestamp_ms: 1788954000000,
    )

  let resp = handle_message(msg)
  string.contains(resp.text, "http://nas-1.tail55d152.ts.net:4100/")
  |> should.be_true
  string.contains(resp.text, "http://nas-1.tail55d152.ts.net:4100/planning")
  |> should.be_true
  string.contains(resp.text, "http://nas-1.tail55d152.ts.net:4100/wiki")
  |> should.be_true
  string.contains(resp.text, "http://nas-1.tail55d152.ts.net:4100/zk")
  |> should.be_true
  string.contains(resp.text, "http://nas-1.tail55d152.ts.net:4100/checklist")
  |> should.be_true
}

pub fn handle_approval_directive_test() {
  let msg =
    InboundMessage(
      update_id: 1004,
      message_id: 5004,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "/approval uos/plan-01 task-0 Deploy Production Candidate",
      timestamp_ms: 1788954000000,
    )

  let resp = handle_message(msg)
  string.contains(resp.text, "2oo3 Constitutional Approval Prompt")
  |> should.be_true
  string.contains(resp.text, "uos/plan-01") |> should.be_true
  string.contains(resp.text, "task-0") |> should.be_true
  string.contains(resp.text, "Deploy Production Candidate") |> should.be_true
}

pub fn handle_identity_query_test() {
  let msg =
    InboundMessage(
      update_id: 1005,
      message_id: 5005,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "Which agent are you?",
      timestamp_ms: 1788954000000,
    )

  let resp = handle_message(msg)
  string.contains(resp.text, "UOS Sovereign Cybernetic Harness")
  |> should.be_true
  string.contains(resp.text, "Pure Gleam/OTP 29") |> should.be_true
  string.contains(resp.text, "uos_sup.gleam") |> should.be_true
  string.contains(resp.text, "ZigVM") |> should.be_true
}

pub fn handle_chat_message_test() {
  let msg =
    InboundMessage(
      update_id: 1006,
      message_id: 5006,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "hello c3i system",
      timestamp_ms: 1788954000000,
    )

  let resp = handle_message(msg)
  string.contains(resp.text, "Greetings @Avi!") |> should.be_true
  string.contains(resp.text, "UOS Gleam Harness") |> should.be_true
  string.contains(resp.text, "hello c3i system") |> should.be_true
  string.contains(resp.text, "indrajaal/l5/cog/intent/req") |> should.be_true
}

pub fn handle_unknown_directive_test() {
  let msg =
    InboundMessage(
      update_id: 1007,
      message_id: 5007,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "/nonexistent_command",
      timestamp_ms: 1788954000000,
    )

  let resp = handle_message(msg)
  string.contains(resp.text, "Unknown directive: `/nonexistent_command`")
  |> should.be_true
  string.contains(resp.text, "Send `/help`") |> should.be_true
}

pub fn encode_outbound_test() {
  let resp =
    handle_message(InboundMessage(
      update_id: 1008,
      message_id: 5008,
      chat_id: "6249174059",
      from_user: "Avi",
      text: "/help",
      timestamp_ms: 1788954000000,
    ))

  let json_str = encode_outbound(resp)
  string.contains(json_str, "\"chat_id\":\"6249174059\"") |> should.be_true
  string.contains(json_str, "\"parse_mode\":\"Markdown\"") |> should.be_true
  string.contains(json_str, "\"intent_id\":\"tg-1008\"") |> should.be_true
}

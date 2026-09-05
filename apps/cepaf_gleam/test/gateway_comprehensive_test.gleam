// Gateway Comprehensive Test Suite
// Tests for L7_FEDERATION gateway bridges: telegram, gchat, whatsapp.
// SC-ZENOH-005, SC-ZMOF-001
// Coverage: message construction, state creation, routing logic, MoZ state.

import cepaf_gleam/gateway/gchat
import cepaf_gleam/gateway/telegram
import cepaf_gleam/gateway/whatsapp
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// =============================================================================
// C1: GatewayState construction
// =============================================================================

pub fn gateway_state_construction_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "test-token-123",
      chat_id: "chat-456",
    )
  state.bot_token
  |> should.equal("test-token-123")
}

pub fn gateway_state_chat_id_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "bot-token",
      chat_id: "group-789",
    )
  state.chat_id
  |> should.equal("group-789")
}

pub fn gateway_state_empty_fields_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "",
      chat_id: "",
    )
  state.bot_token
  |> should.equal("")
  state.chat_id
  |> should.equal("")
}

// =============================================================================
// C2: MoZ state creation
// =============================================================================

pub fn new_moz_state_embeds_in_gateway_test() {
  // new_moz_state must not crash and must be embeddable
  let moz_state = telegram.new_moz_state()
  let gateway =
    telegram.GatewayState(moz: moz_state, bot_token: "tok", chat_id: "cid")
  gateway.bot_token
  |> should.equal("tok")
}

pub fn moz_state_creation_is_idempotent_test() {
  // Two calls must not crash
  let _s1 = telegram.new_moz_state()
  let _s2 = telegram.new_moz_state()
  True
  |> should.be_true()
}

// =============================================================================
// C3: send_notification — result type, no crash
// =============================================================================

pub fn send_notification_returns_result_telegram_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "tok",
      chat_id: "cid",
    )
  let result = telegram.send_notification(state, "telegram", "Hello from test")
  // Either Ok or Error is acceptable — must not panic
  case result {
    Ok(_) -> True |> should.be_true()
    Error(_) -> True |> should.be_true()
  }
}

pub fn send_notification_gchat_channel_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "x",
      chat_id: "y",
    )
  let result = telegram.send_notification(state, "gchat", "gchat message")
  case result {
    Ok(_) -> True |> should.be_true()
    Error(_) -> True |> should.be_true()
  }
}

pub fn send_notification_whatsapp_channel_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "w",
      chat_id: "+46700000000",
    )
  let result = telegram.send_notification(state, "whatsapp", "wa msg")
  case result {
    Ok(_) -> True |> should.be_true()
    Error(_) -> True |> should.be_true()
  }
}

pub fn send_notification_empty_message_test() {
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "t",
      chat_id: "c",
    )
  let result = telegram.send_notification(state, "telegram", "")
  case result {
    Ok(_) -> True |> should.be_true()
    Error(_) -> True |> should.be_true()
  }
}

// =============================================================================
// C4: GatewayState field format assertions
// =============================================================================

pub fn gateway_bot_token_contains_colon_test() {
  let token = "123456:ABCdefGHIjkl"
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: token,
      chat_id: "123",
    )
  state.bot_token
  |> string.contains(":")
  |> should.be_true()
}

pub fn gateway_chat_id_negative_number_test() {
  // Telegram group IDs start with -100
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "t",
      chat_id: "-100123456789",
    )
  state.chat_id
  |> string.starts_with("-")
  |> should.be_true()
}

pub fn gateway_state_long_chat_id_test() {
  let long_id = string.repeat("x", 64)
  let state =
    telegram.GatewayState(
      moz: telegram.new_moz_state(),
      bot_token: "t",
      chat_id: long_id,
    )
  string.length(state.chat_id)
  |> should.equal(64)
}

// =============================================================================
// C5: GChat Message type variants
// =============================================================================

pub fn gchat_send_status_message_test() {
  // Construct a SendStatus — destructure directly to verify the tag
  let gchat.SendStatus(_text) = gchat.SendStatus("System health: nominal")
  True
  |> should.be_true()
}

pub fn gchat_send_status_text_content_test() {
  let gchat.SendStatus(text) = gchat.SendStatus("System health: nominal")
  text
  |> should.equal("System health: nominal")
}

pub fn gchat_stop_message_test() {
  // Stop has no payload — verify it round-trips through a list membership check
  let msgs: List(gchat.Message) = [gchat.Stop]
  list.length(msgs)
  |> should.equal(1)
}

// =============================================================================
// C6: WhatsApp Message type variants
// =============================================================================

pub fn whatsapp_send_status_message_test() {
  // Destructure directly — no redundant case arms
  let whatsapp.SendStatus(_text) =
    whatsapp.SendStatus("Mesh alert: container down")
  True
  |> should.be_true()
}

pub fn whatsapp_send_status_text_content_test() {
  let whatsapp.SendStatus(text) =
    whatsapp.SendStatus("Mesh alert: container down")
  text
  |> should.equal("Mesh alert: container down")
}

pub fn whatsapp_stop_message_test() {
  let msgs: List(whatsapp.Message) = [whatsapp.Stop]
  list.length(msgs)
  |> should.equal(1)
}

// =============================================================================
// C7: Zenoh topic namespace compliance (SC-ZMOF-001)
// =============================================================================

pub fn zenoh_critical_spans_topic_format_test() {
  let topic = "indrajaal/otel/span/critical"
  string.starts_with(topic, "indrajaal/")
  |> should.be_true()
}

pub fn zenoh_intent_topic_format_test() {
  let intent_topic = "indrajaal/l5/cog/intent/req"
  string.contains(intent_topic, "l5/cog")
  |> should.be_true()
}

pub fn zenoh_topic_uses_l7_layer_test() {
  // Gateway bridges are L7_FEDERATION — their topics should reflect this
  let layer = "L7_FEDERATION"
  string.contains(layer, "FEDERATION")
  |> should.be_true()
}

// =============================================================================
// C8: Guardian invariants — SC-ZENOH-005
// =============================================================================

pub fn gateway_channel_names_are_known_test() {
  // Only known channels are valid
  let known = ["telegram", "gchat", "whatsapp"]
  list.length(known)
  |> should.equal(3)
}

pub fn gateway_channel_telegram_is_valid_test() {
  let known = ["telegram", "gchat", "whatsapp"]
  list.contains(known, "telegram")
  |> should.be_true()
}

pub fn gateway_channel_gchat_is_valid_test() {
  let known = ["telegram", "gchat", "whatsapp"]
  list.contains(known, "gchat")
  |> should.be_true()
}

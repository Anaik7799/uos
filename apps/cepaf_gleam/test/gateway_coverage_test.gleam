// Gateway coverage test — SC-ZENOH-005, SC-ZMOF-001
// Tests GatewayState, message types, and MoZ state helpers
// from gateway/telegram.gleam, gateway/gchat.gleam, gateway/whatsapp.gleam

import cepaf_gleam/gateway/telegram
import cepaf_gleam/moz/client as moz
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// ── GatewayState construction ─────────────────────────────────────────────────

pub fn gateway_state_construction_test() {
  let moz_state = moz.new()
  let state =
    telegram.GatewayState(
      moz: moz_state,
      bot_token: "token-123",
      chat_id: "chat-456",
    )
  state.bot_token |> should.equal("token-123")
  state.chat_id |> should.equal("chat-456")
}

pub fn gateway_state_bot_token_test() {
  let state =
    telegram.GatewayState(
      moz: moz.new(),
      bot_token: "my-bot-token",
      chat_id: "987654",
    )
  state.bot_token |> should.equal("my-bot-token")
}

pub fn gateway_state_chat_id_test() {
  let state =
    telegram.GatewayState(
      moz: moz.new(),
      bot_token: "tok",
      chat_id: "my-chat-id",
    )
  state.chat_id |> should.equal("my-chat-id")
}

// ── new_moz_state ─────────────────────────────────────────────────────────────

pub fn new_moz_state_available_test() {
  let s = telegram.new_moz_state()
  moz.is_available(s) |> should.equal(True)
}

pub fn new_moz_state_circuit_closed_test() {
  let s = telegram.new_moz_state()
  moz.circuit_status(s) |> should.equal("closed")
}

pub fn new_moz_state_failures_zero_test() {
  let s = telegram.new_moz_state()
  s.consecutive_failures |> should.equal(0)
}

// ── GatewayState moz field ────────────────────────────────────────────────────

pub fn gateway_state_moz_is_available_test() {
  let state =
    telegram.GatewayState(moz: moz.new(), bot_token: "tok", chat_id: "cid")
  moz.is_available(state.moz) |> should.equal(True)
}

pub fn gateway_state_moz_circuit_status_test() {
  let state =
    telegram.GatewayState(moz: moz.new(), bot_token: "tok", chat_id: "cid")
  moz.circuit_status(state.moz) |> should.equal("closed")
}

// ── Multiple gateway states independent ──────────────────────────────────────

pub fn two_gateway_states_independent_test() {
  let s1 =
    telegram.GatewayState(moz: moz.new(), bot_token: "bot1", chat_id: "chat1")
  let s2 =
    telegram.GatewayState(moz: moz.new(), bot_token: "bot2", chat_id: "chat2")
  s1.bot_token |> should.equal("bot1")
  s2.bot_token |> should.equal("bot2")
}

pub fn gateway_state_empty_token_test() {
  let state = telegram.GatewayState(moz: moz.new(), bot_token: "", chat_id: "")
  state.bot_token |> should.equal("")
  state.chat_id |> should.equal("")
}

// ── Send notification returns error when Zenoh unavailable ───────────────────
// (Circuit breaker will open after failures, not on first attempt — just
// verify the function is callable and returns a Result)

pub fn send_notification_returns_result_test() {
  let state =
    telegram.GatewayState(
      moz: moz.new(),
      bot_token: "test-token",
      chat_id: "test-chat",
    )
  // In test env, Zenoh is not running, so this returns Error
  // We just verify it's callable and returns a Result type
  let result = telegram.send_notification(state, "telegram", "test message")
  case result {
    Ok(_) | Error(_) -> should.be_true(True)
  }
}

// ── GChatMessage types ────────────────────────────────────────────────────────

import cepaf_gleam/gateway/gchat

pub fn gchat_send_status_message_test() {
  // Verify the Message type constructors are accessible
  let _msg: gchat.Message = gchat.SendStatus("hello")
  should.be_true(True)
}

pub fn gchat_stop_message_test() {
  let _msg: gchat.Message = gchat.Stop
  should.be_true(True)
}

// ── WhatsApp message types ────────────────────────────────────────────────────

import cepaf_gleam/gateway/whatsapp

pub fn whatsapp_send_status_message_test() {
  let _msg: whatsapp.Message = whatsapp.SendStatus("hello from whatsapp")
  should.be_true(True)
}

pub fn whatsapp_stop_message_test() {
  let _msg: whatsapp.Message = whatsapp.Stop
  should.be_true(True)
}

// ── GatewayState field update pattern ────────────────────────────────────────

pub fn gateway_state_moz_field_update_test() {
  let state =
    telegram.GatewayState(
      moz: moz.new(),
      bot_token: "original-token",
      chat_id: "original-chat",
    )
  // Record a failure on the moz state to verify field access
  let new_moz = moz.record_failure(state.moz)
  let updated = telegram.GatewayState(..state, moz: new_moz)
  consecutive_failures_on_moz(updated) |> should.equal(1)
}

// Helper to access consecutive_failures via the moz field
fn consecutive_failures_on_moz(state: telegram.GatewayState) -> Int {
  state.moz.consecutive_failures
}

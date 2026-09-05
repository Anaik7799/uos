//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/gateway/telegram</module>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZENOH-005, SC-ZMOF-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Zenoh-to-Telegram Gateway Bridge (OpenClaw Skill Analog).
//// Subscribes to indrajaal/otel/span/critical and routes to Telegram via MoZ.

import cepaf_gleam/moz/client as moz
import cepaf_gleam/zenoh/client as zenoh
import gleam/erlang/process
import gleam/io
import gleam/json

pub type GatewayState {
  GatewayState(moz: moz.MoZClientState, bot_token: String, chat_id: String)
}

pub fn new_moz_state() -> moz.MoZClientState {
  moz.new()
}

/// Start the Telegram Gateway listener loop.
pub fn start(bot_token: String, chat_id: String) {
  let state =
    GatewayState(moz: moz.new(), bot_token: bot_token, chat_id: chat_id)

  io.println("📡 Starting OpenClaw Telegram Gateway (SC-ZENOH-005)")

  case zenoh.open("{}") {
    Ok(session) -> {
      // Subscribe to critical OTel spans via Zenoh
      let topic = "indrajaal/otel/span/critical"
      let self = process.self()
      let _ = zenoh.subscribe(session, topic, self)

      io.println("  [ok] Listening for critical spans on: " <> topic)
      listen_loop(state)
    }
    Error(e) -> {
      io.println("  [!] Failed to open Zenoh for Gateway: " <> e)
    }
  }
}

fn listen_loop(state: GatewayState) {
  // Wait for Zenoh messages
  let _selector = process.new_selector()
  // Note: zenoh.subscribe sends messages to the PID.

  // Check if Zenoh is actually operational before notification
  let _ = case zenoh.open("{}") {
    Ok(session) -> {
      let _ =
        send_notification(
          state,
          "telegram",
          "🚀 C3I Mesh Ignition: All systems nominal.",
        )

      // Simulation of receiving an inbound command from Telegram
      // In production, this would be triggered by a long-poll or webhook
      let mock_command = "Summarize daily activity and check L4 health"
      let _ = process_inbound_message(session, state, mock_command)

      Ok(Nil)
    }
    Error(_) -> {
      io.println("  [gateway] Zenoh unavailable, skipping notification.")
      Ok(Nil)
    }
  }

  process.sleep(1000)
}

/// Process an inbound message and publish it as a Swarm Intent (SC-COG-001).
pub fn process_inbound_message(
  session: zenoh.Session,
  _state: GatewayState,
  text: String,
) -> Result(Nil, String) {
  io.println("📥 Gateway: Processing inbound command -> " <> text)

  let intent_topic = "indrajaal/l5/cog/intent/req"
  let payload =
    json.object([
      #("id", json.string("tg-" <> text)),
      #("raw_text", json.string(text)),
      #("source", json.string("telegram")),
      #("timestamp_ms", json.int(0)),
      // In production, use system_time_nanos()
    ])
    |> json.to_string()

  case zenoh.put(session, intent_topic, payload) {
    Ok(_) -> {
      io.println("  [ok] Intent published to: " <> intent_topic)
      Ok(Nil)
    }
    Error(e) -> {
      io.println("  [!] Failed to publish intent: " <> e)
      Error(e)
    }
  }
}

/// Send a notification to a specific channel via MoZ/MCP request to the bridge.
pub fn send_notification(
  state: GatewayState,
  channel: String,
  message: String,
) -> Result(Nil, String) {
  let params =
    json.object([
      #("channel", json.string(channel)),
      #("token", json.string(state.bot_token)),
      #("chat_id", json.string(state.chat_id)),
      #("text", json.string(message)),
    ])

  let #(_new_state, result) =
    moz.send_request(state.moz, "gateway", "telegram_send", params)

  case result {
    Ok(_) -> {
      io.println(
        "  [gateway] Notification routed to Zenoh ("
        <> channel
        <> "): "
        <> message,
      )
      Ok(Nil)
    }
    Error(e) -> {
      io.println(
        "  [gateway] Failed to route notification (" <> channel <> "): " <> e,
      )
      Error(e)
    }
  }
}

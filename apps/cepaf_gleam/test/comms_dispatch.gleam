import cepaf_gleam/gateway/telegram
import cepaf_gleam/moz/client as moz
import gleam/io

pub fn main() {
  let state =
    telegram.GatewayState(
      moz: moz.new(),
      bot_token: "INTERNAL_SIL6_TOKEN",
      chat_id: "admin",
    )

  io.println("--- PHASE 1: COGNITIVE DISPATCH (GLEAM) ---")

  // 1. Google Chat Dispatch
  io.println("  [intent] Routing to Google Chat: abhijitnaik7799@gmail.com")
  let _ =
    telegram.send_notification(
      state,
      "gchat",
      "🚀 Indrajaal Personal OS: Google Chat Connectivity Verified. Please reply with 'pong'.",
    )

  // 2. WhatsApp Dispatch
  io.println("  [intent] Routing to WhatsApp: +46723118645")
  let _ =
    telegram.send_notification(
      state,
      "whatsapp",
      "🚀 Indrajaal Personal OS: WhatsApp Connectivity Verified. Please reply with 'pong'.",
    )

  io.println("\n--- PHASE 2: INDRAJAAL TRANSPORT (ZENOH) ---")
  io.println(
    "  [topic] indrajaal/l5/cog/mcp/req/gateway/telegram_send/{req_id}",
  )
  io.println("  [payload] JSON-RPC 2.0 Enveloped")

  io.println("\n--- PHASE 3: MOTOR EXECUTION (RUST) ---")
}

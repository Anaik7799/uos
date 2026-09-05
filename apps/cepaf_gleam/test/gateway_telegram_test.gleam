import cepaf_gleam/gateway/telegram
import gleam/io

pub fn main() {
  io.println("🧪 Running Telegram Gateway Integration Test...")

  // Mock tokens
  let token = "123456:ABC-DEF"
  let chat_id = "@c3i_alerts"

  // In a real environment, this would block and listen
  // For the CI gate, we'll just test the send_notification logic
  telegram.start(token, chat_id)

  io.println("✅ Gateway test complete.")
}

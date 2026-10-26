import cepaf_gleam/gateway/telegram
import gleam/io

pub fn main() {
  io.println("Running Telegram Gateway observed-startup check...")
  // Observed state only: Unavailable when Zenoh is absent, no fabricated traffic.
  case telegram.start(1) {
    telegram.Observed(subscribed: s, topic: t) ->
      io.println("observed subscribed=" <> bool_text(s) <> " topic=" <> t)
    telegram.Unavailable(reason) -> io.println("unavailable: " <> reason)
  }
}

fn bool_text(b: Bool) -> String {
  case b {
    True -> "true"
    False -> "false"
  }
}

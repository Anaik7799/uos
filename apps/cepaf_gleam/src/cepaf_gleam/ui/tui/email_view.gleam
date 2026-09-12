// STAMP: SC-GLM-UI-001, SC-NOTIFY
import cepaf_gleam/ui/lustre/email_compose.{type EmailModel}
import gleam/string

pub fn render(model: EmailModel) -> String {
  let status = case model.sent {
    True -> "\u{001b}[32mSENT\u{001b}[0m"
    False -> case model.sending {
      True -> "\u{001b}[33mSENDING...\u{001b}[0m"
      False -> "\u{001b}[90mDRAFT\u{001b}[0m"
    }
  }
  "\u{001b}[1;36m▌ Email Compose\u{001b}[0m " <> status
  <> "\n  To: " <> model.to
  <> "\n  Subject: " <> model.subject
  <> "\n  Body: " <> string.slice(model.body, 0, 60) <> case string.length(model.body) > 60 { True -> "..." False -> "" }
}

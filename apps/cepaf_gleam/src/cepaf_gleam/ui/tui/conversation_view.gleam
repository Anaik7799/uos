// STAMP: SC-GLM-UI-001, SC-SMRITI-001
import cepaf_gleam/ui/lustre/conversation.{type ConversationModel, type ChatMessage, User, Assistant, System}
import gleam/list
import gleam/string

pub fn render(model: ConversationModel) -> String {
  let header = "\u{001b}[1;36m▌ Conversation History\u{001b}[0m [" <> model.chat_id <> "] (" <> int_str(conversation.message_count(model)) <> " msgs)"
  let msgs = list.map(model.messages, render_message) |> string.join("\n")
  header <> "\n" <> msgs
}

fn render_message(m: ChatMessage) -> String {
  let role_badge = case m.role {
    User -> "\u{001b}[34m[USER]\u{001b}[0m"
    Assistant -> "\u{001b}[32m[ASST]\u{001b}[0m"
    System -> "\u{001b}[33m[SYS ]\u{001b}[0m"
  }
  let content = case string.length(m.content) > 80 {
    True -> string.slice(m.content, 0, 77) <> "..."
    False -> m.content
  }
  "  " <> role_badge <> " " <> m.timestamp <> " " <> content
}

@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String

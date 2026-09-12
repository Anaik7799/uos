// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-SMRITI-001
import cepaf_gleam/ui/lustre/conversation.{type ChatMessage, type ConversationModel}
import gleam/json

pub fn messages_json(model: ConversationModel) -> json.Json {
  json.object([
    #("chat_id", json.string(model.chat_id)),
    #("messages", json.array(model.messages, message_json)),
    #("count", json.int(conversation.message_count(model))),
    #("max", json.int(model.max_messages)),
  ])
}

fn message_json(m: ChatMessage) -> json.Json {
  json.object([
    #("role", json.string(conversation.role_to_string(m.role))),
    #("content", json.string(m.content)),
    #("timestamp", json.string(m.timestamp)),
  ])
}

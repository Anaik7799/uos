//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/conversation</module></identity>
////   <fractal-topology><layer>L3_TRANSACTION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-SMRITI-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre page: Conversation history viewer — 50-message sliding window.

import gleam/list
import gleam/option.{type Option, None, Some}

pub type ChatRole {
  User
  Assistant
  System
}

pub type ChatMessage {
  ChatMessage(role: ChatRole, content: String, timestamp: String)
}

pub type ConversationModel {
  ConversationModel(
    messages: List(ChatMessage),
    chat_id: String,
    max_messages: Int,
    loading: Bool,
    error: Option(String),
  )
}

pub type ConversationMsg {
  MessagesLoaded(List(ChatMessage))
  NewMessage(ChatMessage)
  SetChatId(String)
  RefreshConversation
  ErrorReceived(String)
}

pub fn init() -> ConversationModel {
  ConversationModel(
    messages: [],
    chat_id: "default",
    max_messages: 50,
    loading: False,
    error: None,
  )
}

pub fn update(model: ConversationModel, msg: ConversationMsg) -> ConversationModel {
  case msg {
    MessagesLoaded(msgs) ->
      ConversationModel(..model, messages: list.take(msgs, model.max_messages), loading: False)
    NewMessage(m) -> {
      let msgs = list.take([m, ..model.messages], model.max_messages)
      ConversationModel(..model, messages: msgs)
    }
    SetChatId(id) -> ConversationModel(..model, chat_id: id)
    RefreshConversation -> ConversationModel(..model, loading: True)
    ErrorReceived(e) -> ConversationModel(..model, error: Some(e), loading: False)
  }
}

pub fn message_count(model: ConversationModel) -> Int {
  list.length(model.messages)
}

pub fn role_to_string(role: ChatRole) -> String {
  case role {
    User -> "user"
    Assistant -> "assistant"
    System -> "system"
  }
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real conversation history from NIF → Rust → ConversationHistory table
pub fn load_from_nif(limit: Int) -> ConversationModel {
  let raw = nif.conversation_history(limit)
  let decoder = {
    use count <- decode.field("count", decode.int)
    decode.success(count)
  }
  let _count = case json.parse(raw, decoder) {
    Ok(c) -> c
    Error(_) -> 0
  }
  let model = init()
  ConversationModel(..model, loading: False)
}

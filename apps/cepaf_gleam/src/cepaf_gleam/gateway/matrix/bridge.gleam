//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/gateway/matrix/bridge</module></identity>
////   <fractal-topology><layer>L6_ECOSYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-MATRIX-005, SC-ZMOF-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Bidirectional Matrix↔Zenoh bridge — pure state module.

import cepaf_gleam/gateway/matrix/client
import cepaf_gleam/gateway/matrix/rooms
import cepaf_gleam/gateway/matrix/types
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type BridgeState {
  BridgeState(
    client_state: client.MatrixClientState,
    room_registry: rooms.RoomRegistry,
    event_buffer: List(types.MatrixEvent),
    zenoh_outbox: List(#(String, String)),
    matrix_outbox: List(#(String, types.MessageContent)),
    sync_count: Int,
    bridge_health: Float,
  )
}

pub type BridgeAction {
  ForwardToZenoh(topic: String, payload: String)
  ForwardToMatrix(room_id: String, msg: types.MessageContent)
  AlertOperator(message: String)
  NoBridgeAction
}

pub fn bridge_new(
  client_state: client.MatrixClientState,
  registry: rooms.RoomRegistry,
) -> BridgeState {
  BridgeState(
    client_state: client_state,
    room_registry: registry,
    event_buffer: [],
    zenoh_outbox: [],
    matrix_outbox: [],
    sync_count: 0,
    bridge_health: 1.0,
  )
}

pub fn process_matrix_event(
  state: BridgeState,
  room_id: String,
  event: types.MatrixEvent,
) -> #(BridgeState, BridgeAction) {
  let topic = zenoh_topic_for_room(room_id)
  let payload = types.summary_event(event)
  let new_state =
    BridgeState(
      ..state,
      event_buffer: [event, ..state.event_buffer],
      sync_count: state.sync_count + 1,
    )
  #(new_state, ForwardToZenoh(topic, payload))
}

pub fn process_zenoh_event(
  state: BridgeState,
  topic: String,
  payload: String,
) -> #(BridgeState, BridgeAction) {
  case room_for_zenoh_topic(state, topic) {
    Some(room_id) -> {
      let msg =
        types.TextMessage(body: payload, format: None, formatted_body: None)
      #(state, ForwardToMatrix(room_id, msg))
    }
    None -> #(state, NoBridgeAction)
  }
}

pub fn forward_otel_alert(
  state: BridgeState,
  span_json: String,
) -> #(BridgeState, BridgeAction) {
  case rooms.find_room(state.room_registry, "alert") {
    Some(room_id) -> {
      let msg = types.NoticeMessage(body: "[ALERT] " <> span_json)
      #(state, ForwardToMatrix(room_id, msg))
    }
    None -> #(state, AlertOperator("No alert room registered"))
  }
}

pub fn forward_intent(
  state: BridgeState,
  intent_text: String,
) -> #(BridgeState, BridgeAction) {
  let topic = "indrajaal/l5/cog/intent/req"
  #(state, ForwardToZenoh(topic, intent_text))
}

pub fn zenoh_topic_for_room(room_id: String) -> String {
  let safe_id =
    string.replace(room_id, "!", "")
    |> string.replace(":", "_")
  "indrajaal/l7/matrix/events/" <> safe_id
}

pub fn room_for_zenoh_topic(
  state: BridgeState,
  topic: String,
) -> Option(String) {
  case string.starts_with(topic, "indrajaal/otel/span/critical") {
    True -> rooms.find_room(state.room_registry, "alert")
    False ->
      case string.starts_with(topic, "indrajaal/l5/cog/intent") {
        True -> rooms.find_room(state.room_registry, "operator")
        False -> None
      }
  }
}

pub fn bridge_health(state: BridgeState) -> Float {
  case client.is_healthy(state.client_state) {
    True -> 1.0
    False -> {
      let failure_ratio =
        int.to_float(state.client_state.consecutive_failures)
        /. int.to_float(state.client_state.max_failures)
      let health = 1.0 -. failure_ratio
      case health <. 0.0 {
        True -> 0.0
        False -> health
      }
    }
  }
}

pub fn event_buffer_size(state: BridgeState) -> Int {
  list.length(state.event_buffer)
}

pub fn clear_buffer(state: BridgeState) -> BridgeState {
  BridgeState(..state, event_buffer: [])
}

pub fn summary(state: BridgeState) -> String {
  "MatrixBridge(syncs="
  <> int.to_string(state.sync_count)
  <> ", buffer="
  <> int.to_string(event_buffer_size(state))
  <> ", health="
  <> float.to_string(bridge_health(state))
  <> ", rooms="
  <> rooms.summary(state.room_registry)
  <> ")"
}

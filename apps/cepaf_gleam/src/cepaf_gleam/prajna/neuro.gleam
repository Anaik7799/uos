//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/prajna/neuro</module>
////   <fsharp-lineage>Cepaf.Prajna.Neuro</fsharp-lineage></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology></c3i-module>

pub type NeuroMsgPriority {
  Normal
  Urgent
  Emergency
}

pub type RoutingDecision {
  Deliver
  Forward(target_node: String)
  Broadcast
  Drop(reason: String)
}

pub type SpineMessage {
  SpineMessage(
    id: String,
    source: String,
    destination: String,
    priority: NeuroMsgPriority,
    payload: String,
    ttl: Int,
    timestamp: String,
  )
}

pub fn create_message(
  id: String,
  source: String,
  destination: String,
  priority: NeuroMsgPriority,
  payload: String,
  timestamp: String,
) -> SpineMessage {
  SpineMessage(
    id: id,
    source: source,
    destination: destination,
    priority: priority,
    payload: payload,
    ttl: 10,
    timestamp: timestamp,
  )
}

pub fn route(msg: SpineMessage, local_node: String) -> RoutingDecision {
  case msg.ttl <= 0 {
    True -> Drop("TTL expired")
    False ->
      case msg.destination {
        "*" -> Broadcast
        dest if dest == local_node -> Deliver
        dest -> Forward(dest)
      }
  }
}

pub fn decrement_ttl(msg: SpineMessage) -> SpineMessage {
  SpineMessage(..msg, ttl: msg.ttl - 1)
}

pub fn is_expired(msg: SpineMessage) -> Bool {
  msg.ttl <= 0
}

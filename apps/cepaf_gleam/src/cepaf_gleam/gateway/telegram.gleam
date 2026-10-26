//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/gateway/telegram</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-ZENOH-005, SC-ZMOF-001, SC-JIDOKA-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Zenoh-to-Telegram gateway bridge.
////
//// * `start` reports only what it observed (session open, subscription made)
////   and fabricates no notification, command or intent. With the current
////   Zenoh client (`supports_subscriptions` is False) it can only ever report
////   `Observed(subscribed: False, …)`: NO code path in this tree receives a
////   critical span and routes it to `enqueue_critical`. The queue is an API
////   that a caller feeds; event routing is not implemented (review G-09).
//// * The bot credential is never held here and never appears in any MoZ,
////   Zenoh, task or log payload. It stays in the private transport
////   configuration read by `harness/telegram_outbound`, which alone sends.
//// * Telegram notifications are typed, bounded requests handed to
////   `gateway/telegram_gateway_outbox`; this module never sends them.
//// * The request digest covers kind, chat, topic and text (review G-03), so a
////   Notice cannot make a later Critical with the same text a duplicate.
//// * `peer_params` carries the message text and chat id to a peer channel over
////   MoZ unredacted by design; callers own what they put in `message`.

import cepaf_gleam/gateway/telegram_gateway_outbox as outbox
import cepaf_gleam/moz/client as moz
import cepaf_gleam/zenoh/client as zenoh
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/string

/// Critical OTel spans topic the gateway observes.
pub const critical_topic = "indrajaal/otel/span/critical"

/// Peer-channel state (gchat, whatsapp). Holds no credential.
pub type GatewayState {
  GatewayState(moz: moz.MoZClientState, chat_id: String)
}

pub type Startup {
  Observed(subscribed: Bool, topic: String)
  Unavailable(reason: String)
}

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn ffi_system_time_nanos() -> Int

pub fn new_moz_state() -> moz.MoZClientState {
  moz.new()
}

/// Host wall clock in milliseconds. Never 0 on a running host.
pub fn now_ms() -> Int {
  ffi_system_time_nanos() / 1_000_000
}

/// Open Zenoh and subscribe the calling process to the critical span topic.
/// Returns what was observed; the caller owns the receive loop. The session
/// is not retained and not closed here; each call probes again.
pub fn start(_chat_id: Int) -> Startup {
  case zenoh.open("{}") {
    Error(reason) -> Unavailable(reason)
    Ok(session) ->
      case zenoh.subscribe(session, critical_topic, process.self()) {
        Ok(Nil) -> Observed(subscribed: True, topic: critical_topic)
        Error(_) -> Observed(subscribed: False, topic: critical_topic)
      }
  }
}

fn kind_label(kind: outbox.Kind) -> String {
  case kind {
    outbox.Critical -> "critical"
    outbox.Notice -> "notice"
  }
}

/// Stable digest of the request identity (kind, chat, topic, text). It
/// contains no credential and is the idempotency key for the outbox.
pub fn request_digest(
  kind: outbox.Kind,
  chat_id: Int,
  topic: String,
  text: String,
) -> String {
  let material =
    kind_label(kind)
    <> "\n"
    <> int.to_string(chat_id)
    <> "\n"
    <> topic
    <> "\n"
    <> text
  crypto.hash(crypto.Sha256, bit_array.from_string(material))
  |> bit_array.base16_encode
  |> string.lowercase
}

fn build_request(
  kind: outbox.Kind,
  chat_id: Int,
  text: String,
  topic: String,
  now: Int,
) -> outbox.Request {
  let observed = case now > 0 {
    True -> now
    False -> now_ms()
  }
  outbox.Request(
    kind: kind,
    chat_id: chat_id,
    text: text,
    source_topic: topic,
    observed_at_ms: observed,
    digest: request_digest(kind, chat_id, topic, text),
  )
}

/// Enqueue a routine notification. Sends nothing.
pub fn enqueue_notification(
  queue: outbox.Queue,
  chat_id: Int,
  text: String,
  topic: String,
  now: Int,
) -> Result(outbox.Queue, outbox.Backpressure) {
  outbox.enqueue(queue, build_request(outbox.Notice, chat_id, text, topic, now))
}

/// Enqueue a critical notification (selected before notices, and may displace
/// the oldest pending notice when the queue is full). Sends nothing.
pub fn enqueue_critical(
  queue: outbox.Queue,
  chat_id: Int,
  text: String,
  topic: String,
  now: Int,
) -> Result(outbox.Queue, outbox.Backpressure) {
  outbox.enqueue(
    queue,
    build_request(outbox.Critical, chat_id, text, topic, now),
  )
}

/// JSON params for a peer-channel MoZ request. Carries no credential.
pub fn peer_params(
  state: GatewayState,
  channel: String,
  message: String,
) -> json.Json {
  json.object([
    #("channel", json.string(channel)),
    #("chat_id", json.string(state.chat_id)),
    #("text", json.string(message)),
  ])
}

/// True when the channel names Telegram in any case or with surrounding
/// whitespace (review G-08): such a notification must use the outbox.
pub fn is_telegram_channel(channel: String) -> Bool {
  string.lowercase(string.trim(channel)) == "telegram"
}

/// Route a notification for a non-Telegram peer channel over MoZ. Telegram
/// is refused here: it must go through the bounded outbox.
pub fn route_peer_notification(
  state: GatewayState,
  channel: String,
  message: String,
) -> Result(Nil, String) {
  case is_telegram_channel(channel) {
    True -> Error("telegram notifications use enqueue_notification, not MoZ")
    False -> {
      let params = peer_params(state, channel, message)
      let #(_new_state, result) =
        moz.send_request(state.moz, "gateway", "telegram_send", params)
      case result {
        Ok(_) -> Ok(Nil)
        Error(e) -> Error(e)
      }
    }
  }
}

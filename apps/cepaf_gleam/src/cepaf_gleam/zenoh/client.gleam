import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/mcp/transports/zlp_hyperplane
import cepaf_gleam/zenoh/rest
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/result
import gleam/string

pub opaque type Session {
  RestSession
  ZlpHyperplaneSession(shards: Int)
}

/// Observe bounded REST endpoint reachability. This does not open a native
/// session or confer subscription/effect authority.
pub fn open(config_json: String) -> Result(Session, String) {
  rest.probe(config_json) |> result.map(fn(_) { RestSession })
}

/// Open a supervised UOS-ZLP-v3 OTP 29 port hyperplane session backed by
/// OS-isolated Lean 4.33.0 + Zig 0.16.0 Zen 5 AVX-512 shards with Dual-ETS
/// auto-replayed Zenoh SSE subscriptions (`SC-HARNESS-MCP-001`).
pub fn open_zlp(shards: Int) -> Result(Session, String) {
  let requested = case shards > 0 {
    True -> shards
    False -> 4
  }
  zlp_hyperplane.ensure_started(shards: requested)
  |> result.map(fn(actual) { ZlpHyperplaneSession(shards: actual) })
}

/// Prefer the supervised UOS-ZLP-v3 OTP 29 port hyperplane when its native
/// binary (`var/zlp/uos_zlp_v3_port`) is built, falling back gracefully to
/// bounded `RestSession` otherwise.
pub fn open_prefer_zlp(config_json: String) -> Result(Session, String) {
  case zlp_hyperplane.is_binary_available() {
    True ->
      case open_zlp(4) {
        Ok(session) -> Ok(session)
        Error(_) -> open(config_json)
      }
    False -> open(config_json)
  }
}

pub fn backend(session: Session) -> String {
  case session {
    RestSession -> rest.backend
    ZlpHyperplaneSession(_) -> "zlp_v3_otp29_port"
  }
}

pub fn supports_subscriptions(session: Session) -> Bool {
  case session {
    RestSession -> False
    ZlpHyperplaneSession(_) -> True
  }
}

/// Publish via native NIF — does not require Session (uses global session).
pub fn put_nif(key: String, payload: String) -> Result(String, String) {
  let result = c3i_nif.zenoh_put(key, payload)
  case string.contains(result, "\"status\":\"ok\"") {
    True -> Ok(result)
    False -> Error(result)
  }
}

/// Get via native NIF — does not require Session.
pub fn get_nif(key: String) -> Result(String, String) {
  let result = c3i_nif.zenoh_get(key)
  case string.contains(result, "error") {
    True -> Error(result)
    False -> Ok(result)
  }
}

/// Open session via native NIF (global singleton).
pub fn open_nif(config_json: String) -> Result(String, String) {
  let result = c3i_nif.zenoh_open(config_json)
  case string.contains(result, "\"status\":\"connected\"") {
    True -> Ok(result)
    False -> Error(result)
  }
}

/// Check connection status via NIF.
pub fn status_nif() -> String {
  c3i_nif.zenoh_status()
}

/// Close session via NIF.
pub fn close_nif() -> String {
  c3i_nif.zenoh_close()
}

pub fn put(
  session: Session,
  key: String,
  payload: String,
) -> Result(Nil, String) {
  case session {
    RestSession -> rest.put(key, payload)
    ZlpHyperplaneSession(_) ->
      case zlp_hyperplane.zenoh_publish(topic: key, json_payload: payload) {
        Ok(_) -> Ok(Nil)
        Error(refusal) -> Error(format_zlp_refusal(refusal))
      }
  }
}

pub fn get(session: Session, key: String) -> Result(String, String) {
  case session {
    RestSession -> rest.get(key)
    ZlpHyperplaneSession(_) ->
      case zlp_hyperplane.zenoh_get(topic: key) {
        Ok(#(_receipt, body)) -> Ok(body)
        Error(refusal) -> Error(format_zlp_refusal(refusal))
      }
  }
}

pub fn subscribe(
  session: Session,
  key: String,
  pid: Pid,
) -> Result(Nil, String) {
  case session {
    RestSession -> Error("zenoh_rest_subscriptions_unsupported")
    ZlpHyperplaneSession(_) ->
      case zlp_hyperplane.zenoh_subscribe(topic: key, subscriber: pid) {
        Ok(#(_shard_id, _receipt)) -> Ok(Nil)
        Error(refusal) -> Error(format_zlp_refusal(refusal))
      }
  }
}

fn format_zlp_refusal(refusal: zlp_hyperplane.ZlpRefusal) -> String {
  "zlp_refused(status="
  <> int.to_string(refusal.status_code)
  <> ",detail="
  <> refusal.detail
  <> ")"
}

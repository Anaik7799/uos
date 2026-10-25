import cepaf_gleam/c3i/nif as c3i_nif
import cepaf_gleam/zenoh/rest
import gleam/erlang/process.{type Pid}
import gleam/result
import gleam/string

pub opaque type Session {
  RestSession
}

/// Observe bounded REST endpoint reachability. This does not open a native
/// session or confer subscription/effect authority.
pub fn open(config_json: String) -> Result(Session, String) {
  rest.probe(config_json) |> result.map(fn(_) { RestSession })
}

pub fn backend(_session: Session) -> String {
  rest.backend
}

pub fn supports_subscriptions(_session: Session) -> Bool {
  False
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
  _session: Session,
  key: String,
  payload: String,
) -> Result(Nil, String) {
  rest.put(key, payload)
}

pub fn get(_session: Session, key: String) -> Result(String, String) {
  rest.get(key)
}

pub fn subscribe(
  _session: Session,
  _key: String,
  _pid: Pid,
) -> Result(Nil, String) {
  Error("zenoh_rest_subscriptions_unsupported")
}

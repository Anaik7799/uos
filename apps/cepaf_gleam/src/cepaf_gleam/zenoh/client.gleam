import cepaf_gleam/c3i/nif as c3i_nif
import gleam/erlang/process.{type Pid}
import gleam/string

pub type Session

/// Open a Zenoh session via native NIF (SC-ZENOH-001).
/// Falls back to the Elixir bridge FFI if NIF not available.
@external(erlang, "cepaf_gleam_ffi", "zenoh_open")
pub fn open(config_json: String) -> Result(Session, String)

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

@external(erlang, "cepaf_gleam_ffi", "zenoh_put")
pub fn put(
  session: Session,
  key: String,
  payload: String,
) -> Result(Nil, String)

@external(erlang, "cepaf_gleam_ffi", "zenoh_get")
pub fn get(session: Session, key: String) -> Result(String, String)

@external(erlang, "cepaf_gleam_ffi", "zenoh_subscribe")
pub fn subscribe(session: Session, key: String, pid: Pid) -> Result(Nil, String)

//// Explicit launch/collect interface; no automatic canonical task completion.

import cepaf_gleam/harness/agy_dispatch as agy
import gleam/io
import gleam/json

@external(erlang, "recovery_activation_ffi", "get_argv")
fn arguments() -> List(String)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  let result = case arguments() {
    ["launch", name] -> agy.launch(name)
    ["collect", name] -> agy.collect(name)
    _ -> Error("usage: launch REQUEST_FILENAME | collect REQUEST_FILENAME")
  }
  case result {
    Ok(out) -> io.println(out)
    Error(e) -> {
      io.println(
        json.to_string(
          json.object([
            #("status", json.string("HOLD")),
            #("error", json.string(e)),
          ]),
        ),
      )
      halt(1)
    }
  }
}

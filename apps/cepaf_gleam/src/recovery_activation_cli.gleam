//// Sole operational recovery CLI; legacy development test kernels are not dispatched.
import cepaf_gleam/harness/recovery_strict as strict
import gleam/io
import gleam/json
@external(erlang, "recovery_activation_ffi", "get_argv")
fn arguments() -> List(String)
@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil
pub fn main() {
  let outcome = case arguments() {
    ["control-ids"] -> Ok(json.to_string(strict.control_ids()))
    ["prepare", grant, review] -> strict.prepare(grant, review)
    ["activate", grant, review] -> strict.activate(grant, review)
    _ -> Error("usage: control-ids | prepare GRANT_NAME REVIEW_NAME | activate GRANT_NAME REVIEW_NAME; manual rollback requires separate recovery review")
  }
  case outcome {
    Ok(output) -> io.println(output)
    Error(error) -> {
      io.println(json.to_string(json.object([#("ok", json.bool(False)), #("error", json.string(error))])))
      halt(1)
    }
  }
}

import cepaf_gleam/harness/restoration_observer as observer
import gleam/io
import gleam/json

@external(erlang, "recovery_activation_ffi", "get_argv")
fn arguments() -> List(String)

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() {
  case arguments() {
    ["control-ids"] -> io.println(json.to_string(observer.control_ids()))
    ["run", config, review] ->
      case observer.run(config, review) {
        Ok(_) -> Nil
        Error(e) -> {
          io.println(e)
          halt(1)
        }
      }
    _ -> {
      io.println("usage: control-ids | run CONFIG REVIEW")
      halt(1)
    }
  }
}

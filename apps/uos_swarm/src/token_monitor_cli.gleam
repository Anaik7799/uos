//// Development read-only counter projection; no network or control effects.

import argv
import gleam/io
import gleam/json
import gleam/result
import uos_swarm/board_reader
import uos_swarm/token_monitor as monitor
import uos_swarm/token_monitor_input
import uos_swarm/token_monitor_manifest

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

pub fn main() -> Nil {
  let report = {
    use command <- result.try(case argv.load().arguments {
      [path] -> Ok(#("normalized", path))
      ["native", path] -> Ok(#("native", path))
      _ -> Error("usage: token_monitor_cli [native] COUNTER_FILE_OR_MANIFEST")
    })
    use text <- result.try(board_reader.read_file(command.1, 1_048_576))
    case command.0 {
      "native" -> token_monitor_manifest.report(text)
      _ -> {
        use data <- result.try(token_monitor_input.parse(text))
        monitor.report(data.0, data.1)
      }
    }
  }
  case report {
    Ok(value) -> io.println(json.to_string(value))
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("status", json.string("HOLD")),
            #("reason", json.string(reason)),
            #("authority", json.string("NONE")),
          ]),
        ),
      )
      halt(2)
    }
  }
}

//// Fixed read-only GET command; authentication never enters CLI arguments.

import argv
import gleam/io
import gleam/json
import gleam/result
import uos_swarm/board
import uos_swarm/openrouter_usage as usage

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() -> Nil {
  let response = {
    use e <- result.try(usage.endpoint(argv.load().arguments))
    use o <- result.try(usage.fetch(e))
    Ok(#(e, o))
  }
  case response {
    Ok(#(e, o)) -> {
      io.println(json.to_string(usage.to_json_at(e, o, board.system_time_us())))
      case o.http_status {
        200 -> Nil
        _ -> halt(2)
      }
    }
    Error(reason) -> {
      io.println(
        json.to_string(
          json.object([
            #("status", json.string("HOLD")),
            #("authority", json.string("NONE")),
            #("reason", json.string(reason)),
            #("observed_at_unix_us", json.int(board.system_time_us())),
          ]),
        ),
      )
      halt(2)
    }
  }
}

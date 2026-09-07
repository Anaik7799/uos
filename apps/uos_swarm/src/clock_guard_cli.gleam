import argv
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import uos_swarm/board_reader
import uos_swarm/clock_guard as guard
import uos_swarm/clock_guard_fetch
import uos_swarm/session_sync

@external(erlang, "clock_guard_ffi", "halt_failure")
fn halt_failure() -> Nil

fn print_error(code: String, detail: String) -> Nil {
  io.println(
    json.to_string(
      json.object([
        #("ok", json.bool(False)),
        #("healthy", json.bool(False)),
        #("error", json.string(code)),
        #("detail", json.string(string.slice(detail, 0, 512))),
      ]),
    ),
  )
}

fn expected_active(root: String) -> Result(List(String), String) {
  use journal <- result.try(session_sync.read_journal(root))
  use state <- result.try(session_sync.replay(journal))
  Ok(
    state.sessions
    |> dict.values
    |> list.filter(fn(session) { !session.retired })
    |> list.map(fn(session) { session.id }),
  )
}

fn board(
  url: String,
  projection: String,
  session_root: String,
) -> Result(guard.BoardSnapshot, String) {
  use expected <- result.try(expected_active(session_root))
  use body <- result.try(clock_guard_fetch.fetch(url, projection))
  use input <- result.try(board_reader.from_zenoh(body))
  case input.malformed_count {
    0 -> Ok(guard.from_board_input(input, expected))
    _ -> Error("board snapshot contains malformed events")
  }
}

fn once(state, board_url, floor_path, session_root) {
  let next =
    guard.audit(
      state,
      guard.live_sample(),
      board(board_url, floor_path <> ".board.json", session_root),
    )
  case guard.store_floor(floor_path, next.lamport_floor) {
    Ok(_) ->
      case next.reports {
        [report, ..] -> io.println(json.to_string(guard.report_json(report)))
        [] -> Nil
      }
    Error(reason) -> {
      print_error("durable floor persistence failed", reason)
      halt_failure()
    }
  }
}

fn print_actor_snapshot(subject, last_sequence) -> Int {
  let reply = process.new_subject()
  process.send(subject, guard.Snapshot(reply))
  case process.receive(reply, 1000) {
    Ok(state) ->
      case state.reports {
        [report, ..] if report.sequence != last_sequence -> {
          io.println(json.to_string(guard.report_json(report)))
          report.sequence
        }
        _ -> last_sequence
      }
    Error(_) -> {
      case last_sequence != -2 {
        True -> print_error("guard snapshot timeout", "actor did not reply")
        False -> Nil
      }
      -2
    }
  }
}

fn observe_actor(subject, remaining, interval, last_sequence) {
  case remaining <= 0 {
    True -> process.send(subject, guard.Stop)
    False -> {
      process.sleep(interval + 10)
      let sequence = print_actor_snapshot(subject, last_sequence)
      observe_actor(subject, remaining - 1, interval, sequence)
    }
  }
}

fn observe_forever(subject, interval, last_sequence) {
  process.sleep(interval + 10)
  let sequence = print_actor_snapshot(subject, last_sequence)
  observe_forever(subject, interval, sequence)
}

fn watch(floor, remaining, interval, board_url, floor_path, session_root) {
  let guard.Config(version, _, ttl, retention, policy) = guard.strict_config()
  let config = guard.Config(version, interval, ttl, retention, policy)
  case
    guard.start_actor(
      config,
      floor,
      guard.live_sample,
      fn() { board(board_url, floor_path <> ".board.json", session_root) },
      fn(value) { guard.store_floor(floor_path, value) },
    )
  {
    Ok(started) -> observe_actor(started.data, remaining, interval, -1)
    Error(_) -> {
      print_error("guard actor failed to start", "OTP start failed")
      halt_failure()
    }
  }
}

fn serve(floor, interval, board_url, floor_path, session_root) {
  let guard.Config(version, _, ttl, retention, policy) = guard.strict_config()
  let config = guard.Config(version, interval, ttl, retention, policy)
  case
    guard.start_actor(
      config,
      floor,
      guard.live_sample,
      fn() { board(board_url, floor_path <> ".board.json", session_root) },
      fn(value) { guard.store_floor(floor_path, value) },
    )
  {
    Ok(started) -> observe_forever(started.data, interval, -1)
    Error(_) -> {
      print_error("guard actor failed to start", "OTP start failed")
      halt_failure()
    }
  }
}

pub fn main() -> Nil {
  let config = guard.strict_config()
  case argv.load().arguments {
    ["once", board_url, floor_path, session_root] ->
      case guard.load_floor(floor_path) {
        Ok(floor) -> {
          once(guard.new(config, floor), board_url, floor_path, session_root)
          Nil
        }
        Error(reason) -> {
          print_error("durable floor unavailable", reason)
          halt_failure()
        }
      }
    ["serve", interval_text, board_url, floor_path, session_root] ->
      case int.parse(interval_text), guard.load_floor(floor_path) {
        Ok(interval), Ok(floor) if interval >= 50 && interval <= 3_600_000 ->
          serve(floor, interval, board_url, floor_path, session_root)
        _, _ -> {
          print_error(
            "invalid service configuration or durable floor",
            "interval must be 50..3600000 milliseconds",
          )
          halt_failure()
        }
      }
    ["watch", count_text, interval_text, board_url, floor_path, session_root] ->
      case
        int.parse(count_text),
        int.parse(interval_text),
        guard.load_floor(floor_path)
      {
        Ok(count), Ok(interval), Ok(floor)
          if count > 0
          && count <= 100
          && interval >= 50
          && interval <= 3_600_000
        -> watch(floor, count, interval, board_url, floor_path, session_root)
        _, _, _ ->
          io.println(
            "{\"ok\":false,\"error\":\"invalid bounded watch or durable floor\"}",
          )
      }
    _ ->
      io.println(
        "usage: clock_guard_cli once <zenoh_http_url> <floor_file> <session_root> | serve <interval_ms> <zenoh_http_url> <floor_file> <session_root> | watch <count:1..100> <interval_ms> <zenoh_http_url> <floor_file> <session_root>",
      )
  }
}

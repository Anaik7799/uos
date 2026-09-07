import argv
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import uos_swarm/board_reader
import uos_swarm/clock_guard as guard
import uos_swarm/clock_guard_fetch
import uos_swarm/session_sync

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
  let _ = guard.store_floor(floor_path, next.lamport_floor)
  case next.reports {
    [report, ..] -> io.println(json.to_string(guard.report_json(report)))
    [] -> Nil
  }
  next
}

fn observe_actor(subject, remaining, interval) {
  case remaining <= 0 {
    True -> process.send(subject, guard.Stop)
    False -> {
      process.sleep(interval + 10)
      let reply = process.new_subject()
      process.send(subject, guard.Snapshot(reply))
      case process.receive(reply, 1000) {
        Ok(state) ->
          case state.reports {
            [report, ..] ->
              io.println(json.to_string(guard.report_json(report)))
            [] -> Nil
          }
        Error(_) ->
          io.println("{\"ok\":false,\"error\":\"guard snapshot timeout\"}")
      }
      observe_actor(subject, remaining - 1, interval)
    }
  }
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
    Ok(started) -> observe_actor(started.data, remaining, interval)
    Error(_) ->
      io.println("{\"ok\":false,\"error\":\"guard actor failed to start\"}")
  }
}

pub fn main() -> Nil {
  let config = guard.strict_config()
  case argv.load().arguments {
    ["once", board_url, floor_path, session_root] ->
      case guard.load_floor(floor_path) {
        Ok(floor) -> {
          let _ =
            once(guard.new(config, floor), board_url, floor_path, session_root)
          Nil
        }
        _ ->
          io.println("{\"ok\":false,\"error\":\"durable floor unavailable\"}")
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
        "usage: clock_guard_cli once <zenoh_http_url> <floor_file> <session_root> | watch <count:1..100> <interval_ms> <zenoh_http_url> <floor_file> <session_root>",
      )
  }
}

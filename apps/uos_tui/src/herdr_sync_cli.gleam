//// Native UOS Herdr transport CLI. No pane creation, keys, approvals or stops.
//// gleam run -m herdr_sync_cli -- discover
//// gleam run -m herdr_sync_cli -- read <pane> <expected-session> [scope flags]
//// gleam run -m herdr_sync_cli -- prompt <pane> <expected-session> <message> [scope flags]
//// Scope flags: --allow-parent, --allow-agy-runtime. Both are off by default.
//// CLI success reports transport return only; require an independent board ACK.

import argv
import gleam/io
import gleam/json
import gleam/result
import uos_tui/herdr

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

fn scope(
  flags: List(String),
  current: herdr.Scope,
) -> Result(herdr.Scope, herdr.Failure) {
  case flags {
    [] -> Ok(current)
    ["--allow-parent", ..rest] ->
      scope(rest, herdr.Scope(..current, allow_parent: True))
    ["--allow-agy-runtime", ..rest] ->
      scope(rest, herdr.Scope(..current, allow_agy_runtime: True))
    _ ->
      Error(herdr.Failure(
        "arguments",
        "unknown_scope_flag",
        herdr.NotDispatched,
      ))
  }
}

fn execute(arguments: List(String)) -> Result(json.Json, herdr.Failure) {
  case arguments {
    ["discover"] ->
      herdr.discover()
      |> result.map(fn(agents) {
        json.object([
          #("ok", json.bool(True)),
          #("agents", json.array(agents, herdr.agent_to_json)),
          #("authority", json.string("observed_herdr_metadata_only")),
          #("atomic_session_fence", json.bool(False)),
        ])
      })
    ["read", pane, session, ..flags] -> {
      use scope <- result.try(scope(flags, herdr.strict_scope()))
      herdr.read(herdr.Target(pane, session), scope)
      |> result.map(herdr.receipt_to_json)
    }
    ["prompt", pane, session, message, ..flags] -> {
      use scope <- result.try(scope(flags, herdr.strict_scope()))
      herdr.prompt(herdr.Target(pane, session), message, scope)
      |> result.map(herdr.receipt_to_json)
    }
    _ ->
      Error(herdr.Failure(
        "arguments",
        "usage: discover | read PANE SESSION [--allow-parent] [--allow-agy-runtime] | prompt PANE SESSION MESSAGE [--allow-parent] [--allow-agy-runtime]",
        herdr.NotDispatched,
      ))
  }
}

pub fn main() -> Nil {
  case execute(argv.load().arguments) {
    Ok(value) -> io.println(json.to_string(value))
    Error(failure) -> {
      io.println(json.to_string(herdr.failure_to_json(failure)))
      halt(1)
    }
  }
}

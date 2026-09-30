//// Canonical operational coordinator. Historical file journals remain evidence;
//// they are never a fallback source of live task or runtime authority.
import gleam/json
import gleam/result
import gleam/string
import session_store_cli
import simplifile
import uos_swarm/session_store as store
import uos_swarm/session_sync as sync

pub const database = "/home/an/NAS-setup/uos/var/coordination/tri-agent/coordinator.sqlite3"

fn existing_database(path: String) -> Result(Nil, String) {
  use info <- result.try(simplifile.link_info(path) |> result.map_error(string.inspect))
  case simplifile.file_info_type(info) == simplifile.File && info.size >= 512 {
    True -> Ok(Nil)
    False -> Error("canonical_coordinator_requires_existing_regular_database")
  }
}

pub fn run_at(path: String, arguments: List(String)) -> Result(String, String) {
  use _ <- result.try(existing_database(path))
  use verified <- result.try(store.open_existing(path) |> result.map_error(store.error_to_string))
  use _ <- result.try(store.close(verified) |> result.map_error(store.error_to_string))
  session_store_cli.run([path, ..arguments])
}

pub fn run(arguments: List(String)) -> Result(String, String) {
  run_at(database, arguments)
}

pub fn query_at(
  path: String,
  query: fn(sync.State, String, Int) -> Result(a, String),
) -> Result(a, String) {
  use _ <- result.try(existing_database(path))
  use opened <- result.try(store.open_existing(path) |> result.map_error(store.error_to_string))
  let outcome = store.observe(opened, fn(state, boot, now) {
    query(state, boot, now) |> result.map_error(store.RefusedError)
  })
  let closed = store.close(opened)
  use value <- result.try(outcome |> result.map_error(store.error_to_string))
  use _ <- result.try(closed |> result.map_error(store.error_to_string))
  Ok(value)
}

pub fn observe_at(
  path: String,
  query: fn(sync.State, String, Int) -> Result(json.Json, String),
) -> Result(String, String) {
  query_at(path, query) |> result.map(json.to_string)
}

pub fn observe(query: fn(sync.State, String, Int) -> Result(json.Json, String)) -> Result(String, String) {
  observe_at(database, query)
}

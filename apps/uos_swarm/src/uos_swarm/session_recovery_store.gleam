import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import uos_swarm/session_recovery as recovery
import uos_swarm/session_store as store

pub type Receipt {
  Receipt(database: String, digest: String)
}

@external(erlang, "session_store_ffi", "create_exclusive")
fn create_exclusive(path: String) -> Result(Nil, String)

fn require(condition: Bool, reason: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(reason)
  }
}

fn protected_ancestor(path: String, user_id: Int) -> Result(Nil, String) {
  use info <- result.try(
    simplifile.link_info(path) |> result.map_error(string.inspect),
  )
  require(
    simplifile.file_info_type(info) == simplifile.Directory
      && { info.user_id == user_id || info.user_id == 0 }
      && {
      int.bitwise_and(info.mode, 0o022) == 0
      || int.bitwise_and(info.mode, 0o1000) != 0
    },
    "candidate ancestor must be a trusted real directory with protected entries",
  )
}

fn validate_parent(directory: String) -> Result(Nil, String) {
  use _ <- result.try(require(
    string.byte_size(directory) <= 4096 && !string.contains(directory, "\u{0}"),
    "invalid candidate path",
  ))
  use components <- result.try(case string.split(directory, "/") {
    ["", ..components] -> Ok(components)
    _ -> Error("candidate path must be absolute")
  })
  use _ <- result.try(require(
    !list.is_empty(components)
      && list.length(components) <= 64
      && list.all(components, fn(component) {
      component != "" && component != "." && component != ".."
    }),
    "candidate path must be canonical and bounded",
  ))
  use process_info <- result.try(
    simplifile.file_info("/proc/self") |> result.map_error(string.inspect),
  )
  let user_id = process_info.user_id
  use _ <- result.try(protected_ancestor("/", user_id))
  let parents = components |> list.reverse |> list.drop(1) |> list.reverse
  use parent <- result.try(
    list.try_fold(parents, "/", fn(parent, component) {
      let path = case parent {
        "/" -> "/" <> component
        _ -> parent <> "/" <> component
      }
      use _ <- result.try(protected_ancestor(path, user_id))
      Ok(path)
    }),
  )
  use info <- result.try(
    simplifile.link_info(parent) |> result.map_error(string.inspect),
  )
  require(
    info.user_id == user_id
      && simplifile.file_info_permissions_octal(info) == 0o700,
    "candidate parent must be owned by this process user with mode 0700",
  )
}

pub fn stage(
  directory: String,
  candidate: recovery.Candidate,
) -> Result(Receipt, String) {
  use _ <- result.try(validate_parent(directory))
  use _ <- result.try(
    simplifile.create_directory(directory)
    |> result.map_error(fn(error) {
      "candidate requires a new directory: " <> string.inspect(error)
    }),
  )
  use _ <- result.try(
    simplifile.set_permissions_octal(directory, 0o700)
    |> result.map_error(string.inspect),
  )
  let database = directory <> "/coordinator.sqlite3"
  use _ <- result.try(create_exclusive(database))
  use opened <- result.try(
    store.open(database) |> result.map_error(store.error_to_string),
  )
  let outcome =
    store.quarantine(
      opened,
      json.to_string(recovery.to_json(candidate)),
      "recovery evidence only; no historical command or lease is activated; candidate digest "
        <> recovery.digest(candidate),
    )
  let closed = store.close(opened)
  use _ <- result.try(outcome |> result.map_error(store.error_to_string))
  use _ <- result.try(closed |> result.map_error(store.error_to_string))
  Ok(Receipt(database, recovery.digest(candidate)))
}

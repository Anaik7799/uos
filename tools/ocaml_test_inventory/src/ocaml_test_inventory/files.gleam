import gleam/list
import gleam/result
import gleam/string
import ocaml_test_inventory/inventory.{
  type Entry, type Finding, type ReadError, CannotRead, InvalidInventory,
  NotFound,
}
import simplifile

pub fn verify(root: String, entries: List(Entry)) -> List(Finding) {
  case
    string.starts_with(root, "/")
    && inventory.canonical_relative_path(string.drop_start(root, 1))
  {
    False -> [
      InvalidInventory("source root must be canonical absolute path, not /"),
    ]
    True ->
      inventory.verify_entries(entries, fn(path) {
        read_checked(root <> "/" <> path)
      })
  }
}

// Reject symlinks at every component. This is NOT descriptor-relative access:
// concurrent hostile renames between lstat and read remain outside this gate.
pub fn read_checked(absolute_path: String) -> Result(BitArray, ReadError) {
  case
    string.starts_with(absolute_path, "/")
    && inventory.canonical_relative_path(string.drop_start(absolute_path, 1))
  {
    False -> Error(CannotRead)
    True -> {
      use _ <- result.try(check_parts(
        "",
        string.split(string.drop_start(absolute_path, 1), "/"),
      ))
      simplifile.read_bits(absolute_path) |> result.map_error(read_error)
    }
  }
}

fn read_error(error: simplifile.FileError) -> ReadError {
  case error {
    simplifile.Enoent -> NotFound
    _ -> CannotRead
  }
}

fn check_parts(prefix: String, parts: List(String)) -> Result(Nil, ReadError) {
  case parts {
    [] -> Error(CannotRead)
    [head, ..tail] -> {
      let path = prefix <> "/" <> head
      use info <- result.try(
        simplifile.link_info(path) |> result.map_error(read_error),
      )
      case list.is_empty(tail), simplifile.file_info_type(info) {
        True, simplifile.File ->
          case info.size <= 16 * 1024 * 1024 {
            True -> Ok(Nil)
            False -> Error(CannotRead)
          }
        False, simplifile.Directory -> check_parts(path, tail)
        _, _ -> Error(CannotRead)
      }
    }
  }
}

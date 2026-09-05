pub type Entry {
  Entry(path: String, sha256: String)
}

pub type ReadError {
  NotFound
  CannotRead
}

pub type Finding {
  Changed(path: String)
  Missing(path: String)
  Unreadable(path: String)
  InvalidInventory(reason: String)
}

pub fn verify_entries(
  entries: List(Entry),
  read: fn(String) -> Result(BitArray, ReadError),
) -> List(Finding) {
  let invalid = validate(entries)
  case invalid {
    [] ->
      list.filter_map(entries, fn(entry) {
        case read(entry.path) {
          Error(NotFound) -> Ok(Missing(entry.path))
          Error(CannotRead) -> Ok(Unreadable(entry.path))
          Ok(bytes) ->
            case digest(bytes) == entry.sha256 {
              True -> Error(Nil)
              False -> Ok(Changed(entry.path))
            }
        }
      })
    _ -> invalid
  }
}

pub fn digest(bytes: BitArray) -> String {
  bytes
  |> crypto.hash(crypto.Sha256, _)
  |> bit_array.base16_encode
  |> string.lowercase
}

pub fn canonical_relative_path(path: String) -> Bool {
  !string.contains(path, "\\")
  && !string.contains(path, "\u{0}")
  && list.all(string.split(path, "/"), fn(segment) {
    segment != "" && segment != "." && segment != ".."
  })
}

pub fn validate(entries: List(Entry)) -> List(Finding) {
  let count = list.length(entries)
  case count == 0 || count > 100_000 {
    True -> [InvalidInventory("expected 1..100000 entries")]
    False -> {
      let #(_, errors) =
        list.fold(entries, #(set.new(), []), fn(acc, entry) {
          let #(seen, errors) = acc
          let error = case canonical_relative_path(entry.path) {
            False -> [
              InvalidInventory("noncanonical relative path: " <> entry.path),
            ]
            True ->
              case set.contains(seen, entry.path) {
                True -> [InvalidInventory("duplicate path: " <> entry.path)]
                False ->
                  case
                    string.length(entry.sha256) == 64
                    && list.all(string.to_graphemes(entry.sha256), fn(c) {
                      string.contains("0123456789abcdef", c)
                    })
                  {
                    True -> []
                    False -> [
                      InvalidInventory("invalid SHA256: " <> entry.path),
                    ]
                  }
              }
          }
          #(set.insert(seen, entry.path), list.append(errors, error))
        })
      errors
    }
  }
}

import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/set
import gleam/string

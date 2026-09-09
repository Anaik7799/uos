//// Bounded version-1 mesh wire primitives. Objects and null are not in the
//// grammar, so duplicate JSON object keys cannot acquire last-writer semantics.
//// This validates data shape; it authenticates neither a sender nor transport.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const max_bytes = 131_072

pub const max_depth = 12

pub const max_entries = 256

pub const max_string_bytes = 1024

pub const max_integer = 9_007_199_254_740_991

pub type WireError {
  ByteLimit
  DepthLimit
  CollectionLimit
  StringLimit
  IntegerLimit
  NonFinite
  InvalidShape
  InvalidIdentity
  DuplicateKey
  DuplicateDot
  NodeMismatch
}

pub type Value {
  Text(String)
  Integer(Int)
  Real(Float)
  Boolean(Bool)
  Array(List(Value))
}

/// Early collection check: visits at most max_entries + 1 list cells.
pub fn bounded_list(items: List(a)) -> Bool {
  bounded(items, max_entries)
}

fn bounded(items: List(a), left: Int) -> Bool {
  case items {
    [] -> True
    [_, ..rest] -> left > 0 && bounded(rest, left - 1)
  }
}

fn value_decoder() -> decode.Decoder(Value) {
  decode.one_of(decode.map(decode.int, Integer), [
    decode.map(decode.float, Real),
    decode.map(decode.string, Text),
    decode.map(decode.bool, Boolean),
    decode.map(decode.list(decode.recursive(value_decoder)), Array),
  ])
}

/// Scan bytes before the JSON parser allocates a recursive value. JSON itself
/// checks escapes, UTF-8, literals and exact syntax after this depth guard.
fn scan(
  bytes: BitArray,
  depth: Int,
  quoted: Bool,
  escaped: Bool,
) -> Result(Nil, WireError) {
  case bytes {
    <<>> ->
      case depth == 0 && !quoted {
        True -> Ok(Nil)
        False -> Error(InvalidShape)
      }
    <<c:8, rest:bits>> ->
      case quoted {
        True ->
          case escaped, c {
            True, _ -> scan(rest, depth, True, False)
            False, 92 -> scan(rest, depth, True, True)
            False, 34 -> scan(rest, depth, False, False)
            False, _ -> scan(rest, depth, True, False)
          }
        False ->
          case c {
            34 -> scan(rest, depth, True, False)
            91 ->
              case depth >= max_depth {
                True -> Error(DepthLimit)
                False -> scan(rest, depth + 1, False, False)
              }
            93 ->
              case depth <= 0 {
                True -> Error(InvalidShape)
                False -> scan(rest, depth - 1, False, False)
              }
            123 | 125 -> Error(InvalidShape)
            _ -> scan(rest, depth, False, False)
          }
      }
    _ -> Error(InvalidShape)
  }
}

pub fn validate(value: Value) -> Result(Nil, WireError) {
  validate_at(value, 0)
}

fn validate_at(value: Value, depth: Int) -> Result(Nil, WireError) {
  case value {
    Text(s) ->
      case string.byte_size(s) <= max_string_bytes {
        True -> Ok(Nil)
        False -> Error(StringLimit)
      }
    Integer(n) ->
      case n >= 0 && n <= max_integer {
        True -> Ok(Nil)
        False -> Error(IntegerLimit)
      }
    Real(f) ->
      case f >=. -1.7976931348623157e308 && f <=. 1.7976931348623157e308 {
        True -> Ok(Nil)
        False -> Error(NonFinite)
      }
    Boolean(_) -> Ok(Nil)
    Array(items) ->
      case depth >= max_depth, bounded_list(items) {
        True, _ -> Error(DepthLimit)
        _, False -> Error(CollectionLimit)
        False, True -> list.try_each(items, fn(v) { validate_at(v, depth + 1) })
      }
  }
}

pub fn parse(input: String) -> Result(Value, WireError) {
  use _ <- result.try(case string.byte_size(input) <= max_bytes {
    True -> Ok(Nil)
    False -> Error(ByteLimit)
  })
  use _ <- result.try(scan(bit_array.from_string(input), 0, False, False))
  use value <- result.try(
    json.parse(input, value_decoder())
    |> result.map_error(fn(_) { InvalidShape }),
  )
  use _ <- result.try(validate(value))
  Ok(value)
}

/// Diagnostic callers may render an already typed value without asserting wire
/// validity. Transport callers must use encode, which returns a typed refusal.
pub fn diagnostic_json(value: Value) -> json.Json {
  case value {
    Text(s) -> json.string(s)
    Integer(n) -> json.int(n)
    Real(f) -> json.float(f)
    Boolean(b) -> json.bool(b)
    Array(items) -> json.array(items, diagnostic_json)
  }
}

pub fn encode(value: Value) -> Result(String, WireError) {
  use _ <- result.try(validate(value))
  let bytes = value |> diagnostic_json |> json.to_string
  case string.byte_size(bytes) <= max_bytes {
    True -> Ok(bytes)
    False -> Error(ByteLimit)
  }
}

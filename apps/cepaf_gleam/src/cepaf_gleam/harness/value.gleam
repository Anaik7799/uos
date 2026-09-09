//// Lossless structural JSON adapter; no evaluation of stored strings.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option

pub type Value {
  Object(List(#(String, Value)))
  Array(List(Value))
  Text(String)
  Integer(Int)
  Number(Float)
  Boolean(Bool)
  Null
}

pub fn decoder() -> decode.Decoder(Value) {
  let child = decode.recursive(decoder)
  decode.one_of(decode.map(decode.string, Text), [
    decode.map(decode.int, Integer),
    decode.map(decode.float, Number),
    decode.map(decode.bool, Boolean),
    decode.map(decode.dict(decode.string, child), fn(x) {
      Object(dict.to_list(x))
    }),
    decode.map(decode.list(child), Array),
    decode.map(decode.optional(decode.string), fn(x) {
      case x {
        option.None -> Null
        option.Some(s) -> Text(s)
      }
    }),
  ])
}

pub fn encode(value: Value) -> json.Json {
  case value {
    Object(fields) ->
      json.object(list.map(fields, fn(p) { #(p.0, encode(p.1)) }))
    Array(values) -> json.array(values, encode)
    Text(s) -> json.string(s)
    Integer(n) -> json.int(n)
    Number(n) -> json.float(n)
    Boolean(b) -> json.bool(b)
    Null -> json.null()
  }
}

pub fn get(value: Value, key: String) -> Result(Value, String) {
  case value {
    Object(fields) ->
      case list.find(fields, fn(p) { p.0 == key }) {
        Ok(p) -> Ok(p.1)
        Error(_) -> Error("missing_field:" <> key)
      }
    _ -> Error("object_required")
  }
}

pub fn set(value: Value, key: String, replacement: Value) -> Value {
  case value {
    Object(fields) ->
      Object([#(key, replacement), ..list.filter(fields, fn(p) { p.0 != key })])
    _ -> value
  }
}

//// Bounded REST publication/query policy. Reachability is not subscription,
//// native-session, durability, or effect authority. No shared key is deleted.
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const backend = "zenoh_rest"
pub const endpoint = "http://nas-1.tail55d152.ts.net:8080"

@external(erlang, "zenoh_rest_ffi", "request")
fn request(method: String, key: String, body: String) -> Result(#(Int, String), String)

@external(erlang, "zenoh_rest_ffi", "encode_json")
fn encode_json(value: Dynamic) -> String

pub fn valid_key(key: String) -> Bool {
  bit_array.byte_size(bit_array.from_string(key)) <= 512
  && list.all(string.split(key, "/"), fn(p) { p != "" && p != "." && p != ".." })
  && list.all(string.to_graphemes(key), fn(c) {
    string.contains("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/_.-", c)
  })
}

pub fn valid_config(config: String) -> Bool {
  // Legacy callers use these empty/client selectors. Arbitrary endpoints and
  // native configuration are deliberately not silently ignored.
  config == "{}" || config == "{\"mode\": \"client\"}" || config == "{\"mode\":\"client\"}"
}

pub fn probe(config: String) -> Result(Nil, String) {
  case valid_config(config) {
    False -> Error("unsupported_zenoh_rest_config")
    True -> {
      use reply <- result.try(request("GET", "c3i/recovery/capability/reachability", ""))
      use body <- result.try(http_ok(reply))
      // Empty storage is valid reachability, not a successful query.
      json.parse(body, decode.list(sample_decoder()))
      |> result.map(fn(_) { Nil })
      |> result.map_error(fn(_) { "invalid_zenoh_rest_envelope" })
    }
  }
}

pub fn http_ok(reply: #(Int, String)) -> Result(String, String) {
  case reply {
    #(200, body) -> Ok(body)
    _ -> Error("zenoh_rest_http_failure")
  }
}

pub fn publication_ok(reply: #(Int, String)) -> Result(Nil, String) {
  case reply {
    #(200, _) | #(201, _) | #(204, _) -> Ok(Nil)
    _ -> Error("zenoh_rest_publication_failed")
  }
}

pub fn put(key: String, payload: String) -> Result(Nil, String) {
  // Coordinator envelopes must use the typed board publisher, never raw text.
  case valid_key(key) && key != "c3i/a2a"
    && !string.starts_with(key, "c3i/a2a/")
    && bit_array.byte_size(bit_array.from_string(payload)) <= 65536 {
    False -> Error("invalid_zenoh_key_or_payload_bound")
    True -> {
      use reply <- result.try(request("PUT", key, payload))
      publication_ok(reply)
    }
  }
}

pub fn get(key: String) -> Result(String, String) {
  case valid_key(key) {
    False -> Error("invalid_zenoh_key")
    True -> {
      use reply <- result.try(request("GET", key, ""))
      use body <- result.try(http_ok(reply))
      decode_reply(key, body)
    }
  }
}

type Sample {
  Sample(key: String, encoding: String, value: Dynamic)
}

fn sample_decoder() -> decode.Decoder(Sample) {
  use key <- decode.field("key", decode.string)
  use encoding <- decode.field("encoding", decode.string)
  use value <- decode.field("value", decode.dynamic)
  decode.success(Sample(key, encoding, value))
}

pub fn decode_reply(key: String, body: String) -> Result(String, String) {
  use samples <- result.try(
    json.parse(body, decode.list(sample_decoder()))
    |> result.map_error(fn(_) { "invalid_zenoh_rest_envelope" }),
  )
  case samples {
    [] -> Error("zenoh_no_reply")
    [sample] if sample.key == key -> {
      case sample.encoding {
        "text/plain" | "text/plain; charset=utf-8" ->
          decode.run(sample.value, decode.string)
          |> result.map_error(fn(_) { "invalid_zenoh_text_value" })
        "application/json" -> Ok(encode_json(sample.value))
        _ -> Error("unsupported_zenoh_encoding")
      }
    }
    [_] -> Error("zenoh_reply_key_mismatch")
    _ -> Error("ambiguous_zenoh_replies")
  }
}

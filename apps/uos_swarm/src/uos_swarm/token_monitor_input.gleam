import gleam/dynamic/decode
import gleam/json
import gleam/result
import uos_swarm/coord
import uos_swarm/token_monitor as monitor

@external(erlang, "token_monitor_json_ffi", "valid_object")
fn strict_object(text: String) -> Bool

fn usage() -> decode.Decoder(coord.Usage) {
  use a <- decode.field("agent", decode.string)
  use m <- decode.field("model", decode.string)
  use i <- decode.field("input_tokens", decode.int)
  use o <- decode.field("output_tokens", decode.int)
  use r <- decode.field("cache_read", decode.int)
  use w <- decode.field("cache_write", decode.int)
  use t <- decode.field("tool_uses", decode.int)
  use ms <- decode.field("wall_ms", decode.int)
  decode.success(coord.Usage(a, m, i, o, r, w, t, ms))
}

fn receipt() -> decode.Decoder(monitor.Receipt) {
  use p <- decode.field("provider", decode.string)
  use id <- decode.field("request_id", decode.string)
  use u <- decode.field("usage", decode.optional(usage()))
  use r <- decode.field("reasoning_tokens", decode.optional(decode.int))
  use c <- decode.field("estimated_nanodollars", decode.optional(decode.int))
  use f <- decode.field("failed", decode.bool)
  decode.success(monitor.Receipt(p, id, u, r, c, f))
}

pub fn parse(
  text: String,
) -> Result(#(monitor.Monitor, monitor.Policy), String) {
  use _ <- result.try(case strict_object(text) {
    True -> Ok(Nil)
    False -> Error("invalid_bounded_unique_key_json")
  })
  let decoder = {
    use schema <- decode.field("schema_version", decode.int)
    use rows <- decode.field("receipts", decode.list(receipt()))
    use max_t <- decode.field("max_tokens", decode.int)
    use max_c <- decode.field("max_calls", decode.int)
    decode.success(#(schema, rows, monitor.Policy(max_t, max_c)))
  }
  use value <- result.try(
    json.parse(text, decoder) |> result.replace_error("invalid_monitor_schema"),
  )
  use _ <- result.try(case value.0 == 1 {
    True -> Ok(Nil)
    False -> Error("unsupported_schema")
  })
  use m <- result.try(monitor.collect(value.1))
  use _ <- result.try(monitor.decide(m, value.2))
  Ok(#(m, value.2))
}

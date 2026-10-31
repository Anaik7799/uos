//// Provider-specific raw receipt interpretation. No prompts/results are emitted.
//// Claude CLI invocation usage is already aggregate; never add modelUsage.
//// Pi SDK uses disjoint uncached/read/write input categories.
//// DeepSeek chat prompt_tokens includes cache hits: subtract those before reuse.

import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import uos_swarm/coord
import uos_swarm/token_monitor as monitor

@external(erlang, "token_monitor_json_ffi", "valid_object")
fn strict_object(text: String) -> Bool

pub type Native {
  Native(
    input: Int,
    output: Int,
    read: Int,
    write: Int,
    reasoning: Option(Int),
    total: Option(Int),
    cost: Option(Float),
    failure_observed: Bool,
  )
}

fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}

fn claude() -> decode.Decoder(Native) {
  use n <- decode.field("usage", {
    use i <- decode.field("input_tokens", decode.int)
    use o <- decode.field("output_tokens", decode.int)
    use r <- decode.field("cache_read_input_tokens", decode.int)
    use w <- decode.field("cache_creation_input_tokens", decode.int)
    use t <- decode.optional_field(
      "total_tokens",
      None,
      decode.optional(decode.int),
    )
    use think <- decode.optional_field("output_tokens_details", None, {
      use n <- decode.optional_field(
        "thinking_tokens",
        None,
        decode.optional(decode.int),
      )
      decode.success(n)
    })
    decode.success(Native(i, o, r, w, think, t, None, False))
  })
  use c <- decode.optional_field(
    "total_cost_usd",
    None,
    decode.optional(number()),
  )
  use f <- decode.field("is_error", decode.bool)
  decode.success(Native(..n, cost: c, failure_observed: f))
}

fn pi() -> decode.Decoder(Native) {
  use aborted <- decode.field("settled", decode.at(["aborted"], decode.bool))
  use response <- decode.field("result", {
    use n <- decode.field("usage", {
      use i <- decode.field("input", decode.int)
      use o <- decode.field("output", decode.int)
      use r <- decode.field("cacheRead", decode.int)
      use w <- decode.field("cacheWrite", decode.int)
      use think <- decode.optional_field(
        "reasoning",
        None,
        decode.optional(decode.int),
      )
      use t <- decode.optional_field(
        "totalTokens",
        None,
        decode.optional(decode.int),
      )
      use c <- decode.optional_field("cost", None, {
        use n <- decode.field("total", decode.optional(number()))
        decode.success(n)
      })
      decode.success(Native(i, o, r, w, think, t, c, False))
    })
    use stop <- decode.field("stopReason", decode.string)
    decode.success(
      Native(..n, failure_observed: stop == "error" || stop == "aborted"),
    )
  })
  decode.success(
    Native(..response, failure_observed: aborted || response.failure_observed),
  )
}

fn deepseek() -> decode.Decoder(Native) {
  decode.at(["usage"], {
    use i <- decode.field("prompt_tokens", decode.int)
    use o <- decode.field("completion_tokens", decode.int)
    use r <- decode.field("prompt_cache_hit_tokens", decode.int)
    use miss <- decode.field("prompt_cache_miss_tokens", decode.int)
    use t <- decode.field("total_tokens", decode.int)
    use think <- decode.optional_field("completion_tokens_details", None, {
      use n <- decode.optional_field(
        "reasoning_tokens",
        None,
        decode.optional(decode.int),
      )
      decode.success(n)
    })
    // An invalid partition is represented by a negative category and refused below.
    let uncached = case i == r + miss {
      True -> miss
      False -> -1
    }
    decode.success(Native(uncached, o, r, 0, think, Some(t), None, False))
  })
}

pub fn parse(
  format: String,
  provider: String,
  id: String,
  agent: String,
  model: String,
  text: String,
) -> Result(monitor.Receipt, String) {
  use _ <- result.try(case strict_object(text) {
    True -> Ok(Nil)
    False -> Error("invalid_raw_receipt_json")
  })
  use decoder <- result.try(case format {
    "claude_cli" -> Ok(claude())
    "pi_sdk" -> Ok(pi())
    "deepseek_chat" -> Ok(deepseek())
    _ -> Error("unsupported_receipt_format")
  })
  use _ <- result.try(case format {
    "claude_cli" -> {
      use terminal <- result.try(
        json.parse(text, decode.at(["type"], decode.string))
        |> result.replace_error("missing_final_result_marker"),
      )
      use _ <- result.try(case terminal == "result" {
        True -> Ok(Nil)
        False -> Error("nonfinal_receipt")
      })
      use actual <- result.try(
        json.parse(text, decode.at(["session_id"], decode.string))
        |> result.replace_error("missing_native_invocation_id"),
      )
      case actual == id {
        True -> Ok(Nil)
        False -> Error("native_invocation_id_mismatch")
      }
    }
    "pi_sdk" -> {
      let final = {
        use starts <- decode.field("assistant_starts", decode.int)
        use tools <- decode.field("tool_executions", decode.int)
        use settled <- decode.field(
          "settled",
          decode.at(["type"], decode.string),
        )
        use stop <- decode.field(
          "result",
          decode.at(["stopReason"], decode.string),
        )
        decode.success(
          starts == 1
          && tools == 0
          && settled == "agent_settled"
          && list.contains(["stop", "length", "error", "aborted"], stop),
        )
      }
      case json.parse(text, final) {
        Ok(True) -> Ok(Nil)
        _ -> Error("nonfinal_or_multiresponse_pi_receipt")
      }
    }
    "deepseek_chat" -> {
      let final = {
        use actual <- decode.field("id", decode.string)
        use kind <- decode.field("object", decode.string)
        decode.success(actual == id && kind == "chat.completion")
      }
      case json.parse(text, final) {
        Ok(True) -> Ok(Nil)
        _ -> Error("native_invocation_id_or_kind_mismatch")
      }
    }
    _ -> Error("unsupported_receipt_format")
  })
  use n <- result.try(
    json.parse(text, decoder) |> result.replace_error("unknown_usage_schema"),
  )
  let u = coord.Usage(agent, model, n.input, n.output, n.read, n.write, 0, 0)
  use _ <- result.try(case n.total {
    None -> Ok(Nil)
    Some(t) ->
      case t == monitor.tokens(u) {
        True -> Ok(Nil)
        False -> Error("inconsistent_total")
      }
  })
  use cost <- result.try(case n.cost {
    None -> Ok(None)
    Some(c) ->
      case c >=. 0.0 && c <=. 1000.0 {
        True -> Ok(Some(float.round(c *. 1_000_000_000.0)))
        False -> Error("invalid_cost")
      }
  })
  let receipt =
    monitor.Receipt(
      provider,
      id,
      Some(u),
      n.reasoning,
      cost,
      n.failure_observed,
    )
  use _ <- result.try(monitor.collect([receipt]))
  Ok(receipt)
}

//// Bounded read adapters. Malformed inputs are counted, never returned as raw
//// log/message bodies. No collector acceptance is inferred from board storage.

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import uos_swarm/board
import uos_swarm/board_insights as insights

pub const max_bytes = 16_777_216

pub const max_line_bytes = 65_536

@external(erlang, "board_reader_ffi", "read_bounded")
pub fn read_file(path: String, limit: Int) -> Result(String, String)

@external(erlang, "board_reader_ffi", "unwrap_samples")
fn unwrap_samples(body: String) -> Result(List(String), String)

pub type Input(a) {
  Input(events: List(a), malformed_count: Int)
}

fn lines(text: String) -> Result(List(String), String) {
  case string.byte_size(text) > max_bytes {
    True -> Error("input exceeds 16 MiB")
    False -> {
      let rows =
        text
        |> string.split("\n")
        |> list.filter(fn(s) { string.trim(s) != "" })
      case list.length(rows) > 10_000 {
        True -> Error("input exceeds 10000 events")
        False -> Ok(rows)
      }
    }
  }
}

fn parse_rows(
  rows: List(String),
  parse: fn(String) -> Result(a, String),
) -> Input(a) {
  let #(events, bad) =
    list.fold(rows, #([], 0), fn(acc, row) {
      let parsed = case string.byte_size(row) > max_line_bytes {
        True -> Error("event exceeds 64 KiB")
        False -> parse(row)
      }
      case parsed {
        Ok(event) -> #([event, ..acc.0], acc.1)
        Error(_) -> #(acc.0, acc.1 + 1)
      }
    })
  Input(list.reverse(events), bad)
}

fn decode_message(row: String) -> Result(board.Message, String) {
  // board.decode's legacy fallback maps unknown kinds to Progress; this reader
  // refuses them before delegating so an invalid event cannot look like activity.
  use kind <- result.try(
    json.parse(row, string_field("kind"))
    |> result.replace_error("missing kind"),
  )
  use _ <- result.try(board.kind_from_label(kind))
  board.decode(row)
}

fn string_field(name: String) -> decode.Decoder(String) {
  use value <- decode.field(name, decode.string)
  decode.success(value)
}

pub fn from_jsonl(text: String) -> Result(Input(board.Message), String) {
  use rows <- result.try(lines(text))
  Ok(parse_rows(rows, decode_message))
}

/// Supports Zenoh REST values encoded as objects or JSON strings.
/// Does not use the legacy fetch path that silently skips malformed envelopes.
pub fn from_zenoh(text: String) -> Result(Input(board.Message), String) {
  case string.byte_size(text) > max_bytes {
    True -> Error("input exceeds 16 MiB")
    False -> {
      use rows <- result.try(unwrap_samples(text))
      Ok(parse_rows(rows, decode_message))
    }
  }
}

fn sample_decoder() -> decode.Decoder(insights.Sample) {
  use id <- decode.field("id", decode.string)
  use source <- decode.field("source_ref", decode.string)
  use hive <- decode.field("hive_id", decode.string)
  use tenant <- decode.field("tenant_id", decode.string)
  use trace <- decode.field("trace_id", decode.string)
  use span <- decode.field("span_id", decode.string)
  use message <- decode.optional_field(
    "message_id",
    option.None,
    decode.optional(decode.string),
  )
  use candidate <- decode.optional_field(
    "candidate_ref",
    option.None,
    decode.optional(decode.string),
  )
  use service <- decode.field("service", decode.string)
  use observed <- decode.field("observed_us", decode.int)
  use signal <- decode.field("signal", decode.string)
  use severity <- decode.field("severity", decode.string)
  decode.success(
    insights.Sample(
      id,
      source,
      hive,
      tenant,
      trace,
      span,
      message,
      candidate,
      service,
      observed,
      case signal {
        "structured_log" -> insights.StructuredLog
        "span" -> insights.Span
        "collector_accepted" -> insights.CollectorAccepted
        "backend_visible" -> insights.BackendVisible
        _ -> insights.StructuredLog
      },
      case severity {
        "info" -> insights.Info
        "warning" -> insights.Warning
        "error" -> insights.ErrorSeverity
        _ -> insights.UnknownSeverity
      },
    ),
  )
}

fn decode_sample(row: String) -> Result(insights.Sample, String) {
  use signal <- result.try(
    json.parse(row, string_field("signal"))
    |> result.replace_error("missing signal"),
  )
  case
    list.contains(
      ["structured_log", "span", "collector_accepted", "backend_visible"],
      signal,
    )
  {
    False -> Error("unsupported signal")
    True ->
      json.parse(row, sample_decoder())
      |> result.replace_error("malformed telemetry observation")
  }
}

pub fn telemetry_jsonl(text: String) -> Result(Input(insights.Sample), String) {
  use rows <- result.try(lines(text))
  Ok(parse_rows(rows, decode_sample))
}

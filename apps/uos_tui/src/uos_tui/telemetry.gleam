//// C3I telemetry spans: W3C trace context identifiers and microsecond
//// UTC ISO 8601 timestamps for the uos_tui fractal observability contract.
////
//// Reference: OpenTelemetry span model (trace_id/span_id/parent_span_id),
//// projected through pure integer civil-date arithmetic (Howard Hinnant's
//// `civil_from_days` algorithm) so no host clock or external library is
//// required to render `ts`/`ts_end` fields.
////
//// STAMP id: SC-TUI-W06-001

import gleam/bit_array
import gleam/int
import gleam/json.{type Json}
import gleam/option.{type Option, None, Some}
import gleam/string

/// One C3I telemetry span, carrying W3C trace context and a fractal layer.
pub type Span {
  Span(
    trace_id: String,
    span_id: String,
    parent_span_id: Option(String),
    name: String,
    start_us: Int,
    end_us: Int,
    fractal_layer: Int,
    attributes: List(#(String, String)),
  )
}

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(n: Int) -> BitArray

/// Fallback non-zero 32-hex-digit id, used only if random generation
/// bottoms out at an all-zero value repeatedly (astronomically unlikely).
const trace_fallback = "6f00000000000000000000000000001"

/// Fallback non-zero 16-hex-digit id, same rationale as `trace_fallback`.
const span_fallback = "6f00000000000001"

fn random_hex(bytes: Int) -> String {
  strong_rand_bytes(bytes)
  |> bit_array.base16_encode
  |> string.lowercase
}

fn is_all_zero_hex(s: String) -> Bool {
  s
  |> string.to_graphemes
  |> non_zero_grapheme
  |> option.is_none
}

fn non_zero_grapheme(graphemes: List(String)) -> Option(String) {
  case graphemes {
    [] -> None
    [g, ..rest] ->
      case g {
        "0" -> non_zero_grapheme(rest)
        _ -> Some(g)
      }
  }
}

fn generate_non_zero_hex(
  bytes: Int,
  attempts: Int,
  fallback: String,
) -> String {
  case attempts <= 0 {
    True -> fallback
    False -> {
      let candidate = random_hex(bytes)
      case is_all_zero_hex(candidate) {
        True -> generate_non_zero_hex(bytes, attempts - 1, fallback)
        False -> candidate
      }
    }
  }
}

/// A fresh 32-lowercase-hex-digit W3C trace id (never all zeros).
pub fn new_trace_id() -> String {
  generate_non_zero_hex(16, 8, trace_fallback)
}

/// A fresh 16-lowercase-hex-digit W3C span id (never all zeros).
pub fn new_span_id() -> String {
  generate_non_zero_hex(8, 8, span_fallback)
}

fn is_hex_grapheme(g: String) -> Bool {
  case g {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    "a" | "b" | "c" | "d" | "e" | "f" -> True
    _ -> False
  }
}

fn all_hex(graphemes: List(String)) -> Bool {
  case graphemes {
    [] -> True
    [g, ..rest] ->
      case is_hex_grapheme(g) {
        True -> all_hex(rest)
        False -> False
      }
  }
}

/// True when `s` has exactly `len` lowercase hex graphemes and is not
/// the all-zero id.
pub fn is_hex_id(s: String, len: Int) -> Bool {
  let graphemes = string.to_graphemes(s)
  case list_length(graphemes) == len {
    True ->
      case all_hex(graphemes) {
        True -> !is_all_zero_hex(s)
        False -> False
      }
    False -> False
  }
}

fn list_length(xs: List(a)) -> Int {
  fold_length(xs, 0)
}

fn fold_length(xs: List(a), acc: Int) -> Int {
  case xs {
    [] -> acc
    [_, ..rest] -> fold_length(rest, acc + 1)
  }
}

/// Floor division, correct for negative dividends (unlike Gleam's
/// truncating `/`).
fn floor_div(a: Int, b: Int) -> Int {
  let q = a / b
  let r = a - q * b
  case r != 0 && { r < 0 } != { b < 0 } {
    True -> q - 1
    False -> q
  }
}

fn floor_mod(a: Int, b: Int) -> Int {
  a - floor_div(a, b) * b
}

type CivilDate {
  CivilDate(year: Int, month: Int, day: Int)
}

/// Howard Hinnant's `civil_from_days`: days since 1970-01-01 -> (y, m, d),
/// valid across the proleptic Gregorian calendar including negative days.
fn civil_from_days(z: Int) -> CivilDate {
  let z = z + 719_468
  let era = floor_div(z, 146_097)
  let doe = z - era * 146_097
  let yoe = { doe - doe / 1460 + doe / 36_524 - doe / 146_096 } / 365
  let y = yoe + era * 400
  let doy = doe - { 365 * yoe + yoe / 4 - yoe / 100 }
  let mp = { 5 * doy + 2 } / 153
  let d = doy - { 153 * mp + 2 } / 5 + 1
  let m = case mp < 10 {
    True -> mp + 3
    False -> mp - 9
  }
  let year = case m <= 2 {
    True -> y + 1
    False -> y
  }
  CivilDate(year, m, d)
}

fn pad2(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}

fn pad4(n: Int) -> String {
  let s = int.to_string(n)
  case list_length(string.to_graphemes(s)) {
    1 -> "000" <> s
    2 -> "00" <> s
    3 -> "0" <> s
    _ -> s
  }
}

fn pad6(n: Int) -> String {
  let s = int.to_string(n)
  let len = list_length(string.to_graphemes(s))
  let zeros = int.max(6 - len, 0)
  repeat_zero(zeros) <> s
}

fn repeat_zero(n: Int) -> String {
  case n <= 0 {
    True -> ""
    False -> "0" <> repeat_zero(n - 1)
  }
}

const us_per_day = 86_400_000_000

/// Render unix microseconds as `YYYY-MM-DDTHH:MM:SS.ffffffZ`, using pure
/// integer civil-from-days arithmetic. Valid for negative microseconds.
pub fn iso8601_us(unix_us: Int) -> String {
  let days = floor_div(unix_us, us_per_day)
  let us_of_day = floor_mod(unix_us, us_per_day)
  let civil = civil_from_days(days)
  let hh = us_of_day / 3_600_000_000
  let mm = { us_of_day % 3_600_000_000 } / 60_000_000
  let ss = { us_of_day % 60_000_000 } / 1_000_000
  let frac = us_of_day % 1_000_000
  pad4(civil.year)
  <> "-"
  <> pad2(civil.month)
  <> "-"
  <> pad2(civil.day)
  <> "T"
  <> pad2(hh)
  <> ":"
  <> pad2(mm)
  <> ":"
  <> pad2(ss)
  <> "."
  <> pad6(frac)
  <> "Z"
}

/// Render a span as a C3I telemetry JSON object.
pub fn to_c3i_json(span: Span) -> Json {
  let parent = case span.parent_span_id {
    None -> json.null()
    Some(id) -> json.string(id)
  }
  json.object([
    #("trace_id", json.string(span.trace_id)),
    #("span_id", json.string(span.span_id)),
    #("parent_span_id", parent),
    #("name", json.string(span.name)),
    #("ts", json.string(iso8601_us(span.start_us))),
    #("ts_end", json.string(iso8601_us(span.end_us))),
    #("duration_us", json.int(span.end_us - span.start_us)),
    #("fractal_layer", json.string("L" <> int.to_string(span.fractal_layer))),
    #(
      "attributes",
      json.object(
        span.attributes
        |> list_map(fn(pair) { #(pair.0, json.string(pair.1)) }),
      ),
    ),
  ])
}

fn list_map(xs: List(a), f: fn(a) -> b) -> List(b) {
  case xs {
    [] -> []
    [x, ..rest] -> [f(x), ..list_map(rest, f)]
  }
}

/// Structural + range validation for a span. Never panics.
pub fn validate(span: Span) -> Result(Nil, String) {
  case is_hex_id(span.trace_id, 32) {
    False -> Error("invalid trace_id")
    True ->
      case is_hex_id(span.span_id, 16) {
        False -> Error("invalid span_id")
        True ->
          case span.end_us >= span.start_us {
            False -> Error("end_us before start_us")
            True ->
              case span.fractal_layer >= 0 && span.fractal_layer <= 9 {
                False -> Error("fractal_layer out of range")
                True ->
                  case string.is_empty(span.name) {
                    True -> Error("name is empty")
                    False -> Ok(Nil)
                  }
              }
          }
      }
  }
}

/// Build a `tui.frame` span at fractal layer 3, carrying `frame_count`.
pub fn frame_span(
  trace_id: String,
  frame_count: Int,
  start_us: Int,
  end_us: Int,
) -> Span {
  Span(
    trace_id: trace_id,
    span_id: new_span_id(),
    parent_span_id: None,
    name: "tui.frame",
    start_us: start_us,
    end_us: end_us,
    fractal_layer: 3,
    attributes: [#("frame_count", int.to_string(frame_count))],
  )
}

/// Build a child span sharing `parent`'s trace id, with a new span id.
pub fn child(parent: Span, name: String, start_us: Int, end_us: Int) -> Span {
  Span(
    trace_id: parent.trace_id,
    span_id: new_span_id(),
    parent_span_id: Some(parent.span_id),
    name: name,
    start_us: start_us,
    end_us: end_us,
    fractal_layer: parent.fractal_layer,
    attributes: [],
  )
}

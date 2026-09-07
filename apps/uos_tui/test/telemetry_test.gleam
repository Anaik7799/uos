//// Tests for uos_tui/telemetry: W3C trace context ids and microsecond
//// UTC ISO 8601 rendering (CHK-16-OTEL).
////
//// STAMP id: SC-TUI-W06-001

import gleam/json
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import prng
import uos_tui/telemetry.{Span}

pub fn iso8601_epoch_test() {
  telemetry.iso8601_us(0)
  |> should.equal("1970-01-01T00:00:00.000000Z")
}

pub fn iso8601_known_instant_test() {
  telemetry.iso8601_us(1_757_203_416_000_000)
  |> should.equal("2025-09-07T00:03:36.000000Z")
}

pub fn iso8601_negative_epoch_test() {
  // -1 microsecond is the last microsecond of 1969-12-31.
  telemetry.iso8601_us(-1)
  |> should.equal("1969-12-31T23:59:59.999999Z")
}

pub fn iso8601_leap_day_test() {
  // 2024-02-29T00:00:00Z, precomputed unix seconds.
  telemetry.iso8601_us(1_709_164_800_000_000)
  |> should.equal("2024-02-29T00:00:00.000000Z")
}

pub fn iso8601_far_negative_test() {
  // One full day before epoch.
  telemetry.iso8601_us(-86_400_000_000)
  |> should.equal("1969-12-31T00:00:00.000000Z")
}

pub fn trace_id_shape_test() {
  let id = telemetry.new_trace_id()
  telemetry.is_hex_id(id, 32)
  |> should.be_true
}

pub fn span_id_shape_test() {
  let id = telemetry.new_span_id()
  telemetry.is_hex_id(id, 16)
  |> should.be_true
}

pub fn is_hex_id_rejects_wrong_length_test() {
  telemetry.is_hex_id("abcd", 32)
  |> should.be_false
}

pub fn is_hex_id_rejects_all_zero_test() {
  telemetry.is_hex_id(string_repeat("0", 32), 32)
  |> should.be_false
}

fn string_repeat(s: String, n: Int) -> String {
  case n <= 0 {
    True -> ""
    False -> s <> string_repeat(s, n - 1)
  }
}

pub fn validate_rejects_bad_trace_id_test() {
  let span = Span("bad", telemetry.new_span_id(), None, "x", 0, 1, 3, [])
  telemetry.validate(span)
  |> should.be_error
}

pub fn validate_rejects_negative_duration_test() {
  let span =
    Span(
      telemetry.new_trace_id(),
      telemetry.new_span_id(),
      None,
      "x",
      10,
      5,
      3,
      [],
    )
  telemetry.validate(span)
  |> should.be_error
}

pub fn validate_rejects_layer_out_of_range_test() {
  let span =
    Span(
      telemetry.new_trace_id(),
      telemetry.new_span_id(),
      None,
      "x",
      0,
      1,
      10,
      [],
    )
  telemetry.validate(span)
  |> should.be_error
}

pub fn validate_rejects_empty_name_test() {
  let span =
    Span(
      telemetry.new_trace_id(),
      telemetry.new_span_id(),
      None,
      "",
      0,
      1,
      3,
      [],
    )
  telemetry.validate(span)
  |> should.be_error
}

pub fn validate_accepts_well_formed_span_test() {
  let span = telemetry.frame_span(telemetry.new_trace_id(), 7, 0, 1000)
  telemetry.validate(span)
  |> should.be_ok
}

pub fn frame_span_shape_test() {
  let span = telemetry.frame_span(telemetry.new_trace_id(), 7, 0, 1000)
  span.name
  |> should.equal("tui.frame")
  span.fractal_layer
  |> should.equal(3)
  span.parent_span_id
  |> should.equal(None)
}

pub fn child_keeps_trace_id_and_sets_parent_test() {
  let parent = telemetry.frame_span(telemetry.new_trace_id(), 1, 0, 100)
  let kid = telemetry.child(parent, "tui.render", 0, 50)
  kid.trace_id
  |> should.equal(parent.trace_id)
  kid.parent_span_id
  |> should.equal(Some(parent.span_id))
  kid.span_id
  |> should.not_equal(parent.span_id)
}

pub fn to_c3i_json_contains_z_and_layer_test() {
  let span = telemetry.frame_span(telemetry.new_trace_id(), 3, 0, 1000)
  let rendered = telemetry.to_c3i_json(span) |> json.to_string
  string.contains(rendered, "Z\"")
  |> should.be_true
  string.contains(rendered, "L3")
  |> should.be_true
}

pub fn property_id_lengths_over_samples_test() {
  prng.seeds(200)
  |> check_ids
}

fn check_ids(seeds: List(prng.Seed)) -> Nil {
  case seeds {
    [] -> Nil
    [_, ..rest] -> {
      let trace = telemetry.new_trace_id()
      let span = telemetry.new_span_id()
      telemetry.is_hex_id(trace, 32)
      |> should.be_true
      telemetry.is_hex_id(span, 16)
      |> should.be_true
      check_ids(rest)
    }
  }
}

pub fn fuzz_is_hex_id_never_crashes_test() {
  fuzz_run(prng.seeds(50))
}

fn fuzz_run(seeds: List(prng.Seed)) -> Nil {
  case seeds {
    [] -> Nil
    [seed, ..rest] -> {
      let #(len, seed2) = prng.int_between(seed, 0, 40)
      let #(text, _) = prng.text(seed2, len)
      // Must not crash regardless of input shape; result is a plain Bool.
      let _ = telemetry.is_hex_id(text, len)
      fuzz_run(rest)
    }
  }
}

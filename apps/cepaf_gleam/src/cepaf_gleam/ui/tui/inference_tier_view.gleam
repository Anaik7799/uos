// STAMP: SC-GLM-UI-001, SC-COG-001
// TUI ANSI view for inference tier dashboard.

import cepaf_gleam/ui/lustre/inference_tier.{
  type InferenceTierModel, type TierStatus, CircuitClosed, CircuitHalfOpen,
  CircuitOpen,
}
import gleam/list
import gleam/string

pub fn render(model: InferenceTierModel) -> String {
  let header =
    "\u{001b}[1;36m▌ Inference Tier Dashboard\u{001b}[0m"
    <> "  Active: \u{001b}[1;32m"
    <> inference_tier.active_tier_name(model)
    <> "\u{001b}[0m"
    <> case model.hedged_mode {
      True -> " [HEDGED]"
      False -> " [SEQUENTIAL]"
    }

  let table_header =
    "\u{001b}[90m  Tier  Model                    Latency  Circuit       Req    Fail\u{001b}[0m"

  let rows =
    list.map(model.tiers, fn(t) { render_tier_row(t, model.active_tier) })
    |> string.join("\n")

  let cache_line =
    "  Cache hit rate: "
    <> float_to_pct(model.cache_hit_rate)
    <> " | Total requests: "
    <> int_str(model.total_requests)

  string.join([header, "", table_header, rows, "", cache_line], "\n")
}

fn render_tier_row(t: TierStatus, active: Int) -> String {
  let marker = case t.tier == active {
    True -> "\u{001b}[1;32m→\u{001b}[0m"
    False -> " "
  }

  let circuit_color = case t.circuit {
    CircuitClosed -> "\u{001b}[32m"
    CircuitOpen(_) -> "\u{001b}[31m"
    CircuitHalfOpen -> "\u{001b}[33m"
  }

  marker
  <> " T"
  <> int_str(t.tier)
  <> "  "
  <> pad_right(t.name, 24)
  <> pad_right(int_str(t.latency_ms) <> "ms", 9)
  <> circuit_color
  <> pad_right(inference_tier.circuit_state_label(t.circuit), 14)
  <> "\u{001b}[0m"
  <> pad_right(int_str(t.requests_total), 7)
  <> int_str(t.failures_total)
}

fn pad_right(s: String, width: Int) -> String {
  let len = string.length(s)
  case len >= width {
    True -> s
    False -> s <> string.repeat(" ", width - len)
  }
}

fn float_to_pct(f: Float) -> String {
  let pct = f *. 100.0
  int_str(float_to_int(pct)) <> "%"
}

@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String

@external(erlang, "erlang", "trunc")
fn float_to_int(f: Float) -> Int

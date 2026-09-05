// STAMP: SC-GLM-UI-001, SC-COG-001
// TUI ANSI view for PipelineTracer.

import cepaf_gleam/ui/lustre/pipeline_tracer.{
  type PipelineTrace, type PipelineTracerModel, type StageEvent,
}
import gleam/list
import gleam/string

pub fn render(model: PipelineTracerModel) -> String {
  let header = "\u{001b}[1;36m▌ Pipeline Tracer\u{001b}[0m"
  let summary_line =
    "  Total: "
    <> int_str(model.summary.total_intents)
    <> " | Avg: "
    <> int_str(model.summary.avg_latency_ms)
    <> "ms | P50: "
    <> int_str(model.summary.p50_ms)
    <> "ms | P95: "
    <> int_str(model.summary.p95_ms)
    <> "ms | P99: "
    <> int_str(model.summary.p99_ms)
    <> "ms"

  let traces =
    list.map(model.traces, render_trace)
    |> string.join("\n")

  string.join([header, summary_line, "", traces], "\n")
}

fn render_trace(t: PipelineTrace) -> String {
  let status_color = case t.status {
    "ok" -> "\u{001b}[32m"
    "error" -> "\u{001b}[31m"
    _ -> "\u{001b}[33m"
  }

  let waterfall =
    list.map(t.stages, render_stage)
    |> string.join(" > ")

  "  "
  <> status_color
  <> t.status
  <> "\u{001b}[0m "
  <> t.model_used
  <> " ["
  <> int_str(t.total_ms)
  <> "ms] T:"
  <> int_str(t.tiers_tried)
  <> " S:"
  <> int_str(t.tiers_skipped)
  <> "\n    "
  <> waterfall
}

fn render_stage(s: StageEvent) -> String {
  let color = case s.elapsed_ms > 2000 {
    True -> "\u{001b}[31m"
    False ->
      case s.elapsed_ms > 500 {
        True -> "\u{001b}[33m"
        False -> "\u{001b}[32m"
      }
  }
  color <> s.name <> "(" <> int_str(s.elapsed_ms) <> "ms)\u{001b}[0m"
}

@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String

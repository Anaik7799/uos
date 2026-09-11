//// =============================================================================
//// [C3I-SIL6-MSTS] UOS CORTEX PIPELINE TRACER
//// =============================================================================
//// <uos-module>
////   <identity>
////     <module>cepaf_gleam/cortex/pipeline_tracer</module>
////     <authority>UOS-CANONICAL-AGENT-POLICY</authority>
////   </identity>
////   <fractal-topology>
////     <layer>L4_SYSTEM</layer>
////     <topology>Zero-Write Hot-Path Microsecond Timing Collector</topology>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-COG-001, SC-XHOLON-001, SC-MUDA-001</stamp-controls>
////   </compliance>
//// </uos-module>
//// =============================================================================

import cepaf_gleam/cortex/cortex_types.{type PipelineTrace, PipelineTrace, TraceStage}
import gleam/int
import gleam/list
import gleam/string

pub fn new_trace(id: String, source: String, started_at_ms: Int) -> PipelineTrace {
  PipelineTrace(
    id: id,
    source: source,
    started_at_ms: started_at_ms,
    stages: [],
    classification: "pending",
    total_ms: 0,
  )
}

pub fn add_stage(
  trace: PipelineTrace,
  name: String,
  detail: String,
  status: String,
  current_now_ms: Int,
) -> PipelineTrace {
  let elapsed = current_now_ms - trace.started_at_ms
  let stage = TraceStage(name: name, detail: detail, status: status, elapsed_ms: elapsed)
  PipelineTrace(
    ..trace,
    stages: list.append(trace.stages, [stage]),
    total_ms: elapsed,
  )
}

pub fn set_classification(trace: PipelineTrace, classification: String) -> PipelineTrace {
  PipelineTrace(..trace, classification: classification)
}

/// Format the compact footer per SC-COG-001:
/// "Pipeline: recv(0ms) > class(1ms) > ack(2ms) > infer(1200ms) > delivered(1400ms)"
pub fn format_footer(trace: PipelineTrace) -> String {
  let formatted_stages =
    list.map(trace.stages, fn(st) {
      st.name <> "(" <> int.to_string(st.elapsed_ms) <> "ms)"
    })
    |> string.join(" > ")

  "Pipeline: " <> formatted_stages
}

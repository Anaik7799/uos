//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ui/lustre/pipeline_tracer</module></identity>
////   <fractal-topology><layer>L1_ATOMIC_DEBUG</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-XHOLON-001, SC-COG-001</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre page: PipelineTracer live view — 7-stage waterfall + TransactionSummary.
//// STAMP: SC-GLM-UI-001 (Triple-Interface), SC-COG-001, SC-XHOLON-001

import gleam/list
import gleam/option.{type Option, None, Some}

pub type PipelineStage {
  Received
  Classified
  AckSent
  InferenceStarted
  RagEnriched
  InferenceComplete
  Delivered
}

pub type StageEvent {
  StageEvent(name: String, elapsed_ms: Int, status: String)
}

pub type PipelineTrace {
  PipelineTrace(
    intent_id: String,
    source: String,
    model_used: String,
    stages: List(StageEvent),
    total_ms: Int,
    tiers_tried: Int,
    tiers_skipped: Int,
    status: String,
  )
}

pub type PipelineSummary {
  PipelineSummary(
    total_intents: Int,
    avg_latency_ms: Int,
    p50_ms: Int,
    p95_ms: Int,
    p99_ms: Int,
    failure_rate: Float,
    cache_hits: Int,
  )
}

pub type PipelineTracerModel {
  PipelineTracerModel(
    traces: List(PipelineTrace),
    summary: PipelineSummary,
    selected_trace: Option(String),
    loading: Bool,
    error: Option(String),
  )
}

pub type PipelineTracerMsg {
  TracesLoaded(List(PipelineTrace))
  SummaryUpdated(PipelineSummary)
  SelectTrace(String)
  RefreshTraces
  ErrorReceived(String)
}

pub fn init() -> PipelineTracerModel {
  PipelineTracerModel(
    traces: [],
    summary: PipelineSummary(0, 0, 0, 0, 0, 0.0, 0),
    selected_trace: None,
    loading: False,
    error: None,
  )
}

pub fn update(
  model: PipelineTracerModel,
  msg: PipelineTracerMsg,
) -> PipelineTracerModel {
  case msg {
    TracesLoaded(traces) ->
      PipelineTracerModel(..model, traces: traces, loading: False)
    SummaryUpdated(summary) ->
      PipelineTracerModel(..model, summary: summary)
    SelectTrace(id) ->
      PipelineTracerModel(..model, selected_trace: Some(id))
    RefreshTraces ->
      PipelineTracerModel(..model, loading: True)
    ErrorReceived(e) ->
      PipelineTracerModel(..model, error: Some(e), loading: False)
  }
}

pub fn stage_name(stage: PipelineStage) -> String {
  case stage {
    Received -> "received"
    Classified -> "classified"
    AckSent -> "ack_sent"
    InferenceStarted -> "inference_started"
    RagEnriched -> "rag"
    InferenceComplete -> "inference_complete"
    Delivered -> "delivered"
  }
}

pub fn bottleneck_stage(trace: PipelineTrace) -> Option(StageEvent) {
  case trace.stages {
    [] -> None
    stages -> {
      let max = list.fold(stages, StageEvent("", 0, ""), fn(acc, s) {
        case s.elapsed_ms > acc.elapsed_ms {
          True -> s
          False -> acc
        }
      })
      Some(max)
    }
  }
}

pub fn is_slow(trace: PipelineTrace) -> Bool {
  trace.total_ms > 5000
}

pub fn trace_count(model: PipelineTracerModel) -> Int {
  list.length(model.traces)
}

// =============================================================================
// NIF-backed data loading (SC-WIRE-001: real ops data)
// =============================================================================

import cepaf_gleam/c3i/nif
import gleam/dynamic/decode
import gleam/json

/// Load real pipeline traces from NIF → Rust → TransactionSummary
pub fn load_from_nif(limit: Int) -> PipelineTracerModel {
  let raw = nif.trace_recent(limit)
  let decoder = {
    use count <- decode.field("count", decode.int)
    decode.success(count)
  }
  let count = case json.parse(raw, decoder) {
    Ok(c) -> c
    Error(_) -> 0
  }
  let model = init()
  PipelineTracerModel(..model, summary: PipelineSummary(count, 0, 0, 0, 0, 0.0, 0), loading: False)
}

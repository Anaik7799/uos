// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-COG-001
// Wisp REST endpoint for PipelineTracer.

import cepaf_gleam/ui/lustre/pipeline_tracer.{
  type PipelineSummary, type PipelineTrace, type StageEvent,
}
import gleam/json
import gleam/list

pub fn traces_json(traces: List(PipelineTrace)) -> json.Json {
  json.object([
    #("traces", json.array(traces, trace_json)),
    #("count", json.int(list.length(traces))),
  ])
}

pub fn trace_json(t: PipelineTrace) -> json.Json {
  json.object([
    #("intent_id", json.string(t.intent_id)),
    #("source", json.string(t.source)),
    #("model_used", json.string(t.model_used)),
    #("total_ms", json.int(t.total_ms)),
    #("tiers_tried", json.int(t.tiers_tried)),
    #("tiers_skipped", json.int(t.tiers_skipped)),
    #("status", json.string(t.status)),
    #("stages", json.array(t.stages, stage_json)),
  ])
}

fn stage_json(s: StageEvent) -> json.Json {
  json.object([
    #("name", json.string(s.name)),
    #("elapsed_ms", json.int(s.elapsed_ms)),
    #("status", json.string(s.status)),
  ])
}

pub fn summary_json(s: PipelineSummary) -> json.Json {
  json.object([
    #("total_intents", json.int(s.total_intents)),
    #("avg_latency_ms", json.int(s.avg_latency_ms)),
    #("p50_ms", json.int(s.p50_ms)),
    #("p95_ms", json.int(s.p95_ms)),
    #("p99_ms", json.int(s.p99_ms)),
    #("failure_rate", json.float(s.failure_rate)),
    #("cache_hits", json.int(s.cache_hits)),
  ])
}

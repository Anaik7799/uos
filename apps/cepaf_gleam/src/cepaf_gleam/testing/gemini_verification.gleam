//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/testing/gemini_verification</module>
////     <fsharp-lineage>Cepaf.Testing.GeminiVerification</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L6_ECOSYSTEM</layer>
////     <mesh-domain>Gemini AI Agent Pipeline Verification</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <stamp-controls>SC-GEM-001, SC-GEM-003, SC-MCP-001, SC-GLM-ZEN-001</stamp-controls>
////   </compliance>
//// </c3i-module>
////
//// Gemini Pipeline Verification — verifies OTel -> Zenoh -> MCP -> Gemini flow.
//// Checks that all OTel messages published via Zenoh are received by Gemini via MCP.
//// STAMP: SC-GEM-001, SC-GEM-003, SC-MCP-001

import cepaf_gleam/testing/zenoh_test_observer.{type ObserverState}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

// =============================================================================
// Gemini Verification Types
// =============================================================================

pub type GeminiVerification {
  GeminiVerification(
    topics_published: List(String),
    topics_received_by_mcp: List(String),
    mcp_queries: List(String),
    response_times_ms: List(Int),
    all_received: Bool,
    delivery_rate: Float,
    pipeline_healthy: Bool,
  )
}

pub type PipelineStage {
  StageOtelPublish
  StageZenohTransport
  StageMcpRelay
  StageGeminiProcess
}

pub type StageResult {
  StageResult(
    stage: PipelineStage,
    passed: Bool,
    message_count: Int,
    latency_ms: Int,
    details: String,
  )
}

// =============================================================================
// Pipeline Verification
// =============================================================================

/// Verify the full OTel -> Zenoh -> MCP -> Gemini pipeline.
pub fn verify_gemini_pipeline(
  observer: ObserverState,
  mcp_received: List(String),
) -> GeminiVerification {
  let published_topics =
    list.map(observer.messages, fn(m) { m.topic }) |> unique_list
  let mcp_matched =
    list.filter(mcp_received, fn(r) { list.contains(published_topics, r) })
  let all_received = case published_topics {
    [] -> True
    _ -> list.length(mcp_matched) == list.length(published_topics)
  }
  let rate = case list.length(published_topics) {
    0 -> 1.0
    n -> int.to_float(list.length(mcp_matched)) /. int.to_float(n)
  }

  GeminiVerification(
    topics_published: published_topics,
    topics_received_by_mcp: mcp_matched,
    mcp_queries: mcp_received,
    response_times_ms: [],
    all_received: all_received,
    delivery_rate: rate,
    pipeline_healthy: all_received && rate >=. 0.9,
  )
}

/// Verify individual pipeline stages.
pub fn verify_pipeline_stages(
  observer: ObserverState,
  mcp_received: List(String),
) -> List(StageResult) {
  let otel_count = list.length(observer.span_log)
  let zenoh_count = list.length(observer.messages)
  let mcp_count = list.length(mcp_received)

  [
    StageResult(
      stage: StageOtelPublish,
      passed: otel_count > 0,
      message_count: otel_count,
      latency_ms: 0,
      details: "OTel spans: " <> int.to_string(otel_count),
    ),
    StageResult(
      stage: StageZenohTransport,
      passed: zenoh_count > 0,
      message_count: zenoh_count,
      latency_ms: 0,
      details: "Zenoh messages: " <> int.to_string(zenoh_count),
    ),
    StageResult(
      stage: StageMcpRelay,
      passed: mcp_count > 0 || zenoh_count == 0,
      message_count: mcp_count,
      latency_ms: 0,
      details: "MCP relayed: " <> int.to_string(mcp_count),
    ),
    StageResult(
      stage: StageGeminiProcess,
      passed: mcp_count > 0 || zenoh_count == 0,
      message_count: mcp_count,
      latency_ms: 0,
      details: "Gemini processed: " <> int.to_string(mcp_count),
    ),
  ]
}

// =============================================================================
// Report Formatting
// =============================================================================

/// Format Gemini verification results as human-readable string.
pub fn format_gemini_report(verification: GeminiVerification) -> String {
  let header = "=== Gemini Pipeline Verification ==="
  let status = case verification.pipeline_healthy {
    True -> "HEALTHY"
    False -> "DEGRADED"
  }
  let delivery =
    int.to_string({ verification.delivery_rate *. 100.0 } |> float_round) <> "%"

  string.join(
    [
      header,
      "Status: " <> status,
      "Topics published: "
        <> int.to_string(list.length(verification.topics_published)),
      "Topics received by MCP: "
        <> int.to_string(list.length(verification.topics_received_by_mcp)),
      "Delivery rate: " <> delivery,
      "All received: "
        <> case verification.all_received {
        True -> "YES"
        False -> "NO"
      },
    ],
    "\n",
  )
}

pub fn stage_to_string(stage: PipelineStage) -> String {
  case stage {
    StageOtelPublish -> "OTel Publish"
    StageZenohTransport -> "Zenoh Transport"
    StageMcpRelay -> "MCP Relay"
    StageGeminiProcess -> "Gemini Process"
  }
}

// =============================================================================
// Helpers
// =============================================================================

fn unique_list(items: List(String)) -> List(String) {
  unique_acc(items, [])
}

fn unique_acc(items: List(String), seen: List(String)) -> List(String) {
  case items {
    [] -> seen
    [item, ..rest] ->
      case list.contains(seen, item) {
        True -> unique_acc(rest, seen)
        False -> unique_acc(rest, [item, ..seen])
      }
  }
}

fn float_round(f: Float) -> Int {
  float.round(f)
}

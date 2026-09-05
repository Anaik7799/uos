//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/correlated_log</module>
////     <fsharp-lineage>None — novel F15 log correlation layer (Satya Plan)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>Structured log entries correlated to OTel trace spans</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-LOG-001, SC-LOG-003, SC-OTEL-002, SC-GLM-ZEN-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       F# Serilog correlated logging ↪ Gleam pure structured log type.
////       No side effects in log construction; emission is caller's responsibility.
////       PII scrubbing responsibility lies with the Rust NIF layer (SC-LOG-003).
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// CORRELATED LOG ENTRIES — F15 Log Correlation with Trace IDs
//// ज्योतिषामपि तज्ज्योतिः — The light of all lights (Gita 13.17)
////
//// Every log entry carries a TraceContext so individual log lines can be
//// correlated back to the originating distributed trace in Jaeger/Grafana Tempo.
////
//// Design principles:
////   1. Pure construction — no IO in log() or format(). Callers emit.
////   2. Structured first — to_json() is the canonical format for pipelines.
////   3. Human readable — format() produces grep-friendly terminal output.
////   4. Trace-first layout — trace prefix before message for easy filtering.
////
//// Log level severity mapping (aligns with OTel SeverityNumber):
////   Debug    →  5 (DEBUG)
////   Info     →  9 (INFO)
////   Warn     → 13 (WARN)
////   Error    → 17 (ERROR)
////   Critical → 21 (FATAL)
////
//// STAMP: SC-LOG-001, SC-LOG-003, SC-OTEL-002, SC-GLM-ZEN-001

import cepaf_gleam/ha/trace_context.{type TraceContext}
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// FFI — wall-clock nanoseconds (same FFI as trace_context)
// ---------------------------------------------------------------------------

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

@external(erlang, "cepaf_gleam_ffi", "nanos_to_iso8601")
fn nanos_to_iso8601(nanos: Int) -> String

/// Map short layer identifier to canonical fractal layer enum
pub fn layer_to_fractal_enum(layer: String) -> String {
  case layer {
    "L0" | "L0_MICROKERNEL_ALLOCATOR" -> "L0_MICROKERNEL_ALLOCATOR"
    "L1" | "L1_TERM_JIT" -> "L1_TERM_JIT"
    "L2" | "L2_INSTRUCTION_DISPATCH" -> "L2_INSTRUCTION_DISPATCH"
    "L3" | "L3_BYTE_PARITY" -> "L3_BYTE_PARITY"
    "L4" | "L4_STM_CONCURRENCY" -> "L4_STM_CONCURRENCY"
    "L5" | "L5_ACTOR_SUPERVISION" -> "L5_ACTOR_SUPERVISION"
    "L6" | "L6_ZERO_TRUST_GATE" -> "L6_ZERO_TRUST_GATE"
    "L7" | "L7_PROBABILISTIC_TELEMETRY" -> "L7_PROBABILISTIC_TELEMETRY"
    "L8" | "L8_LIVING_ONTOLOGY" -> "L8_LIVING_ONTOLOGY"
    "L9" | "L9_AUTONOMOUS_FEDERATION" -> "L9_AUTONOMOUS_FEDERATION"
    _ -> "L5_ACTOR_SUPERVISION"
  }
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// OTel-aligned log severity levels.
pub type LogLevel {
  Debug
  Info
  Warn
  Error
  Critical
}

/// A structured log entry with embedded trace correlation.
/// Pure data — no side effects. Callers decide how to emit.
pub type LogEntry {
  LogEntry(
    level: LogLevel,
    message: String,
    trace: TraceContext,
    timestamp: Int,
  )
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create a correlated log entry at the given level.
/// Captures the current wall-clock nanosecond timestamp automatically.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">Log event ↪ immutable LogEntry</morphism>
///   <formal-proof>
///     <P> message ≠ "" ∧ trace is a valid TraceContext </P>
///     <C> log(level, message, trace) </C>
///     <Q> result.message == message ∧ result.level == level
///         ∧ result.trace.trace_id == trace.trace_id
///         ∧ result.timestamp > 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn log(level: LogLevel, message: String, trace: TraceContext) -> LogEntry {
  LogEntry(
    level: level,
    message: message,
    trace: trace,
    timestamp: system_time_nanos(),
  )
}

// ---------------------------------------------------------------------------
// Level helpers
// ---------------------------------------------------------------------------

/// Convert LogLevel to its canonical string representation.
pub fn level_to_string(level: LogLevel) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Warn -> "WARN"
    Error -> "ERROR"
    Critical -> "CRITICAL"
  }
}

/// Map LogLevel to OTel SeverityNumber (integer).
/// OTel spec: DEBUG=5, INFO=9, WARN=13, ERROR=17, FATAL=21.
pub fn level_to_otel_severity(level: LogLevel) -> Int {
  case level {
    Debug -> 5
    Info -> 9
    Warn -> 13
    Error -> 17
    Critical -> 21
  }
}

/// Return the ANSI color escape code for the log level.
/// Used in terminal output to color-code severity.
pub fn level_to_ansi(level: LogLevel) -> String {
  case level {
    Debug -> "\u{001B}[36m"
    // Cyan
    Info -> "\u{001B}[32m"
    // Green
    Warn -> "\u{001B}[33m"
    // Yellow
    Error -> "\u{001B}[31m"
    // Red
    Critical -> "\u{001B}[35m"
    // Magenta
  }
}

const ansi_reset = "\u{001B}[0m"

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/// Format as human-readable structured string for terminal/file output.
/// Layout: "[LEVEL] [trace:XXXXXXXX span:YYYYYYYY L:LN] message"
///
/// Example:
///   [INFO]  [trace:4bf92f35 span:00f067aa L:L5] plan_status NIF returned 42 tasks
pub fn format(entry: LogEntry) -> String {
  let level_str = level_to_string(entry.level)
  let padded_level = string.pad_end(level_str, 8, " ")
  let prefix = trace_context.log_prefix(entry.trace)
  string.concat([
    level_to_ansi(entry.level),
    "[",
    padded_level,
    "] ",
    ansi_reset,
    prefix,
    " ",
    entry.message,
  ])
}

/// Format as plain text (no ANSI codes) — suitable for file logging.
pub fn format_plain(entry: LogEntry) -> String {
  let level_str = level_to_string(entry.level)
  let padded_level = string.pad_end(level_str, 8, " ")
  let prefix = trace_context.log_prefix(entry.trace)
  string.concat(["[", padded_level, "] ", prefix, " ", entry.message])
}

/// Serialize to JSON for structured logging pipelines (Loki, Elasticsearch).
/// Follows OTel Log Data Model field naming.
///
/// Output shape:
/// {
///   "timestamp": 1234567890000000000,
///   "severity": "INFO",
///   "severity_number": 9,
///   "body": "...",
///   "trace_id": "...",
///   "span_id": "...",
///   "attributes": {
///     "layer": "L5",
///     "operation": "render_planning",
///     "parent_span_id": "..."
///   }
/// }
pub fn to_json(entry: LogEntry) -> String {
  let parent_json = case entry.trace.parent_span_id {
    "" -> "null"
    p -> "\"" <> p <> "\""
  }
  string.concat([
    "{",
    "\"timestamp\":",
    int.to_string(entry.timestamp),
    ",\"timestamp_utc\":\"",
    nanos_to_iso8601(entry.timestamp),
    "\",\"severity\":\"",
    level_to_string(entry.level),
    "\",\"severity_number\":",
    int.to_string(level_to_otel_severity(entry.level)),
    ",\"fractal_layer\":\"",
    layer_to_fractal_enum(entry.trace.layer),
    "\",\"holon_id\":\"c3i_control_node_1\"",
    ",\"subsystem\":\"gleam_control\"",
    ",\"message\":\"",
    escape_json_string(entry.message),
    "\",\"body\":\"",
    escape_json_string(entry.message),
    "\",\"trace_id\":\"",
    entry.trace.trace_id,
    "\",\"span_id\":\"",
    entry.trace.span_id,
    "\",\"parent_span_id\":",
    parent_json,
    ",\"attributes\":{",
    "\"layer\":\"",
    entry.trace.layer,
    "\",\"operation\":\"",
    entry.trace.operation,
    "\",\"parent_span_id\":\"",
    entry.trace.parent_span_id,
    "\"}}",
  ])
}

// ---------------------------------------------------------------------------
// Batch helpers
// ---------------------------------------------------------------------------

/// Filter a list of log entries by minimum severity level.
/// Returns only entries at or above the threshold level.
pub fn filter_by_level(
  entries: List(LogEntry),
  min_level: LogLevel,
) -> List(LogEntry) {
  let min_num = level_to_otel_severity(min_level)
  list.filter(entries, fn(e) { level_to_otel_severity(e.level) >= min_num })
}

/// Filter entries by trace ID — extract all log lines for one distributed trace.
pub fn filter_by_trace(
  entries: List(LogEntry),
  trace_id: String,
) -> List(LogEntry) {
  list.filter(entries, fn(e) { e.trace.trace_id == trace_id })
}

/// Format multiple entries as a newline-separated log stream.
pub fn format_batch(entries: List(LogEntry)) -> String {
  entries
  |> list.map(format_plain)
  |> string.join("\n")
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Minimal JSON string escaping (handles quotes and backslashes).
fn escape_json_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}

import gleam/list

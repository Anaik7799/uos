//// =============================================================================
//// [C3I-SIL6-MSTS] MATHEMATICAL & SEMANTIC MODULE CONTRACT
//// =============================================================================
//// <c3i-module>
////   <identity>
////     <module>cepaf_gleam/ha/trace_context</module>
////     <fsharp-lineage>None — novel distributed tracing context (F15/F13)</fsharp-lineage>
////   </identity>
////   <fractal-topology>
////     <layer>L1_ATOMIC_DEBUG</layer>
////     <mesh-domain>OTel W3C trace context propagation across all OODA operations</mesh-domain>
////   </fractal-topology>
////   <compliance>
////     <criticality>HIGH</criticality>
////     <stamp-controls>SC-LOG-001, SC-OTEL-002, SC-GLM-ZEN-001, SC-NIF-001</stamp-controls>
////   </compliance>
////   <transformations>
////     <morphism type="injective">
////       W3C Trace Context spec (traceparent header) ↪ Gleam custom type.
////       128-bit trace_id + 64-bit span_id match OTel semantic conventions.
////       crypto.strong_random_bytes/1 provides cryptographic randomness.
////     </morphism>
////   </transformations>
//// </c3i-module>
//// =============================================================================
////
//// DISTRIBUTED TRACE CONTEXT — OTel W3C Propagation
//// ज्योतिषामपि तज्ज्योतिः — The light of all lights (Gita 13.17)
////
//// Every OODA cycle, NIF call, render, and state mutation carries a TraceContext.
//// This enables end-to-end correlation: browser → Gleam → NIF → Rust → Zenoh.
////
//// W3C Trace Context Level 1 (https://www.w3.org/TR/trace-context/):
////   traceparent: "00-{32-hex-trace_id}-{16-hex-span_id}-{flags}"
////   flags: 01 = sampled, 00 = not sampled. We default to 01 (always sample).
////
//// Fractal namespace mapping:
////   L0 Constitutional: guardian operations, emergency stop
////   L1 Atomic/Debug:  NIF calls, telemetry emission (THIS layer)
////   L2 Component:     pure render functions
////   L3 Transaction:   DB writes, planning mutations
////   L4 System:        container lifecycle, podman operations
////   L5 Cognitive:     OODA cycle, MCP tool calls, Cortex decisions
////   L6 Ecosystem:     Zenoh pub/sub, mesh topology
////   L7 Federation:    cross-node consensus, gateway broadcast
////
//// STAMP: SC-LOG-001, SC-OTEL-002, SC-GLM-ZEN-001, SC-NIF-001

import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/string

// ---------------------------------------------------------------------------
// FFI — wall-clock microseconds since Unix epoch
// ---------------------------------------------------------------------------

/// Wall-clock nanoseconds since Unix epoch (Erlang system_time/1).
@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

// ---------------------------------------------------------------------------
// Core type
// ---------------------------------------------------------------------------

/// W3C-compatible OTel trace context.
/// Flows through every operation from UI render → NIF → Rust daemon → Zenoh.
pub type TraceContext {
  TraceContext(
    /// 128-bit trace ID as 32-char lowercase hex — immutable for the full request
    trace_id: String,
    /// 64-bit span ID as 16-char lowercase hex — unique per operation
    span_id: String,
    /// Parent span ID (empty string "" for root spans)
    parent_span_id: String,
    /// Human-readable operation name, e.g. "render_planning", "nif_plan_status"
    operation: String,
    /// Fractal layer declaration "L0".."L7"
    layer: String,
    /// Unix nanoseconds when this span started
    start_time: Int,
  )
}

// ---------------------------------------------------------------------------
// ID generation (cryptographically random, matching OTel conventions)
// ---------------------------------------------------------------------------

/// Convert a BitArray to a lowercase hex string.
fn bytes_to_hex(bytes: BitArray) -> String {
  bytes
  |> bit_array.base16_encode()
  |> string.lowercase()
}

/// Generate a pseudo-random lowercase hex string of the given character length.
/// length=32 → 128-bit trace ID; length=16 → 64-bit span ID.
///
/// Uses crypto.strong_random_bytes so IDs are unpredictable and unique.
/// The `length` parameter controls output chars (each byte → 2 hex chars).
pub fn generate_id(length: Int) -> String {
  let byte_count = length / 2
  let safe_byte_count = case byte_count > 0 {
    True -> byte_count
    False -> 8
  }
  crypto.strong_random_bytes(safe_byte_count)
  |> bytes_to_hex()
  |> string.slice(0, length)
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

/// Create a new root trace context (no parent span).
/// Generates fresh 128-bit trace_id and 64-bit span_id.
/// Use this at the top of a request chain (e.g., when a page render begins).
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">OTel root span ↪ Gleam TraceContext</morphism>
///   <formal-proof>
///     <P> operation ≠ "" ∧ layer ∈ {"L0".."L7"} </P>
///     <C> new_trace(operation, layer) </C>
///     <Q> result.trace_id has length 32 ∧ result.span_id has length 16
///         ∧ result.parent_span_id == "" ∧ result.start_time > 0 </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn new_trace(operation: String, layer: String) -> TraceContext {
  TraceContext(
    trace_id: generate_id(32),
    span_id: generate_id(16),
    parent_span_id: "",
    operation: operation,
    layer: layer,
    start_time: system_time_nanos(),
  )
}

/// Create a child span inheriting the parent's trace_id but with a new span_id.
/// The parent's span_id becomes this child's parent_span_id.
/// Use this when a sub-operation starts within an existing trace.
///
/// [C3I-SIL6] ATOMIC CONTRACT
/// <c3i-atomic>
///   <morphism type="injective">OTel child span ↪ Gleam TraceContext child</morphism>
///   <formal-proof>
///     <P> parent is a valid TraceContext with non-empty trace_id </P>
///     <C> child_span(parent, child_operation, child_layer) </C>
///     <Q> result.trace_id == parent.trace_id
///         ∧ result.span_id ≠ parent.span_id
///         ∧ result.parent_span_id == parent.span_id </Q>
///   </formal-proof>
/// </c3i-atomic>
pub fn child_span(
  parent: TraceContext,
  operation: String,
  layer: String,
) -> TraceContext {
  TraceContext(
    trace_id: parent.trace_id,
    span_id: generate_id(16),
    parent_span_id: parent.span_id,
    operation: operation,
    layer: layer,
    start_time: system_time_nanos(),
  )
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

/// Format as W3C traceparent header value.
/// Spec: "version-trace_id-span_id-flags"
/// Always uses version "00" and flags "01" (sampled).
///
/// Example: "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
pub fn to_traceparent(ctx: TraceContext) -> String {
  string.concat(["00-", ctx.trace_id, "-", ctx.span_id, "-01"])
}

/// Format as structured log prefix for correlated log lines.
/// Example: "[trace:4bf92f35 span:00f067aa L:L5]"
/// (Truncated to 8/8 chars for readability in log streams.)
pub fn log_prefix(ctx: TraceContext) -> String {
  let short_trace = string.slice(ctx.trace_id, 0, 8)
  let short_span = string.slice(ctx.span_id, 0, 8)
  string.concat([
    "[trace:",
    short_trace,
    " span:",
    short_span,
    " L:",
    ctx.layer,
    "]",
  ])
}

/// Attach trace metadata to a JSON response string by appending a `_trace` field.
/// The input json_str is expected to be a JSON object ending with `}`.
/// Returns the augmented JSON string with trace context embedded.
///
/// If json_str does not end with `}`, returns it unchanged (defensive).
pub fn attach_to_json(ctx: TraceContext, json_str: String) -> String {
  let trace_fragment =
    string.concat([
      ",\"_trace\":{\"trace_id\":\"",
      ctx.trace_id,
      "\",\"span_id\":\"",
      ctx.span_id,
      "\",\"parent_span_id\":\"",
      ctx.parent_span_id,
      "\",\"operation\":\"",
      ctx.operation,
      "\",\"layer\":\"",
      ctx.layer,
      "\",\"start_time\":",
      int.to_string(ctx.start_time),
      "}",
    ])
  case string.ends_with(json_str, "}") {
    True -> {
      let prefix = string.drop_end(json_str, 1)
      string.concat([prefix, trace_fragment, "}"])
    }
    False -> json_str
  }
}

/// Compute elapsed nanoseconds from span start to now.
pub fn elapsed_ns(ctx: TraceContext) -> Int {
  system_time_nanos() - ctx.start_time
}

/// Compute elapsed milliseconds (integer, truncated) from span start to now.
pub fn elapsed_ms(ctx: TraceContext) -> Int {
  elapsed_ns(ctx) / 1_000_000
}

/// Return a canonical string representation for debugging.
/// Format: "TraceContext(op={operation} layer={layer} trace={trace_id[0..8]})"
pub fn to_debug_string(ctx: TraceContext) -> String {
  string.concat([
    "TraceContext(op=",
    ctx.operation,
    " layer=",
    ctx.layer,
    " trace=",
    string.slice(ctx.trace_id, 0, 8),
    ")",
  ])
}

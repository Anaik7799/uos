// STAMP: SC-OTEL-001, SC-OBS-001
// AOR: AOR-OTEL-001
// Criticality: Level 2 (HIGH) - Observability and Distributed Tracing
//
// This module provides the OpenTelemetry-compatible tracing and metrics
// bridge for Gleam. It wraps the standard Erlang `telemetry` library
// to ensure seamless integration with the BEAM ecosystem.

import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/list
import gleam/option.{type Option, None, Some}

// ============================================================================
// Semantic Conventions
// ============================================================================

pub const container_name = "container.name"

pub const container_id = "container.id"

pub const operation_type = "cepaf.operation.type"

pub const operation_status = "cepaf.operation.status"

pub const error_type = "error.type"

pub const health_status = "container.health.status"

pub const trace_id_key = "trace_id"

pub const span_id_key = "span_id"

pub const parent_span_id_key = "parent_span_id"

// ============================================================================
// Span Context
// ============================================================================

pub type SpanContext {
  SpanContext(trace_id: String, span_id: String, parent_span_id: String)
}

// ============================================================================
// FFI Definitions for Erlang Telemetry
// ============================================================================

/// Represents a metric measurement (e.g., duration, count).
pub type Measurements =
  Dict(String, Float)

/// Represents the metadata/tags associated with an event.
pub type Metadata =
  Dict(String, String)

// Erlang FFI: telemetry:execute(EventName, Measurements, Metadata)
@external(erlang, "telemetry", "execute")
fn erl_telemetry_execute(
  event_name: List(dynamic.Dynamic),
  measurements: dynamic.Dynamic,
  metadata: dynamic.Dynamic,
) -> Nil

@external(erlang, "cepaf_gleam_ffi", "identity")
fn to_dynamic(a: a) -> Dynamic

// ============================================================================
// Tracing & Metrics API
// ============================================================================

/// Start a new span/activity with optional parent context.
pub fn start_span(
  name: List(String),
  tags: Metadata,
  ctx: Option(SpanContext),
) -> Nil {
  let event_name = build_event_name(name, "start")
  let tags_with_ctx = case ctx {
    Some(c) -> {
      tags
      |> dict.insert(trace_id_key, c.trace_id)
      |> dict.insert(span_id_key, c.span_id)
      |> dict.insert(parent_span_id_key, c.parent_span_id)
    }
    None -> tags
  }

  erl_telemetry_execute(
    event_name,
    to_dynamic(dict.from_list([#("system_time", 0.0)])),
    to_dynamic(tags_with_ctx),
  )
}

/// Stop a span successfully.
pub fn stop_span(
  name: List(String),
  duration_ms: Float,
  tags: Metadata,
  ctx: Option(SpanContext),
) -> Nil {
  let event_name = build_event_name(name, "stop")
  let tags_with_status =
    tags
    |> dict.insert(operation_status, "success")
    |> inject_context(ctx)

  erl_telemetry_execute(
    event_name,
    to_dynamic(dict.from_list([#("duration_ms", duration_ms)])),
    to_dynamic(tags_with_status),
  )
}

/// Stop a span with an error.
pub fn error_span(
  name: List(String),
  duration_ms: Float,
  err_type: String,
  tags: Metadata,
  ctx: Option(SpanContext),
) -> Nil {
  let event_name = build_event_name(name, "exception")
  let error_tags =
    tags
    |> dict.insert(operation_status, "error")
    |> dict.insert(error_type, err_type)
    |> inject_context(ctx)

  erl_telemetry_execute(
    event_name,
    to_dynamic(dict.from_list([#("duration_ms", duration_ms)])),
    to_dynamic(error_tags),
  )
}

fn inject_context(tags: Metadata, ctx: Option(SpanContext)) -> Metadata {
  case ctx {
    Some(c) -> {
      tags
      |> dict.insert(trace_id_key, c.trace_id)
      |> dict.insert(span_id_key, c.span_id)
    }
    None -> tags
  }
}

/// Generate a new unique SpanContext.
pub fn generate_context(parent: Option(SpanContext)) -> SpanContext {
  let trace_id = case parent {
    Some(p) -> p.trace_id
    None -> generate_id()
  }
  let parent_id = case parent {
    Some(p) -> p.span_id
    None -> ""
  }
  SpanContext(
    trace_id: trace_id,
    span_id: generate_id(),
    parent_span_id: parent_id,
  )
}

@external(erlang, "cepaf_gleam_ffi", "generate_id")
fn generate_id() -> String

/// Helper to construct Erlang atom lists for telemetry events (e.g., [:cepaf, :podman, :start]).
fn build_event_name(base: List(String), suffix: String) -> List(Dynamic) {
  list.append(base, [suffix])
  |> list.map(string_to_atom_dynamic)
}

// Wrapper to simplify the 2-arity Erlang BIF call
fn string_to_atom_dynamic(s: String) -> Dynamic {
  // Using utf8 encoding
  string_to_atom_dynamic_impl(s, "utf8")
}

@external(erlang, "erlang", "binary_to_atom")
fn string_to_atom_dynamic_impl(s: String, encoding: String) -> Dynamic

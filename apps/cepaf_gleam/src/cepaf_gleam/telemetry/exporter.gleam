// STAMP: SC-OTEL-002, SC-OBS-002
// AOR: AOR-OTEL-002
// Criticality: Level 2 (HIGH) - OTel OTLP/HTTP Span Exporter
//
// This module exports spans to an OpenTelemetry Collector via OTLP/HTTP
// (JSON over HTTP POST to localhost:4318/v1/traces).

import gleam/bit_array
import gleam/crypto
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/string

// ============================================================================
// FFI Bindings
// ============================================================================

/// Standard TCP HTTP request (no UDS socket). Returns (status, headers, body).
@external(erlang, "cepaf_gleam_ffi", "hackney_http_request")
fn hackney_http_request(
  method: http.Method,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
) -> Result(#(Int, List(#(String, String)), BitArray), String)

/// Wall-clock nanoseconds since Unix epoch.
@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

// ============================================================================
// Constants
// ============================================================================

const collector_url = "http://localhost:4318/v1/traces"

const service_name = "cepaf-gleam"

const scope_name = "cepaf_gleam"

// ============================================================================
// ID Generation
// ============================================================================

/// Generate a 32-character lowercase hex string for trace IDs (16 bytes).
fn generate_trace_id() -> String {
  crypto.strong_random_bytes(16)
  |> bytes_to_hex()
}

/// Generate a 16-character lowercase hex string for span IDs (8 bytes).
fn generate_span_id() -> String {
  crypto.strong_random_bytes(8)
  |> bytes_to_hex()
}

/// Convert a BitArray to a lowercase hex string.
fn bytes_to_hex(bytes: BitArray) -> String {
  bytes
  |> bit_array.base16_encode()
  |> string.lowercase()
}

// ============================================================================
// OTLP Status Mapping
// ============================================================================

/// Map a user-friendly status string to OTLP status code integer.
/// OTLP spec: 0 = UNSET, 1 = OK, 2 = ERROR
fn status_to_code(status: String) -> Int {
  case string.lowercase(status) {
    "ok" -> 1
    "error" -> 2
    _ -> 0
  }
}

// ============================================================================
// OTLP JSON Payload Builder
// ============================================================================

/// Build a single-span OTLP JSON payload matching the OpenTelemetry proto format.
fn build_otlp_payload(
  name: String,
  duration_ms: Float,
  status: String,
  attributes: List(#(String, String)),
) -> String {
  let now_ns = system_time_nanos()
  let duration_ns = float_to_int_nanos(duration_ms)
  let start_ns = now_ns - duration_ns
  let trace_id = generate_trace_id()
  let span_id = generate_span_id()

  let span_attributes =
    list.map(attributes, fn(attr) {
      let #(key, value) = attr
      json.object([
        #("key", json.string(key)),
        #("value", json.object([#("stringValue", json.string(value))])),
      ])
    })

  let resource_attributes = [
    json.object([
      #("key", json.string("service.name")),
      #("value", json.object([#("stringValue", json.string(service_name))])),
    ]),
  ]

  json.object([
    #(
      "resourceSpans",
      json.preprocessed_array([
        json.object([
          #(
            "resource",
            json.object([
              #("attributes", json.preprocessed_array(resource_attributes)),
            ]),
          ),
          #(
            "scopeSpans",
            json.preprocessed_array([
              json.object([
                #("scope", json.object([#("name", json.string(scope_name))])),
                #(
                  "spans",
                  json.preprocessed_array([
                    json.object([
                      #("traceId", json.string(trace_id)),
                      #("spanId", json.string(span_id)),
                      #("name", json.string(name)),
                      #(
                        "startTimeUnixNano",
                        json.string(int.to_string(start_ns)),
                      ),
                      #("endTimeUnixNano", json.string(int.to_string(now_ns))),
                      #(
                        "status",
                        json.object([
                          #("code", json.int(status_to_code(status))),
                        ]),
                      ),
                      #("attributes", json.preprocessed_array(span_attributes)),
                    ]),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ]),
    ),
  ])
  |> json.to_string()
}

/// Convert milliseconds (Float) to nanoseconds (Int).
fn float_to_int_nanos(ms: Float) -> Int {
  // 1 ms = 1_000_000 ns
  let ns_float = ms *. 1_000_000.0
  float_to_int(ns_float)
}

@external(erlang, "erlang", "trunc")
fn float_to_int(f: Float) -> Int

// ============================================================================
// Public API
// ============================================================================

/// Export a single span to the OTel collector at localhost:4318.
///
/// Parameters:
///   - name: Span name (e.g. "c3i.boot", "podman.list_containers")
///   - duration_ms: Span duration in milliseconds
///   - status: "ok", "error", or "unset"
///   - attributes: Key-value string pairs for span attributes
///
/// Returns Ok(Nil) on successful export, Error(reason) on failure.
pub fn export_span(
  name: String,
  duration_ms: Float,
  status: String,
  attributes: List(#(String, String)),
) -> Result(Nil, String) {
  let payload = build_otlp_payload(name, duration_ms, status, attributes)
  let body = bit_array.from_string(payload)
  let headers = [
    #("content-type", "application/json"),
  ]

  case hackney_http_request(http.Post, collector_url, headers, body) {
    Ok(#(status_code, _, _)) ->
      case status_code >= 200 && status_code < 300 {
        True -> Ok(Nil)
        False ->
          Error("OTel collector returned HTTP " <> int.to_string(status_code))
      }
    Error("hackney_not_available_undef") -> {
      // io.println("  [otel] Skipping export: hackney not available")
      Ok(Nil)
    }
    Error(reason) -> Error("OTel export failed: " <> reason)
  }
}

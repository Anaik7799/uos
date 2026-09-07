// STAMP: SC-OTEL-002, SC-OBS-002
// AOR: AOR-OTEL-002
// Criticality: Level 2 (HIGH) - OTel OTLP/HTTP Span Exporter

import cepaf_gleam/ha/trace_context.{type TraceContext}
import envoy
import gleam/bit_array
import gleam/erlang/process
import gleam/http
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "cepaf_gleam_ffi", "hackney_http_request")
fn hackney_http_request(
  method: http.Method,
  url: String,
  headers: List(#(String, String)),
  body: BitArray,
) -> Result(#(Int, List(#(String, String)), BitArray), String)

@external(erlang, "cepaf_gleam_ffi", "system_time_nanos")
fn system_time_nanos() -> Int

pub const default_collector_url = "http://127.0.0.1:4318/v1/traces"

pub const default_timeout_ms = 2000

pub type Config {
  Config(
    endpoint: String,
    service_name: String,
    scope_name: String,
    timeout_ms: Int,
    endpoint_source: String,
  )
}

pub type Transport =
  fn(http.Method, String, List(#(String, String)), BitArray) ->
    Result(#(Int, List(#(String, String)), BitArray), String)

pub fn new_config(
  endpoint: String,
  service_name: String,
  scope_name: String,
  timeout_ms: Int,
) -> Result(Config, String) {
  new_config_with_source(
    endpoint,
    service_name,
    scope_name,
    timeout_ms,
    "explicit",
  )
}

fn new_config_with_source(
  endpoint: String,
  service_name: String,
  scope_name: String,
  timeout_ms: Int,
  endpoint_source: String,
) -> Result(Config, String) {
  case
    string.starts_with(endpoint, "http://")
    || string.starts_with(endpoint, "https://"),
    service_name != "" && scope_name != "",
    timeout_ms > 0 && timeout_ms <= 30_000
  {
    False, _, _ -> Error("OTLP endpoint must use http or https")
    _, False, _ -> Error("OTLP service and scope names must be non-empty")
    _, _, False -> Error("OTLP timeout must be within 1..30000ms")
    True, True, True ->
      Ok(Config(endpoint, service_name, scope_name, timeout_ms, endpoint_source))
  }
}

/// Resolve typed configuration from standard OTel environment variables.
/// Invalid configured values fail closed instead of silently selecting another
/// endpoint. No environment value is returned by the status API.
pub fn config_from_env() -> Result(Config, String) {
  let #(endpoint, source) = case
    envoy.get("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
  {
    Ok(value) -> #(value, "environment")
    Error(Nil) -> #(default_collector_url, "default")
  }
  use timeout <- result.try(case envoy.get("OTEL_EXPORTER_OTLP_TIMEOUT") {
    Error(Nil) -> Ok(default_timeout_ms)
    Ok(value) ->
      int.parse(value)
      |> result.map_error(fn(_) {
        "OTEL_EXPORTER_OTLP_TIMEOUT is not an integer"
      })
  })
  new_config_with_source(
    endpoint,
    "cepaf-gleam",
    "cepaf_gleam",
    timeout,
    source,
  )
}

fn status_to_code(status: String) -> Int {
  case string.lowercase(status) {
    "ok" -> 1
    "error" -> 2
    _ -> 0
  }
}

fn float_to_int_nanos(ms: Float) -> Int {
  float_to_int(ms *. 1_000_000.0)
}

@external(erlang, "erlang", "trunc")
fn float_to_int(f: Float) -> Int

fn span_json(
  config: Config,
  context: TraceContext,
  name: String,
  duration_ms: Float,
  status: String,
  attributes: List(#(String, String)),
) -> String {
  let now_ns = system_time_nanos()
  let start_ns = now_ns - float_to_int_nanos(duration_ms)
  let span_attributes =
    attributes
    |> list.map(fn(attribute) {
      json.object([
        #("key", json.string(attribute.0)),
        #("value", json.object([#("stringValue", json.string(attribute.1))])),
      ])
    })
  let parent = case context.parent_span_id {
    "" -> []
    value -> [#("parentSpanId", json.string(value))]
  }
  let span_fields =
    list.append(
      [
        #("traceId", json.string(context.trace_id)),
        #("spanId", json.string(context.span_id)),
        #("name", json.string(name)),
        #("startTimeUnixNano", json.string(int.to_string(start_ns))),
        #("endTimeUnixNano", json.string(int.to_string(now_ns))),
        #("status", json.object([#("code", json.int(status_to_code(status)))])),
        #("attributes", json.preprocessed_array(span_attributes)),
      ],
      parent,
    )

  json.object([
    #(
      "resourceSpans",
      json.preprocessed_array([
        json.object([
          #(
            "resource",
            json.object([
              #(
                "attributes",
                json.preprocessed_array([
                  json.object([
                    #("key", json.string("service.name")),
                    #(
                      "value",
                      json.object([
                        #("stringValue", json.string(config.service_name)),
                      ]),
                    ),
                  ]),
                ]),
              ),
            ]),
          ),
          #(
            "scopeSpans",
            json.preprocessed_array([
              json.object([
                #(
                  "scope",
                  json.object([#("name", json.string(config.scope_name))]),
                ),
                #("spans", json.preprocessed_array([json.object(span_fields)])),
              ]),
            ]),
          ),
        ]),
      ]),
    ),
  ])
  |> json.to_string
}

fn request_bounded(
  config: Config,
  body: BitArray,
  transport: Transport,
) -> Result(#(Int, List(#(String, String)), BitArray), String) {
  let reply = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      let response =
        transport(
          http.Post,
          config.endpoint,
          [#("content-type", "application/json")],
          body,
        )
      process.send(reply, response)
    })
  case process.receive(from: reply, within: config.timeout_ms) {
    Ok(response) -> response
    Error(Nil) -> {
      process.kill(worker)
      Error(
        "OTel export timed out after "
        <> int.to_string(config.timeout_ms)
        <> "ms",
      )
    }
  }
}

fn classify_response(
  response: Result(#(Int, List(#(String, String)), BitArray), String),
) -> Result(Nil, String) {
  case response {
    Ok(#(status_code, _, _)) if status_code >= 200 && status_code < 300 ->
      Ok(Nil)
    Ok(#(status_code, _, _)) ->
      Error("OTel collector returned HTTP " <> int.to_string(status_code))
    Error(reason) ->
      case string.starts_with(reason, "OTel export timed out") {
        True -> Error(reason)
        False -> Error("OTel export failed: " <> reason)
      }
  }
}

/// Export through an injected transport. This keeps timeout and response
/// semantics directly testable without pretending a collector exists.
pub fn export_span_using(
  config: Config,
  name: String,
  duration_ms: Float,
  status: String,
  attributes: List(#(String, String)),
  transport: Transport,
) -> Result(Nil, String) {
  case name == "" || duration_ms <. 0.0 {
    True -> Error("OTel span name and duration are invalid")
    False -> {
      let context = trace_context.new_trace(name, "L7")
      span_json(config, context, name, duration_ms, status, attributes)
      |> bit_array.from_string
      |> request_bounded(config, _, transport)
      |> classify_response
    }
  }
}

/// Export while retaining an existing trace context for cross-message
/// correlation.
pub fn export_span_with_context(
  config: Config,
  context: TraceContext,
  name: String,
  duration_ms: Float,
  status: String,
  attributes: List(#(String, String)),
) -> Result(Nil, String) {
  case name == "" || duration_ms <. 0.0 {
    True -> Error("OTel span name and duration are invalid")
    False ->
      span_json(config, context, name, duration_ms, status, attributes)
      |> bit_array.from_string
      |> request_bounded(config, _, hackney_http_request)
      |> classify_response
  }
}

/// Compatibility entry point using typed environment/default configuration.
/// Missing HTTP support is an error; it is never reported as successful.
pub fn export_span(
  name: String,
  duration_ms: Float,
  status: String,
  attributes: List(#(String, String)),
) -> Result(Nil, String) {
  use config <- result.try(config_from_env())
  export_span_using(
    config,
    name,
    duration_ms,
    status,
    attributes,
    hackney_http_request,
  )
}

/// Status without a probe. Configuration is known; collector acceptance,
/// backend visibility, and counts remain unknown until observed separately.
pub fn status_json(config: Config) -> String {
  json.object([
    #("page", json.string("Telemetry")),
    #("standard", json.string("OpenTelemetry")),
    #("transport", json.string("OTLP/HTTP")),
    #("signal", json.string("traces")),
    #("configuration_status", json.string("valid")),
    #("endpoint_source", json.string(config.endpoint_source)),
    #("exporter_status", json.string("configured_unprobed")),
    #("collector_status", json.string("unknown")),
    #("backend_status", json.string("unknown")),
    #("log_level", json.null()),
    #("active_spans", json.null()),
    #("total_traces", json.null()),
  ])
  |> json.to_string
}

pub fn configuration_error_json(reason: String) -> String {
  json.object([
    #("page", json.string("Telemetry")),
    #("standard", json.string("OpenTelemetry")),
    #("transport", json.string("OTLP/HTTP")),
    #("signal", json.string("traces")),
    #("configuration_status", json.string("invalid")),
    #("reason", json.string(reason)),
    #("exporter_status", json.string("unavailable")),
    #("collector_status", json.string("unknown")),
    #("backend_status", json.string("unknown")),
    #("log_level", json.null()),
    #("active_spans", json.null()),
    #("total_traces", json.null()),
  ])
  |> json.to_string
}

import cepaf_gleam/ha/trace_context
import cepaf_gleam/observability/zenoh_otel_ingestor
import cepaf_gleam/telemetry/exporter
import cepaf_gleam/telemetry/otel
import cepaf_gleam/ui/domain.{Dashboard}
import cepaf_gleam/ui/wisp/router
import cepaf_gleam/ui/zenoh_otel.{Observe}
import gleam/dict
import gleam/erlang/process
import gleam/json
import gleam/option.{None}
import gleam/string
import gleeunit/should

pub fn zenoh_span_uses_w3c_ids_and_real_time_test() {
  let span = zenoh_otel.new_span(Dashboard, "audit", Observe, json.object([]))

  string.length(span.trace_id) |> should.equal(32)
  string.lowercase(span.trace_id) |> should.equal(span.trace_id)
  string.length(span.span_id) |> should.equal(16)
  string.lowercase(span.span_id) |> should.equal(span.span_id)
  { span.timestamp > 0 } |> should.be_true
}

pub fn zenoh_emitter_and_ingestor_share_topic_registry_test() {
  zenoh_otel.span_topic_prefix
  |> should.equal(zenoh_otel_ingestor.span_topic_prefix)

  zenoh_otel_ingestor.accepts_topic(
    zenoh_otel.span_topic_prefix <> "dashboard/audit",
  )
  |> should.be_true
  zenoh_otel_ingestor.accepts_topic("indrajaal/otel/spans/dashboard/audit")
  |> should.be_false
}

pub fn telemetry_context_uses_w3c_ids_test() {
  let context = otel.generate_context(None)
  string.length(context.trace_id) |> should.equal(32)
  string.lowercase(context.trace_id) |> should.equal(context.trace_id)
  string.length(context.span_id) |> should.equal(16)
  string.lowercase(context.span_id) |> should.equal(context.span_id)
}

pub fn telemetry_start_measurement_uses_wall_clock_test() {
  let assert Ok(system_time) =
    otel.start_measurements()
    |> dict.get("system_time")
  { system_time > 0 } |> should.be_true
}

pub fn exporter_rejects_invalid_typed_config_test() {
  exporter.new_config("", "cepaf-gleam", "cepaf_gleam", 1000)
  |> should.be_error
  exporter.new_config(
    "http://127.0.0.1:4318/v1/traces",
    "cepaf-gleam",
    "cepaf_gleam",
    0,
  )
  |> should.be_error
}

pub fn exporter_transport_is_bounded_test() {
  let assert Ok(config) =
    exporter.new_config(
      "http://127.0.0.1:4318/v1/traces",
      "cepaf-gleam",
      "cepaf_gleam",
      5,
    )
  let result =
    exporter.export_span_using(
      config,
      "audit.synthetic",
      1.0,
      "ok",
      [],
      fn(_, _, _, _) {
        process.sleep(50)
        Error("late transport result")
      },
    )

  result |> should.equal(Error("OTel export timed out after 5ms"))
}

pub fn exporter_missing_transport_fails_closed_test() {
  let assert Ok(config) =
    exporter.new_config(
      "http://127.0.0.1:4318/v1/traces",
      "cepaf-gleam",
      "cepaf_gleam",
      100,
    )
  exporter.export_span_using(
    config,
    "audit.synthetic",
    1.0,
    "ok",
    [],
    fn(_, _, _, _) { Error("hackney_not_available_undef") },
  )
  |> should.equal(Error("OTel export failed: hackney_not_available_undef"))
}

pub fn context_export_rejects_invalid_span_before_transport_test() {
  let assert Ok(config) =
    exporter.new_config(
      "http://127.0.0.1:4318/v1/traces",
      "cepaf-gleam",
      "cepaf_gleam",
      100,
    )
  let context = trace_context.new_trace("audit.parent", "L7")

  exporter.export_span_with_context(config, context, "", -1.0, "error", [])
  |> should.equal(Error("OTel span name and duration are invalid"))
}

pub fn telemetry_status_is_truthful_when_unprobed_test() {
  let assert Ok(config) =
    exporter.new_config(
      "http://127.0.0.1:4318/v1/traces",
      "cepaf-gleam",
      "cepaf_gleam",
      1000,
    )
  let status = exporter.status_json(config)

  status
  |> string.contains("\"collector_status\":\"unknown\"")
  |> should.be_true
  status |> string.contains("\"backend_status\":\"unknown\"") |> should.be_true
  status |> string.contains("\"active_spans\":null") |> should.be_true
  status |> string.contains("\"total_traces\":null") |> should.be_true
  status |> string.contains("1247") |> should.be_false
}

pub fn telemetry_route_does_not_invent_counts_test() {
  let status = router.route("/api/telemetry/status")
  status
  |> string.contains("\"collector_status\":\"unknown\"")
  |> should.be_true
  status |> string.contains("\"active_spans\":null") |> should.be_true
  status |> string.contains("1247") |> should.be_false
}

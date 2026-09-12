/// Lustre component for Telemetry plane (SC-GLM-UI-001).
/// Manages spans, metrics, log levels, and active traces.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/ui/domain.{Telemetry}
import cepaf_gleam/ui/zenoh_otel
import gleam/list

pub type TelemetryModel {
  TelemetryModel(
    spans: List(Span),
    metrics: List(Metric),
    log_level: LogLevel,
    active_traces: Int,
    // P3-4: Rate limiting display
    rate_limit_remaining: Int,
    rate_limit_max: Int,
    rate_limit_reset_s: Int,
  )
}

pub type Span {
  Span(
    trace_id: String,
    span_id: String,
    name: String,
    duration_us: Int,
    status: String,
  )
}

pub type Metric {
  Metric(name: String, value: Float, unit: String, timestamp: Int)
}

pub type LogLevel {
  Debug
  Info
  Warning
  Error
}

pub type TelemetryMsg {
  SpanReceived(Span)
  MetricUpdated(Metric)
  SetLogLevel(LogLevel)
  RefreshTelemetry
}

pub fn init() -> TelemetryModel {
  TelemetryModel(spans: [], metrics: [], log_level: Info, active_traces: 0,
    rate_limit_remaining: 20, rate_limit_max: 20, rate_limit_reset_s: 60)
}

pub fn update(model: TelemetryModel, msg: TelemetryMsg) -> TelemetryModel {
  zenoh_otel.emit(Telemetry, "update", zenoh_otel.Act)
  case msg {
    SpanReceived(span) -> TelemetryModel(..model, spans: [span, ..model.spans])
    MetricUpdated(metric) ->
      TelemetryModel(..model, metrics: [metric, ..model.metrics])
    SetLogLevel(level) -> TelemetryModel(..model, log_level: level)
    RefreshTelemetry -> model
  }
}

pub fn log_level_to_string(level: LogLevel) -> String {
  case level {
    Debug -> "DEBUG"
    Info -> "INFO"
    Warning -> "WARNING"
    Error -> "ERROR"
  }
}

pub fn recent_spans(model: TelemetryModel, count: Int) -> List(Span) {
  list.take(model.spans, count)
}

pub fn metric_by_name(
  model: TelemetryModel,
  name: String,
) -> Result(Metric, Nil) {
  list.find(model.metrics, fn(m) { m.name == name })
}

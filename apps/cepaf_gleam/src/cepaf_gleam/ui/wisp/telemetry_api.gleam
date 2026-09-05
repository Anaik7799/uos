/// Wisp API for Telemetry plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Typed JSON via gleam/json — no raw strings (SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import cepaf_gleam/ui/domain.{
  type EvolutionVectors, type MathematicalIntegrity, type SingularityEstimation,
}
import gleam/json

/// Full telemetry status JSON with OTel spans, active traces, metrics, and log level.
pub fn status_json(
  active_traces: Int,
  total_spans: Int,
  cpu_percent: Float,
  memory_mb: Int,
  network_bytes_sec: Int,
  log_level: String,
) -> String {
  json.object([
    #("plane", json.string("telemetry")),
    #("active_traces", json.int(active_traces)),
    #("total_spans", json.int(total_spans)),
    #(
      "metrics",
      json.object([
        #("cpu_percent", json.float(cpu_percent)),
        #("memory_mb", json.int(memory_mb)),
        #("network_bytes_sec", json.int(network_bytes_sec)),
      ]),
    ),
    #("log_level", json.string(log_level)),
  ])
  |> json.to_string()
}

/// Compact metrics-only JSON for telemetry plane.
pub fn metrics_json(
  cpu_percent: Float,
  memory_mb: Int,
  network_bytes_sec: Int,
) -> String {
  json.object([
    #("plane", json.string("telemetry")),
    #("cpu_percent", json.float(cpu_percent)),
    #("memory_mb", json.int(memory_mb)),
    #("network_bytes_sec", json.int(network_bytes_sec)),
  ])
  |> json.to_string()
}

/// JSON encoder for Mathematical Integrity Pane (Hs, epsilon, Ds).
pub fn integrity_json(integrity: MathematicalIntegrity) -> String {
  json.object([
    #("plane", json.string("integrity")),
    #("hs", json.float(integrity.hs)),
    #("epsilon", json.float(integrity.epsilon)),
    #("ds", json.float(integrity.ds)),
  ])
  |> json.to_string()
}

/// JSON encoder for Evolution Vectors (V1-V4).
pub fn evolution_vectors_json(vectors: EvolutionVectors) -> String {
  json.object([
    #("plane", json.string("evolution_vectors")),
    #("v1", json.float(vectors.v1)),
    #("v2", json.float(vectors.v2)),
    #("v3", json.float(vectors.v3)),
    #("v4", json.float(vectors.v4)),
  ])
  |> json.to_string()
}

/// JSON encoder for Time-to-Singularity estimation.
pub fn singularity_json(estimation: SingularityEstimation) -> String {
  json.object([
    #("plane", json.string("singularity")),
    #("time_to_singularity_ms", json.int(estimation.time_to_singularity_ms)),
    #("confidence_interval", json.float(estimation.confidence_interval)),
    #(
      "critical_threshold_reached",
      json.bool(estimation.critical_threshold_reached),
    ),
  ])
  |> json.to_string()
}

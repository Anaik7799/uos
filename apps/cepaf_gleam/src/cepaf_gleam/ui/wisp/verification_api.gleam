/// Wisp API for Verification plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007, SC-PROM-001..007, SC-GRAPH-001..010
import cepaf_gleam/ui/domain.{
  type BicameralSignOff, type BiomorphicMatrix, type MathematicalIntegrity,
}
import cepaf_gleam/verification/graph_verification.{type GraphCheck}
import cepaf_gleam/verification/prometheus.{
  type ProofToken, type VerificationResult, Inconclusive, Rejected, Verified,
}
import cepaf_gleam/verification/swarm.{
  type FractalLayerReport, type OodaMetrics, type SwarmReport,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option

pub fn mathematical_integrity_json(mi: MathematicalIntegrity) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("type", json.string("mathematical_integrity")),
    #("hs", json.float(mi.hs)),
    #("epsilon", json.float(mi.epsilon)),
    #("ds", json.float(mi.ds)),
  ])
  |> json.to_string()
}

/// JSON encoder for Bicameral Two-Key Release Protocol (813a7a93).
pub fn bicameral_sign_off_json(sign_off: BicameralSignOff) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("type", json.string("bicameral_sign_off")),
    #("key1_signed", json.bool(sign_off.key1_signed)),
    #("key2_signed", json.bool(sign_off.key2_signed)),
    #(
      "authorized_by",
      json.string(option.unwrap(sign_off.authorized_by, "none")),
    ),
  ])
  |> json.to_string()
}

/// JSON encoder for NASA-STD-3000 Biomorphic Matrix (aa1ce076).
pub fn biomorphic_matrix_json(matrix: BiomorphicMatrix) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("type", json.string("biomorphic_matrix")),
    #(
      "levels",
      json.array(matrix.levels, fn(l) {
        let #(layer, status) = l
        json.object([
          #("layer", json.string(domain.layer_to_string(layer))),
          #("status", json.string(status_to_string(status))),
        ])
      }),
    ),
  ])
  |> json.to_string()
}

fn status_to_string(status: domain.HealthStatus) -> String {
  case status {
    domain.Healthy -> "healthy"
    domain.Degraded(r) -> "degraded: " <> r
    domain.Critical(r) -> "critical: " <> r
    domain.Unknown -> "unknown"
  }
}

pub fn swarm_report_json(report: SwarmReport) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("healthy_containers", json.int(report.healthy_containers)),
    #("total_containers", json.int(report.total_containers)),
    #("ooda", encode_ooda(report.ooda_metrics)),
    #("fractal_layers", json.array(report.fractal_layers, encode_layer)),
  ])
  |> json.to_string()
}

/// Returns typed JSON for a high-level verification status (SC-GLM-UI-003).
/// Fixed: compliance_percent now computes the integer ratio correctly instead
/// of discarding the json.int() call and always returning 0.0.
pub fn verification_status_json(
  healthy: Int,
  total: Int,
  compliant: Bool,
) -> String {
  let pct = case total {
    0 -> 0.0
    t -> int.to_float(healthy * 100 / t)
  }
  json.object([
    #("plane", json.string("verification")),
    #("healthy", json.int(healthy)),
    #("total", json.int(total)),
    #("compliant", json.bool(compliant)),
    #("compliance_percent", json.float(pct)),
  ])
  |> json.to_string()
}

/// Encodes a ProofToken to a JSON string (SC-PROM-001).
pub fn proof_token_json(proof: ProofToken) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("type", json.string("proof_token")),
    #("dag_hash", json.string(proof.dag_hash)),
    #("path", json.array(proof.path, json.string)),
    #("verified_at", json.int(proof.verified_at)),
    #("constraints_checked", json.array(proof.constraints_checked, json.string)),
    #("result", json.string(result_to_string(proof.result))),
  ])
  |> json.to_string()
}

/// Encodes DAG topology statistics to a JSON string (SC-BOOT-008).
pub fn dag_status_json(
  node_count: Int,
  edge_count: Int,
  is_acyclic: Bool,
) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("type", json.string("dag_status")),
    #("node_count", json.int(node_count)),
    #("edge_count", json.int(edge_count)),
    #("is_acyclic", json.bool(is_acyclic)),
  ])
  |> json.to_string()
}

/// Encodes a list of GraphChecks with aggregate pass/fail counts (SC-GRAPH-001).
pub fn graph_checks_json(checks: List(GraphCheck)) -> String {
  json.object([
    #("plane", json.string("verification")),
    #("type", json.string("graph_checks")),
    #("checks", json.array(checks, encode_graph_check)),
    #("all_passed", json.bool(graph_verification.all_passed(checks))),
    #("passed_count", json.int(graph_verification.passed_count(checks))),
    #("total_count", json.int(list.length(checks))),
  ])
  |> json.to_string()
}

fn encode_graph_check(check: GraphCheck) -> json.Json {
  json.object([
    #("name", json.string(check.name)),
    #("passed", json.bool(check.passed)),
    #("details", json.string(check.details)),
  ])
}

fn result_to_string(result: VerificationResult) -> String {
  case result {
    Verified -> "verified"
    Rejected(_) -> "rejected"
    Inconclusive -> "inconclusive"
  }
}

fn encode_ooda(m: OodaMetrics) -> json.Json {
  json.object([
    #("agent_latency_ms", json.int(m.agent_latency_ms)),
    #("intelligence_latency_ms", json.int(m.intelligence_latency_ms)),
    #("compliance", json.bool(m.compliance)),
  ])
}

fn encode_layer(l: FractalLayerReport) -> json.Json {
  json.object([
    #("layer", json.int(l.layer)),
    #("status", json.string(l.status)),
    #("evidence", json.string(l.evidence)),
  ])
}

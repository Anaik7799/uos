/// TUI view for Verification plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007, SC-PROM-001..007, SC-GRAPH-001..010
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/verification.{type VerificationModel}
import cepaf_gleam/verification/graph_verification.{type GraphCheck}
import cepaf_gleam/verification/prometheus.{
  type VerificationResult, Inconclusive, Rejected, Verified,
}
import cepaf_gleam/verification/swarm.{type FractalLayerReport, type SwarmReport}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: VerificationModel) -> String {
  let header = visuals.with_color("  VERIFICATION", "cyan")
  let status = render_run_status(model)
  let report = case model.last_report {
    Some(r) -> render_report(r)
    None -> "  No verification run yet."
  }
  let proof = render_proof(model)
  let checks = render_graph_checks(model)
  let dag = render_dag_stats(model)
  let heatmap =
    visuals.render_fractal_heatmap([
      #("L0 Constitutional", case model.last_report {
        Some(r) ->
          case r.total_containers > 0 {
            True ->
              int.to_float(r.healthy_containers)
              /. int.to_float(r.total_containers)
            False -> 0.0
          }
        None -> 0.0
      }),
      #("L1 Atomic", 0.95),
      #("L2 Component", 0.92),
      #("L3 Transaction", 0.88),
      #("L4 System", 0.9),
      #("L5 Cognitive", 0.85),
      #("L6 Ecosystem", 0.78),
      #("L7 Federation", 0.65),
    ])
  string.join(
    [header, status, "", report, "", proof, "", heatmap, "", checks, "", dag],
    "\n",
  )
}

fn render_run_status(model: VerificationModel) -> String {
  case model.running {
    True -> "  " <> visuals.with_color("RUNNING...", "yellow")
    False ->
      "  "
      <> visuals.with_color("IDLE", "blue")
      <> "  History: "
      <> int.to_string(list.length(model.history))
      <> " runs"
  }
}

fn render_report(report: SwarmReport) -> String {
  let pct = case report.total_containers {
    0 -> 0
    t -> report.healthy_containers * 100 / t
  }
  let bar = visuals.render_progress_bar(int_to_float(pct) /. 100.0, 30)
  let containers =
    "  Containers: "
    <> int.to_string(report.healthy_containers)
    <> "/"
    <> int.to_string(report.total_containers)
    <> " healthy"
  let compliance =
    "  OODA: "
    <> case report.ooda_metrics.compliance {
      True -> visuals.with_color("COMPLIANT", "green")
      False -> visuals.with_color("NON-COMPLIANT", "red")
    }
    <> "  Agent: "
    <> int.to_string(report.ooda_metrics.agent_latency_ms)
    <> "ms"
    <> "  Intel: "
    <> int.to_string(report.ooda_metrics.intelligence_latency_ms)
    <> "ms"
  let layers = render_layers(report.fractal_layers)
  string.join([bar, containers, compliance, "", layers], "\n")
}

fn render_layers(layers: List(FractalLayerReport)) -> String {
  layers
  |> list.map(fn(l) {
    let color = case l.status {
      "Stable" -> "green"
      "Healthy" -> "green"
      "Degraded" -> "yellow"
      _ -> "red"
    }
    "  L"
    <> int.to_string(l.layer)
    <> " "
    <> visuals.with_color(l.status, color)
    <> " — "
    <> l.evidence
  })
  |> string.join("\n")
}

/// Renders the latest PROMETHEUS proof token section.
fn render_proof(model: VerificationModel) -> String {
  let label = visuals.with_color("  PROOF", "cyan")
  case model.latest_proof {
    None -> label <> "\n  No proof generated"
    Some(proof) -> {
      let path_str = string.join(proof.path, " → ")
      let result_color = proof_result_color(proof.result)
      let result_str =
        visuals.with_color(
          verification.proof_result_string(proof.result),
          result_color,
        )
      let constraint_count =
        int.to_string(list.length(proof.constraints_checked))
      string.join(
        [
          label,
          "  Proof: " <> proof.dag_hash,
          "  Path:  " <> path_str,
          "  Result: " <> result_str,
          "  Constraints: " <> constraint_count <> " checked",
          "  Verified at: " <> int.to_string(proof.verified_at),
        ],
        "\n",
      )
    }
  }
}

/// Renders the graph check results section.
fn render_graph_checks(model: VerificationModel) -> String {
  let label = visuals.with_color("  GRAPH CHECKS", "cyan")
  case model.graph_checks {
    [] -> label <> "\n  No graph checks run"
    checks -> {
      let total = list.length(checks)
      let passed =
        list.length(list.filter(checks, fn(c: GraphCheck) { c.passed }))
      let rows =
        list.map(checks, fn(c: GraphCheck) {
          let badge = case c.passed {
            True -> visuals.with_color("PASS", "green")
            False -> visuals.with_color("FAIL", "red")
          }
          "  [" <> badge <> "] " <> c.name <> ": " <> c.details
        })
      let summary =
        "  "
        <> int.to_string(passed)
        <> "/"
        <> int.to_string(total)
        <> " checks passed"
      string.join([label, ..list.append(rows, [summary])], "\n")
    }
  }
}

/// Renders the DAG node/edge statistics section.
fn render_dag_stats(model: VerificationModel) -> String {
  let label = visuals.with_color("  DAG", "cyan")
  label
  <> "\n  DAG: "
  <> int.to_string(model.dag_node_count)
  <> " nodes, "
  <> int.to_string(model.dag_edge_count)
  <> " edges"
}

/// Maps a VerificationResult to a terminal color name.
fn proof_result_color(result: VerificationResult) -> String {
  case result {
    Verified -> "green"
    Rejected(_) -> "red"
    Inconclusive -> "yellow"
  }
}

fn int_to_float(n: Int) -> Float {
  int.to_float(n)
}

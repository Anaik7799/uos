//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/singularity_view</module></identity>
////   <fractal-topology><layer>L7_FEDERATION</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-SING-001</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/singularity.{
  type CapabilityMetric, type SingularityModel,
}
import gleam/float
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: SingularityModel) -> String {
  let header = visuals.with_color("  SINGULARITY (L7 Federation)", "cyan")
  let body = case model.loading {
    True -> "  Loading estimation data..."
    False ->
      case model.error {
        Some(e) -> "  " <> visuals.with_color("ERROR: " <> e, "red")
        None -> render_state(model)
      }
  }
  string.join([header, body], "\n")
}

fn render_state(model: SingularityModel) -> String {
  let conv_line =
    "  Convergence: "
    <> visuals.render_progress_bar(model.convergence_pct /. 100.0, 25)
    <> " "
    <> float.to_string(model.convergence_pct)
    <> "%"
  let safety_color = case singularity.within_safety_boundary(model) {
    True -> "green"
    False -> "red"
  }
  let safety_line =
    "  Safety:      "
    <> visuals.with_color(float.to_string(model.safety_margin), safety_color)
  let cap_line = "  Capability:  " <> float.to_string(model.capability_score)
  let horizon_line = "  Horizon:     " <> model.estimation_horizon
  let caps_header = "  Capabilities:"
  let cap_rows =
    model.capabilities
    |> list.map(render_capability)
    |> string.join("\n")
  string.join(
    [conv_line, safety_line, cap_line, horizon_line, "", caps_header, cap_rows],
    "\n",
  )
}

fn render_capability(cap: CapabilityMetric) -> String {
  let trend_icon = case cap.trend {
    "up" -> visuals.with_color("^", "green")
    "down" -> visuals.with_color("v", "red")
    _ -> "-"
  }
  "    " <> cap.name <> ": " <> float.to_string(cap.score) <> " " <> trend_icon
}

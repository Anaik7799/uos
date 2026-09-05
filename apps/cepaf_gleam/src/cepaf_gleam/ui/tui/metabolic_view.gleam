/// TUI view for Metabolic plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/domain.{Critical, Degraded, Healthy, Unknown}
import cepaf_gleam/ui/lustre/metabolic.{type MetabolicModel}
import gleam/float
import gleam/string

pub fn render(model: MetabolicModel) -> String {
  let header = visuals.with_color("  METABOLIC", "cyan")
  let health = render_health(model)
  let energy = render_energy(model)
  let cpu = render_cpu(model)
  let sparkline = render_cpu_sparkline(model)
  string.join([header, health, "", energy, cpu, sparkline], "\n")
}

fn render_cpu_sparkline(model: MetabolicModel) -> String {
  let samples = [0.3, 0.4, 0.5, 0.45, 0.6, 0.55, 0.7, 0.65, model.cpu_load]
  "  CPU History: " <> visuals.render_sparkline(samples)
}

fn render_health(model: MetabolicModel) -> String {
  let status_text = case model.health {
    Healthy -> visuals.with_color("HEALTHY", "green")
    Degraded(reason) -> visuals.with_color("DEGRADED: " <> reason, "yellow")
    Critical(reason) -> visuals.with_color("CRITICAL: " <> reason, "red")
    Unknown -> visuals.with_color("UNKNOWN", "yellow")
  }
  "  Health: " <> status_text
}

fn render_energy(model: MetabolicModel) -> String {
  let ratio = metabolic.energy_ratio(model)
  let bar = visuals.render_progress_bar(ratio, 30)
  "  Energy: "
  <> float.to_string(model.energy)
  <> " / Set-point: "
  <> float.to_string(model.set_point)
  <> "\n  "
  <> bar
  <> " "
  <> float.to_string(ratio)
  <> "x"
}

fn render_cpu(model: MetabolicModel) -> String {
  let color = case model.cpu_load {
    l if l >. 0.9 -> "red"
    l if l >. 0.7 -> "yellow"
    _ -> "green"
  }
  let bar = visuals.render_progress_bar(model.cpu_load, 30)
  "  CPU: "
  <> visuals.with_color(float.to_string(model.cpu_load), color)
  <> "\n  "
  <> bar
}

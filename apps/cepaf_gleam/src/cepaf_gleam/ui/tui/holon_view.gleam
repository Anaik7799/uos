/// TUI view for Holon Registry plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/holon.{type HolonModel}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: HolonModel) -> String {
  let header = visuals.with_color("  HOLON REGISTRY", "cyan")
  let runtimes = render_runtimes(model)
  let layers = render_layers(model)
  let domains = render_domains(model)
  let uhis = render_uhis(model)
  let gleam = render_gleam(model)
  string.join([header, runtimes, layers, domains, uhis, gleam], "\n")
}

fn render_runtimes(model: HolonModel) -> String {
  "  Runtimes: "
  <> visuals.with_color(int.to_string(list.length(model.runtimes)), "blue")
}

fn render_layers(model: HolonModel) -> String {
  "  Layers: "
  <> visuals.with_color(int.to_string(list.length(model.layers)), "blue")
}

fn render_domains(model: HolonModel) -> String {
  "  Domains: "
  <> visuals.with_color(int.to_string(list.length(model.domains)), "blue")
}

fn render_uhis(model: HolonModel) -> String {
  let count = holon.total_uhis(model)
  let color = case count {
    0 -> "yellow"
    _ -> "green"
  }
  "  Active UHIs: " <> visuals.with_color(int.to_string(count), color)
}

fn render_gleam(model: HolonModel) -> String {
  let has = holon.has_gleam_holons(model)
  case has {
    True -> "  Gleam: " <> visuals.with_color("AVAILABLE", "green")
    False -> "  Gleam: " <> visuals.with_color("UNAVAILABLE", "red")
  }
}

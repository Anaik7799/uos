/// TUI view for Config Management plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/config.{type ConfigModel}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: ConfigModel) -> String {
  let header = visuals.with_color("  CONFIG MANAGEMENT", "cyan")
  let containers = render_containers(model)
  let networks = render_networks(model)
  let quorum = render_quorum(model)
  let validity = render_validity(model)
  let resources = render_resources(model)
  string.join([header, containers, networks, quorum, validity, resources], "\n")
}

fn render_containers(model: ConfigModel) -> String {
  "  Containers: "
  <> visuals.with_color(int.to_string(list.length(model.containers)), "blue")
}

fn render_networks(model: ConfigModel) -> String {
  "  Networks: "
  <> visuals.with_color(int.to_string(list.length(model.networks)), "blue")
}

fn render_quorum(model: ConfigModel) -> String {
  let met = config.quorum_met(model)
  let color = case met {
    True -> "green"
    False -> "yellow"
  }
  "  Quorum: "
  <> visuals.with_color(int.to_string(model.quorum_size), color)
  <> case met {
    True -> " " <> visuals.with_color("(met)", "green")
    False -> " " <> visuals.with_color("(unmet)", "yellow")
  }
}

fn render_validity(model: ConfigModel) -> String {
  case model.is_valid {
    True -> "  Validity: " <> visuals.with_color("VALID", "green")
    False -> "  Validity: " <> visuals.with_color("INVALID", "red")
  }
}

fn render_resources(model: ConfigModel) -> String {
  "  CPU: "
  <> int.to_string(model.total_cpu)
  <> "  Memory: "
  <> int.to_string(model.total_memory)
  <> " MB"
}

/// TUI view for Agent Hierarchy plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/agents.{type AgentsModel}
import gleam/float
import gleam/int
import gleam/string

pub fn render(model: AgentsModel) -> String {
  let header = visuals.with_color("  AGENT HIERARCHY", "cyan")
  let counts = render_counts(model)
  let efficiency = render_efficiency(model)
  let deadlock = render_deadlock(model)
  let compliance = render_compliance(model)
  string.join([header, counts, efficiency, deadlock, compliance], "\n")
}

fn render_counts(model: AgentsModel) -> String {
  "  "
  <> visuals.with_color("Exec:" <> int.to_string(model.executives), "magenta")
  <> " "
  <> visuals.with_color("Sup:" <> int.to_string(model.supervisors), "blue")
  <> " "
  <> visuals.with_color("Wrk:" <> int.to_string(model.workers), "green")
  <> "  Total: "
  <> int.to_string(model.total_agents)
}

fn render_efficiency(model: AgentsModel) -> String {
  let pct = float.round(model.efficiency *. 100.0)
  let color = case model.efficiency {
    e if e >=. 0.8 -> "green"
    e if e >=. 0.5 -> "yellow"
    _ -> "red"
  }
  "  Efficiency: " <> visuals.with_color(int.to_string(pct) <> "%", color)
}

fn render_deadlock(model: AgentsModel) -> String {
  case model.deadlock_detected {
    True -> "  Deadlock: " <> visuals.with_color("DETECTED", "red")
    False -> "  Deadlock: " <> visuals.with_color("NONE", "green")
  }
}

fn render_compliance(model: AgentsModel) -> String {
  let compliant = agents.is_compliant(model)
  let color = case compliant {
    True -> "green"
    False -> "red"
  }
  let label = case compliant {
    True -> "COMPLIANT"
    False -> "NON-COMPLIANT"
  }
  "  Compliance: " <> visuals.with_color(label, color)
}

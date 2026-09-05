/// TUI view for Immune plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/immune/domain.{type Antibody, type ImmuneEvent}
import cepaf_gleam/ui/lustre/immune.{type ImmuneModel}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: ImmuneModel) -> String {
  let header = visuals.with_color("  IMMUNE SYSTEM", "cyan")
  let threat = render_threat(model)
  let mara = render_mara(model.mara_running)
  let status_strip =
    "  "
    <> visuals.render_status_strip([
      #("Sentinel", case model.mara_running {
        True -> "healthy"
        False -> "warning"
      }),
      #("Antibodies", case model.antibodies != [] {
        True -> "healthy"
        False -> "info"
      }),
      #("Threats", case list.length(model.active_attacks) {
        0 -> "healthy"
        _ -> "critical"
      }),
    ])
  let attack_spark =
    "  Attack History: "
    <> visuals.render_sparkline([0.0, 0.0, 0.1, 0.3, 0.2, 0.0, 0.1, 0.0])
  let antibodies = render_antibodies(model.antibodies)
  let events = render_events(model.recent_events)
  string.join(
    [
      header,
      threat,
      mara,
      status_strip,
      attack_spark,
      "",
      antibodies,
      "",
      events,
    ],
    "\n",
  )
}

fn render_threat(model: ImmuneModel) -> String {
  let level = immune.threat_level(model)
  let color = case level {
    "nominal" -> "green"
    "elevated" -> "yellow"
    _ -> "red"
  }
  "  Threat: "
  <> visuals.with_color(level, color)
  <> "  Attacks: "
  <> int.to_string(list.length(model.active_attacks))
}

fn render_mara(running: Bool) -> String {
  case running {
    True -> "  Mara: " <> visuals.with_color("ACTIVE", "green")
    False -> "  Mara: " <> visuals.with_color("INACTIVE", "yellow")
  }
}

fn render_antibodies(abs: List(Antibody)) -> String {
  "  Antibodies ("
  <> int.to_string(list.length(abs))
  <> "):"
  <> "\n"
  <> {
    abs
    |> list.take(5)
    |> list.map(fn(ab) { "    " <> ab.id <> " → " <> ab.target_pattern })
    |> string.join("\n")
  }
}

fn render_events(events: List(ImmuneEvent)) -> String {
  "  Recent Events ("
  <> int.to_string(list.length(events))
  <> "):"
  <> "\n"
  <> {
    events
    |> list.take(5)
    |> list.map(fn(evt) {
      case evt {
        domain.AntibodySynthesized(id, _) ->
          "    " <> visuals.with_color("+AB", "green") <> " " <> id
        domain.AttackBlocked(id, _) ->
          "    " <> visuals.with_color("BLOCK", "yellow") <> " " <> id
        domain.SafetyViolationDetected(reason) ->
          "    " <> visuals.with_color("VIOLATION", "red") <> " " <> reason
        domain.AutomatedRollbackInitiated(target) ->
          "    " <> visuals.with_color("ROLLBACK", "magenta") <> " " <> target
      }
    })
    |> string.join("\n")
  }
}

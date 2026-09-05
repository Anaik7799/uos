/// TUI view for Device Health Grid (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/domain.{type DeviceHealth, Maintenance, Offline, Online}
import cepaf_gleam/ui/lustre/health_grid.{type HealthGridModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: HealthGridModel) -> String {
  let header = visuals.with_color("  DEVICE HEALTH GRID", "cyan")
  let summary = render_summary(model.devices)
  let device_list = render_device_list(model.devices)
  string.join([header, summary, "", device_list], "\n")
}

fn render_summary(devices: List(DeviceHealth)) -> String {
  let total = list.length(devices)
  let healthy = list.count(devices, fn(d) { d.health_score >. 0.8 })
  let degraded =
    list.count(devices, fn(d) {
      d.health_score <=. 0.8 && d.health_score >. 0.5
    })
  let critical = list.count(devices, fn(d) { d.health_score <=. 0.5 })

  "  "
  <> visuals.with_color("H:" <> int.to_string(healthy), "green")
  <> " "
  <> visuals.with_color("D:" <> int.to_string(degraded), "yellow")
  <> " "
  <> visuals.with_color("C:" <> int.to_string(critical), "red")
  <> "  Total: "
  <> int.to_string(total)
}

fn render_device_list(devices: List(DeviceHealth)) -> String {
  devices
  |> list.map(fn(d) {
    let status_str = case d.status {
      Online -> "ON"
      Offline -> "OFF"
      Maintenance -> "MAINT"
    }
    let status_color = case d.status {
      Online -> "green"
      Offline -> "red"
      Maintenance -> "yellow"
    }

    "  "
    <> pad_right(d.id, 12)
    <> " "
    <> visuals.with_color("[" <> status_str <> "]", status_color)
    <> " "
    <> visuals.render_progress_bar(d.health_score, 20)
    <> " "
    <> float_to_pct(d.health_score)
  })
  |> string.join("\n")
}

fn pad_right(str: String, width: Int) -> String {
  let len = string.length(str)
  case len >= width {
    True -> str
    False -> str <> string.repeat(" ", width - len)
  }
}

fn float_to_pct(f: Float) -> String {
  int.to_string(float.round(f *. 100.0)) <> "%"
}

/// Calculate overall health score from container statuses.
pub fn health_score(healthy: Int, total: Int) -> Float {
  case total {
    0 -> 0.0
    _ -> int.to_float(healthy) /. int.to_float(total)
  }
}

/// Health grade from score.
pub fn health_grade(score: Float) -> String {
  case score >=. 0.9 {
    True -> "A"
    False ->
      case score >=. 0.7 {
        True -> "B"
        False ->
          case score >=. 0.5 {
            True -> "C"
            False -> "D"
          }
      }
  }
}

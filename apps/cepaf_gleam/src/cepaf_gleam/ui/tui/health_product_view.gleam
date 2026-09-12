//// TUI view for Health Product (SC-GLM-UI-001, SC-GLM-UI-004).
//// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-BIO-EVO-001

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/health_product_page.{type HealthProductModel}
import gleam/float
import gleam/int
import gleam/string

pub fn render(model: HealthProductModel) -> String {
  let header = visuals.with_color("  BIOMORPHIC HEALTH PRODUCT", "cyan")
  let weather_color = case model.weather {
    "Clear" -> "green"
    "Partly Cloudy" -> "yellow"
    "Cloudy" -> "yellow"
    "Stormy" -> "red"
    _ -> "red"
  }
  let weather_line =
    "  Weather: "
    <> visuals.with_color(model.weather, weather_color)
  let product_line =
    "  Π(health) = "
    <> float.to_string(model.product)
    <> "  ("
    <> int.to_string(model.subsystem_count)
    <> " subsystems)"
  let status_line = case model.is_optimal {
    True -> "  Status: " <> visuals.with_color("OPTIMAL", "green")
    False ->
      case model.is_healthy {
        True -> "  Status: " <> visuals.with_color("HEALTHY", "green")
        False ->
          case model.is_alive {
            True -> "  Status: " <> visuals.with_color("DEGRADED", "yellow")
            False -> "  Status: " <> visuals.with_color("DEAD", "red")
          }
      }
  }
  let weakest_line =
    "  Weakest: "
    <> model.weakest_name
    <> " ("
    <> float.to_string(model.weakest_health)
    <> ")"
  let vitals = model.vitals_table
  let status_strip =
    "  "
    <> visuals.render_status_strip([
      #("Alive", case model.is_alive {
        True -> "healthy"
        False -> "critical"
      }),
      #("Healthy", case model.is_healthy {
        True -> "healthy"
        False -> "warning"
      }),
      #("Optimal", case model.is_optimal {
        True -> "healthy"
        False -> "info"
      }),
    ])
  string.join(
    [
      header,
      weather_line,
      product_line,
      status_line,
      weakest_line,
      "",
      "  Subsystem Vitals:",
      vitals,
      "",
      status_strip,
    ],
    "\n",
  )
}

//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/homeostasis_view</module></identity>
////   <fractal-topology><layer>L2_COMPONENT</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-MATH-003</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/homeostasis.{type HomeostasisModel}
import gleam/float
import gleam/int
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: HomeostasisModel) -> String {
  let header = visuals.with_color("  HOMEOSTASIS (L2 Component)", "cyan")
  let body = case model.loading {
    True -> "  Loading PID controller state..."
    False ->
      case model.error {
        Some(e) -> "  " <> visuals.with_color("ERROR: " <> e, "red")
        None -> render_state(model)
      }
  }
  string.join([header, body], "\n")
}

fn render_state(model: HomeostasisModel) -> String {
  let pid = model.pid
  let stable_line = case model.stable {
    True -> "  State:       " <> visuals.with_color("STABLE", "green")
    False -> "  State:       " <> visuals.with_color("CONVERGING", "yellow")
  }
  let convergence_bar =
    "  Convergence: "
    <> visuals.render_progress_bar(model.convergence_pct /. 100.0, 25)
    <> " "
    <> float.to_string(model.convergence_pct)
    <> "%"
  let convergence_line = convergence_bar
  let samples_line = "  Samples:     " <> int.to_string(model.sample_count)
  let pid_header = "  PID Controller:"
  let setpoint_line = "    Setpoint:  " <> float.to_string(pid.setpoint)
  let actual_line = "    Actual:    " <> float.to_string(pid.actual)
  let error_line =
    "    Error:     "
    <> visuals.with_color(float.to_string(pid.error), error_color(pid.error))
  let output_line = "    Output:    " <> float.to_string(pid.output)
  let gains_line =
    "    Gains:     Kp="
    <> float.to_string(pid.kp)
    <> " Ki="
    <> float.to_string(pid.ki)
    <> " Kd="
    <> float.to_string(pid.kd)
  string.join(
    [
      stable_line,
      convergence_line,
      samples_line,
      "",
      pid_header,
      setpoint_line,
      actual_line,
      error_line,
      output_line,
      gains_line,
    ],
    "\n",
  )
}

fn error_color(err: Float) -> String {
  let abs_err = case err <. 0.0 {
    True -> float.negate(err)
    False -> err
  }
  case abs_err <. 0.1 {
    True -> "green"
    False ->
      case abs_err <. 0.5 {
        True -> "yellow"
        False -> "red"
      }
  }
}

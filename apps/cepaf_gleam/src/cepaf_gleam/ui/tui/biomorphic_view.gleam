//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/biomorphic_view</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-BIO-EVO-001..007</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/symbiosis/tensor
import cepaf_gleam/symbiosis/types as symbiosis
import cepaf_gleam/ui/lustre/biomorphic.{
  type BiomorphicModel, type SubsystemHealth,
}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: BiomorphicModel) -> String {
  let header = visuals.with_color("  BIOMORPHIC (L5 Cognitive)", "cyan")
  let body = case model.loading {
    True -> "  Loading biomorphic subsystems..."
    False ->
      case model.error {
        Some(e) -> "  " <> visuals.with_color("ERROR: " <> e, "red")
        None -> render_state(model)
      }
  }
  string.join([header, body], "\n")
}

fn render_state(model: BiomorphicModel) -> String {
  let mode_line = "  Mode: " <> visuals.with_color(model.mode, "white")
  let overall_line =
    "  Overall: "
    <> visuals.with_color(
      float.to_string(model.overall_score),
      score_color(model.overall_score),
    )
  let bio_line = render_subsystem(model.bio)
  let neuro_line = render_subsystem(model.neuro)
  let immune_line = render_subsystem(model.immune)
  let status = case biomorphic.all_healthy(model) {
    True -> "  Status: " <> visuals.with_color("ALL NOMINAL", "green")
    False -> "  Status: " <> visuals.with_color("DEGRADED", "yellow")
  }
  let tensor_section = render_tensor(model.tensor)
  let symbiosis_section = render_symbiosis(model.symbiosis)
  string.join(
    [
      mode_line, overall_line, "",
      bio_line, neuro_line, immune_line, "",
      status, "",
      tensor_section, "",
      symbiosis_section,
    ],
    "\n",
  )
}

fn render_tensor(t: tensor.BiomorphicTensor) -> String {
  let header =
    "  "
    <> visuals.with_color("BIOMORPHIC TENSOR (7×8)", "cyan")
    <> "  Coverage: "
    <> visuals.with_color(
      float.to_string(t.coverage *. 100.0) <> "%",
      score_color(t.coverage),
    )
    <> "  Health: "
    <> visuals.with_color(
      float.to_string(t.health *. 100.0) <> "%",
      score_color(t.health),
    )
  let active = tensor.active_count(t)
  let missing = tensor.missing_count(t)
  let counts =
    "  Active: "
    <> int.to_string(active)
    <> "  Missing: "
    <> int.to_string(missing)
    <> "  Total: "
    <> int.to_string(list.length(t.cells))
  string.join([header, counts], "\n")
}

fn render_symbiosis(s: symbiosis.SymbiosisIndex) -> String {
  let header =
    "  "
    <> visuals.with_color("SYMBIOSIS INDEX (सहजीवन)", "cyan")
    <> "  Global: "
    <> visuals.with_color(
      float.to_string(s.global_index),
      case s.global_index >. 0.0 {
        True -> "green"
        False -> "red"
      },
    )
  let counts =
    "  Mutualism: "
    <> int.to_string(s.mutualism_count)
    <> "  Parasitism: "
    <> int.to_string(s.parasitism_count)
    <> "  Total: "
    <> int.to_string(s.total_count)
  let health = case symbiosis.is_healthy(s) {
    True -> "  Ecosystem: " <> visuals.with_color("MUTUALISTIC", "green")
    False -> "  Ecosystem: " <> visuals.with_color("PARASITIC", "red")
  }
  string.join([header, counts, health], "\n")
}

fn render_subsystem(s: SubsystemHealth) -> String {
  let color = status_color(s.status)
  "  "
  <> visuals.with_color(s.name, "white")
  <> ": "
  <> visuals.with_color(s.status, color)
  <> " ("
  <> float.to_string(s.score)
  <> ") "
  <> s.detail
}

fn status_color(status: String) -> String {
  case status {
    "healthy" -> "green"
    "degraded" -> "yellow"
    "critical" -> "red"
    _ -> "white"
  }
}

fn score_color(score: Float) -> String {
  case score >=. 0.8 {
    True -> "green"
    False ->
      case score >=. 0.5 {
        True -> "yellow"
        False -> "red"
      }
  }
}

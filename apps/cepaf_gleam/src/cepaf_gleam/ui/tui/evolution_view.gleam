//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/tui/evolution_view</module></identity>
////   <fractal-topology><layer>L5_COGNITIVE</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-EVO-001</stamp-controls></compliance>
//// </c3i-module>

import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/evolution.{type EvolutionModel}
import gleam/float
import gleam/int
import gleam/option.{None, Some}
import gleam/string

pub fn render(model: EvolutionModel) -> String {
  let header = visuals.with_color("  EVOLUTION (L5 Cognitive)", "cyan")
  let body = case model.loading {
    True -> "  Loading evolution metrics..."
    False ->
      case model.error {
        Some(e) -> "  " <> visuals.with_color("ERROR: " <> e, "red")
        None -> render_state(model)
      }
  }
  string.join([header, body], "\n")
}

fn render_state(model: EvolutionModel) -> String {
  let entropy_color = case evolution.entropy_healthy(model) {
    True -> "green"
    False -> "red"
  }
  let entropy_line =
    "  Shannon H:     "
    <> visuals.with_color(
      float.to_string(model.entropy) <> " bits",
      entropy_color,
    )
    <> " (gate: >= 2.5)"
  let entropy_spark =
    "  Entropy Trend: "
    <> visuals.render_sparkline([
      1.8,
      2.0,
      2.2,
      2.3,
      2.4,
      2.5,
      2.6,
      model.entropy,
    ])
  let fitness_bar =
    "  Fitness:       "
    <> visuals.render_progress_bar(model.fitness_score, 20)
    <> " "
    <> float.to_string(model.fitness_score)
  let cycle_line = "  Cycles:        " <> int.to_string(model.cycle_count)
  let gen_line = "  Generation:    " <> int.to_string(model.generation)
  let mutation_line =
    "  Mutation Rate: " <> float.to_string(model.mutation_rate)
  let last_line = "  Last Cycle:    " <> model.last_cycle
  string.join(
    [
      entropy_line,
      entropy_spark,
      fitness_bar,
      cycle_line,
      gen_line,
      mutation_line,
      last_line,
    ],
    "\n",
  )
}

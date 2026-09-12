// STAMP: SC-GLM-UI-001, SC-FRACTAL-001
import cepaf_gleam/ui/lustre/ruliology.{type RuliologyModel, type AutomatonState}
import gleam/list
import gleam/string

pub fn render(model: RuliologyModel) -> String {
  let header = "\u{001b}[1;36m▌ Ruliology Explorer\u{001b}[0m  Rule: " <> int_str(model.rule_number) <> " | Steps: " <> int_str(model.steps)
  let automata = list.map(model.automata, render_automaton) |> string.join("\n")
  header <> "\n" <> automata
}
fn render_automaton(a: AutomatonState) -> String {
  "  " <> a.name <> " [" <> a.current <> "] step " <> int_str(a.step_count)
}
@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String

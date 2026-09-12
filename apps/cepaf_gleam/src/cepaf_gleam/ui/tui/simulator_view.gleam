// STAMP: SC-GLM-UI-001, SC-SIM-001
import cepaf_gleam/ui/lustre/simulator.{type SimulatorModel}
import gleam/string

pub fn render(model: SimulatorModel) -> String {
  let header = "\u{001b}[1;36m▌ Simulator Browser\u{001b}[0m  Scenarios: " <> int_str(simulator.scenario_count(model)) <> " | Categories: " <> int_str(simulator.category_count(model))
  let status = case model.running { True -> "  \u{001b}[33mRUNNING...\u{001b}[0m" False -> "" }
  let response = case model.last_response { "" -> "" r -> "\n  Last: " <> string.slice(r, 0, 80) }
  header <> status <> response
}
@external(erlang, "erlang", "integer_to_binary")
fn int_str(i: Int) -> String

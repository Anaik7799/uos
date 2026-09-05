// STAMP: SC-GLM-UI-001, SC-FRACTAL-001
import cepaf_gleam/ui/lustre/ruliology.{type AutomatonState, type RuliologyModel}
import gleam/json

pub fn status_json(model: RuliologyModel) -> json.Json {
  json.object([
    #("rule_number", json.int(model.rule_number)),
    #("steps", json.int(model.steps)),
    #("automata", json.array(model.automata, automaton_json)),
  ])
}

fn automaton_json(a: AutomatonState) -> json.Json {
  json.object([
    #("name", json.string(a.name)),
    #("current", json.string(a.current)),
    #("step_count", json.int(a.step_count)),
    #("states", json.array(a.states, json.string)),
  ])
}

// STAMP: SC-GLM-UI-001, SC-SIM-001
import cepaf_gleam/ui/lustre/simulator.{type SimulatorModel, type Scenario}
import gleam/json

pub fn status_json(model: SimulatorModel) -> json.Json {
  json.object([
    #("scenario_count", json.int(simulator.scenario_count(model))),
    #("category_count", json.int(simulator.category_count(model))),
    #("running", json.bool(model.running)),
    #("last_response", json.string(model.last_response)),
    #("scenarios", json.array(model.scenarios, scenario_json)),
  ])
}
fn scenario_json(s: Scenario) -> json.Json {
  json.object([
    #("category", json.string(s.category)),
    #("text", json.string(s.text)),
    #("channel", json.string(s.channel)),
  ])
}

//// [C3I-SIL6-MSTS] Simulator browser — 400 test scenarios. STAMP: SC-GLM-UI-001, SC-SIM-001

import gleam/list
import gleam/option.{type Option, None, Some}

pub type Scenario { Scenario(category: String, text: String, channel: String, expected: String) }

pub type SimulatorModel {
  SimulatorModel(scenarios: List(Scenario), selected: Option(String), custom_text: String,
    last_response: String, running: Bool, error: Option(String))
}

pub type SimulatorMsg {
  ScenariosLoaded(List(Scenario))
  SelectScenario(String)
  SetCustomText(String)
  RunScenario
  ResponseReceived(String)
  RefreshSimulator
  ErrorReceived(String)
}

pub fn init() -> SimulatorModel {
  SimulatorModel(scenarios: [], selected: None, custom_text: "", last_response: "", running: False, error: None)
}

pub fn update(model: SimulatorModel, msg: SimulatorMsg) -> SimulatorModel {
  case msg {
    ScenariosLoaded(s) -> SimulatorModel(..model, scenarios: s)
    SelectScenario(id) -> SimulatorModel(..model, selected: Some(id))
    SetCustomText(t) -> SimulatorModel(..model, custom_text: t)
    RunScenario -> SimulatorModel(..model, running: True)
    ResponseReceived(r) -> SimulatorModel(..model, last_response: r, running: False)
    RefreshSimulator -> model
    ErrorReceived(e) -> SimulatorModel(..model, error: Some(e), running: False)
  }
}

pub fn scenario_count(model: SimulatorModel) -> Int { list.length(model.scenarios) }
pub fn category_count(model: SimulatorModel) -> Int {
  model.scenarios |> list.map(fn(s) { s.category }) |> list.unique |> list.length
}

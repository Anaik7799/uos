/// Lustre component for Config Management plane (SC-GLM-UI-001).
/// Manages container config, network topology, and resource validation.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/int
import gleam/list

pub type PiiPattern {
  PiiPattern(name: String, enabled: Bool, example: String)
}

pub type ConfigModel {
  ConfigModel(
    containers: List(String),
    networks: List(String),
    quorum_size: Int,
    is_valid: Bool,
    total_cpu: Int,
    total_memory: Int,
    // P3-5: PII scrubber config
    pii_patterns: List(PiiPattern),
    // P3-8: Inference model selector
    active_model: String,
    available_models: List(String),
  )
}

pub type ConfigMsg {
  ConfigLoaded
  ValidationRan(Bool)
  ContainerAdded(String)
  RefreshConfig
}

pub fn init() -> ConfigModel {
  ConfigModel(
    containers: [],
    networks: [],
    quorum_size: 3,
    is_valid: False,
    total_cpu: 0,
    total_memory: 0,
    pii_patterns: default_pii_patterns(),
    active_model: "gemini-3.1-flash-lite-preview",
    available_models: ["gemini-3.1-flash-lite-preview", "gemini-3-flash-preview", "gemma4", "gemma3", "rule-engine"],
  )
}

fn default_pii_patterns() -> List(PiiPattern) {
  [
    PiiPattern("email", True, "user@example.com"),
    PiiPattern("phone", True, "+1-555-0100"),
    PiiPattern("credit_card", True, "4111-1111-1111-1111"),
    PiiPattern("ssn", True, "123-45-6789"),
    PiiPattern("ip_address", True, "192.168.1.1"),
  ]
}

pub fn update(model: ConfigModel, msg: ConfigMsg) -> ConfigModel {
  case msg {
    ConfigLoaded -> model
    ValidationRan(valid) -> ConfigModel(..model, is_valid: valid)
    ContainerAdded(name) ->
      ConfigModel(..model, containers: [name, ..model.containers])
    RefreshConfig -> model
  }
}

pub fn quorum_met(model: ConfigModel) -> Bool {
  list.length(model.containers) >= model.quorum_size
}

pub fn resource_summary(model: ConfigModel) -> String {
  "CPU:"
  <> int.to_string(model.total_cpu)
  <> " MEM:"
  <> int.to_string(model.total_memory)
  <> "MB"
}

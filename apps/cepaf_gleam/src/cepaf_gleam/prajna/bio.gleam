//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/prajna/bio</module>
////   <fsharp-lineage>Cepaf.Prajna.Bio</fsharp-lineage></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology></c3i-module>

import gleam/list
import gleam/option.{type Option}

pub type Permeability {
  Closed
  Open
  Selective(allowed: List(String))
  EmergencyPerm
}

pub type HolonState {
  Dormant
  Awakening
  Active
  Stressed
  Healing
  Apoptotic
}

pub type VitalSigns {
  VitalSigns(health_index: Float, stress_index: Float, energy: Float)
}

pub type MembraneConfig {
  MembraneConfig(permeability: Permeability, blocked_sources: List(String))
}

pub type HolonInstance {
  HolonInstance(
    id: String,
    holon_type: String,
    state: HolonState,
    vitals: VitalSigns,
    membrane: MembraneConfig,
    parent_id: Option(String),
  )
}

pub fn create_holon(
  id: String,
  holon_type: String,
  parent_id: Option(String),
) -> HolonInstance {
  HolonInstance(
    id: id,
    holon_type: holon_type,
    state: Dormant,
    vitals: VitalSigns(1.0, 0.0, 1.0),
    membrane: default_membrane_config(),
    parent_id: parent_id,
  )
}

pub fn transition(
  holon: HolonInstance,
  target: HolonState,
) -> Result(HolonInstance, String) {
  let valid = case holon.state, target {
    Dormant, Awakening -> True
    Awakening, Active -> True
    Active, Stressed -> True
    Stressed, Healing -> True
    Healing, Active -> True
    Active, Apoptotic -> True
    Stressed, Apoptotic -> True
    _, _ -> False
  }
  case valid {
    True -> Ok(HolonInstance(..holon, state: target))
    False -> Error("Invalid transition")
  }
}

pub fn is_healthy(holon: HolonInstance) -> Bool {
  holon.vitals.health_index >. 0.5
  && holon.vitals.stress_index <. 0.8
  && holon.state == Active
}

pub fn can_pass(
  membrane: MembraneConfig,
  source: String,
  msg_type: String,
) -> Bool {
  case membrane.permeability {
    Closed -> False
    Open -> !list.contains(membrane.blocked_sources, source)
    Selective(allowed) -> list.contains(allowed, msg_type)
    EmergencyPerm -> msg_type == "emergency"
  }
}

pub fn default_membrane_config() -> MembraneConfig {
  MembraneConfig(Open, [])
}

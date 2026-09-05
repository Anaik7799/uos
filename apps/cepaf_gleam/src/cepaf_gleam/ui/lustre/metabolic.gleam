/// Lustre component for Metabolic plane (SC-GLM-UI-001).
/// Manages set-point tracking, energy levels, CPU load, and health state.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/ui/domain.{type HealthStatus, Healthy}

pub type MetabolicModel {
  MetabolicModel(
    set_point: Float,
    energy: Float,
    cpu_load: Float,
    health: HealthStatus,
  )
}

pub type MetabolicMsg {
  SetPointUpdated(Float)
  EnergyChanged(Float)
  HealthChanged(HealthStatus)
  RefreshMetabolic
}

pub fn init() -> MetabolicModel {
  MetabolicModel(set_point: 0.5, energy: 1.0, cpu_load: 0.0, health: Healthy)
}

pub fn update(model: MetabolicModel, msg: MetabolicMsg) -> MetabolicModel {
  case msg {
    SetPointUpdated(sp) -> MetabolicModel(..model, set_point: sp)
    EnergyChanged(e) -> MetabolicModel(..model, energy: e)
    HealthChanged(h) -> MetabolicModel(..model, health: h)
    RefreshMetabolic -> model
  }
}

pub fn energy_ratio(model: MetabolicModel) -> Float {
  case model.set_point >. 0.0 {
    True -> model.energy /. model.set_point
    False -> 0.0
  }
}

pub fn is_overloaded(model: MetabolicModel) -> Bool {
  model.cpu_load >. 0.9
}

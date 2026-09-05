/// Lustre component for Immune plane (SC-GLM-UI-001).
/// Imports from immune/domain.gleam — no type duplication (SC-GLM-UI-009).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/immune/domain.{
  type Antibody, type ChaosAttack, type ImmuneEvent,
}
import cepaf_gleam/ui/domain as ui_domain
import cepaf_gleam/ui/zenoh_otel
import gleam/list

pub type ImmuneModel {
  ImmuneModel(
    antibodies: List(Antibody),
    recent_events: List(ImmuneEvent),
    active_attacks: List(ChaosAttack),
    mara_running: Bool,
  )
}

pub type ImmuneMsg {
  AntibodyAdded(Antibody)
  EventReceived(ImmuneEvent)
  AttackDetected(ChaosAttack)
  AttackResolved(String)
  ToggleMara
  RefreshImmune
}

pub fn init() -> ImmuneModel {
  ImmuneModel(
    antibodies: [],
    recent_events: [],
    active_attacks: [],
    mara_running: False,
  )
}

pub fn update(model: ImmuneModel, msg: ImmuneMsg) -> ImmuneModel {
  zenoh_otel.emit(ui_domain.Immune, "update", zenoh_otel.Act)
  case msg {
    AntibodyAdded(ab) ->
      ImmuneModel(..model, antibodies: [ab, ..model.antibodies])
    EventReceived(evt) ->
      ImmuneModel(..model, recent_events: [evt, ..model.recent_events])
    AttackDetected(atk) ->
      ImmuneModel(..model, active_attacks: [atk, ..model.active_attacks])
    AttackResolved(_id) -> model
    ToggleMara -> ImmuneModel(..model, mara_running: !model.mara_running)
    RefreshImmune -> model
  }
}

pub fn threat_level(model: ImmuneModel) -> String {
  case list.length(model.active_attacks) {
    0 -> "nominal"
    n if n <= 2 -> "elevated"
    _ -> "critical"
  }
}

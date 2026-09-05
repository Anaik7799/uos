/// Lustre component for Holon Registry plane (SC-GLM-UI-001).
/// Tracks UHI registrations across runtimes, layers, domains, and types.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/list

pub type HolonModel {
  HolonModel(
    runtimes: List(String),
    layers: List(String),
    domains: List(String),
    holon_types: List(String),
    active_uhis: List(String),
  )
}

pub type HolonMsg {
  UhiRegistered(String)
  UhiRemoved(String)
  RefreshHolon
}

pub fn init() -> HolonModel {
  HolonModel(
    runtimes: ["gleam", "elixir", "rust", "fsharp"],
    layers: ["L0", "L1", "L2", "L3", "L4", "L5", "L6", "L7"],
    domains: ["immune", "metabolic", "cognitive", "substrate"],
    holon_types: ["actor", "sensor", "effector", "bridge"],
    active_uhis: [],
  )
}

pub fn update(model: HolonModel, msg: HolonMsg) -> HolonModel {
  case msg {
    UhiRegistered(uhi) ->
      HolonModel(..model, active_uhis: [uhi, ..model.active_uhis])
    UhiRemoved(uhi) ->
      HolonModel(
        ..model,
        active_uhis: list.filter(model.active_uhis, fn(u) { u != uhi }),
      )
    RefreshHolon -> model
  }
}

pub fn total_uhis(model: HolonModel) -> Int {
  list.length(model.active_uhis)
}

pub fn has_gleam_holons(model: HolonModel) -> Bool {
  list.contains(model.runtimes, "gleam")
}

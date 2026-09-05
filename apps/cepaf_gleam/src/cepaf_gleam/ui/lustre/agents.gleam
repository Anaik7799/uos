/// Lustre component for Agent Hierarchy plane (SC-GLM-UI-001).
/// Tracks agent counts, efficiency, and deadlock detection.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/ui/domain.{Agents}
import cepaf_gleam/ui/zenoh_otel
import gleam/int

pub type AgentsModel {
  AgentsModel(
    total_agents: Int,
    executives: Int,
    supervisors: Int,
    workers: Int,
    efficiency: Float,
    deadlock_detected: Bool,
  )
}

pub type AgentsMsg {
  HierarchyLoaded(Int, Int, Int, Int)
  EfficiencyUpdated(Float)
  DeadlockDetected(Bool)
  RefreshAgents
}

pub fn init() -> AgentsModel {
  AgentsModel(
    total_agents: 0,
    executives: 0,
    supervisors: 0,
    workers: 0,
    efficiency: 0.0,
    deadlock_detected: False,
  )
}

pub fn update(model: AgentsModel, msg: AgentsMsg) -> AgentsModel {
  zenoh_otel.emit(Agents, "update", zenoh_otel.Act)
  case msg {
    HierarchyLoaded(total, execs, sups, wrks) ->
      AgentsModel(
        ..model,
        total_agents: total,
        executives: execs,
        supervisors: sups,
        workers: wrks,
      )
    EfficiencyUpdated(eff) -> AgentsModel(..model, efficiency: eff)
    DeadlockDetected(detected) ->
      AgentsModel(..model, deadlock_detected: detected)
    RefreshAgents -> model
  }
}

pub fn is_compliant(model: AgentsModel) -> Bool {
  model.total_agents > 0 && !model.deadlock_detected && model.efficiency >=. 0.5
}

pub fn agent_summary(model: AgentsModel) -> String {
  "E:"
  <> int.to_string(model.executives)
  <> " S:"
  <> int.to_string(model.supervisors)
  <> " W:"
  <> int.to_string(model.workers)
}

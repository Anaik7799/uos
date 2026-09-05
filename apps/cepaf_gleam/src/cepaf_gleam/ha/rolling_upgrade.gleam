//// [C3I-SIL6-MSTS] <c3i-module><identity><module>cepaf_gleam/ha/rolling_upgrade</module></identity>
////   <fractal-topology><layer>L4_SYSTEM</layer></fractal-topology>
////   <compliance><stamp-controls>SC-HA-001, SC-SIL4-011</stamp-controls></compliance>
//// </c3i-module>
////
//// Rolling upgrade sequencer — zero-downtime N-node upgrades.

import gleam/list

pub type UpgradeState {
  Idle
  Planning
  Upgrading(
    current_node: String,
    remaining: List(String),
    completed: List(String),
  )
  Verifying(node: String)
  RollingBack(node: String, reason: String)
  Complete(nodes_upgraded: Int)
}

pub type UpgradeStep {
  DrainNode(zid: String)
  WaitDrain(zid: String, max_ms: Int)
  StopNode(zid: String)
  DeployBinary(zid: String, version: String)
  StartNode(zid: String)
  VerifyHealth(zid: String)
  ResumeTraffic(zid: String)
}

pub type UpgradeModel {
  UpgradeModel(
    state: UpgradeState,
    target_version: String,
    steps_completed: List(UpgradeStep),
    errors: List(String),
  )
}

pub fn init() -> UpgradeModel {
  UpgradeModel(state: Idle, target_version: "", steps_completed: [], errors: [])
}

/// Plan upgrade for N nodes — Backup first, Primary last
pub fn plan(
  model: UpgradeModel,
  nodes: List(String),
  version: String,
) -> UpgradeModel {
  // Sort: Primary last (upgrade order = reverse importance)
  let ordered = list.reverse(nodes)
  case ordered {
    [] -> model
    [first, ..rest] ->
      UpgradeModel(
        ..model,
        state: Upgrading(current_node: first, remaining: rest, completed: []),
        target_version: version,
      )
  }
}

/// Advance to next node after successful verification
pub fn advance(model: UpgradeModel) -> UpgradeModel {
  case model.state {
    Upgrading(current, remaining, completed) ->
      case remaining {
        [] -> UpgradeModel(..model, state: Complete(list.length(completed) + 1))
        [next, ..rest] ->
          UpgradeModel(
            ..model,
            state: Upgrading(current_node: next, remaining: rest, completed: [
              current,
              ..completed
            ]),
          )
      }
    _ -> model
  }
}

/// Rollback current node on failure
pub fn rollback(model: UpgradeModel, reason: String) -> UpgradeModel {
  case model.state {
    Upgrading(current, _, _) ->
      UpgradeModel(..model, state: RollingBack(current, reason), errors: [
        reason,
        ..model.errors
      ])
    _ -> model
  }
}

/// Check if upgrade is complete
pub fn is_complete(model: UpgradeModel) -> Bool {
  case model.state {
    Complete(_) -> True
    _ -> False
  }
}

/// Generate upgrade steps for a single node
pub fn steps_for_node(zid: String, version: String) -> List(UpgradeStep) {
  [
    DrainNode(zid),
    WaitDrain(zid, 30_000),
    StopNode(zid),
    DeployBinary(zid, version),
    StartNode(zid),
    VerifyHealth(zid),
    ResumeTraffic(zid),
  ]
}

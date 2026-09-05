//// [C3I-SIL6-MSTS] MODULE CONTRACT
//// <c3i-module>
////   <identity><module>cepaf_gleam/ui/lustre/bicameral</module></identity>
////   <fractal-topology><layer>L0_CONSTITUTIONAL</layer></fractal-topology>
////   <compliance><stamp-controls>SC-GLM-UI-001, SC-GLM-UI-002, SC-CONSENSUS-001, SC-SIL4-006</stamp-controls></compliance>
//// </c3i-module>
////
//// Lustre MVU component for the Bicameral page.
//// Displays 2oo3 voting chamber status, veto history, consensus timeline.

import gleam/option.{type Option, None, Some}

pub type Chamber {
  Chamber(name: String, vote: String, timestamp: String, veto_count: Int)
}

pub type BicameralModel {
  BicameralModel(
    guardian: Chamber,
    sentinel: Chamber,
    cortex: Chamber,
    consensus_reached: Bool,
    total_decisions: Int,
    total_vetoes: Int,
    loading: Bool,
    error: Option(String),
  )
}

pub type BicameralMsg {
  StateLoaded(
    guardian: Chamber,
    sentinel: Chamber,
    cortex: Chamber,
    decisions: Int,
    vetoes: Int,
  )
  VoteReceived(chamber: String, vote: String, timestamp: String)
  ConsensusReached(Bool)
  RefreshBicameral
  ErrorReceived(String)
}

pub fn init() -> BicameralModel {
  BicameralModel(
    guardian: Chamber(
      name: "Guardian",
      vote: "pending",
      timestamp: "",
      veto_count: 0,
    ),
    sentinel: Chamber(
      name: "Sentinel",
      vote: "pending",
      timestamp: "",
      veto_count: 0,
    ),
    cortex: Chamber(
      name: "Cortex",
      vote: "pending",
      timestamp: "",
      veto_count: 0,
    ),
    consensus_reached: False,
    total_decisions: 0,
    total_vetoes: 0,
    loading: True,
    error: None,
  )
}

pub fn update(model: BicameralModel, msg: BicameralMsg) -> BicameralModel {
  case msg {
    StateLoaded(g, s, c, d, v) ->
      BicameralModel(
        guardian: g,
        sentinel: s,
        cortex: c,
        consensus_reached: check_consensus(g, s, c),
        total_decisions: d,
        total_vetoes: v,
        loading: False,
        error: None,
      )
    VoteReceived(chamber, vote, ts) -> {
      let m = case chamber {
        "guardian" ->
          BicameralModel(
            ..model,
            guardian: Chamber(..model.guardian, vote: vote, timestamp: ts),
          )
        "sentinel" ->
          BicameralModel(
            ..model,
            sentinel: Chamber(..model.sentinel, vote: vote, timestamp: ts),
          )
        "cortex" ->
          BicameralModel(
            ..model,
            cortex: Chamber(..model.cortex, vote: vote, timestamp: ts),
          )
        _ -> model
      }
      BicameralModel(
        ..m,
        consensus_reached: check_consensus(m.guardian, m.sentinel, m.cortex),
      )
    }
    ConsensusReached(v) -> BicameralModel(..model, consensus_reached: v)
    RefreshBicameral -> BicameralModel(..model, loading: True)
    ErrorReceived(e) -> BicameralModel(..model, error: Some(e), loading: False)
  }
}

fn check_consensus(g: Chamber, s: Chamber, c: Chamber) -> Bool {
  let approvals = count_approvals([g.vote, s.vote, c.vote], 0)
  approvals >= 2
}

fn count_approvals(votes: List(String), acc: Int) -> Int {
  case votes {
    [] -> acc
    ["approve", ..rest] -> count_approvals(rest, acc + 1)
    [_, ..rest] -> count_approvals(rest, acc)
  }
}

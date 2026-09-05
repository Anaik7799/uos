/// Lustre component for Git Analytics plane (SC-GLM-UI-001).
/// Tracks commit analysis, health scoring, and ICP compliance.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import gleam/float

pub type GitModel {
  GitModel(
    commit_types: List(String),
    health_score: Float,
    total_commits: Int,
    icp_compliance: Float,
  )
}

pub type GitMsg {
  AnalysisLoaded(Float, Float)
  CommitParsed
  RefreshGit
}

pub fn init() -> GitModel {
  GitModel(
    commit_types: [],
    health_score: 0.0,
    total_commits: 0,
    icp_compliance: 0.0,
  )
}

pub fn update(model: GitModel, msg: GitMsg) -> GitModel {
  case msg {
    AnalysisLoaded(health, compliance) ->
      GitModel(..model, health_score: health, icp_compliance: compliance)
    CommitParsed -> GitModel(..model, total_commits: model.total_commits + 1)
    RefreshGit -> model
  }
}

pub fn is_healthy(model: GitModel) -> Bool {
  model.health_score >=. 0.7
}

pub fn style_summary(model: GitModel) -> String {
  "health:"
  <> float.to_string(model.health_score)
  <> " icp:"
  <> float.to_string(model.icp_compliance)
}

/// TUI view for Git Analytics plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/git.{type GitModel}
import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: GitModel) -> String {
  let header = visuals.with_color("  GIT ANALYTICS", "cyan")
  let types = render_commit_types(model)
  let health = render_health(model)
  let commits = render_commits(model)
  let icp = render_icp(model)
  string.join([header, types, health, commits, icp], "\n")
}

fn render_commit_types(model: GitModel) -> String {
  "  Commit Types: "
  <> visuals.with_color(int.to_string(list.length(model.commit_types)), "blue")
}

fn render_health(model: GitModel) -> String {
  let score_pct = float.round(model.health_score *. 100.0)
  let color = case model.health_score {
    s if s >=. 0.8 -> "green"
    s if s >=. 0.5 -> "yellow"
    _ -> "red"
  }
  "  Health: " <> visuals.with_color(int.to_string(score_pct) <> "%", color)
}

fn render_commits(model: GitModel) -> String {
  "  Total Commits: " <> int.to_string(model.total_commits)
}

fn render_icp(model: GitModel) -> String {
  let pct = float.round(model.icp_compliance *. 100.0)
  let color = case model.icp_compliance {
    c if c >=. 0.9 -> "green"
    c if c >=. 0.7 -> "yellow"
    _ -> "red"
  }
  "  ICP Compliance: " <> visuals.with_color(int.to_string(pct) <> "%", color)
}

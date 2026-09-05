/// TUI view for Planning plane (SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007).
/// Same command set as Wisp API (SC-GLM-UI-007). Renders via cockpit/visuals.gleam.
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-004, SC-GLM-UI-007
import cepaf_gleam/cockpit/visuals
import cepaf_gleam/ui/lustre/planning.{type PlanningModel, type PlanningTask}
import gleam/int
import gleam/list
import gleam/string

pub fn render(model: PlanningModel) -> String {
  let header = visuals.with_color("  PLANNING", "cyan")
  let counts = render_counts(model.tasks)
  let task_list = render_task_list(planning.filtered_tasks(model))
  string.join([header, counts, "", task_list], "\n")
}

fn render_counts(tasks: List(PlanningTask)) -> String {
  let p = planning.task_count_by_status(tasks, "pending")
  let ip = planning.task_count_by_status(tasks, "in_progress")
  let c = planning.task_count_by_status(tasks, "completed")
  let b = planning.task_count_by_status(tasks, "blocked")
  "  "
  <> visuals.with_color("P:" <> int.to_string(p), "yellow")
  <> " "
  <> visuals.with_color("IP:" <> int.to_string(ip), "blue")
  <> " "
  <> visuals.with_color("C:" <> int.to_string(c), "green")
  <> " "
  <> visuals.with_color("B:" <> int.to_string(b), "red")
  <> "  Total: "
  <> int.to_string(list.length(tasks))
}

fn render_task_list(tasks: List(PlanningTask)) -> String {
  tasks
  |> list.take(15)
  |> list.map(fn(t) {
    let status_color = case t.status {
      "pending" -> "yellow"
      "in_progress" -> "blue"
      "completed" -> "green"
      "blocked" -> "red"
      _ -> ""
    }
    "  "
    <> visuals.with_color("[" <> t.status <> "]", status_color)
    <> " "
    <> t.id
    <> " "
    <> t.title
  })
  |> string.join("\n")
}

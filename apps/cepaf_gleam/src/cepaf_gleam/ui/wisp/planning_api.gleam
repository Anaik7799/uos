/// Wisp API for Planning plane (SC-GLM-UI-001, SC-GLM-UI-003).
/// Typed JSON via gleam/json — no raw strings (SC-GLM-UI-003).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-003, SC-GLM-UI-007
import gleam/json
import gleam/list

pub type TaskSummary {
  TaskSummary(id: String, title: String, status: String, priority: String)
}

pub fn list_tasks_json(tasks: List(TaskSummary)) -> String {
  json.object([
    #("plane", json.string("planning")),
    #("count", json.int(list.length(tasks))),
    #("tasks", json.array(tasks, encode_task)),
  ])
  |> json.to_string()
}

pub fn task_detail_json(task: TaskSummary) -> String {
  json.object([
    #("plane", json.string("planning")),
    #("task", encode_task(task)),
  ])
  |> json.to_string()
}

pub fn status_summary_json(
  pending: Int,
  in_progress: Int,
  completed: Int,
  blocked: Int,
) -> String {
  json.object([
    #("plane", json.string("planning")),
    #("pending", json.int(pending)),
    #("in_progress", json.int(in_progress)),
    #("completed", json.int(completed)),
    #("blocked", json.int(blocked)),
    #("total", json.int(pending + in_progress + completed + blocked)),
  ])
  |> json.to_string()
}

fn encode_task(task: TaskSummary) -> json.Json {
  json.object([
    #("id", json.string(task.id)),
    #("title", json.string(task.title)),
    #("status", json.string(task.status)),
    #("priority", json.string(task.priority)),
  ])
}

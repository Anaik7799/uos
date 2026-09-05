/// Lustre component for Planning plane (SC-GLM-UI-001).
/// Imports from planning domain — no type duplication (SC-GLM-UI-009).
/// STAMP: SC-GLM-UI-001, SC-GLM-UI-002, SC-GLM-UI-009
import cepaf_gleam/ui/domain.{Planning}
import cepaf_gleam/ui/zenoh_otel
import gleam/list
import gleam/option.{None, Some}

pub type PlanningModel {
  PlanningModel(
    tasks: List(PlanningTask),
    filter: TaskFilter,
    selected_id: option.Option(String),
  )
}

pub type PlanningTask {
  PlanningTask(
    id: String,
    title: String,
    status: String,
    priority: String,
    owner: option.Option(String),
  )
}

pub type TaskFilter {
  AllTasks
  PendingOnly
  InProgressOnly
  CompletedOnly
  BlockedOnly
}

pub type PlanningMsg {
  SetFilter(TaskFilter)
  SelectTask(String)
  RefreshTasks
  TasksLoaded(List(PlanningTask))
}

pub fn init() -> PlanningModel {
  PlanningModel(tasks: [], filter: AllTasks, selected_id: None)
}

pub fn update(model: PlanningModel, msg: PlanningMsg) -> PlanningModel {
  zenoh_otel.emit(Planning, "update", zenoh_otel.Act)
  case msg {
    SetFilter(f) -> PlanningModel(..model, filter: f)
    SelectTask(id) -> PlanningModel(..model, selected_id: Some(id))
    RefreshTasks -> model
    TasksLoaded(tasks) -> PlanningModel(..model, tasks: tasks)
  }
}

pub fn filtered_tasks(model: PlanningModel) -> List(PlanningTask) {
  case model.filter {
    AllTasks -> model.tasks
    PendingOnly -> list.filter(model.tasks, fn(t) { t.status == "pending" })
    InProgressOnly ->
      list.filter(model.tasks, fn(t) { t.status == "in_progress" })
    CompletedOnly -> list.filter(model.tasks, fn(t) { t.status == "completed" })
    BlockedOnly -> list.filter(model.tasks, fn(t) { t.status == "blocked" })
  }
}

pub fn task_count_by_status(tasks: List(PlanningTask), status: String) -> Int {
  list.filter(tasks, fn(t) { t.status == status }) |> list.length
}

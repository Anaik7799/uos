open Core

module Store = Sa_plan_store

type task = {
  task : Store.task_view;
  estimate_points : int option;
  lease_until_ns : int64 option;
  dependencies : string list;
  selection : Store.selection_evidence option;
  ready : bool;
}

type budgets = {
  estimated_points : int;
  completed_points : int;
  retry_capacity_remaining : int;
  lease_budget_remaining_ns : int64;
}

type metrics = {
  leased_tasks : int;
  retrying_jobs : int;
  active_workflows : int;
  dependency_edges : int;
}

type safety = {
  observation_state : string;
  evidence_tasks : int;
  unevidenced_tasks : int;
  max_stpa : int option;
  max_fema : int option;
}

type workflow = Store.workflow_view

type t = {
  generated_at_ns : int64;
  read_only : bool;
  plan : Store.plan_view;
  summary : Store.summary;
  tasks : task list;
  jobs : Store.job_view list;
  workflows : workflow list;
  budgets : budgets;
  metrics : metrics;
  safety : safety;
}

val observe :
  Store.t -> plan_id:string -> now_ns:int64 -> (t, string) Result.t

val to_yojson : t -> Yojson.Safe.t
val to_text : t -> string
val publish : path:string -> t -> (unit, string) Result.t

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

let job_state_text = function
  | Store.Job_available -> "available"
  | Job_executing -> "executing"
  | Job_retry -> "retry"
  | Job_completed -> "completed"
  | Job_discarded -> "discarded"
  | Job_cancelled -> "cancelled"

let observe store ~plan_id ~now_ns =
  Result.bind (Store.find_plan store ~id_or_name:plan_id) ~f:(function
    | None -> Error ("Unknown Sa-plan plan: " ^ plan_id)
    | Some plan ->
        Result.bind (Store.summary store ~plan_id:plan.id) ~f:(fun summary ->
          Result.bind (Store.list_task_observations store ~plan_id:plan.id)
            ~f:(fun observed_tasks ->
              Result.bind (Store.list_jobs store ~queue:None) ~f:(fun jobs ->
                Result.map (Store.list_workflows store) ~f:(fun workflows ->
                  let states =
                    List.fold observed_tasks ~init:String.Map.empty
                      ~f:(fun states observed ->
                        Map.set states ~key:observed.task.id
                          ~data:observed.task.state)
                  in
                  let tasks =
                    List.map observed_tasks ~f:(fun observed ->
                      let dependencies_complete =
                        List.for_all observed.dependencies ~f:(fun id ->
                          Map.find states id
                          |> Option.value_map ~default:false
                               ~f:(String.equal "completed"))
                      in
                      { task = observed.task;
                        estimate_points = observed.estimate_points;
                        lease_until_ns = observed.lease_until_ns;
                        dependencies = observed.dependencies;
                        selection = observed.selection;
                        ready = String.equal observed.task.state "available"
                                && dependencies_complete })
                  in
                  let estimated_points =
                    List.sum (module Int) tasks ~f:(fun task ->
                      Option.value task.estimate_points ~default:0)
                  and completed_points =
                    List.sum (module Int) tasks ~f:(fun task ->
                      if String.equal task.task.state "completed" then
                        Option.value task.estimate_points ~default:0
                      else 0)
                  and retry_capacity_remaining =
                    List.sum (module Int) jobs ~f:(fun job ->
                      match job.state with
                      | Store.Job_completed | Job_discarded | Job_cancelled -> 0
                      | Job_available | Job_executing | Job_retry ->
                          Int.max 0 (job.max_attempts - job.attempt))
                  and lease_budget_remaining_ns =
                    List.fold tasks ~init:0L ~f:(fun total task ->
                      match task.lease_until_ns with
                      | None -> total
                      | Some deadline ->
                          Int64.(total + max 0L (deadline - now_ns)))
                  in
                  let evidence =
                    List.filter_map tasks ~f:(fun task -> task.selection)
                  in
                  let maximum factor = List.max_elt ~compare:Int.compare factor in
                  { generated_at_ns = now_ns;
                    read_only = true;
                    plan;
                    summary;
                    tasks;
                    jobs;
                    workflows;
                    budgets =
                      { estimated_points; completed_points;
                        retry_capacity_remaining; lease_budget_remaining_ns };
                    metrics =
                      { leased_tasks =
                          List.count tasks ~f:(fun task ->
                            Option.is_some task.lease_until_ns);
                        retrying_jobs =
                          List.count jobs ~f:(fun job ->
                            Poly.equal job.state Store.Job_retry);
                        active_workflows =
                          List.count workflows ~f:(fun workflow ->
                            String.equal workflow.state "running");
                        dependency_edges =
                          List.sum (module Int) tasks ~f:(fun task ->
                            List.length task.dependencies) };
                    safety =
                      { observation_state = "selection_evidence_only";
                        evidence_tasks = List.length evidence;
                        unevidenced_tasks = List.length tasks - List.length evidence;
                        max_stpa = maximum (List.map evidence ~f:(fun item -> item.factors.stpa));
                        max_fema = maximum (List.map evidence ~f:(fun item -> item.factors.fema)) } })))))

let option_json f = function None -> `Null | Some value -> f value
let int64_json value = `Intlit (Int64.to_string value)

let factors_json (factors : Store.selection_factors) =
  `Assoc
    [ "stpa", `Int factors.Store.stpa;
      "fema", `Int factors.fema;
      "criticality", `Int factors.criticality;
      "dependency", `Int factors.dependency;
      "standards", `Int factors.standards;
      "agent_fit", `Int factors.agent_fit ]

let selection_json (selection : Store.selection_evidence) =
  `Assoc
    [ "actor", `String selection.Store.actor;
      "old_priority", option_json (fun value -> `Int value) selection.old_priority;
      "new_priority", `Int selection.new_priority;
      "factors", factors_json selection.factors;
      "rationale", `String selection.rationale;
      "recorded_at_ns", int64_json selection.recorded_at_ns ]

let task_json (observed : task) =
  let task = observed.task in
  `Assoc
    [ "id", `String task.Store.id;
      "name", `String task.name;
      "title", `String task.title;
      "parent_id", option_json (fun value -> `String value) task.parent_id;
      "state", `String task.state;
      "priority", `Int task.priority;
      "worker", option_json (fun value -> `String value) task.worker;
      "attempt", `Int task.attempt;
      "estimate_points", option_json (fun value -> `Int value) observed.estimate_points;
      "lease_until_ns", option_json int64_json observed.lease_until_ns;
      "dependencies", `List (List.map observed.dependencies ~f:(fun id -> `String id));
      "ready", `Bool observed.ready;
      "safety_selection", option_json selection_json observed.selection ]

let job_json (job : Store.job_view) =
  `Assoc
    [ "id", `String job.Store.id;
      "name", `String job.name;
      "queue", `String job.queue;
      "worker", `String job.worker;
      "state", `String (job_state_text job.state);
      "attempt", `Int job.attempt;
      "max_attempts", `Int job.max_attempts;
      "available_at_ns", int64_json job.available_at_ns;
      "lease_owner", option_json (fun value -> `String value) job.lease_owner;
      "lease_until_ns", option_json int64_json job.lease_until_ns;
      "result", option_json (fun value -> `String value) job.result ]

let event_json (event : Store.workflow_event) =
  `Assoc
    [ "sequence", `Int event.Store.sequence;
      "kind", `String event.kind;
      "payload", `String event.payload;
      "occurred_at_ns", int64_json event.occurred_at_ns ]

let workflow_json (workflow : workflow) =
  `Assoc
    [ "id", `String workflow.Store.id;
      "name", `String workflow.name;
      "kind", `String workflow.kind;
      "input", `String workflow.input;
      "state", `String workflow.state;
      "result", option_json (fun value -> `String value) workflow.result;
      "created_at_ns", int64_json workflow.created_at_ns;
      "completed_at_ns", option_json int64_json workflow.completed_at_ns;
      "events", `List (List.map workflow.events ~f:event_json) ]

let to_yojson snapshot =
  `Assoc
    [ "generated_at_ns", int64_json snapshot.generated_at_ns;
      "read_only", `Bool snapshot.read_only;
      "plan",
      `Assoc [ "id", `String snapshot.plan.id;
               "name", `String snapshot.plan.name;
               "title", `String snapshot.plan.title ];
      "summary",
      `Assoc [ "total", `Int snapshot.summary.total;
               "completed", `Int snapshot.summary.completed;
               "ready", `Int snapshot.summary.ready;
               "executing", `Int snapshot.summary.executing ];
      "tasks", `List (List.map snapshot.tasks ~f:task_json);
      "jobs", `List (List.map snapshot.jobs ~f:job_json);
      "workflows", `List (List.map snapshot.workflows ~f:workflow_json);
      "budgets",
      `Assoc [ "estimated_points", `Int snapshot.budgets.estimated_points;
               "completed_points", `Int snapshot.budgets.completed_points;
               "retry_capacity_remaining", `Int snapshot.budgets.retry_capacity_remaining;
               "lease_budget_remaining_ns", int64_json snapshot.budgets.lease_budget_remaining_ns ];
      "metrics",
      `Assoc [ "leased_tasks", `Int snapshot.metrics.leased_tasks;
               "retrying_jobs", `Int snapshot.metrics.retrying_jobs;
               "active_workflows", `Int snapshot.metrics.active_workflows;
               "dependency_edges", `Int snapshot.metrics.dependency_edges ];
      "safety",
      `Assoc [ "observation_state", `String snapshot.safety.observation_state;
               "evidence_tasks", `Int snapshot.safety.evidence_tasks;
               "unevidenced_tasks", `Int snapshot.safety.unevidenced_tasks;
               "max_stpa", option_json (fun value -> `Int value) snapshot.safety.max_stpa;
               "max_fema", option_json (fun value -> `Int value) snapshot.safety.max_fema ] ]

let to_text snapshot =
  let buffer = Buffer.create 2048 in
  Printf.bprintf buffer
    "sa-plan %s read-only=%b total=%d ready=%d executing=%d completed=%d\n"
    snapshot.plan.name snapshot.read_only snapshot.summary.total
    snapshot.summary.ready snapshot.summary.executing snapshot.summary.completed;
  Printf.bprintf buffer
    "budgets points=%d/%d retry-capacity=%d lease-remaining-ns=%Ld\n"
    snapshot.budgets.completed_points snapshot.budgets.estimated_points
    snapshot.budgets.retry_capacity_remaining
    snapshot.budgets.lease_budget_remaining_ns;
  Printf.bprintf buffer
    "metrics leased-tasks=%d retrying-jobs=%d active-workflows=%d dependency-edges=%d\n"
    snapshot.metrics.leased_tasks snapshot.metrics.retrying_jobs
    snapshot.metrics.active_workflows snapshot.metrics.dependency_edges;
  Printf.bprintf buffer "safety state=%s evidence=%d unevidenced=%d\n"
    snapshot.safety.observation_state snapshot.safety.evidence_tasks
    snapshot.safety.unevidenced_tasks;
  List.iter snapshot.tasks ~f:(fun observed ->
    Printf.bprintf buffer
      "task %s state=%s ready=%b worker=%s lease=%s attempts=%d dependencies=[%s]\n"
      observed.task.name observed.task.state observed.ready
      (Option.value observed.task.worker ~default:"-")
      (Option.value_map observed.lease_until_ns ~default:"-" ~f:Int64.to_string)
      observed.task.attempt (String.concat ~sep:"," observed.dependencies));
  List.iter snapshot.jobs ~f:(fun job ->
    Printf.bprintf buffer
      "job %s queue=%s state=%s attempts=%d/%d lease-owner=%s lease=%s\n"
      job.name job.queue (job_state_text job.state) job.attempt job.max_attempts
      (Option.value job.lease_owner ~default:"-")
      (Option.value_map job.lease_until_ns ~default:"-" ~f:Int64.to_string));
  List.iter snapshot.workflows ~f:(fun workflow ->
    Printf.bprintf buffer "workflow %s kind=%s state=%s events=%d\n"
      workflow.name workflow.kind workflow.state (List.length workflow.events));
  Buffer.contents buffer

let publish ~path snapshot =
  let temporary = path ^ ".tmp" in
  try
    let content = to_yojson snapshot |> Yojson.Safe.pretty_to_string in
    Out_channel.write_all temporary ~data:(content ^ "\n");
    Stdlib.Sys.rename temporary path;
    Ok ()
  with exn ->
    if Stdlib.Sys.file_exists temporary then Stdlib.Sys.remove temporary;
    Error (Exn.to_string exn)

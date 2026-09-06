(** Sa-plan read-only KPI projection (cp-12-observability).

    Semantic domain: see sa_plan_observability_kpi.mli — [snapshot] is a pure
    counting-monoid fold over the Store's read views at an explicit [now_ns];
    it partitions the plan's task set by state, partitions executing tasks by
    lease liveness, and reports the most-overdue executing lease age. It is
    REPORT-ONLY and fail-closed: unknown plan ids and store read errors are
    [Error], and no Store-mutating API is ever called. *)

module Store = Sa_plan.Store

type kpi = {
  plan_id : string;
  total : int;
  completed : int;
  available : int;
  executing : int;
  blocked_or_other : int;
  lease_live : int;
  lease_expired : int;
  jobs_pending : int;
  workflows_open : int;
  oldest_executing_age_ns : int64 option;
}

let ( let* ) result f = match result with Ok v -> f v | Error e -> Error e

let is_state name (observation : Store.task_observation) =
  String.equal observation.task.state name

(* Lease deadline of an executing task; a missing lease denotes deadline 0
   (infinitely overdue — fail-closed against silent stalls). *)
let lease_deadline (observation : Store.task_observation) =
  match observation.lease_until_ns with Some deadline -> deadline | None -> 0L

let snapshot store ~plan_id ~now_ns =
  let* plan = Store.find_plan store ~id_or_name:plan_id in
  match plan with
  | None -> Error (Printf.sprintf "unknown plan_id (fail-closed): %s" plan_id)
  | Some plan ->
      let plan_id = plan.Store.id in
      let* observations = Store.list_task_observations store ~plan_id in
      let* jobs = Store.list_jobs store ~queue:None in
      let* workflows = Store.list_workflows store in
      let count pred =
        List.fold_left (fun acc o -> if pred o then acc + 1 else acc) 0
          observations
      in
      let total = List.length observations in
      let completed = count (is_state "completed") in
      let available = count (is_state "available") in
      let executing = count (is_state "executing") in
      let blocked_or_other = total - completed - available - executing in
      let lease_live =
        count (fun o ->
            is_state "executing" o
            && Int64.compare (lease_deadline o) now_ns > 0)
      in
      let lease_expired = executing - lease_live in
      let oldest_executing_age_ns =
        List.fold_left
          (fun acc o ->
            if not (is_state "executing" o) then acc
            else
              let overdue = Int64.sub now_ns (lease_deadline o) in
              let overdue =
                if Int64.compare overdue 0L < 0 then 0L else overdue
              in
              match acc with
              | None -> Some overdue
              | Some previous ->
                  Some
                    (if Int64.compare overdue previous > 0 then overdue
                     else previous))
          None observations
      in
      let jobs_pending =
        List.fold_left
          (fun acc (job : Store.job_view) ->
            match job.state with
            | Job_available | Job_executing | Job_retry -> acc + 1
            | Job_completed | Job_discarded | Job_cancelled -> acc)
          0 jobs
      in
      let workflows_open =
        List.fold_left
          (fun acc (workflow : Store.workflow_view) ->
            match workflow.completed_at_ns with
            | None -> acc + 1
            | Some _ -> acc)
          0 workflows
      in
      Ok
        {
          plan_id;
          total;
          completed;
          available;
          executing;
          blocked_or_other;
          lease_live;
          lease_expired;
          jobs_pending;
          workflows_open;
          oldest_executing_age_ns;
        }

let escape_json_string value =
  let buffer = Buffer.create (String.length value + 2) in
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string buffer "\\\""
      | '\\' -> Buffer.add_string buffer "\\\\"
      | '\n' -> Buffer.add_string buffer "\\n"
      | '\r' -> Buffer.add_string buffer "\\r"
      | '\t' -> Buffer.add_string buffer "\\t"
      | c when Char.code c < 0x20 ->
          Buffer.add_string buffer (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char buffer c)
    value;
  Buffer.contents buffer

let to_json kpi =
  Printf.sprintf
    "{\"plan_id\":\"%s\",\"total\":%d,\"completed\":%d,\"available\":%d,\
     \"executing\":%d,\"blocked_or_other\":%d,\"lease_live\":%d,\
     \"lease_expired\":%d,\"jobs_pending\":%d,\"workflows_open\":%d,\
     \"oldest_executing_age_ns\":%s}"
    (escape_json_string kpi.plan_id)
    kpi.total kpi.completed kpi.available kpi.executing kpi.blocked_or_other
    kpi.lease_live kpi.lease_expired kpi.jobs_pending kpi.workflows_open
    (match kpi.oldest_executing_age_ns with
    | None -> "null"
    | Some age -> Int64.to_string age)

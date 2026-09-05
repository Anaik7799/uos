(** Registration only: no worker, shell invocation, task completion, or external
    effect is dispatched. Existing OCaml sources and tests are never written. *)
val plan_id : string
val workflow_id : string
val queue : string
val nodes : Sa_plan.Management.plan_node list
val specification : Yojson.Basic.t

(** Entire plan/workflow/job registration is atomic. Exact replay preserves
    identities and histories; graph or immutable-input drift is an error. *)
val materialize :
  Sa_plan.Store.t -> now_ns:int64 -> (Yojson.Basic.t, string) result

(** Observe persisted task dependencies, jobs and workflow events, without
    claiming tasks/jobs or completing any work. *)
val observe : Sa_plan.Store.t -> (Yojson.Basic.t, string) result

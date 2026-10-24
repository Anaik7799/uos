(** Bounded exact target observation for a cancellation proposal. Read-only data,
    never approval or effect authority. Exact controller binding, current task,
    bridge and target lease are observed in one transaction after lock acquisition.
    Private job arguments/results are neither selected nor returned. *)
type t
val decode : string -> (t,string) result
val execute_observed : Sa_plan_store.t -> t -> observe_now:(unit -> int64) -> (Yojson.Safe.t,string) result

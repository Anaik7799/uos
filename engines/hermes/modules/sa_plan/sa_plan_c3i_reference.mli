open Core

type verdict = Verified | Rejected_by_policy | Unavailable_observed
[@@deriving compare, equal]

type row = {
  id : string;
  surface : string;
  reference_observation : string;
  ocaml_observation : string;
  verdict : verdict;
  reason : string;
  sources : string list;
}

type report = row list

val corpus : row list
val normalize_task_state : dependencies_ready:bool -> string -> string
val normalize_job_state : Sa_plan_store.job_state -> string
val retry_delay_ns : attempt:int -> int64
val evaluate_store : Sa_plan_store.t -> now_ns:int64 -> (report, string) Result.t
val find_verdict : report -> string -> verdict option
val report_to_yojson : report -> Yojson.Safe.t
val publish : path:string -> report -> (unit, string) Result.t

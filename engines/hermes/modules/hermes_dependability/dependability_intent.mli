(** Closed, declarative dependability intent authority.

    This module is pure.  It exposes validated policies and intents but no
    process, SQLite, scheduler, transport, or filesystem operation. *)

type target =
  | Sqlite_run_event_store
  | Sqlite_sa_plan_store
  | Sqlite_ops_completion_history
  | Sqlite_evidence_store

type plane = Control_plane | Data_plane | Both_planes

type operation = Prove_lifecycle | Verify_reliability | Verify_full

type success_predicate =
  | Exit_zero
  | No_signal
  | Metric_at_least of string * int64
  | No_matching_crash

type criterion = private {
  id : string;
  description : string;
  predicate : success_predicate;
}

type source_authority = {
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
  build_digest : string;
  provenance_digest : string;
}

type reliability_schedule = private {
  sequential_oracle_attempts : int;
  bounded_parallel_attempts : int;
  lane_count : int;
  permit_topology_digest : string;
}

type policy = private {
  confidence_ppm : int;
  maximum_incident_rate_ppm : int;
  attempts : int;
  per_child_timeout_ns : int64;
  maximum_failures : int;
  minimum_overlap_gc_cycles : int;
  reliability_schedule : reliability_schedule;
  require_formal : bool;
  require_crash_window : bool;
  require_full_gate : bool;
}

type t = private {
  request_id : string;
  activity_id : string;
  run_id : string;
  operation : operation;
  activity_path : Ops_capability.coordinate list;
  target : target;
  plane : plane;
  policy : policy;
  criteria : criterion list;
  source : source_authority;
}

val all_targets : target list

val target_id : target -> string
(*@ id = target_id target
    pure
    ensures id <> "" *)

val target_coordinate : target -> string
(*@ coordinate = target_coordinate target
    pure
    ensures coordinate <> "" *)

val target_hazards : target -> string list
(*@ hazards = target_hazards target
    pure *)

val target_sources : target -> string list
(*@ sources = target_sources target
    pure *)

val required_attempts :
  confidence_ppm:int -> maximum_incident_rate_ppm:int -> (int, string) result
(*@ required = required_attempts ~confidence_ppm ~maximum_incident_rate_ppm
    pure *)

val make_reliability_schedule :
  sequential_oracle_attempts:int ->
  bounded_parallel_attempts:int ->
  lane_count:int ->
  (reliability_schedule, string) result
(*@ checked = make_reliability_schedule ~sequential_oracle_attempts
      ~bounded_parallel_attempts ~lane_count
    pure *)

val make_policy :
  confidence_ppm:int ->
  maximum_incident_rate_ppm:int ->
  attempts:int ->
  per_child_timeout_ns:int64 ->
  maximum_failures:int ->
  minimum_overlap_gc_cycles:int ->
  reliability_schedule:reliability_schedule ->
  require_formal:bool ->
  require_crash_window:bool ->
  require_full_gate:bool ->
  unit ->
  (policy, string) result
(*@ checked = make_policy ~confidence_ppm ~maximum_incident_rate_ppm ~attempts
      ~per_child_timeout_ns ~maximum_failures ~minimum_overlap_gc_cycles
      ~reliability_schedule ~require_formal ~require_crash_window
      ~require_full_gate ()
    pure *)

val make_criterion :
  id:string ->
  description:string ->
  predicate:success_predicate ->
  (criterion, string) result
(*@ checked = make_criterion ~id ~description ~predicate
    pure *)

val make :
  request_id:string ->
  activity_id:string ->
  run_id:string ->
  operation:operation ->
  activity_path:Ops_capability.coordinate list ->
  target:target ->
  plane:plane ->
  policy:policy ->
  criteria:criterion list ->
  source:source_authority ->
  (t, string) result
(*@ checked = make ~request_id ~activity_id ~run_id ~operation ~activity_path
      ~target ~plane ~policy ~criteria ~source
    pure *)

val request_id : t -> string
val activity_id : t -> string
val run_id : t -> string
val operation : t -> operation
val activity_path_of_intent : t -> Ops_capability.coordinate list
val target : t -> target
val plane : t -> plane
val policy_of_intent : t -> policy
val criteria : t -> criterion list
val source : t -> source_authority

val attempts : policy -> int
val maximum_failures : policy -> int
val maximum_parallelism : policy -> int
val reliability_schedule : policy -> reliability_schedule
val sequential_oracle_attempts : reliability_schedule -> int
val bounded_parallel_attempts : reliability_schedule -> int
val lane_count : reliability_schedule -> int
val sequential_attempt_ids : reliability_schedule -> int list
val parallel_attempt_ids : reliability_schedule -> int list
val all_attempt_ids : reliability_schedule -> int list
val parallel_lane_partitions : reliability_schedule -> int list list
val permit_topology_digest : reliability_schedule -> string
val per_child_timeout_ns : policy -> int64
val minimum_overlap_gc_cycles : policy -> int
val require_formal : policy -> bool
val require_crash_window : policy -> bool
val require_full_gate : policy -> bool

val canonical_json : t -> string
(*@ json = canonical_json intent
    pure
    ensures json <> "" *)

val digest : t -> string
(*@ hash = digest intent
    pure
    ensures String.length hash = 64 *)

val target_digest : t -> string
val policy_digest : t -> string
val criteria_digest : t -> string
val source_digest : t -> string
val operations_for_target : target -> operation list
val ops_planes : plane -> Ops_capability.plane list

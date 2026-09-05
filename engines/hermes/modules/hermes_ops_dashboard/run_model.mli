(** Closed, canonical run-event carrier. Run lifecycle is intentionally distinct
    from [Ops_capability.lifecycle]; promotion into governance completion is an
    explicit later admission boundary. *)

type phase =
  | Admission
  | Authority_preflight
  | Discovery
  | Build
  | Dispatch
  | Suite_execution
  | Aggregation
  | Completion_admission
  | Publication

type lifecycle =
  | Declared
  | Admitted
  | Running
  | Aggregating
  | Succeeded
  | Failed
  | Cancelled
  | Blocked
  | Unavailable

type subject =
  | Run
  | Phase of phase
  | Suite of string
  | Attempt of string * int
  | Resource of string
  | Safety_gate of string
  | Intelligence_gate of string
  | Analysis of string
  | Trace_span of string
  | Profile of string
  | Command of string
  | Receipt of string
  | Residual of string

type availability = Measured | Unavailable_observed of string

type event_kind =
  | Run_declared
  | Run_started
  | Run_finished
  | Phase_started
  | Phase_finished
  | Suite_discovered
  | Suite_started
  | Suite_finished
  | Swarm_step_ready
  | Swarm_step_running
  | Swarm_step_terminal
  | Resource_sampled
  | Diagnostic_emitted
  | Safety_evaluated
  | Intelligence_evaluated
  | Analysis_recorded
  | Trace_recorded
  | Profile_recorded
  | Fast_path_selected
  | Command_observed
  | Receipt_admitted
  | Residual_recorded
  | Heartbeat

type plane = Ops_capability.plane = Control_plane | Data_plane

type provenance = {
  source_revision : string;
  source_clean : bool;
  configuration_digest : string;
  authority_digest : string;
  executable_digest : string;
}

type event = private {
  run_id : string;
  sequence : int64;
  event_id : string;
  kind : event_kind;
  subject : subject;
  plane : plane;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  occurred_at_ns : int64;
  monotonic_at_ns : int64;
  provenance : provenance;
  payload : Yojson.Safe.t;
  previous_digest : string option;
  digest : string;
}

val make :
  run_id:string -> sequence:int64 -> event_id:string -> kind:event_kind ->
  subject:subject -> plane:plane -> coordinate:Ops_capability.coordinate ->
  rca_origin:Ops_capability.rca_origin -> occurred_at_ns:int64 ->
  monotonic_at_ns:int64 -> provenance:provenance -> payload:Yojson.Safe.t ->
  previous_digest:string option -> (event, string) result
(*@ ensures match result with
    | Ok event -> event.run_id = run_id /\ event.sequence = sequence /\
                  event.event_id = event_id /\ String.length event.digest = 64
    | Error _ -> true *)

val to_json : event -> Yojson.Safe.t
val of_json : Yojson.Safe.t -> (event, string) result
val digest : event -> string
(*@ ensures String.length result = 64 *)

val canonical_json : Yojson.Safe.t -> (Yojson.Safe.t, string) result
val canonical_string : Yojson.Safe.t -> (string, string) result
val validate_head : run_id:string -> provenance:provenance -> (unit, string) result
val equal_provenance : provenance -> provenance -> bool
val string_of_lifecycle : lifecycle -> string
val lifecycle_of_string : string -> (lifecycle, string) result
val terminal_lifecycle : lifecycle -> bool

type stage =
  | Decode
  | Validate
  | Materialize
  | Discover
  | Acquire
  | Zk
  | Wiki
  | Render
  | Publish
  | Report

type status =
  | Started
  | Completed of { duration_ms : int }
  | Skipped of { reason : string; duration_ms : int }
  | Failed of { message : string; duration_ms : int }

type measurement = {
  work_items : int option;
  bytes : int option;
  domains : int option;
  wiki_notes : int option;
  artifacts : int option;
}

type event

type summary = {
  events : event list;
  started_count : int;
  terminal_count : int;
  failed_count : int;
  work_items_total : int;
  bytes_total : int;
  duration_ms_total : int;
  max_domains : int;
  max_wiki_notes : int option;
  max_artifacts : int option;
}

type violation
type budget_violation

val make :
  sequence:int ->
  timestamp_ns:int64 ->
  stage:stage ->
  status:status ->
  measurement:measurement ->
  unit ->
  event

val empty_measurement : measurement
val fold : event list -> summary
val violations : summary -> violation list
val violation_name : violation -> string
val stage_budget_ms : stage -> int
val warm_path_budget_ms : int
val within_warm_path_budget : duration_ms:int -> bool
val budget_violations : summary -> budget_violation list
val budget_violation_name : budget_violation -> string
val render_tui : event list -> string
val render_dashboard : title:string -> summary -> string
val render_metrics : summary -> Yojson.Safe.t
val render_otel_file : trace_id:string -> event list -> Yojson.Safe.t
val preserve_bundle_violations : 'a list -> summary -> 'a list
val event_stage : event -> stage
val event_status : event -> status
val stage_name : stage -> string

type availability
type exact_head_receipt

val partial : string -> availability
val unavailable_observed : string -> availability
val verified : exact_head_receipt -> availability

type programme_summary = {
  registered_nodes : int;
  total_nodes : int;
  tasks_ready : int;
  tasks_waiting : int;
  tasks_executing : int;
  tasks_completed : int;
  lifecycle_projection_running : bool;
  recovery_projection_jobs : int;
}

type snapshot

val make_snapshot :
  public_url:string ->
  timestamp:string ->
  programme:programme_summary ->
  bridge:availability ->
  fpp:availability ->
  formal:availability ->
  browser:availability ->
  canonical_bridge_calls:int ->
  residual_direct_calls:int ->
  knowledge_artifacts:int ->
  snapshot

val validate_snapshot : snapshot -> string list
val validate_public_url : string -> (unit, string) result
val validate_tailscale_fqdn : string -> (unit, string) result
val validate_timestamp : string -> (unit, string) result

val get_recent_history :
  Sqlite3.db -> ((string * string * string * string) list, string) result

val observe_snapshot :
  (unit -> ('a, string) result) -> ('a, string) result

val render_dashboard :
  snapshot -> (string * string * string * string) list -> string

val port_from_environment :
  getenv:(string -> string option) -> (int, string) result

type request_resolution = Dashboard | Dashboard_style | Not_found | Method_not_allowed
val resolve_request : method_name:string -> target:string -> request_resolution

val dashboard_style : string

val start_server :
  port:int -> db_path:string ->
  snapshot:(unit -> (snapshot, string) result) -> unit

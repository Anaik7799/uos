(** SQLite-backed boundary for graph snapshots and durable workspace commands.

    This module is the only persistence surface used by Dream. It talks to
    SQLite exclusively through the harness [Db] actor. *)

type context = {
  id : string;
  title : string;
  kind : string;
  updated_at : string;
  node_count : int;
  edge_count : int;
}

type job = {
  id : int;
  command : string;
  state : string;
  requested_by : string;
  role : string;
  attempts : int;
  max_attempts : int;
  inserted_at : string;
  updated_at : string;
  error : string option;
  result : Yojson.Safe.t option;
}

type work_item = { job : job; args : Yojson.Safe.t }

val ensure_schema : Db.t -> unit
val load_system_graph : Db.t -> Graph_intelligence.t
val snapshot_system_graph : Db.t -> Graph_intelligence.t -> string
val save_graph : Db.t -> source_kind:string -> Graph_intelligence.t -> string
val save_text_graph :
  Db.t -> source_uri:string -> text:string -> Graph_intelligence.t -> string
val load_graph : Db.t -> string -> Graph_intelligence.t option
val list_contexts : Db.t -> context list
val contexts_to_yojson : context list -> Yojson.Safe.t
val enqueue :
  Db.t ->
  command:string ->
  args:Yojson.Safe.t ->
  requested_by:string ->
  role:string ->
  idempotency_key:string option ->
  (job, string) result
val get_job : Db.t -> int -> job option
val job_to_yojson : job -> Yojson.Safe.t
val claim_next : Db.t -> work_item option
val finish_job :
  Db.t -> id:int -> (Yojson.Safe.t, string) result -> job option
val recover_stale_jobs : Db.t -> int

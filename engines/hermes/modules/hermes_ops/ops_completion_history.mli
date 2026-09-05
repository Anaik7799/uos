type t

type counts = { receipts : int; observations : int; interactions : int }

type interaction_kind = Prompt | Agent_message | Command | Decision | Residual

type interaction = {
  interaction_id : string;
  run_id : string;
  actor : string;
  kind : interaction_kind;
  body : string;
  recorded_at_ns : int64;
}

val open_store : Dependability_sqlite_location.reference -> (t, string) result
val close : t -> unit
val record : t -> Ops_observability.event -> Ops_command.receipt -> (unit, string) result
val append_interaction : t -> interaction -> (unit, string) result
val counts : t -> (counts, string) result
val receipt_is_current :
  t -> source:Ops_observability.source_context -> receipt_digest:string -> (bool, string) result

val has_current_success :
  t ->
  source:Ops_observability.source_context ->
  action:string ->
  scope:string ->
  (bool, string) result

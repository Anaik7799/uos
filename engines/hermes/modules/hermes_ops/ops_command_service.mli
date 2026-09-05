val default_history_location : Dependability_sqlite_location.reference

(** The durable orientation memory (R30): pass history and key state. *)
val default_orientation_path : string

val dispatch :
  ?root:string ->
  ?history_location:Dependability_sqlite_location.reference ->
  execute:Ops_command.executor ->
  surface:Ops_command.surface ->
  Ops_command.request ->
  (Ops_command.observation, string) result

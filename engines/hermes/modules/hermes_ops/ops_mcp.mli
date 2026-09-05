val handle :
  ?dispatcher:Ops_command.dispatcher ->
  execute:Ops_command.executor -> Yojson.Safe.t -> (Yojson.Safe.t option, string) result
val serve : ?dispatcher:Ops_command.dispatcher -> execute:Ops_command.executor -> unit -> unit

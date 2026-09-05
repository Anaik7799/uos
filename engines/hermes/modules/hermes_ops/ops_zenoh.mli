val command_keyexpr : string
val handle : ?dispatcher:Ops_command.dispatcher -> execute:Ops_command.executor -> key:string -> payload:string ->
  unit -> (string, string) result
val serve : ?dispatcher:Ops_command.dispatcher -> execute:Ops_command.executor -> unit -> (unit, string) result

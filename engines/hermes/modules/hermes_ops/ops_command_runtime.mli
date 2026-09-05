val execute_direct : Ops_command.executor
val execute : Ops_command.executor
val metrics_json : unit -> Yojson.Safe.t
val debug_integration_gaps : unit -> string list
val invocation_action : string -> Ops_command.action option

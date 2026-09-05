(** Finite test-only fixture authority for the process owner.

    A capability identifies a fixed fixture/fault profile only.  It contains
    no executable path, argv, environment, cwd, callback, or effect handle. *)

type fixture = Exit_zero | Exit_nonzero | Timeout | Signal | Output_bound

type capability

val all_fixtures : fixture list
val key : fixture -> string
val declare : fixture -> capability
val fixture : capability -> fixture

(** A fixed non-executable production declaration used only to prove that the
    production owner refuses before registered target resolution. *)
val unavailable_production_declaration :
  unit -> Dependability_process_protocol.declaration

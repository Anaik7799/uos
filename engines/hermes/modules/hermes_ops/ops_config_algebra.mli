(** Fractal functional algebra for declarative configuration.  The same
    fail-closed join applies to an element, layer, subsystem, and whole-system
    roll-up; the empty denominator is explicitly [Unmapped]. *)

type resolution =
  | Supplied
  | Defaulted
  | Optional_unavailable
  | Required_blocked

type completion = Unmapped | Verified | Partial | Blocked

val resolve : present:bool -> Ops_config.necessity -> resolution
val completion_of_resolution : resolution -> completion
val combine : completion -> completion -> completion
val roll_up : completion list -> completion
val schema_id : string
val declaration_digest : Ops_config.element list -> string
val binds_execution_intent :
  configuration_digest:string -> context_configuration_digest:string -> bool
val validate : unit -> (unit, string) result

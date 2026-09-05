type node_kind = Declaration | Command | Surface | Activity | Receipt | Criterion | Metric | Model
type node = { node_id : string; kind : node_kind; obligation_id : string }
type relation = Declares | Projects | Executes | Produces | Satisfies | Measures | Models
type edge = { source : string; relation : relation; target : string }

val nodes : node list
val edges : edge list
val validate : unit -> string list
val paths_to_criterion : string -> string list list

val lifecycle_leq : Ops_capability.lifecycle -> Ops_capability.lifecycle -> bool
type parity_admission = Grant | Block | Deny
val admit_parity :
  level:Ops_capability.level -> evidence:Ops_capability.evidence ->
  origin:Ops_capability.rca_origin -> divergent:bool -> parity_admission
val surface_homomorphism : Ops_command.receipt list -> bool
val ooda_closed : Ops_capability.ooda_phase list -> bool
val semantic_denominator : unit -> (string * Ops_capability.coordinate) list
val formal_smt2 : unit -> string

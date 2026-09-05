(** Fractal functional paths derived from the declarative configuration
    ontology.  Every configuration declaration reaches evidence only through
    validation, exact digest binding, assurance, and [Run_swarm_bridge]. *)

type edge_kind =
  | Declares
  | Supplies
  | Consumes
  | Observes
  | Validates
  | Derives
  | Binds
  | Admits
  | Executes
  | Emits

type edge = { source : string; target : string; kind : edge_kind }

val schema_id : string
val declaration_digest : string
val kind_name : edge_kind -> string
val edges : edge list
val predecessors : string -> string list
val paths_to_receipt : string -> string list list
val can_reach : string -> string -> bool
val validate_edges : edge list -> (unit, string) result
val validate : unit -> (unit, string) result

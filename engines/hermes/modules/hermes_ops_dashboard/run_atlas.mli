(** Continuous bounded atlas for admission, evidence, and observational
    projection. Projection paths never flow into completion admission. *)

type edge_kind =
  | Admission_flow
  | Evidence_flow
  | Projection_flow
  | Observation_flow
  | Planned_flow
type edge = { source : string; target : string; kind : edge_kind }

val edges : edge list
val validate_edges : edge list -> (unit, string) result
val validate : unit -> (unit, string) result
val paths_to_criterion : string -> string list list
val has_edge : string -> string -> bool
val has_active_edge : string -> string -> bool
val can_reach : string -> string -> bool
val can_reach_available : string -> string -> bool

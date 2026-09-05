(** Executable L0-L6/LX ontology for the Zellij integration. *)

type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX

type kind =
  | Workspace
  | Capability
  | Session
  | Contract
  | Projection
  | Runtime
  | Receipt
  | Controller

type lifecycle =
  | Declared
  | Implemented
  | Tested
  | Live_observed
  | Current
  | Unavailable_observed

type rca_origin =
  | Specification
  | Implementation
  | Environment
  | Evidence
  | Control

type node

val nodes : node list
val find : string -> node option
val validate : unit -> string list
val validate_nodes : node list -> string list
val id : node -> string
val parent_id : node -> string option
val level : node -> level
val kind : node -> kind
val carrier : node -> string
val operations : node -> string list
val observations : node -> string list
val invariants : node -> string list
val hazards : node -> string list
val sources : node -> string list
val lifecycle : node -> lifecycle
val rca_origin : node -> rca_origin
val implementation_paths : node -> string list
val test_paths : node -> string list
val residuals : node -> string list
val with_parent : node -> string option -> node
val level_name : level -> string
val kind_name : kind -> string
val lifecycle_name : lifecycle -> string

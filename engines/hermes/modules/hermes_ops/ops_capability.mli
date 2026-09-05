type kind = Rule | Skill | Superpower | Agent | Capability | Sop | Activity

type plane = Control_plane | Data_plane

type surface = Ocaml_api | Cli | Mcp | Zenoh

type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX

type ooda_phase = Observe | Orient | Decide | Act

type lifecycle = Declared | Implemented | Executed | Current

type rca_origin = Specification | Implementation | Environment | Evidence | Control

type evidence = Structural | Functional | Differential | Formal | Mutation | Resource | Publication

type implementation = Judgment_only of string | Command of string

type applicability = Applicable | Not_applicable of string

type coordinate = { level : level; phase : ooda_phase }

type declaration = {
  id : string;
  kind : kind;
  purpose : string;
  authority : string;
  owner : string;
  dependencies : string list;
  path : coordinate list;
  implementation : implementation;
  evidence : evidence list;
  plane : plane;
  surfaces : (surface * applicability) list;
  projections : string list;
}

val all : declaration list
val rule_titles : (string * string) list
val rule_ids : unit -> string list
val declaration_digest : declaration list -> string
val source_digest : string

val string_of_kind : kind -> string
val string_of_plane : plane -> string
val string_of_surface : surface -> string
val string_of_level : level -> string
val string_of_phase : ooda_phase -> string
val string_of_lifecycle : lifecycle -> string
val string_of_rca_origin : rca_origin -> string

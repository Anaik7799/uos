(** Operations/runtime ontology kept explicitly separate from the L0-L6
    evidence fractal while reusing its eleven engineering aspects. *)

type fractal = Operations_runtime | Evidence_chain
type coverage = Fractal_ontology.coverage = Addressed of string | Not_applicable of string
type lifecycle =
  | Operations_run of Run_model.lifecycle
  | Governance_declaration of Ops_capability.lifecycle

type availability =
  | Available
  | Unavailable_observed of string
  | Planned of string

type authority = Executable | Projection | Oracle | Report_only
type rule_engine = Not_rule_engine | Naive_forward_chainer | Rete_ul_engine
type aspect_evidence =
  | Implemented_observed of string
  | Applicable_unverified of string
  | Planned_unavailable of string

type component = {
  id : string;
  module_path : string;
  purpose : string;
  level : Ops_capability.level;
  fractal : fractal;
  availability : availability;
  authority : authority;
  rule_engine : rule_engine;
  substantiated_aspects : Fractal_ontology.aspect list;
  aspect_evidence : (Fractal_ontology.aspect * aspect_evidence) list;
  coverage : (Fractal_ontology.aspect * coverage) list;
}

val all : component list
val components : string list
val find : string -> component option
val validate_components : component list -> (unit, string) result
val validate : unit -> (unit, string) result

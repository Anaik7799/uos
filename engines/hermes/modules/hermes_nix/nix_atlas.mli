(** Comprehensive functional atlas for Nix, Determinate Systems, and Devenv.
    Maps operations, capability domains, preconditions, postconditions, and failure envelopes. *)

type domain =
  | Substrate_domain
  | Evaluation_domain
  | Flake_domain
  | Security_domain
  | Devenv_domain
  | Supervision_domain
  | Intent_bridge_domain

type capability = {
  name : string;
  domain : domain;
  ontology_level : Nix_ontology.level;
  read_only : bool;
  preconditions : string list;
  postconditions : string list;
  failure_modes : string list;
}

val domain_to_string : domain -> string
val all_capabilities : capability list
val find_capability : string -> capability option
val capabilities_by_domain : domain -> capability list
val to_yojson : capability -> Yojson.Safe.t

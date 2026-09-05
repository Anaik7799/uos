(** Closed catalog of declared Nix and Devenv operations with metadata,
    risk profiles, and declaration keys. *)

type t =
  | Ping_daemon
  | Eval_flake_attr
  | Eval_raw_expr
  | Build_flake_attr
  | Build_derivation
  | Flake_lock
  | Flake_audit
  | Flake_bom
  | Store_verify
  | Store_gc
  | Devenv_shell
  | Devenv_up
  | Devenv_test
  | Devenv_build
  | Devenv_gc
  | Devenv_info

type declaration = {
  key : string;
  description : string;
  read_only : bool;
  ontology_level : Nix_ontology.level;
}

val all : t list
val declaration : t -> declaration
val find : string -> t option
val declaration_is_safe : t -> bool

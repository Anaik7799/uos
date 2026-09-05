(** Equational laws, semilattices, and algebraic signatures for Nix closures,
    Flake lock compositions, and Devenv module overlays. *)

module Closure_set : sig
  type t
  val empty : t
  val singleton : Nix_id.Store_path.t -> t
  val union : t -> t -> t
  val inter : t -> t -> t
  val subset : t -> t -> bool
  val equal : t -> t -> bool
  val size : t -> int
  val elements : t -> Nix_id.Store_path.t list
end

module Flake_lock_composition : sig
  type node = { name : string; locked_rev : string; nar_hash : string }
  type t = node list
  val empty : t
  val combine : t -> t -> t
  val is_idempotent : t -> bool
  val is_commutative : t -> t -> bool
end

module Devenv_module_overlay : sig
  type layer = {
    env_vars : (string * string) list;
    packages : string list;
    services : string list;
  }
  type t = layer list
  val empty : layer
  val compose_layer : layer -> layer -> layer
  val compose_all : t -> layer
end

module Laws : sig
  val verify_closure_join_semilattice :
    Closure_set.t -> Closure_set.t -> Closure_set.t -> bool
  val verify_flake_lock_monoid :
    Flake_lock_composition.t -> Flake_lock_composition.t -> bool
  val verify_devenv_overlay_associativity :
    Devenv_module_overlay.layer ->
    Devenv_module_overlay.layer ->
    Devenv_module_overlay.layer ->
    bool
end

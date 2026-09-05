(** Strongly typed, validated identifiers for controlled Nix and Devenv ecosystem.
    Every identifier is validated against canonical charset and size bounds. *)

module type ID = sig
  type t
  val make : string -> (t, string) result
  val of_string_exn : string -> t
  val to_string : t -> string
  val equal : t -> t -> bool
  val compare : t -> t -> int
end

module Store_path : ID
module Derivation_hash : ID
module Flake_ref : ID
module Flake_url : ID
module Attribute_path : ID
module Profile_name : ID
module Devenv_root : ID
module Devenv_env_name : ID
module Process_name : ID
module Service_name : ID
module Task_name : ID
module Receipt_id : ID
module Closure_digest : ID
module Intent_id : ID

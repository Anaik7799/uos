(** Typed, bounded refusals for the pure Jujutsu declaration layer. *)

type code =
  | Empty_identity
  | Control_byte
  | Identity_too_long
  | Noncanonical_identity
  | Invalid_budget
  | Unknown_operation
  | Unavailable_observed

type t

val make : code -> detail:string -> t
val code : t -> code
val detail : t -> string
val to_string : t -> string
val source_digest : string

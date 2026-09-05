(** Static pure-law obligation authority.

    This module executes no solver and accepts no proof receipt. Consequently
    every current row is explicitly unavailable and grants no formal,
    completion, or parity credit. *)

type availability = Credited | Unavailable_observed
type credit_limit = No_formal_or_parity_credit
type obligation

val schema_id : string
val obligations : obligation list
(*@ ensures List.length obligations = List.length Jj_algebra.laws *)

val obligation_id : obligation -> string
val law_id : obligation -> string
val statement : obligation -> string
val negative_control_id : obligation -> string
val availability : obligation -> availability
val credit_limit : obligation -> credit_limit

val validate : unit -> string list
(*@ ensures result = [] -> obligations <> [] *)

val source_digest : string
(*@ ensures String.length source_digest = 64 *)

module For_test : sig
  type mutation =
    | Drop_obligation
    | Duplicate_obligation
    | Drop_negative_control
    | Invent_credit
    | Reorder_obligations

  val validate_with_mutation : mutation -> string list
end

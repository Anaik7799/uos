(** Closed aggregate over the pure controlled-Jujutsu source denominator.

    A missing constituent digest is an explicit blocker. No module name,
    source path, or prose claim is accepted as a substitute source digest. *)

type unavailable_reason = Missing_digest_accessor
type availability =
  | Available of string
  | Unavailable of unavailable_reason
type constituent

val schema_id : string
val constituents : constituent list
(*@ ensures List.length constituents = 35 *)

val constituent_id : constituent -> string
val constituent_availability : constituent -> availability
val unavailable_constituents : unit -> constituent list

(** SHA-256 over every ordered [id,digest] pair, with both the pair and the
    complete sequence length-framed. Refuses while any row is unavailable. *)
val source_digest : unit -> (string, constituent list) result

module For_test : sig
  type compose_error =
    | Denominator_mismatch
    | Duplicate_constituent
    | Invalid_digest of string

  val compose : (string * string) list -> (string, compose_error) result
end

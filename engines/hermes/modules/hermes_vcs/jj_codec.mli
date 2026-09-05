(** Sole canonical descriptor and normalization authority for [Jj_intent]. *)

type error = Too_large | Malformed_json | Unknown_field of string
  | Missing_field of string | Duplicate_field of string | Hostile_value
  | Invalid_value of string | Intent_error of Jj_intent.error

val canonical_bytes : Jj_intent.t -> string
val digest : Jj_intent.t -> string
val to_json : Jj_intent.t -> string
val of_json : string -> (Jj_intent.t, error) result
val source_digest : string

module For_test : sig
  type source_mutation = Change_json_bound | Drop_expected_field
  val source_digest_with_mutation : source_mutation -> string
end

(** Bounded resource declarations for a future admitted operation. *)

type t = private {
  max_attempts : int;
  timeout_ms : int;
  max_output_bytes : int;
}

type profile = Observation | Local_mutation | History_rewrite | Recovery | Remote

val make : max_attempts:int -> timeout_ms:int -> max_output_bytes:int -> (t, Jj_error.t) result
val valid : t -> bool
val for_profile : profile -> t
val source_digest : string

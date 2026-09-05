(** The sole closed early process-request algebra. It is declarative only. *)

type request_kind =
  | Jujutsu_operation of Jj_operation.t
  | Candidate_verification of Jj_action_kind.candidate_step
  | Formal_oracle of Jj_action_kind.formal_tool

val all : request_kind list
val key : request_kind -> string
val source_digest : string

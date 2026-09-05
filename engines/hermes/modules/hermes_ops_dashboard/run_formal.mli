(** Pure formal obligation authority. Solver execution belongs to Task 6. *)

type result = Sat | Unsat | Unknown | Timeout | Unavailable
type kind = Negated_law | False_control
type obligation = {
  stable_id : string;
  requirement_id : string;
  kind : kind;
  statement : string;
  smt2 : string;
  expected : result;
  solver_id : string;
  solver_version_constraint : string;
  timeout_ms : int;
  query_digest : string;
}

val obligations : obligation list
val digest_query : string -> string
(*@ ensures String.length result = 64 *)
val validate_obligations : obligation list -> string list
val validate : unit -> string list
(*@ ensures result = [] -> obligations <> [] *)
val specification_digest : string

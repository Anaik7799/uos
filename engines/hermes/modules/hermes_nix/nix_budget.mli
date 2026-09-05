(** Bounded operational budgets for Nix evaluation, build derivation, and Devenv execution. *)

type t = {
  timeout_ms : int;
  max_eval_memory_mb : int;
  max_build_cores : int;
  max_log_bytes : int;
  allow_network_during_build : bool;
}

val default : t
val fast_eval : t
val heavyweight_build : t
val validate : t -> (unit, string) result

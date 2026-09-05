(** R31 Controlled External Access policy gate for Nix and Devenv.
    Fails closed on unauthorized network egress, unbounded budgets, or unvalidated paths. *)

type decision =
  | Admitted
  | Rejected of Nix_error.t

val evaluate_intent : Nix_intent.t -> decision
val check_path_sandbox : string -> (unit, Nix_error.t) result
val check_flake_ref : Nix_id.Flake_ref.t -> (unit, Nix_error.t) result

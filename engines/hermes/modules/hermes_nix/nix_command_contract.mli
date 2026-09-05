(** Typed command contract synthesis for controlled execution under R31.
    Translates validated declarative intent into bounded argv arrays without shell formatting. *)

type t = {
  executable : string;
  args : string list;
  env_overrides : (string * string) list;
  timeout_ms : int;
}

val synthesize : Nix_intent.t -> (t, Nix_error.t) result
val to_string_summary : t -> string

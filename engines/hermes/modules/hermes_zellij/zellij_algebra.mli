(** Finite algebra for declared Zellij session observations. *)

type observation = private {
  session : Zellij_intent.session;
  command_present : bool;
  session_live : bool;
  cwd_matches : bool;
}

val make_observation :
  session:Zellij_intent.session ->
  command_present:bool ->
  session_live:bool ->
  cwd_matches:bool ->
  observation

val session : observation -> Zellij_intent.session
val command_present : observation -> bool
val session_live : observation -> bool
val cwd_matches : observation -> bool
val normalize : observation list -> (observation list, string list) result
val complete : observation list -> bool
val command_session_bijection : (string * Zellij_intent.session) list -> bool

val ensure_session :
  Zellij_intent.session -> observation list -> observation list

val union :
  observation list -> observation list -> (observation list, string list) result

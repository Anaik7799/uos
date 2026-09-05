(** Total observation of the local Zellij integration. *)

type 'a fact = Known of 'a | Unknown of string

type process_result = {
  status : Unix.process_status;
  stdout : string;
  stderr : string;
}

type runner = program:string -> argv:string array -> process_result
type link_state = Correct | Missing | Wrong of string

type observation = private {
  version : string fact;
  sessions : Zellij_intent.session list fact;
  config_digest : string option fact;
  launcher_present : bool fact;
  command_links : (Zellij_intent.session * link_state) list;
  tmux_sessions : string fact;
  nested_session : bool fact;
}

val make :
  version:string fact ->
  sessions:Zellij_intent.session list fact ->
  config_digest:string option fact ->
  launcher_present:bool fact ->
  command_links:(Zellij_intent.session * link_state) list ->
  tmux_sessions:string fact ->
  nested_session:bool fact ->
  observation

val run : runner
val parse_sessions : process_result -> Zellij_intent.session list fact
val observe_with : runner:runner -> Zellij_intent.t -> observation
val observe : Zellij_intent.t -> observation
val version : observation -> string fact
val sessions : observation -> Zellij_intent.session list fact
val config_digest : observation -> string option fact
val launcher_present : observation -> bool fact
val command_links : observation -> (Zellij_intent.session * link_state) list
val tmux_sessions : observation -> string fact
val nested_session : observation -> bool fact

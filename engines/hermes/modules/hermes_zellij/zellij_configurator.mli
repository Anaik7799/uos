(** Pure planning and checked effects for the declarative Zellij integration. *)

type change =
  | Write_config
  | Install_launcher
  | Link_command of Zellij_intent.session
  | Ensure_session of Zellij_intent.session

type command = Plan | Check | Apply | Ensure | Status | Docs_audit

type receipt = {
  intent_digest : string;
  applied : change list;
  config_digest : string;
}

val launcher_session : string -> (Zellij_intent.session, string) result
val command_of_argv : string array -> (command, string) result

val plan :
  Zellij_intent.t ->
  Zellij_observe.observation ->
  (change list, string list) result

val preflight_resources : Zellij_intent.t -> Resource_envelope.resource list
val preflight : Zellij_intent.t -> (unit, string list) result

val write_atomic_with :
  emit:(out_channel -> string -> (unit, string) result) ->
  string ->
  string ->
  (unit, string) result

val write_atomic : string -> string -> (unit, string) result

val apply :
  launcher_source:string ->
  Zellij_intent.t ->
  change list ->
  (receipt, string list) result

val render_change : change -> string
val write_documentation : Zellij_intent.t -> (string list, string list) result

(** Closed declarative authority for the harness-bionic Zellij workspace. *)

type session = Zlt_1 | Zlt_2 | Zlt_3 | Zlt_4 | Zlt_5 | Zlt_6
type install_method = Cargo_locked
type attachment = Manual

type t = private {
  install_method : install_method;
  workspace_root : string;
  config_root : string;
  command_root : string;
  zellij_bin : string;
  shell : string;
  sessions : session list;
  attachment : attachment;
}

val all_sessions : session list
val session_name : session -> string
val session_of_string : string -> session option
val compare_session : session -> session -> int

val make :
  install_method:install_method ->
  workspace_root:string ->
  config_root:string ->
  command_root:string ->
  zellij_bin:string ->
  shell:string ->
  sessions:session list ->
  attachment:attachment ->
  unit ->
  (t, string list) result

val default : unit -> (t, string list) result
val validate : t -> string list
val workspace_root : t -> string
val config_root : t -> string
val command_root : t -> string
val zellij_bin : t -> string
val shell : t -> string
val sessions : t -> session list
val canonical_json : t -> string
val digest : t -> string

(** Deterministic SysML, OML/OWL, OpenMBEE MMS and FPP dictionary surfaces. *)

type manifest = {
  source_digest : string;
  component_ids : string list;
  port_ids : string list;
  channel_ids : string list;
  requirement_ids : string list;
  edge_ids : string list;
  lifecycle_machine_ids : string list;
  fault_event_ids : string list;
  gate_command_ids : string list;
  activity_ids : string list;
}

val manifest : manifest
val oml_blocks : unit -> Hermes_sysml.Sysml_types.block list
val sysml_v2 : unit -> string
(*@ ensures result <> "" *)
val oml_owl : unit -> string
(*@ ensures result <> "" *)
val openmbee_mms : unit -> string
(*@ ensures result <> "" *)
val fpp_dictionary : unit -> string
(*@ ensures result <> "" *)
val outputs : unit -> (string * string) list
val validate : unit -> string list
val manifest_of_sysml : string -> (manifest, string) result
val manifest_of_turtle : string -> (manifest, string) result
val manifest_of_mms : string -> (manifest, string) result
val manifest_of_fpp : string -> (manifest, string) result
val escape_sysml : string -> string
val escape_turtle : string -> string

(** Total capability and evidence registry for the InfraNodus-equivalent OCaml
    workspace. Status is an observation of repository evidence, not intent. *)

type family =
  | Workspace
  | Acquisition
  | Processing
  | Visualization
  | Analytics
  | Intelligence
  | Integration

type behavior = Static | Dynamic | Static_and_dynamic

type status = Implemented | Adapter_ready | Planned | Unknown_not_claimed

type t

val all : t list
val find : string -> t option
val validate : t list -> (unit, string list) result

val id : t -> string
val family : t -> family
val title : t -> string
val behavior : t -> behavior
val use_case : t -> string
val status : t -> status
val ui_controls : t -> string list
val scenario_ids : t -> string list
val evidence : t -> string list

val family_name : family -> string
val behavior_name : behavior -> string
val status_name : status -> string
val to_yojson : t -> Yojson.Safe.t
val to_markdown : t list -> string

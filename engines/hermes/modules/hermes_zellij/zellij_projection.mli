(** Deterministic projections derived from the closed Zellij intent model. *)

val digest : string -> string
val render_config_kdl : Zellij_intent.t -> string
val command_links : Zellij_intent.t -> (string * string) list
val render_ontology_markdown : unit -> string
val render_atlas_markdown : unit -> string
val render_algebra_markdown : unit -> string
val render_guide_markdown : Zellij_intent.t -> string
val render_authority_json : unit -> string
val render_model_json : Zellij_intent.t -> string

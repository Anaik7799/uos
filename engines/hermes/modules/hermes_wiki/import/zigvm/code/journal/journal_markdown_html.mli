(** A deterministic, self-contained HTML interpretation of a Markdown journal. *)

type t
type artifact

val create : title:string -> source_path:string -> markdown:string -> t

val text_artifact : label:string -> content:string -> artifact

val image_artifact :
  label:string -> mime_type:string -> base64:string -> artifact

val video_artifact :
  label:string -> mime_type:string -> base64:string -> sha256:string ->
  bytes:int -> provenance:string -> artifact

val download_artifact :
  label:string -> mime_type:string -> base64:string -> sha256:string ->
  bytes:int -> provenance:string -> artifact

val with_artifacts : t -> artifact list -> t

val with_rendered_body : t -> string -> t
(** Supply a body already rendered by the repository-wide wiki corpus, so
    wikilink resolution and typed-edge extraction use the canonical graph. *)

val render : t -> string
(** [render document] preserves the journal body through the repository's safe
    Markdown renderer and makes provenance visible above the fold. *)

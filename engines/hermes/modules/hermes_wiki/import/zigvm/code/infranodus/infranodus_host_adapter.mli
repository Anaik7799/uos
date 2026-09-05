(** Host-specific coordinates mapped into the shared acquisition carrier. *)

type host = Browser | Obsidian | Ide | N8n
type payload = { host : host; external_id : string; title : string; body : string; locator : string option; tags : string list }

val host_name : host -> string
val to_request : payload -> (Infranodus_acquisition.request, string) Stdlib.result
val to_yojson : payload -> Yojson.Safe.t
val of_yojson : Yojson.Safe.t -> (payload, string) Stdlib.result

(* Resource capability v2 PREPARATION. Every supplied anchor/configuration is
   DATA. Signatures establish consistency under provided keys, never custody,
   admitted resource ownership, an issuer role, or production Store permission. *)
type opened
type anchor_data
type evidence
type historical

val open_owned : string -> (opened, string) result
val close : opened -> unit
val identity_json : opened -> Yojson.Basic.t
val check_opened : opened -> (unit, string) result
val anchor_data : string -> (anchor_data, string) result
val anchor_sha256 : anchor_data -> string
val resource_bytes : anchor_data -> request_bytes:string -> capability_bytes:string ->
  reviewer_signature:string -> issuer_signature:string -> (string, string) result
val review_message : string -> string
val issuer_message : string -> reviewer_signature:string -> string
val verify : anchor_data -> request_bytes:string -> capability_bytes:string ->
  reviewer_signature:string -> issuer_signature:string -> resource_bytes:string ->
  resource_reviewer_signature:string -> resource_issuer_signature:string ->
  (evidence, string) result
val verify_history : anchor_data -> request_bytes:string -> capability_bytes:string ->
  reviewer_signature:string -> issuer_signature:string -> resource_bytes:string ->
  resource_reviewer_signature:string -> resource_issuer_signature:string ->
  (historical, string) result
val check_effect_boundary : evidence -> database:opened -> journal:opened ->
  (unit, string) result
val check_history_boundary : historical -> database:opened -> journal:opened ->
  (unit, string) result
val evidence_anchor_sha256 : evidence -> string
val sqlite_descriptor_binding : string
val production_status : unit -> string

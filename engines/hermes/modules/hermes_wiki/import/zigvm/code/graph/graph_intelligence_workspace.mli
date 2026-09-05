(** Source-scoped intelligence over deterministic graph analytics. Model
    providers are optional interpreters and never become the authority. *)

type provider_state = Configured of string | Unavailable of string | Rate_limited of { provider : string; retry_after_seconds : int }
type evidence = { statement_id : string; text : string }
type retrieval_packet = { query : string; revision : int; filter_digest : string; node_ids : string list; evidence : evidence list }
type answer = { text : string; provider : string option; citations : string list }
type ontology = { entities : string list; relations : (string * string) list; categories : (string * string list) list; rules : string list }
type note_mode = Append | Replace
type note = { label : string; revision : int; body : string }
type provider = string -> (string, provider_state) Stdlib.result

val topic_overview : Graph_analytics.report -> string
val focused_summary : node_ids:string list -> Graph_analytics.report -> string
val gap_ideation : Graph_analytics.report -> string list
val retrieve : query:string -> Graph_analytics.report -> retrieval_packet
val augment_prompt : prompt:string -> retrieval_packet -> string
val chat : ?provider:provider -> retrieval_packet -> (answer, provider_state) Stdlib.result
val classify : Graph_analytics.report -> ontology
val generate_note : mode:note_mode -> existing:string -> label:string -> Graph_analytics.report -> note
val select_provider : provider_state list -> (string, provider_state) Stdlib.result
val packet_to_yojson : retrieval_packet -> Yojson.Safe.t
val ontology_to_yojson : ontology -> Yojson.Safe.t

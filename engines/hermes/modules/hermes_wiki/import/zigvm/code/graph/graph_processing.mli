(** Pure attributed-text processing profile and provenance algebra. *)

type graph_mode = Words_and_entities | Entities_only

type profile = {
  language : string;
  lemmatize : bool;
  stop_words : string list;
  protected_words : string list;
  synonyms : (string * string) list;
  process_words : bool;
  process_wiki_links : bool;
  process_mentions : bool;
  process_categories : bool;
  window : int;
  graph_mode : graph_mode;
}

type statement = {
  id : string;
  source_id : string;
  ordinal : int;
  text : string;
  metadata : (string * string) list;
}

type typed_node = { id : string; label : string; kind : string; weight : float }
type metadata_tag = { statement_id : string; key : string; value : string }

type result = {
  statements : statement list;
  graph : Graph_intelligence.t;
  typed_nodes : typed_node list;
  node_statements : (string * string list) list;
  aliases : (string * string) list;
  tags : metadata_tag list;
  effective_language : string;
  digest : string;
}

val default_profile : profile
val statement : id:string -> source_id:string -> ?ordinal:int -> ?metadata:(string * string) list -> string -> statement
val process : profile -> statement list -> result
val has_node : result -> string -> bool
val statement_ids_for_node : result -> string -> string list

(** Local exports over one visible revision and its exact analytics report. *)

type format =
  | Statements_csv
  | Statements_markdown
  | Analytics_text
  | Analytics_csv
  | Json
  | Graph_csv
  | Gexf
  | Dot
  | Graphml
  | Source_json

type packet

val formats : format list
val format_name : format -> string
val packet : revision:Graph_revision.t -> statements:Graph_processing.statement list -> analytics:Graph_analytics.report -> packet
val exported_node_ids : packet -> string list
val statement_ids : packet -> string list
val statements_csv : packet -> string
val statements_markdown : packet -> string
val analytics_text : packet -> string
val analytics_csv : packet -> string
val json : packet -> string
val graph_csv : packet -> string
val gexf : packet -> string
val dot : packet -> string
val graphml : packet -> string
val source_json : packet -> string
val decode_source_backup : string -> (Graph_revision.t * Graph_processing.statement list, string) result
val render : format -> packet -> string * string

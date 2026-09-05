(** Revision- and filter-scoped deterministic analytics observations. *)

type excerpt = { statement_id : string; text : string; node_ids : string list; metadata : (string * string) list }
type topic = { id : string; label : string; node_ids : string list; influence : float }
type ranked = { node_id : string; score : float }
type gateway = { node_id : string; globality : float; locality : float }
type relation = { source : string; target : string; occurrences : int; weight : float }
type sentiment_summary = { positive : int; negative : int; neutral : int; total : int }
type structure = { modularity : float; influence_entropy : float; diversity : [ `Biased | `Focused | `Diverse | `Dispersed ]; components : int; density : float }
type stats = { words : int; unique_lemmas : int; characters : int; nodes : int; edges : int; average_degree : float }
type trend = { bucket : int; topic_id : string; cumulative_occurrences : int }
type propagation = { values : float list; alpha : float option; classification : string }
type bucket = { degree : int; count : int }

type report = {
  revision : int;
  filter_digest : string;
  excerpts : excerpt list;
  topics : topic list;
  influential_concepts : ranked list;
  gaps : Graph_intelligence.gap list;
  gateways : gateway list;
  relations : relation list;
  sentiment : sentiment_summary;
  stats : stats;
  trends : trend list;
  structure : structure;
  propagation : propagation;
  degree_distribution : bucket list;
  lda_comparison : topic list;
}

val analyze : filter_digest:string -> Graph_revision.t -> Graph_processing.statement list -> report
val to_yojson : report -> Yojson.Safe.t

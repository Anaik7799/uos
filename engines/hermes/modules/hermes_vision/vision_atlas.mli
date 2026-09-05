(* Fractal atlas for the vision pipeline.

   The ontology says what each stage IS; the atlas says how the stages
   are related and what evidence reaches each one. Its job is to answer
   "what does this receipt actually establish, and what did it assume"
   without a human tracing the graph by hand. *)

type relation =
  | Feeds       (* the source stage's output is the target's input *)
  | Observes    (* the source stage measures the target, without feeding it *)
  | Governs     (* the source stage's declaration constrains the target *)

type edge = { source : Vision_ontology.stage; relation : relation; target : Vision_ontology.stage }

val relation_name : relation -> string
val edges : edge list

(* The chain of stages a receipt at [s] depends on, nearest first. An
   Observe receipt that depends on nothing is a receipt about nothing. *)
val evidence_path : Vision_ontology.stage -> Vision_ontology.stage list

(* Stages that feed [s] but are not covered by the given measured
   segment — what a receipt at [s] ASSUMED rather than established. This
   is the atlas's real product: it turns a green result into a green
   result with a named list of assumptions. *)
val assumptions : Vision_ontology.stage -> Vision_algebra.segment -> Vision_ontology.stage list

(* Rendered atlas, one line per edge, for the operator and the docs. *)
val render : unit -> string

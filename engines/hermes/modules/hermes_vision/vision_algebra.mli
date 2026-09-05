(* Fractal algebra for the vision pipeline.

   A run is a SEGMENT of the pipeline — a contiguous stage range. The
   algebra is composition of segments, and it exists to make one claim
   checkable: that a green end-to-end result covers every stage with no
   gap. Reporting "Source ok, Serve ok, Observe ok" while never checking
   Package or Play is exactly the shape of an untrue green, and here it
   is not a well-formed value.

   The laws below are asserted in the tests, not merely stated:
     - compose is ASSOCIATIVE where defined;
     - [identity s] is a unit for composition at [s];
     - compose is DEFINED only on adjacency, so gaps cannot be built;
     - [covers_pipeline] holds exactly for Source..Observe. *)

type segment = { first : Vision_ontology.stage; last : Vision_ontology.stage }

(* [first] must not come after [last]; anything else is not a segment. *)
val segment : Vision_ontology.stage -> Vision_ontology.stage -> segment option

val stages_of : segment -> Vision_ontology.stage list

(* Defined iff [b] begins exactly where [a] ends, or one stage after it.
   Overlap is allowed (re-measuring a stage is honest); a GAP is not. *)
val compose : segment -> segment -> segment option

val identity : Vision_ontology.stage -> segment

(* The whole pipeline, Source through Observe. *)
val full : segment

(* True only for a segment spanning every stage. This is what an
   end-to-end claim must produce. *)
val covers_pipeline : segment -> bool

(* Fold a set of measured segments into the coverage they jointly
   establish, or report the first gap. Order-independent: the caller
   cannot make coverage appear by sorting its evidence. *)
val coverage : segment list -> (segment, string) result

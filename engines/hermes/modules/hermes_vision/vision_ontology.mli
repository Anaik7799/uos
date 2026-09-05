(* Fractal ontology for the vision pipeline.

   The pipeline is six stages, and the ontology exists so that a failure
   can be LOCATED rather than described. "The video is broken" is not a
   diagnosis; "Package produced no segment while Encode was still
   advancing" is, and it names which stage to look at and which origin
   may be blamed.

   Each stage carries its fractal level and the RCA origin that owns its
   failures. R5 holds here as elsewhere: only Implementation may deny
   parity credit, and no stage whose failure is really an absent tool or
   an unreachable host is allowed to claim Implementation. *)

type stage =
  | Source    (* a signal exists at all *)
  | Encode    (* frames become a compressed elementary stream *)
  | Package   (* the stream becomes addressable media segments *)
  | Serve     (* segments become reachable over the network *)
  | Play      (* a browser decodes and presents them *)
  | Observe   (* the presented result is captured and compared *)

val stages : stage list          (* in pipeline order, Source first *)
val stage_name : stage -> string
val stage_index : stage -> int

(* Where a stage sits in the fractal, and who owns its failures. *)
val level : stage -> Fractal_diagnostic.fractal_level
val origin : stage -> Fractal_diagnostic.origin

(* What must be true for the stage to be considered live, in one line.
   This is the sentence a probe is written against, so a probe that
   checks something else is visibly not checking the law. *)
val law : stage -> string

(* The hazard the stage owns — the way this stage lies rather than
   fails. Every stage has one, because a stage that cannot lie does not
   need a probe. *)
val hazard : stage -> string

(* The stage a failure at [s] should be investigated from: a browser
   showing nothing is usually not a browser defect. Total; [Source]
   answers itself. *)
val upstream : stage -> stage

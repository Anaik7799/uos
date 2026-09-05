(* Rete-UL: forward-chaining diagnosis over stage observations.

   Six verdicts do not tell an operator what to fix. A pipeline where
   Package, Serve and Play are all Absent has ONE fault and two
   consequences, and reporting three failures sends someone to the wrong
   place. These rules turn a set of verdicts into a blame assignment.

   Mirrors the working-memory / fire-rules shape of the existing
   `hermes_rete` (R14) rather than inventing a second rule vocabulary.

   -------------------------------------------------------------------
   TWO LAWS, AND BOTH ARE ABOUT NOT BLAMING THE WRONG THING

   NEVER BLAME A STAGE WHOSE UPSTREAM ALSO FAILED. That is a cascade,
   and the downstream stage is a victim. This is the misdiagnosis the
   rules exist to prevent: the browser shows nothing because the encoder
   died, and blaming the browser wastes the afternoon.

   NEVER BLAME A STAGE THAT WAS NOT MEASURED. An Unknown stage proves
   nothing in either direction, so it can neither be blamed nor clear
   the stage below it. Treating Unknown as "fine" is how a cascade gets
   attributed to the first stage anyone happened to probe. *)

type fact =
  | Verdict of Vision_ontology.stage * string   (* LIVE | ABSENT | UNKNOWN *)

type conclusion =
  | Blame of { stage : Vision_ontology.stage; because : string }
  | Cascade of { stage : Vision_ontology.stage; from_ : Vision_ontology.stage }
  | Unmeasured of Vision_ontology.stage
  | Healthy

val fact_of : Vision_controller.observation -> fact
val facts_of : Vision_controller.observation list -> fact list

(* The working memory, as the rete modules phrase it. *)
val verdict_of : fact list -> Vision_ontology.stage -> string option

(* Fire every rule to fixpoint. Total, and order-independent: the same
   facts in any order yield the same conclusions, because a diagnosis
   that depended on probe ordering would be an artefact of the harness
   rather than of the system. *)
val infer : fact list -> conclusion list

(* The single stage to investigate, if the rules identify one. [None]
   when the pipeline is healthy, when nothing was measured, or when the
   evidence genuinely does not distinguish — saying "I do not know" is a
   result, and guessing is not. *)
val root_cause : conclusion list -> Vision_ontology.stage option

val render : conclusion list -> string

type declared
type observed
type oriented
type hypothesized
type discriminated
type corrected
type verified
type receipt = private {
  intent_id : string;
  root_cause_id : string;
  rca_origin : Ops_capability.rca_origin;
  evidence_digests : string list;
  stage : Debug_ontology.protocol_stage;
  digest : string;
}
val declare : Debug_intent.t -> declared
val observe : declared -> Debug_ontology.observation list -> (observed, string) result
val orient : observed -> (oriented, string) result
val hypothesize : oriented -> mechanical_proof:bool -> Debug_ontology.hypothesis list -> (hypothesized, string) result
val discriminate : hypothesized -> Debug_ontology.discriminator -> eliminated:string list -> (discriminated, string) result
val correct : discriminated -> correction_id:string -> via_bridge:bool -> (corrected, string) result
val verify : corrected -> Debug_ontology.observation list -> (verified, string) result
val close : verified -> (receipt, string) result


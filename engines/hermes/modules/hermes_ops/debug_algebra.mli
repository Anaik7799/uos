type verdict = Unavailable | Stale | Contradicted | Open | Established | Corrected | Verified | Closed
type failure_effect = Blocks_credit | Denies_credit
val evidence_union : Debug_ontology.observation list -> Debug_ontology.observation list -> Debug_ontology.observation list
val eliminate : Debug_ontology.hypothesis list -> string list -> Debug_ontology.hypothesis list
val join_verdict : verdict -> verdict -> verdict
val failure_effect : Ops_capability.rca_origin -> failure_effect


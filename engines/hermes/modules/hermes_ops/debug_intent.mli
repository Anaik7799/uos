type effect_policy = Pure_diagnosis | Corrective_via_bridge of string
type fpp_mapping = { owner : string; component : string; channel : string }
type t = private {
  stable_id : string;
  failure_family : string;
  objective : string;
  target_module_id : string;
  symptom_patterns : string list;
  assumptions : string list;
  constraints : string list;
  success_criteria : string list;
  path : Ops_capability.coordinate list;
  capability_ids : string list;
  configuration_ids : string list;
  surfaces : (Ops_capability.surface * Ops_capability.applicability) list;
  effect_policy : effect_policy;
  fpp : fpp_mapping;
  dependability : Debug_dependability.t;
  hypotheses : Debug_ontology.hypothesis list;
  next_measurement : Debug_ontology.discriminator;
}
val all : t list
val find : string -> t option
val validate : t list -> string list
val source_digest : string
module For_test : sig
  type mutation = Drop_first | Duplicate_first | Empty_symptoms | Direct_effect | Unbounded_test | Collapse_hypotheses
  val mutate : mutation -> t list
end


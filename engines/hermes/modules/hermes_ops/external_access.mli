(** R31 pure authority for controlled SQLite and external-system access.
    This module validates and prepares immutable declarative intent. It owns no
    effect interpreter and cannot call the Swarm engine. *)

type resource =
  | Sqlite
  | Filesystem
  | Process
  | Network
  | Vcs
  | External_service
  | Hardware
  | Oracle

type operation = Read | Write | Execute | Publish | Observe | Recover
type redaction = Public | Metadata_only | Secret

type budget = {
  timeout_ms : int;
  max_bytes : int;
  max_attempts : int;
}

type declaration = {
  intent_id : string;
  request_id : string;
  owner_id : string;
  adapter_id : string;
  resource : resource;
  operation : operation;
  purpose : string;
  target_class : string;
  config_ids : string list;
  authorization_id : string;
  budget : budget;
  redaction : redaction;
  idempotency_key : string;
  success_criteria : string list;
  recovery_id : string;
  coordinate : Ops_capability.coordinate;
}

type intent
type prepared

val resources : resource list
val resource_name : resource -> string
val adapter_id : resource -> string
val declare : declaration -> (intent, string list) result
val intent_resource : intent -> resource
val intent_digest : intent -> string

type execution_status = Unavailable_observed
val prepare : intent -> (prepared, string list) result
val prepared_digest : prepared -> string
val prepared_bridge_id : prepared -> string
val prepared_engine_calls : prepared -> int
val execution_status : prepared -> execution_status

type ontology_node = {
  level : Ops_capability.level;
  stable_id : string;
  carrier : string;
  invariant : string;
}

val ontology : ontology_node list
val validate_ontology : ontology_node list -> string list

type atlas_path = {
  resource : resource;
  stable_id : string;
  steps : string list;
  recovery_step : string;
  fpp_component_id : string;
}

val atlas : atlas_path list
val validate_atlas : atlas_path list -> string list

type law =
  | Closure | Identity | Associativity | Effect_ordering | Absorption
  | Validation_monotonicity | Authority_conservation | Credit_non_escalation
  | Apply_once | Readback | Redaction_homomorphism | Boundedness
  | Recovery_closure | Surface_equivalence

type mutant = Mutant of law
val laws : law list
val mutants : mutant list
val law_id : law -> string
val prove_finite : law -> bool
val mutant_is_killed : mutant -> bool
val validate_algebra : unit -> string list
val lifecycle_reachability_gaps : unit -> string list
val credit_non_escalation_gaps : unit -> string list

val fpp_model : Fpp_model.model
val validate_fpp : unit -> string list
val source_digest : string

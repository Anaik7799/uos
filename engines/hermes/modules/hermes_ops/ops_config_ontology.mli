(** Typed fractal ontology derived from [Ops_config.elements].  It separates
    configuration declaration, observation, admission, execution, scheduling,
    and evidence authorities so that documentation cannot collapse them. *)

type node_kind =
  | Registry
  | Supply
  | Element
  | Consumer
  | Source_observation
  | Validation
  | Configuration_digest
  | Execution_intent
  | Assurance
  | Execution_bridge
  | Scheduler
  | Receipt

type authority =
  | Declaration
  | Observation
  | Derived_identity
  | Admission
  | Execution
  | Scheduling
  | Evidence

type node = {
  id : string;
  label : string;
  kind : node_kind;
  layer : Ops_config.layer option;
  authority : authority;
  purpose : string;
}

val registry_id : string
val observation_id : string
val validation_id : string
val configuration_digest_id : string
val execution_intent_id : string
val assurance_id : string
val execution_bridge_id : string
val scheduler_id : string
val receipt_id : string

(** Exact pure authority identities projected from [Ops_config]. *)
val schema_id : string
val declaration_digest : string

val element_id : string -> string
val consumer_id : string -> string
val supply_id : Ops_config.supply -> string
val kind_name : node_kind -> string
val authority_name : authority -> string

val all : node list
val find : string -> node option
val validate_nodes : node list -> (unit, string) result
val validate : unit -> (unit, string) result

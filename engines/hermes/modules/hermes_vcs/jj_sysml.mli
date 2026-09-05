(** Sparse SysML-shaped projection derived from [Jj_ontology] and the exact
    [Jj_operation] denominator.  It is a pure model, not an execution surface. *)

type flow =
  | Contains
  | Observes
  | Admits
  | Prepares
  | Produces
  | Retains
  | Reports

type verification = Structural_check

type part = private {
  id : string;
  kind : Jj_ontology.kind;
  coordinate : Jj_ontology.coordinate;
  owner : Jj_ontology.owner;
  identity : Jj_ontology.identity;
  lifecycle : Jj_ontology.lifecycle;
}

type connection = private {
  source : string;
  target : string;
  flow : flow;
}

type requirement = private {
  id : string;
  subject : string;
  invariant : Jj_ontology.invariant;
  verification : verification;
}

type operation_allocation = private {
  operation : Jj_operation.t;
  operation_key : string;
  operation_digest : string;
  intent_part : string;
  effect_part : string;
  lifecycle : Jj_ontology.lifecycle;
}

type model = private {
  schema_id : string;
  ontology_digest : string;
  operation_authority_digest : string;
  parts : part list;
  connections : connection list;
  requirements : requirement list;
  operation_allocations : operation_allocation list;
}

val schema_id : string
val model : model
val source_digest : string

val flow_key : flow -> string
val requirement_count : model -> int
val operation_count : model -> int
val connection_endpoints_exist : model -> bool
val operation_denominator_is_exact : model -> bool

module For_test : sig
  type mutation = Drop_part | Reverse_connection | Drop_requirement | Change_operation
  val source_digest_with_mutation : mutation -> string
end

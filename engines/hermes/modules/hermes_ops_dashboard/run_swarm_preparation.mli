(** Pure, closed request preparation for the canonical Swarm bridge actions.
    This module owns no scheduler, event store, target, or effect authority. *)

type t = private {
  action_id : string;
  effect_kind : Run_topology.effect_kind;
  request_bytes : string;
  request_digest : string;
  dependency_input_digest : string;
  idempotency_key : string;
}

val idempotency_key :
  execution_identity:string -> activity:Run_topology.admitted_activity ->
  action:Run_topology.declarative_action -> string
(** Pure identity projection used by readback to query the exact effect ledger
    row without re-preparing, applying, or invoking a target.  The admitted
    activity is required so identical-looking actions cannot cross activity
    authority boundaries. *)

val prepare :
  execution_identity:string -> activity:Run_topology.admitted_activity ->
  action:Run_topology.declarative_action -> input_payload:string ->
  (t, string) result
(** Accepts only an exact member of the supplied admitted activity and binds
    its closed [work] carrier into the canonical request identity.  The three
    original repository carriers retain their structured fields; every Task-7A
    carrier projects the topology-owned closed [action_work_id], never argv,
    raw paths, callbacks, or execution authority. *)

val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_schema_version
    | Drop_activity_identity_field
    | Drop_topology_authority_field
    | Drop_action_identity_field
    | Drop_assignment_field
    | Drop_command_field
    | Drop_dependency_ids_field
    | Drop_dependency_input_field
    | Drop_execution_identity_field
    | Drop_action_digest_field
    | Drop_preparation_id_field
    | Drop_target_component_field
    | Drop_effect_kind_field
    | Reorder_request_fields
    | Drop_effect_denominator
    | Drop_work_class_denominator
    | Drop_completion_receipt_subdenominator
    | Drop_work_projection_fields
    | Drop_idempotency_fields
    | Enable_noncanonical_action

  val source_digest_with_mutation : source_mutation -> string
end

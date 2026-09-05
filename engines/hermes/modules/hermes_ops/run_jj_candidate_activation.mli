(** Pure, fail-closed Task-9 candidate-activation foundation.

    The module validates the closed five-request candidate process subset and
    publishes its nominal runtime declaration.  It exposes no executable,
    argv, cwd/path, environment, process handle, callback, serialized
    capability, dispatch function, live owner constructor, or Current
    constructor. *)

type owner
type activation_current

type unavailable_prerequisite =
  | Candidate_activation_owner_part_current
  | Runtime_manifest_current_carrier
  | Frozen_candidate_process_source_authority
  | Candidate_process_obligation_schema_current
  | Candidate_process_registry_current
  | Registered_candidate_executable_current
  | Candidate_configuration_current_carrier
  | Materialized_candidate_current_carrier
  | A1_candidate_plan_current_carrier
  | Candidate_suite_manifest_current_carrier
  | Approval_occurrence_capabilities_current
  | Receipt_bound_resource_envelope_current
  | Request_bound_candidate_step_current_carrier
  | Candidate_process_apply_once_current
  | Ordered_candidate_step_readback_current
  | Candidate_cleanup_eligibility_current

type diagnostic = private {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

val diagnostic_prerequisite : diagnostic -> unavailable_prerequisite
val diagnostic_message : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> [ `Evidence ]

val runtime_declaration :
  Jj_runtime_manifest.activation_candidate Jj_runtime_manifest.declaration

val accepted_steps : Jj_action_kind.candidate_step list
val step_ids : string list
val obligation_ids : string list

val validated_subset :
  unit ->
  ( Run_jj_runtime_core.candidate_profile
      Run_jj_runtime_core.validated_subset,
    diagnostic )
  result
(** This validation is pure and nonauthorizing.  A successful value is not a
    live process registration, activation owner, or Current receipt. *)

val prerequisites : unavailable_prerequisite list
val production_posture : [ `Implemented_unavailable ]
val create_owner_unavailable : unit -> (owner, diagnostic list) result

(** Digest of the lower source authorities and every closed denominator in
    this foundation.  An unavailable lower source authority is named as an
    unavailable constituent; it is never replaced by caller-supplied bytes. *)
val source_digest : string

module For_test : sig
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_runtime_current_protocol_source
    | Drop_action_kind_source
    | Drop_process_protocol_source
    | Drop_campaign_action_source
    | Drop_dependability_process_protocol_source
    | Drop_dependability_process_source
    | Drop_runtime_core_source
    | Drop_candidate_target_source
    | Drop_topology_source
    | Drop_swarm_preparation_source
    | Drop_event_prefix_source
    | Drop_root_bootstrap_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_candidate_step
    | Reorder_candidate_steps
    | Duplicate_candidate_step
    | Add_formal_step
    | Drop_candidate_obligation
    | Reorder_candidate_obligations
    | Add_writer_obligation
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_live_owner
    | Invent_runtime_manifest_current
    | Invent_process_registry_current
    | Permit_without_materialized_candidate
    | Permit_without_a1_plan
    | Permit_without_suite_manifest
    | Permit_without_approval
    | Permit_cleanup_before_readback
    | Add_raw_executable
    | Add_raw_argv
    | Add_raw_path
    | Add_environment
    | Expose_process
    | Add_callback
    | Serialize_capability
    | Add_current_constructor
    | Add_activation_dispatch

  val source_digest_with_mutation : source_mutation -> string
end

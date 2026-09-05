type owner = |
type activation_current = |

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

type diagnostic = {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

let diagnostic_prerequisite diagnostic = diagnostic.prerequisite
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.origin

let runtime_declaration = Jj_runtime_manifest.activation_candidate
let accepted_steps = Jj_action_kind.candidate_steps
let step_ids = List.map Jj_action_kind.candidate_step_key accepted_steps

let obligation_id = function
  | Dependability_process_protocol.Exact_source -> "exact-source"
  | Dependability_process_protocol.Exact_configuration ->
      "exact-configuration"
  | Dependability_process_protocol.Approval_required -> "approval-required"
  | Dependability_process_protocol.Writer_lease_required ->
      "writer-lease-required"
  | Dependability_process_protocol.Resource_preflight_required ->
      "resource-preflight-required"
  | Dependability_process_protocol.Bridge_admission_required ->
      "bridge-admission-required"
  | Dependability_process_protocol.Apply_once_receipt_required ->
      "apply-once-receipt-required"
  | Dependability_process_protocol.Readback_required -> "readback-required"
  | Dependability_process_protocol.Remote_publication_cas_required ->
      "remote-publication-cas-required"

let candidate_obligations =
  [ Dependability_process_protocol.Exact_source;
    Dependability_process_protocol.Exact_configuration;
    Dependability_process_protocol.Approval_required;
    Dependability_process_protocol.Resource_preflight_required;
    Dependability_process_protocol.Bridge_admission_required;
    Dependability_process_protocol.Apply_once_receipt_required;
    Dependability_process_protocol.Readback_required ]

let obligation_ids = List.map obligation_id candidate_obligations

let prerequisites =
  [ Candidate_activation_owner_part_current;
    Runtime_manifest_current_carrier;
    Frozen_candidate_process_source_authority;
    Candidate_process_obligation_schema_current;
    Candidate_process_registry_current;
    Registered_candidate_executable_current;
    Candidate_configuration_current_carrier;
    Materialized_candidate_current_carrier;
    A1_candidate_plan_current_carrier;
    Candidate_suite_manifest_current_carrier;
    Approval_occurrence_capabilities_current;
    Receipt_bound_resource_envelope_current;
    Request_bound_candidate_step_current_carrier;
    Candidate_process_apply_once_current;
    Ordered_candidate_step_readback_current;
    Candidate_cleanup_eligibility_current ]

let prerequisite_id = function
  | Candidate_activation_owner_part_current ->
      "candidate-activation-owner-part-current"
  | Runtime_manifest_current_carrier -> "runtime-manifest-current-carrier"
  | Frozen_candidate_process_source_authority ->
      "frozen-candidate-process-source-authority"
  | Candidate_process_obligation_schema_current ->
      "candidate-process-obligation-schema-current"
  | Candidate_process_registry_current ->
      "candidate-process-registry-current"
  | Registered_candidate_executable_current ->
      "registered-candidate-executable-current"
  | Candidate_configuration_current_carrier ->
      "candidate-configuration-current-carrier"
  | Materialized_candidate_current_carrier ->
      "materialized-candidate-current-carrier"
  | A1_candidate_plan_current_carrier -> "a1-candidate-plan-current-carrier"
  | Candidate_suite_manifest_current_carrier ->
      "candidate-suite-manifest-current-carrier"
  | Approval_occurrence_capabilities_current ->
      "approval-occurrence-capabilities-current"
  | Receipt_bound_resource_envelope_current ->
      "receipt-bound-resource-envelope-current"
  | Request_bound_candidate_step_current_carrier ->
      "request-bound-candidate-step-current-carrier"
  | Candidate_process_apply_once_current ->
      "candidate-process-apply-once-current"
  | Ordered_candidate_step_readback_current ->
      "ordered-candidate-step-readback-current"
  | Candidate_cleanup_eligibility_current ->
      "candidate-cleanup-eligibility-current"

let diagnostic prerequisite message =
  { prerequisite;
    message;
    coordinate = "L3/Orient/run-jj-candidate-activation";
    origin = `Evidence }

let validated_subset () =
  match Run_jj_runtime_core.validate_subset Run_jj_runtime_core.Candidate with
  | Ok subset -> Ok subset
  | Error lower ->
      Error
        (diagnostic Frozen_candidate_process_source_authority
           (Run_jj_runtime_core.diagnostic_message lower))

let production_posture = `Implemented_unavailable

let create_owner_unavailable () =
  Error
    (List.map
       (fun prerequisite ->
         diagnostic prerequisite (prerequisite_id prerequisite ^ " is unavailable"))
       prerequisites)

let declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let lower_source_fields =
  [ ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("runtime-current-protocol-source",
     Jj_runtime_current_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("process-protocol-source", Jj_process_protocol.source_digest);
    ("campaign-action-source", Jj_campaign_action.source_digest);
    ("dependability-process-protocol-source",
     Dependability_process_protocol.source_digest);
    ("dependability-process-source",
     "unavailable:no-exported-source-digest");
    ("runtime-core-source", Run_jj_runtime_core.source_digest);
    ("candidate-target-source",
     Ops_candidate_tree_verification_target.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("swarm-preparation-source", Run_swarm_preparation.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest) ]

let source_fields =
  ("schema", "run-jj-candidate-activation-foundation-v1")
  :: lower_source_fields
  @ [ ("runtime-declaration", declaration_id runtime_declaration);
      ("candidate-step-order", String.concat "," step_ids);
      ("candidate-obligation-order", String.concat "," obligation_ids);
      ("missing-prerequisite-order",
       String.concat "," (List.map prerequisite_id prerequisites));
      ("validated-subset", "pure:nonauthorizing:five");
      ("live-owner", "unconstructible");
      ("runtime-manifest-current", "unavailable");
      ("process-registry-current", "unavailable");
      ("activation-current", "unconstructible");
      ("activation-dispatch", "absent");
      ("raw-executable", "absent");
      ("raw-argv", "absent");
      ("raw-path", "absent");
      ("environment", "absent");
      ("process-handle", "absent");
      ("callback", "absent");
      ("capability-serialization", "forbidden");
      ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest = digest source_fields

module For_test = struct
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

  let source_digest_with_mutation = function
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
    | Add_activation_dispatch -> source_digest
end

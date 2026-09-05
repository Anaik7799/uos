(** One typed source authority for the operations FPP and MBSE projections. *)

type component = { stable_id : string; purpose : string }
type direction = Input | Output
type port_kind = Intent | Evidence | State | Telemetry | Scene
type port = {
  stable_id : string;
  component_id : string;
  name : string;
  direction : direction;
  kind : port_kind;
  count : int;
}

type channel = {
  stable_id : string;
  component_id : string;
  metric_id : string option;
  fpp_name : string;
}

type edge_kind = Admission | Execution | Evidence_flow | State_flow | Projection
type edge = {
  stable_id : string;
  from_component : string;
  from_port : string;
  to_component : string;
  to_port : string;
  kind : edge_kind;
}

type verifier_kind =
  | Fpp_validation
  | Metric_channel_mapping
  | Window_disjointness
  | Execution_mediation
  | Ui_admission_isolation
  | Projection_correspondence
  | Formal_nonvacuity

type verifier = { stable_id : string; kind : verifier_kind }

type lifecycle_transition = {
  signal : string;
  actions : string list;
  target_state : string;
}

type lifecycle_state = {
  stable_id : string;
  transitions : lifecycle_transition list;
}

type lifecycle_machine = {
  stable_id : string;
  component_id : string;
  instance_id : string;
  initial_state : string;
  states : lifecycle_state list;
}

type fault_severity = Fault_diagnostic | Fault_warning | Fault_fatal
type fault_event = {
  stable_id : string;
  component_id : string;
  severity : fault_severity;
  format : string;
}

type gate_kind = Formal_gate | Stress_gate | Reliability_gate | Full_gate
  | Swarm_verification
type gate_command = {
  stable_id : string;
  component_id : string;
  kind : gate_kind;
  intent_id : string;
}

type effect_kind =
  | Dependability_process_attempt
  | Verification_suite_execution
  | Durable_artifact_publication
  | External_resource_observation
  | Repository_source_observation
  | Approval_nonce_consumption
  | Writer_lease_transition
  | Production_activation_transition
  | Network_scope_transition
  | Credential_lease_transition
  | Controlled_filesystem_materialization
  | Candidate_tree_verification
  | Jujutsu_observation
  | Jujutsu_local_mutation
  | Jujutsu_history_rewrite
  | Jujutsu_recovery
  | Jujutsu_remote_synchronization
  | Jujutsu_remote_publish
  | Formal_oracle_execution

val effect_kinds : effect_kind list
val effect_kind_id : effect_kind -> string
val effect_kind_of_jujutsu_operation : Jj_operation.t -> effect_kind

type miq_route = {
  selector_id : string;
  required_capability_id : string;
  assigned_agent_id : string;
}

type verification_profile = Verification_fast | Verification_full

type jujutsu_action_role = Observe_before | Execute | Observe_after

val jujutsu_action_role_id : jujutsu_action_role -> string

type action_work =
  | Topology_gate
  | Repository_build of {
      profile : verification_profile;
      build_command : string;
    }
  | Repository_verification_suite of {
      profile : verification_profile;
      suite_id : string;
      executable : string;
    }
  | Clock_work of Jj_action_kind.auxiliary_role
  | Filesystem_work of Jj_action_kind.auxiliary_role
  | External_resource_work of Jj_action_kind.auxiliary_role
  | Repository_source_work of Jj_action_kind.auxiliary_role
  | Approval_nonce_work of Jj_action_kind.auxiliary_role
  | Writer_lease_work of Jj_action_kind.auxiliary_role
  | Network_scope_work of Jj_action_kind.auxiliary_role
  | Credential_lease_work of Jj_action_kind.auxiliary_role
  | Activation_transition_work of Jj_action_kind.frontier_action
  | Mutation_frontier_work of Jj_action_kind.frontier_action
  | Materialization_work of Jj_action_kind.auxiliary_role
  | Candidate_verification_work of Jj_action_kind.candidate_step
  | Formal_oracle_work of Jj_action_kind.formal_process
  | Jujutsu_readback_work of Jj_action_kind.auxiliary_role
  | Completion_receipt_work of Jj_action_kind.auxiliary_role
  | Jujutsu_work of {
      operation : Jj_operation.t;
      role : jujutsu_action_role;
    }
(** Closed declarative work identity. It carries data only: no callback,
    process handle, or execution authority. *)

val action_work_id : action_work -> string
val action_work_gaps : action_work -> string list
(** Refuses a typed wrapper around the wrong lower
    {!Jj_action_kind.auxiliary_role} or frontier constructor. *)

(** Exact 16-class Task-7A work denominator.  Readback and completion receipt
    work remain distinct from operation execution, and Reserve/Finalize remain
    distinct typed values inside the completion-receipt class. *)
val task7a_action_work_class_ids : string list
val task7a_action_work_class_digest : string
val task7a_completion_receipt_work_ids : string list
val task7a_completion_receipt_work_digest : string

type controlled_lifecycle_state =
  | Declared
  | Prepared
  | Admitted
  | Running
  | Readback
  | Terminal
  | Refused
  | Indeterminate
  | Stale

type conditional_control_state =
  | Guarded
  | Consume_ready
  | Action_terminal
  | Decision_pending
  | Continue_selected
  | Branch_selected
  | Decision_indeterminate

type conditional_control_event =
  | Prefix_complete
  | Decision_committed
  | Decision_replayed
  | Condition_not_selected_recorded
  | Decision_refused

type conditional_channel_kind =
  | Bounded_family_prefix
  | Decision_receipt
  | Selected_branch_identity
  | Node_disposition

val controlled_lifecycle_states : controlled_lifecycle_state list
val controlled_lifecycle_state_id : controlled_lifecycle_state -> string
val conditional_control_states : conditional_control_state list
val conditional_control_state_id : conditional_control_state -> string
val conditional_control_events : conditional_control_event list
val conditional_control_event_id : conditional_control_event -> string
val conditional_channel_kinds : conditional_channel_kind list
val conditional_channel_kind_id : conditional_channel_kind -> string

val live_execution_posture : [ `Implemented_unavailable ]
(** Task 7A declares pure closed rows only.  It grants no bridge admission,
    effect execution, target currentness, or upper Task-8 activation. *)

type declarative_action = private {
  stable_id : string;
  command_id : string;
  assigned_agent_id : string;
  dependency_ids : string list;
  selector_id : string;
  required_capability_id : string;
  context_requirement_ids : string list;
  target_component_id : string;
  effect_kind : effect_kind;
  preparation_id : string;
  work : action_work;
}
(** Closed action intent owned by the topology. It contains no callback and
    grants no execution authority. *)

type declarative_activity = {
  stable_id : string;
  bridge_component_id : string;
  target_component_id : string;
  target_state : string;
  intent : string;
  constraints : string list;
  success_criteria : string list;
  required_capability_ids : string list;
  context_requirement_ids : string list;
  miq_routes : miq_route list;
  effect_kinds : effect_kind list;
  command_ids : string list;
  actions : declarative_action list;
}

val task7a_declaration_activities : declarative_activity list
val task7a_declaration_gaps : unit -> string list
val task7a_declaration_digest : string
(** Pure, non-admitted declarations for the constructible standalone Jujutsu
    operation and candidate projections.  The digest also binds the exact
    47-row static template denominator.  Nothing is inserted into {!authority}
    before Task-8/9 target and bridge mappings exist. *)

type static_template_class =
  | Standalone_operation_template
  | Standalone_phase_template
  | Conditional_family_template
  | Candidate_verification_template

type static_template = private {
  template_stable_id : string;
  template_class : static_template_class;
  template_schema_digest : string;
}

val task7a_static_templates : static_template list
val task7a_static_template_digest : string
(** Exactly 34 operation, ten phase-family, two conditional-family, and one
    candidate template.  Request-bound occurrence/node identities are never
    inserted into this static authority. *)

type conditional_projection_prerequisite =
  | Public_ten_phase_enum
  | Occurrence_phase_ordinal_accessor
  | Conditional_node_identity_accessor
  | Conditional_guard_control_ids
  | Conditional_edge_label_accessor
  | Readback_completion_work_carriers
  | Multi_target_activity_schema
  | Conditional_activity_schema
  | Failure_recovery_policy_schema
  | Plan_dispatch_identity_schema

type conditional_projection_error

val conditional_projection_error_code : conditional_projection_error -> string
val conditional_projection_prerequisite_status :
  conditional_projection_prerequisite ->
  (unit, conditional_projection_error) result

type conditional_activity_projection

type conditional_control_projection = private {
  control_node_id : string;
  control_node_kind : Jj_campaign_action.node_kind;
  control_guard_identity : string;
  control_parent_occurrence_id : string option;
  control_parent_ordinal : int option;
  control_decision_id : string option;
  control_prefix_id : string option;
  control_branch_ids : string list;
}

type conditional_edge_projection = private {
  projected_edge_source_id : string;
  projected_edge_target_id : string;
  projected_edge_label : string;
  projected_edge_guard_identity : string;
}

val standalone_phase_activity :
  'phase Jj_campaign_action.standalone_phase_request ->
  (declarative_activity, conditional_projection_error) result

val b_success_activity :
  Jj_campaign_action.b_campaign Jj_campaign_action.conditional_plan ->
  (conditional_activity_projection, conditional_projection_error) result

val completion_reconcile_activity :
  Jj_campaign_action.completion_reconcile Jj_campaign_action.conditional_plan ->
  (conditional_activity_projection, conditional_projection_error) result

val conditional_projection_family_id : conditional_activity_projection -> string
val conditional_projection_activity_id : conditional_activity_projection -> string
val conditional_projection_plan_digest : conditional_activity_projection -> string
val conditional_projection_dispatch_key : conditional_activity_projection -> string
val conditional_projection_external_actions :
  conditional_activity_projection -> declarative_action list
val conditional_projection_internal_controls :
  conditional_activity_projection -> conditional_control_projection list
val conditional_projection_edges :
  conditional_activity_projection -> conditional_edge_projection list
val conditional_projection_posture : [ `Implemented ]
(** Pure request-bound projection only.  External action occurrences and
    internal consume/decision controls are distinct exact denominators.  The
    result grants neither admission nor execution authority. *)

val expected_static_template_count : int
(** Exactly 34 standalone operations, 10 standalone phase families, two
    conditional families, and one candidate-verification prerequisite. *)

val constructible_static_template_count : int
(** All 47 pure static templates are constructible.  Dynamic occurrence and
    conditional projections remain outside the static registry. *)

type admitted_activity

val activity_digest_of : declarative_activity -> string
(** Canonical JSON digest of every activity carrier. *)

val action_digest_of : declarative_action -> string
(** Canonical JSON digest of every closed action carrier. *)

val admit_activity :
  stable_id:string -> (admitted_activity, string list) result
(** Looks up one activity in {!authority}, validates the complete authority,
    and returns no value when the stable id is empty, missing, duplicated, or
    the canonical activity envelope has drifted. *)

val admitted_activity_digest : admitted_activity -> string
val admitted_activity_authority_digest : admitted_activity -> string
val admitted_declaration : admitted_activity -> declarative_activity
val admitted_actions : admitted_activity -> declarative_action list
val declarative_activity_actions : declarative_activity -> declarative_action list
(** Read-only projections for downstream effect and fast-path validation.
    They do not make an admitted value caller-constructible. *)

module For_test : sig
  val declarative_action :
    stable_id:string -> command_id:string -> assigned_agent_id:string ->
    dependency_ids:string list -> selector_id:string ->
    required_capability_id:string -> context_requirement_ids:string list ->
    target_component_id:string -> effect_kind:effect_kind ->
    preparation_id:string -> declarative_action
  (** Narrow RED/mutation constructor. It is not an execution callback and
      cannot mint {!admitted_activity}. *)

  val declarative_action_work :
    stable_id:string -> command_id:string -> assigned_agent_id:string ->
    dependency_ids:string list -> selector_id:string ->
    required_capability_id:string -> context_requirement_ids:string list ->
    target_component_id:string -> effect_kind:effect_kind ->
    work:action_work -> preparation_id:string -> declarative_action
  (** Task-8 RED constructor with an explicit closed work carrier. *)

  val action_graph_gaps_for :
    expected_actions:declarative_action list -> declarative_activity -> string list
  (** Structural and exact-order diagnostics for an independently supplied
      closed action denominator. It does not register or admit the activity. *)

  type task7a_mutation =
    | Drop_declaration_activity
    | Duplicate_declaration_action
    | Claim_live_bridge
    | Drop_static_template
    | Reorder_work_class
    | Flatten_conditional_controls
    | Swap_completion_receipt_order

  val task7a_declaration_digest_with_mutation : task7a_mutation -> string
end

type requirement = {
  stable_id : string;
  statement : string;
  verifier_id : string;
  source : string;
  covered_elements : string list;
}

type execution_policy = {
  supervisor_component_id : string;
  bridge_component_id : string;
  worker_component_id : string;
  required_execution_edge_id : string;
}

type ui_isolation_policy = {
  ui_component_ids : string list;
  admission_component_ids : string list;
}

type model_policy = {
  fpp_model_name : string;
  fpp_topology_name : string;
  fpp_base_id : int;
  projection_surface_ids : string list;
}

type sqlite_transition_policy = {
  machine_id : string;
  source_state_id : string;
  signal_id : string;
  target_state_id : string;
  required_action_ids : string list;
}

type sqlite_policy = {
  machine_state_ids : (string * string list) list;
  required_transitions : sqlite_transition_policy list;
  fault_event_ids : string list;
  gate_command_ids : string list;
  activity_id : string;
  hazard_requirement_id : string;
}

type formal_policy = {
  execution : execution_policy;
  ui_isolation : ui_isolation_policy;
  model_contract : model_policy;
  sqlite : sqlite_policy;
}

type authority = {
  components : component list;
  ports : port list;
  channels : channel list;
  edges : edge list;
  verifiers : verifier list;
  lifecycle_machines : lifecycle_machine list;
  fault_events : fault_event list;
  gate_commands : gate_command list;
  activities : declarative_activity list;
  requirements : requirement list;
  formal_policy : formal_policy;
}

val component_names : string list
val debug_runtime_channels : channel list
val authority : authority
val source_digest : string
val source_digest_of : authority -> string
(*@ ensures String.length result = 64 *)
val model : Fpp_model.model
val to_fpp_model : authority -> Fpp_model.model

val validate_authority : authority -> string list
val validate : unit -> string list
(*@ ensures result = [] -> component_names <> [] *)
val metric_channel_gaps_for : authority -> string list
val metric_channel_gaps : unit -> string list
(*@ ensures List.length result >= 0 *)
val requirement_gaps_for : authority -> string list
val requirement_gaps : unit -> string list
val sqlite_dependability_gaps_for : authority -> string list
val sqlite_dependability_gaps : unit -> string list
val execution_bypass_gaps : authority -> string list
val ui_admission_gaps : authority -> string list

(** Diagnose actual half-open instance intervals from supplied models against
    Operations. This legacy diagnostic is not the normative five-owner
    allocation-window theorem and does not prove external models pairwise
    disjoint from one another. *)
val interval_gaps : (string * Fpp_model.model) list -> string list
(*@ ensures List.length result >= 0 *)

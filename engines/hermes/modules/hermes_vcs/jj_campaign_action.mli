(** Pure, non-authorizing campaign declarations. *)
type release
type formal
type disposable
type a0
type a1
type b_recovery
type completion_reserve
type completion_record
type completion_record_recovery
type completion_final
type fixture_manifest
type causal_failure
type sealed_vault
type formal_manifest
val fixture_manifest : Jj_id.Receipt.t -> fixture_manifest
val causal_failure : Jj_id.Event.t -> causal_failure
val sealed_vault : Jj_id.Receipt.t -> sealed_vault
type fault_case =
  | B_recovery_fault of Jj_recovery_schema.b_success_cut
  | Completion_record_recovery_fault of
      Jj_recovery_schema.completion_record_cut_point
      * Jj_recovery_schema.workspace_branch
      * Jj_recovery_schema.execution_mode
type disposable_profile = Semantics | Surface_equivalence | Fault of fault_case
type recovery_scope_class = Disposable_test | Production_record
type 'phase standalone_phase_request
type error =
  | Empty_manifest
  | Unbounded_manifest
  | Phase_context_mismatch
  | Empty_negative_control_denominator
  | Duplicate_negative_control
  | Unbounded_negative_control_denominator
val formal_manifest :
  tool:Jj_action_kind.formal_tool ->
  model:Jj_id.Formal_model.t ->
  source:Jj_id.Formal_source.t ->
  negative_controls:Jj_id.Negative_control.t list ->
  (formal_manifest, error) result
val formal_manifest_tool : formal_manifest -> Jj_action_kind.formal_tool
val formal_manifest_model : formal_manifest -> Jj_id.Formal_model.t
val formal_manifest_source : formal_manifest -> Jj_id.Formal_source.t
val formal_manifest_negative_controls :
  formal_manifest -> Jj_id.Negative_control.t list
val formal_manifest_cases : formal_manifest -> Jj_action_kind.formal_case list
val formal_manifest_digest : formal_manifest -> string
val release_request : request_id:Jj_id.Request.t -> release standalone_phase_request
val formal_request :
  request_id:Jj_id.Request.t -> manifest:formal_manifest ->
  formal standalone_phase_request
val disposable_request :
  request_id:Jj_id.Request.t -> profile:disposable_profile ->
  fixture:fixture_manifest -> disposable standalone_phase_request
val a0_request : request_id:Jj_id.Request.t -> a0 standalone_phase_request
val a1_request : request_id:Jj_id.Request.t -> selected_objects:int -> classified_objects:int -> (a1 standalone_phase_request, error) result
val completion_reserve_request :
  request_id:Jj_id.Request.t -> completion_reserve standalone_phase_request
val completion_record_request :
  request_id:Jj_id.Request.t ->
  workspace_branch:Jj_recovery_schema.workspace_branch ->
  completion_record standalone_phase_request
val b_recovery_request :
  request_id:Jj_id.Request.t -> causal_failure:causal_failure ->
  cut:Jj_recovery_schema.b_success_cut -> sealed_vault:sealed_vault ->
  b_recovery standalone_phase_request
val completion_record_recovery_request :
  request_id:Jj_id.Request.t -> causal_failure:causal_failure ->
  cut:Jj_recovery_schema.completion_record_cut_point ->
  workspace_branch:Jj_recovery_schema.workspace_branch ->
  mode:Jj_recovery_schema.execution_mode -> sealed_vault:sealed_vault ->
  scope_class:recovery_scope_class ->
  completion_record_recovery standalone_phase_request
val completion_final_request :
  request_id:Jj_id.Request.t -> completion_final standalone_phase_request
type occurrence
val occurrence_id : occurrence -> string
val occurrence_nonce : occurrence -> string
val occurrence_action : occurrence -> Jj_action_kind.t
type occurrence_descriptor = private {
  stable_occurrence_id : string;
  stable_nonce_id : string;
  occurrence_phase_id : string;
  occurrence_phase_ordinal : int;
  occurrence_action_identity : Jj_action_kind.t;
}
val occurrence_descriptor : occurrence -> occurrence_descriptor
val occurrence_phase : occurrence -> string
val occurrence_ordinal : occurrence -> int
val occurrence_projection_digest : occurrence -> string
type standalone_phase_kind = private
  | Release_phase
  | Formal_phase
  | Disposable_phase
  | A0_phase
  | A1_phase
  | B_recovery_phase
  | Completion_reserve_phase
  | Completion_record_phase
  | Completion_record_recovery_phase
  | Completion_final_phase
val standalone_phase_kinds : standalone_phase_kind list
val standalone_phase_kind_id : standalone_phase_kind -> string
val standalone_phase_kind : 'phase standalone_phase_request -> standalone_phase_kind
val standalone_phase_declarations : 'phase standalone_phase_request -> occurrence list
type approval_consume
val standalone_approval_consumptions :
  'phase standalone_phase_request -> approval_consume list
val approval_consume_id : approval_consume -> string
val approval_consume_parent_occurrence_id : approval_consume -> string
val approval_consume_parent_ordinal : approval_consume -> int
val approval_consume_action :
  approval_consume -> Jj_action_kind.auxiliary_role
val standalone_phase_count : int
val standalone_phase_denominator_digest : string
val standalone_projection_digest : 'phase standalone_phase_request -> string
val canonical_unsigned_bytes : occurrence list -> string
type b_campaign
type completion_reconcile
type _ conditional_family =
  | B_campaign : b_campaign conditional_family
  | Completion_reconcile_plan : completion_reconcile conditional_family
type completion_outcome = Applied_exact | Not_applied | Diverged

(** Closed, non-authorizing material for one occurrence approval.  Identity
    values remain typed until the canonical encoding boundary. *)
type approval_constraint =
  | Authorized_phase
  | Exact_head
  | Exact_tree
  | No_publication
  | Bounded_resources
  | Readback_required
  | Recovery_required

type expected_identity =
  | Expected_repository of Jj_id.Repository.t
  | Expected_workspace of Jj_id.Workspace.t
  | Expected_operation of Jj_id.Operation.t
  | Expected_change of Jj_id.Change.t
  | Expected_commit of Jj_id.Commit.t
  | Expected_bookmark of Jj_id.Bookmark.t
  | Expected_remote of Jj_id.Remote.t
  | Expected_receipt of Jj_id.Receipt.t

type b_approval_context =
  | B_success_context of Jj_id.Operation.t * Jj_id.Receipt.t
  | B_guard_context of
      Jj_recovery_schema.b_success_cut * Jj_recovery_schema.b_disposition
      * Jj_id.Operation.t * Jj_id.Receipt.t
  | B_recovery_context of
      Jj_recovery_schema.b_success_cut * Jj_id.Operation.t * Jj_id.Receipt.t

type completion_approval_context =
  | Completion_reserve_context of Jj_id.Receipt.t
  | Completion_record_context of
      Jj_recovery_schema.workspace_branch * Jj_id.Receipt.t
  | Completion_record_recovery_context of
      Jj_recovery_schema.completion_record_cut_point
      * Jj_recovery_schema.workspace_branch
      * Jj_recovery_schema.execution_mode
      * Jj_id.Receipt.t
  | Completion_final_context of Jj_id.Receipt.t
  | Completion_reconcile_pending_context of Jj_id.Receipt.t
  | Completion_reconcile_outcome_context of
      completion_outcome * Jj_id.Receipt.t

type approval_phase_context =
  | Approval_release of Jj_id.Receipt.t
  | Approval_formal of formal_manifest * Jj_id.Receipt.t
  | Approval_a0 of Jj_id.Operation.t
  | Approval_a1 of int * int * Jj_id.Receipt.t
  | Approval_b of b_approval_context
  | Approval_completion of completion_approval_context

type approval_payload
type approval_projection = private {
  approval_reference : Jj_id.Approval.t;
  occurrence : occurrence;
  occurrence_ordinal : int;
  phase_context : approval_phase_context;
  constraints : approval_constraint list;
  expected_identities : expected_identity list;
}

val approval_payload :
  approval_reference:Jj_id.Approval.t ->
  occurrence:occurrence ->
  phase_context:approval_phase_context ->
  constraints:approval_constraint list ->
  expected_identities:expected_identity list ->
  (approval_payload, error) result
val approval_projection : approval_payload -> approval_projection
val canonical_approval_unsigned_bytes : approval_payload -> string
type _ guard =
  | B_guard : Jj_recovery_schema.b_success_cut * Jj_recovery_schema.b_disposition -> b_campaign guard
  | Completion_guard : completion_outcome -> completion_reconcile guard
type 'family conditional_branch
type 'family conditional_plan
val derive_b_campaign_plan : request_id:Jj_id.Request.t -> (b_campaign conditional_plan, error) result
val derive_completion_reconcile_plan : request_id:Jj_id.Request.t -> (completion_reconcile conditional_plan, error) result
val common_declarations : 'family conditional_plan -> occurrence list
val conditional_branches : 'family conditional_plan -> 'family conditional_branch list
val branch_guard : 'family conditional_branch -> 'family guard
val branch_declarations : 'family conditional_branch -> occurrence list
val conditional_branch_count : 'family conditional_plan -> int
(* True exactly when every authorizable occurrence and nonce identity in the
   common spine and all dormant branches occurs once. *)
val conditional_identities_are_disjoint : 'family conditional_plan -> bool
type node_kind = Consume_node_kind | Action_node_kind | Decision_node_kind
type node_guard_shape =
  | Always_guard
  | All_continue_guard of int
  | Branch_selected_guard
type guard_descriptor = private
  | Always_guard_descriptor
  | All_continue_guard_descriptor of { control_ids : string list }
  | Branch_selected_guard_descriptor of {
      control_id : string;
      branch_id : string;
    }
val guard_descriptor_identity : guard_descriptor -> string
type conditional_node_descriptor = private
  | Consume_descriptor of {
      node_id : string;
      guard : guard_descriptor;
      parent_occurrence_id : string;
      parent_occurrence_ordinal : int;
      consume_action_identity : Jj_action_kind.auxiliary_role;
    }
  | Action_descriptor of {
      node_id : string;
      guard : guard_descriptor;
      occurrence : occurrence_descriptor;
    }
  | Decision_descriptor of {
      node_id : string;
      guard : guard_descriptor;
      control_id : string;
      prefix_id : string;
      branch_ids : string list;
    }
type conditional_edge_descriptor = private {
  edge_source_id : string;
  edge_target_id : string;
  edge_label : string;
  edge_guard_identity : string;
}
type 'family node
type conditional_edge
val conditional_family :
  'family conditional_plan -> 'family conditional_family
val conditional_nodes : 'family conditional_plan -> 'family node list
val node_kind : 'family node -> node_kind
val node_guard_shape : 'family node -> node_guard_shape
val node_nonce : 'family node -> string option
val conditional_node_descriptor : 'family node -> conditional_node_descriptor
val node_count : 'family conditional_plan -> int
val consume_node_count : 'family conditional_plan -> int
val action_node_count : 'family conditional_plan -> int
val decision_node_count : 'family conditional_plan -> int
val control_count : 'family conditional_plan -> int
val guarded_edges : 'family conditional_plan -> conditional_edge list
val edge_source : conditional_edge -> string
val edge_target : conditional_edge -> string
val edge_label : conditional_edge -> string
val edge_guard_identity : conditional_edge -> string
val conditional_edge_descriptor : conditional_edge -> conditional_edge_descriptor
val edges_are_acyclic : 'family conditional_plan -> bool
val all_nodes_reach_aggregate : 'family conditional_plan -> bool
val conditional_node_projection_digest : 'family conditional_plan -> string
val guarded_edge_projection_digest : 'family conditional_plan -> string
val conditional_projection_digest : 'family conditional_plan -> string
(* Canonical bytes bind the common spine, ordered branch guards, and complete
   dormant branch denominator. They are structural and non-authorizing. *)
val canonical_conditional_unsigned_bytes : 'family conditional_plan -> string
val source_digest : string

module For_test : sig
  type mutation = Drop_node | Drop_edge | Reverse_edge
  val canonical_with_mutation :
    'family conditional_plan -> mutation -> string

  type descriptor_mutation =
    | Drop_descriptor
    | Reorder_descriptors
    | Mismatch_identity
  val standalone_phase_denominator_digest_with_mutation :
    descriptor_mutation -> string
  val standalone_projection_digest_with_mutation :
    'phase standalone_phase_request -> descriptor_mutation -> string
  val standalone_projection_digest_without_approval_consumptions :
    'phase standalone_phase_request -> string
  val conditional_node_projection_digest_with_mutation :
    'family conditional_plan -> descriptor_mutation -> string
  val guarded_edge_projection_digest_with_mutation :
    'family conditional_plan -> descriptor_mutation -> string

  type approval_mutation =
    | Change_approval_phase
    | Change_occurrence_ordinal
    | Change_approval_constraint
    | Change_expected_identity
  val canonical_approval_with_mutation :
    approval_payload -> approval_mutation -> string

  type source_mutation =
    | Change_manifest_bound
    | Drop_constraint
    | Drop_descriptor_schema
    | Drop_formal_manifest_schema
    | Drop_formal_consume_schema
  val source_digest_with_mutation : source_mutation -> string
end

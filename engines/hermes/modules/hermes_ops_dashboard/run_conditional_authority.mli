(** Pure Task-8 conditional-control authority.

    The constructible surface derives its complete family/state/event/channel
    and decision-preparation schema only from the opaque campaign plan.  It
    accepts no caller branch, outcome, list, digest, callback, cut, or dynamic
    receipt.  Operational currentness remains fail-closed until every named
    lower store/owner receipt has a real constructor. *)

type diagnostic_code =
  | Family_denominator_mismatch
  | State_denominator_mismatch
  | Event_denominator_mismatch
  | Channel_denominator_mismatch
  | Decision_denominator_mismatch
  | Decision_control_mismatch
  | Decision_prefix_mismatch
  | Decision_branch_mismatch
  | Decision_guard_mismatch
  | Projection_digest_mismatch
  | Store_owner_receipts_unavailable

type diagnostic = private {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
}

val diagnostic_code : diagnostic -> diagnostic_code
val diagnostic_message : diagnostic -> string
val diagnostic_coordinate : diagnostic -> Ops_capability.coordinate
val diagnostic_origin : diagnostic -> Ops_capability.rca_origin
val string_of_diagnostic_code : diagnostic_code -> string

type _ family =
  | B_family : Jj_campaign_action.b_campaign family
  | Completion_family : Jj_campaign_action.completion_reconcile family

type packed_family = Family : 'family family -> packed_family

val families : packed_family list
val family_id_of : 'family family -> string
val packed_family_id : packed_family -> string

type _ lifecycle_state =
  | Guarded : 'family lifecycle_state
  | Consume_ready : 'family lifecycle_state
  | Action_terminal : 'family lifecycle_state
  | Decision_pending : 'family lifecycle_state
  | Continue_selected : Jj_campaign_action.b_campaign lifecycle_state
  | B_branch_selected : Jj_campaign_action.b_campaign lifecycle_state
  | Applied_exact_selected :
      Jj_campaign_action.completion_reconcile lifecycle_state
  | Not_applied_selected :
      Jj_campaign_action.completion_reconcile lifecycle_state
  | Diverged_selected :
      Jj_campaign_action.completion_reconcile lifecycle_state
  | Decision_indeterminate : 'family lifecycle_state

val lifecycle_states : 'family family -> 'family lifecycle_state list
val lifecycle_state_id : 'family lifecycle_state -> string

type event =
  | Prefix_complete
  | Decision_committed
  | Decision_replayed
  | Condition_not_selected_recorded
  | Decision_refused

val events : event list
val event_id : event -> string

type channel =
  | Family_prefix_identity
  | Decision_receipt
  | Selected_branch_identity
  | Node_disposition

val channels : channel list
val channel_id : channel -> string

type 'family decision_preparation
type 'family schema

val derive :
  'family Jj_campaign_action.conditional_plan ->
  ('family schema, diagnostic) result
(** Derives every decision exclusively from the plan's private node and edge
    projections.  No caller-supplied discriminator exists. *)

val validate : 'family schema -> (unit, diagnostic) result
val family_id : 'family schema -> string
val decision_preparations :
  'family schema -> 'family decision_preparation list
val decision_node_id : 'family decision_preparation -> string
val decision_control_id : 'family decision_preparation -> string
val decision_prefix_id : 'family decision_preparation -> string
val decision_branch_ids : 'family decision_preparation -> string list
val decision_guard_identity : 'family decision_preparation -> string
val decision_preparation_digest : 'family decision_preparation -> string
val schema_digest : 'family schema -> string

(** These types are deliberately nonconstructible.  They name the exact
    future joins without forging absent lower-owner current receipts. *)
type 'family admitted_plan_current
type dispatch_claim_current
type 'family wrapper_dispositions_current
type effect_prefix_current
type event_prefix_current
type mutation_frontier_current
type resource_vault_current
type 'family readback_current
type 'family prefix_current
type interpreter
type 'family decision_current
type 'family guarded_node_current
type dormant_closed_receipt
type 'purpose abandonment_current
type 'purpose node_and_nonce_terminal_current
type activity_result_current
type completion_final_terminal
type completion_reconcile_terminal
type 'phase campaign_terminal_current

val prepare_prefix :
  schema:'family schema ->
  plan:'family admitted_plan_current ->
  claim:dispatch_claim_current ->
  wrappers:'family wrapper_dispositions_current ->
  effects:effect_prefix_current ->
  events:event_prefix_current ->
  frontier:mutation_frontier_current ->
  posture:resource_vault_current ->
  readback:'family readback_current ->
  ('family prefix_current, diagnostic) result

val create :
  Run_root_bootstrap.conditional_interpreter_part ->
  (interpreter, diagnostic) result

val prepare_decision :
  interpreter -> schema:'family schema -> prefix:'family prefix_current ->
  ('family decision_current, diagnostic) result

val close_dormant :
  interpreter -> decision:'family decision_current ->
  node:'family guarded_node_current ->
  (dormant_closed_receipt, diagnostic) result

val close_claimed_unentered :
  interpreter -> plan:'family admitted_plan_current ->
  abandonment:'purpose abandonment_current ->
  ('purpose node_and_nonce_terminal_current, diagnostic) result

val validate_campaign_terminal :
  interpreter -> plan:'phase admitted_plan_current ->
  result:activity_result_current -> events:event_prefix_current ->
  ('phase campaign_terminal_current, diagnostic) result

val reconcile_recovery_only :
  Run_root_bootstrap.conditional_recovery_part ->
  decisions:Dependability_dispatch_store.conditional_inventory_current ->
  abandonments:Dependability_dispatch_store.abandonment_inventory_current ->
  nonces:Dependability_authority_store.approval_inventory_current ->
  (Dependability_owner_inventory.conditional_terminal_current, diagnostic)
  result

type unavailable_operation =
  | Prepare_prefix_operation
  | Create_interpreter_operation
  | Prepare_decision_operation
  | Close_dormant_operation
  | Close_claimed_unentered_operation
  | Validate_campaign_terminal_operation
  | Reconcile_recovery_only_operation

val unavailable_operations : unavailable_operation list
val unavailable_operation_id : unavailable_operation -> string
val prerequisite_status : unavailable_operation -> (unit, diagnostic) result
val production_posture : [ `Implemented_unavailable ]
val source_digest : string

module For_test : sig
  type mutation =
    | Drop_decision
    | Reorder_decisions
    | Mismatch_control
    | Mismatch_prefix
    | Mismatch_branch
    | Mismatch_family
    | Drop_state
    | Reorder_events
    | Drop_channel
    | Mismatch_projection_digest

  val mutate : mutation -> 'family schema -> 'family schema

  type source_mutation =
    | Drop_family
    | Drop_state_schema
    | Drop_event
    | Drop_channel_schema
    | Drop_decision_field
    | Add_caller_branch_input
    | Add_caller_outcome_input
    | Add_caller_list_input
    | Add_caller_digest_input
    | Add_caller_callback_input
    | Construct_authorizing_type
    | Use_placeholder_interpreter_part
    | Use_placeholder_recovery_carriers

  val source_digest_with_mutation : source_mutation -> string
end

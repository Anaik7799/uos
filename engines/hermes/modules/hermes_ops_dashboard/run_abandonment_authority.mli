(** Bounded, nonauthorizing foundation for abandonment evidence joining.

    The complete authority cannot yet be constructed: root bootstrap exposes
    neither abandonment part nor the seven lower producer seals.  The dispatch
    store now exposes only its native read-only current abandonment inventory;
    it grants no terminal evidence or commit authority.  The operational
    entries therefore fail closed without accepting substitute strings, lists,
    cuts, branches, digests, callbacks, or executable capabilities. *)

type rca_origin = Specification | Implementation | Environment | Evidence | Control
type diagnostic

type prerequisite =
  | Root_abandonment_authority_part
  | Root_abandonment_recovery_part
  | Approved_plan_current_receipt
  | Dispatch_claim_current_receipt
  | Target_entry_inventory_current_receipt
  | Effect_prefix_current_receipt
  | Event_prefix_current_receipt
  | Frontier_current_receipt
  | Quiescent_or_fenced_current_receipt
  | Before_after_current_receipt
  | Seven_distinct_producer_seals
  | Dispatch_abandonment_writer_capability
  | Dispatch_abandonment_inventory_current_carrier

val prerequisite_id : prerequisite -> string
val prerequisite_status : prerequisite -> (unit, diagnostic) result
val diagnostic_code : diagnostic -> string
val diagnostic_prerequisite : diagnostic -> prerequisite
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

val production_posture : [ `Implemented_unavailable ]

type global_no_effect = Dependability_abandonment_protocol.global_no_effect
type fenced_unentered_tail =
  Dependability_abandonment_protocol.fenced_unentered_tail

type 'purpose purpose = 'purpose Dependability_abandonment_protocol.purpose =
  | Global_no_effect : global_no_effect purpose
  | Fenced_unentered_tail : fenced_unentered_tail purpose

type role =
  | Claim
  | Target_entry
  | Effect
  | Event
  | Frontier
  | Session
  | Before_after

type requirement =
  | Exact_dispatch_session_attempt_claim
  | No_source_changing_target_entry
  | Terminal_entered_target_prefix_and_tail_unentered
  | No_effect_applied
  | Terminal_entered_effect_prefix_and_tail_unentered
  | No_effect_event
  | Terminal_entered_event_prefix_and_tail_unentered
  | No_mutation_attempted
  | Terminal_mutation_frontier_and_tail_unentered
  | Quiescent_or_fenced_dead
  | Exact_operation_tree_source_equal_and_resources_released
  | Pending_transition_and_writer_fence_retained

val purpose_id : 'purpose purpose -> string
val role_id : role -> string
val requirement_id : requirement -> string

type 'purpose denominator

val denominator : 'purpose purpose -> 'purpose denominator
(** Returns the fixed authority-owned denominator; callers cannot supply or
    alter its members or order. *)

val denominator_count : 'purpose denominator -> int
val denominator_requires : 'purpose denominator -> role -> bool
val denominator_position : 'purpose denominator -> role -> int option
val role_requirement : 'purpose denominator -> role -> requirement

type t

val create :
  Run_root_bootstrap.abandonment_authority_part -> (t, diagnostic) result
(** Consumes only the native root part type and fails with
    [Root_abandonment_authority_part] while that part and its seven producer
    seals remain unconstructible. *)

val commit_global_no_effect :
  unit ->
  ( global_no_effect Dependability_dispatch_store.abandonment_current,
    diagnostic )
  result

val commit_fenced_unentered_tail :
  unit ->
  ( fenced_unentered_tail Dependability_dispatch_store.abandonment_current,
    diagnostic )
  result

val reconcile_recovery_only :
  Run_root_bootstrap.abandonment_recovery_part ->
  (Dependability_dispatch_store.abandonment_inventory_current, diagnostic)
  result
(** The three operational probes are typed unavailable and perform no lower
    prepare, seal, compose, commit, inventory, bridge, or execution call. *)

val source_digest : string

module For_test : sig
  type denominator_mutation =
    | Drop_claim
    | Drop_target_entry
    | Drop_effect
    | Drop_event
    | Drop_frontier
    | Drop_session
    | Drop_before_after
    | Duplicate_session
    | Swap_effect_and_event
    | Use_other_purpose_requirements

  val denominator_is_exact_with_mutation :
    'purpose purpose -> denominator_mutation -> bool

  type source_mutation =
    | Drop_lower_protocol_source
    | Drop_root_bootstrap_source
    | Drop_dispatch_store_source
    | Drop_global_no_effect_purpose
    | Drop_fenced_unentered_tail_purpose
    | Drop_role_denominator
    | Swap_role_order
    | Drop_current_receipt_prerequisites
    | Drop_producer_seals_prerequisite
    | Drop_dispatch_writer_prerequisite
    | Enable_create
    | Enable_commit
    | Enable_reconcile
    | Coerce_global_to_fenced_purpose
    | Use_placeholder_recovery_carrier
    | Use_unit_create_placeholder

  val source_digest_with_mutation : source_mutation -> string
end

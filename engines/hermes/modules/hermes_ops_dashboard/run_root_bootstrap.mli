(** Lower phase-indexed root-bootstrap distribution core.

    This Task-6 surface can consume only the exact lower authority-store
    bundle that exists today.  It distributes its nominal role capabilities
    and peer-open fences once; it does not open peer owners, allocate producer
    seals, construct an inventory-current value, activate an upper runtime, or
    expose a Task-8 event/effect/target view.

    Recovery and recovery-only roots remain typed unavailable while the five
    owners expose only prepared inventory fragments and the authority owner
    exposes no peer inventory-fence or bound recovery-session protocol. *)

type rca_origin = Specification | Implementation | Environment | Evidence | Control
type diagnostic

val diagnostic_code : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

type unavailable_prerequisite =
  | Five_owner_inventory_current_carriers
  | Peer_inventory_fence_bundle
  | Authority_recovery_bound_session
  | Recovery_only_terminal_current_carrier
  | Target_entry_inventory_current_carrier
  | Effect_prefix_current_carrier
  | Event_prefix_current_carrier
  | Mutation_frontier_current_carrier
  | Quiescent_or_fenced_current_carrier
  | Before_after_current_carrier
  | Abandonment_producer_seal_bundle
  | Dispatch_abandonment_writer_capability
  | Dispatch_conditional_decision_capability
  | Dispatch_abandonment_inventory_current_carrier
  | Dispatch_conditional_inventory_current_carrier
  | Authority_approval_inventory_current_carrier

val prerequisite_status :
  unavailable_prerequisite -> (unit, diagnostic) result

val production_posture : [ `Implemented_unavailable ]

type operational_root
type recovery_root
type recovery_only_root
type 'phase jj_owner_bundle

val compose_lower_operational_once :
  Dependability_authority_store.lower_open_result ->
  (operational_root jj_owner_bundle, diagnostic) result
(** Consumes all authority-store roles and its exact four-way peer-open bundle
    into one lower coordinator-owned carrier.  The result is explicitly only
    a lower distribution; it is not five-owner operational currentness. *)

val lower_bundle_posture :
  operational_root jj_owner_bundle -> [ `Lower_distribution_only ]

type operational_parts

type target_read_only_view_package
type effect_read_only_view_package
type event_read_only_view_package
type target_owner_parts
type abandonment_authority_part
type conditional_interpreter_part

val take_target_read_only_views :
  operational_parts -> (target_read_only_view_package, diagnostic) result

val take_effect_read_only_views :
  operational_parts -> (effect_read_only_view_package, diagnostic) result

val take_event_read_only_views :
  operational_parts -> (event_read_only_view_package, diagnostic) result

val take_target_owner_parts :
  operational_parts -> (target_owner_parts, diagnostic) result

val take_abandonment_authority_part :
  operational_parts -> (abandonment_authority_part, diagnostic) result

val take_conditional_interpreter_part :
  operational_parts -> (conditional_interpreter_part, diagnostic) result
(** These packages are nominal and nonconstructible in the current
    foundation.  Probing them returns the exact absent-current prerequisite
    without consuming any existing Task-6 role or peer-open fence. *)

val split_operational_once :
  operational_root jj_owner_bundle ->
  (operational_parts, diagnostic) result

val take_approval_nonce :
  operational_parts ->
  (Dependability_authority_store.approval_nonce_capability, diagnostic) result

val take_approval_dormancy :
  operational_parts ->
  (Dependability_authority_store.approval_dormancy_capability, diagnostic) result

val take_approval_abandonment :
  operational_parts ->
  (Dependability_authority_store.approval_abandonment_capability, diagnostic)
  result

val take_writer_fence :
  operational_parts ->
  (Dependability_authority_store.writer_fence_capability, diagnostic) result

val take_production_activation :
  operational_parts ->
  (Dependability_authority_store.production_activation_capability, diagnostic)
  result

val take_recovery_port_issuer :
  operational_parts ->
  ( Dependability_authority_store.recovery_port_issuer_capability,
    diagnostic ) result

val take_recovery_port_lifecycle :
  operational_parts ->
  ( Dependability_authority_store.recovery_port_lifecycle_capability,
    diagnostic ) result

val take_lifecycle :
  operational_parts ->
  (Dependability_authority_store.lifecycle_capability, diagnostic) result

val take_writer_open :
  operational_parts ->
  (Dependability_authority_store.writer_operational_open, diagnostic) result

val take_dispatch_open :
  operational_parts ->
  (Dependability_authority_store.dispatch_operational_open, diagnostic) result

val take_vault_open :
  operational_parts ->
  (Dependability_authority_store.vault_operational_open, diagnostic) result

val take_completion_open :
  operational_parts ->
  (Dependability_authority_store.completion_operational_open, diagnostic) result

type opened
type awaiting_abandonment
type awaiting_conditional
type awaiting_terminal
type 'phase recovery_parts
type abandonment_recovery_part
type conditional_recovery_part
type recovery_only_runtime_part
type recovery_only_tail

val split_recovery_once :
  recovery_root jj_owner_bundle ->
  (opened recovery_parts, diagnostic) result

val prepare_abandonment_recovery_once :
  opened recovery_parts ->
  (abandonment_recovery_part * awaiting_abandonment recovery_parts, diagnostic)
  result

val prepare_conditional_recovery_inputs_once :
  awaiting_abandonment recovery_parts ->
  abandonments:Dependability_dispatch_store.abandonment_inventory_current ->
  ( conditional_recovery_part *
    Dependability_dispatch_store.conditional_inventory_current *
    Dependability_authority_store.approval_inventory_current *
    awaiting_conditional recovery_parts,
    diagnostic )
  result
(** Joins only the native opaque dispatch and authority inventory-current
    carrier types.  The operation remains unreachable while recovery-root,
    peer-fence, and producer-seal prerequisites are unavailable; it accepts no
    caller row, list, digest, branch, absence flag, or substitute inventory. *)

type recovery_finish

val recovery_finish_kind :
  recovery_finish -> [ `Operational_ready | `Recovery_only_ready ]
(** Non-authorizing projection only.  The result itself has no public
    constructor and remains unconstructible in this foundation. *)

val finish_recovery_once :
  awaiting_conditional recovery_parts ->
  conditional:Dependability_owner_inventory.conditional_terminal_current ->
  (recovery_finish, diagnostic) result

val await_recovery_terminal_once :
  opened recovery_parts ->
  (awaiting_terminal recovery_parts, diagnostic) result

val split_recovery_only_once :
  recovery_only_root jj_owner_bundle ->
  (recovery_only_runtime_part * recovery_only_tail, diagnostic) result

val finish_recovery_only_once :
  recovery_only_tail ->
  terminal:Dependability_owner_inventory.recovery_only_terminal_current ->
  (operational_root jj_owner_bundle, diagnostic) result
(** These recovery entries cannot be reached from a public constructor in the
    present lower foundation and refuse without forging current inventory,
    producer seals, peer fences, or a successor operational root. *)

val source_digest : string

module For_test : sig
  type mutation =
    | Duplicate_operational_split
    | Duplicate_part_take
    | Forge_inventory_current
    | Invent_generic_producer_seal
    | Drop_peer_inventory_fence
    | Cast_recovery_phase
    | Promote_without_terminal
    | Add_upper_task8_view
    | Forge_target_read_only_view
    | Forge_effect_read_only_view
    | Forge_event_read_only_view
    | Forge_abandonment_authority_part
    | Forge_conditional_interpreter_part
    | Forge_abandonment_recovery_part
    | Skip_abandonment_recovery_phase
    | Drop_task8_prerequisite_schema
    | Reorder_task8_package_order
    | Flatten_native_recovery_inventory_join
    | Expose_recovery_finish_constructor

  val source_digest_with_mutation : mutation -> string
end

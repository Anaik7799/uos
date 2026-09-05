(** Bounded, fail-closed authority-store foundation.

    The store owns its SQLite database and exposes only opaque identities,
    prepared transitions, scoped role capabilities, redacted receipts, and
    nonauthorizing owner-inventory preparation.  It exposes no filename,
    path, SQL text, native database/statement/finalizer, clock function, or
    upper [Run_*]/[Ops_*] value.

    Durable production opening remains unavailable until the descriptor-held
    exclusive owner-lock prerequisite is implemented by the filesystem owner.
    The present operational posture is therefore a bounded volatile test
    foundation, never production activation authority. *)

type rca_origin = Specification | Implementation | Environment | Evidence | Control
type diagnostic

val diagnostic_code : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

module Digest : sig
  type t

  val make : string -> (t, diagnostic) result
  (** Accepts exactly one canonical lower-case SHA-256 hexadecimal digest. *)

  val to_hex : t -> string
  val equal : t -> t -> bool
end

type bootstrap_context

val prepare_bootstrap :
  build:Digest.t ->
  root:Digest.t ->
  configuration:Digest.t ->
  host:Digest.t ->
  pins:Digest.t ->
  observed_at:Dependability_clock.receipt ->
  (bootstrap_context, diagnostic) result

val bootstrap_digest : bootstrap_context -> string

type operational
type role_bundle
type lower_open_result

val open_first_or_successor :
  location:Dependability_sqlite_location.reference ->
  bootstrap:bootstrap_context ->
  (lower_open_result, diagnostic) result
(** Refuses every registered production location while the physical exclusive
    owner-lock backend is unavailable.  A test-only volatile location may
    construct the non-production foundation used by the focused suite. *)

val operational : lower_open_result -> operational
val role_bundle : lower_open_result -> role_bundle
type peer_operational_open_bundle
type writer_operational_open
type dispatch_operational_open
type vault_operational_open
type completion_operational_open

val peer_operational_open_bundle : lower_open_result -> peer_operational_open_bundle
val split_peer_operational_open_once :
  peer_operational_open_bundle ->
  ( writer_operational_open * dispatch_operational_open *
    vault_operational_open * completion_operational_open,
    diagnostic ) result
val consume_writer_operational_open :
  writer_operational_open -> authority:operational -> (unit, diagnostic) result
val consume_dispatch_operational_open :
  dispatch_operational_open -> authority:operational -> (unit, diagnostic) result
val consume_vault_operational_open :
  vault_operational_open -> authority:operational -> (unit, diagnostic) result
val consume_completion_operational_open :
  completion_operational_open -> authority:operational -> (unit, diagnostic) result

type writer_inventory_fence
type dispatch_inventory_fence
type vault_inventory_fence
type completion_inventory_fence
val peer_inventory_fence_posture : [ `Implemented_unavailable ]

val owner_session_generation : operational -> int
(*@ ensures result >= 1 *)
val owner_session_digest : operational -> string
val store_epoch_digest : operational -> string
val operational_posture : operational -> [ `Volatile_test_foundation ]

(** These role capabilities are nominally distinct.  The bundle has one
    consuming accessor per role and no generic/store-wide accessor. *)
type approval_nonce_capability
type approval_dormancy_capability
type approval_abandonment_capability
type writer_fence_capability
type production_activation_capability
type recovery_port_issuer_capability
type recovery_port_lifecycle_capability
type lifecycle_capability

val take_approval_nonce :
  role_bundle -> (approval_nonce_capability, diagnostic) result
val take_approval_dormancy :
  role_bundle -> (approval_dormancy_capability, diagnostic) result
val take_approval_abandonment :
  role_bundle -> (approval_abandonment_capability, diagnostic) result
val take_writer_fence :
  role_bundle -> (writer_fence_capability, diagnostic) result
val take_production_activation :
  role_bundle -> (production_activation_capability, diagnostic) result
val take_recovery_port_issuer :
  role_bundle -> (recovery_port_issuer_capability, diagnostic) result
val take_recovery_port_lifecycle :
  role_bundle -> (recovery_port_lifecycle_capability, diagnostic) result
val take_lifecycle : role_bundle -> (lifecycle_capability, diagnostic) result

type approval_campaign_key
type approval_identity
type approval_occurrence
type prepared_approval_campaign
type approval_campaign_receipt
type approval_occurrence_nonce
type approval_nonce_readback
type approval_nonce_current
type approval_nonce_state =
  | Available
  | Consumed
  | Dormant_closed
  | Abandoned_closed

val approval_identity : Digest.t -> approval_identity
val approval_occurrence :
  identity:Digest.t -> nonce:Digest.t -> approval_occurrence

val prepare_approval_campaign_key :
  approval_nonce_capability ->
  approval:approval_identity -> plan:Digest.t ->
  (approval_campaign_key, diagnostic) result
val prepare_approval_campaign :
  key:approval_campaign_key -> request:Digest.t -> verification:Digest.t ->
  occurrences:approval_occurrence list ->
  observed_at:Dependability_clock.receipt ->
  (prepared_approval_campaign, diagnostic) result
val register_approval_campaign_once :
  approval_nonce_capability -> prepared_approval_campaign ->
  (approval_campaign_receipt, diagnostic) result
val approval_campaign_receipt_digest : approval_campaign_receipt -> string
val approval_campaign_occurrence_count : approval_campaign_receipt -> int
(*@ ensures result >= 1 *)
val approval_campaign_replayed : approval_campaign_receipt -> bool
val approval_occurrence_nonce :
  approval_campaign_receipt -> occurrence:approval_occurrence ->
  (approval_occurrence_nonce, diagnostic) result
val read_approval_nonce :
  approval_nonce_capability -> approval_occurrence_nonce ->
  (approval_nonce_readback, diagnostic) result
val approval_nonce_readback_state : approval_nonce_readback -> approval_nonce_state
val approval_nonce_readback_digest : approval_nonce_readback -> string
val reconcile_approval_nonce_current :
  approval_nonce_capability -> now:Dependability_clock.receipt ->
  approval_nonce_readback -> (approval_nonce_current, diagnostic) result
val approval_nonce_current_state : approval_nonce_current -> approval_nonce_state
val approval_nonce_current_digest : approval_nonce_current -> string
val approval_nonce_transition_posture : [ `Implemented_unavailable ]

type approval_campaign_inventory_readback
type approval_inventory_current

val read_approval_campaign_inventory :
  approval_nonce_capability -> campaign:approval_campaign_receipt ->
  (approval_campaign_inventory_readback, diagnostic) result
(** Owner-derived read-only inventory for exactly one opaque campaign receipt.
    It re-reads the campaign row, its ordered nonce denominator, and every
    current nonce pointer.  No caller supplies a key, row, list, state, digest,
    decision, abandonment, or callback. *)

val approval_campaign_inventory_readback_digest :
  approval_campaign_inventory_readback -> string
val approval_campaign_inventory_readback_nonce_count :
  approval_campaign_inventory_readback -> int

val reconcile_approval_campaign_inventory_current :
  approval_nonce_capability -> now:Dependability_clock.receipt ->
  campaign:approval_campaign_receipt ->
  approval_campaign_inventory_readback ->
  (approval_inventory_current, diagnostic) result
(** Re-reads the exact campaign/current-pointer denominator, rejects changed or
    cross-campaign input, and validates every stored clock receipt against
    [now].  Unchanged replay has one stable digest. *)

val approval_inventory_digest : approval_inventory_current -> string
val approval_inventory_campaign_count : approval_inventory_current -> int
val approval_inventory_nonce_count : approval_inventory_current -> int

type approval_inventory_terminal_prerequisite =
  | Campaign_open_current
  | Conditional_decision_terminal_evidence
  | Abandonment_terminal_evidence

val approval_inventory_terminal_prerequisites :
  approval_inventory_terminal_prerequisite list
val approval_inventory_terminal_posture : [ `Implemented_unavailable ]

type global_approval_inventory_prerequisite =
  | Closed_approval_campaign_inventory

(** Global restart enumeration remains unavailable.  The current closed SQLite
    owner has no operation that enumerates approval campaign keys/current nonce
    rows, and this module does not substitute a process-local index. *)
val global_approval_inventory_prerequisites :
  global_approval_inventory_prerequisite list
val global_approval_inventory_posture : [ `Implemented_unavailable ]

type activation_key
type prepared_initialization
type prepared_root_activation
type prepared_classification

type status = Missing | Root_active | Classified_active
type transition_receipt
type activation_readback
type activation_current

val prepare_activation_key :
  production_activation_capability ->
  root:Digest.t ->
  (activation_key, diagnostic) result

val activation_key_digest : activation_key -> string

val prepare_initialization :
  key:activation_key ->
  request:Digest.t ->
  evidence:Digest.t ->
  context:Digest.t ->
  observed_at:Dependability_clock.receipt ->
  (prepared_initialization, diagnostic) result

val initialize_first_missing :
  production_activation_capability ->
  prepared_initialization ->
  (transition_receipt, diagnostic) result
(** Generation zero is appended exactly once.  Same request replay returns the
    same receipt; a same-key/different-request replay conflicts. *)

val prepare_root_activation :
  predecessor:activation_readback ->
  request:Digest.t ->
  context:Digest.t ->
  observed_at:Dependability_clock.receipt ->
  (prepared_root_activation, diagnostic) result
(** Root activation derives its evidence identity from the sealed bootstrap
    context.  There is deliberately no source-observation argument. *)

val activate_root_once :
  production_activation_capability ->
  prepared_root_activation ->
  (transition_receipt, diagnostic) result

val prepare_classification :
  predecessor:activation_readback ->
  request:Digest.t ->
  evidence:Digest.t ->
  context:Digest.t ->
  observed_at:Dependability_clock.receipt ->
  (prepared_classification, diagnostic) result

val classify_once :
  production_activation_capability ->
  prepared_classification ->
  (transition_receipt, diagnostic) result

val transition_status : transition_receipt -> status
val transition_generation : transition_receipt -> int
(*@ ensures result >= 0 *)
val transition_id : transition_receipt -> string
val transition_replayed : transition_receipt -> bool

val read_status :
  production_activation_capability ->
  activation_key ->
  (activation_readback, diagnostic) result
(** Reads only identity, generation, status, and digests.  It cannot recreate
    a role capability or an upper execution authority. *)

val readback_status : activation_readback -> status
val readback_generation : activation_readback -> int
(*@ ensures result >= 0 *)
val readback_digest : activation_readback -> string

val reconcile_current :
  production_activation_capability ->
  now:Dependability_clock.receipt ->
  activation_readback ->
  (activation_current, diagnostic) result
(** Re-reads the exact pointer/transition and validates the stored bounded
    clock receipt against [now].  A stale row or expired receipt refuses. *)

val current_status : activation_current -> status
val current_generation : activation_current -> int
(*@ ensures result >= 0 *)
val current_digest : activation_current -> string

val prepare_activation_inventory :
  production_activation_capability ->
  manifest:Dependability_owner_inventory.Identity.t ->
  recovery_attempt:Dependability_owner_inventory.Identity.t ->
  challenge:Dependability_owner_inventory.Identity.t ->
  transition:Dependability_owner_inventory.Identity.t ->
  ( Dependability_owner_inventory.activation
    Dependability_owner_inventory.fragment_prepared,
    diagnostic )
  result
(** The owner derives the complete activation-row denominator and readback
    from its private store.  The result is explicitly prepared and
    nonauthorizing: this module cannot forge the abstract producer seal needed
    to construct a current fragment. *)

type drain_receipt
type close_receipt

val drain_once :
  lifecycle_capability -> (drain_receipt, diagnostic) result
val drain_receipt_digest : drain_receipt -> string
val drain_replayed : drain_receipt -> bool

val close_once :
  lifecycle_capability ->
  drain_receipt ->
  (close_receipt, diagnostic) result
val close_receipt_digest : close_receipt -> string
val close_replayed : close_receipt -> bool

val source_digest : string

module For_test : sig
  type mutation =
    | Drop_role_separation
    | Permit_production_without_lock
    | Drop_session_fence
    | Overwrite_transition
    | Drop_request_replay_check
    | Drop_pointer_cas
    | Skip_current_readback
    | Forge_inventory_current
    | Duplicate_peer_open
    | Forge_inventory_fence
    | Partial_nonce_denominator
    | Overwrite_nonce_state
    | Reopen_terminal_nonce
    | Forge_approval_inventory_current
    | Skip_approval_inventory_readback
    | Permit_global_inventory_without_closed_enumeration

  val source_digest_with_mutation : mutation -> string

  type approval_inventory_readback_mutation = Current_nonce_identity

  val mutate_approval_inventory_readback :
    approval_inventory_readback_mutation ->
    approval_campaign_inventory_readback ->
    approval_campaign_inventory_readback
end

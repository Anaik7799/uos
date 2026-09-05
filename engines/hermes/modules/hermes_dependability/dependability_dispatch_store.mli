(** Bounded, fail-closed dispatch-store foundation.

    The store owns its SQLite database and exposes no location, SQL, native
    database/statement/finalizer, branch value, executable action, or upper
    [Run_*]/[Ops_*] type.  Production opening remains implemented-unavailable
    until the authority store can transfer its nominal dispatch-open fence and
    the filesystem owner can hold the physical lock.

    The current foundation proves the durable dispatch claim lifecycle and an
    exact Undecided conditional row.  Decision and abandonment transitions are
    typed but unavailable until their Task-8 family-bound selection and
    producer-sealed evidence prerequisites exist. *)

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
  authority:Dependability_authority_store.operational ->
  observed_at:Dependability_clock.receipt ->
  (bootstrap_context, diagnostic) result
(** Binds the non-production foundation to the exact lower authority-store
    owner session, store epoch, clock receipt, and pure Jujutsu declarations. *)

val bootstrap_digest : bootstrap_context -> string

type operational
type role_bundle
type lower_open_result

val open_first_or_successor :
  fence:Dependability_authority_store.dispatch_operational_open ->
  location:Dependability_sqlite_location.reference ->
  bootstrap:bootstrap_context ->
  (lower_open_result, diagnostic) result
(** Registered production locations refuse with [Implemented_unavailable].
    A test-only volatile location can open this focused foundation only after
    consuming the exact nominal dispatch-open fence from the same authority
    owner session. *)

val operational : lower_open_result -> operational
val role_bundle : lower_open_result -> role_bundle
val owner_session_generation : operational -> int
(*@ ensures result >= 1 *)
val recovery_attempt_ordinal : operational -> int
(*@ ensures result >= 1 *)
val owner_session_digest : operational -> string
val store_epoch_digest : operational -> string
val operational_posture : operational -> [ `Volatile_test_foundation ]
val production_posture : operational -> [ `Implemented_unavailable ]

(** Mutually distinct one-shot role capabilities. *)
type dispatch_claim_capability
type conditional_decision_capability
type abandonment_writer_capability
type lifecycle_capability

val take_dispatch_claim :
  role_bundle -> (dispatch_claim_capability, diagnostic) result
val take_conditional_decision :
  role_bundle -> (conditional_decision_capability, diagnostic) result
val take_abandonment_writer :
  role_bundle -> (abandonment_writer_capability, diagnostic) result
val take_lifecycle : role_bundle -> (lifecycle_capability, diagnostic) result

type dispatch_key

val prepare_dispatch_key :
  dispatch_claim_capability ->
  logical_execution:Digest.t ->
  admission:Digest.t ->
  plan:Digest.t ->
  (dispatch_key, diagnostic) result

val dispatch_key_digest : dispatch_key -> string

type dispatch_status =
  | Not_dispatched
  | Dispatch_claimed
  | Terminal
  | Indeterminate

type prepared_registration
type prepared_claim
type transition_receipt
type dispatch_readback
type claim_current

val prepare_registration :
  key:dispatch_key ->
  request:Digest.t ->
  observed_at:Dependability_clock.receipt ->
  (prepared_registration, diagnostic) result

val register_not_dispatched_once :
  dispatch_claim_capability ->
  prepared_registration ->
  (transition_receipt, diagnostic) result
(** Appends the exact [Not_dispatched] row and an exact [Undecided]
    conditional row in one transaction.  Same request replay is stable and a
    same-key/different-request replay conflicts. *)

val read_dispatch :
  dispatch_claim_capability ->
  dispatch_key ->
  (dispatch_readback, diagnostic) result

val prepare_claim :
  predecessor:dispatch_readback ->
  request:Digest.t ->
  observed_at:Dependability_clock.receipt ->
  (prepared_claim, diagnostic) result

val claim_once :
  dispatch_claim_capability ->
  prepared_claim ->
  (transition_receipt, diagnostic) result
(** The sole [Not_dispatched -> Dispatch_claimed] CAS. *)

val transition_status : transition_receipt -> dispatch_status
val transition_ordinal : transition_receipt -> int
(*@ ensures result >= 0 *)
val transition_id : transition_receipt -> string
val transition_replayed : transition_receipt -> bool

val readback_status : dispatch_readback -> dispatch_status
val readback_ordinal : dispatch_readback -> int
(*@ ensures result >= 0 *)
val readback_digest : dispatch_readback -> string

val reconcile_claim_current :
  dispatch_claim_capability ->
  now:Dependability_clock.receipt ->
  dispatch_readback ->
  (claim_current, diagnostic) result
(** Re-reads the exact pointer/row, validates the owner session, recovery
    attempt and bounded clock currentness, and accepts only
    [Dispatch_claimed]. *)

val claim_digest : claim_current -> string
val claim_owner_session_digest : claim_current -> string
val claim_recovery_attempt_ordinal : claim_current -> int
(*@ ensures result >= 1 *)

type decision_status = Undecided | Decided | Decision_indeterminate
type decision_readback
type undecided_current
type decision_current

val read_decision :
  conditional_decision_capability ->
  claim_current ->
  (decision_readback, diagnostic) result

val decision_readback_status : decision_readback -> decision_status
val decision_readback_digest : decision_readback -> string

val reconcile_undecided_current :
  conditional_decision_capability ->
  now:Dependability_clock.receipt ->
  decision_readback ->
  (undecided_current, diagnostic) result

val undecided_current_digest : undecided_current -> string

type 'family prepared_decision_transition

val prepare_decision_transition :
  conditional_decision_capability ->
  claim:claim_current ->
  plan:'family Jj_campaign_action.conditional_plan ->
  ('family prepared_decision_transition, diagnostic) result
(** Refuses with [Decision_protocol_unavailable].  It accepts no branch,
    prefix, outcome, list, digest, or callback; the required family-bound
    semantic selection carrier does not yet exist. *)

val commit_decision_once :
  conditional_decision_capability ->
  'family prepared_decision_transition ->
  (decision_current, diagnostic) result

type abandonment_status = No_abandonment | Abandonment_committed
type abandonment_readback
type 'purpose abandonment_current
type 'purpose prepared_abandonment_transition

val read_abandonment :
  abandonment_writer_capability ->
  claim_current ->
  (abandonment_readback, diagnostic) result

val abandonment_readback_status : abandonment_readback -> abandonment_status
val abandonment_readback_digest : abandonment_readback -> string

val prepare_abandonment_transition :
  abandonment_writer_capability ->
  claim:claim_current ->
  evidence:
    'purpose Dependability_abandonment_protocol.abandonment_evidence_current ->
  ('purpose prepared_abandonment_transition, diagnostic) result
(** Refuses with [Abandonment_protocol_unavailable].  The lower evidence
    protocol deliberately exposes neither its context nor the dispatch tail
    ledger needed to derive node accounting. *)

val commit_abandonment_once :
  abandonment_writer_capability ->
  'purpose prepared_abandonment_transition ->
  ('purpose abandonment_current, diagnostic) result

type conditional_inventory_current
type abandonment_inventory_current

val reconcile_restart_inventories :
  lifecycle_capability -> now:Dependability_clock.receipt ->
  (conditional_inventory_current * abandonment_inventory_current, diagnostic)
  result
(** Re-reads the owner-private, ordered decision and abandonment identity
    denominators.  The caller supplies no row, list, digest, branch, absence
    flag, or callback.  Exact unchanged replay is stable.  These are current
    read-only identities, not terminal semantic or commit authority. *)

val conditional_inventory_digest : conditional_inventory_current -> string
val conditional_inventory_decision_count : conditional_inventory_current -> int
val abandonment_inventory_digest : abandonment_inventory_current -> string
val abandonment_inventory_commitment_count :
  abandonment_inventory_current -> int

(** Terminal credit remains unavailable because the current closed SQLite
    inventory operation exposes ordered identities, not family selections,
    decision states, or the exact entered-prefix/unentered-tail ledger. *)
val conditional_inventory_terminal_posture :
  [ `Implemented_unavailable ]
val abandonment_inventory_terminal_posture :
  [ `Implemented_unavailable ]

val prepare_dispatch_inventory :
  lifecycle_capability ->
  manifest:Dependability_owner_inventory.Identity.t ->
  recovery_attempt:Dependability_owner_inventory.Identity.t ->
  challenge:Dependability_owner_inventory.Identity.t ->
  transition:Dependability_owner_inventory.Identity.t ->
  ( Dependability_owner_inventory.dispatch
    Dependability_owner_inventory.fragment_prepared,
    diagnostic )
  result
(** Derives the complete private dispatch/decision/abandonment row
    denominator and readback.  It remains prepared and nonauthorizing because
    the dispatch producer seal is intentionally unavailable. *)

type drain_receipt
type close_receipt

val drain_once : lifecycle_capability -> (drain_receipt, diagnostic) result
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
    | Drop_nominal_open_fence
    | Drop_session_attempt_fence
    | Overwrite_dispatch
    | Drop_request_replay_check
    | Drop_pointer_cas
    | Skip_current_readback
    | Forge_decision
    | Forge_abandonment
    | Forge_conditional_inventory
    | Forge_abandonment_inventory
    | Skip_restart_inventory_readback
    | Forge_inventory_current

  val source_digest_with_mutation : mutation -> string
end

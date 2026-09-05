(** Bounded private Completion-receipt store foundation.

    The owner holds its SQLite database, schema, statements and finalizer.  A
    caller can receive only one of five nominal capabilities and redacted
    typed receipts.  Production peer opening deliberately remains unavailable
    because the authority-store peer fence is not constructible yet.  The
    shared reservation-payload digest is supplied by
    {!Jj_completion_store_protocol}; this owner uses it to prove exact
    Reserve/Finalize equality rather than guessing or weakening the law. *)

type rca_origin = Specification | Implementation | Environment | Evidence | Control
type diagnostic

val diagnostic_code : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

type unavailable_prerequisite =
  | Nominal_peer_open_fence

type production_availability =
  | Implemented_unavailable of unavailable_prerequisite list

type row_state = Absent | Reserved | Finalized | Indeterminate | Conflict

type recovery_outcome =
  | Absent_terminal
  | Reserved_terminal
  | Finalized_terminal
  | Indeterminate_blocked
  | Conflict_blocked

type operational
type role_bundle
type lower_open_result

val open_first_or_successor :
  authority:Dependability_authority_store.operational ->
  location:Dependability_sqlite_location.reference ->
  observed_at:Dependability_clock.receipt ->
  (lower_open_result, diagnostic) result
(** Registered production locations refuse because the nominal peer-open
    fence is unavailable.  A test-only volatile location may open this
    non-production foundation. *)

val operational : lower_open_result -> operational
val role_bundle : lower_open_result -> role_bundle
val operational_posture : operational -> [ `Volatile_test_foundation ]
val production_availability : operational -> production_availability
val owner_session_digest : operational -> string
val store_epoch_digest : operational -> string

(** There is no generic or store-wide capability.  Each accessor consumes its
    exact role once. *)
type reserve_capability
type finalize_capability
type read_capability
type recovery_capability
type lifecycle_capability

val take_reserve : role_bundle -> (reserve_capability, diagnostic) result
val take_finalize : role_bundle -> (finalize_capability, diagnostic) result
val take_read : role_bundle -> (read_capability, diagnostic) result
val take_recovery : role_bundle -> (recovery_capability, diagnostic) result
val take_lifecycle : role_bundle -> (lifecycle_capability, diagnostic) result

type reserve_outcome = Reserved_inserted | Reserved_replayed
type reserve_receipt

val reserve_once :
  reserve_capability ->
  observed_at:Dependability_clock.receipt ->
  Jj_completion_store_protocol.prepared ->
  (reserve_receipt, diagnostic) result
(** Accepts only a protocol [Reserve].  Same completion and same canonical
    reserve request replay the first receipt; same completion and a different
    request durably enters [Conflict].  Reservation is nonauthorizing. *)

val reserve_outcome : reserve_receipt -> reserve_outcome
val reserve_receipt_digest : reserve_receipt -> string

type finalize_outcome = Finalized_inserted | Finalized_replayed
type finalize_receipt

val finalize_once :
  finalize_capability ->
  observed_at:Dependability_clock.receipt ->
  Jj_completion_store_protocol.prepared ->
  (finalize_receipt, diagnostic) result
(** Accepts only a protocol [Finalize].  It commits only when the exact
    reservation exists and the protocol's common reservation-payload digest
    matches; the finalization-only dependency digest is recorded separately. *)

val finalize_outcome : finalize_receipt -> finalize_outcome
val finalize_receipt_digest : finalize_receipt -> string

type readback

val read_current :
  read_capability ->
  observed_at:Dependability_clock.receipt ->
  Jj_completion_store_protocol.prepared ->
  (readback, diagnostic) result
(** Re-reads the exact row and validates its stored clock receipt.  It returns
    no capability and grants no semantic, completion, or parity credit. *)

val readback_state : readback -> row_state
val readback_digest : readback -> string
val readback_credit : readback -> [ `No_credit ]

val inventory_current :
  read_capability ->
  manifest:Dependability_owner_inventory.Identity.t ->
  recovery_attempt:Dependability_owner_inventory.Identity.t ->
  challenge:Dependability_owner_inventory.Identity.t ->
  transition:Dependability_owner_inventory.Identity.t ->
  ( Dependability_owner_inventory.completion_store
    Dependability_owner_inventory.fragment_prepared,
    diagnostic )
  result
(** Owner-derived exact row denominator.  The result is intentionally only a
    prepared fragment because this owner has no producer-seal constructor. *)

type recovery_unbound
type recovery_bound
type bound_manifest_current
type prepared_recovery_current
type recovery_result

val open_recovery_inventory :
  recovery_capability ->
  recovery_attempt:Dependability_owner_inventory.Identity.t ->
  challenge:Dependability_owner_inventory.Identity.t ->
  transition:Dependability_owner_inventory.Identity.t ->
  observed_at:Dependability_clock.receipt ->
  (recovery_unbound, diagnostic) result

val bind_recovery_manifest_once :
  recovery_unbound ->
  Dependability_owner_inventory.Identity.t ->
  (recovery_bound * bound_manifest_current, diagnostic) result
(** The first exact manifest bind wins.  Equal input replays; different input
    conflicts. *)

val bound_manifest_digest : bound_manifest_current -> string
val recovery_bound_digest : recovery_bound -> string

val prepare_recovery_current :
  recovery_bound ->
  observed_at:Dependability_clock.receipt ->
  (prepared_recovery_current, diagnostic) result
(** Re-reads the complete owner inventory.  The caller supplies no row state,
    payload, SQL, command, or third reconciliation action. *)

val reconcile_recovery_once :
  recovery_capability ->
  prepared_recovery_current ->
  (recovery_result, diagnostic) result

val recovery_outcome : recovery_result -> recovery_outcome
val recovery_result_digest : recovery_result -> string
val recovery_replayed : recovery_result -> bool

val prepare_recovered_fragment :
  recovery_result ->
  ( Dependability_owner_inventory.completion_store
    Dependability_owner_inventory.recovery_only_terminal_fragment_prepared,
    diagnostic )
  result
(** Defined only for [Absent_terminal], [Reserved_terminal], or
    [Finalized_terminal].  It creates no current value and cannot forge the
    Completion-store producer seal. *)

type drain_receipt
type close_receipt

val drain : lifecycle_capability -> (drain_receipt, diagnostic) result
val drain_receipt_digest : drain_receipt -> string
val drain_replayed : drain_receipt -> bool

val close :
  lifecycle_capability ->
  drain_receipt ->
  (close_receipt, diagnostic) result
val close_receipt_digest : close_receipt -> string
val close_replayed : close_receipt -> bool
(** An [Indeterminate] or [Conflict] row retains the store fence and refuses
    drain/close. *)

val source_digest : string

module For_test : sig
  type mutation =
    | Drop_role_separation
    | Permit_production_without_peer_fence
    | Drop_authority_session_binding
    | Overwrite_reservation
    | Drop_replay_check
    | Forge_common_payload_match
    | Skip_current_readback
    | Caller_supplied_reconcile
    | Forge_producer_seal
    | Close_blocked_row

  val source_digest_with_mutation : mutation -> string
end

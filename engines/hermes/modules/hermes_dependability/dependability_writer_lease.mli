(** Bounded, nonauthorizing writer-lease foundation.

    A prepared acquisition contract binds the exact repository, workspace,
    before-state identities, holder, operator-quiescence receipt, and bounded
    clock receipt.  Its pure currentness kernel may only reject or fence the
    contract; it never constructs a physical lease, writer epoch, approval,
    mutation capability, or current owner witness.

    Registered production remains typed unavailable until the filesystem
    owner provides an owner-held physical lock and the approval/authority
    owners provide current, session-fenced operational protocols. *)

type rca_origin = Specification | Implementation | Environment | Evidence | Control
type diagnostic

val diagnostic_code : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

type prerequisite =
  | Physical_owner_lock_backend
  | Approval_current_carrier
  | Authority_writer_fence_transition
  | Authority_role_session_fence
  | Nominal_writer_peer_open_fence

val prerequisite_status : prerequisite -> (unit, diagnostic) result
val production_posture : [ `Implemented_unavailable ]

type acquisition_contract

val prepare_acquisition :
  lease:Jj_id.Lease.t ->
  repository:Jj_id.Repository.t ->
  workspace:Jj_id.Workspace.t ->
  expected_operation:Jj_id.Operation.t ->
  expected_change:Jj_id.Change.t ->
  expected_commit:Jj_id.Commit.t ->
  holder:Jj_id.Approval.t ->
  operator_quiescence:Jj_id.Receipt.t ->
  observed_at:Dependability_clock.receipt ->
  (acquisition_contract, diagnostic) result
(** Preparation is declarative and nonauthorizing.  Expiry is the private
    monotonic lifetime carried by [observed_at]; no raw caller time is
    accepted. *)

val acquisition_digest : acquisition_contract -> string

type mutation_state = Not_started | Started

type fence_reason =
  | Head_changed
  | External_writer_detected
  | Lease_expired
  | Lease_expired_during_started_mutation

type contract_state

val initial_state : acquisition_contract -> contract_state

val observe :
  contract_state ->
  now:Dependability_clock.receipt ->
  observed_operation:Jj_id.Operation.t ->
  external_writer_detected:bool ->
  mutation_state:mutation_state ->
  (contract_state, diagnostic) result
(** Head drift, a sensed external writer, and expiry fence absorbingly.  This
    is validation of a nonauthorizing contract, not evidence that a physical
    lease was acquired. *)

val contract_is_current : contract_state -> bool
val permits_acquisition_request : contract_state -> bool
val permits_next_governed_action : contract_state -> bool
(** Always false in this bounded foundation: no physical held-lease witness
    can be constructed. *)

val started_mutation_may_complete : contract_state -> bool
val requires_full_readback : contract_state -> bool
val fence_reason : contract_state -> fence_reason option

type readback_requirement =
  | No_readback_required
  | Full_supervision_readback_required

val readback_requirement : contract_state -> readback_requirement

type registered_owner

val open_registered :
  authority:Dependability_authority_store.operational ->
  writer_fence:Dependability_authority_store.writer_fence_capability ->
  approval:Dependability_approval.approved_plan_current ->
  observed_at:Dependability_clock.receipt ->
  (registered_owner, diagnostic) result
(** Refuses before constructing an owner.  Passing opaque lower tokens cannot
    replace the missing physical lock, authority fence-transition protocol,
    role-session validation, or nominal peer-open fence. *)

val source_digest : string

module For_test : sig
  type mutation =
    | Invent_physical_lock
    | Drop_approval_current
    | Drop_authority_fence_transition
    | Accept_raw_time
    | Permit_after_fence
    | Kill_started_mutation_on_expiry
    | Skip_full_readback
    | Forge_current_owner

  val source_digest_with_mutation : mutation -> string
end

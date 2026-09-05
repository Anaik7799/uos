(** Bounded, nonauthorizing operator-broker foundation.

    The constructible surface prepares a fixed-capacity map keyed only by the
    canonical admitted-activity digest.  It never accepts or projects an owned
    database, event-store handle, target callback, filesystem scope, process
    backend, executable, or caller-created identity digest.

    Operational registration and leases remain fail-closed until the target,
    effect-interpreter, conditional-interpreter, and event-store owners expose
    their exact opaque current identity carriers. *)

type unavailable_code =
  | Invalid_capacity
  | Activity_invalid
  | Registration_capacity_exhausted
  | Registration_conflict
  | Missing_registration
  | Current_registration_unavailable

type current_prerequisite =
  | Target_registry_current
  | Effect_interpreter_current_identity
  | Conditional_interpreter_current
  | Event_store_current_identity

type unavailable = private {
  code : unavailable_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
  hazard_id : string;
  missing_prerequisites : current_prerequisite list;
}

type broker

val create : maximum_registrations:int -> (broker, unavailable) result
(** Accepts a fixed bound in [1, 256].  The bound cannot be changed later. *)

type prepared_family = Ordinary_activity

type prepared_slot_receipt = private {
  prepared_activity_digest : string;
  prepared_family : prepared_family;
  prepared_slot_schema_digest : string;
  prepared_slot_receipt_digest : string;
  prepared_slot_was_replayed : bool;
}

type slot_state =
  | Slot_unregistered
  | Slot_prepared
  | Slot_conflict

val prepare_slot :
  broker -> activity:Run_topology.admitted_activity ->
  (prepared_slot_receipt, unavailable) result
(** Validates the exact current admitted activity and atomically prepares its
    nonauthorizing slot.  Exact replay is stable.  A changed same-key row
    enters an absorbing conflict.  Current target/interpreter/store identities
    are deliberately absent from this receipt. *)

val slot_state :
  broker -> activity:Run_topology.admitted_activity -> slot_state
val prepared_registration_count : broker -> int

val current_prerequisites : current_prerequisite list
val current_registration_posture : [ `Implemented_unavailable ]

val register_current_unavailable :
  broker -> prepared_slot_receipt -> (unit, unavailable) result
(** Always returns the exact missing current-owner seams and changes no state. *)

type ordinary

type _ lease_family =
  | Ordinary_family : ordinary lease_family
  | B_family : Jj_campaign_action.b_campaign lease_family
  | Completion_family : Jj_campaign_action.completion_reconcile lease_family

type 'family lease
type packed_lease = Lease : 'family lease -> packed_lease

val family_id : 'family lease_family -> string
val lease_projection_ids : string list

val acquire_current_unavailable :
  broker -> activity:Run_topology.admitted_activity ->
  (packed_lease, unavailable) result

val effect_interpreter :
  'family lease -> Run_effect_authority.interpreter
(** The only effect projection in a future lease. *)

val conditional_interpreter :
  'family Run_conditional_authority.family -> 'family lease ->
  Run_conditional_authority.interpreter
(** The family witness prevents an ordinary or wrong-family lease from
    projecting a conditional interpreter. *)

module For_test : sig
  type slot_mutation = Slot_schema_identity

  val mutate_prepared_slot :
    broker -> activity:Run_topology.admitted_activity -> slot_mutation -> bool
  (** Corrupts only one nonauthorizing prepared-row digest.  It creates no
      current identity, interpreter, target, store, or lease. *)
end

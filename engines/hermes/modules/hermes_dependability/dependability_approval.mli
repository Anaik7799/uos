(** Bounded, fail-closed approval-owner foundation.

    This interface records the exact lower prerequisites of the independent
    approval owner without inventing a nonce store, campaign-open witness,
    public-key identity, ticket schema, signature surface, or executable
    capability.  No owner or current approval value can be constructed until
    the authority-store protocols named below exist. *)

type rca_origin = Specification | Implementation | Environment | Evidence | Control
type diagnostic

val diagnostic_code : diagnostic -> string
val diagnostic_coordinate : diagnostic -> string
val diagnostic_origin : diagnostic -> rca_origin

type prerequisite =
  | Authority_nonce_store_protocol
  | Authority_role_session_fence
  | Operator_public_key_identity
  | Canonical_campaign_ticket_schema
  | Campaign_open_current_carrier
  | Dispatch_decision_current_carrier
  | Dispatch_abandonment_current_carrier

val prerequisite_status : prerequisite -> (unit, diagnostic) result
(** The authority nonce store and role/session fence are available.  The
    remaining prerequisites fail closed with exact diagnostics. *)

val bind_authority_approval_identity :
  Jj_id.Approval.t ->
  (Dependability_authority_store.approval_identity, diagnostic) result
val bind_authority_occurrence :
  Jj_campaign_action.occurrence ->
  (Dependability_authority_store.approval_occurrence, diagnostic) result
(** Pure, nonauthorizing projections into the authority store's neutral
    digest-only nonce protocol. *)

val production_posture : [ `Implemented_unavailable ]

type owner

val open_owner :
  authority:Dependability_authority_store.operational ->
  nonce:Dependability_authority_store.approval_nonce_capability ->
  dormancy:Dependability_authority_store.approval_dormancy_capability ->
  abandonment:Dependability_authority_store.approval_abandonment_capability ->
  operator_key:Dependability_approval_crypto.public_key ->
  observed_at:Dependability_clock.receipt ->
  (owner, diagnostic) result
(** Refuses before constructing [owner].  The opaque authority role tokens
    are not consumed because the configured public key has no public identity
    projection and the complete signed-ticket schema is unavailable. *)

type signed_ticket
type approved_plan_current
type 'family approved_conditional_plan_current

val verify_signed_ticket :
  operator_key:Dependability_approval_crypto.public_key ->
  signature:Dependability_approval_crypto.signature ->
  now:Dependability_clock.receipt ->
  expected:Jj_approval.context ->
  presented:Jj_approval.context ->
  (signed_ticket, diagnostic) result
(** Validates the complete typed context, derives one canonical length-framed
    ticket internally, verifies its opaque Ed25519 signature, and retains only
    the key, context-witness, canonical-ticket and verification digests. *)

val signed_ticket_digest : signed_ticket -> string
val signed_ticket_public_key_identity : signed_ticket -> string
val signed_ticket_context_witness_digest : signed_ticket -> string

val verify_standalone_plan :
  owner ->
  plan:'phase Jj_campaign_action.standalone_phase_request ->
  signed_ticket ->
  (approved_plan_current, diagnostic) result

val verify_conditional_plan :
  owner ->
  plan:'family Jj_campaign_action.conditional_plan ->
  signed_ticket ->
  ('family approved_conditional_plan_current, diagnostic) result

type nonce_state = Available | Consumed | Dormant_closed | Abandoned_closed
type occurrence_nonce
type occurrence_capability
type dormant_closed_receipt
type 'purpose abandoned_closed_receipt

val occurrence_nonce :
  approved_plan_current ->
  occurrence:Jj_campaign_action.occurrence ->
  (occurrence_nonce, diagnostic) result

val nonce_state : owner -> occurrence_nonce -> (nonce_state, diagnostic) result

val close_dormant_once :
  Dependability_authority_store.approval_dormancy_capability ->
  Dependability_dispatch_store.decision_current ->
  occurrence_nonce ->
  (dormant_closed_receipt, diagnostic) result

val close_abandoned_once :
  Dependability_authority_store.approval_abandonment_capability ->
  'purpose Dependability_dispatch_store.abandonment_current ->
  occurrence_nonce ->
  ('purpose abandoned_closed_receipt, diagnostic) result

(** Normal nonce consumption is intentionally absent: no lower
    campaign-open-current carrier exists to type its required authority. *)

val source_digest : string

module For_test : sig
  type mutation =
    | Invent_nonce_store
    | Drop_role_session_fence
    | Accept_raw_signature
    | Accept_partial_ticket
    | Consume_without_campaign_open
    | Consume_unselected_nonce
    | Reopen_terminal_nonce
    | Forge_decision_current
    | Forge_abandonment_current

  val source_digest_with_mutation : mutation -> string
end

(** Pure, non-authorizing fractal ontology for controlled Jujutsu.

    This is structural authority only.  A node records obligations and an
    unavailable lifecycle; it is not an effect capability, runtime receipt, or
    parity claim. *)

type level = L0 | L1 | L2 | L3 | L4 | L5 | L6 | LX

type coordinate = private { level : level; node : string }

type owner =
  | Portfolio_owner
  | Repository_workspace_owner
  | Policy_coordinator_owner
  | Intent_operation_owner
  | Effect_attempt_owner
  | Readback_evidence_owner
  | Durable_receipt_owner
  | Telemetry_owner

type lifecycle = Declared_unavailable | Implemented_unavailable

type invariant =
  | Canonical_identity
  | Identity_separation
  | Monotone_policy
  | Approval_and_lease_required
  | Apply_once
  | Deterministic_replay
  | Bounded_output
  | Exact_readback
  | Recovery_anchor_retained
  | Source_only_closure
  | Redacted_observation
  | Surface_equivalence
  | Bridge_before_effect
  | Remote_publication_requires_cas

type input =
  | Portfolio_declaration
  | Repository_workspace_identity
  | Policy_and_coordination_state
  | Operation_intent
  | Prepared_effect_attempt
  | Bounded_readback
  | Durable_receipt_input
  | Receipt_observation

type output =
  | Portfolio_scope
  | Repository_workspace_scope
  | Admitted_policy_decision
  | Typed_operation_declaration
  | Effect_attempt_identity
  | Readback_evidence
  | Durable_receipt
  | Non_authorizing_telemetry

type hazard =
  | Authority_drift
  | Identity_aliasing
  | Approval_bypass
  | Lease_bypass
  | Duplicate_apply
  | Unbounded_output
  | Readback_mismatch
  | Recovery_anchor_loss
  | Secret_disclosure
  | Bridge_bypass
  | Unproved_remote_publication
  | False_credit

type kind =
  | Portfolio
  | Repository_workspace
  | Policy_coordinator
  | Intent_operation
  | Effect_attempt
  | Readback_evidence_node
  | Durable_receipt_node
  | Telemetry

type identity = private {
  schema_id : string;
  authority_digest : string;
}

type node = private {
  kind : kind;
  coordinate : coordinate;
  owner : owner;
  identity : identity;
  invariants : invariant list;
  inputs : input list;
  outputs : output list;
  hazards : hazard list;
  lifecycle : lifecycle;
}

val schema_id : string
val all : node list
val find : kind -> node

val level_key : level -> string
val kind_key : kind -> string
val owner_key : owner -> string
val lifecycle_key : lifecycle -> string
val invariant_key : invariant -> string
val input_key : input -> string
val output_key : output -> string
val hazard_key : hazard -> string

(** Digest of every ordered node field and the exact lower source authorities
    to which node identities are bound. *)
val source_digest : string

module For_test : sig
  type mutation = Drop_node | Change_identity | Drop_invariant | Claim_available
  val source_digest_with_mutation : mutation -> string
end

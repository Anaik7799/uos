(** Pure algebraic laws for the controlled Jujutsu authority.  This module
    validates and normalizes values; it owns no external effect. *)

type canonical_field = { name : string; value : string }
type canonical_refusal =
  | Empty_field_name
  | Invalid_field_name
  | Field_too_large
  | Too_many_fields
  | Duplicate_field

val canonicalize : canonical_field list -> (string, canonical_refusal) result

type identity
val identity :
  operation:Jj_operation.t ->
  request:Jj_id.Request.t ->
  repository:Jj_id.Repository.t ->
  workspace:Jj_id.Workspace.t ->
  (identity, canonical_refusal) result
val identity_digest : identity -> string
val identity_separated : identity -> identity -> bool

val policy_conjunction : Jj_policy.decision list -> Jj_policy.decision
val policy_monotone : Jj_policy.decision list -> bool

type approval_posture = Approval_valid | Approval_missing
type lease_posture = Lease_valid | Lease_stale
type guard_refusal = Policy_denied | Approval_absent | Lease_absent
type guard = Guarded | Refused of guard_refusal
val guard :
  policy:Jj_policy.decision -> approval:approval_posture ->
  lease:lease_posture -> guard

type apply_state = Unapplied | Applied of string
type apply_disposition = First_applied | Replayed
type apply_refusal = Invalid_effect_digest | Apply_conflict
val apply_once :
  apply_state -> effect_digest:string ->
  ((apply_state * apply_disposition), apply_refusal) result

val output_within_bound : Jj_operation.t -> output_bytes:int -> bool
val readback_matches :
  expected_operation:Jj_operation.t -> observed_operation:Jj_operation.t ->
  expected_state:string -> observed_state:string -> bool

type recovery_anchor = No_anchor | Before_state_anchor | Partition_anchor
val recovery_anchor_valid : Jj_operation.t -> anchor:recovery_anchor -> bool

val source_only :
  Mainline_carrier_policy.observation list ->
  (Mainline_carrier_policy.observation list,
   Mainline_carrier_policy.refusal) result
val redact : public_identity:string -> private_value:string -> string

type surface = Ocaml_api | Cli | Mcp | Zenoh
type normalized_receipt = {
  operation_key : string;
  disposition : string;
  state_digest : string;
}
val surface_receipt : surface -> normalized_receipt -> normalized_receipt

type bridge = Bridge_unavailable | Bridge_admitted
type effect_posture = Zero_effect | Effect_prepared
val effect_posture : bridge:bridge -> requested_effect:bool -> effect_posture

type cas = Cas_unproved | Cas_proved
type publication =
  | Not_remote_publication
  | Publication_unavailable
  | Publication_prepared
val remote_publication : operation:Jj_operation.t -> cas:cas -> publication

type law
type law_credit = Validation_only
val laws : law list
val law_id : law -> string
val law_statement : law -> string
val law_negative_control_id : law -> string
val law_credit : law -> law_credit

(** Digest of the complete ordered law registry and schema identities. *)
val source_digest : string


(** Validation-only approval witnesses over canonical campaign payloads.
    This module does not mint, sign, consume, renew, persist, or execute. *)

module Digest : sig
  type t
  val make : string -> (t, [ `Invalid_digest ]) result
  val to_string : t -> string
end

module Actor : Jj_id.ID
module Host : Jj_id.ID
module Branch : Jj_id.ID
module Capability : Jj_id.ID

module Journal_position : sig
  type t
  val make : int64 -> (t, [ `Invalid_journal_position ]) result
  val to_int64 : t -> int64
end

type context = {
  payload : Jj_campaign_action.approval_payload;
  plan : Digest.t;
  design : Digest.t;
  head : Jj_id.Operation.t;
  repository : Jj_id.Repository.t;
  workspace : Jj_id.Workspace.t;
  phase : string;
  branch : Branch.t;
  actor : Actor.t;
  host : Host.t;
  expires_at_epoch : int64;
  journal_position : Journal_position.t;
  occurrence_nonce : string;
  capability_references : Capability.t list;
}

type validation_error =
  | Expired
  | Payload_mismatch
  | Plan_mismatch
  | Design_mismatch
  | Head_mismatch
  | Repository_mismatch
  | Workspace_mismatch
  | Phase_mismatch
  | Branch_mismatch
  | Actor_mismatch
  | Host_mismatch
  | Expiry_mismatch
  | Journal_position_mismatch
  | Occurrence_nonce_mismatch
  | Empty_capability_references
  | Duplicate_capability_reference
  | Occurrence_nonce_alias
  | Capability_references_mismatch

type witness

val validate :
  now_epoch:int64 -> expected:context -> presented:context ->
  (witness, validation_error) result

(** A stable digest of every field validated by [validate]. It is evidence of
    validation only and grants no execution or parity authority. *)
val witness_digest : witness -> string
val source_digest : string

module For_test : sig
  type source_mutation = Change_digest_bound | Drop_validation_field
  val source_digest_with_mutation : source_mutation -> string
end

(** Exact auxiliary-role ownership and carrier declarations for later bridge use. *)

type owner =
  | Clock_owner | External_resource_owner | Release_owner
  | Repository_source_owner
  | Approval_owner | Writer_lease_owner | Network_scope_owner
  | Credential_lease_owner | Filesystem_materialization_owner
  | Candidate_verification_owner | Jujutsu_process_owner
  | Completion_receipt_owner | Formal_oracle_owner | Recovery_transition_owner

type carrier_class = Nonserializable_bridge_carrier

type t

val role : t -> Jj_action_kind.auxiliary_role
val owner : t -> owner
val carrier_class : t -> carrier_class
val all : t list
val for_role : Jj_action_kind.auxiliary_role -> t option
val is_well_formed : t -> bool
val source_digest : string

type owner =
  | Clock_owner | External_resource_owner | Release_owner
  | Repository_source_owner
  | Approval_owner | Writer_lease_owner | Network_scope_owner
  | Credential_lease_owner | Filesystem_materialization_owner
  | Candidate_verification_owner | Jujutsu_process_owner
  | Completion_receipt_owner | Formal_oracle_owner | Recovery_transition_owner

open Jj_action_kind

type carrier_class = Nonserializable_bridge_carrier

type t = {
  role : Jj_action_kind.auxiliary_role;
  owner : owner;
  carrier_class : carrier_class;
}

let owner_for = function
  | Jj_action_kind.Acquire_clock -> Clock_owner
  | Observe_external_resource -> External_resource_owner
  | Observe_release_bundle -> Release_owner
  | Observe_repository_source | Observe_tree | Observe_object -> Repository_source_owner
  | Consume_approval_nonce -> Approval_owner
  | Acquire_writer_lease | Renew_writer_lease | Release_writer_lease -> Writer_lease_owner
  | Acquire_network_scope | Release_network_scope -> Network_scope_owner
  | Acquire_credential_lease | Release_credential_lease -> Credential_lease_owner
  | Materialize_candidate | Write_partition | Restore_partition
  | Restore_sealed_record_preimage | Write_sealed_record_candidate
  | Remove_disposable_scope -> Filesystem_materialization_owner
  | Stage_recovery_set | Reconcile_recovery_set | Cleanup_recovery_set -> Recovery_transition_owner
  | Verify_candidate_tree -> Candidate_verification_owner
  | Execute_jj_process | Readback_jj_state -> Jujutsu_process_owner
  | Reserve_completion_receipt | Finalize_completion_receipt -> Completion_receipt_owner
  | Execute_formal_oracle -> Formal_oracle_owner

let make role = { role; owner = owner_for role; carrier_class = Nonserializable_bridge_carrier }
let all = List.map make Jj_action_kind.auxiliary_roles
let role row = row.role
let owner row = row.owner
let carrier_class row = row.carrier_class
let for_role role = List.find_opt (fun row -> row.role = role) all

let is_well_formed row =
  row.owner = owner_for row.role
  && row.carrier_class = Nonserializable_bridge_carrier

let owner_key = function
  | Clock_owner -> "clock-owner"
  | External_resource_owner -> "external-resource-owner"
  | Release_owner -> "release-owner"
  | Repository_source_owner -> "repository-source-owner"
  | Approval_owner -> "approval-owner"
  | Writer_lease_owner -> "writer-lease-owner"
  | Network_scope_owner -> "network-scope-owner"
  | Credential_lease_owner -> "credential-lease-owner"
  | Filesystem_materialization_owner -> "filesystem-materialization-owner"
  | Candidate_verification_owner -> "candidate-verification-owner"
  | Jujutsu_process_owner -> "jujutsu-process-owner"
  | Completion_receipt_owner -> "completion-receipt-owner"
  | Formal_oracle_owner -> "formal-oracle-owner"
  | Recovery_transition_owner -> "recovery-transition-owner"

let source_digest =
  all
  |> List.map (fun row ->
      Jj_id.length_frame [ Jj_action_kind.auxiliary_role_key row.role;
        owner_key row.owner; "nonserializable-bridge-carrier" ])
  |> String.concat "\n" |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

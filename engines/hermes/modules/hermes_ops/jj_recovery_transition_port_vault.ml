type vault = |
type resolver = |
type retained_port = |
type current_reference = |

type lifecycle_state =
  | Prepared
  | Applied
  | Diverged
  | Closed_unused
  | Session_fenced
  | Indeterminate

let lifecycle_states =
  [ Prepared; Applied; Diverged; Closed_unused; Session_fenced; Indeterminate ]

let lifecycle_state_id = function
  | Prepared -> "prepared"
  | Applied -> "applied"
  | Diverged -> "diverged"
  | Closed_unused -> "closed-unused"
  | Session_fenced -> "session-fenced"
  | Indeterminate -> "indeterminate"

type unavailable_prerequisite =
  | Root_recovery_port_issuer_current
  | Root_recovery_port_lifecycle_current
  | Activation_recovery_port_preparation_current
  | Authority_store_recovery_port_prepared_row_current
  | Authority_store_recovery_port_reference_sealing_current
  | Authority_store_recovery_port_atomic_withdrawal_current
  | Authority_store_recovery_port_lifecycle_current
  | Owner_session_current_carrier
  | Activation_generation_current_carrier
  | Activity_identity_current_carrier
  | Source_transition_commitment_current_carrier
  | B_selected_decision_current_carrier
  | Selected_prefix_current_carrier
  | Bounded_expiry_current_carrier
  | Dependency_carrier_owner_current
  | Transition_target_resolver_registration_current
  | Event_effect_readback_current
  | Recovery_port_readback_current_carrier
  | Terminal_or_close_unused_evidence_current
  | Session_fence_current_carrier
  | Drain_barrier_current_carrier

type diagnostic = {
  prerequisite : unavailable_prerequisite;
  message : string;
  coordinate : string;
  origin : [ `Evidence ];
}

let diagnostic_prerequisite diagnostic = diagnostic.prerequisite
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.origin

let runtime_declaration = Jj_runtime_manifest.runtime_recovery_port_vault
let target_slot = Jj_runtime_manifest.Target_transition
let consumer = Jj_action_kind.Activate_source_recovery_branch

let binding_ids =
  [ "target-slot";
    "owner-session";
    "activation-generation";
    "activity";
    "source-transition-commitment";
    "consumer";
    "expiry" ]

let callsite_ids =
  [ "issuer:run-jj-operator-runtime";
    "retained-holder:jj-recovery-transition-port-vault";
    "resolver:ops-jj-transition-target";
    "carrier:run-dependency-authority-reference-only" ]

let prerequisites =
  [ Root_recovery_port_issuer_current;
    Root_recovery_port_lifecycle_current;
    Activation_recovery_port_preparation_current;
    Authority_store_recovery_port_prepared_row_current;
    Authority_store_recovery_port_reference_sealing_current;
    Authority_store_recovery_port_atomic_withdrawal_current;
    Authority_store_recovery_port_lifecycle_current;
    Owner_session_current_carrier;
    Activation_generation_current_carrier;
    Activity_identity_current_carrier;
    Source_transition_commitment_current_carrier;
    B_selected_decision_current_carrier;
    Selected_prefix_current_carrier;
    Bounded_expiry_current_carrier;
    Dependency_carrier_owner_current;
    Transition_target_resolver_registration_current;
    Event_effect_readback_current;
    Recovery_port_readback_current_carrier;
    Terminal_or_close_unused_evidence_current;
    Session_fence_current_carrier;
    Drain_barrier_current_carrier ]

let prerequisite_id = function
  | Root_recovery_port_issuer_current ->
      "root-recovery-port-issuer-current"
  | Root_recovery_port_lifecycle_current ->
      "root-recovery-port-lifecycle-current"
  | Activation_recovery_port_preparation_current ->
      "activation-recovery-port-preparation-current"
  | Authority_store_recovery_port_prepared_row_current ->
      "authority-store-recovery-port-prepared-row-current"
  | Authority_store_recovery_port_reference_sealing_current ->
      "authority-store-recovery-port-reference-sealing-current"
  | Authority_store_recovery_port_atomic_withdrawal_current ->
      "authority-store-recovery-port-atomic-withdrawal-current"
  | Authority_store_recovery_port_lifecycle_current ->
      "authority-store-recovery-port-lifecycle-current"
  | Owner_session_current_carrier -> "owner-session-current-carrier"
  | Activation_generation_current_carrier ->
      "activation-generation-current-carrier"
  | Activity_identity_current_carrier -> "activity-identity-current-carrier"
  | Source_transition_commitment_current_carrier ->
      "source-transition-commitment-current-carrier"
  | B_selected_decision_current_carrier ->
      "b-selected-decision-current-carrier"
  | Selected_prefix_current_carrier -> "selected-prefix-current-carrier"
  | Bounded_expiry_current_carrier -> "bounded-expiry-current-carrier"
  | Dependency_carrier_owner_current -> "dependency-carrier-owner-current"
  | Transition_target_resolver_registration_current ->
      "transition-target-resolver-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"
  | Recovery_port_readback_current_carrier ->
      "recovery-port-readback-current-carrier"
  | Terminal_or_close_unused_evidence_current ->
      "terminal-or-close-unused-evidence-current"
  | Session_fence_current_carrier -> "session-fence-current-carrier"
  | Drain_barrier_current_carrier -> "drain-barrier-current-carrier"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/jj-recovery-transition-port-vault";
    origin = `Evidence }

let production_posture = `Implemented_unavailable
let create_vault_unavailable () = Error (List.map diagnostic prerequisites)

let runtime_declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let state_ids = List.map lifecycle_state_id lifecycle_states
let prerequisite_ids = List.map prerequisite_id prerequisites

let source_fields ~declaration ~target ~consumer_id ~states ~bindings
    ~callsites ~missing =
  [ ("schema", "jj-recovery-transition-port-vault-foundation-v1");
    ("port-protocol-source", Jj_recovery_transition_port_protocol.source_digest);
    ("runtime-current-protocol-source", Jj_runtime_current_protocol.source_digest);
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("authority-store-source", Dependability_authority_store.source_digest);
    ("recovery-set-vault-source", Dependability_recovery_vault.source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest);
    ("dependency-authority-source", Run_dependency_authority.source_digest);
    ("conditional-authority-source", Run_conditional_authority.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("runtime-registry-source", Run_jj_runtime_registry.source_digest);
    ("runtime-declaration", declaration);
    ("target-slot", target);
    ("consumer", consumer_id);
    ("lifecycle-state-order", String.concat "," states);
    ("binding-field-order", String.concat "," bindings);
    ("callsite-order", String.concat "," callsites);
    ("missing-prerequisites", String.concat "," missing);
    ("create-without-issuer-current", "refused");
    ("create-without-lifecycle-current", "refused");
    ("prepare-without-activation-preparation", "refused");
    ("prepare-activity-binding", "exact-current-required");
    ("prepare-commitment-binding", "exact-current-required");
    ("prepare-session-binding", "exact-current-required");
    ("prepare-generation-binding", "exact-current-required");
    ("prepare-target-binding", "target-transition-only");
    ("prepare-consumer-binding", "activate-source-recovery-branch-only");
    ("prepare-expiry", "bounded-current-required");
    ("changed-prepare-replay", "absorbing-conflict");
    ("retained-port-projection", "absent");
    ("retained-port-serialization", "forbidden");
    ("reference-authority", "nonauthorizing");
    ("reference-serialization", "forbidden");
    ("reference-field-projection", "absent");
    ("dashboard-resolver", "absent");
    ("resolve-selected-decision", "b-selected-current-required");
    ("resolve-prefix", "exact-selected-prefix-required");
    ("resolve-binding", "exact-all-fields-required");
    ("duplicate-resolution", "stable-replay-or-conflict");
    ("late-apply-after-unused", "refused");
    ("late-apply-after-fence", "refused");
    ("close-unused-evidence", "owner-produced-current-required");
    ("fence-session-evidence", "process-death-current-required");
    ("lost-reply", "never-guessed");
    ("reconcile-readback", "durable-current-required");
    ("lifecycle-regression", "forbidden");
    ("terminal-barrier", "exactly-one-terminal-row-required");
    ("drain-live-prepared", "forbidden");
    ("owner-session-use", "exact-binding-required");
    ("store-epoch-use", "exact-binding-required");
    ("issuer-capability-projection", "absent");
    ("lifecycle-capability-projection", "absent");
    ("broad-activation-owner-projection", "absent");
    ("database-projection", "absent");
    ("location-projection", "absent");
    ("sql-projection", "absent");
    ("store-projection", "absent");
    ("payload-projection", "absent");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("vault-constructor", "absent");
    ("resolver-constructor", "absent");
    ("current-constructor", "absent");
    ("vault-promotion", "implemented-unavailable");
    ("recovery-set-vault-alias", "forbidden-distinct-authorities");
    ("repository-mutation", "absent");
    ("filesystem-effect", "absent");
    ("reference-completion-credit", "forbidden");
    ("reference-parity-credit", "forbidden");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let canonical_fields () =
  source_fields ~declaration:(runtime_declaration_id runtime_declaration)
    ~target:(Jj_runtime_manifest.slot_key target_slot)
    ~consumer_id:(Jj_action_kind.frontier_action_key consumer)
    ~states:state_ids ~bindings:binding_ids ~callsites:callsite_ids
    ~missing:prerequisite_ids

let source_digest = canonical_fields () |> digest

module For_test = struct
  type source_mutation =
    | Drop_port_protocol_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_manifest_source
    | Drop_action_kind_source
    | Drop_authority_store_source
    | Drop_recovery_set_vault_source
    | Drop_root_bootstrap_source
    | Drop_dependency_authority_source
    | Drop_conditional_authority_source
    | Drop_topology_source
    | Drop_event_prefix_source
    | Drop_runtime_registry_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_slot
    | Substitute_target_slot
    | Drop_consumer
    | Substitute_consumer
    | Drop_lifecycle_state
    | Reorder_lifecycle_states
    | Duplicate_lifecycle_state
    | Merge_applied_diverged
    | Merge_closed_fenced
    | Drop_binding_field
    | Reorder_binding_fields
    | Duplicate_binding_field
    | Drop_callsite
    | Reorder_callsites
    | Substitute_callsite
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_create_without_issuer_current
    | Permit_create_without_lifecycle_current
    | Permit_prepare_without_activation_preparation
    | Permit_prepare_cross_activity
    | Permit_prepare_cross_commitment
    | Permit_prepare_cross_session
    | Permit_prepare_cross_generation
    | Permit_prepare_wrong_target
    | Permit_prepare_wrong_consumer
    | Permit_prepare_after_expiry
    | Permit_changed_prepare_replay
    | Expose_retained_port
    | Serialize_retained_port
    | Authorize_reference
    | Serialize_reference
    | Expose_reference_fields
    | Permit_dashboard_resolver
    | Permit_resolve_without_selected_decision
    | Permit_resolve_without_prefix
    | Permit_resolve_cross_binding
    | Permit_duplicate_resolution
    | Permit_late_apply_after_unused
    | Permit_late_apply_after_fence
    | Permit_close_unused_without_evidence
    | Permit_fence_without_session_death
    | Guess_lost_reply
    | Permit_reconcile_without_readback
    | Permit_state_regression
    | Permit_terminal_without_barrier
    | Permit_drain_with_live_prepared
    | Permit_cross_owner_session
    | Permit_cross_store_epoch
    | Expose_issuer_capability
    | Expose_lifecycle_capability
    | Expose_broad_activation_owner
    | Expose_database
    | Expose_location
    | Expose_sql
    | Expose_store
    | Expose_payload
    | Add_callback
    | Accept_caller_digest
    | Add_vault_constructor
    | Add_resolver_constructor
    | Add_current_constructor
    | Promote_unavailable_vault
    | Alias_recovery_set_vault
    | Add_repository_mutation
    | Add_filesystem_effect
    | Promote_reference_to_completion_credit
    | Promote_reference_to_parity_credit

  let drop_field name fields =
    List.filter
      (fun (candidate, _) -> not (String.equal candidate name))
      fields

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let source_digest_with_mutation mutation =
    let fields = canonical_fields () in
    let replace name value = replace_field name value fields in
    let mutated_fields =
      match mutation with
      | Drop_port_protocol_source ->
          drop_field "port-protocol-source" fields
      | Drop_runtime_current_protocol_source ->
          drop_field "runtime-current-protocol-source" fields
      | Drop_runtime_manifest_source ->
          drop_field "runtime-manifest-source" fields
      | Drop_action_kind_source -> drop_field "action-kind-source" fields
      | Drop_authority_store_source ->
          drop_field "authority-store-source" fields
      | Drop_recovery_set_vault_source ->
          drop_field "recovery-set-vault-source" fields
      | Drop_root_bootstrap_source ->
          drop_field "root-bootstrap-source" fields
      | Drop_dependency_authority_source ->
          drop_field "dependency-authority-source" fields
      | Drop_conditional_authority_source ->
          drop_field "conditional-authority-source" fields
      | Drop_topology_source -> drop_field "topology-source" fields
      | Drop_event_prefix_source -> drop_field "event-prefix-source" fields
      | Drop_runtime_registry_source ->
          drop_field "runtime-registry-source" fields
      | Drop_runtime_declaration -> drop_field "runtime-declaration" fields
      | Substitute_runtime_declaration ->
          replace "runtime-declaration" "substituted-runtime-slot"
      | Drop_target_slot -> drop_field "target-slot" fields
      | Substitute_target_slot ->
          replace "target-slot" "target-mutation-frontier"
      | Drop_consumer -> drop_field "consumer" fields
      | Substitute_consumer ->
          replace "consumer" "set-activity-frontier:reconciled-terminal"
      | Drop_lifecycle_state ->
          replace "lifecycle-state-order"
            (String.concat "," (List.tl state_ids))
      | Reorder_lifecycle_states ->
          replace "lifecycle-state-order"
            (String.concat "," (List.rev state_ids))
      | Duplicate_lifecycle_state ->
          replace "lifecycle-state-order"
            (String.concat "," (lifecycle_state_id Prepared :: state_ids))
      | Merge_applied_diverged ->
          replace "lifecycle-state-order"
            "prepared,applied-or-diverged,closed-unused,session-fenced,indeterminate"
      | Merge_closed_fenced ->
          replace "lifecycle-state-order"
            "prepared,applied,diverged,closed-or-fenced,indeterminate"
      | Drop_binding_field ->
          replace "binding-field-order"
            (String.concat "," (List.tl binding_ids))
      | Reorder_binding_fields ->
          replace "binding-field-order"
            (String.concat "," (List.rev binding_ids))
      | Duplicate_binding_field ->
          replace "binding-field-order"
            (String.concat "," ("target-slot" :: binding_ids))
      | Drop_callsite ->
          replace "callsite-order" (String.concat "," (List.tl callsite_ids))
      | Reorder_callsites ->
          replace "callsite-order" (String.concat "," (List.rev callsite_ids))
      | Substitute_callsite ->
          replace "callsite-order"
            (String.concat ","
               ("issuer:ops-jj-transition-target" :: List.tl callsite_ids))
      | Drop_prerequisite ->
          replace "missing-prerequisites"
            (String.concat "," (List.tl prerequisite_ids))
      | Reorder_prerequisites ->
          replace "missing-prerequisites"
            (String.concat "," (List.rev prerequisite_ids))
      | Duplicate_prerequisite ->
          replace "missing-prerequisites"
            (String.concat ","
               ("root-recovery-port-issuer-current" :: prerequisite_ids))
      | Substitute_prerequisite ->
          replace "missing-prerequisites"
            (String.concat ","
               ("root-recovery-port-issuer-substituted"
                :: List.tl prerequisite_ids))
      | Permit_create_without_issuer_current ->
          replace "create-without-issuer-current" "permitted"
      | Permit_create_without_lifecycle_current ->
          replace "create-without-lifecycle-current" "permitted"
      | Permit_prepare_without_activation_preparation ->
          replace "prepare-without-activation-preparation" "permitted"
      | Permit_prepare_cross_activity ->
          replace "prepare-activity-binding" "cross-activity-permitted"
      | Permit_prepare_cross_commitment ->
          replace "prepare-commitment-binding" "cross-commitment-permitted"
      | Permit_prepare_cross_session ->
          replace "prepare-session-binding" "cross-session-permitted"
      | Permit_prepare_cross_generation ->
          replace "prepare-generation-binding" "cross-generation-permitted"
      | Permit_prepare_wrong_target ->
          replace "prepare-target-binding" "any-target-permitted"
      | Permit_prepare_wrong_consumer ->
          replace "prepare-consumer-binding" "any-consumer-permitted"
      | Permit_prepare_after_expiry ->
          replace "prepare-expiry" "expired-permitted"
      | Permit_changed_prepare_replay ->
          replace "changed-prepare-replay" "changed-stable-replay"
      | Expose_retained_port ->
          replace "retained-port-projection" "exposed"
      | Serialize_retained_port ->
          replace "retained-port-serialization" "permitted"
      | Authorize_reference -> replace "reference-authority" "authorizing"
      | Serialize_reference ->
          replace "reference-serialization" "permitted"
      | Expose_reference_fields ->
          replace "reference-field-projection" "exposed"
      | Permit_dashboard_resolver ->
          replace "dashboard-resolver" "permitted"
      | Permit_resolve_without_selected_decision ->
          replace "resolve-selected-decision" "optional"
      | Permit_resolve_without_prefix -> replace "resolve-prefix" "optional"
      | Permit_resolve_cross_binding ->
          replace "resolve-binding" "cross-binding-permitted"
      | Permit_duplicate_resolution ->
          replace "duplicate-resolution" "repeat-application-permitted"
      | Permit_late_apply_after_unused ->
          replace "late-apply-after-unused" "permitted"
      | Permit_late_apply_after_fence ->
          replace "late-apply-after-fence" "permitted"
      | Permit_close_unused_without_evidence ->
          replace "close-unused-evidence" "optional"
      | Permit_fence_without_session_death ->
          replace "fence-session-evidence" "optional"
      | Guess_lost_reply -> replace "lost-reply" "guessed"
      | Permit_reconcile_without_readback ->
          replace "reconcile-readback" "optional"
      | Permit_state_regression ->
          replace "lifecycle-regression" "permitted"
      | Permit_terminal_without_barrier ->
          replace "terminal-barrier" "optional"
      | Permit_drain_with_live_prepared ->
          replace "drain-live-prepared" "permitted"
      | Permit_cross_owner_session ->
          replace "owner-session-use" "cross-session-permitted"
      | Permit_cross_store_epoch ->
          replace "store-epoch-use" "cross-epoch-permitted"
      | Expose_issuer_capability ->
          replace "issuer-capability-projection" "exposed"
      | Expose_lifecycle_capability ->
          replace "lifecycle-capability-projection" "exposed"
      | Expose_broad_activation_owner ->
          replace "broad-activation-owner-projection" "exposed"
      | Expose_database -> replace "database-projection" "exposed"
      | Expose_location -> replace "location-projection" "exposed"
      | Expose_sql -> replace "sql-projection" "exposed"
      | Expose_store -> replace "store-projection" "exposed"
      | Expose_payload -> replace "payload-projection" "exposed"
      | Add_callback -> replace "callback" "present"
      | Accept_caller_digest -> replace "caller-digest" "accepted"
      | Add_vault_constructor -> replace "vault-constructor" "present"
      | Add_resolver_constructor -> replace "resolver-constructor" "present"
      | Add_current_constructor -> replace "current-constructor" "present"
      | Promote_unavailable_vault -> replace "vault-promotion" "available"
      | Alias_recovery_set_vault ->
          replace "recovery-set-vault-alias" "aliased"
      | Add_repository_mutation -> replace "repository-mutation" "present"
      | Add_filesystem_effect -> replace "filesystem-effect" "present"
      | Promote_reference_to_completion_credit ->
          replace "reference-completion-credit" "permitted"
      | Promote_reference_to_parity_credit ->
          replace "reference-parity-credit" "permitted"
    in
    digest mutated_fields
end

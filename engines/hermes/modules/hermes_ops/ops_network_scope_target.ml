type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Network_scope_operational_owner_current
  | Controlled_network_backend_current
  | Named_remote_identity_current_carrier
  | Remote_operation_intent_current_carrier
  | Credential_lease_current_carrier
  | Bounded_clock_current_carrier
  | Approval_occurrence_capability_current
  | Network_scope_release_eligibility_current
  | Dependency_carrier_owner_current
  | Effect_target_registration_current
  | Event_effect_readback_current

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

let runtime_declaration = Jj_runtime_manifest.target_network_scope
let target_protocol = Jj_target_protocol.Network_scope
let accepted_roles =
  [ Jj_action_kind.Acquire_network_scope;
    Jj_action_kind.Release_network_scope ]
let accepted_effects = [ Run_topology.Network_scope_transition ]

let binding_ids =
  [ "auxiliary:acquire-network-scope->network-scope-transition";
    "auxiliary:release-network-scope->network-scope-transition" ]

let operation_policy_binding_ids =
  [ "git-fetch->remote-synchronization->jujutsu-remote-synchronization:local-mutation-approval+writer-lease+recovery-required:implemented-unavailable:remote-activity-scope-actions-omitted";
    "git-push->remote-publication->jujutsu-remote-publish:expected-remote-tip-cas-required:implemented-unavailable:remote-cas-proof-missing" ]

let prerequisites =
  [ Target_owner_part_current;
    Network_scope_operational_owner_current;
    Controlled_network_backend_current;
    Named_remote_identity_current_carrier;
    Remote_operation_intent_current_carrier;
    Credential_lease_current_carrier;
    Bounded_clock_current_carrier;
    Approval_occurrence_capability_current;
    Network_scope_release_eligibility_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Network_scope_operational_owner_current ->
      "network-scope-operational-owner-current"
  | Controlled_network_backend_current ->
      "controlled-network-backend-current"
  | Named_remote_identity_current_carrier ->
      "named-remote-identity-current-carrier"
  | Remote_operation_intent_current_carrier ->
      "remote-operation-intent-current-carrier"
  | Credential_lease_current_carrier ->
      "credential-lease-current-carrier"
  | Bounded_clock_current_carrier -> "bounded-clock-current-carrier"
  | Approval_occurrence_capability_current ->
      "approval-occurrence-capability-current"
  | Network_scope_release_eligibility_current ->
      "network-scope-release-eligibility-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-network-scope-target";
    origin = `Evidence }

let production_posture = `Implemented_unavailable
let create_owner_unavailable () = Error (List.map diagnostic prerequisites)

let role_ids = List.map Jj_action_kind.auxiliary_role_key accepted_roles
let effect_ids = List.map Run_topology.effect_kind_id accepted_effects
let prerequisite_ids = List.map prerequisite_id prerequisites

let runtime_declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let source_fields ~declaration ~target ~roles ~effects ~bindings
    ~operation_policies ~missing =
  [ ("schema", "ops-network-scope-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("operation-source", Jj_operation.source_digest);
    ("dependency-schema-source", Jj_dependency_schema.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("network-owner-source", Dependability_network.source_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-effect-order", String.concat "," effects);
    ("action-effect-binding-order", String.concat "," bindings);
    ("operation-policy-binding-order", String.concat "," operation_policies);
    ("missing-prerequisites", String.concat "," missing);
    ("acquire-backend-gate", "controlled-current-required");
    ("acquire-remote-gate", "named-current-required");
    ("acquire-operation-intent-gate",
     "remote-operation-current-required");
    ("acquire-credential-gate", "credential-lease-current-required");
    ("acquire-clock-gate", "bounded-clock-current-required");
    ("acquire-approval-gate",
     "occurrence-capability-current-required");
    ("release-eligibility-gate",
     "network-scope-release-eligible-current-required");
    ("active-operation-release", "forbidden");
    ("expired-scope", "absorbing");
    ("revoked-scope", "absorbing");
    ("cleaned-scope", "absorbing");
    ("changed-replay", "absorbing-conflict");
    ("raw-remote", "rejected");
    ("raw-endpoint", "absent");
    ("raw-socket", "absent");
    ("raw-request-bytes", "absent");
    ("credential-projection", "absent");
    ("capability-projection", "absent:owner-resolved");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("network-backend", "implemented-unavailable");
    ("remote-activity-projection",
     "unavailable:network-and-credential-scope-actions-omitted");
    ("production-posture", "implemented-unavailable") ]

let digest fields =
  fields
  |> List.map (fun (name, value) -> Jj_id.length_frame [ name; value ])
  |> Jj_id.length_frame
  |> Digestif.SHA256.digest_string
  |> Digestif.SHA256.to_hex

let source_digest =
  source_fields ~declaration:(runtime_declaration_id runtime_declaration)
    ~target:(Jj_target_protocol.key target_protocol) ~roles:role_ids
    ~effects:effect_ids ~bindings:binding_ids
    ~operation_policies:operation_policy_binding_ids
    ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_operation_source
    | Drop_dependency_schema_source
    | Drop_topology_source
    | Drop_network_owner_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_acquire_role
    | Drop_release_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_acquire_binding
    | Drop_release_binding
    | Reorder_bindings
    | Duplicate_binding
    | Bind_release_to_credential_effect
    | Drop_git_fetch_policy
    | Drop_git_push_policy
    | Reorder_operation_policies
    | Bind_fetch_to_remote_publish
    | Drop_fetch_local_mutation_authority
    | Permit_push_without_remote_cas
    | Claim_remote_activity_projection_complete
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_acquire_without_backend
    | Permit_acquire_without_named_remote
    | Permit_acquire_without_operation_intent
    | Permit_acquire_without_credential
    | Permit_acquire_without_clock
    | Permit_acquire_without_approval
    | Permit_release_without_eligibility
    | Permit_release_during_active_operation
    | Permit_after_expiry
    | Permit_after_revocation
    | Permit_after_cleanup
    | Permit_changed_replay
    | Accept_raw_remote
    | Add_raw_endpoint
    | Add_raw_socket
    | Add_raw_request_bytes
    | Expose_credential
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_backend

  let drop_field name fields =
    List.filter
      (fun (candidate, _) -> not (String.equal candidate name))
      fields

  let replace_field name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let without value values =
    List.filter (fun candidate -> not (String.equal candidate value)) values

  let replace_value before after values =
    List.map
      (fun value -> if String.equal value before then after else value)
      values

  let base_declaration = runtime_declaration_id runtime_declaration
  let base_target = Jj_target_protocol.key target_protocol

  let compose ?(declaration = base_declaration) ?(target = base_target)
      ?(roles = role_ids) ?(effects = effect_ids)
      ?(bindings = binding_ids)
      ?(operation_policies = operation_policy_binding_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~effects ~bindings
      ~operation_policies ~missing
    |> mutate |> digest

  let fetch_policy = List.hd operation_policy_binding_ids
  let push_policy = List.hd (List.tl operation_policy_binding_ids)

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_operation_source ->
        compose ~mutate:(drop_field "operation-source") ()
    | Drop_dependency_schema_source ->
        compose ~mutate:(drop_field "dependency-schema-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_network_owner_source ->
        compose ~mutate:(drop_field "network-owner-source") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id
               Jj_runtime_manifest.target_credential_lease)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Drop_acquire_role ->
        compose ~roles:(without "acquire-network-scope" role_ids) ()
    | Drop_release_role ->
        compose ~roles:(without "release-network-scope" role_ids) ()
    | Reorder_roles -> compose ~roles:(List.rev role_ids) ()
    | Add_role ->
        compose ~roles:(role_ids @ [ "acquire-credential-lease" ]) ()
    | Drop_effect -> compose ~effects:[] ()
    | Add_effect ->
        compose ~effects:(effect_ids @ [ "credential-lease-transition" ]) ()
    | Drop_acquire_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:acquire-network-scope->network-scope-transition"
               binding_ids)
          ()
    | Drop_release_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:release-network-scope->network-scope-transition"
               binding_ids)
          ()
    | Reorder_bindings -> compose ~bindings:(List.rev binding_ids) ()
    | Duplicate_binding ->
        compose ~bindings:(List.hd binding_ids :: binding_ids) ()
    | Bind_release_to_credential_effect ->
        compose
          ~bindings:
            (replace_value
               "auxiliary:release-network-scope->network-scope-transition"
               "auxiliary:release-network-scope->credential-lease-transition"
               binding_ids)
          ()
    | Drop_git_fetch_policy ->
        compose
          ~operation_policies:(without fetch_policy operation_policy_binding_ids)
          ()
    | Drop_git_push_policy ->
        compose
          ~operation_policies:(without push_policy operation_policy_binding_ids)
          ()
    | Reorder_operation_policies ->
        compose ~operation_policies:(List.rev operation_policy_binding_ids) ()
    | Bind_fetch_to_remote_publish ->
        compose
          ~operation_policies:
            (replace_value fetch_policy
               "git-fetch->remote-publication->jujutsu-remote-publish:local-mutation-approval+writer-lease+recovery-required:implemented-unavailable:remote-activity-scope-actions-omitted"
               operation_policy_binding_ids)
          ()
    | Drop_fetch_local_mutation_authority ->
        compose
          ~operation_policies:
            (replace_value fetch_policy
               "git-fetch->remote-synchronization->jujutsu-remote-synchronization:recovery-required:implemented-unavailable:remote-activity-scope-actions-omitted"
               operation_policy_binding_ids)
          ()
    | Permit_push_without_remote_cas ->
        compose
          ~operation_policies:
            (replace_value push_policy
               "git-push->remote-publication->jujutsu-remote-publish:stable-request-identity-required:implemented-unavailable:remote-cas-proof-missing"
               operation_policy_binding_ids)
          ()
    | Claim_remote_activity_projection_complete ->
        compose
          ~mutate:
            (replace_field "remote-activity-projection" "complete")
          ()
    | Drop_prerequisite ->
        compose
          ~missing:(match prerequisite_ids with [] -> [] | _ :: rest -> rest)
          ()
    | Reorder_prerequisites -> compose ~missing:(List.rev prerequisite_ids) ()
    | Duplicate_prerequisite ->
        compose ~missing:(List.hd prerequisite_ids :: prerequisite_ids) ()
    | Substitute_prerequisite ->
        compose
          ~missing:
            (replace_value "controlled-network-backend-current"
               "controlled-process-backend-current" prerequisite_ids)
          ()
    | Permit_acquire_without_backend ->
        compose ~mutate:(replace_field "acquire-backend-gate" "omitted") ()
    | Permit_acquire_without_named_remote ->
        compose ~mutate:(replace_field "acquire-remote-gate" "omitted") ()
    | Permit_acquire_without_operation_intent ->
        compose
          ~mutate:(replace_field "acquire-operation-intent-gate" "omitted")
          ()
    | Permit_acquire_without_credential ->
        compose ~mutate:(replace_field "acquire-credential-gate" "omitted") ()
    | Permit_acquire_without_clock ->
        compose ~mutate:(replace_field "acquire-clock-gate" "omitted") ()
    | Permit_acquire_without_approval ->
        compose ~mutate:(replace_field "acquire-approval-gate" "omitted") ()
    | Permit_release_without_eligibility ->
        compose ~mutate:(replace_field "release-eligibility-gate" "omitted") ()
    | Permit_release_during_active_operation ->
        compose ~mutate:(replace_field "active-operation-release" "permitted")
          ()
    | Permit_after_expiry ->
        compose ~mutate:(replace_field "expired-scope" "current") ()
    | Permit_after_revocation ->
        compose ~mutate:(replace_field "revoked-scope" "current") ()
    | Permit_after_cleanup ->
        compose ~mutate:(replace_field "cleaned-scope" "current") ()
    | Permit_changed_replay ->
        compose ~mutate:(replace_field "changed-replay" "stable") ()
    | Accept_raw_remote ->
        compose ~mutate:(replace_field "raw-remote" "accepted") ()
    | Add_raw_endpoint ->
        compose ~mutate:(replace_field "raw-endpoint" "present") ()
    | Add_raw_socket ->
        compose ~mutate:(replace_field "raw-socket" "present") ()
    | Add_raw_request_bytes ->
        compose ~mutate:(replace_field "raw-request-bytes" "present") ()
    | Expose_credential ->
        compose ~mutate:(replace_field "credential-projection" "present") ()
    | Expose_capability ->
        compose ~mutate:(replace_field "capability-projection" "present") ()
    | Add_callback ->
        compose ~mutate:(replace_field "callback" "present") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor ->
        compose ~mutate:(replace_field "registration-constructor" "present") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "present") ()
    | Promote_unavailable_backend ->
        compose ~mutate:(replace_field "network-backend" "current") ()
end

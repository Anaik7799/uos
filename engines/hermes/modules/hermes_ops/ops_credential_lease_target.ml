type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Credential_lease_operational_owner_current
  | Controlled_secret_provider_handoff_current
  | Credential_declaration_current_carrier
  | Remote_operation_context_current_carrier
  | Authority_role_session_fence
  | Approval_occurrence_capability_current
  | Bounded_clock_current_carrier
  | Request_bound_credential_transition_current_carrier
  | Remote_terminal_readback_cleanup_eligibility_current
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

let runtime_declaration = Jj_runtime_manifest.target_credential_lease
let target_protocol = Jj_target_protocol.Credential_lease
let accepted_roles =
  [ Jj_action_kind.Acquire_credential_lease;
    Jj_action_kind.Release_credential_lease ]
let accepted_effects = [ Run_topology.Credential_lease_transition ]

let binding_ids =
  [ "auxiliary:acquire-credential-lease->credential-lease-transition";
    "auxiliary:release-credential-lease->credential-lease-transition" ]

let prerequisites =
  [ Target_owner_part_current;
    Credential_lease_operational_owner_current;
    Controlled_secret_provider_handoff_current;
    Credential_declaration_current_carrier;
    Remote_operation_context_current_carrier;
    Authority_role_session_fence;
    Approval_occurrence_capability_current;
    Bounded_clock_current_carrier;
    Request_bound_credential_transition_current_carrier;
    Remote_terminal_readback_cleanup_eligibility_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Credential_lease_operational_owner_current ->
      "credential-lease-operational-owner-current"
  | Controlled_secret_provider_handoff_current ->
      "controlled-secret-provider-handoff-current"
  | Credential_declaration_current_carrier ->
      "credential-declaration-current-carrier"
  | Remote_operation_context_current_carrier ->
      "remote-operation-context-current-carrier"
  | Authority_role_session_fence -> "authority-role-session-fence"
  | Approval_occurrence_capability_current ->
      "approval-occurrence-capability-current"
  | Bounded_clock_current_carrier -> "bounded-clock-current-carrier"
  | Request_bound_credential_transition_current_carrier ->
      "request-bound-credential-transition-current-carrier"
  | Remote_terminal_readback_cleanup_eligibility_current ->
      "remote-terminal-readback-cleanup-eligibility-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-credential-lease-target";
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

let target_registry_schema_digest =
  Run_effect_authority.canonical_jj_target_registry_schema ()
  |> Run_effect_authority.jj_target_registry_schema_digest

let source_fields ~declaration ~target ~roles ~effects ~bindings ~missing =
  [ ("schema", "ops-credential-lease-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("dependency-schema-source", Jj_dependency_schema.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("credential-source", Dependability_credential.source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest);
    ("dependency-authority-source", Run_dependency_authority.source_digest);
    ("swarm-preparation-source", Run_swarm_preparation.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("target-registry-schema", target_registry_schema_digest);
    ("credential-config-declaration", "JUJUTSU_CREDENTIAL_POLICY");
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-effect-order", String.concat "," effects);
    ("action-effect-binding-order", String.concat "," bindings);
    ("missing-prerequisites", String.concat "," missing);
    ("acquire-provider-gate", "controlled-current-required");
    ("acquire-declaration-gate", "exact-current-required");
    ("acquire-remote-context-gate", "exact-current-required");
    ("acquire-approval-gate", "occurrence-capability-current-required");
    ("acquire-clock-gate", "bounded-clock-current-required");
    ("lease-remote-binding", "exact");
    ("lease-transport-binding", "exact");
    ("lease-session-binding", "exact-fenced-session");
    ("lease-activity-binding", "exact-request-activity");
    ("expired-lease", "absorbing-refused");
    ("revoked-lease", "absorbing-refused");
    ("cleaned-lease", "absorbing-refused");
    ("release-terminal-readback-gate", "exact-current-required");
    ("changed-replay", "absorbing-conflict");
    ("secret-bytes", "rejected");
    ("credential-string", "rejected");
    ("authorization-header", "rejected");
    ("environment", "absent:scrubbed-owner-side");
    ("raw-endpoint", "absent");
    ("lease-capability-projection", "absent");
    ("lease-reference-authority", "nonauthorizing");
    ("dependency-carrier-serialization", "forbidden");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("unavailable-lease-authorization", "denied");
    ("redacted-remote-projection", "absent");
    ("source-secret-binding", "absent");
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
    ~effects:effect_ids ~bindings:binding_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_dependency_schema_source
    | Drop_topology_source
    | Drop_credential_source
    | Drop_root_bootstrap_source
    | Drop_dependency_authority_source
    | Drop_swarm_preparation_source
    | Drop_event_prefix_source
    | Drop_target_registry_schema
    | Drop_credential_config_declaration
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Substitute_network_scope_protocol
    | Drop_acquire_role
    | Drop_release_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Substitute_network_scope_effect
    | Add_effect
    | Drop_acquire_binding
    | Drop_release_binding
    | Reorder_bindings
    | Duplicate_binding
    | Bind_acquire_to_network_scope_effect
    | Bind_release_to_network_scope_effect
    | Merge_acquire_release
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_acquire_without_provider
    | Permit_acquire_without_declaration
    | Permit_acquire_without_remote_context
    | Permit_acquire_without_approval
    | Permit_acquire_without_clock
    | Permit_cross_remote_lease
    | Permit_cross_transport_lease
    | Permit_cross_session_lease
    | Permit_cross_activity_lease
    | Permit_expired_lease
    | Permit_revoked_lease
    | Permit_cleaned_lease_reuse
    | Permit_release_before_terminal_readback
    | Permit_changed_replay
    | Accept_secret_bytes
    | Accept_credential_string
    | Accept_auth_header
    | Accept_environment
    | Accept_raw_endpoint
    | Expose_lease_capability
    | Accept_lease_reference_as_authority
    | Serialize_dependency_carrier
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_lease
    | Expose_redacted_remote
    | Bind_source_digest_to_secret_bytes

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
      ?(bindings = binding_ids) ?(missing = prerequisite_ids)
      ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~effects ~bindings ~missing
    |> mutate |> digest

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_dependency_schema_source ->
        compose ~mutate:(drop_field "dependency-schema-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_credential_source ->
        compose ~mutate:(drop_field "credential-source") ()
    | Drop_root_bootstrap_source ->
        compose ~mutate:(drop_field "root-bootstrap-source") ()
    | Drop_dependency_authority_source ->
        compose ~mutate:(drop_field "dependency-authority-source") ()
    | Drop_swarm_preparation_source ->
        compose ~mutate:(drop_field "swarm-preparation-source") ()
    | Drop_event_prefix_source ->
        compose ~mutate:(drop_field "event-prefix-source") ()
    | Drop_target_registry_schema ->
        compose ~mutate:(drop_field "target-registry-schema") ()
    | Drop_credential_config_declaration ->
        compose ~mutate:(drop_field "credential-config-declaration") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id Jj_runtime_manifest.target_network_scope)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Substitute_network_scope_protocol -> compose ~target:"network-scope" ()
    | Drop_acquire_role ->
        compose ~roles:(without "acquire-credential-lease" role_ids) ()
    | Drop_release_role ->
        compose ~roles:(without "release-credential-lease" role_ids) ()
    | Reorder_roles -> compose ~roles:(List.rev role_ids) ()
    | Add_role ->
        compose ~roles:(role_ids @ [ "acquire-network-scope" ]) ()
    | Drop_effect -> compose ~effects:[] ()
    | Substitute_network_scope_effect ->
        compose ~effects:[ "network-scope-transition" ] ()
    | Add_effect ->
        compose ~effects:(effect_ids @ [ "network-scope-transition" ]) ()
    | Drop_acquire_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:acquire-credential-lease->credential-lease-transition"
               binding_ids)
          ()
    | Drop_release_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:release-credential-lease->credential-lease-transition"
               binding_ids)
          ()
    | Reorder_bindings -> compose ~bindings:(List.rev binding_ids) ()
    | Duplicate_binding ->
        compose ~bindings:(List.hd binding_ids :: binding_ids) ()
    | Bind_acquire_to_network_scope_effect ->
        compose
          ~bindings:
            (replace_value
               "auxiliary:acquire-credential-lease->credential-lease-transition"
               "auxiliary:acquire-credential-lease->network-scope-transition"
               binding_ids)
          ()
    | Bind_release_to_network_scope_effect ->
        compose
          ~bindings:
            (replace_value
               "auxiliary:release-credential-lease->credential-lease-transition"
               "auxiliary:release-credential-lease->network-scope-transition"
               binding_ids)
          ()
    | Merge_acquire_release ->
        compose
          ~bindings:
            [ "auxiliary:credential-lease->credential-lease-transition" ]
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
            (replace_value "controlled-secret-provider-handoff-current"
               "ambient-secret-provider-current" prerequisite_ids)
          ()
    | Permit_acquire_without_provider ->
        compose ~mutate:(replace_field "acquire-provider-gate" "omitted") ()
    | Permit_acquire_without_declaration ->
        compose ~mutate:(replace_field "acquire-declaration-gate" "omitted") ()
    | Permit_acquire_without_remote_context ->
        compose ~mutate:(replace_field "acquire-remote-context-gate" "omitted")
          ()
    | Permit_acquire_without_approval ->
        compose ~mutate:(replace_field "acquire-approval-gate" "omitted") ()
    | Permit_acquire_without_clock ->
        compose ~mutate:(replace_field "acquire-clock-gate" "omitted") ()
    | Permit_cross_remote_lease ->
        compose ~mutate:(replace_field "lease-remote-binding" "any") ()
    | Permit_cross_transport_lease ->
        compose ~mutate:(replace_field "lease-transport-binding" "any") ()
    | Permit_cross_session_lease ->
        compose ~mutate:(replace_field "lease-session-binding" "any") ()
    | Permit_cross_activity_lease ->
        compose ~mutate:(replace_field "lease-activity-binding" "any") ()
    | Permit_expired_lease ->
        compose ~mutate:(replace_field "expired-lease" "current") ()
    | Permit_revoked_lease ->
        compose ~mutate:(replace_field "revoked-lease" "current") ()
    | Permit_cleaned_lease_reuse ->
        compose ~mutate:(replace_field "cleaned-lease" "reusable") ()
    | Permit_release_before_terminal_readback ->
        compose
          ~mutate:(replace_field "release-terminal-readback-gate" "omitted")
          ()
    | Permit_changed_replay ->
        compose ~mutate:(replace_field "changed-replay" "stable") ()
    | Accept_secret_bytes ->
        compose ~mutate:(replace_field "secret-bytes" "accepted") ()
    | Accept_credential_string ->
        compose ~mutate:(replace_field "credential-string" "accepted") ()
    | Accept_auth_header ->
        compose ~mutate:(replace_field "authorization-header" "accepted") ()
    | Accept_environment ->
        compose ~mutate:(replace_field "environment" "accepted") ()
    | Accept_raw_endpoint ->
        compose ~mutate:(replace_field "raw-endpoint" "present") ()
    | Expose_lease_capability ->
        compose ~mutate:(replace_field "lease-capability-projection" "present")
          ()
    | Accept_lease_reference_as_authority ->
        compose ~mutate:(replace_field "lease-reference-authority" "authorizing")
          ()
    | Serialize_dependency_carrier ->
        compose
          ~mutate:(replace_field "dependency-carrier-serialization" "allowed")
          ()
    | Add_callback -> compose ~mutate:(replace_field "callback" "present") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor ->
        compose ~mutate:(replace_field "registration-constructor" "present") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "present") ()
    | Promote_unavailable_lease ->
        compose
          ~mutate:(replace_field "unavailable-lease-authorization" "permitted")
          ()
    | Expose_redacted_remote ->
        compose ~mutate:(replace_field "redacted-remote-projection" "present")
          ()
    | Bind_source_digest_to_secret_bytes ->
        compose ~mutate:(replace_field "source-secret-binding" "present") ()
end

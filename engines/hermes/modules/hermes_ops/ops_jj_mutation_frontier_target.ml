type owner = |
type registration = |
type current_receipt = |

type terminal_readback_family =
  | Normal_b
  | B_selected_recovery
  | B_restarted_recovery
  | Completion_record
  | Completion_record_selected_recovery
  | Completion_record_restarted_recovery
  | Completion_final
  | Completion_reconcile_applied_exact
  | Completion_reconcile_not_applied

let terminal_readback_families =
  [ Normal_b; B_selected_recovery; B_restarted_recovery;
    Completion_record; Completion_record_selected_recovery;
    Completion_record_restarted_recovery; Completion_final;
    Completion_reconcile_applied_exact;
    Completion_reconcile_not_applied ]

let terminal_readback_family_id = function
  | Normal_b -> "normal-b"
  | B_selected_recovery -> "b-selected-recovery"
  | B_restarted_recovery -> "b-restarted-recovery"
  | Completion_record -> "completion-record"
  | Completion_record_selected_recovery ->
      "completion-record-selected-recovery"
  | Completion_record_restarted_recovery ->
      "completion-record-restarted-recovery"
  | Completion_final -> "completion-final"
  | Completion_reconcile_applied_exact ->
      "completion-reconcile-applied-exact"
  | Completion_reconcile_not_applied ->
      "completion-reconcile-not-applied"

type unavailable_prerequisite =
  | Target_owner_part_current
  | Mutation_frontier_operational_owner_current
  | Activity_generation_current_carrier
  | Approval_occurrence_capability_current
  | Writer_fence_session_current_carrier
  | Normal_b_terminal_readback_current_carrier
  | B_selected_recovery_terminal_readback_current_carrier
  | B_restarted_recovery_terminal_readback_current_carrier
  | Completion_record_terminal_readback_current_carrier
  | Completion_record_selected_recovery_terminal_readback_current_carrier
  | Completion_record_restarted_recovery_terminal_readback_current_carrier
  | Completion_final_terminal_readback_current_carrier
  | Completion_reconcile_applied_exact_terminal_readback_current_carrier
  | Completion_reconcile_not_applied_terminal_readback_current_carrier
  | Monotone_frontier_store_current
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

let runtime_declaration = Jj_runtime_manifest.target_mutation_frontier
let target_protocol = Jj_target_protocol.Mutation_frontier
let accepted_roles = []
let accepted_frontiers =
  [ Jj_action_kind.Set_activity_frontier
      Jj_action_kind.Reconciled_terminal ]
let accepted_effects = [ Run_topology.Jujutsu_local_mutation ]

let prerequisites =
  [ Target_owner_part_current;
    Mutation_frontier_operational_owner_current;
    Activity_generation_current_carrier;
    Approval_occurrence_capability_current;
    Writer_fence_session_current_carrier;
    Normal_b_terminal_readback_current_carrier;
    B_selected_recovery_terminal_readback_current_carrier;
    B_restarted_recovery_terminal_readback_current_carrier;
    Completion_record_terminal_readback_current_carrier;
    Completion_record_selected_recovery_terminal_readback_current_carrier;
    Completion_record_restarted_recovery_terminal_readback_current_carrier;
    Completion_final_terminal_readback_current_carrier;
    Completion_reconcile_applied_exact_terminal_readback_current_carrier;
    Completion_reconcile_not_applied_terminal_readback_current_carrier;
    Monotone_frontier_store_current; Dependency_carrier_owner_current;
    Effect_target_registration_current; Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Mutation_frontier_operational_owner_current ->
      "mutation-frontier-operational-owner-current"
  | Activity_generation_current_carrier ->
      "activity-generation-current-carrier"
  | Approval_occurrence_capability_current ->
      "approval-occurrence-capability-current"
  | Writer_fence_session_current_carrier ->
      "writer-fence-session-current-carrier"
  | Normal_b_terminal_readback_current_carrier ->
      "normal-b-terminal-readback-current-carrier"
  | B_selected_recovery_terminal_readback_current_carrier ->
      "b-selected-recovery-terminal-readback-current-carrier"
  | B_restarted_recovery_terminal_readback_current_carrier ->
      "b-restarted-recovery-terminal-readback-current-carrier"
  | Completion_record_terminal_readback_current_carrier ->
      "completion-record-terminal-readback-current-carrier"
  | Completion_record_selected_recovery_terminal_readback_current_carrier ->
      "completion-record-selected-recovery-terminal-readback-current-carrier"
  | Completion_record_restarted_recovery_terminal_readback_current_carrier ->
      "completion-record-restarted-recovery-terminal-readback-current-carrier"
  | Completion_final_terminal_readback_current_carrier ->
      "completion-final-terminal-readback-current-carrier"
  | Completion_reconcile_applied_exact_terminal_readback_current_carrier ->
      "completion-reconcile-applied-exact-terminal-readback-current-carrier"
  | Completion_reconcile_not_applied_terminal_readback_current_carrier ->
      "completion-reconcile-not-applied-terminal-readback-current-carrier"
  | Monotone_frontier_store_current -> "monotone-frontier-store-current"
  | Dependency_carrier_owner_current -> "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-jj-mutation-frontier-target";
    origin = `Evidence }

let production_posture = `Implemented_unavailable
let create_owner_unavailable () = Error (List.map diagnostic prerequisites)

let role_ids = List.map Jj_action_kind.auxiliary_role_key accepted_roles
let frontier_ids =
  List.map Jj_action_kind.frontier_action_key accepted_frontiers
let effect_ids = List.map Run_topology.effect_kind_id accepted_effects
let terminal_family_ids =
  List.map terminal_readback_family_id terminal_readback_families
let prerequisite_ids = List.map prerequisite_id prerequisites

let runtime_declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let target_registry_schema_digest =
  Run_effect_authority.canonical_jj_target_registry_schema ()
  |> Run_effect_authority.jj_target_registry_schema_digest

let source_fields ~declaration ~target ~roles ~frontiers ~effects
    ~terminal_families ~missing =
  [ ("schema", "ops-jj-mutation-frontier-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("campaign-action-source", Jj_campaign_action.source_digest);
    ("recovery-schema-source", Jj_recovery_schema.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("approval-source", Dependability_approval.source_digest);
    ("writer-lease-source", Dependability_writer_lease.source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest);
    ("conditional-authority-source", Run_conditional_authority.source_digest);
    ("dependency-authority-source", Run_dependency_authority.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("runtime-current-protocol-source",
     Jj_runtime_current_protocol.source_digest);
    ("runtime-registry-source", Run_jj_runtime_registry.source_digest);
    ("target-registry-schema", target_registry_schema_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-frontier-order", String.concat "," frontiers);
    ("accepted-effect-order", String.concat "," effects);
    ("terminal-readback-family-order", String.concat "," terminal_families);
    ("missing-prerequisites", String.concat "," missing);
    ("terminal-transition-law",
     "no-mutation+global-no-effect|mutation-may-have-applied+exact-readback->reconciled-terminal");
    ("early-terminal", "rejected");
    ("terminal-readback", "complete-exact-required");
    ("readback-prefix", "contiguous-required");
    ("target-capability-binding", "exact-target");
    ("activity-binding", "exact-activity");
    ("generation-binding", "exact-generation");
    ("writer-session-binding", "exact-session-fence");
    ("activation-conversion", "forbidden");
    ("branch-selection", "forbidden");
    ("fence-release", "forbidden");
    ("completion-finalize", "forbidden");
    ("repository-effect", "forbidden");
    ("process-effect", "forbidden");
    ("filesystem-effect", "forbidden");
    ("frontier-regression", "forbidden");
    ("changed-replay", "absorbing-conflict");
    ("raw-frontier-state", "absent");
    ("capability-projection", "absent:owner-resolved");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("owner-promotion", "implemented-unavailable");
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
    ~frontiers:frontier_ids ~effects:effect_ids
    ~terminal_families:terminal_family_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_campaign_action_source
    | Drop_recovery_schema_source
    | Drop_topology_source
    | Drop_approval_source
    | Drop_writer_lease_source
    | Drop_root_bootstrap_source
    | Drop_conditional_authority_source
    | Drop_dependency_authority_source
    | Drop_event_prefix_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_registry_source
    | Drop_target_registry_schema
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Substitute_transition_protocol
    | Add_auxiliary_role
    | Drop_frontier_action
    | Substitute_activation_frontier
    | Add_frontier_action
    | Drop_effect
    | Substitute_activation_effect
    | Add_effect
    | Drop_terminal_readback_family
    | Reorder_terminal_readback_families
    | Duplicate_terminal_readback_family
    | Add_diverged_terminal_readback_family
    | Merge_b_selected_restarted
    | Merge_record_selected_restarted
    | Merge_reconcile_outcomes
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_early_terminal_frontier
    | Permit_missing_readback
    | Permit_noncontiguous_readback_prefix
    | Permit_cross_target_capability
    | Permit_cross_activity_capability
    | Permit_cross_generation_capability
    | Permit_cross_session_fence
    | Permit_activation_through_frontier
    | Permit_branch_selection
    | Permit_fence_release
    | Permit_completion_finalize
    | Permit_repository_effect
    | Permit_process_effect
    | Permit_filesystem_effect
    | Permit_frontier_regression
    | Permit_changed_replay
    | Accept_raw_frontier_state
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_owner

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

  let merge_values first second merged values =
    values |> replace_value first merged |> without second

  let base_declaration = runtime_declaration_id runtime_declaration
  let base_target = Jj_target_protocol.key target_protocol

  let compose ?(declaration = base_declaration) ?(target = base_target)
      ?(roles = role_ids) ?(frontiers = frontier_ids)
      ?(effects = effect_ids) ?(terminal_families = terminal_family_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~frontiers ~effects
      ~terminal_families ~missing
    |> mutate |> digest

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_campaign_action_source ->
        compose ~mutate:(drop_field "campaign-action-source") ()
    | Drop_recovery_schema_source ->
        compose ~mutate:(drop_field "recovery-schema-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_approval_source ->
        compose ~mutate:(drop_field "approval-source") ()
    | Drop_writer_lease_source ->
        compose ~mutate:(drop_field "writer-lease-source") ()
    | Drop_root_bootstrap_source ->
        compose ~mutate:(drop_field "root-bootstrap-source") ()
    | Drop_conditional_authority_source ->
        compose ~mutate:(drop_field "conditional-authority-source") ()
    | Drop_dependency_authority_source ->
        compose ~mutate:(drop_field "dependency-authority-source") ()
    | Drop_event_prefix_source ->
        compose ~mutate:(drop_field "event-prefix-source") ()
    | Drop_runtime_current_protocol_source ->
        compose ~mutate:(drop_field "runtime-current-protocol-source") ()
    | Drop_runtime_registry_source ->
        compose ~mutate:(drop_field "runtime-registry-source") ()
    | Drop_target_registry_schema ->
        compose ~mutate:(drop_field "target-registry-schema") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id Jj_runtime_manifest.target_transition)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Substitute_transition_protocol ->
        compose ~target:(Jj_target_protocol.key Jj_target_protocol.Transition) ()
    | Add_auxiliary_role ->
        compose
          ~roles:
            (role_ids
             @ [ Jj_action_kind.auxiliary_role_key
                   Jj_action_kind.Consume_approval_nonce ])
          ()
    | Drop_frontier_action -> compose ~frontiers:[] ()
    | Substitute_activation_frontier ->
        compose
          ~frontiers:
            [ Jj_action_kind.frontier_action_key
                Jj_action_kind.Activate_source_recovery_branch ]
          ()
    | Add_frontier_action ->
        compose
          ~frontiers:
            (frontier_ids
             @ [ Jj_action_kind.frontier_action_key
                   Jj_action_kind.Activate_source_recovery_branch ])
          ()
    | Drop_effect -> compose ~effects:[] ()
    | Substitute_activation_effect ->
        compose
          ~effects:
            [ Run_topology.effect_kind_id
                Run_topology.Production_activation_transition ]
          ()
    | Add_effect ->
        compose
          ~effects:
            (effect_ids
             @ [ Run_topology.effect_kind_id
                   Run_topology.Production_activation_transition ])
          ()
    | Drop_terminal_readback_family ->
        compose ~terminal_families:(without "normal-b" terminal_family_ids) ()
    | Reorder_terminal_readback_families ->
        compose ~terminal_families:(List.rev terminal_family_ids) ()
    | Duplicate_terminal_readback_family ->
        compose
          ~terminal_families:
            (match terminal_family_ids with
             | [] -> [ "duplicate"; "duplicate" ]
             | first :: _ -> first :: terminal_family_ids)
          ()
    | Add_diverged_terminal_readback_family ->
        compose ~terminal_families:(terminal_family_ids @ [ "diverged" ]) ()
    | Merge_b_selected_restarted ->
        compose
          ~terminal_families:
            (merge_values "b-selected-recovery" "b-restarted-recovery"
               "b-recovery" terminal_family_ids)
          ()
    | Merge_record_selected_restarted ->
        compose
          ~terminal_families:
            (merge_values "completion-record-selected-recovery"
               "completion-record-restarted-recovery"
               "completion-record-recovery" terminal_family_ids)
          ()
    | Merge_reconcile_outcomes ->
        compose
          ~terminal_families:
            (merge_values "completion-reconcile-applied-exact"
               "completion-reconcile-not-applied" "completion-reconcile"
               terminal_family_ids)
          ()
    | Drop_prerequisite ->
        compose
          ~missing:(match prerequisite_ids with [] -> [] | _ :: rest -> rest)
          ()
    | Reorder_prerequisites -> compose ~missing:(List.rev prerequisite_ids) ()
    | Duplicate_prerequisite ->
        compose
          ~missing:
            (match prerequisite_ids with
             | [] -> [ "duplicate"; "duplicate" ]
             | first :: _ -> first :: prerequisite_ids)
          ()
    | Substitute_prerequisite ->
        compose
          ~missing:
            (replace_value "activity-generation-current-carrier"
               "caller-generation" prerequisite_ids)
          ()
    | Permit_early_terminal_frontier ->
        compose ~mutate:(replace_field "early-terminal" "accepted") ()
    | Permit_missing_readback ->
        compose ~mutate:(replace_field "terminal-readback" "optional") ()
    | Permit_noncontiguous_readback_prefix ->
        compose ~mutate:(replace_field "readback-prefix" "gaps-accepted") ()
    | Permit_cross_target_capability ->
        compose
          ~mutate:(replace_field "target-capability-binding" "transferable")
          ()
    | Permit_cross_activity_capability ->
        compose ~mutate:(replace_field "activity-binding" "transferable") ()
    | Permit_cross_generation_capability ->
        compose ~mutate:(replace_field "generation-binding" "transferable") ()
    | Permit_cross_session_fence ->
        compose
          ~mutate:(replace_field "writer-session-binding" "transferable") ()
    | Permit_activation_through_frontier ->
        compose ~mutate:(replace_field "activation-conversion" "allowed") ()
    | Permit_branch_selection ->
        compose ~mutate:(replace_field "branch-selection" "caller-selected") ()
    | Permit_fence_release ->
        compose ~mutate:(replace_field "fence-release" "allowed") ()
    | Permit_completion_finalize ->
        compose ~mutate:(replace_field "completion-finalize" "allowed") ()
    | Permit_repository_effect ->
        compose ~mutate:(replace_field "repository-effect" "allowed") ()
    | Permit_process_effect ->
        compose ~mutate:(replace_field "process-effect" "allowed") ()
    | Permit_filesystem_effect ->
        compose ~mutate:(replace_field "filesystem-effect" "allowed") ()
    | Permit_frontier_regression ->
        compose ~mutate:(replace_field "frontier-regression" "allowed") ()
    | Permit_changed_replay ->
        compose ~mutate:(replace_field "changed-replay" "reapply") ()
    | Accept_raw_frontier_state ->
        compose ~mutate:(replace_field "raw-frontier-state" "public") ()
    | Expose_capability ->
        compose ~mutate:(replace_field "capability-projection" "public") ()
    | Add_callback ->
        compose ~mutate:(replace_field "callback" "public-function") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor ->
        compose ~mutate:(replace_field "registration-constructor" "public") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "public") ()
    | Promote_unavailable_owner ->
        compose ~mutate:(replace_field "owner-promotion" "current") ()
end

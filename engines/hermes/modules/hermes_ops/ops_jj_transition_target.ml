type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Recovery_vault_owner_current
  | Recovery_transition_port_vault_current
  | Execution_local_transition_resolver_current
  | Recovery_transition_reference_current_carrier
  | Source_change_transition_commitment_current_carrier
  | B_selected_decision_current_carrier
  | Owner_produced_prefix_current_carrier
  | Apply_once_pending_transition_conversion_current
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

let runtime_declaration = Jj_runtime_manifest.target_transition
let target_protocol = Jj_target_protocol.Transition
let accepted_roles =
  [ Jj_action_kind.Stage_recovery_set;
    Jj_action_kind.Reconcile_recovery_set;
    Jj_action_kind.Cleanup_recovery_set ]
let accepted_frontiers = [ Jj_action_kind.Activate_source_recovery_branch ]
let accepted_effects =
  [ Run_topology.Controlled_filesystem_materialization;
    Run_topology.Production_activation_transition ]

let binding_ids =
  [ "auxiliary:stage-recovery-set->controlled-filesystem-materialization";
    "auxiliary:reconcile-recovery-set->controlled-filesystem-materialization";
    "auxiliary:cleanup-recovery-set->controlled-filesystem-materialization";
    "frontier:activate-source-recovery-branch->production-activation-transition" ]

let prerequisites =
  [ Target_owner_part_current; Recovery_vault_owner_current;
    Recovery_transition_port_vault_current;
    Execution_local_transition_resolver_current;
    Recovery_transition_reference_current_carrier;
    Source_change_transition_commitment_current_carrier;
    B_selected_decision_current_carrier;
    Owner_produced_prefix_current_carrier;
    Apply_once_pending_transition_conversion_current;
    Dependency_carrier_owner_current; Effect_target_registration_current;
    Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Recovery_vault_owner_current -> "recovery-vault-owner-current"
  | Recovery_transition_port_vault_current ->
      "recovery-transition-port-vault-current"
  | Execution_local_transition_resolver_current ->
      "execution-local-transition-resolver-current"
  | Recovery_transition_reference_current_carrier ->
      "recovery-transition-reference-current-carrier"
  | Source_change_transition_commitment_current_carrier ->
      "source-change-transition-commitment-current-carrier"
  | B_selected_decision_current_carrier ->
      "b-selected-decision-current-carrier"
  | Owner_produced_prefix_current_carrier ->
      "owner-produced-prefix-current-carrier"
  | Apply_once_pending_transition_conversion_current ->
      "apply-once-pending-transition-conversion-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-jj-transition-target";
    origin = `Evidence }

let production_posture = `Implemented_unavailable
let create_owner_unavailable () = Error (List.map diagnostic prerequisites)

let role_ids = List.map Jj_action_kind.auxiliary_role_key accepted_roles
let frontier_ids =
  List.map Jj_action_kind.frontier_action_key accepted_frontiers
let effect_ids = List.map Run_topology.effect_kind_id accepted_effects
let prerequisite_ids = List.map prerequisite_id prerequisites

let runtime_declaration_id declaration =
  Jj_id.length_frame
    [ Jj_runtime_manifest.declaration_key declaration;
      Jj_runtime_manifest.declaration_digest declaration ]

let source_fields ~declaration ~target ~roles ~frontiers ~effects ~bindings
    ~missing =
  [ ("schema", "ops-jj-transition-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("recovery-vault-source", Dependability_recovery_vault.source_digest);
    ("transition-port-protocol-source",
     Jj_recovery_transition_port_protocol.source_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-frontier-order", String.concat "," frontiers);
    ("accepted-effect-order", String.concat "," effects);
    ("action-effect-binding-order", String.concat "," bindings);
    ("missing-prerequisites", String.concat "," missing);
    ("stage-gate", "recovery-vault-current-required");
    ("reconcile-gate", "owner-produced-prefix-current-required");
    ("cleanup-gate", "reconciled-terminal-required");
    ("activation-decision-gate", "b-selected-decision-current-required");
    ("activation-commitment-gate",
     "source-change-transition-commitment-current-required");
    ("reference-session-binding", "exact-owner-session");
    ("reference-activity-binding", "exact-activity");
    ("reference-generation-binding", "exact-generation");
    ("caller-cut", "rejected");
    ("caller-effect", "rejected");
    ("raw-path", "absent");
    ("raw-bytes", "absent");
    ("vault-capability-projection", "absent");
    ("transition-port-projection", "absent");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("recovery-role-allocation",
     "transition-owner:stage,reconcile,cleanup;operational-contract-unavailable");
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
    ~frontiers:frontier_ids ~effects:effect_ids ~bindings:binding_ids
    ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_recovery_vault_source
    | Drop_transition_port_protocol_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_stage_role
    | Drop_reconcile_role
    | Drop_cleanup_role
    | Reorder_roles
    | Add_role
    | Drop_frontier
    | Substitute_frontier
    | Drop_filesystem_effect
    | Drop_activation_effect
    | Reorder_effects
    | Add_effect
    | Drop_stage_binding
    | Drop_reconcile_binding
    | Drop_cleanup_binding
    | Drop_activation_binding
    | Reorder_bindings
    | Duplicate_binding
    | Swap_stage_activation_effect_binding
    | Bind_reconcile_to_activation_effect
    | Bind_activation_to_filesystem_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_stage_without_vault
    | Permit_reconcile_without_prefix
    | Permit_cleanup_before_terminal
    | Permit_activation_without_selected_decision
    | Permit_activation_without_commitment
    | Permit_cross_session_reference
    | Permit_cross_activity_reference
    | Permit_cross_generation_reference
    | Accept_caller_cut
    | Accept_caller_effect
    | Add_raw_path
    | Add_raw_bytes
    | Expose_vault_capability
    | Expose_transition_port
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Merge_recovery_role_allocation

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

  let substitute_first before after values =
    let rec substitute = function
      | [] -> []
      | value :: rest when String.equal value before -> after :: rest
      | value :: rest -> value :: substitute rest
    in
    substitute values

  let base_declaration = runtime_declaration_id runtime_declaration
  let base_target = Jj_target_protocol.key target_protocol

  let compose ?(declaration = base_declaration) ?(target = base_target)
      ?(roles = role_ids) ?(frontiers = frontier_ids)
      ?(effects = effect_ids) ?(bindings = binding_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~frontiers ~effects ~bindings
      ~missing
    |> mutate |> digest

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_recovery_vault_source ->
        compose ~mutate:(drop_field "recovery-vault-source") ()
    | Drop_transition_port_protocol_source ->
        compose ~mutate:(drop_field "transition-port-protocol-source") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id
               Jj_runtime_manifest.target_mutation_frontier)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Drop_stage_role -> compose ~roles:(without "stage-recovery-set" role_ids) ()
    | Drop_reconcile_role ->
        compose ~roles:(without "reconcile-recovery-set" role_ids) ()
    | Drop_cleanup_role ->
        compose ~roles:(without "cleanup-recovery-set" role_ids) ()
    | Reorder_roles -> compose ~roles:(List.rev role_ids) ()
    | Add_role -> compose ~roles:(role_ids @ [ "write-partition" ]) ()
    | Drop_frontier -> compose ~frontiers:[] ()
    | Substitute_frontier ->
        compose ~frontiers:[ "set-activity-frontier:reconciled-terminal" ] ()
    | Drop_filesystem_effect ->
        compose
          ~effects:(without "controlled-filesystem-materialization" effect_ids)
          ()
    | Drop_activation_effect ->
        compose
          ~effects:(without "production-activation-transition" effect_ids)
          ()
    | Reorder_effects -> compose ~effects:(List.rev effect_ids) ()
    | Add_effect -> compose ~effects:(effect_ids @ [ "jujutsu-recovery" ]) ()
    | Drop_stage_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:stage-recovery-set->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_reconcile_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:reconcile-recovery-set->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_cleanup_binding ->
        compose
          ~bindings:
            (without
               "auxiliary:cleanup-recovery-set->controlled-filesystem-materialization"
               binding_ids)
          ()
    | Drop_activation_binding ->
        compose
          ~bindings:
            (without
               "frontier:activate-source-recovery-branch->production-activation-transition"
               binding_ids)
          ()
    | Reorder_bindings -> compose ~bindings:(List.rev binding_ids) ()
    | Duplicate_binding ->
        compose
          ~bindings:
            (match binding_ids with
             | [] -> [ "duplicate"; "duplicate" ]
             | first :: _ -> first :: binding_ids)
          ()
    | Swap_stage_activation_effect_binding ->
        compose
          ~bindings:
            (binding_ids
             |> replace_value
                  "auxiliary:stage-recovery-set->controlled-filesystem-materialization"
                  "auxiliary:stage-recovery-set->production-activation-transition"
             |> replace_value
                  "frontier:activate-source-recovery-branch->production-activation-transition"
                  "frontier:activate-source-recovery-branch->controlled-filesystem-materialization")
          ()
    | Bind_reconcile_to_activation_effect ->
        compose
          ~bindings:
            (replace_value
               "auxiliary:reconcile-recovery-set->controlled-filesystem-materialization"
               "auxiliary:reconcile-recovery-set->production-activation-transition"
               binding_ids)
          ()
    | Bind_activation_to_filesystem_effect ->
        compose
          ~bindings:
            (replace_value
               "frontier:activate-source-recovery-branch->production-activation-transition"
               "frontier:activate-source-recovery-branch->controlled-filesystem-materialization"
               binding_ids)
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
            (substitute_first "b-selected-decision-current-carrier"
               "caller-selected-branch" prerequisite_ids)
          ()
    | Permit_stage_without_vault ->
        compose ~mutate:(replace_field "stage-gate" "not-required") ()
    | Permit_reconcile_without_prefix ->
        compose ~mutate:(replace_field "reconcile-gate" "not-required") ()
    | Permit_cleanup_before_terminal ->
        compose ~mutate:(replace_field "cleanup-gate" "early") ()
    | Permit_activation_without_selected_decision ->
        compose
          ~mutate:(replace_field "activation-decision-gate" "not-required")
          ()
    | Permit_activation_without_commitment ->
        compose
          ~mutate:(replace_field "activation-commitment-gate" "not-required")
          ()
    | Permit_cross_session_reference ->
        compose
          ~mutate:(replace_field "reference-session-binding" "transferable")
          ()
    | Permit_cross_activity_reference ->
        compose
          ~mutate:(replace_field "reference-activity-binding" "transferable")
          ()
    | Permit_cross_generation_reference ->
        compose
          ~mutate:
            (replace_field "reference-generation-binding" "transferable")
          ()
    | Accept_caller_cut ->
        compose ~mutate:(replace_field "caller-cut" "accepted") ()
    | Accept_caller_effect ->
        compose ~mutate:(replace_field "caller-effect" "accepted") ()
    | Add_raw_path ->
        compose ~mutate:(replace_field "raw-path" "public-string") ()
    | Add_raw_bytes ->
        compose ~mutate:(replace_field "raw-bytes" "public-bytes") ()
    | Expose_vault_capability ->
        compose
          ~mutate:(replace_field "vault-capability-projection" "public") ()
    | Expose_transition_port ->
        compose
          ~mutate:(replace_field "transition-port-projection" "public") ()
    | Add_callback ->
        compose ~mutate:(replace_field "callback" "public-function") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor ->
        compose
          ~mutate:(replace_field "registration-constructor" "public") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "public") ()
    | Merge_recovery_role_allocation ->
        compose
          ~mutate:
            (replace_field "recovery-role-allocation" "generic-merged-owner")
          ()
end

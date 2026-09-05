type owner = |
type registration = |
type current_receipt = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Writer_lease_operational_owner_current
  | Physical_owner_lock_backend
  | Authority_role_session_fence
  | Nominal_writer_peer_open_fence
  | Authority_writer_fence_transition
  | Approval_occurrence_capability_current
  | Bounded_clock_current_carrier
  | Repository_before_state_current_carrier
  | Quiescence_or_fenced_session_current_carrier
  | Mutation_frontier_release_eligibility_current
  | Dependency_carrier_owner_current
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

let runtime_declaration = Jj_runtime_manifest.target_writer_lease
let target_protocol = Jj_target_protocol.Writer_lease
let accepted_roles =
  [ Jj_action_kind.Acquire_writer_lease; Jj_action_kind.Renew_writer_lease;
    Jj_action_kind.Release_writer_lease ]
let accepted_effects = [ Run_topology.Writer_lease_transition ]

let prerequisites =
  [ Target_owner_part_current; Writer_lease_operational_owner_current;
    Physical_owner_lock_backend; Authority_role_session_fence;
    Nominal_writer_peer_open_fence; Authority_writer_fence_transition;
    Approval_occurrence_capability_current; Bounded_clock_current_carrier;
    Repository_before_state_current_carrier;
    Quiescence_or_fenced_session_current_carrier;
    Mutation_frontier_release_eligibility_current;
    Dependency_carrier_owner_current; Event_effect_readback_current ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Writer_lease_operational_owner_current ->
      "writer-lease-operational-owner-current"
  | Physical_owner_lock_backend -> "physical-owner-lock-backend"
  | Authority_role_session_fence -> "authority-role-session-fence"
  | Nominal_writer_peer_open_fence -> "nominal-writer-peer-open-fence"
  | Authority_writer_fence_transition ->
      "authority-writer-fence-transition"
  | Approval_occurrence_capability_current ->
      "approval-occurrence-capability-current"
  | Bounded_clock_current_carrier -> "bounded-clock-current-carrier"
  | Repository_before_state_current_carrier ->
      "repository-before-state-current-carrier"
  | Quiescence_or_fenced_session_current_carrier ->
      "quiescence-or-fenced-session-current-carrier"
  | Mutation_frontier_release_eligibility_current ->
      "mutation-frontier-release-eligibility-current"
  | Dependency_carrier_owner_current ->
      "dependency-carrier-owner-current"
  | Event_effect_readback_current -> "event-effect-readback-current"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-jj-writer-lease-target";
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

let source_fields ~declaration ~target ~roles ~effects ~missing =
  [ ("schema", "ops-jj-writer-lease-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("writer-lease-owner-source", Dependability_writer_lease.source_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-effects", String.concat "," effects);
    ("missing-prerequisites", String.concat "," missing);
    ("acquire-lock-gate", "physical-owner-lock-required");
    ("renew-state-gate", "held-required");
    ("release-reconciliation-gate", "reconciled-terminal-required");
    ("release-frontier-gate", "release-eligible-current-required");
    ("session-binding", "exact-owner-session");
    ("repository-binding", "exact-repository-before-state");
    ("raw-lock", "absent");
    ("raw-time", "absent:bounded-clock-carrier-only");
    ("raw-lease", "absent");
    ("capability-projection", "absent:owner-resolved");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("current-constructor", "absent");
    ("registration-constructor", "absent");
    ("lower-contract-promotion", "forbidden");
    ("transition-denominator", "acquire,renew,release:distinct");
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
    ~effects:effect_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_action_kind_source
    | Drop_topology_source
    | Drop_writer_lease_owner_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_acquire_role
    | Drop_renew_role
    | Drop_release_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_acquire_without_lock
    | Permit_renew_without_held
    | Permit_release_after_unreconciled
    | Permit_release_without_frontier
    | Permit_cross_session_lease
    | Permit_cross_repository_lease
    | Accept_raw_lock
    | Accept_raw_time
    | Accept_raw_lease
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_current_constructor
    | Forge_registration
    | Promote_lower_contract
    | Merge_acquire_renew_release

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
      ?(roles = role_ids) ?(effects = effect_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~effects ~missing
    |> mutate |> digest

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_writer_lease_owner_source ->
        compose ~mutate:(drop_field "writer-lease-owner-source") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id Jj_runtime_manifest.target_approval)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Drop_acquire_role -> compose ~roles:(without "acquire-writer-lease" role_ids) ()
    | Drop_renew_role -> compose ~roles:(without "renew-writer-lease" role_ids) ()
    | Drop_release_role -> compose ~roles:(without "release-writer-lease" role_ids) ()
    | Reorder_roles -> compose ~roles:(List.rev role_ids) ()
    | Add_role -> compose ~roles:(role_ids @ [ "consume-approval-nonce" ]) ()
    | Drop_effect -> compose ~effects:[] ()
    | Add_effect ->
        compose ~effects:(effect_ids @ [ "approval-nonce-consumption" ]) ()
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
            (substitute_first "approval-occurrence-capability-current"
               "caller-approval-reference" prerequisite_ids)
          ()
    | Permit_acquire_without_lock ->
        compose ~mutate:(replace_field "acquire-lock-gate" "not-required") ()
    | Permit_renew_without_held ->
        compose ~mutate:(replace_field "renew-state-gate" "any-state") ()
    | Permit_release_after_unreconciled ->
        compose
          ~mutate:(replace_field "release-reconciliation-gate" "not-required")
          ()
    | Permit_release_without_frontier ->
        compose ~mutate:(replace_field "release-frontier-gate" "not-required") ()
    | Permit_cross_session_lease ->
        compose ~mutate:(replace_field "session-binding" "transferable") ()
    | Permit_cross_repository_lease ->
        compose ~mutate:(replace_field "repository-binding" "transferable") ()
    | Accept_raw_lock ->
        compose ~mutate:(replace_field "raw-lock" "public-handle") ()
    | Accept_raw_time ->
        compose ~mutate:(replace_field "raw-time" "caller-int64") ()
    | Accept_raw_lease ->
        compose ~mutate:(replace_field "raw-lease" "public-record") ()
    | Expose_capability ->
        compose ~mutate:(replace_field "capability-projection" "public") ()
    | Add_callback ->
        compose ~mutate:(replace_field "callback" "public-function") ()
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_current_constructor ->
        compose ~mutate:(replace_field "current-constructor" "public") ()
    | Forge_registration ->
        compose ~mutate:(replace_field "registration-constructor" "public") ()
    | Promote_lower_contract ->
        compose ~mutate:(replace_field "lower-contract-promotion" "current") ()
    | Merge_acquire_renew_release ->
        compose ~mutate:(replace_field "transition-denominator" "generic") ()
end

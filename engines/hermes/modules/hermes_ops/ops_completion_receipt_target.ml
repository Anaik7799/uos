type owner = |
type registration = |
type reservation_current = |
type completion_current = |

type unavailable_prerequisite =
  | Target_owner_part_current
  | Completion_reserve_owner_part_current
  | Completion_finalize_owner_part_current
  | Completion_store_operational_owner_current
  | Completion_store_nominal_peer_open_fence_current
  | Completion_store_session_epoch_current_carrier
  | Activity_generation_current_carrier
  | Approval_occurrence_capability_current
  | Bounded_clock_current_carrier
  | Reservation_source_head_campaign_current_carrier
  | Reservation_record_role_payload_current_carrier
  | Completion_reservation_current_carrier
  | Completion_branch_ordinal_current_carrier
  | Bookmark_poststate_readback_current_carrier
  | Writer_lease_release_current_carrier
  | Reconciled_terminal_frontier_current_carrier
  | Completion_transition_commitment_current_carrier
  | Completion_finalization_cas_current
  | Dependency_carrier_owner_current
  | Effect_target_registration_current
  | Event_effect_readback_current
  | Completion_store_readback_current_carrier

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

let runtime_declaration = Jj_runtime_manifest.target_completion_receipt
let target_protocol = Jj_target_protocol.Completion_receipt
let accepted_roles =
  [ Jj_action_kind.Reserve_completion_receipt;
    Jj_action_kind.Finalize_completion_receipt ]
let accepted_effects = [ Run_topology.Durable_artifact_publication ]

let binding_ids =
  [ "auxiliary:reserve-completion-receipt->durable-artifact-publication";
    "auxiliary:finalize-completion-receipt->durable-artifact-publication" ]

let protocol_binding_ids =
  [ "reserve-completion-receipt->Reserve:Completion_reservation";
    "finalize-completion-receipt->Finalize:Completion_final" ]

let lifecycle_law_ids =
  [ "absent+exact-reserve->reserved";
    "reservation-receipt->nonauthorizing";
    "same-reserve-request->stable-replay";
    "same-id+changed-reserve-request->conflict";
    "finalize-without-reservation->refused";
    "finalize-common-reservation-payload->exact-match-required";
    "finalize-bookmark-readback+lease-release+frontier+commitment+ordinal+occurrence->all-current-required";
    "reserved+exact-finalize->one-cas->finalized";
    "same-finalize-request->stable-replay";
    "same-id+changed-finalize-request->conflict";
    "indeterminate-or-conflict->operationally-blocked";
    "store-readback->nonauthorizing-no-credit";
    "lost-event-append->durable-store-readback+fresh-occurrence+same-final-payload+no-bookmark-repeat" ]

let prerequisites =
  [ Target_owner_part_current;
    Completion_reserve_owner_part_current;
    Completion_finalize_owner_part_current;
    Completion_store_operational_owner_current;
    Completion_store_nominal_peer_open_fence_current;
    Completion_store_session_epoch_current_carrier;
    Activity_generation_current_carrier;
    Approval_occurrence_capability_current;
    Bounded_clock_current_carrier;
    Reservation_source_head_campaign_current_carrier;
    Reservation_record_role_payload_current_carrier;
    Completion_reservation_current_carrier;
    Completion_branch_ordinal_current_carrier;
    Bookmark_poststate_readback_current_carrier;
    Writer_lease_release_current_carrier;
    Reconciled_terminal_frontier_current_carrier;
    Completion_transition_commitment_current_carrier;
    Completion_finalization_cas_current;
    Dependency_carrier_owner_current;
    Effect_target_registration_current;
    Event_effect_readback_current;
    Completion_store_readback_current_carrier ]

let prerequisite_id = function
  | Target_owner_part_current -> "target-owner-part-current"
  | Completion_reserve_owner_part_current ->
      "completion-reserve-owner-part-current"
  | Completion_finalize_owner_part_current ->
      "completion-finalize-owner-part-current"
  | Completion_store_operational_owner_current ->
      "completion-store-operational-owner-current"
  | Completion_store_nominal_peer_open_fence_current ->
      "completion-store-nominal-peer-open-fence-current"
  | Completion_store_session_epoch_current_carrier ->
      "completion-store-session-epoch-current-carrier"
  | Activity_generation_current_carrier ->
      "activity-generation-current-carrier"
  | Approval_occurrence_capability_current ->
      "approval-occurrence-capability-current"
  | Bounded_clock_current_carrier -> "bounded-clock-current-carrier"
  | Reservation_source_head_campaign_current_carrier ->
      "reservation-source-head-campaign-current-carrier"
  | Reservation_record_role_payload_current_carrier ->
      "reservation-record-role-payload-current-carrier"
  | Completion_reservation_current_carrier ->
      "completion-reservation-current-carrier"
  | Completion_branch_ordinal_current_carrier ->
      "completion-branch-ordinal-current-carrier"
  | Bookmark_poststate_readback_current_carrier ->
      "bookmark-poststate-readback-current-carrier"
  | Writer_lease_release_current_carrier ->
      "writer-lease-release-current-carrier"
  | Reconciled_terminal_frontier_current_carrier ->
      "reconciled-terminal-frontier-current-carrier"
  | Completion_transition_commitment_current_carrier ->
      "completion-transition-commitment-current-carrier"
  | Completion_finalization_cas_current ->
      "completion-finalization-cas-current"
  | Dependency_carrier_owner_current -> "dependency-carrier-owner-current"
  | Effect_target_registration_current ->
      "effect-target-registration-current"
  | Event_effect_readback_current -> "event-effect-readback-current"
  | Completion_store_readback_current_carrier ->
      "completion-store-readback-current-carrier"

let diagnostic prerequisite =
  { prerequisite;
    message = prerequisite_id prerequisite ^ " is unavailable";
    coordinate = "L3/Orient/ops-completion-receipt-target";
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
    ~protocol_bindings ~missing =
  [ ("schema", "ops-completion-receipt-target-foundation-v1");
    ("runtime-manifest-source", Jj_runtime_manifest.source_digest);
    ("target-protocol-source", Jj_target_protocol.source_digest);
    ("dependency-schema-source", Jj_dependency_schema.source_digest);
    ("action-kind-source", Jj_action_kind.source_digest);
    ("campaign-action-source", Jj_campaign_action.source_digest);
    ("completion-store-protocol-source",
     Jj_completion_store_protocol.source_digest);
    ("readback-source", Jj_readback.source_digest);
    ("topology-source", Run_topology.source_digest);
    ("completion-store-source", Dependability_completion_store.source_digest);
    ("writer-lease-source", Dependability_writer_lease.source_digest);
    ("approval-source", Dependability_approval.source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest);
    ("event-prefix-source", Run_event_store.event_prefix_source_digest);
    ("runtime-current-protocol-source",
     Jj_runtime_current_protocol.source_digest);
    ("runtime-declaration", declaration);
    ("target-protocol", target);
    ("accepted-role-order", String.concat "," roles);
    ("accepted-effect-order", String.concat "," effects);
    ("action-effect-binding-order", String.concat "," bindings);
    ("protocol-binding-order", String.concat "," protocol_bindings);
    ("missing-prerequisites", String.concat "," missing);
    ("lifecycle-law-order", String.concat "," lifecycle_law_ids);
    ("reservation-authority", "nonauthorizing");
    ("reservation-overwrite", "forbidden:conflict");
    ("reserve-source", "exact-current-required");
    ("reserve-head", "exact-current-required");
    ("reserve-campaign", "exact-current-required");
    ("reserve-record-role", "completion-reservation-required");
    ("changed-reserve-replay", "absorbing-conflict");
    ("finalize-reservation", "exact-reservation-required");
    ("finalize-role", "completion-final-required");
    ("finalize-source", "exact-reservation-source-required");
    ("finalize-head", "exact-reservation-head-required");
    ("finalize-campaign", "exact-reservation-campaign-required");
    ("finalize-payload", "exact-common-payload-required");
    ("finalize-bookmark-readback", "current-required");
    ("finalize-lease-release", "current-required");
    ("finalize-frontier", "reconciled-terminal-current-required");
    ("finalize-transition-commitment", "current-required");
    ("finalize-overwrite", "forbidden:conflict");
    ("finalize-cas", "exactly-one-required");
    ("changed-finalize-replay", "absorbing-conflict");
    ("activity-capability-binding", "exact-activity");
    ("generation-capability-binding", "exact-generation");
    ("owner-session-binding", "exact-owner-session");
    ("store-epoch-binding", "exact-store-epoch");
    ("reserve-finalize-capabilities", "disjoint-linear-parts");
    ("read-capability-projection", "absent");
    ("lifecycle-capability-projection", "absent");
    ("recovery-capability-projection", "absent");
    ("bookmark-mutation", "absent");
    ("repository-mutation", "absent");
    ("process-authority", "absent");
    ("network-authority", "absent");
    ("credential-authority", "absent");
    ("database-projection", "absent");
    ("location-projection", "absent");
    ("sql-projection", "absent");
    ("store-projection", "absent");
    ("payload-projection", "absent");
    ("capability-projection", "absent:owner-resolved");
    ("callback", "absent");
    ("caller-digest", "rejected");
    ("registration-constructor", "absent");
    ("current-constructor", "absent");
    ("owner-promotion", "implemented-unavailable");
    ("store-readback-credit", "nonauthorizing-no-credit");
    ("completion-history-authority", "distinct-nonauthorizing-consumer");
    ("lost-event-append", "store-readback+fresh-occurrence-required");
    ("blocked-row-close", "forbidden");
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
    ~protocol_bindings:protocol_binding_ids ~missing:prerequisite_ids
  |> digest

module For_test = struct
  type source_mutation =
    | Drop_runtime_manifest_source
    | Drop_target_protocol_source
    | Drop_dependency_schema_source
    | Drop_action_kind_source
    | Drop_campaign_action_source
    | Drop_completion_store_protocol_source
    | Drop_readback_source
    | Drop_topology_source
    | Drop_completion_store_source
    | Drop_writer_lease_source
    | Drop_approval_source
    | Drop_root_bootstrap_source
    | Drop_event_prefix_source
    | Drop_runtime_current_protocol_source
    | Drop_runtime_declaration
    | Substitute_runtime_declaration
    | Drop_target_protocol
    | Drop_reserve_role
    | Drop_finalize_role
    | Reorder_roles
    | Add_role
    | Drop_effect
    | Add_effect
    | Drop_reserve_binding
    | Drop_finalize_binding
    | Reorder_bindings
    | Duplicate_binding
    | Substitute_binding_effect
    | Drop_prerequisite
    | Reorder_prerequisites
    | Duplicate_prerequisite
    | Substitute_prerequisite
    | Permit_reservation_authority
    | Permit_reservation_overwrite
    | Permit_reserve_without_source
    | Permit_reserve_without_head
    | Permit_reserve_without_campaign
    | Permit_reserve_without_record_role
    | Permit_same_id_different_payload_replay
    | Permit_finalize_without_reservation
    | Permit_finalize_wrong_role
    | Permit_finalize_wrong_source
    | Permit_finalize_wrong_head
    | Permit_finalize_wrong_campaign
    | Permit_finalize_wrong_payload
    | Permit_finalize_without_bookmark_readback
    | Permit_finalize_without_lease_release
    | Permit_finalize_before_reconciled_frontier
    | Permit_finalize_without_completion_commitment
    | Permit_finalize_overwrite
    | Drop_finalize_cas
    | Permit_changed_finalize_replay
    | Permit_cross_activity_capability
    | Permit_cross_generation_capability
    | Permit_cross_owner_session
    | Permit_cross_store_epoch
    | Alias_reserve_finalize_capability
    | Expose_read_capability
    | Expose_lifecycle_capability
    | Expose_recovery_capability
    | Add_bookmark_mutation
    | Add_repository_mutation
    | Add_process
    | Add_network
    | Add_credential
    | Expose_database
    | Expose_location
    | Expose_sql
    | Expose_store
    | Expose_payload
    | Expose_capability
    | Add_callback
    | Accept_caller_digest
    | Add_registration_constructor
    | Add_current_constructor
    | Promote_unavailable_owner
    | Promote_store_readback_to_completion_credit
    | Alias_completion_history
    | Guess_lost_append
    | Permit_close_blocked_row

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
      ?(bindings = binding_ids) ?(protocol_bindings = protocol_binding_ids)
      ?(missing = prerequisite_ids) ?(mutate = Fun.id) () =
    source_fields ~declaration ~target ~roles ~effects ~bindings
      ~protocol_bindings ~missing
    |> mutate |> digest

  let permit field = compose ~mutate:(replace_field field "permitted") ()
  let expose field = compose ~mutate:(replace_field field "exposed") ()
  let add field = compose ~mutate:(replace_field field "present") ()

  let reserve_role_id =
    Jj_action_kind.auxiliary_role_key
      Jj_action_kind.Reserve_completion_receipt

  let finalize_role_id =
    Jj_action_kind.auxiliary_role_key
      Jj_action_kind.Finalize_completion_receipt

  let reserve_binding =
    "auxiliary:reserve-completion-receipt->durable-artifact-publication"

  let finalize_binding =
    "auxiliary:finalize-completion-receipt->durable-artifact-publication"

  let source_digest_with_mutation = function
    | Drop_runtime_manifest_source ->
        compose ~mutate:(drop_field "runtime-manifest-source") ()
    | Drop_target_protocol_source ->
        compose ~mutate:(drop_field "target-protocol-source") ()
    | Drop_dependency_schema_source ->
        compose ~mutate:(drop_field "dependency-schema-source") ()
    | Drop_action_kind_source ->
        compose ~mutate:(drop_field "action-kind-source") ()
    | Drop_campaign_action_source ->
        compose ~mutate:(drop_field "campaign-action-source") ()
    | Drop_completion_store_protocol_source ->
        compose ~mutate:(drop_field "completion-store-protocol-source") ()
    | Drop_readback_source -> compose ~mutate:(drop_field "readback-source") ()
    | Drop_topology_source -> compose ~mutate:(drop_field "topology-source") ()
    | Drop_completion_store_source ->
        compose ~mutate:(drop_field "completion-store-source") ()
    | Drop_writer_lease_source ->
        compose ~mutate:(drop_field "writer-lease-source") ()
    | Drop_approval_source ->
        compose ~mutate:(drop_field "approval-source") ()
    | Drop_root_bootstrap_source ->
        compose ~mutate:(drop_field "root-bootstrap-source") ()
    | Drop_event_prefix_source ->
        compose ~mutate:(drop_field "event-prefix-source") ()
    | Drop_runtime_current_protocol_source ->
        compose ~mutate:(drop_field "runtime-current-protocol-source") ()
    | Drop_runtime_declaration -> compose ~declaration:"" ()
    | Substitute_runtime_declaration ->
        compose
          ~declaration:
            (runtime_declaration_id Jj_runtime_manifest.target_release)
          ()
    | Drop_target_protocol -> compose ~target:"" ()
    | Drop_reserve_role -> compose ~roles:(without reserve_role_id role_ids) ()
    | Drop_finalize_role ->
        compose ~roles:(without finalize_role_id role_ids) ()
    | Reorder_roles -> compose ~roles:(List.rev role_ids) ()
    | Add_role ->
        compose
          ~roles:
            (role_ids
             @ [ Jj_action_kind.auxiliary_role_key
                   Jj_action_kind.Consume_approval_nonce ])
          ()
    | Drop_effect -> compose ~effects:[] ()
    | Add_effect ->
        compose
          ~effects:
            (effect_ids
             @ [ Run_topology.effect_kind_id
                   Run_topology.Jujutsu_local_mutation ])
          ()
    | Drop_reserve_binding ->
        compose ~bindings:(without reserve_binding binding_ids) ()
    | Drop_finalize_binding ->
        compose ~bindings:(without finalize_binding binding_ids) ()
    | Reorder_bindings -> compose ~bindings:(List.rev binding_ids) ()
    | Duplicate_binding ->
        compose ~bindings:(reserve_binding :: binding_ids) ()
    | Substitute_binding_effect ->
        compose
          ~bindings:
            (replace_value finalize_binding
               "auxiliary:finalize-completion-receipt->jujutsu-local-mutation"
               binding_ids)
          ()
    | Drop_prerequisite ->
        compose
          ~missing:(without "target-owner-part-current" prerequisite_ids)
          ()
    | Reorder_prerequisites -> compose ~missing:(List.rev prerequisite_ids) ()
    | Duplicate_prerequisite ->
        compose ~missing:("target-owner-part-current" :: prerequisite_ids) ()
    | Substitute_prerequisite ->
        compose
          ~missing:
            (replace_value "target-owner-part-current"
               "target-owner-part-guessed" prerequisite_ids)
          ()
    | Permit_reservation_authority -> permit "reservation-authority"
    | Permit_reservation_overwrite -> permit "reservation-overwrite"
    | Permit_reserve_without_source -> permit "reserve-source"
    | Permit_reserve_without_head -> permit "reserve-head"
    | Permit_reserve_without_campaign -> permit "reserve-campaign"
    | Permit_reserve_without_record_role -> permit "reserve-record-role"
    | Permit_same_id_different_payload_replay ->
        permit "changed-reserve-replay"
    | Permit_finalize_without_reservation -> permit "finalize-reservation"
    | Permit_finalize_wrong_role -> permit "finalize-role"
    | Permit_finalize_wrong_source -> permit "finalize-source"
    | Permit_finalize_wrong_head -> permit "finalize-head"
    | Permit_finalize_wrong_campaign -> permit "finalize-campaign"
    | Permit_finalize_wrong_payload -> permit "finalize-payload"
    | Permit_finalize_without_bookmark_readback ->
        permit "finalize-bookmark-readback"
    | Permit_finalize_without_lease_release ->
        permit "finalize-lease-release"
    | Permit_finalize_before_reconciled_frontier ->
        permit "finalize-frontier"
    | Permit_finalize_without_completion_commitment ->
        permit "finalize-transition-commitment"
    | Permit_finalize_overwrite -> permit "finalize-overwrite"
    | Drop_finalize_cas ->
        compose ~mutate:(replace_field "finalize-cas" "absent") ()
    | Permit_changed_finalize_replay -> permit "changed-finalize-replay"
    | Permit_cross_activity_capability -> permit "activity-capability-binding"
    | Permit_cross_generation_capability ->
        permit "generation-capability-binding"
    | Permit_cross_owner_session -> permit "owner-session-binding"
    | Permit_cross_store_epoch -> permit "store-epoch-binding"
    | Alias_reserve_finalize_capability ->
        compose
          ~mutate:
            (replace_field "reserve-finalize-capabilities" "aliased")
          ()
    | Expose_read_capability -> expose "read-capability-projection"
    | Expose_lifecycle_capability -> expose "lifecycle-capability-projection"
    | Expose_recovery_capability -> expose "recovery-capability-projection"
    | Add_bookmark_mutation -> add "bookmark-mutation"
    | Add_repository_mutation -> add "repository-mutation"
    | Add_process -> add "process-authority"
    | Add_network -> add "network-authority"
    | Add_credential -> add "credential-authority"
    | Expose_database -> expose "database-projection"
    | Expose_location -> expose "location-projection"
    | Expose_sql -> expose "sql-projection"
    | Expose_store -> expose "store-projection"
    | Expose_payload -> expose "payload-projection"
    | Expose_capability -> expose "capability-projection"
    | Add_callback -> add "callback"
    | Accept_caller_digest ->
        compose ~mutate:(replace_field "caller-digest" "accepted") ()
    | Add_registration_constructor -> add "registration-constructor"
    | Add_current_constructor -> add "current-constructor"
    | Promote_unavailable_owner ->
        compose ~mutate:(replace_field "owner-promotion" "available") ()
    | Promote_store_readback_to_completion_credit ->
        compose
          ~mutate:(replace_field "store-readback-credit" "completion-credit")
          ()
    | Alias_completion_history ->
        compose
          ~mutate:
            (replace_field "completion-history-authority" "aliased-authority")
          ()
    | Guess_lost_append ->
        compose ~mutate:(replace_field "lost-event-append" "guessed") ()
    | Permit_close_blocked_row -> permit "blocked-row-close"
end

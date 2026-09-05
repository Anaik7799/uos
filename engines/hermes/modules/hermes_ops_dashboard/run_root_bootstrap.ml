type rca_origin = Specification | Implementation | Environment | Evidence | Control

type diagnostic =
  | Lower_authority_distribution_conflict
  | Operational_split_conflict
  | Operational_part_already_taken
  | Five_owner_inventory_current_carriers_unavailable
  | Peer_inventory_fence_bundle_unavailable
  | Authority_recovery_bound_session_unavailable
  | Recovery_only_terminal_current_carrier_unavailable
  | Target_entry_inventory_current_carrier_unavailable
  | Effect_prefix_current_carrier_unavailable
  | Event_prefix_current_carrier_unavailable
  | Mutation_frontier_current_carrier_unavailable
  | Quiescent_or_fenced_current_carrier_unavailable
  | Before_after_current_carrier_unavailable
  | Abandonment_producer_seal_bundle_unavailable
  | Dispatch_abandonment_writer_capability_unavailable
  | Dispatch_conditional_decision_capability_unavailable

let diagnostic_code = function
  | Lower_authority_distribution_conflict ->
      "lower-authority-distribution-conflict"
  | Operational_split_conflict -> "operational-split-conflict"
  | Operational_part_already_taken -> "operational-part-already-taken"
  | Five_owner_inventory_current_carriers_unavailable ->
      "five-owner-inventory-current-carriers-unavailable"
  | Peer_inventory_fence_bundle_unavailable ->
      "peer-inventory-fence-bundle-unavailable"
  | Authority_recovery_bound_session_unavailable ->
      "authority-recovery-bound-session-unavailable"
  | Recovery_only_terminal_current_carrier_unavailable ->
      "recovery-only-terminal-current-carrier-unavailable"
  | Target_entry_inventory_current_carrier_unavailable ->
      "target-entry-inventory-current-carrier-unavailable"
  | Effect_prefix_current_carrier_unavailable ->
      "effect-prefix-current-carrier-unavailable"
  | Event_prefix_current_carrier_unavailable ->
      "event-prefix-current-carrier-unavailable"
  | Mutation_frontier_current_carrier_unavailable ->
      "mutation-frontier-current-carrier-unavailable"
  | Quiescent_or_fenced_current_carrier_unavailable ->
      "quiescent-or-fenced-current-carrier-unavailable"
  | Before_after_current_carrier_unavailable ->
      "before-after-current-carrier-unavailable"
  | Abandonment_producer_seal_bundle_unavailable ->
      "abandonment-producer-seal-bundle-unavailable"
  | Dispatch_abandonment_writer_capability_unavailable ->
      "dispatch-abandonment-writer-capability-unavailable"
  | Dispatch_conditional_decision_capability_unavailable ->
      "dispatch-conditional-decision-capability-unavailable"

let diagnostic_coordinate _ = "L2.Task6.RootBootstrap"
let diagnostic_origin _ = Evidence

type unavailable_prerequisite =
  | Five_owner_inventory_current_carriers
  | Peer_inventory_fence_bundle
  | Authority_recovery_bound_session
  | Recovery_only_terminal_current_carrier
  | Target_entry_inventory_current_carrier
  | Effect_prefix_current_carrier
  | Event_prefix_current_carrier
  | Mutation_frontier_current_carrier
  | Quiescent_or_fenced_current_carrier
  | Before_after_current_carrier
  | Abandonment_producer_seal_bundle
  | Dispatch_abandonment_writer_capability
  | Dispatch_conditional_decision_capability
  | Dispatch_abandonment_inventory_current_carrier
  | Dispatch_conditional_inventory_current_carrier
  | Authority_approval_inventory_current_carrier

let prerequisite_status = function
  | Five_owner_inventory_current_carriers ->
      Error Five_owner_inventory_current_carriers_unavailable
  | Peer_inventory_fence_bundle ->
      Error Peer_inventory_fence_bundle_unavailable
  | Authority_recovery_bound_session ->
      Error Authority_recovery_bound_session_unavailable
  | Recovery_only_terminal_current_carrier ->
      Error Recovery_only_terminal_current_carrier_unavailable
  | Target_entry_inventory_current_carrier ->
      Error Target_entry_inventory_current_carrier_unavailable
  | Effect_prefix_current_carrier ->
      Error Effect_prefix_current_carrier_unavailable
  | Event_prefix_current_carrier ->
      Error Event_prefix_current_carrier_unavailable
  | Mutation_frontier_current_carrier ->
      Error Mutation_frontier_current_carrier_unavailable
  | Quiescent_or_fenced_current_carrier ->
      Error Quiescent_or_fenced_current_carrier_unavailable
  | Before_after_current_carrier ->
      Error Before_after_current_carrier_unavailable
  | Abandonment_producer_seal_bundle ->
      Error Abandonment_producer_seal_bundle_unavailable
  | Dispatch_abandonment_writer_capability ->
      Error Dispatch_abandonment_writer_capability_unavailable
  | Dispatch_conditional_decision_capability ->
      Error Dispatch_conditional_decision_capability_unavailable
  | Dispatch_abandonment_inventory_current_carrier ->
      Ok ()
  | Dispatch_conditional_inventory_current_carrier ->
      Ok ()
  | Authority_approval_inventory_current_carrier ->
      Ok ()

let production_posture = `Implemented_unavailable

type operational_root
type recovery_root
type recovery_only_root

type operational_parts = {
  approval_nonce :
    Dependability_authority_store.approval_nonce_capability option Atomic.t;
  approval_dormancy :
    Dependability_authority_store.approval_dormancy_capability option Atomic.t;
  approval_abandonment :
    Dependability_authority_store.approval_abandonment_capability option Atomic.t;
  writer_fence :
    Dependability_authority_store.writer_fence_capability option Atomic.t;
  production_activation :
    Dependability_authority_store.production_activation_capability option Atomic.t;
  recovery_port_issuer :
    Dependability_authority_store.recovery_port_issuer_capability option Atomic.t;
  recovery_port_lifecycle :
    Dependability_authority_store.recovery_port_lifecycle_capability option Atomic.t;
  lifecycle :
    Dependability_authority_store.lifecycle_capability option Atomic.t;
  writer_open :
    Dependability_authority_store.writer_operational_open option Atomic.t;
  dispatch_open :
    Dependability_authority_store.dispatch_operational_open option Atomic.t;
  vault_open :
    Dependability_authority_store.vault_operational_open option Atomic.t;
  completion_open :
    Dependability_authority_store.completion_operational_open option Atomic.t;
}

type 'phase jj_owner_bundle = {
  parts : operational_parts;
  split : bool Atomic.t;
}

let ( let* ) value next =
  match value with Ok result -> next result | Error _ -> Error Lower_authority_distribution_conflict

let compose_lower_operational_once lower =
  let roles = Dependability_authority_store.role_bundle lower in
  let peers = Dependability_authority_store.peer_operational_open_bundle lower in
  let* approval_nonce = Dependability_authority_store.take_approval_nonce roles in
  let* approval_dormancy =
    Dependability_authority_store.take_approval_dormancy roles
  in
  let* approval_abandonment =
    Dependability_authority_store.take_approval_abandonment roles
  in
  let* writer_fence = Dependability_authority_store.take_writer_fence roles in
  let* production_activation =
    Dependability_authority_store.take_production_activation roles
  in
  let* recovery_port_issuer =
    Dependability_authority_store.take_recovery_port_issuer roles
  in
  let* recovery_port_lifecycle =
    Dependability_authority_store.take_recovery_port_lifecycle roles
  in
  let* lifecycle = Dependability_authority_store.take_lifecycle roles in
  let* writer_open, dispatch_open, vault_open, completion_open =
    Dependability_authority_store.split_peer_operational_open_once peers
  in
  Ok
    { split = Atomic.make false;
      parts =
        { approval_nonce = Atomic.make (Some approval_nonce);
          approval_dormancy = Atomic.make (Some approval_dormancy);
          approval_abandonment = Atomic.make (Some approval_abandonment);
          writer_fence = Atomic.make (Some writer_fence);
          production_activation = Atomic.make (Some production_activation);
          recovery_port_issuer = Atomic.make (Some recovery_port_issuer);
          recovery_port_lifecycle = Atomic.make (Some recovery_port_lifecycle);
          lifecycle = Atomic.make (Some lifecycle);
          writer_open = Atomic.make (Some writer_open);
          dispatch_open = Atomic.make (Some dispatch_open);
          vault_open = Atomic.make (Some vault_open);
          completion_open = Atomic.make (Some completion_open) } }

let lower_bundle_posture _ = `Lower_distribution_only

let split_operational_once root =
  if Atomic.compare_and_set root.split false true then Ok root.parts
  else Error Operational_split_conflict

type target_read_only_view_package = |
type effect_read_only_view_package = |
type event_read_only_view_package = |
type target_owner_parts = |
type abandonment_authority_part = |
type conditional_interpreter_part = |

let take_target_read_only_views _ =
  Error Target_entry_inventory_current_carrier_unavailable

let take_effect_read_only_views _ =
  Error Effect_prefix_current_carrier_unavailable

let take_event_read_only_views _ =
  Error Event_prefix_current_carrier_unavailable

let take_target_owner_parts _ =
  Error Target_entry_inventory_current_carrier_unavailable

let take_abandonment_authority_part _ =
  Error Abandonment_producer_seal_bundle_unavailable

let take_conditional_interpreter_part _ =
  Error Dispatch_conditional_decision_capability_unavailable

let take projection parts =
  match Atomic.exchange (projection parts) None with
  | None -> Error Operational_part_already_taken
  | Some capability -> Ok capability

let take_approval_nonce =
  take (fun parts -> parts.approval_nonce)

let take_approval_dormancy =
  take (fun parts -> parts.approval_dormancy)

let take_approval_abandonment =
  take (fun parts -> parts.approval_abandonment)

let take_writer_fence =
  take (fun parts -> parts.writer_fence)

let take_production_activation =
  take (fun parts -> parts.production_activation)

let take_recovery_port_issuer =
  take (fun parts -> parts.recovery_port_issuer)

let take_recovery_port_lifecycle =
  take (fun parts -> parts.recovery_port_lifecycle)

let take_lifecycle = take (fun parts -> parts.lifecycle)

let take_writer_open = take (fun parts -> parts.writer_open)

let take_dispatch_open = take (fun parts -> parts.dispatch_open)

let take_vault_open = take (fun parts -> parts.vault_open)

let take_completion_open = take (fun parts -> parts.completion_open)

type opened
type awaiting_abandonment
type awaiting_conditional
type awaiting_terminal
type 'phase recovery_parts = |
type abandonment_recovery_part = |
type conditional_recovery_part = |
type recovery_only_runtime_part = |
type recovery_only_tail = |

let split_recovery_once _ = Error Peer_inventory_fence_bundle_unavailable

let prepare_abandonment_recovery_once _ =
  Error Abandonment_producer_seal_bundle_unavailable

let prepare_conditional_recovery_inputs_once _ ~abandonments:_ =
  Error Peer_inventory_fence_bundle_unavailable

type recovery_finish = |

let recovery_finish_kind :
    recovery_finish -> [ `Operational_ready | `Recovery_only_ready ] = function
  | _ -> .

let finish_recovery_once _ ~conditional:_ =
  Error Five_owner_inventory_current_carriers_unavailable

let await_recovery_terminal_once _ =
  Error Five_owner_inventory_current_carriers_unavailable

let split_recovery_only_once _ =
  Error Authority_recovery_bound_session_unavailable

let finish_recovery_only_once _ ~terminal:_ =
  Error Recovery_only_terminal_current_carrier_unavailable

let sha256 values =
  values |> String.concat "\000"
  |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let task8_prerequisites =
  [ Target_entry_inventory_current_carrier;
    Effect_prefix_current_carrier;
    Event_prefix_current_carrier;
    Mutation_frontier_current_carrier;
    Quiescent_or_fenced_current_carrier;
    Before_after_current_carrier;
    Abandonment_producer_seal_bundle;
    Dispatch_abandonment_writer_capability;
    Dispatch_conditional_decision_capability;
    Dispatch_abandonment_inventory_current_carrier;
    Dispatch_conditional_inventory_current_carrier;
    Authority_approval_inventory_current_carrier ]

let prerequisite_code prerequisite =
  match prerequisite_status prerequisite with
  | Error unavailable -> diagnostic_code unavailable
  | Ok () -> "available"

let task8_prerequisite_schema =
  task8_prerequisites |> List.map prerequisite_code |> String.concat ","

let source_fields =
  [ ("schema", "run-root-bootstrap-task8-package-v3");
    ("authority-store-source", Dependability_authority_store.source_digest);
    ("owner-inventory-source", Dependability_owner_inventory.source_digest);
    ("operational-root", "lower-authority-distribution-only");
    ("role-denominator",
     "approval-nonce,approval-dormancy,approval-abandonment,writer-fence,production-activation,recovery-port-issuer,recovery-port-lifecycle,lifecycle");
    ("peer-open-denominator", "writer,dispatch,recovery-vault,completion-store");
    ("root-split", "one-shot");
    ("part-take", "independent-one-shot");
    ("five-owner-current", "unavailable");
    ("producer-seals", "seven-distinct-nonconstructible");
    ("task8-prerequisite-schema", task8_prerequisite_schema);
    ("task8-package-order",
     "target-view,effect-view,event-view,target-owner,abandonment-authority,conditional-interpreter");
    ("target-read-only-view", "unavailable");
    ("effect-read-only-view", "unavailable");
    ("event-read-only-view", "unavailable");
    ("target-owner-part", "unavailable");
    ("abandonment-authority-part", "unavailable");
    ("conditional-interpreter-part", "unavailable");
    ("recovery-phase-order",
     "opened,awaiting-abandonment,awaiting-conditional");
    ("abandonment-recovery-part", "unavailable");
    ("conditional-recovery-part", "unavailable-before-peer-fence");
    ("native-recovery-inventory-join",
     "abandonment-input,conditional-output,approval-output");
    ("recovery-finish-gate", "conditional-terminal-plus-five-owner-current");
    ("recovery-finish-visibility", "abstract-result-with-kind-projection");
    ("recovery-only-gate", "bound-session-plus-terminal-current");
    ("upper-edge-posture", "no-abandonment-conditional-bridge-operator-edge") ]

let source_digest_of fields =
  fields
  |> List.concat_map (fun (name, value) -> [ name; value ])
  |> sha256

let source_digest = source_digest_of source_fields

module For_test = struct
  type mutation =
    | Duplicate_operational_split
    | Duplicate_part_take
    | Forge_inventory_current
    | Invent_generic_producer_seal
    | Drop_peer_inventory_fence
    | Cast_recovery_phase
    | Promote_without_terminal
    | Add_upper_task8_view
    | Forge_target_read_only_view
    | Forge_effect_read_only_view
    | Forge_event_read_only_view
    | Forge_abandonment_authority_part
    | Forge_conditional_interpreter_part
    | Forge_abandonment_recovery_part
    | Skip_abandonment_recovery_phase
    | Drop_task8_prerequisite_schema
    | Reorder_task8_package_order
    | Flatten_native_recovery_inventory_join
    | Expose_recovery_finish_constructor

  let drop name fields =
    List.filter (fun (candidate, _) -> not (String.equal candidate name)) fields

  let replace name value fields =
    List.map
      (fun ((candidate, _) as field) ->
        if String.equal candidate name then (candidate, value) else field)
      fields

  let source_digest_with_mutation mutation =
    let fields =
      match mutation with
      | Duplicate_operational_split ->
          replace "root-split" "repeatable" source_fields
      | Duplicate_part_take ->
          replace "part-take" "repeatable" source_fields
      | Forge_inventory_current ->
          replace "five-owner-current" "caller-constructible" source_fields
      | Invent_generic_producer_seal ->
          replace "producer-seals" "generic-constructible" source_fields
      | Drop_peer_inventory_fence ->
          drop "peer-open-denominator" source_fields
      | Cast_recovery_phase ->
          replace "recovery-phase-order" "phase-castable" source_fields
      | Promote_without_terminal ->
          replace "recovery-finish-gate" "no-terminal-required" source_fields
      | Add_upper_task8_view ->
          replace "target-read-only-view" "current-without-carrier" source_fields
      | Forge_target_read_only_view ->
          replace "target-read-only-view" "caller-constructible" source_fields
      | Forge_effect_read_only_view ->
          replace "effect-read-only-view" "caller-constructible" source_fields
      | Forge_event_read_only_view ->
          replace "event-read-only-view" "caller-constructible" source_fields
      | Forge_abandonment_authority_part ->
          replace "abandonment-authority-part" "caller-constructible"
            source_fields
      | Forge_conditional_interpreter_part ->
          replace "conditional-interpreter-part" "caller-constructible"
            source_fields
      | Forge_abandonment_recovery_part ->
          replace "abandonment-recovery-part" "caller-constructible"
            source_fields
      | Skip_abandonment_recovery_phase ->
          replace "recovery-phase-order" "opened,awaiting-conditional"
            source_fields
      | Drop_task8_prerequisite_schema ->
          drop "task8-prerequisite-schema" source_fields
      | Reorder_task8_package_order ->
          replace "task8-package-order"
            "conditional-interpreter,abandonment-authority,target-owner,event-view,effect-view,target-view"
            source_fields
      | Flatten_native_recovery_inventory_join ->
          replace "native-recovery-inventory-join" "caller-list-and-digest"
            source_fields
      | Expose_recovery_finish_constructor ->
          replace "recovery-finish-visibility" "public-constructor" source_fields
    in
    source_digest_of fields
end

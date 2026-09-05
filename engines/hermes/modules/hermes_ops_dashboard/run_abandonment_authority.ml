type rca_origin = Specification | Implementation | Environment | Evidence | Control

type prerequisite =
  | Root_abandonment_authority_part
  | Root_abandonment_recovery_part
  | Approved_plan_current_receipt
  | Dispatch_claim_current_receipt
  | Target_entry_inventory_current_receipt
  | Effect_prefix_current_receipt
  | Event_prefix_current_receipt
  | Frontier_current_receipt
  | Quiescent_or_fenced_current_receipt
  | Before_after_current_receipt
  | Seven_distinct_producer_seals
  | Dispatch_abandonment_writer_capability
  | Dispatch_abandonment_inventory_current_carrier

type diagnostic = {
  prerequisite : prerequisite;
  code : string;
  coordinate : string;
  origin : rca_origin;
}

let prerequisite_id = function
  | Root_abandonment_authority_part -> "root-abandonment-authority-part"
  | Root_abandonment_recovery_part -> "root-abandonment-recovery-part"
  | Approved_plan_current_receipt -> "approved-plan-current-receipt"
  | Dispatch_claim_current_receipt -> "dispatch-claim-current-receipt"
  | Target_entry_inventory_current_receipt ->
      "target-entry-inventory-current-receipt"
  | Effect_prefix_current_receipt -> "effect-prefix-current-receipt"
  | Event_prefix_current_receipt -> "event-prefix-current-receipt"
  | Frontier_current_receipt -> "frontier-current-receipt"
  | Quiescent_or_fenced_current_receipt ->
      "quiescent-or-fenced-current-receipt"
  | Before_after_current_receipt -> "before-after-current-receipt"
  | Seven_distinct_producer_seals -> "seven-distinct-producer-seals"
  | Dispatch_abandonment_writer_capability ->
      "dispatch-abandonment-writer-capability"
  | Dispatch_abandonment_inventory_current_carrier ->
      "dispatch-abandonment-inventory-current-carrier"

let diagnostic prerequisite =
  { prerequisite;
    code = "abandonment-prerequisite-unavailable:" ^ prerequisite_id prerequisite;
    coordinate = "L3/Act/run-abandonment-authority";
    origin = Specification }

let prerequisite_status = function
  | Dispatch_abandonment_inventory_current_carrier -> Ok ()
  | prerequisite -> Error (diagnostic prerequisite)
let diagnostic_code value = value.code
let diagnostic_prerequisite value = value.prerequisite
let diagnostic_coordinate value = value.coordinate
let diagnostic_origin value = value.origin
let production_posture = `Implemented_unavailable

type global_no_effect = Dependability_abandonment_protocol.global_no_effect
type fenced_unentered_tail =
  Dependability_abandonment_protocol.fenced_unentered_tail

type 'purpose purpose = 'purpose Dependability_abandonment_protocol.purpose =
  | Global_no_effect : global_no_effect purpose
  | Fenced_unentered_tail : fenced_unentered_tail purpose

type role =
  | Claim
  | Target_entry
  | Effect
  | Event
  | Frontier
  | Session
  | Before_after

type requirement =
  | Exact_dispatch_session_attempt_claim
  | No_source_changing_target_entry
  | Terminal_entered_target_prefix_and_tail_unentered
  | No_effect_applied
  | Terminal_entered_effect_prefix_and_tail_unentered
  | No_effect_event
  | Terminal_entered_event_prefix_and_tail_unentered
  | No_mutation_attempted
  | Terminal_mutation_frontier_and_tail_unentered
  | Quiescent_or_fenced_dead
  | Exact_operation_tree_source_equal_and_resources_released
  | Pending_transition_and_writer_fence_retained

let purpose_id : type p. p purpose -> string = function
  | Global_no_effect -> "global-no-effect"
  | Fenced_unentered_tail -> "fenced-unentered-tail"

let role_id = function
  | Claim -> "claim"
  | Target_entry -> "target-entry"
  | Effect -> "effect"
  | Event -> "event"
  | Frontier -> "frontier"
  | Session -> "session"
  | Before_after -> "before-after"

let requirement_id = function
  | Exact_dispatch_session_attempt_claim ->
      "exact-dispatch-session-attempt-claim"
  | No_source_changing_target_entry -> "no-source-changing-target-entry"
  | Terminal_entered_target_prefix_and_tail_unentered ->
      "terminal-entered-target-prefix-and-tail-unentered"
  | No_effect_applied -> "no-effect-applied"
  | Terminal_entered_effect_prefix_and_tail_unentered ->
      "terminal-entered-effect-prefix-and-tail-unentered"
  | No_effect_event -> "no-effect-event"
  | Terminal_entered_event_prefix_and_tail_unentered ->
      "terminal-entered-event-prefix-and-tail-unentered"
  | No_mutation_attempted -> "no-mutation-attempted"
  | Terminal_mutation_frontier_and_tail_unentered ->
      "terminal-mutation-frontier-and-tail-unentered"
  | Quiescent_or_fenced_dead -> "quiescent-or-fenced-dead"
  | Exact_operation_tree_source_equal_and_resources_released ->
      "exact-operation-tree-source-equal-and-resources-released"
  | Pending_transition_and_writer_fence_retained ->
      "pending-transition-and-writer-fence-retained"

type 'purpose denominator = { purpose : 'purpose purpose }

let denominator purpose = { purpose }

let fixed_roles =
  [ Claim; Target_entry; Effect; Event; Frontier; Session; Before_after ]

let denominator_count _ = List.length fixed_roles

let denominator_requires _ role = List.mem role fixed_roles

let denominator_position _ role =
  let rec find index = function
    | [] -> None
    | candidate :: rest ->
        if candidate = role then Some index else find (index + 1) rest
  in
  find 0 fixed_roles

let role_requirement : type p. p denominator -> role -> requirement =
 fun denominator role ->
  match denominator.purpose, role with
  | Global_no_effect, Claim -> Exact_dispatch_session_attempt_claim
  | Fenced_unentered_tail, Claim -> Exact_dispatch_session_attempt_claim
  | Global_no_effect, Target_entry -> No_source_changing_target_entry
  | Fenced_unentered_tail, Target_entry ->
      Terminal_entered_target_prefix_and_tail_unentered
  | Global_no_effect, Effect -> No_effect_applied
  | Fenced_unentered_tail, Effect ->
      Terminal_entered_effect_prefix_and_tail_unentered
  | Global_no_effect, Event -> No_effect_event
  | Fenced_unentered_tail, Event ->
      Terminal_entered_event_prefix_and_tail_unentered
  | Global_no_effect, Frontier -> No_mutation_attempted
  | Fenced_unentered_tail, Frontier ->
      Terminal_mutation_frontier_and_tail_unentered
  | Global_no_effect, Session -> Quiescent_or_fenced_dead
  | Fenced_unentered_tail, Session -> Quiescent_or_fenced_dead
  | Global_no_effect, Before_after ->
      Exact_operation_tree_source_equal_and_resources_released
  | Fenced_unentered_tail, Before_after ->
      Pending_transition_and_writer_fence_retained

type t = |

let create (_part : Run_root_bootstrap.abandonment_authority_part) :
    (t, diagnostic) result =
  Error (diagnostic Root_abandonment_authority_part)

let commit_global_no_effect () =
  Error (diagnostic Approved_plan_current_receipt)

let commit_fenced_unentered_tail () =
  Error (diagnostic Approved_plan_current_receipt)

let reconcile_recovery_only
    (_part : Run_root_bootstrap.abandonment_recovery_part) :
    (Dependability_dispatch_store.abandonment_inventory_current, diagnostic)
    result =
  Error (diagnostic Root_abandonment_recovery_part)

let sha256 value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = string_of_int (String.length value) ^ ":" ^ value

let digest_fields fields =
  fields
  |> List.map (fun (name, value) -> frame name ^ frame value)
  |> String.concat ""
  |> sha256

let requirement_denominator purpose =
  fixed_roles
  |> List.map (fun role ->
       role_id role ^ "="
       ^ requirement_id (role_requirement (denominator purpose) role))
  |> String.concat ","

let current_receipt_prerequisites =
  [ Approved_plan_current_receipt; Dispatch_claim_current_receipt;
    Target_entry_inventory_current_receipt; Effect_prefix_current_receipt;
    Event_prefix_current_receipt; Frontier_current_receipt;
    Quiescent_or_fenced_current_receipt; Before_after_current_receipt ]
  |> List.map prerequisite_id
  |> String.concat ","

let source_fields =
  [ ("schema", "run-abandonment-authority-v3");
    ("lower-protocol-source", Dependability_abandonment_protocol.source_digest);
    ("root-bootstrap-source", Run_root_bootstrap.source_digest);
    ("dispatch-store-source", Dependability_dispatch_store.source_digest);
    ("production-posture", "implemented-unavailable");
    ("purpose-global", purpose_id Global_no_effect);
    ("purpose-fenced", purpose_id Fenced_unentered_tail);
    ("role-denominator", String.concat "," (List.map role_id fixed_roles));
    ("global-requirements", requirement_denominator Global_no_effect);
    ("fenced-requirements", requirement_denominator Fenced_unentered_tail);
    ("root-operational-prerequisite",
     prerequisite_id Root_abandonment_authority_part);
    ("root-recovery-prerequisite",
     prerequisite_id Root_abandonment_recovery_part);
    ("current-receipt-prerequisites", current_receipt_prerequisites);
    ("producer-seals-prerequisite",
     prerequisite_id Seven_distinct_producer_seals);
    ("dispatch-writer-prerequisite",
     prerequisite_id Dispatch_abandonment_writer_capability);
    ("native-recovery-carrier",
     "Run_root_bootstrap.abandonment_recovery_part->Dependability_dispatch_store.abandonment_inventory_current");
    ("native-create-carrier",
     "Run_root_bootstrap.abandonment_authority_part->Run_abandonment_authority.t");
    ("create", "unavailable");
    ("commit", "unavailable");
    ("reconcile", "unavailable");
    ("purpose-separation", "distinct") ]

let source_digest = digest_fields source_fields

module For_test = struct
  type denominator_mutation =
    | Drop_claim
    | Drop_target_entry
    | Drop_effect
    | Drop_event
    | Drop_frontier
    | Drop_session
    | Drop_before_after
    | Duplicate_session
    | Swap_effect_and_event
    | Use_other_purpose_requirements

  let roles_with_mutation = function
    | Drop_claim -> List.filter (( <> ) Claim) fixed_roles
    | Drop_target_entry -> List.filter (( <> ) Target_entry) fixed_roles
    | Drop_effect -> List.filter (( <> ) Effect) fixed_roles
    | Drop_event -> List.filter (( <> ) Event) fixed_roles
    | Drop_frontier -> List.filter (( <> ) Frontier) fixed_roles
    | Drop_session -> List.filter (( <> ) Session) fixed_roles
    | Drop_before_after -> List.filter (( <> ) Before_after) fixed_roles
    | Duplicate_session ->
        [ Claim; Target_entry; Effect; Event; Frontier; Session; Session;
          Before_after ]
    | Swap_effect_and_event ->
        [ Claim; Target_entry; Event; Effect; Frontier; Session; Before_after ]
    | Use_other_purpose_requirements -> fixed_roles

  let requirement_ids purpose roles =
    let fixed = denominator purpose in
    List.map
      (fun role -> requirement_id (role_requirement fixed role))
      roles

  let other_requirement_ids : type p. p purpose -> string list = function
    | Global_no_effect -> requirement_ids Fenced_unentered_tail fixed_roles
    | Fenced_unentered_tail -> requirement_ids Global_no_effect fixed_roles

  let denominator_is_exact_with_mutation purpose mutation =
    let candidate_roles = roles_with_mutation mutation in
    let candidate_requirements =
      match mutation with
      | Use_other_purpose_requirements -> other_requirement_ids purpose
      | _ -> requirement_ids purpose candidate_roles
    in
    candidate_roles = fixed_roles
    && candidate_requirements = requirement_ids purpose fixed_roles

  type source_mutation =
    | Drop_lower_protocol_source
    | Drop_root_bootstrap_source
    | Drop_dispatch_store_source
    | Drop_global_no_effect_purpose
    | Drop_fenced_unentered_tail_purpose
    | Drop_role_denominator
    | Swap_role_order
    | Drop_current_receipt_prerequisites
    | Drop_producer_seals_prerequisite
    | Drop_dispatch_writer_prerequisite
    | Enable_create
    | Enable_commit
    | Enable_reconcile
    | Coerce_global_to_fenced_purpose
    | Use_placeholder_recovery_carrier
    | Use_unit_create_placeholder

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
      | Drop_lower_protocol_source -> drop "lower-protocol-source" source_fields
      | Drop_root_bootstrap_source -> drop "root-bootstrap-source" source_fields
      | Drop_dispatch_store_source -> drop "dispatch-store-source" source_fields
      | Drop_global_no_effect_purpose -> drop "purpose-global" source_fields
      | Drop_fenced_unentered_tail_purpose -> drop "purpose-fenced" source_fields
      | Drop_role_denominator -> drop "role-denominator" source_fields
      | Swap_role_order ->
          replace "role-denominator"
            "claim,target-entry,event,effect,frontier,session,before-after"
            source_fields
      | Drop_current_receipt_prerequisites ->
          drop "current-receipt-prerequisites" source_fields
      | Drop_producer_seals_prerequisite ->
          drop "producer-seals-prerequisite" source_fields
      | Drop_dispatch_writer_prerequisite ->
          drop "dispatch-writer-prerequisite" source_fields
      | Enable_create -> replace "create" "enabled" source_fields
      | Enable_commit -> replace "commit" "enabled" source_fields
      | Enable_reconcile -> replace "reconcile" "enabled" source_fields
      | Coerce_global_to_fenced_purpose ->
          replace "purpose-separation" "coerced" source_fields
      | Use_placeholder_recovery_carrier ->
          replace "native-recovery-carrier" "unit->local-placeholder"
            source_fields
      | Use_unit_create_placeholder ->
          replace "native-create-carrier" "unit->local-placeholder"
            source_fields
    in
    digest_fields fields
end

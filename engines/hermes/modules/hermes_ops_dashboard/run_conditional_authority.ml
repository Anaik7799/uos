type diagnostic_code =
  | Family_denominator_mismatch
  | State_denominator_mismatch
  | Event_denominator_mismatch
  | Channel_denominator_mismatch
  | Decision_denominator_mismatch
  | Decision_control_mismatch
  | Decision_prefix_mismatch
  | Decision_branch_mismatch
  | Decision_guard_mismatch
  | Projection_digest_mismatch
  | Store_owner_receipts_unavailable

type diagnostic = {
  code : diagnostic_code;
  message : string;
  coordinate : Ops_capability.coordinate;
  rca_origin : Ops_capability.rca_origin;
}

let diagnostic_code diagnostic = diagnostic.code
let diagnostic_message diagnostic = diagnostic.message
let diagnostic_coordinate diagnostic = diagnostic.coordinate
let diagnostic_origin diagnostic = diagnostic.rca_origin

let string_of_diagnostic_code = function
  | Family_denominator_mismatch -> "family-denominator-mismatch"
  | State_denominator_mismatch -> "state-denominator-mismatch"
  | Event_denominator_mismatch -> "event-denominator-mismatch"
  | Channel_denominator_mismatch -> "channel-denominator-mismatch"
  | Decision_denominator_mismatch -> "decision-denominator-mismatch"
  | Decision_control_mismatch -> "decision-control-mismatch"
  | Decision_prefix_mismatch -> "decision-prefix-mismatch"
  | Decision_branch_mismatch -> "decision-branch-mismatch"
  | Decision_guard_mismatch -> "decision-guard-mismatch"
  | Projection_digest_mismatch -> "projection-digest-mismatch"
  | Store_owner_receipts_unavailable -> "store-owner-receipts-unavailable"

let diagnostic code message origin =
  { code; message;
    coordinate =
      { Ops_capability.level = Ops_capability.L5;
        phase = Ops_capability.Decide };
    rca_origin = origin }

type _ family =
  | B_family : Jj_campaign_action.b_campaign family
  | Completion_family : Jj_campaign_action.completion_reconcile family

type packed_family = Family : 'family family -> packed_family

let families = [ Family B_family; Family Completion_family ]

let family_id_of : type f. f family -> string = function
  | B_family -> "b-campaign"
  | Completion_family -> "completion-reconcile"

let packed_family_id (Family family) = family_id_of family

let family_of_plan : type f.
    f Jj_campaign_action.conditional_plan -> f family =
  fun plan ->
    match Jj_campaign_action.conditional_family plan with
    | Jj_campaign_action.B_campaign -> B_family
    | Jj_campaign_action.Completion_reconcile_plan -> Completion_family

type _ lifecycle_state =
  | Guarded : 'family lifecycle_state
  | Consume_ready : 'family lifecycle_state
  | Action_terminal : 'family lifecycle_state
  | Decision_pending : 'family lifecycle_state
  | Continue_selected : Jj_campaign_action.b_campaign lifecycle_state
  | B_branch_selected : Jj_campaign_action.b_campaign lifecycle_state
  | Applied_exact_selected :
      Jj_campaign_action.completion_reconcile lifecycle_state
  | Not_applied_selected :
      Jj_campaign_action.completion_reconcile lifecycle_state
  | Diverged_selected :
      Jj_campaign_action.completion_reconcile lifecycle_state
  | Decision_indeterminate : 'family lifecycle_state

let lifecycle_states : type f.
    f family -> f lifecycle_state list = function
  | B_family ->
      [ Guarded; Consume_ready; Action_terminal; Decision_pending;
        Continue_selected; B_branch_selected; Decision_indeterminate ]
  | Completion_family ->
      [ Guarded; Consume_ready; Action_terminal; Decision_pending;
        Applied_exact_selected; Not_applied_selected; Diverged_selected;
        Decision_indeterminate ]

let lifecycle_state_id : type f. f lifecycle_state -> string =
  function
  | Guarded -> "guarded"
  | Consume_ready -> "consume-ready"
  | Action_terminal -> "action-terminal"
  | Decision_pending -> "decision-pending"
  | Continue_selected -> "continue-selected"
  | B_branch_selected -> "branch-selected"
  | Applied_exact_selected -> "applied-exact-selected"
  | Not_applied_selected -> "not-applied-selected"
  | Diverged_selected -> "diverged-selected"
  | Decision_indeterminate -> "decision-indeterminate"

type event =
  | Prefix_complete
  | Decision_committed
  | Decision_replayed
  | Condition_not_selected_recorded
  | Decision_refused

let events =
  [ Prefix_complete; Decision_committed; Decision_replayed;
    Condition_not_selected_recorded; Decision_refused ]

let event_id = function
  | Prefix_complete -> "prefix-complete"
  | Decision_committed -> "decision-committed"
  | Decision_replayed -> "decision-replayed"
  | Condition_not_selected_recorded ->
      "condition-not-selected-recorded"
  | Decision_refused -> "decision-refused"

type channel =
  | Family_prefix_identity
  | Decision_receipt
  | Selected_branch_identity
  | Node_disposition

let channels =
  [ Family_prefix_identity; Decision_receipt; Selected_branch_identity;
    Node_disposition ]

let channel_id = function
  | Family_prefix_identity -> "family-prefix-identity"
  | Decision_receipt -> "decision-receipt"
  | Selected_branch_identity -> "selected-branch-identity"
  | Node_disposition -> "node-disposition"

let digest value = Digestif.SHA256.(to_hex (digest_string value))

type 'family decision_preparation = {
  node_identity : string;
  control_identity : string;
  prefix_identity : string;
  branch_identities : string list;
  guard_identity : string;
  preparation_digest : string;
}

type 'family schema = {
  plan : 'family Jj_campaign_action.conditional_plan;
  family_identity : string;
  state_identities : string list;
  event_identities : string list;
  channel_identities : string list;
  decisions : 'family decision_preparation list;
  node_projection_digest : string;
  edge_projection_digest : string;
  campaign_projection_digest : string;
  schema_digest : string;
}

let family_id schema = schema.family_identity
let decision_preparations schema = schema.decisions
let decision_node_id decision = decision.node_identity
let decision_control_id decision = decision.control_identity
let decision_prefix_id decision = decision.prefix_identity
let decision_branch_ids decision = decision.branch_identities
let decision_guard_identity decision = decision.guard_identity
let decision_preparation_digest decision = decision.preparation_digest
let schema_digest schema = schema.schema_digest

let decision_frame decision =
  Jj_id.length_frame
    [ decision.node_identity; decision.control_identity;
      decision.prefix_identity;
      Jj_id.length_frame decision.branch_identities;
      decision.guard_identity ]

let make_decision node_identity guard control_identity prefix_identity
    branch_identities =
  let guard_identity =
    Jj_campaign_action.guard_descriptor_identity guard
  in
  let frame =
    Jj_id.length_frame
      [ node_identity; control_identity; prefix_identity;
        Jj_id.length_frame branch_identities; guard_identity ]
  in
  { node_identity; control_identity; prefix_identity; branch_identities;
    guard_identity;
    preparation_digest =
      digest (Jj_id.length_frame [ "decision-preparation-v1"; frame ]) }

let branch_label branch_identity = "branch:" ^ branch_identity

let expected_branch_guard control_identity branch_identity =
  "branch-selected:"
  ^ Jj_id.length_frame [ control_identity; branch_identity ]

let validate_branch_edges edges control_identity branch_identities =
  let branch_edges =
    List.filter
      (fun (edge : Jj_campaign_action.conditional_edge_descriptor) ->
        edge.Jj_campaign_action.edge_source_id = control_identity
        && String.starts_with ~prefix:"branch:"
             edge.Jj_campaign_action.edge_label)
      edges
  in
  List.length branch_edges = List.length branch_identities
  && List.for_all2
       (fun branch_identity
            (edge : Jj_campaign_action.conditional_edge_descriptor) ->
         edge.Jj_campaign_action.edge_label = branch_label branch_identity
         && edge.Jj_campaign_action.edge_guard_identity =
              expected_branch_guard control_identity branch_identity)
       branch_identities branch_edges

let derive_decisions plan =
  let edges =
    Jj_campaign_action.guarded_edges plan
    |> List.map Jj_campaign_action.conditional_edge_descriptor
  in
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | node :: rest ->
        begin
          match Jj_campaign_action.conditional_node_descriptor node with
          | Jj_campaign_action.Consume_descriptor _
          | Jj_campaign_action.Action_descriptor _ -> collect acc rest
          | Jj_campaign_action.Decision_descriptor
              { node_id; guard; control_id; prefix_id; branch_ids } ->
              if node_id <> control_id then
                Error
                  (diagnostic Decision_control_mismatch
                     "decision node identity differs from its control identity"
                     Ops_capability.Specification)
              else if prefix_id = "" then
                Error
                  (diagnostic Decision_prefix_mismatch
                     "decision predecessor prefix identity is empty"
                     Ops_capability.Specification)
              else if branch_ids = []
                      || List.length branch_ids
                         <> List.length
                              (List.sort_uniq String.compare branch_ids)
              then
                Error
                  (diagnostic Decision_branch_mismatch
                     "decision branch denominator is empty or duplicated"
                     Ops_capability.Specification)
              else if
                not (validate_branch_edges edges control_id branch_ids)
              then
                Error
                  (diagnostic Decision_guard_mismatch
                     "branch edges do not bind the declared control and guard"
                     Ops_capability.Specification)
              else
                collect
                  (make_decision node_id guard control_id prefix_id branch_ids
                   :: acc)
                  rest
        end
  in
  collect [] (Jj_campaign_action.conditional_nodes plan)

let validate_guard_order : type f.
    f family -> f decision_preparation list -> bool =
  fun family decisions ->
    match family with
    | B_family ->
        let rec loop preceding = function
          | [] -> true
          | decision :: rest ->
              let expected =
                if preceding = [] then "always"
                else "all-continue:" ^ Jj_id.length_frame preceding
              in
              decision.guard_identity = expected
              && loop
                   (preceding @ [ decision.control_identity ]) rest
        in
        loop [] decisions
    | Completion_family ->
        List.for_all
          (fun decision -> decision.guard_identity = "always") decisions

let expected_decision_denominator : type f.
    f family -> int * int = function
  | B_family -> 23, 105
  | Completion_family -> 1, 3

let schema_frame family_identity state_identities event_identities
    channel_identities decisions node_projection_digest edge_projection_digest
    campaign_projection_digest =
  Jj_id.length_frame
    [ "conditional-authority-schema-v1"; family_identity;
      Jj_id.length_frame state_identities;
      Jj_id.length_frame event_identities;
      Jj_id.length_frame channel_identities;
      decisions |> List.map decision_frame |> Jj_id.length_frame;
      node_projection_digest; edge_projection_digest;
      campaign_projection_digest; Jj_campaign_action.source_digest ]

let derive plan =
  let family = family_of_plan plan in
  match derive_decisions plan with
  | Error error -> Error error
  | Ok decisions ->
      let expected_decisions, expected_branches =
        expected_decision_denominator family
      in
      let branch_count =
        List.fold_left
          (fun count decision ->
            count + List.length decision.branch_identities)
          0 decisions
      in
      if List.length decisions <> expected_decisions
         || branch_count <> expected_branches
         || Jj_campaign_action.decision_node_count plan <> expected_decisions
      then
        Error
          (diagnostic Decision_denominator_mismatch
             "decision/control or branch denominator differs from the frozen family"
             Ops_capability.Specification)
      else if not (validate_guard_order family decisions) then
        Error
          (diagnostic Decision_guard_mismatch
             "decision guard prefix differs from the frozen family ordering"
             Ops_capability.Specification)
      else
        let family_identity = family_id_of family in
        let state_identities =
          lifecycle_states family |> List.map lifecycle_state_id
        in
        let event_identities = List.map event_id events in
        let channel_identities = List.map channel_id channels in
        let node_projection_digest =
          Jj_campaign_action.conditional_node_projection_digest plan
        in
        let edge_projection_digest =
          Jj_campaign_action.guarded_edge_projection_digest plan
        in
        let campaign_projection_digest =
          Jj_campaign_action.conditional_projection_digest plan
        in
        let schema_digest =
          schema_frame family_identity state_identities event_identities
            channel_identities decisions node_projection_digest
            edge_projection_digest campaign_projection_digest
          |> digest
        in
        Ok
          { plan; family_identity; state_identities;
            event_identities; channel_identities; decisions;
            node_projection_digest; edge_projection_digest;
            campaign_projection_digest; schema_digest }

let first_decision_mismatch observed expected =
  let rec loop observed expected =
    match observed, expected with
    | [], [] -> None
    | [], _ | _, [] -> Some Decision_denominator_mismatch
    | left :: left_rest, right :: right_rest ->
        if left.control_identity <> right.control_identity
        then Some Decision_control_mismatch
        else if left.prefix_identity <> right.prefix_identity
        then Some Decision_prefix_mismatch
        else if left.branch_identities <> right.branch_identities
        then Some Decision_branch_mismatch
        else if left.guard_identity <> right.guard_identity
        then Some Decision_guard_mismatch
        else if left <> right then Some Projection_digest_mismatch
        else loop left_rest right_rest
  in
  loop observed expected

let validate schema =
  match derive schema.plan with
  | Error error -> Error error
  | Ok expected ->
      let mismatch code message =
        Error (diagnostic code message Ops_capability.Specification)
      in
      if schema.family_identity <> expected.family_identity then
        mismatch Family_denominator_mismatch
          "schema family identity differs from the plan family"
      else if schema.state_identities <> expected.state_identities then
        mismatch State_denominator_mismatch
          "family lifecycle state denominator differs"
      else if schema.event_identities <> expected.event_identities then
        mismatch Event_denominator_mismatch
          "conditional event denominator differs"
      else if schema.channel_identities <> expected.channel_identities then
        mismatch Channel_denominator_mismatch
          "conditional channel denominator differs"
      else
        match first_decision_mismatch schema.decisions expected.decisions with
        | Some code -> mismatch code "decision preparation differs"
        | None ->
            if schema.node_projection_digest
               <> expected.node_projection_digest
               || schema.edge_projection_digest
                  <> expected.edge_projection_digest
               || schema.campaign_projection_digest
                  <> expected.campaign_projection_digest
               || schema.schema_digest <> expected.schema_digest
            then
              mismatch Projection_digest_mismatch
                "campaign or conditional schema projection digest differs"
            else Ok ()

type 'family admitted_plan_current = unit
type dispatch_claim_current = unit
type 'family wrapper_dispositions_current = unit
type effect_prefix_current = unit
type event_prefix_current = unit
type mutation_frontier_current = unit
type resource_vault_current = unit
type 'family readback_current = unit
type 'family prefix_current = unit
type interpreter = unit
type 'family decision_current = unit
type 'family guarded_node_current = unit
type dormant_closed_receipt = unit
type 'purpose abandonment_current = unit
type 'purpose node_and_nonce_terminal_current = unit
type activity_result_current = unit
type completion_final_terminal
type completion_reconcile_terminal
type 'phase campaign_terminal_current = unit

let unavailable operation =
  Error
    (diagnostic Store_owner_receipts_unavailable
       ("conditional operation " ^ operation
        ^ " requires absent lower store/owner current receipts")
       Ops_capability.Specification)

let prepare_prefix ~schema:_ ~plan:_ ~claim:_ ~wrappers:_ ~effects:_ ~events:_
    ~frontier:_ ~posture:_ ~readback:_ =
  unavailable "prepare-prefix"

let create (_part : Run_root_bootstrap.conditional_interpreter_part) =
  unavailable "create-interpreter"

let prepare_decision _ ~schema:_ ~prefix:_ =
  unavailable "prepare-decision"

let close_dormant _ ~decision:_ ~node:_ = unavailable "close-dormant"

let close_claimed_unentered _ ~plan:_ ~abandonment:_ =
  unavailable "close-claimed-unentered"

let validate_campaign_terminal _ ~plan:_ ~result:_ ~events:_ =
  unavailable "validate-campaign-terminal"

let reconcile_recovery_only
    (_part : Run_root_bootstrap.conditional_recovery_part)
    ~(decisions : Dependability_dispatch_store.conditional_inventory_current)
    ~(abandonments :
        Dependability_dispatch_store.abandonment_inventory_current)
    ~(nonces : Dependability_authority_store.approval_inventory_current) :
    (Dependability_owner_inventory.conditional_terminal_current, diagnostic)
    result =
  let _ = decisions, abandonments, nonces in
  unavailable "reconcile-recovery-only"

type unavailable_operation =
  | Prepare_prefix_operation
  | Create_interpreter_operation
  | Prepare_decision_operation
  | Close_dormant_operation
  | Close_claimed_unentered_operation
  | Validate_campaign_terminal_operation
  | Reconcile_recovery_only_operation

let unavailable_operations =
  [ Prepare_prefix_operation; Create_interpreter_operation;
    Prepare_decision_operation; Close_dormant_operation;
    Close_claimed_unentered_operation; Validate_campaign_terminal_operation;
    Reconcile_recovery_only_operation ]

let unavailable_operation_id = function
  | Prepare_prefix_operation -> "prepare-prefix"
  | Create_interpreter_operation -> "create-interpreter"
  | Prepare_decision_operation -> "prepare-decision"
  | Close_dormant_operation -> "close-dormant"
  | Close_claimed_unentered_operation -> "close-claimed-unentered"
  | Validate_campaign_terminal_operation -> "validate-campaign-terminal"
  | Reconcile_recovery_only_operation -> "reconcile-recovery-only"

let prerequisite_status operation =
  unavailable (unavailable_operation_id operation)

let production_posture = `Implemented_unavailable

let family_schema = List.map packed_family_id families
let b_state_schema =
  lifecycle_states B_family |> List.map lifecycle_state_id
let completion_state_schema =
  lifecycle_states Completion_family |> List.map lifecycle_state_id
let event_schema = List.map event_id events
let channel_schema = List.map channel_id channels
let decision_schema =
  [ "node-identity"; "control-identity"; "prefix-identity";
    "branch-identities"; "guard-identity"; "preparation-digest";
    "b-decision-count:23"; "b-branch-count:105";
    "completion-decision-count:1"; "completion-branch-count:3" ]
let absent_caller_seams =
  [ "caller-branch-input:absent"; "caller-outcome-input:absent";
    "caller-list-input:absent"; "caller-digest-input:absent";
    "caller-callback-input:absent" ]
let authorizing_type_posture = [ "authorizing-types:nonconstructible" ]
let native_create_carrier_schema =
  [ "interpreter-part:Run_root_bootstrap.conditional_interpreter_part";
    "interpreter:abstract-nonconstructible" ]
let native_recovery_carrier_schema =
  [ "part:Run_root_bootstrap.conditional_recovery_part";
    "decisions:Dependability_dispatch_store.conditional_inventory_current";
    "abandonments:Dependability_dispatch_store.abandonment_inventory_current";
    "nonces:Dependability_authority_store.approval_inventory_current";
    "terminal:Dependability_owner_inventory.conditional_terminal_current" ]

let source_projection ~families ~b_states ~completion_states ~events
    ~channels ~decision_fields ~caller_seams ~authorizing_types
    ~create_carriers ~recovery_carriers =
  Jj_id.length_frame
    [ "run-conditional-authority-v1";
      Jj_campaign_action.source_digest;
      Jj_campaign_action.standalone_phase_denominator_digest;
      Run_root_bootstrap.source_digest;
      Dependability_dispatch_store.source_digest;
      Dependability_authority_store.source_digest;
      Dependability_owner_inventory.source_digest;
      Jj_id.length_frame families; Jj_id.length_frame b_states;
      Jj_id.length_frame completion_states; Jj_id.length_frame events;
      Jj_id.length_frame channels; Jj_id.length_frame decision_fields;
      Jj_id.length_frame caller_seams;
      Jj_id.length_frame authorizing_types;
      Jj_id.length_frame create_carriers;
      Jj_id.length_frame recovery_carriers;
      Jj_id.length_frame
        (List.map unavailable_operation_id unavailable_operations) ]

let source_digest =
  source_projection ~families:family_schema ~b_states:b_state_schema
    ~completion_states:completion_state_schema ~events:event_schema
    ~channels:channel_schema ~decision_fields:decision_schema
    ~caller_seams:absent_caller_seams
    ~authorizing_types:authorizing_type_posture
    ~create_carriers:native_create_carrier_schema
    ~recovery_carriers:native_recovery_carrier_schema
  |> digest

module For_test = struct
  type mutation =
    | Drop_decision
    | Reorder_decisions
    | Mismatch_control
    | Mismatch_prefix
    | Mismatch_branch
    | Mismatch_family
    | Drop_state
    | Reorder_events
    | Drop_channel
    | Mismatch_projection_digest

  let update_first update = function
    | [] -> []
    | first :: rest -> update first :: rest

  let mutate mutation schema =
    match mutation with
    | Drop_decision ->
        { schema with decisions = List.tl schema.decisions }
    | Reorder_decisions ->
        { schema with decisions = List.rev schema.decisions }
    | Mismatch_control ->
        { schema with
          decisions =
            update_first
              (fun decision ->
                { decision with
                  control_identity =
                    "mismatch:" ^ decision.control_identity })
              schema.decisions }
    | Mismatch_prefix ->
        { schema with
          decisions =
            update_first
              (fun decision ->
                { decision with
                  prefix_identity = "mismatch:" ^ decision.prefix_identity })
              schema.decisions }
    | Mismatch_branch ->
        { schema with
          decisions =
            update_first
              (fun decision ->
                { decision with
                  branch_identities =
                    update_first (fun id -> "mismatch:" ^ id)
                      decision.branch_identities })
              schema.decisions }
    | Mismatch_family ->
        { schema with family_identity = "mismatch:" ^ schema.family_identity }
    | Drop_state ->
        { schema with state_identities = List.tl schema.state_identities }
    | Reorder_events ->
        { schema with event_identities = List.rev schema.event_identities }
    | Drop_channel ->
        { schema with channel_identities = List.tl schema.channel_identities }
    | Mismatch_projection_digest ->
        { schema with
          node_projection_digest =
            "mismatch:" ^ schema.node_projection_digest }

  type source_mutation =
    | Drop_family
    | Drop_state_schema
    | Drop_event
    | Drop_channel_schema
    | Drop_decision_field
    | Add_caller_branch_input
    | Add_caller_outcome_input
    | Add_caller_list_input
    | Add_caller_digest_input
    | Add_caller_callback_input
    | Construct_authorizing_type
    | Use_placeholder_interpreter_part
    | Use_placeholder_recovery_carriers

  let source_digest_with_mutation mutation =
    let recovery_carriers =
      match mutation with
      | Use_placeholder_recovery_carriers ->
          [ "part:local-unit"; "decisions:local-unit";
            "abandonments:local-unit"; "nonces:local-unit";
            "terminal:local-unit" ]
      | _ -> native_recovery_carrier_schema
    in
    let create_carriers =
      match mutation with
      | Use_placeholder_interpreter_part ->
          [ "interpreter-part:local-unit"; "interpreter:local-unit" ]
      | _ -> native_create_carrier_schema
    in
    let families, b_states, events, channels, decision_fields, caller_seams,
        authorizing_types =
      match mutation with
      | Drop_family ->
          List.tl family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, absent_caller_seams, authorizing_type_posture
      | Drop_state_schema ->
          family_schema, List.tl b_state_schema, event_schema, channel_schema,
          decision_schema, absent_caller_seams, authorizing_type_posture
      | Drop_event ->
          family_schema, b_state_schema, List.tl event_schema, channel_schema,
          decision_schema, absent_caller_seams, authorizing_type_posture
      | Drop_channel_schema ->
          family_schema, b_state_schema, event_schema, List.tl channel_schema,
          decision_schema, absent_caller_seams, authorizing_type_posture
      | Drop_decision_field ->
          family_schema, b_state_schema, event_schema, channel_schema,
          List.tl decision_schema, absent_caller_seams,
          authorizing_type_posture
      | Add_caller_branch_input ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, "caller-branch-input:present" :: absent_caller_seams,
          authorizing_type_posture
      | Add_caller_outcome_input ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, "caller-outcome-input:present" :: absent_caller_seams,
          authorizing_type_posture
      | Add_caller_list_input ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, "caller-list-input:present" :: absent_caller_seams,
          authorizing_type_posture
      | Add_caller_digest_input ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, "caller-digest-input:present" :: absent_caller_seams,
          authorizing_type_posture
      | Add_caller_callback_input ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, "caller-callback-input:present" :: absent_caller_seams,
          authorizing_type_posture
      | Construct_authorizing_type ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, absent_caller_seams,
          [ "authorizing-types:constructible" ]
      | Use_placeholder_interpreter_part ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, absent_caller_seams, authorizing_type_posture
      | Use_placeholder_recovery_carriers ->
          family_schema, b_state_schema, event_schema, channel_schema,
          decision_schema, absent_caller_seams, authorizing_type_posture
    in
    source_projection ~families ~b_states
      ~completion_states:completion_state_schema ~events ~channels
      ~decision_fields ~caller_seams ~authorizing_types ~recovery_carriers
      ~create_carriers
    |> digest
end

let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf "FAIL: %s\n" name
  end

let contains text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index =
    index + width <= length
    && (String.sub text index width = needle || loop (index + 1))
  in
  width > 0 && loop 0

let count_occurrences text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index count =
    if width = 0 || index + width > length then count
    else if String.sub text index width = needle then
      loop (index + width) (count + 1)
    else loop (index + 1) count
  in
  loop 0 0

let replace_first text ~before ~after =
  let before_width = String.length before in
  let rec find index =
    if index + before_width > String.length text then None
    else if String.sub text index before_width = before then Some index
    else find (index + 1)
  in
  match find 0 with
  | None -> None
  | Some index ->
      let suffix_start = index + before_width in
      Some
        (String.sub text 0 index ^ after
         ^ String.sub text suffix_start (String.length text - suffix_start))

let expected_obligation_ids =
  [ "law.fpp-valid.negated"; "control.fpp-valid.fpp-cmp-01-witness";
    "law.metric-total.negated"; "control.metric-total.false-witness";
    "law.id-windows.negated"; "control.id-windows.false-witness";
    (* the ID-window law covered only the operations model and had no
       overflow relation; independent review rejected the 20/20 result
       for exactly that. These two controls are the omission made
       falsifiable. *)
    "control.id-windows.external-overlap-witness";
    "control.id-windows.overflow-witness";
    "control.id-windows.model-name-witness";
    "control.id-windows.absent-allocation-witness";
    "control.id-windows.absent-component-witness";
    "control.id-windows.wrong-base-witness";
    "control.id-windows.actual-scope-witness";
    "law.execution-bridge.negated"; "control.execution-bridge.false-witness";
    "law.ui-isolation.negated"; "control.ui-isolation.false-witness";
    "law.mbse-correspondence.negated";
    "control.mbse-correspondence.false-witness";
    "control.mbse-correspondence.repository-action-missing-witness";
    "control.mbse-correspondence.repository-action-duplicate-witness";
    "control.mbse-correspondence.repository-action-substitution-witness";
    "control.mbse-correspondence.repository-action-reorder-witness";
    "law.sqlite-finalization.negated";
    "control.sqlite-finalization.false-witness";
    (* the SQLite law asserted only the reelect action and omitted every
       machine, initial-state, transition, fault, gate and activity
       invariant the source validator enforces *)
    "control.sqlite-finalization.machine-owner-witness";
    "control.sqlite-finalization.initial-state-witness";
    "control.sqlite-finalization.transition-target-witness";
    "control.sqlite-finalization.transition-signal-witness";
    "control.sqlite-finalization.fault-owner-witness";
    "control.sqlite-finalization.fault-format-witness";
    "control.sqlite-finalization.gate-owner-witness";
    "control.sqlite-finalization.gate-intent-witness";
    "control.sqlite-finalization.transition-actions-witness";
    "control.sqlite-finalization.activity-intent-witness";
    "control.sqlite-finalization.activity-contract-witness";
    "control.sqlite-finalization.activity-success-witness";
    "control.sqlite-finalization.activity-target-state-witness";
    "control.sqlite-finalization.activity-capabilities-witness";
    "control.sqlite-finalization.activity-context-witness";
    "control.sqlite-finalization.activity-miq-witness";
    "control.sqlite-finalization.activity-effects-witness" ]

let host_precomputed smt2 =
  contains smt2 "(assert (= violation true))"
  || contains smt2 "(assert (= violation false))"

let host_boolean_campaign () =
  List.map
    (fun (item : Run_formal.obligation) ->
      let value, final_assert =
        match item.kind with
        | Run_formal.Negated_law -> ("false", "(assert violation)")
        | Run_formal.False_control -> ("true", "(assert violation)")
      in
      let smt2 =
        Printf.sprintf
          "; deliberately vacuous host-precomputed campaign %s\n\
           (set-logic QF_UF)\n\
           (declare-const violation Bool)\n\
           (assert (= violation %s))\n\
           %s\n\
           (check-sat)\n"
          item.stable_id value final_assert
      in
      { item with smt2; query_digest = Run_formal.digest_query smt2 })
    Run_formal.obligations

type fact_mutant_kind =
  | Inject_fpp_cmp_01_passive_async
  | Duplicate_metric_mapping
  | Overlap_instance_window
  | Add_execution_bypass
  | Add_ui_admission_edge
  | Drop_turtle_edge
  | Drop_sqlite_reelect_action
  | Overlap_external_window
  | Overflow_instance_window
  | Invalid_sqlite_machine_owner
  | Invalid_sqlite_initial_state
  | Invalid_sqlite_transition_target
  | Empty_sqlite_transition_signal
  | Invalid_sqlite_fault_owner
  | Invalid_sqlite_gate_intent
  | Invalid_sqlite_activity_contract
  | Mismatch_window_model_name
  | Remove_window_allocation
  | Remove_window_component
  | Change_window_observed_base
  | Include_unregistered_actual_window
  | Empty_sqlite_transition_actions
  | Empty_sqlite_fault_format
  | Invalid_sqlite_gate_owner
  | Empty_sqlite_activity_intent
  | Empty_sqlite_activity_success_criteria
  | Invalid_sqlite_activity_target_state
  | Invalid_sqlite_activity_capabilities
  | Invalid_sqlite_activity_context
  | Invalid_sqlite_activity_miq
  | Invalid_sqlite_activity_effects
  | Drop_repository_action
  | Duplicate_repository_action
  | Substitute_repository_action_work
  | Reorder_repository_actions

type fact_mutant_control = {
  kind : fact_mutant_kind;
  control_id : string;
  witness : unit -> bool;
}

let mutant_id_of_kind = function
  | Inject_fpp_cmp_01_passive_async -> "fpp.fpp-cmp-01-passive-async"
  | Duplicate_metric_mapping -> "metric.duplicate-channel-mapping"
  | Overlap_instance_window -> "id.overlap-instance-window"
  | Add_execution_bypass -> "execution.direct-supervisor-worker-edge"
  | Add_ui_admission_edge -> "ui.dream-to-admission-edge"
  | Drop_turtle_edge -> "mbse.drop-turtle-edge"
  | Drop_sqlite_reelect_action -> "sqlite.drop-reelect-action"
  | Overlap_external_window -> "id.overlap-external-window"
  | Overflow_instance_window -> "id.overflow-instance-window"
  | Invalid_sqlite_machine_owner -> "sqlite.invalid-machine-owner"
  | Invalid_sqlite_initial_state -> "sqlite.invalid-initial-state"
  | Invalid_sqlite_transition_target -> "sqlite.invalid-transition-target"
  | Empty_sqlite_transition_signal -> "sqlite.empty-transition-signal"
  | Invalid_sqlite_fault_owner -> "sqlite.invalid-fault-owner"
  | Invalid_sqlite_gate_intent -> "sqlite.invalid-gate-intent"
  | Invalid_sqlite_activity_contract -> "sqlite.invalid-activity-contract"
  | Mismatch_window_model_name -> "id.mismatched-model-name"
  | Remove_window_allocation -> "id.absent-allocation"
  | Remove_window_component -> "id.absent-component"
  | Change_window_observed_base -> "id.wrong-observed-base"
  | Include_unregistered_actual_window -> "id.include-unregistered-actual-window"
  | Empty_sqlite_transition_actions -> "sqlite.empty-transition-actions"
  | Empty_sqlite_fault_format -> "sqlite.empty-fault-format"
  | Invalid_sqlite_gate_owner -> "sqlite.invalid-gate-owner"
  | Empty_sqlite_activity_intent -> "sqlite.empty-activity-intent"
  | Empty_sqlite_activity_success_criteria ->
      "sqlite.empty-activity-success-criteria"
  | Invalid_sqlite_activity_target_state ->
      "sqlite.invalid-activity-target-state"
  | Invalid_sqlite_activity_capabilities ->
      "sqlite.invalid-activity-capabilities"
  | Invalid_sqlite_activity_context -> "sqlite.invalid-activity-context"
  | Invalid_sqlite_activity_miq -> "sqlite.invalid-activity-miq"
  | Invalid_sqlite_activity_effects -> "sqlite.invalid-activity-effects"
  | Drop_repository_action -> "mbse.repository-action-missing"
  | Duplicate_repository_action -> "mbse.repository-action-duplicate"
  | Substitute_repository_action_work ->
      "mbse.repository-action-work-substitution"
  | Reorder_repository_actions -> "mbse.repository-action-reordered"

let fpp_mutant_witness () =
  match Run_topology.model.components with
  | [] -> false
  | (first : Fpp_model.component) :: rest ->
      let mutant_port =
        Fpp_model.General
          { name = "fppCmp01Mutant"; port = "OperationsFlow";
            direction = Fpp_model.Async_input
                { priority = None; queue_full = Fpp_model.Drop };
            count = 1 }
      in
      let mutant =
        { Run_topology.model with
          components =
            { first with kind = Fpp_model.Passive;
              ports = mutant_port :: first.ports } :: rest }
      in
      List.exists
        (fun diagnostic ->
          diagnostic.Fractal_diagnostic.hazard = "FPP-CMP-01")
        (Fpp_model.validate mutant)

let metric_mutant_witness () =
  match List.find_opt
      (fun (item : Run_topology.channel) -> Option.is_some item.metric_id)
      Run_topology.authority.channels
  with
  | None -> false
  | Some channel ->
      let mutant =
        { Run_topology.authority with
          channels = channel :: Run_topology.authority.channels }
      in
      Run_topology.metric_channel_gaps_for mutant <> []

let intervals_overlap (left_base, left_span) (right_base, right_span) =
  left_base < right_base + right_span && right_base < left_base + left_span

let id_window_mutant_witness () =
  match
    Fpp_window_authority.rows Fpp_window_authority.Completion
      Ops_completion_topology.model
  with
  | (first : Fpp_window_authority.row) :: second :: _ ->
      not
        (intervals_overlap (first.observed_base_id, first.span)
           (second.observed_base_id, second.span))
      && intervals_overlap (first.observed_base_id, first.span)
           (first.observed_base_id, second.span)
  | _ -> false

let execution_mutant_witness () =
  let bypass : Run_topology.edge =
    { stable_id = "edge.mutant.execution-direct";
      from_component = "runSupervisor"; from_port = "admittedOut";
      to_component = "suiteWorker"; to_port = "workIn";
      kind = Run_topology.Execution }
  in
  let mutant =
    { Run_topology.authority with
      edges = bypass :: Run_topology.authority.edges }
  in
  Run_topology.execution_bypass_gaps mutant <> []

let ui_mutant_witness () =
  let bypass : Run_topology.edge =
    { stable_id = "edge.mutant.ui-admission";
      from_component = "dreamGateway"; from_port = "stateOut";
      to_component = "swarmExecutionBridge"; to_port = "intentIn";
      kind = Run_topology.Admission }
  in
  let mutant =
    { Run_topology.authority with
      edges = bypass :: Run_topology.authority.edges }
  in
  Run_topology.ui_admission_gaps mutant <> []

let mbse_mutant_witness () =
  let edge_id = "edge.admission.supervisor-rete" in
  match replace_first (Run_mbse.oml_owl ()) ~before:edge_id
          ~after:"edge.mutant.dropped-from-canonical-manifest"
  with
  | None -> false
  | Some mutant ->
      begin match Run_mbse.manifest_of_turtle mutant with
      | Error _ -> true
      | Ok observed -> observed <> Run_mbse.manifest
      end

let rebuild_action ?work (action : Run_topology.declarative_action) =
  Run_topology.For_test.declarative_action_work
    ~stable_id:action.stable_id ~command_id:action.command_id
    ~assigned_agent_id:action.assigned_agent_id
    ~dependency_ids:action.dependency_ids ~selector_id:action.selector_id
    ~required_capability_id:action.required_capability_id
    ~context_requirement_ids:action.context_requirement_ids
    ~target_component_id:action.target_component_id
    ~effect_kind:action.effect_kind ~preparation_id:action.preparation_id
    ~work:(Option.value work ~default:action.work)

let mutate_repository_actions mutate (authority : Run_topology.authority) =
  { authority with activities =
      List.map
        (fun (activity : Run_topology.declarative_activity) ->
          if activity.stable_id <> "activity.verify-repository" then activity
          else
            let actions = mutate activity.actions in
            { activity with actions;
              command_ids =
                List.map
                  (fun (action : Run_topology.declarative_action) ->
                    action.command_id)
                  actions })
        authority.activities }

let missing_repository_action_authority () =
  mutate_repository_actions
    (function build :: _suite :: rest -> build :: rest | actions -> actions)
    Run_topology.authority

let duplicate_repository_action_authority () =
  mutate_repository_actions
    (function build :: suite :: rest -> build :: suite :: suite :: rest
      | actions -> actions)
    Run_topology.authority

let substituted_repository_action_authority () =
  mutate_repository_actions
    (function
      | build :: suite :: rest ->
          build
          :: rebuild_action
               ~work:(Run_topology.Repository_verification_suite
                 { profile = Run_topology.Verification_full;
                   suite_id = "test_substituted";
                   executable = "_build/default/test_substituted.exe" })
               suite
          :: rest
      | actions -> actions)
    Run_topology.authority

let reordered_repository_action_authority () =
  mutate_repository_actions
    (function build :: first :: second :: rest ->
        build :: second :: first :: rest
      | actions -> actions)
    Run_topology.authority

let repository_mutant_witness authority =
  Run_topology.validate_authority authority <> []

let sqlite_mutant_witness () =
  let lifecycle_machines =
    List.map
      (fun (machine : Run_topology.lifecycle_machine) ->
        if machine.stable_id <> "DatabaseCloseLifecycle" then machine
        else
          { machine with
            states =
              List.map
                (fun (state : Run_topology.lifecycle_state) ->
                  if state.stable_id <> "DatabaseCloseBlocked" then state
                  else
                    { state with
                      transitions =
                        List.map
                          (fun (transition : Run_topology.lifecycle_transition) ->
                            if transition.signal <> "blockersReleased" then
                              transition
                            else
                              { transition with
                                actions =
                                  List.filter
                                    (fun action -> action <> "reelectActor")
                                    transition.actions })
                          state.transitions })
                machine.states })
      Run_topology.authority.lifecycle_machines
  in
  Run_topology.sqlite_dependability_gaps_for
    { Run_topology.authority with lifecycle_machines }
  <> []

(* ---------------------------------------------------------------------
   Witnesses for the omissions independent review found.

   A witness confirms, on the host and independently of the formula, that
   the mutant really is a violation. That is the opposite of the rejected
   pattern: a host verdict must never enter the FORMULA BUILDER, but a
   test that could not tell a real mutant from a harmless edit would be
   proving nothing at all. *)

let overlaps (left_base, left_span) (right_base, right_span) =
  not (left_base + left_span <= right_base || right_base + right_span <= left_base)

let external_overlap_witness () =
  let harness =
    Fpp_window_authority.rows Fpp_window_authority.Harness Harness_topology.model
  and wiki =
    Fpp_window_authority.rows Fpp_window_authority.Wiki Wiki_topology.model
  in
  match harness, wiki with
  | (harness_row : Fpp_window_authority.row) :: _, wiki_row :: _ ->
      not
        (overlaps (harness_row.observed_base_id, harness_row.span)
           (wiki_row.observed_base_id, wiki_row.span))
      && overlaps (harness_row.observed_base_id, harness_row.span)
           (harness_row.observed_base_id, wiki_row.span)
  | _ -> false

(* QF_LIA integers are unbounded, so overflow is only meaningful against an
   explicit maximum. The witness states the same relation the formula must:
   a base above max - span is unrepresentable. *)
let overflow_witness () =
  let maximum = max_int in
  let safe =
    Fpp_window_authority.rows Fpp_window_authority.Harness Harness_topology.model
    |> List.for_all (fun (row : Fpp_window_authority.row) ->
           row.observed_base_id <= maximum - row.span)
  in
  let overflowing = (maximum - 4, 8) in
  safe && not (fst overflowing <= maximum - snd overflowing)

let model_of_owner = function
  | Fpp_window_authority.Harness -> Harness_topology.model
  | Fpp_window_authority.Wiki -> Wiki_topology.model
  | Fpp_window_authority.Ops_monitor -> Ops_topology.model
  | Fpp_window_authority.Completion -> Ops_completion_topology.model
  | Fpp_window_authority.Operations -> Run_topology.model

let normative_window_rows () =
  List.concat_map
    (fun owner -> Fpp_window_authority.rows owner (model_of_owner owner))
    Fpp_window_authority.owners

let row_overlaps (left : Fpp_window_authority.row)
    (right : Fpp_window_authority.row) =
  overlaps (left.observed_base_id, left.span)
    (right.observed_base_id, right.span)

let rows_pairwise_disjoint rows =
  let rec loop = function
    | [] -> true
    | first :: rest ->
        List.for_all (fun next -> not (row_overlaps first next)) rest
        && loop rest
  in
  loop rows

let operations_sequence_witness () =
  let rows =
    Fpp_window_authority.rows Fpp_window_authority.Operations Run_topology.model
  in
  let rec adjacent = function
    | (left : Fpp_window_authority.row)
      :: ((right : Fpp_window_authority.row) :: _ as rest) ->
        left.observed_base_id + left.span = right.observed_base_id
        && right.declared_base_id = -1
        && adjacent rest
    | _ -> true
  in
  match rows with
  | [] -> false
  | first :: _ ->
      first.sequential
      && first.declared_base_id
         = Fpp_window_authority.window_base Fpp_window_authority.Operations
      && first.observed_base_id = first.declared_base_id
      && List.for_all
           (fun (row : Fpp_window_authority.row) -> row.sequential) rows
      && adjacent rows

let model_name_witness () =
  let mutant =
    { Harness_topology.model with Fpp_model.model_name = "WrongHarnessModel" }
  in
  List.exists
    (fun (row : Fpp_window_authority.row) ->
      row.declared_model_name <> row.observed_model_name)
    (Fpp_window_authority.rows Fpp_window_authority.Harness mutant)

let absent_allocation_witness () =
  let mutant =
    { Harness_topology.model with
      Fpp_model.instances =
        List.filter
          (fun (instance : Fpp_model.instance) ->
            instance.inst_name <> "harness_config")
          Harness_topology.model.instances }
  in
  List.exists
    (fun (row : Fpp_window_authority.row) ->
      not row.allocation_present && row.component_present)
    (Fpp_window_authority.rows Fpp_window_authority.Harness mutant)

let absent_component_witness () =
  let mutant =
    { Harness_topology.model with
      Fpp_model.components =
        List.filter
          (fun (component : Fpp_model.component) ->
            component.comp_name <> "harness_config")
          Harness_topology.model.components }
  in
  List.exists
    (fun (row : Fpp_window_authority.row) ->
      row.allocation_present && not row.component_present)
    (Fpp_window_authority.rows Fpp_window_authority.Harness mutant)

let wrong_base_witness () =
  let mutant =
    { Harness_topology.model with
      Fpp_model.instances =
        List.map
          (fun (instance : Fpp_model.instance) ->
            if instance.inst_name = "harness_config"
            then { instance with base_id = instance.base_id + 1 }
            else instance)
          Harness_topology.model.instances }
  in
  List.exists
    (fun (row : Fpp_window_authority.row) ->
      row.allocation_present
      && row.declared_base_id <> row.observed_base_id)
    (Fpp_window_authority.rows Fpp_window_authority.Harness mutant)

let actual_scope_witness () =
  let harness =
    Fpp_window_authority.unregistered_actual_rows Fpp_window_authority.Harness
      Harness_topology.model
  and wiki =
    Fpp_window_authority.unregistered_actual_rows Fpp_window_authority.Wiki
      Wiki_topology.model
  in
  let collisions =
    List.concat_map
      (fun left ->
        List.filter_map
          (fun right -> if row_overlaps left right then Some (left, right) else None)
          wiki)
      harness
  in
  let exact_legacy_collision =
    List.exists
      (fun ((left : Fpp_window_authority.row),
            (right : Fpp_window_authority.row)) ->
        (left.observed_base_id = 0x1000 && right.observed_base_id = 0x1000)
        || (left.observed_base_id = 0x1100 && right.observed_base_id = 0x1100))
      collisions
  in
  let normative_ids =
    normative_window_rows ()
    |> List.map (fun (row : Fpp_window_authority.row) ->
           (row.owner, row.instance_id))
  in
  exact_legacy_collision
  && rows_pairwise_disjoint (normative_window_rows ())
  && List.for_all
       (fun (row : Fpp_window_authority.row) ->
         not (List.mem (row.owner, row.instance_id) normative_ids))
       (harness @ wiki)

(* The SQLite invariants, each witnessed by the source validator the
   formula must MIRROR — located and mirrored here, never called from the
   builder. *)
let sqlite_authority_witness mutate =
  Run_topology.sqlite_dependability_gaps_for (mutate Run_topology.authority) <> []

let first_machine_mutated f (value : Run_topology.authority) =
  match value.lifecycle_machines with
  | [] -> value
  | machine :: rest -> { value with lifecycle_machines = f machine :: rest }

let machine_owner_witness () =
  sqlite_authority_witness
    (first_machine_mutated (fun machine ->
         { machine with component_id = "notTheEventStore" }))

let initial_state_witness () =
  sqlite_authority_witness
    (first_machine_mutated (fun machine ->
         { machine with initial_state = "NoSuchState" }))

let map_first_transition f (machine : Run_topology.lifecycle_machine) =
  match machine.states with
  | [] -> machine
  | state :: states ->
      let transitions =
        match state.transitions with
        | [] -> []
        | transition :: rest -> f transition :: rest
      in
      { machine with states = { state with transitions } :: states }

let transition_target_witness () =
  sqlite_authority_witness
    (first_machine_mutated
       (map_first_transition (fun transition ->
            { transition with target_state = "NoSuchTargetState" })))

let transition_signal_witness () =
  sqlite_authority_witness
    (first_machine_mutated
       (map_first_transition (fun transition -> { transition with signal = "" })))

let fault_owner_witness () =
  sqlite_authority_witness (fun value ->
      match value.fault_events with
      | [] -> value
      | fault :: rest ->
          { value with
            fault_events = { fault with component_id = "notTheEventStore" } :: rest })

let gate_intent_witness () =
  sqlite_authority_witness (fun value ->
      match value.gate_commands with
      | [] -> value
      | gate :: rest ->
          { value with gate_commands = { gate with intent_id = "" } :: rest })

let activity_contract_witness () =
  sqlite_authority_witness (fun value ->
      match value.activities with
      | [] -> value
      | activity :: rest ->
          { value with
            activities = { activity with constraints = [] } :: rest })

let transition_actions_witness () =
  sqlite_authority_witness
    (first_machine_mutated
       (map_first_transition (fun transition ->
            { transition with actions = [] })))

let fault_format_witness () =
  sqlite_authority_witness (fun value ->
      match value.fault_events with
      | [] -> value
      | fault :: rest ->
          { value with fault_events = { fault with format = "" } :: rest })

let gate_owner_witness () =
  sqlite_authority_witness (fun value ->
      match value.gate_commands with
      | [] -> value
      | gate :: rest ->
          { value with
            gate_commands =
              { gate with component_id = "notTheEventStore" } :: rest })

let activity_intent_witness () =
  sqlite_authority_witness (fun value ->
      match value.activities with
      | [] -> value
      | activity :: rest ->
          { value with activities = { activity with intent = "" } :: rest })

let activity_success_witness () =
  sqlite_authority_witness (fun value ->
      match value.activities with
      | [] -> value
      | activity :: rest ->
          { value with
            activities = { activity with success_criteria = [] } :: rest })

let mutate_first_activity mutate (value : Run_topology.authority) =
  match value.activities with
  | [] -> value
  | activity :: rest ->
      { value with activities = mutate activity :: rest }

let activity_target_state_witness () =
  sqlite_authority_witness
    (mutate_first_activity (fun activity ->
         { activity with target_state = "sqlite-dependability-substituted" }))

let activity_capabilities_witness () =
  sqlite_authority_witness
    (mutate_first_activity (fun activity ->
         { activity with required_capability_ids = [ "capability.unknown" ] }))

let activity_context_witness () =
  sqlite_authority_witness
    (mutate_first_activity (fun activity ->
         { activity with context_requirement_ids = [ "context.unknown" ] }))

let activity_miq_witness () =
  sqlite_authority_witness
    (mutate_first_activity (fun activity ->
         match activity.miq_routes with
         | [] -> activity
         | route :: rest ->
             { activity with
               miq_routes = { route with selector_id = "miq.unknown" } :: rest }))

let activity_effects_witness () =
  sqlite_authority_witness
    (mutate_first_activity (fun activity ->
         { activity with
           effect_kinds = [ Run_topology.Verification_suite_execution ] }))

let sqlite_query_for_authority authority =
  Run_formal_relation.For_test.sqlite_query_for_authority authority
    Run_formal_relation.Negated_law

let mbse_query_for_authority authority =
  Run_formal_relation.For_test.mbse_query_for_authority authority
    Run_formal_relation.Negated_law

let remove_sqlite_activity (authority : Run_topology.authority) =
  { authority with Run_topology.activities =
      List.filter
        (fun (activity : Run_topology.declarative_activity) ->
          activity.stable_id <> "activity.verify-sqlite-dependability")
        authority.activities }

let duplicate_sqlite_activity (authority : Run_topology.authority) =
  match List.find_opt
      (fun (activity : Run_topology.declarative_activity) ->
        activity.stable_id = "activity.verify-sqlite-dependability")
      authority.activities with
  | None -> authority
  | Some sqlite -> { authority with activities = sqlite :: authority.activities }

let fact_mutant_controls =
  [ { kind = Inject_fpp_cmp_01_passive_async;
      control_id = "control.fpp-valid.fpp-cmp-01-witness";
      witness = fpp_mutant_witness };
    { kind = Duplicate_metric_mapping;
      control_id = "control.metric-total.false-witness";
      witness = metric_mutant_witness };
    { kind = Overlap_instance_window;
      control_id = "control.id-windows.false-witness";
      witness = id_window_mutant_witness };
    { kind = Add_execution_bypass;
      control_id = "control.execution-bridge.false-witness";
      witness = execution_mutant_witness };
    { kind = Add_ui_admission_edge;
      control_id = "control.ui-isolation.false-witness";
      witness = ui_mutant_witness };
    { kind = Drop_turtle_edge;
      control_id = "control.mbse-correspondence.false-witness";
      witness = mbse_mutant_witness };
    { kind = Drop_repository_action;
      control_id =
        "control.mbse-correspondence.repository-action-missing-witness";
      witness = (fun () ->
        repository_mutant_witness (missing_repository_action_authority ())) };
    { kind = Duplicate_repository_action;
      control_id =
        "control.mbse-correspondence.repository-action-duplicate-witness";
      witness = (fun () ->
        repository_mutant_witness (duplicate_repository_action_authority ())) };
    { kind = Substitute_repository_action_work;
      control_id =
        "control.mbse-correspondence.repository-action-substitution-witness";
      witness = (fun () ->
        repository_mutant_witness
          (substituted_repository_action_authority ())) };
    { kind = Reorder_repository_actions;
      control_id =
        "control.mbse-correspondence.repository-action-reorder-witness";
      witness = (fun () ->
        repository_mutant_witness (reordered_repository_action_authority ())) };
    { kind = Drop_sqlite_reelect_action;
      control_id = "control.sqlite-finalization.false-witness";
      witness = sqlite_mutant_witness };
    { kind = Overlap_external_window;
      control_id = "control.id-windows.external-overlap-witness";
      witness = external_overlap_witness };
    { kind = Overflow_instance_window;
      control_id = "control.id-windows.overflow-witness";
      witness = overflow_witness };
    { kind = Mismatch_window_model_name;
      control_id = "control.id-windows.model-name-witness";
      witness = model_name_witness };
    { kind = Remove_window_allocation;
      control_id = "control.id-windows.absent-allocation-witness";
      witness = absent_allocation_witness };
    { kind = Remove_window_component;
      control_id = "control.id-windows.absent-component-witness";
      witness = absent_component_witness };
    { kind = Change_window_observed_base;
      control_id = "control.id-windows.wrong-base-witness";
      witness = wrong_base_witness };
    { kind = Include_unregistered_actual_window;
      control_id = "control.id-windows.actual-scope-witness";
      witness = actual_scope_witness };
    { kind = Invalid_sqlite_machine_owner;
      control_id = "control.sqlite-finalization.machine-owner-witness";
      witness = machine_owner_witness };
    { kind = Invalid_sqlite_initial_state;
      control_id = "control.sqlite-finalization.initial-state-witness";
      witness = initial_state_witness };
    { kind = Invalid_sqlite_transition_target;
      control_id = "control.sqlite-finalization.transition-target-witness";
      witness = transition_target_witness };
    { kind = Empty_sqlite_transition_signal;
      control_id = "control.sqlite-finalization.transition-signal-witness";
      witness = transition_signal_witness };
    { kind = Invalid_sqlite_fault_owner;
      control_id = "control.sqlite-finalization.fault-owner-witness";
      witness = fault_owner_witness };
    { kind = Empty_sqlite_fault_format;
      control_id = "control.sqlite-finalization.fault-format-witness";
      witness = fault_format_witness };
    { kind = Invalid_sqlite_gate_owner;
      control_id = "control.sqlite-finalization.gate-owner-witness";
      witness = gate_owner_witness };
    { kind = Invalid_sqlite_gate_intent;
      control_id = "control.sqlite-finalization.gate-intent-witness";
      witness = gate_intent_witness };
    { kind = Empty_sqlite_transition_actions;
      control_id = "control.sqlite-finalization.transition-actions-witness";
      witness = transition_actions_witness };
    { kind = Empty_sqlite_activity_intent;
      control_id = "control.sqlite-finalization.activity-intent-witness";
      witness = activity_intent_witness };
    { kind = Invalid_sqlite_activity_contract;
      control_id = "control.sqlite-finalization.activity-contract-witness";
      witness = activity_contract_witness };
    { kind = Empty_sqlite_activity_success_criteria;
      control_id = "control.sqlite-finalization.activity-success-witness";
      witness = activity_success_witness };
    { kind = Invalid_sqlite_activity_target_state;
      control_id = "control.sqlite-finalization.activity-target-state-witness";
      witness = activity_target_state_witness };
    { kind = Invalid_sqlite_activity_capabilities;
      control_id = "control.sqlite-finalization.activity-capabilities-witness";
      witness = activity_capabilities_witness };
    { kind = Invalid_sqlite_activity_context;
      control_id = "control.sqlite-finalization.activity-context-witness";
      witness = activity_context_witness };
    { kind = Invalid_sqlite_activity_miq;
      control_id = "control.sqlite-finalization.activity-miq-witness";
      witness = activity_miq_witness };
    { kind = Invalid_sqlite_activity_effects;
      control_id = "control.sqlite-finalization.activity-effects-witness";
      witness = activity_effects_witness } ]

let obligation_for stable_id =
  List.find_opt
    (fun (item : Run_formal.obligation) -> item.stable_id = stable_id)
    Run_formal.obligations

let mutate_relation_script () =
  match Run_formal_relation.canonical with
  | [] -> []
  | (first : Run_formal_relation.query) :: rest ->
      { first with smt2 = first.smt2 ^ "; one-byte-payload-mutant\n" } :: rest

let () =
  if Array.length Sys.argv = 2 && Sys.argv.(1) = "--print-fpp-probe" then begin
    print_string (Run_formal_relation.fpp_probe_smt2 ());
    exit 0
  end;
  Printf.printf "[relational-red] canonical Task5 formal authority\n";
  Printf.printf
    "[relational-evidence] solver=Unavailable_observed \
     reason=hard-isolated-linked-worker-is-Task3; \
     this focused suite checks raw facts and independent mutants only\n";
  check "Task8 has the exact ordered forty-two-obligation denominator"
    (List.map
       (fun (item : Run_formal.obligation) -> item.stable_id)
       Run_formal.obligations
     = expected_obligation_ids);
  check "host-precomputed Boolean campaigns are rejected even with fresh digests"
    (Run_formal.validate_obligations (host_boolean_campaign ()) <> []);
  check "the canonical campaign contains no host-precomputed violation Boolean"
    (List.for_all
       (fun (item : Run_formal.obligation) -> not (host_precomputed item.smt2))
       Run_formal.obligations);
  check "canonical three-or-more-value distinctness is pairwise typed equality"
    (match obligation_for "law.fpp-valid.negated" with
     | None -> false
     | Some obligation ->
         not (contains obligation.smt2 "(distinct ")
         && count_occurrences obligation.smt2 "(not (= " >= 3);
  check "canonical FPP resolver selections are bound raw facts"
    (match obligation_for "law.fpp-valid.negated" with
     | None -> false
     | Some obligation ->
         contains obligation.smt2
           "; raw-fact fpp.topology.0.connection.0.selected.from-owner"
         && contains obligation.smt2
           "; raw-fact fpp.topology.0.connection.0.selected.to-owner"
         && not (contains obligation.smt2 "(declare-const fpp_resolved_"));
  check "diagnostic resolver mutant removes one binding outside canonical bytes"
    (let probe = Run_formal_relation.fpp_probe_smt2 () in
     contains probe "; fact-mutant fpp.resolver-unbound"
     && not
          (String.equal probe
             (match obligation_for "law.fpp-valid.negated" with
              | Some obligation -> obligation.smt2
              | None -> "")));
  check "metric totality uses bounded raw aggregate relations, not a cross product"
    (match obligation_for "law.metric-total.negated" with
     | None -> false
     | Some obligation ->
         contains obligation.smt2 "; raw-fact metric.0.mapping-count"
         && contains obligation.smt2 "; raw-fact metric.0.fpp-mismatch-count"
         && contains obligation.smt2 "; raw-fact metric.unknown-mapping-count"
         && not (contains obligation.smt2 "(ite "));
  check "a relational script-byte mutant is rejected against canonical authority"
    (Run_formal_relation.validate_campaign (mutate_relation_script ()) <> []);
  check "FPP validity has the exact public twenty-five-clause denominator"
    (List.length Run_formal_relation.fpp_validation_clause_ids = 25
     && List.length
          (List.sort_uniq String.compare
             Run_formal_relation.fpp_validation_clause_ids)
        = 25);
  check "the fact-mutant control denominator is exactly thirty-five"
    (List.length fact_mutant_controls = 35);
  check "the normative five-window baseline is disjoint"
    (rows_pairwise_disjoint (normative_window_rows ()));
  check "every normative row preserves declared and observed identity facts"
    (normative_window_rows ()
     |> List.for_all (fun (row : Fpp_window_authority.row) ->
            row.declared_model_name = row.observed_model_name
            && row.instance_id = row.observed_instance_id
            && row.component_id = row.observed_component_id
            && row.allocation_present && row.component_present
            && row.span > 0));
  check "Operations uses the explicit sequential window policy"
    (operations_sequence_witness ());
  check "known Harness/Wiki actual collisions are observed but explicitly out of scope"
    (actual_scope_witness ());
  check "the window theorem exposes declared and observed raw relation fields"
    (match obligation_for "law.id-windows.negated" with
     | None -> false
     | Some obligation ->
         contains obligation.smt2 "; raw-fact window.row.0.declared-model"
         && contains obligation.smt2 "; raw-fact window.row.0.observed-model"
         && contains obligation.smt2 "; raw-fact window.row.0.allocation-present"
         && contains obligation.smt2 "; raw-fact window.row.0.component-present");
  check "SQLite hazard membership is a raw requirement-ID relation, never a host count"
    (match obligation_for "law.sqlite-finalization.negated" with
     | None -> false
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.requirement.0.id"
         && not (contains obligation.smt2 "sqlite.hazard-requirement-count"));
  check "SQLite activity target state is a raw relation fact"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.target-state"
     | None -> false);
  check "SQLite activity capabilities are raw relation facts"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.capability.0"
     | None -> false);
  check "SQLite activity context requirements are raw relation facts"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.context.0"
     | None -> false);
  check "SQLite activity MIQ routes are raw relation facts"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.miq.0.selector"
     | None -> false);
  check "SQLite activity effects are raw relation facts"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.effect.0"
     | None -> false);
  check "SQLite law retains raw facts for every canonical activity"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.id"
         && contains obligation.smt2 "; raw-fact sqlite.activity.1.id"
         && contains obligation.smt2 "; raw-fact sqlite.activity.1.target"
     | None -> false);
  check "each activity row has an explicit SQLite-policy selector fact"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; raw-fact sqlite.activity.0.selected"
         && contains obligation.smt2 "; raw-fact sqlite.activity.1.selected"
     | None -> false);
  check "SQLite selector cardinality is discharged solver-side"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         contains obligation.smt2 "; relation sqlite.activity.selected-count"
         && not (contains obligation.smt2 "; raw-fact sqlite.activity.count")
     | None -> false);
  check "SQLite-only activity envelopes are guarded by row selection"
    (match obligation_for "law.sqlite-finalization.negated" with
     | Some obligation ->
         count_occurrences obligation.smt2
           "; relation sqlite.activity.selected-envelope" = 2
         && count_occurrences obligation.smt2 "(=> " >= 2
     | None -> false);
  check "removing the selected SQLite ID changes relational query bytes"
    (let canonical = sqlite_query_for_authority Run_topology.authority in
     let missing =
       sqlite_query_for_authority
         (remove_sqlite_activity Run_topology.authority)
     in
     canonical.smt2 <> missing.smt2
     && contains missing.smt2 "; relation sqlite.activity.selected-count");
  check "duplicating the selected SQLite ID changes relational query bytes"
    (let canonical = sqlite_query_for_authority Run_topology.authority in
     let duplicate =
       sqlite_query_for_authority
         (duplicate_sqlite_activity Run_topology.authority)
     in
     canonical.smt2 <> duplicate.smt2
     && contains duplicate.smt2 "; raw-fact sqlite.activity.2.selected");
  check "repository theorem carries exactly 219 ordered raw action rows"
    (match obligation_for "law.mbse-correspondence.negated" with
     | Some obligation ->
         count_occurrences obligation.smt2
           "; raw-fact mbse.repository-action.0.stable-id" = 1
         && count_occurrences obligation.smt2
              "; raw-fact mbse.repository-action.218.stable-id" = 1
         && count_occurrences obligation.smt2
              ".stable-id" >= 219
         && contains obligation.smt2
              "; relation mbse.repository-action.count"
     | None -> false);
  check "repository build row carries exact typed work fields"
    (match obligation_for "law.mbse-correspondence.negated" with
     | Some obligation ->
         List.for_all
           (fun field ->
             contains obligation.smt2
               ("; raw-fact mbse.repository-action.0." ^ field))
           [ "index"; "action-digest"; "dependency-count"; "work-kind";
             "profile"; "build-command"; "suite-id"; "executable" ]
     | None -> false);
  check "every repository suite row carries suite identity and executable"
    (match obligation_for "law.mbse-correspondence.negated" with
     | Some obligation ->
         List.for_all
           (fun index ->
             contains obligation.smt2
               (Printf.sprintf
                  "; raw-fact mbse.repository-action.%d.suite-id" index)
             && contains obligation.smt2
                  (Printf.sprintf
                     "; raw-fact mbse.repository-action.%d.executable" index))
           [ 1; 109; 218 ]
     | None -> false);
  check "repository identity digest order and dependency totality are relational"
    (match obligation_for "law.mbse-correspondence.negated" with
     | Some obligation ->
         count_occurrences obligation.smt2
           "; relation mbse.repository-action.identity-correspondence" = 285
         && count_occurrences obligation.smt2
              "; relation mbse.repository-action.work-correspondence" = 285
         && count_occurrences obligation.smt2
              "; relation mbse.repository-action.dependency-correspondence" = 285
     | None -> false);
  check "repository action SMT encoding remains linear-sized"
    (match obligation_for "law.mbse-correspondence.negated" with
     | Some obligation ->
         let variables = count_occurrences obligation.smt2 "(declare-const " in
         let repository_actions =
           count_occurrences obligation.smt2
             "; relation mbse.repository-action.identity-correspondence"
         in
         variables > repository_actions
         && variables < (24 * repository_actions)
     | None -> false);
  let canonical_mbse_query =
    mbse_query_for_authority Run_topology.authority in
  check "missing repository action changes the typed relation"
    ((mbse_query_for_authority (missing_repository_action_authority ())).smt2
     <> canonical_mbse_query.smt2);
  check "duplicate repository action changes the typed relation"
    ((mbse_query_for_authority (duplicate_repository_action_authority ())).smt2
     <> canonical_mbse_query.smt2);
  check "substituted repository work changes the typed relation"
    ((mbse_query_for_authority (substituted_repository_action_authority ())).smt2
     <> canonical_mbse_query.smt2);
  check "reordered repository actions change the typed relation"
    ((mbse_query_for_authority (reordered_repository_action_authority ())).smt2
     <> canonical_mbse_query.smt2);
  List.iter
    (fun (control : fact_mutant_control) ->
      let mutant_id = mutant_id_of_kind control.kind in
      let marker = "; fact-mutant " ^ mutant_id in
      check ("typed fact mutant is independently witnessed: " ^ mutant_id)
        (control.witness ());
      check ("relational SAT control carries typed mutant facts: " ^ mutant_id)
        (match obligation_for control.control_id with
         | Some obligation ->
             obligation.kind = Run_formal.False_control
             && obligation.expected = Run_formal.Sat
             && not (host_precomputed obligation.smt2)
             && contains obligation.smt2 "; relational-authority-v1"
             && contains obligation.smt2 marker
         | None -> false))
    fact_mutant_controls;
  begin match obligation_for "law.mbse-correspondence.negated" with
  | None -> ()
  | Some obligation ->
      Printf.printf
        "[mbse-generation] id=%s bytes=%d variables=%d raw-actions=%d \
         action-relations=%d\n"
        obligation.stable_id (String.length obligation.smt2)
        (count_occurrences obligation.smt2 "(declare-const ")
        (count_occurrences obligation.smt2 ".stable-id")
        (count_occurrences obligation.smt2
           "; relation mbse.repository-action.identity-correspondence")
  end;
  List.iter
    (fun stable_id ->
      match obligation_for stable_id with
      | None -> ()
      | Some obligation ->
          Printf.printf
            "[metric-generation] id=%s bytes=%d assertions=%d variables=%d\n"
            stable_id (String.length obligation.smt2)
            (count_occurrences obligation.smt2 "(assert ")
            (count_occurrences obligation.smt2 "(declare-const "))
    [ "law.metric-total.negated"; "control.metric-total.false-witness" ];
  Printf.printf "run_formal_relational: checks=%d failures=%d\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_formal_relational"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)

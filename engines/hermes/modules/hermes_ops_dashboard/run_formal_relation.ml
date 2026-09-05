type law =
  | Fpp_valid
  | Metric_total
  | Id_windows
  | Execution_bridge
  | Ui_isolation
  | Mbse_correspondence
  | Sqlite_dependability

type fact_mutant =
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

type polarity = Negated_law | Fact_mutant_control of fact_mutant

type query = { stable_id : string; requirement_id : string; statement : string;
  law : law; polarity : polarity; smt2 : string; facts_digest : string;
  relation_digest : string }

let law_id = function
  | Fpp_valid -> "fpp-valid"
  | Metric_total -> "metric-total"
  | Id_windows -> "id-windows"
  | Execution_bridge -> "execution-bridge"
  | Ui_isolation -> "ui-isolation"
  | Mbse_correspondence -> "mbse-correspondence"
  | Sqlite_dependability -> "sqlite-finalization"

let mutant_id = function
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

let digest value =
  value |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let frame value = string_of_int (String.length value) ^ ":" ^ value
let digest_fields tag values = digest (String.concat "" (List.map frame (tag :: values)))

let smt_int value =
  if value < 0 then Printf.sprintf "(- %d)" (-value) else string_of_int value

let and_ = function
  | [] -> "true"
  | [ value ] -> value
  | values -> "(and " ^ String.concat " " values ^ ")"

let or_ = function
  | [] -> "false"
  | [ value ] -> value
  | values -> "(or " ^ String.concat " " values ^ ")"

let not_ value = "(not " ^ value ^ ")"
let eq left right = "(= " ^ left ^ " " ^ right ^ ")"
let le left right = "(<= " ^ left ^ " " ^ right ^ ")"
let lt left right = "(< " ^ left ^ " " ^ right ^ ")"
let implies left right = "(=> " ^ left ^ " " ^ right ^ ")"

let pairwise values predicate =
  let rec loop = function
    | [] -> []
    | first :: rest -> List.map (predicate first) rest @ loop rest
  in
  loop values

(* Smtml's SMT-LIB parser represents [distinct] as an unresolved application,
   whereas equality has a fully typed relational carrier.  Lower distinctness
   at the canonical query authority so linked Smtml/Z3 and the independent CLI
   execute the same bytes. *)
let distinct values =
  pairwise values (fun left right -> not_ (eq left right)) |> and_

type builder = {
  mutable next_fact : int;
  mutable next_symbol : int;
  symbols : (string, int) Hashtbl.t;
  mutable lines_rev : string list;
  mutable material_rev : string list;
}

let create_builder () =
  { next_fact = 0; next_symbol = 1; symbols = Hashtbl.create 256;
    lines_rev = []; material_rev = [] }

let add_line builder line = builder.lines_rev <- line :: builder.lines_rev

let add_material builder value =
  builder.material_rev <- value :: builder.material_rev

let intern builder value =
  match Hashtbl.find_opt builder.symbols value with
  | Some id -> id
  | None ->
      let id = builder.next_symbol in
      builder.next_symbol <- id + 1;
      Hashtbl.add builder.symbols value id;
      add_material builder (Printf.sprintf "symbol|%d|%s" id value);
      id

let add_int builder label value =
  let variable = Printf.sprintf "f%d" builder.next_fact in
  builder.next_fact <- builder.next_fact + 1;
  add_line builder ("; raw-fact " ^ label);
  add_line builder (Printf.sprintf "(declare-const %s Int)" variable);
  add_line builder
    (Printf.sprintf "(assert (= %s %s))" variable (smt_int value));
  add_material builder (Printf.sprintf "int|%s|%d" label value);
  variable

let add_bool builder label value =
  let variable = Printf.sprintf "f%d" builder.next_fact in
  builder.next_fact <- builder.next_fact + 1;
  add_line builder ("; raw-fact " ^ label);
  add_line builder (Printf.sprintf "(declare-const %s Bool)" variable);
  add_line builder
    (Printf.sprintf "(assert (= %s %s))" variable
       (if value then "true" else "false"));
  add_material builder (Printf.sprintf "bool|%s|%b" label value);
  variable

let add_relation builder label expression =
  let variable = Printf.sprintf "r%d" builder.next_fact in
  builder.next_fact <- builder.next_fact + 1;
  add_line builder ("; relation " ^ label);
  add_line builder (Printf.sprintf "(declare-const %s Bool)" variable);
  add_line builder
    (Printf.sprintf "(assert (= %s %s))" variable expression);
  variable

let add_string builder label value =
  let variable = add_int builder label (intern builder value) in
  let length = add_int builder (label ^ ".length") (String.length value) in
  (variable, length)

let membership value candidates =
  or_ (List.map (fun candidate -> eq value candidate) candidates)

let bool_sum conditions =
  match conditions with
  | [] -> "0"
  | _ ->
      "(+ "
      ^ String.concat " "
          (List.map (fun condition -> "(ite " ^ condition ^ " 1 0)") conditions)
      ^ ")"

let make_query ~stable_id ~requirement_id ~statement ~law ~polarity builder
    violation =
  let lines = List.rev builder.lines_rev in
  let facts_material = List.rev builder.material_rev in
  let facts_digest = digest_fields "run-formal-facts-v1" facts_material in
  let marker =
    match polarity with
    | Negated_law -> "none"
    | Fact_mutant_control mutant -> mutant_id mutant
  in
  let relation_digest =
    digest_fields "run-formal-relation-v1"
      [ Run_topology.source_digest; law_id law; marker; facts_digest;
        String.concat "\n" lines; violation ]
  in
  let smt2 =
    String.concat "\n"
      ([ "; relational-authority-v1";
         "; law " ^ law_id law;
         "; fact-mutant " ^ marker;
         "; topology-digest " ^ Run_topology.source_digest;
         "; facts-digest " ^ facts_digest;
         "; relation-digest " ^ relation_digest;
         "(set-logic QF_LIA)" ]
       @ lines @ [ "(assert " ^ violation ^ ")"; "(check-sat)"; "" ])
  in
  { stable_id; requirement_id; statement; law; polarity; smt2; facts_digest;
    relation_digest }

let fpp_cmp_01_mutant (model : Fpp_model.model) =
  match model.components with
  | [] -> model
  | (first : Fpp_model.component) :: rest ->
      let mutant_port =
        Fpp_model.General
          { name = "fppCmp01Mutant"; port = "OperationsFlow";
            direction = Fpp_model.Async_input
                { priority = None; queue_full = Fpp_model.Drop };
            count = 1 }
      in
      { model with
        components =
          { first with kind = Fpp_model.Passive;
            ports = mutant_port :: first.ports } :: rest }

let fpp_machine_name = function
  | Fpp_model.External_machine { machine_name }
  | Fpp_model.Internal_machine { machine_name; _ } -> machine_name

let fpp_type_name = function
  | Fpp_model.Abstract { name }
  | Fpp_model.Alias { name; _ }
  | Fpp_model.Array_t { name; _ }
  | Fpp_model.Enum_t { name; _ }
  | Fpp_model.Struct_t { name; _ } -> name

let fpp_named_type = function
  | Fpp_model.Named name -> Some name
  | Fpp_model.Prim _ -> None

let fpp_special_shape = function
  | Fpp_model.Command_recv -> ("cmdIn", false, 0)
  | Fpp_model.Command_reg -> ("cmdRegOut", true, 1)
  | Fpp_model.Command_resp -> ("cmdResponseOut", true, 2)
  | Fpp_model.Event_p -> ("logOut", true, 3)
  | Fpp_model.Text_event_p -> ("logTextOut", true, 4)
  | Fpp_model.Telemetry_p -> ("tlmOut", true, 5)
  | Fpp_model.Time_get -> ("timeGetOut", true, 6)
  | Fpp_model.Param_get_p -> ("prmGetOut", true, 7)
  | Fpp_model.Param_set_p -> ("prmSetOut", true, 8)
  | Fpp_model.Product_get_p -> ("productGetOut", true, 9)
  | Fpp_model.Product_request_p -> ("productRequestOut", true, 10)
  | Fpp_model.Product_recv_p -> ("productRecvIn", false, 11)
  | Fpp_model.Product_send_p -> ("productSendOut", true, 12)

type fpp_endpoint_fact = { endpoint_instance : string; endpoint_port : string;
  endpoint_index_present : string; endpoint_index : string }

type fpp_connection_fact = { from_endpoint : fpp_endpoint_fact;
  to_endpoint : fpp_endpoint_fact; raw_connection : Fpp_model.connection }

let fpp_resolver_probe = ref None

let fpp_validation_clause_ids =
  [ "FPP-NAME-01"; "FPP-TYPE-01"; "FPP-TYPE-02";
    "FPP-CMP-01"; "FPP-CMP-02"; "FPP-CMP-03"; "FPP-CMP-04";
    "FPP-CMP-05"; "FPP-CMP-06"; "FPP-CMP-07"; "FPP-CMP-08";
    "FPP-CMP-09"; "FPP-CMP-10"; "FPP-SM-01"; "FPP-SM-02";
    "FPP-SM-03"; "FPP-INST-01"; "FPP-INST-02"; "FPP-INST-03";
    "FPP-TOPO-01"; "FPP-TOPO-02"; "FPP-TOPO-03"; "FPP-TOPO-04";
    "FPP-TOPO-05"; "FPP-TOPO-06" ]

let fpp_query polarity =
  let model =
    match polarity with
    | Fact_mutant_control Inject_fpp_cmp_01_passive_async ->
        fpp_cmp_01_mutant Run_topology.model
    | _ -> Run_topology.model
  in
  let builder = create_builder () in
  let first_resolver_carrier = ref None in
  let string_facts label values =
    List.mapi
      (fun index value ->
        fst (add_string builder (Printf.sprintf "%s.%d" label index) value))
      values
  in
  let int_facts label values =
    List.mapi
      (fun index value ->
        add_int builder (Printf.sprintf "%s.%d" label index) value)
      values
  in
  let optional_int label = function
    | None -> (add_int builder (label ^ ".present") 0,
               add_int builder (label ^ ".value") 0)
    | Some value -> (add_int builder (label ^ ".present") 1,
                     add_int builder (label ^ ".value") value)
  in
  let model_name, model_name_length =
    add_string builder "fpp.model.name" model.Fpp_model.model_name in
  let component_count =
    add_int builder "fpp.component.count" (List.length model.components) in
  let instance_count =
    add_int builder "fpp.instance.count" (List.length model.instances) in
  let topology_count =
    add_int builder "fpp.topology.count" (List.length model.topologies) in
  let component_names =
    List.mapi
      (fun index (component : Fpp_model.component) ->
        let name, name_length =
          add_string builder (Printf.sprintf "fpp.component.%d.name" index)
            component.comp_name
        in
        let kind =
          add_int builder (Printf.sprintf "fpp.component.%d.kind" index)
            (match component.kind with
             | Fpp_model.Passive -> 0
             | Fpp_model.Queued -> 1
             | Fpp_model.Active -> 2)
        in
        let async_elements =
          List.fold_left
            (fun count -> function
              | Fpp_model.General
                  { direction = Fpp_model.Async_input _; _ } -> count + 1
              | _ -> count)
            0 component.ports
          + List.fold_left
              (fun count (command : Fpp_model.command) ->
                match command.cmd_kind with
                | Fpp_model.Async_cmd _ -> count + 1
                | _ -> count)
              0 component.commands
          + List.length component.internal_ports + List.length component.machines
        in
        let async_count =
          add_int builder (Printf.sprintf "fpp.component.%d.async-count" index)
            async_elements
        in
        let constraints =
          [ lt "0" name_length;
            implies (eq kind "0") (eq async_count "0");
            implies (or_ [ eq kind "1"; eq kind "2" ])
              (lt "0" async_count) ]
        in
        (name, kind, constraints))
      model.components
  in
  let port_rows =
    List.concat_map
      (fun (component : Fpp_model.component) ->
        List.filter_map
          (function
            | Fpp_model.Special _ -> None
            | Fpp_model.General { name; port; direction; count } ->
                Some (component.comp_name, name, port, direction, count))
          component.ports)
      model.components
  in
  let port_facts =
    List.mapi
      (fun index (owner, name, port, raw_direction, raw_count) ->
        let owner_id, _ =
          add_string builder (Printf.sprintf "fpp.port.%d.owner" index) owner in
        let port_name, port_name_length =
          add_string builder (Printf.sprintf "fpp.port.%d.name" index) name in
        let port_type, _ =
          add_string builder (Printf.sprintf "fpp.port.%d.type" index) port in
        let count = add_int builder (Printf.sprintf "fpp.port.%d.count" index) raw_count in
        let direction =
          add_int builder (Printf.sprintf "fpp.port.%d.direction" index)
            (match raw_direction with
             | Fpp_model.Sync_input -> 0
             | Fpp_model.Guarded_input -> 1
             | Fpp_model.Async_input _ -> 2
             | Fpp_model.Output -> 3)
        in
        (owner_id, port_name, port_type, count, direction,
         [ lt "0" port_name_length; lt "0" count ]))
      port_rows
  in
  let resolved_port_facts =
    List.mapi
      (fun component_index (component : Fpp_model.component) ->
        List.mapi
          (fun port_index port ->
            let prefix =
              Printf.sprintf "fpp.resolved-port.%d.%d" component_index port_index in
            let owner, _ = add_string builder (prefix ^ ".owner") component.comp_name in
            match port with
            | Fpp_model.General item ->
                let name, _ = add_string builder (prefix ^ ".name") item.name in
                let type_id, _ = add_string builder (prefix ^ ".type") item.port in
                let count = add_int builder (prefix ^ ".count") item.count in
                let direction = add_int builder (prefix ^ ".direction")
                    (match item.direction with
                     | Fpp_model.Sync_input -> 0
                     | Fpp_model.Guarded_input -> 1
                     | Fpp_model.Async_input _ -> 2
                     | Fpp_model.Output -> 3)
                in
                let general = add_int builder (prefix ^ ".general") 1 in
                (owner, name, type_id, count, direction, general)
            | Fpp_model.Special special ->
                let name_text, output, code = fpp_special_shape special in
                let name, _ = add_string builder (prefix ^ ".name") name_text in
                let type_id = add_int builder (prefix ^ ".type") 0 in
                let count = add_int builder (prefix ^ ".count") 1 in
                let direction = add_int builder (prefix ^ ".direction")
                    (if output then 3 else 0) in
                let general = add_int builder (prefix ^ ".general") 0 in
                let _code = add_int builder (prefix ^ ".special-code") code in
                (owner, name, type_id, count, direction, general))
          component.ports)
      model.components
    |> List.concat
  in
  let instance_facts =
    List.mapi
      (fun index (instance : Fpp_model.instance) ->
        let name, name_length =
          add_string builder (Printf.sprintf "fpp.instance.%d.name" index)
            instance.inst_name
        in
        let component_id, _ =
          add_string builder (Printf.sprintf "fpp.instance.%d.component" index)
            instance.of_component
        in
        let base =
          add_int builder (Printf.sprintf "fpp.instance.%d.base" index)
            instance.base_id
        in
        let span =
          match List.find_opt
              (fun (component : Fpp_model.component) ->
                component.comp_name = instance.of_component)
              model.components
          with
          | None -> 0
          | Some component -> Fpp_model.id_span component
        in
        let span =
          add_int builder (Printf.sprintf "fpp.instance.%d.span" index) span in
        (name, component_id, base, span,
         [ lt "0" name_length; le "0" base; lt "0" span ]))
      model.instances
  in
  (* Fpp_model.validate has a fixed public clause denominator.  Each clause
     below is reconstructed from typed raw fields, never from its host result:
     NAME-01, TYPE-01/02, CMP-01..10, SM-01..03, INST-01..03 and
     TOPO-01..06. *)
  let machine_names =
    string_facts "fpp.machine.name" (List.map fpp_machine_name model.machines)
  and type_names =
    string_facts "fpp.type.name" (List.map fpp_type_name model.type_defs)
  in
  let definition_name_lengths label values =
    List.mapi
      (fun index value ->
        snd (add_string builder (Printf.sprintf "%s.%d" label index) value))
      values
  in
  let global_name_constraints =
    List.map (lt "0")
      (definition_name_lengths "fpp.port-definition.name-check"
         (List.map (fun (item : Fpp_model.port_def) -> item.port_name)
            model.port_defs)
       @ definition_name_lengths "fpp.topology.name-check"
           (List.map (fun (item : Fpp_model.topology) -> item.topo_name)
              model.topologies)
       @ definition_name_lengths "fpp.machine.name-check"
           (List.map fpp_machine_name model.machines)
       @ definition_name_lengths "fpp.type.name-check"
           (List.map fpp_type_name model.type_defs))
  in
  let named_uses =
    let from_parameters parameters =
      List.filter_map
        (fun (_, ty) -> fpp_named_type ty)
        parameters
    in
    List.concat_map
      (function
        | Fpp_model.Abstract _ | Fpp_model.Enum_t _ -> []
        | Fpp_model.Alias { target; _ } -> List.filter_map Fun.id [ fpp_named_type target ]
        | Fpp_model.Array_t { element; _ } ->
            List.filter_map Fun.id [ fpp_named_type element ]
        | Fpp_model.Struct_t { members; _ } -> from_parameters members)
      model.type_defs
    @ List.concat_map
        (fun (item : Fpp_model.port_def) ->
          from_parameters item.params
          @ List.filter_map Fun.id [ Option.bind item.return_type fpp_named_type ])
        model.port_defs
    @ List.concat_map
        (fun (component : Fpp_model.component) ->
          List.concat_map
            (fun (command : Fpp_model.command) -> from_parameters command.cmd_params)
            component.commands
          @ List.filter_map
              (fun (channel : Fpp_model.channel) -> fpp_named_type channel.chan_type)
              component.channels
          @ List.filter_map
              (fun (parameter : Fpp_model.parameter) ->
                fpp_named_type parameter.param_type)
              component.parameters
          @ List.filter_map
              (fun (record : Fpp_model.record_spec) ->
                fpp_named_type record.record_type)
              component.records
          @ List.concat_map
              (fun (port : Fpp_model.internal_port) ->
                from_parameters port.internal_params)
              component.internal_ports)
        model.components
  in
  let named_use_vars = string_facts "fpp.named-use.target" named_uses in
  let type_resolution_constraints =
    List.map (fun target -> membership target type_names) named_use_vars
  in
  let type_ranks =
    List.mapi
      (fun index _ ->
        let rank = Printf.sprintf "fpp_type_rank_%d" index in
        add_line builder ("(declare-const " ^ rank ^ " Int)");
        rank)
      model.type_defs
  in
  let type_edges =
    List.mapi
      (fun index definition ->
        let dependencies =
          match definition with
          | Fpp_model.Abstract _ | Fpp_model.Enum_t _ -> []
          | Fpp_model.Alias { target; _ } ->
              List.filter_map Fun.id [ fpp_named_type target ]
          | Fpp_model.Array_t { element; _ } ->
              List.filter_map Fun.id [ fpp_named_type element ]
          | Fpp_model.Struct_t { members; _ } ->
              List.filter_map (fun (_, ty) -> fpp_named_type ty) members
        in
        List.map (fun dependency -> (index, dependency)) dependencies)
      model.type_defs
    |> List.concat
  in
  let type_cycle_constraints =
    List.map
      (fun (source_index, target_name) ->
        or_
          (List.mapi
             (fun target_index name ->
               and_
                 [ eq name (smt_int (intern builder target_name));
                   lt (List.nth type_ranks target_index)
                     (List.nth type_ranks source_index) ])
             type_names))
      type_edges
  in
  let component_dictionary_constraints =
    List.mapi
      (fun index (component : Fpp_model.component) ->
        let prefix = Printf.sprintf "fpp.component.%d" index in
        let command_names = string_facts (prefix ^ ".command.name")
            (List.map (fun (item : Fpp_model.command) -> item.cmd_name)
               component.commands)
        and command_opcodes = int_facts (prefix ^ ".command.opcode")
            (List.map (fun (item : Fpp_model.command) -> item.opcode)
               component.commands)
        and event_names = string_facts (prefix ^ ".event.name")
            (List.map (fun (item : Fpp_model.event) -> item.event_name)
               component.events)
        and event_ids = int_facts (prefix ^ ".event.id")
            (List.map (fun (item : Fpp_model.event) -> item.event_id)
               component.events)
        and channel_names = string_facts (prefix ^ ".channel.name")
            (List.map (fun (item : Fpp_model.channel) -> item.chan_name)
               component.channels)
        and channel_ids = int_facts (prefix ^ ".channel.id")
            (List.map (fun (item : Fpp_model.channel) -> item.chan_id)
               component.channels)
        and parameter_names = string_facts (prefix ^ ".parameter.name")
            (List.map (fun (item : Fpp_model.parameter) -> item.param_name)
               component.parameters)
        and parameter_ids = int_facts (prefix ^ ".parameter.id")
            (List.map (fun (item : Fpp_model.parameter) -> item.param_id)
               component.parameters)
        and parameter_opcodes = int_facts (prefix ^ ".parameter.opcode")
            (List.concat_map
               (fun (item : Fpp_model.parameter) ->
                 [ item.set_opcode; item.save_opcode ])
               component.parameters)
        and product_names = string_facts (prefix ^ ".product.name")
            (List.map (fun (item : Fpp_model.record_spec) -> item.record_name)
               component.records
             @ List.map
                 (fun (item : Fpp_model.container_spec) -> item.container_name)
                 component.containers)
        and product_ids = int_facts (prefix ^ ".product.id")
            (List.map (fun (item : Fpp_model.record_spec) -> item.record_id)
               component.records
             @ List.map
                 (fun (item : Fpp_model.container_spec) -> item.container_id)
                 component.containers)
        and special_codes = int_facts (prefix ^ ".special.code")
            (List.filter_map
               (function
                 | Fpp_model.General _ -> None
                 | Fpp_model.Special special ->
                     let _, _, code = fpp_special_shape special in
                     Some code)
               component.ports)
        and machine_instance_names =
          string_facts (prefix ^ ".machine-instance.name")
            (List.map fst component.machines)
        and machine_references =
          string_facts (prefix ^ ".machine-instance.target")
            (List.map snd component.machines)
        in
        let record_count = add_int builder (prefix ^ ".record.count")
            (List.length component.records)
        and container_count = add_int builder (prefix ^ ".container.count")
            (List.length component.containers)
        in
        [ distinct command_names; distinct command_opcodes;
          distinct event_names; distinct event_ids; distinct channel_names;
          distinct channel_ids; distinct parameter_names; distinct parameter_ids;
          distinct (command_opcodes @ parameter_opcodes); distinct product_names;
          distinct product_ids; distinct special_codes; distinct machine_instance_names;
          eq (eq record_count "0") (eq container_count "0") ]
        @ List.map (fun target -> membership target machine_names) machine_references)
      model.components
    |> List.concat
  in
  let state_machine_constraints =
    List.mapi
      (fun machine_index machine ->
        match machine with
        | Fpp_model.External_machine _ -> []
        | Fpp_model.Internal_machine machine ->
            let prefix = Printf.sprintf "fpp.machine.%d" machine_index in
            let state_names = string_facts (prefix ^ ".state.name")
                (List.map (fun (item : Fpp_model.state) -> item.state_name)
                   machine.states)
            and choice_names = string_facts (prefix ^ ".choice.name")
                (List.map (fun (item : Fpp_model.choice) -> item.choice_name)
                   machine.choices)
            and signal_names = string_facts (prefix ^ ".signal.name")
                (List.map (fun (item : Fpp_model.signal_def) -> item.signal_name)
                   machine.signals)
            and guard_names = string_facts (prefix ^ ".guard.name") machine.guards
            and action_names = string_facts (prefix ^ ".action.name") machine.actions
            in
            let target_condition label = function
              | Fpp_model.To_state state ->
                  let value, _ = add_string builder label state in
                  membership value state_names
              | Fpp_model.To_choice choice ->
                  let value, _ = add_string builder label choice in
                  membership value choice_names
            in
            let initial_target, _ =
              add_string builder (prefix ^ ".initial.target") (snd machine.initial) in
            let state_constraints =
              List.mapi
                (fun state_index (state : Fpp_model.state) ->
                  let state_prefix =
                    Printf.sprintf "%s.state.%d" prefix state_index in
                  let entry_actions =
                    string_facts (state_prefix ^ ".entry") state.entry
                  and exit_actions =
                    string_facts (state_prefix ^ ".exit") state.exit_ in
                  List.map (fun action -> membership action action_names)
                    (entry_actions @ exit_actions)
                  @ (List.mapi
                      (fun transition_index
                           (transition : Fpp_model.transition) ->
                        let transition_prefix =
                          Printf.sprintf "%s.transition.%d" state_prefix
                            transition_index in
                        let signal, _ =
                          add_string builder (transition_prefix ^ ".signal")
                            transition.on_signal in
                        let guard_constraints =
                          match transition.guard with
                          | None -> []
                          | Some guard ->
                              let guard, _ =
                                add_string builder (transition_prefix ^ ".guard") guard in
                              [ membership guard guard_names ]
                        in
                        let actions =
                          string_facts (transition_prefix ^ ".action")
                            transition.do_actions in
                        membership signal signal_names
                        :: target_condition (transition_prefix ^ ".target")
                             transition.target
                        :: guard_constraints
                        @ List.map
                            (fun action -> membership action action_names) actions)
                      state.transitions
                     |> List.concat))
                machine.states
              |> List.concat
            in
            let choice_ranks =
              List.mapi
                (fun index _ ->
                  let rank = Printf.sprintf "fpp_choice_rank_%d_%d"
                      machine_index index in
                  add_line builder ("(declare-const " ^ rank ^ " Int)");
                  rank)
                machine.choices
            in
            let choice_constraints =
              List.mapi
                (fun choice_index (choice : Fpp_model.choice) ->
                  let choice_prefix =
                    Printf.sprintf "%s.choice.%d" prefix choice_index in
                  let guard, _ =
                    add_string builder (choice_prefix ^ ".guard")
                      choice.choice_guard in
                  let arc arc_index (actions, target) =
                    let actions = string_facts
                        (Printf.sprintf "%s.arc.%d.action" choice_prefix arc_index)
                        actions in
                    let target_check =
                      target_condition
                        (Printf.sprintf "%s.arc.%d.target" choice_prefix arc_index)
                        target in
                    let rank_check =
                      match target with
                      | Fpp_model.To_state _ -> []
                      | Fpp_model.To_choice target_name ->
                          [ or_
                              (List.mapi
                                 (fun target_index name ->
                                   and_
                                     [ eq name
                                         (smt_int (intern builder target_name));
                                       lt (List.nth choice_ranks target_index)
                                         (List.nth choice_ranks choice_index) ])
                                 choice_names) ]
                    in
                    target_check
                    :: rank_check
                    @ List.map (fun action -> membership action action_names)
                        actions
                  in
                  membership guard guard_names
                  :: (arc 0 choice.if_true @ arc 1 choice.if_false))
                machine.choices
              |> List.concat
            in
            membership initial_target state_names
            :: state_constraints @ choice_constraints)
      model.machines
    |> List.concat
  in
  let instance_runtime_constraints =
    List.mapi
      (fun index (instance : Fpp_model.instance) ->
        let prefix = Printf.sprintf "fpp.instance.%d" index in
        let component_id =
          let value, _ = add_string builder (prefix ^ ".runtime-component")
              instance.of_component in
          value
        and queue_present, _ = optional_int (prefix ^ ".queue") instance.queue_size
        and stack_present, _ = optional_int (prefix ^ ".stack") instance.stack_size
        and priority_present, _ =
          optional_int (prefix ^ ".priority") instance.inst_priority
        and cpu_present, _ = optional_int (prefix ^ ".cpu") instance.cpu in
        or_
          (List.map
             (fun (name, kind, _) ->
               and_
                 [ eq component_id name;
                   implies (eq kind "0") (eq queue_present "0");
                   implies (or_ [ eq kind "1"; eq kind "2" ])
                     (eq queue_present "1");
                   implies (not_ (eq kind "2"))
                     (and_ [ eq stack_present "0"; eq priority_present "0";
                             eq cpu_present "0" ]) ])
             component_names))
      model.instances
  in
  let component_name_vars =
    List.map (fun (name, _, _) -> name) component_names in
  let instance_name_vars =
    List.map (fun (name, _, _, _, _) -> name) instance_facts in
  let component_constraints =
    List.concat_map (fun (_, _, constraints) -> constraints) component_names in
  let port_constraints =
    List.concat_map (fun (_, _, _, _, _, constraints) -> constraints) port_facts in
  let instance_constraints =
    List.concat_map
      (fun (_, component_id, _, _, constraints) ->
        membership component_id component_name_vars :: constraints)
      instance_facts
  in
  let interval_constraints =
    pairwise instance_facts
      (fun (_, _, left_base, left_span, _) (_, _, right_base, right_span, _) ->
        or_
          [ le ("(+ " ^ left_base ^ " " ^ left_span ^ ")") right_base;
            le ("(+ " ^ right_base ^ " " ^ right_span ^ ")") left_base ])
  in
  let connection_constraints =
    List.mapi
      (fun topology_index (topology : Fpp_model.topology) ->
        let prefix = Printf.sprintf "fpp.topology.%d" topology_index in
        let member_vars = string_facts (prefix ^ ".member") topology.members in
        let member_constraints =
          List.map (fun member -> membership member instance_name_vars) member_vars in
        let direct_connections =
          List.concat_map
            (function
              | Fpp_model.Direct graph -> graph.connections
              | Fpp_model.Pattern _ -> [])
            topology.graphs
        in
        let endpoint_fact label (endpoint : Fpp_model.endpoint) =
          let endpoint_instance, _ =
            add_string builder (label ^ ".instance") endpoint.ep_instance in
          let endpoint_port, _ =
            add_string builder (label ^ ".port") endpoint.ep_port in
          let endpoint_index_present, endpoint_index =
            optional_int (label ^ ".index") endpoint.ep_index in
          { endpoint_instance; endpoint_port; endpoint_index_present;
            endpoint_index }
        in
        let connection_facts =
          List.mapi
            (fun index (connection : Fpp_model.connection) ->
              { from_endpoint =
                  endpoint_fact
                    (Printf.sprintf "%s.connection.%d.from" prefix index)
                    connection.from_;
                to_endpoint =
                  endpoint_fact
                    (Printf.sprintf "%s.connection.%d.to" prefix index)
                    connection.to_;
                raw_connection = connection })
            direct_connections
        in
        let endpoint_valid endpoint output selected_owner selected_type
            selected_general =
          let instance_relation =
            or_
              (List.map
                 (fun (instance_name, component_id, _, _, _) ->
                   and_
                     [ eq endpoint.endpoint_instance instance_name;
                       eq selected_owner component_id ])
                 instance_facts)
          in
          let port_relation =
            or_
              (List.map
                 (fun (owner, port_name, port_type, count, direction, general) ->
                   let index_valid =
                     and_
                       [ membership endpoint.endpoint_index_present [ "0"; "1" ];
                         implies
                           (and_ [ eq endpoint.endpoint_index_present "1";
                                   eq general "1" ])
                           (and_ [ le "0" endpoint.endpoint_index;
                                   lt endpoint.endpoint_index count ]) ]
                   in
                   and_
                     [ eq selected_owner owner; eq endpoint.endpoint_port port_name;
                       (if output then eq direction "3"
                        else not_ (eq direction "3"));
                       eq selected_type port_type; eq selected_general general;
                       index_valid ])
                 resolved_port_facts)
          in
          and_
            [ membership endpoint.endpoint_instance member_vars;
              instance_relation; port_relation ]
        in
        let connection_valid index fact =
          let selected endpoint =
            match
              List.find_opt
                (fun (instance : Fpp_model.instance) ->
                  String.equal instance.inst_name endpoint.Fpp_model.ep_instance)
                model.instances
            with
            | None -> (0, 0, 0)
            | Some instance ->
                begin match
                  List.find_opt
                    (fun (component : Fpp_model.component) ->
                      String.equal component.comp_name instance.of_component)
                    model.components
                with
                | None -> (0, 0, 0)
                | Some component ->
                    let port =
                      List.find_opt
                        (function
                          | Fpp_model.General item ->
                              String.equal item.name endpoint.ep_port
                          | Fpp_model.Special special ->
                              let name, _, _ = fpp_special_shape special in
                              String.equal name endpoint.ep_port)
                        component.ports
                    in
                    begin match port with
                    | None -> (0, 0, 0)
                    | Some (Fpp_model.General item) ->
                        (intern builder component.comp_name,
                         intern builder item.port, 1)
                    | Some (Fpp_model.Special _) ->
                        (intern builder component.comp_name, 0, 0)
                    end
                end
          in
          let from_owner_value, from_type_value, from_general_value =
            selected fact.raw_connection.from_
          and to_owner_value, to_type_value, to_general_value =
            selected fact.raw_connection.to_ in
          let resolved field value =
            add_int builder
              (Printf.sprintf "%s.connection.%d.selected.%s" prefix index field)
              value
          in
          let from_owner = resolved "from-owner" from_owner_value
          and from_type = resolved "from-type" from_type_value
          and from_general = resolved "from-general" from_general_value
          and to_owner = resolved "to-owner" to_owner_value
          and to_type = resolved "to-type" to_type_value
          and to_general = resolved "to-general" to_general_value in
          if Option.is_none !first_resolver_carrier then
            first_resolver_carrier := Some (from_owner, from_owner_value);
          and_
            [ endpoint_valid fact.from_endpoint true from_owner from_type
                from_general;
              endpoint_valid fact.to_endpoint false to_owner to_type to_general;
              implies (and_ [ eq from_general "1"; eq to_general "1" ])
                (eq from_type to_type) ]
        in
        let output_conflicts =
          pairwise connection_facts
            (fun left right ->
              not_
                (and_
                   [ eq left.from_endpoint.endpoint_instance
                       right.from_endpoint.endpoint_instance;
                     eq left.from_endpoint.endpoint_port
                       right.from_endpoint.endpoint_port;
                     eq left.from_endpoint.endpoint_index_present "1";
                     eq right.from_endpoint.endpoint_index_present "1";
                     eq left.from_endpoint.endpoint_index
                       right.from_endpoint.endpoint_index ]))
        in
        let pattern_constraints =
          List.concat_map
            (function
              | Fpp_model.Direct _ -> []
              | Fpp_model.Pattern { source; targets; _ } ->
                  let values = source :: targets in
                  List.mapi
                    (fun index value ->
                      let value, _ = add_string builder
                          (Printf.sprintf "%s.pattern-endpoint.%d" prefix index)
                          value in
                      membership value member_vars)
                    values)
            topology.graphs
        in
        let endpoint_touches instance port index endpoint =
          and_
            [ eq endpoint.endpoint_instance (smt_int (intern builder instance));
              eq endpoint.endpoint_port (smt_int (intern builder port));
              eq endpoint.endpoint_index_present "1";
              eq endpoint.endpoint_index (smt_int index) ]
        in
        let touched instance port index =
          or_
            (List.concat_map
               (fun fact ->
                 [ endpoint_touches instance port index fact.from_endpoint;
                   endpoint_touches instance port index fact.to_endpoint ])
               connection_facts)
        in
        let matched_constraints =
          List.concat_map
            (fun (instance : Fpp_model.instance) ->
              match List.find_opt
                  (fun (component : Fpp_model.component) ->
                    component.comp_name = instance.of_component)
                  model.components
              with
              | None -> []
              | Some component ->
                  List.concat_map
                    (fun (left_port, right_port) ->
                      let candidate_indexes =
                        direct_connections
                        |> List.concat_map
                             (fun (connection : Fpp_model.connection) ->
                               [ connection.from_; connection.to_ ])
                        |> List.filter_map
                             (fun (endpoint : Fpp_model.endpoint) ->
                               if endpoint.ep_instance = instance.inst_name
                                  && (endpoint.ep_port = left_port
                                      || endpoint.ep_port = right_port)
                               then endpoint.ep_index else None)
                        |> List.sort_uniq Int.compare
                      in
                      List.map
                        (fun index ->
                          eq (touched instance.inst_name left_port index)
                            (touched instance.inst_name right_port index))
                        candidate_indexes)
                    component.matched)
            model.instances
        in
        member_constraints
        @ List.mapi connection_valid connection_facts
        @ output_conflicts @ pattern_constraints @ matched_constraints)
      model.topologies
    |> List.concat
  in
  let clause_ids =
    string_facts "fpp.validation-clause" fpp_validation_clause_ids in
  let clause_count =
    add_int builder "fpp.validation-clause.count"
      (List.length fpp_validation_clause_ids) in
  let clause_coverage_constraints =
    [ eq clause_count "25"; distinct clause_ids ]
  in
  ignore model_name;
  let valid =
    and_
      ([ lt "0" model_name_length; lt "0" component_count;
         lt "0" instance_count; lt "0" topology_count;
         distinct component_name_vars; distinct instance_name_vars ]
       @ global_name_constraints @ type_resolution_constraints
       @ type_cycle_constraints @ component_constraints @ port_constraints
       @ component_dictionary_constraints @ state_machine_constraints
       @ instance_constraints @ instance_runtime_constraints
       @ interval_constraints @ connection_constraints
       @ clause_coverage_constraints)
  in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.fpp-valid.negated",
         "The negation of FPP validity is impossible for the typed topology.")
    | Fact_mutant_control Inject_fpp_cmp_01_passive_async ->
        ("control.fpp-valid.fpp-cmp-01-witness",
         "A passive component carrying an async input is a satisfiable named \
          FPP-CMP-01 violation.")
    | _ -> invalid_arg "fpp_query: wrong mutant"
  in
  let query =
    make_query ~stable_id ~requirement_id:"REQ-OPS-FPP-VALID" ~statement
      ~law:Fpp_valid ~polarity builder (not_ valid)
  in
  begin match polarity, !first_resolver_carrier with
  | Negated_law, Some (variable, value) ->
      let binding = Printf.sprintf "(assert (= %s %s))" variable (smt_int value) in
      let width = String.length binding in
      let rec find index =
        if index + width > String.length query.smt2 then None
        else if String.sub query.smt2 index width = binding then Some index
        else find (index + 1)
      in
      begin match find 0 with
      | None -> fpp_resolver_probe := None
      | Some index ->
          let suffix = index + width in
          fpp_resolver_probe :=
            Some
              (String.sub query.smt2 0 index
               ^ "; fact-mutant fpp.resolver-unbound"
               ^ String.sub query.smt2 suffix
                   (String.length query.smt2 - suffix)
               ^ Printf.sprintf "(get-value (%s))\n" variable)
      end
  | Fact_mutant_control _, (Some _ | None)
  | Negated_law, None -> ()
  end;
  query

let metric_query polarity =
  let channels =
    match polarity with
    | Fact_mutant_control Duplicate_metric_mapping ->
        begin match List.find_opt
            (fun (item : Run_topology.channel) -> Option.is_some item.metric_id)
            Run_topology.authority.channels
        with
        | None -> Run_topology.authority.channels
        | Some item -> item :: Run_topology.authority.channels
        end
    | _ -> Run_topology.authority.channels
  in
  let builder = create_builder () in
  List.iteri
    (fun index (metric : Run_metrics.declaration) ->
      ignore
        (add_string builder (Printf.sprintf "metric.%d.id" index) metric.id);
      ignore
        (add_string builder (Printf.sprintf "metric.%d.fpp" index)
           metric.fpp_channel))
    Run_metrics.all;
  List.iteri
    (fun index (channel : Run_topology.channel) ->
      let mapped =
        match channel.metric_id with None -> 0 | Some id -> intern builder id
      in
      ignore
        (add_int builder (Printf.sprintf "channel.%d.metric" index) mapped);
      ignore
        (add_string builder (Printf.sprintf "channel.%d.fpp" index)
           channel.fpp_name))
    channels;
  (* These counts are raw aggregate facts derived from the same typed metric and
     channel rows above.  They keep the totality theorem relational while
     avoiding the prior metric-by-channel cross product in the native AST. *)
  let metric_aggregate_constraints =
    List.mapi
      (fun index (metric : Run_metrics.declaration) ->
        let matching =
          List.filter
            (fun (channel : Run_topology.channel) ->
              channel.metric_id = Some metric.id)
            channels
        in
        let mapping_count =
          add_int builder (Printf.sprintf "metric.%d.mapping-count" index)
            (List.length matching)
        in
        let fpp_mismatch_count =
          add_int builder (Printf.sprintf "metric.%d.fpp-mismatch-count" index)
            (List.length
               (List.filter
                  (fun (channel : Run_topology.channel) ->
                    not (String.equal channel.fpp_name metric.fpp_channel))
                  matching))
        in
        and_ [ eq mapping_count "1"; eq fpp_mismatch_count "0" ])
      Run_metrics.all
  in
  let unknown_mapping_count =
    add_int builder "metric.unknown-mapping-count"
      (List.length
         (List.filter
            (fun (channel : Run_topology.channel) ->
              match channel.metric_id with
              | None -> false
              | Some id -> Option.is_none (Run_metrics.find id))
            channels))
  in
  let valid =
    and_ (eq unknown_mapping_count "0" :: metric_aggregate_constraints)
  in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.metric-total.negated",
         "The negation of one-channel-per-metric totality is impossible.")
    | Fact_mutant_control Duplicate_metric_mapping ->
        ("control.metric-total.false-witness",
         "A duplicate metric-to-channel mapping is a satisfiable totality violation.")
    | _ -> invalid_arg "metric_query: wrong mutant"
  in
  make_query ~stable_id ~requirement_id:"REQ-OPS-METRIC-TOTAL" ~statement
    ~law:Metric_total ~polarity builder (not_ valid)

(* The five exact FPP models this law must range over. *)
let external_models () = Run_fpp_authority.models ()

(* QF_LIA integers are unbounded, so "overflow" is only a relation if the
   maximum is itself a raw fact in the query. This is that fact. *)
let representable_maximum = max_int

type window_fact = {
  fact_owner : Fpp_window_authority.owner;
  owner_id : string;
  sequential : string;
  declared_model : string;
  observed_model : string;
  declared_instance : string;
  observed_instance : string;
  declared_component : string;
  observed_component : string;
  allocation_present : string;
  component_present : string;
  declared_base : string;
  observed_base : string;
  span : string;
  qualified_instance : string;
}

let id_windows_query polarity =
  let canonical_rows owner model = Fpp_window_authority.rows owner model in
  let update_first owner update rows =
    let rec loop = function
      | [] -> []
      | (row : Fpp_window_authority.row) :: rest ->
          if row.owner = owner then update row :: rest
          else row :: loop rest
    in
    loop rows
  in
  let rows =
    List.concat_map
      (fun (owner, model) -> canonical_rows owner model)
      (external_models ())
  in
  let rows =
    match polarity with
    | Fact_mutant_control Overlap_instance_window ->
        begin match
            List.filter
              (fun (row : Fpp_window_authority.row) ->
                row.owner = Fpp_window_authority.Completion)
              rows
        with
        | first :: second :: _ ->
            List.map
              (fun (row : Fpp_window_authority.row) ->
                if row.owner = second.owner && row.instance_id = second.instance_id
                then { row with declared_base_id = first.declared_base_id;
                     observed_base_id = first.observed_base_id }
                else row)
              rows
        | _ -> rows
        end
    | Fact_mutant_control Overlap_external_window ->
        let harness_base =
          Fpp_window_authority.window_base Fpp_window_authority.Harness in
        update_first Fpp_window_authority.Wiki
          (fun row ->
            { row with declared_base_id = harness_base;
              observed_base_id = harness_base }) rows
    | Fact_mutant_control Overflow_instance_window ->
        update_first Fpp_window_authority.Harness
          (fun row ->
            { row with declared_base_id = representable_maximum - 1;
              observed_base_id = representable_maximum - 1 }) rows
    | Fact_mutant_control Mismatch_window_model_name ->
        update_first Fpp_window_authority.Harness
          (fun row -> { row with observed_model_name = "WrongHarnessModel" }) rows
    | Fact_mutant_control Remove_window_allocation ->
        update_first Fpp_window_authority.Harness
          (fun row -> { row with allocation_present = false }) rows
    | Fact_mutant_control Remove_window_component ->
        update_first Fpp_window_authority.Harness
          (fun row -> { row with component_present = false }) rows
    | Fact_mutant_control Change_window_observed_base ->
        update_first Fpp_window_authority.Harness
          (fun row -> { row with observed_base_id = row.observed_base_id + 1 }) rows
    | Fact_mutant_control Include_unregistered_actual_window ->
        let promoted =
          external_models ()
          |> List.concat_map (fun (owner, model) ->
                 Fpp_window_authority.unregistered_actual_rows owner model)
          |> List.map (fun (row : Fpp_window_authority.row) ->
                 { row with allocation_present = true;
                   declared_base_id = row.observed_base_id })
        in
        rows @ promoted
    | _ -> rows
  in
  let builder = create_builder () in
  let maximum = add_int builder "window.maximum" representable_maximum in
  let facts =
    List.mapi
      (fun index (row : Fpp_window_authority.row) ->
        let prefix = Printf.sprintf "window.row.%d" index in
        let string field value = fst (add_string builder (prefix ^ "." ^ field) value) in
        { fact_owner = row.owner;
          owner_id = string "owner" (Fpp_window_authority.owner_name row.owner);
          sequential = add_int builder (prefix ^ ".sequential")
              (if row.sequential then 1 else 0);
          declared_model = string "declared-model" row.declared_model_name;
          observed_model = string "observed-model" row.observed_model_name;
          declared_instance = string "declared-instance" row.instance_id;
          observed_instance = string "observed-instance" row.observed_instance_id;
          declared_component = string "declared-component" row.component_id;
          observed_component = string "observed-component" row.observed_component_id;
          allocation_present = add_int builder (prefix ^ ".allocation-present")
              (if row.allocation_present then 1 else 0);
          component_present = add_int builder (prefix ^ ".component-present")
              (if row.component_present then 1 else 0);
          declared_base = add_int builder (prefix ^ ".declared-base")
              row.declared_base_id;
          observed_base = add_int builder (prefix ^ ".observed-base")
              row.observed_base_id;
          span = add_int builder (prefix ^ ".span") row.span;
          qualified_instance = string "qualified-instance"
              (Fpp_window_authority.owner_name row.owner ^ "." ^ row.instance_id) })
      rows
  in
  let facts_of owner = List.filter (fun fact -> fact.fact_owner = owner) facts in
  let window_base_value owner =
    match polarity, owner with
    | Fact_mutant_control Overlap_external_window, Fpp_window_authority.Wiki ->
        Fpp_window_authority.window_base Fpp_window_authority.Harness
    | Fact_mutant_control Overflow_instance_window, Fpp_window_authority.Harness ->
        representable_maximum - 1
    | _ -> Fpp_window_authority.window_base owner
  in
  let owner_bases =
    List.map
      (fun owner ->
        let owner_tag = Fpp_window_authority.owner_name owner in
        (owner,
         add_int builder ("window.owner." ^ owner_tag ^ ".base")
           (window_base_value owner)))
      Fpp_window_authority.owners
  in
  let owner_constraints =
    List.concat_map
      (fun owner ->
        let owner_facts = facts_of owner in
        let owner_tag = Fpp_window_authority.owner_name owner in
        let window_base =
          match List.assoc_opt owner owner_bases with
          | Some value -> value
          | None -> "(- 1)"
        in
        let common =
          List.concat_map
            (fun fact ->
              [ eq fact.owner_id (smt_int (intern builder owner_tag));
                eq fact.declared_model fact.observed_model;
                eq fact.declared_instance fact.observed_instance;
                eq fact.declared_component fact.observed_component;
                eq fact.allocation_present "1";
                eq fact.component_present "1";
                le "0" fact.observed_base; lt "0" fact.span;
                le fact.observed_base ("(- " ^ maximum ^ " " ^ fact.span ^ ")") ])
            owner_facts
        in
        let policy =
          match owner, owner_facts with
          | Fpp_window_authority.Operations, first :: rest ->
              [ eq first.sequential "1"; eq first.declared_base window_base;
                eq first.observed_base first.declared_base ]
              @ List.map (fun fact -> eq fact.sequential "1") rest
              @ (let rec adjacent = function
                   | left :: (right :: _ as tail) ->
                       eq right.observed_base
                         ("(+ " ^ left.observed_base ^ " " ^ left.span ^ ")")
                       :: eq right.declared_base "(- 1)" :: adjacent tail
                   | _ -> []
                 in adjacent owner_facts)
          | Fpp_window_authority.Operations, [] -> [ "false" ]
          | (Fpp_window_authority.Harness | Fpp_window_authority.Wiki
            | Fpp_window_authority.Ops_monitor | Fpp_window_authority.Completion),
            first :: _ ->
              eq first.declared_base window_base
              :: List.concat_map
                   (fun fact ->
                     [ eq fact.sequential "0";
                       eq fact.declared_base fact.observed_base ])
                   owner_facts
          | (Fpp_window_authority.Harness | Fpp_window_authority.Wiki
            | Fpp_window_authority.Ops_monitor | Fpp_window_authority.Completion),
            [] -> [ "false" ]
        in
        lt "0" (smt_int (List.length owner_facts)) :: common @ policy)
      Fpp_window_authority.owners
  in
  let valid =
    let owner_heads =
      List.filter_map
        (fun owner ->
          match facts_of owner with first :: _ -> Some first | [] -> None)
        Fpp_window_authority.owners
    in
    and_
      ([ eq (smt_int (List.length Fpp_window_authority.owners)) "5";
         distinct (List.map snd owner_bases);
         distinct (List.map (fun fact -> fact.owner_id) owner_heads);
         distinct (List.map (fun fact -> fact.declared_model) owner_heads);
         distinct (List.map (fun fact -> fact.qualified_instance) facts) ]
       @ owner_constraints
       @ pairwise facts
           (fun left right ->
             or_
               [ le ("(+ " ^ left.observed_base ^ " " ^ left.span ^ ")")
                   right.observed_base;
                 le ("(+ " ^ right.observed_base ^ " " ^ right.span ^ ")")
                   left.observed_base ]))
  in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.id-windows.negated",
         "The negation of normative five-owner allocation-window identity, \
          disjointness, and representability is impossible.")
    | Fact_mutant_control Overlap_instance_window ->
        ("control.id-windows.false-witness",
         "Two instances sharing one base id are a satisfiable overlap witness.")
    | Fact_mutant_control Overlap_external_window ->
        ("control.id-windows.external-overlap-witness",
         "One model relocated onto another owner's window is a satisfiable \
          cross-model overlap witness.")
    | Fact_mutant_control Overflow_instance_window ->
        ("control.id-windows.overflow-witness",
         "A base above the representable maximum minus its span is a \
          satisfiable overflow witness.")
    | Fact_mutant_control Mismatch_window_model_name ->
        ("control.id-windows.model-name-witness",
         "A declared/observed model-name mismatch is a satisfiable window-authority violation.")
    | Fact_mutant_control Remove_window_allocation ->
        ("control.id-windows.absent-allocation-witness",
         "A missing normative allocation is a satisfiable window-authority violation.")
    | Fact_mutant_control Remove_window_component ->
        ("control.id-windows.absent-component-witness",
         "A normative allocation without its component is a satisfiable window-authority violation.")
    | Fact_mutant_control Change_window_observed_base ->
        ("control.id-windows.wrong-base-witness",
         "A fixed allocation whose observed base differs is a satisfiable violation.")
    | Fact_mutant_control Include_unregistered_actual_window ->
        ("control.id-windows.actual-scope-witness",
         "Silently promoting legacy unregistered actual instances exposes the known \
          Harness/Wiki collision as a satisfiable violation.")
    | _ -> invalid_arg "id_windows_query: wrong mutant"
  in
  make_query ~stable_id ~requirement_id:"REQ-OPS-ID-WINDOWS" ~statement
    ~law:Id_windows ~polarity builder (not_ valid)

type graph_row = { edge_id : string; from_id : string; to_id : string;
  kind_id : string }

let graph_facts builder (authority : Run_topology.authority) =
  let component_ids =
    List.mapi
      (fun index (component : Run_topology.component) ->
        fst (add_string builder (Printf.sprintf "graph.component.%d" index)
          component.stable_id))
      authority.components
  in
  let edges =
    List.mapi
      (fun index (edge : Run_topology.edge) ->
        let edge_id, _ =
          add_string builder (Printf.sprintf "graph.edge.%d.id" index) edge.stable_id in
        let from_id, _ =
          add_string builder (Printf.sprintf "graph.edge.%d.from" index)
            edge.from_component in
        let to_id, _ =
          add_string builder (Printf.sprintf "graph.edge.%d.to" index)
            edge.to_component in
        let kind_id =
          add_int builder (Printf.sprintf "graph.edge.%d.kind" index)
            (match edge.kind with
             | Run_topology.Admission -> 1
             | Run_topology.Execution -> 2
             | Run_topology.Evidence_flow -> 3
             | Run_topology.State_flow -> 4
             | Run_topology.Projection -> 5)
        in
        { edge_id; from_id; to_id; kind_id })
      authority.edges
  in
  (component_ids, edges)

let path_witness builder ~component_ids ~edges ~sources ~targets ~excluded =
  let maximum = max 1 (List.length component_ids - 1) in
  let length = Printf.sprintf "path_len_%d" builder.next_fact in
  builder.next_fact <- builder.next_fact + 1;
  add_line builder ("(declare-const " ^ length ^ " Int)");
  let nodes =
    List.init (maximum + 1) (fun index ->
      let variable = Printf.sprintf "path_%d_%d" builder.next_fact index in
      add_line builder ("(declare-const " ^ variable ^ " Int)");
      variable)
  in
  builder.next_fact <- builder.next_fact + 1;
  let edge_exists left right =
    or_
      (List.map
         (fun edge -> and_ [ eq left edge.from_id; eq right edge.to_id ])
         edges)
  in
  let node index = List.nth nodes index in
  let active index = le (smt_int index) length in
  let steps =
    List.init maximum (fun index ->
      implies (lt (smt_int index) length)
        (edge_exists (node index) (node (index + 1))))
  in
  let domains =
    List.init (maximum + 1) (fun index ->
      implies (active index) (membership (node index) component_ids))
  in
  let exclusions =
    List.concat_map
      (fun excluded_id ->
        List.init (maximum + 1) (fun index ->
          implies (active index) (not_ (eq (node index) excluded_id))))
      excluded
  in
  let target =
    or_
      (List.init maximum (fun zero_based ->
        let path_length = zero_based + 1 in
        and_ [ eq length (smt_int path_length);
          membership (node path_length) targets ]))
  in
  and_
    ([ le "1" length; le length (smt_int maximum);
       membership (node 0) sources; target ]
     @ steps @ domains @ exclusions)

let execution_query polarity =
  let authority =
    match polarity with
    | Fact_mutant_control Add_execution_bypass ->
        let edge : Run_topology.edge =
          { stable_id = "edge.mutant.execution-direct";
            from_component = Run_topology.authority.formal_policy.execution
                .supervisor_component_id;
            from_port = "admittedOut";
            to_component = Run_topology.authority.formal_policy.execution
                .worker_component_id;
            to_port = "workIn"; kind = Run_topology.Execution }
        in
        { Run_topology.authority with edges = edge :: Run_topology.authority.edges }
    | _ -> Run_topology.authority
  in
  let builder = create_builder () in
  let components, edges = graph_facts builder authority in
  let policy = authority.formal_policy.execution in
  let bridge = smt_int (intern builder policy.bridge_component_id)
  and supervisor = smt_int (intern builder policy.supervisor_component_id)
  and worker = smt_int (intern builder policy.worker_component_id)
  and required_edge = smt_int (intern builder policy.required_execution_edge_id) in
  let allowed edge =
    and_ [ eq edge.kind_id "2"; eq edge.from_id bridge; eq edge.to_id worker;
      eq edge.edge_id required_edge ]
  in
  let exact = eq (bool_sum (List.map allowed edges)) "1" in
  let no_other_execution =
    and_ (List.map (fun edge -> implies (eq edge.kind_id "2") (allowed edge)) edges)
  in
  let bypass =
    path_witness builder ~component_ids:components ~edges
      ~sources:[ supervisor ] ~targets:[ worker ] ~excluded:[ bridge ]
  in
  let violation = or_ [ not_ exact; not_ no_other_execution; bypass ] in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.execution-bridge.negated",
         "The negation of sole-bridge execution mediation is impossible.")
    | Fact_mutant_control Add_execution_bypass ->
        ("control.execution-bridge.false-witness",
         "A direct supervisor-to-worker edge is a satisfiable bridge bypass.")
    | _ -> invalid_arg "execution_query: wrong mutant"
  in
  make_query ~stable_id ~requirement_id:"REQ-OPS-EXECUTION-BRIDGE" ~statement
    ~law:Execution_bridge ~polarity builder violation

let ui_query polarity =
  let authority =
    match polarity with
    | Fact_mutant_control Add_ui_admission_edge ->
        let edge : Run_topology.edge =
          { stable_id = "edge.mutant.ui-admission";
            from_component = "dreamGateway"; from_port = "stateOut";
            to_component =
              Run_topology.authority.formal_policy.execution.bridge_component_id;
            to_port = "intentIn"; kind = Run_topology.Admission }
        in
        { Run_topology.authority with edges = edge :: Run_topology.authority.edges }
    | _ -> Run_topology.authority
  in
  let builder = create_builder () in
  let components, edges = graph_facts builder authority in
  let ui =
    List.map (fun id -> smt_int (intern builder id))
      authority.formal_policy.ui_isolation.ui_component_ids in
  let admission =
    List.map (fun id -> smt_int (intern builder id))
      authority.formal_policy.ui_isolation.admission_component_ids in
  let violation =
    path_witness builder ~component_ids:components ~edges ~sources:ui
      ~targets:admission ~excluded:[]
  in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.ui-isolation.negated",
         "The negation of projection-to-admission isolation is impossible.")
    | Fact_mutant_control Add_ui_admission_edge ->
        ("control.ui-isolation.false-witness",
         "A Dream-to-admission edge is a satisfiable UI isolation violation.")
    | _ -> invalid_arg "ui_query: wrong mutant"
  in
  make_query ~stable_id ~requirement_id:"REQ-OPS-UI-ISOLATION" ~statement
    ~law:Ui_isolation ~polarity builder violation

let parsed_manifest parser text =
  match parser text with
  | Ok value -> value
  | Error _ ->
      { Run_mbse.source_digest = "parse-error"; component_ids = []; port_ids = [];
        channel_ids = []; requirement_ids = []; edge_ids = [];
        lifecycle_machine_ids = []; fault_event_ids = []; gate_command_ids = [];
        activity_ids = [] }

type repository_action_fact = {
  repository_stable_id : string;
  repository_action_digest : string;
  repository_dependency_ids : string list;
  repository_work_kind : string;
  repository_profile : string;
  repository_build_command : string;
  repository_suite_id : string;
  repository_executable : string;
}

let repository_action_fact (action : Run_topology.declarative_action) =
  let repository_work_kind, repository_profile, repository_build_command,
      repository_suite_id, repository_executable =
    match action.work with
    | Run_topology.Topology_gate ->
        ("topology-gate", "", "", "", "")
    | Repository_build { profile; build_command } ->
        ("repository-build",
         (match profile with Verification_fast -> "fast"
          | Verification_full -> "full"),
         build_command, "", "")
    | Repository_verification_suite { profile; suite_id; executable } ->
        ("repository-verification-suite",
         (match profile with Verification_fast -> "fast"
          | Verification_full -> "full"),
         "", suite_id, executable)
    | (Clock_work _ | Filesystem_work _ | External_resource_work _
      | Repository_source_work _ | Approval_nonce_work _ | Writer_lease_work _
      | Network_scope_work _ | Credential_lease_work _
      | Activation_transition_work _ | Mutation_frontier_work _
      | Materialization_work _ | Candidate_verification_work _
      | Formal_oracle_work _ | Jujutsu_work _ | Jujutsu_readback_work _
      | Completion_receipt_work _) as work ->
        ("closed-task7a-work:" ^ Run_topology.action_work_id work,
         "", "", "", "")
  in
  { repository_stable_id = action.stable_id;
    repository_action_digest = Run_topology.action_digest_of action;
    repository_dependency_ids = action.dependency_ids;
    repository_work_kind; repository_profile; repository_build_command;
    repository_suite_id; repository_executable }

let repository_action_facts (authority : Run_topology.authority) =
  authority.activities
  |> List.filter
       (fun (activity : Run_topology.declarative_activity) ->
         String.equal activity.stable_id "activity.verify-repository")
  |> List.concat_map
       Run_topology.declarative_activity_actions
  |> List.map repository_action_fact

let mutate_repository_action_facts polarity rows =
  match polarity with
  | Fact_mutant_control Drop_repository_action ->
      begin match rows with
      | build :: _suite :: rest -> build :: rest
      | _ -> rows
      end
  | Fact_mutant_control Duplicate_repository_action ->
      begin match rows with
      | build :: suite :: rest -> build :: suite :: suite :: rest
      | _ -> rows
      end
  | Fact_mutant_control Substitute_repository_action_work ->
      begin match rows with
      | build :: suite :: rest ->
          build
          :: { suite with
               repository_suite_id = "test_substituted";
               repository_executable =
                 "_build/default/test_substituted.exe" }
          :: rest
      | _ -> rows
      end
  | Fact_mutant_control Reorder_repository_actions ->
      begin match rows with
      | build :: first :: second :: rest ->
          build :: second :: first :: rest
      | _ -> rows
      end
  | _ -> rows

let mbse_query_for_authority authority polarity =
  let canonical_manifest = Run_mbse.manifest in
  let turtle_manifest =
    parsed_manifest Run_mbse.manifest_of_turtle (Run_mbse.oml_owl ()) in
  let turtle_manifest =
    match polarity, turtle_manifest.edge_ids with
    | Fact_mutant_control Drop_turtle_edge, _ :: rest ->
        { turtle_manifest with edge_ids = rest }
    | _ -> turtle_manifest
  in
  let surfaces =
    [ ("sysml-v2", parsed_manifest Run_mbse.manifest_of_sysml (Run_mbse.sysml_v2 ()));
      ("oml-owl", turtle_manifest);
      ("openmbee-mms",
       parsed_manifest Run_mbse.manifest_of_mms (Run_mbse.openmbee_mms ()));
      ("fpp", parsed_manifest Run_mbse.manifest_of_fpp (Run_mbse.fpp_dictionary ())) ]
  in
  let builder = create_builder () in
  let list_condition label expected actual =
    let actual_length =
      add_int builder (label ^ ".length") (List.length actual) in
    let expected_length = smt_int (List.length expected) in
    eq actual_length expected_length
    :: List.mapi
         (fun index value ->
           let actual_value, _ =
             add_string builder (Printf.sprintf "%s.%d" label index) value in
           match List.nth_opt expected index with
           | None -> eq actual_value actual_value
           | Some expected_value ->
               eq actual_value (smt_int (intern builder expected_value)))
         actual
  in
  let manifest_conditions surface_id (manifest : Run_mbse.manifest) =
    let digest_value, _ = add_string builder (surface_id ^ ".digest") manifest.source_digest in
    [ eq digest_value (smt_int (intern builder canonical_manifest.source_digest)) ]
    @ list_condition (surface_id ^ ".components") canonical_manifest.component_ids
        manifest.component_ids
    @ list_condition (surface_id ^ ".ports") canonical_manifest.port_ids manifest.port_ids
    @ list_condition (surface_id ^ ".channels") canonical_manifest.channel_ids
        manifest.channel_ids
    @ list_condition (surface_id ^ ".requirements") canonical_manifest.requirement_ids
        manifest.requirement_ids
    @ list_condition (surface_id ^ ".edges") canonical_manifest.edge_ids manifest.edge_ids
    @ list_condition (surface_id ^ ".machines") canonical_manifest.lifecycle_machine_ids
        manifest.lifecycle_machine_ids
    @ list_condition (surface_id ^ ".faults") canonical_manifest.fault_event_ids
        manifest.fault_event_ids
    @ list_condition (surface_id ^ ".gates") canonical_manifest.gate_command_ids
        manifest.gate_command_ids
    @ list_condition (surface_id ^ ".activities") canonical_manifest.activity_ids
        manifest.activity_ids
  in
  let surface_ids = List.map fst surfaces in
  let policy_surface_ids =
    Run_topology.authority.formal_policy.model_contract.projection_surface_ids in
  let expected_repository_actions =
    repository_action_facts Run_topology.authority in
  let observed_repository_actions =
    repository_action_facts authority
    |> mutate_repository_action_facts polarity
  in
  let expected_repository_count = List.length expected_repository_actions in
  add_line builder "; relation mbse.repository-action.count";
  let repository_count =
    add_int builder "mbse.repository-action.count"
      (List.length observed_repository_actions)
  in
  let expected_string value = smt_int (intern builder value) in
  let repository_relations =
    List.mapi
      (fun index (observed : repository_action_fact) ->
        let label = Printf.sprintf "mbse.repository-action.%d" index in
        let symbol_fact field value =
          add_int builder (label ^ "." ^ field) (intern builder value)
        in
        let observed_index = add_int builder (label ^ ".index") index in
        let observed_stable_id =
          symbol_fact "stable-id" observed.repository_stable_id in
        let observed_digest =
          symbol_fact "action-digest" observed.repository_action_digest in
        let observed_dependency_count =
          add_int builder (label ^ ".dependency-count")
            (List.length observed.repository_dependency_ids)
        in
        let observed_dependencies =
          List.mapi
            (fun dependency_index dependency_id ->
              add_int builder
                (Printf.sprintf "%s.dependency.%d" label dependency_index)
                (intern builder dependency_id))
            observed.repository_dependency_ids
        in
        let observed_work_kind =
          symbol_fact "work-kind" observed.repository_work_kind in
        let observed_profile =
          symbol_fact "profile" observed.repository_profile in
        let observed_build_command =
          symbol_fact "build-command" observed.repository_build_command in
        let observed_suite_id =
          symbol_fact "suite-id" observed.repository_suite_id in
        let observed_executable =
          symbol_fact "executable" observed.repository_executable in
        let identity, order, dependencies, work =
          match List.nth_opt expected_repository_actions index with
          | None -> ("false", "false", "false", "false")
          | Some expected ->
              let dependency_equalities =
                eq observed_dependency_count
                  (smt_int (List.length expected.repository_dependency_ids))
                :: List.mapi
                     (fun dependency_index observed_dependency ->
                       match List.nth_opt expected.repository_dependency_ids
                               dependency_index with
                       | None -> "false"
                       | Some expected_dependency ->
                           eq observed_dependency
                             (expected_string expected_dependency))
                     observed_dependencies
              in
              (and_
                 [ eq observed_stable_id
                     (expected_string expected.repository_stable_id);
                   eq observed_digest
                     (expected_string expected.repository_action_digest) ],
               and_
                 [ eq observed_index (smt_int index);
                   eq observed_stable_id
                     (expected_string expected.repository_stable_id) ],
               and_ dependency_equalities,
               and_
                 [ eq observed_work_kind
                     (expected_string expected.repository_work_kind);
                   eq observed_profile
                     (expected_string expected.repository_profile);
                   eq observed_build_command
                     (expected_string expected.repository_build_command);
                   eq observed_suite_id
                     (expected_string expected.repository_suite_id);
                   eq observed_executable
                     (expected_string expected.repository_executable) ])
        in
        (add_relation builder
           "mbse.repository-action.identity-correspondence" identity,
         add_relation builder
           "mbse.repository-action.order-correspondence" order,
         add_relation builder
           "mbse.repository-action.dependency-correspondence" dependencies,
         add_relation builder
           "mbse.repository-action.work-correspondence" work))
      observed_repository_actions
  in
  let identity_relations, order_relations, dependency_relations,
      work_relations =
    List.fold_right
      (fun (identity, order, dependency, work)
           (identities, orders, dependencies, works) ->
        (identity :: identities, order :: orders, dependency :: dependencies,
         work :: works))
      repository_relations ([], [], [], [])
  in
  let repository_total label relations =
    add_line builder ("; relation mbse.repository-action." ^ label);
    eq (bool_sum relations) (smt_int expected_repository_count)
  in
  let valid =
    and_
      (List.concat_map (fun (id, manifest) -> manifest_conditions id manifest) surfaces
       @ list_condition "mbse.projection-surfaces" policy_surface_ids surface_ids
       @ [ eq repository_count (smt_int expected_repository_count);
           repository_total "identity-total" identity_relations;
           repository_total "order-total" order_relations;
           repository_total "dependency-total" dependency_relations;
           repository_total "work-total" work_relations ])
  in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.mbse-correspondence.negated",
         "The negation of cross-projection manifest correspondence is impossible.")
    | Fact_mutant_control Drop_turtle_edge ->
        ("control.mbse-correspondence.false-witness",
         "A Turtle surface missing one edge id is a satisfiable correspondence violation.")
    | Fact_mutant_control Drop_repository_action ->
        ("control.mbse-correspondence.repository-action-missing-witness",
         "One missing repository action is a satisfiable correspondence violation.")
    | Fact_mutant_control Duplicate_repository_action ->
        ("control.mbse-correspondence.repository-action-duplicate-witness",
         "One duplicated repository action is a satisfiable correspondence violation.")
    | Fact_mutant_control Substitute_repository_action_work ->
        ("control.mbse-correspondence.repository-action-substitution-witness",
         "One substituted repository work carrier is a satisfiable correspondence violation.")
    | Fact_mutant_control Reorder_repository_actions ->
        ("control.mbse-correspondence.repository-action-reorder-witness",
         "Repository action reordering is a satisfiable correspondence violation.")
    | _ -> invalid_arg "mbse_query: wrong mutant"
  in
  make_query ~stable_id ~requirement_id:"REQ-OPS-MBSE-CORRESPONDENCE" ~statement
    ~law:Mbse_correspondence ~polarity builder (not_ valid)

let mbse_query polarity = mbse_query_for_authority Run_topology.authority polarity

type sqlite_transition_row = { machine_id : string; source_id : string;
  signal_id : string; target_id : string; action_ids : string list }

type sqlite_machine_fact = { sqlite_machine_id : string;
  sqlite_machine_owner : string; sqlite_initial_state : string;
  sqlite_state_count : string; sqlite_state_ids : string list }

type sqlite_transition_fact = { sqlite_transition_machine : string;
  sqlite_transition_source : string; sqlite_transition_signal : string;
  sqlite_transition_signal_length : string; sqlite_transition_target : string;
  sqlite_transition_actions : string list; sqlite_transition_action_count : string }

type sqlite_fault_fact = { sqlite_fault_id : string; sqlite_fault_owner : string;
  sqlite_fault_format_length : string }

type sqlite_gate_fact = { sqlite_gate_id : string; sqlite_gate_owner : string;
  sqlite_gate_intent_length : string }

type sqlite_miq_route_fact = { sqlite_miq_selector : string;
  sqlite_miq_capability : string; sqlite_miq_agent : string }

type sqlite_activity_fact = { sqlite_activity_id : string;
  sqlite_activity_selected : string;
  sqlite_activity_bridge : string; sqlite_activity_target : string;
  sqlite_activity_target_state : string;
  sqlite_activity_intent_length : string;
  sqlite_activity_constraint_count : string;
  sqlite_activity_criteria_count : string;
  sqlite_activity_capabilities : string list;
  sqlite_activity_contexts : string list;
  sqlite_activity_miq_routes : sqlite_miq_route_fact list;
  sqlite_activity_miq_count : string;
  sqlite_activity_effects : string list;
  sqlite_activity_commands : string list }

(* The SQLite invariants below MIRROR Run_topology.sqlite_dependability_gaps_for.
   Mirrored, never called: a host verdict inside the formula builder is
   what independent review rejected, and it would make the solver agree
   with a Boolean rather than discharge a relation. Each mutant changes
   the named raw fact whose relation it is meant to falsify. *)
let mutate_first_machine f (value : Run_topology.authority) =
  match value.lifecycle_machines with
  | [] -> value
  | machine :: rest -> { value with lifecycle_machines = f machine :: rest }

let mutate_first_transition f (machine : Run_topology.lifecycle_machine) =
  match machine.states with
  | [] -> machine
  | state :: states ->
      let transitions =
        match state.transitions with [] -> [] | first :: rest -> f first :: rest
      in
      { machine with states = { state with transitions } :: states }

let mutate_first_activity f (value : Run_topology.authority) =
  match value.activities with
  | [] -> value
  | activity :: rest -> { value with activities = f activity :: rest }

let effect_kind_id = Run_topology.effect_kind_id

let sqlite_query_for_authority supplied_authority polarity =
  let authority =
    match polarity with
    | Fact_mutant_control Invalid_sqlite_machine_owner ->
        mutate_first_machine
          (fun machine -> { machine with component_id = "notTheEventStore" })
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_initial_state ->
        mutate_first_machine
          (fun machine -> { machine with initial_state = "NoSuchState" })
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_transition_target ->
        mutate_first_machine
          (mutate_first_transition (fun transition ->
               { transition with target_state = "NoSuchTargetState" }))
          supplied_authority
    | Fact_mutant_control Empty_sqlite_transition_signal ->
        mutate_first_machine
          (mutate_first_transition (fun transition -> { transition with signal = "" }))
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_fault_owner ->
        (match supplied_authority.fault_events with
         | [] -> supplied_authority
         | fault :: rest ->
             { supplied_authority with
               fault_events =
                 { fault with component_id = "notTheEventStore" } :: rest })
    | Fact_mutant_control Invalid_sqlite_gate_intent ->
        (match supplied_authority.gate_commands with
         | [] -> supplied_authority
         | gate :: rest ->
             { supplied_authority with
               gate_commands = { gate with intent_id = "" } :: rest })
    | Fact_mutant_control Invalid_sqlite_activity_contract ->
        (match supplied_authority.activities with
         | [] -> supplied_authority
         | activity :: rest ->
             { supplied_authority with
               activities = { activity with constraints = [] } :: rest })
    | Fact_mutant_control Empty_sqlite_transition_actions ->
        mutate_first_machine
          (mutate_first_transition (fun transition ->
               { transition with actions = [] }))
          supplied_authority
    | Fact_mutant_control Empty_sqlite_fault_format ->
        (match supplied_authority.fault_events with
         | [] -> supplied_authority
         | fault :: rest ->
             { supplied_authority with
               fault_events = { fault with format = "" } :: rest })
    | Fact_mutant_control Invalid_sqlite_gate_owner ->
        (match supplied_authority.gate_commands with
         | [] -> supplied_authority
         | gate :: rest ->
             { supplied_authority with
               gate_commands =
                 { gate with component_id = "notTheEventStore" } :: rest })
    | Fact_mutant_control Empty_sqlite_activity_intent ->
        (match supplied_authority.activities with
         | [] -> supplied_authority
         | activity :: rest ->
             { supplied_authority with
               activities = { activity with intent = "" } :: rest })
    | Fact_mutant_control Empty_sqlite_activity_success_criteria ->
        (match supplied_authority.activities with
         | [] -> supplied_authority
         | activity :: rest ->
             { supplied_authority with
               activities = { activity with success_criteria = [] } :: rest })
    | Fact_mutant_control Invalid_sqlite_activity_target_state ->
        mutate_first_activity
          (fun activity ->
            { activity with
              target_state = "sqlite-dependability-substituted" })
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_activity_capabilities ->
        mutate_first_activity
          (fun activity ->
            { activity with
              required_capability_ids = [ "capability.unknown" ] })
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_activity_context ->
        mutate_first_activity
          (fun activity ->
            { activity with context_requirement_ids = [ "context.unknown" ] })
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_activity_miq ->
        mutate_first_activity
          (fun activity ->
            match activity.miq_routes with
            | [] -> activity
            | route :: rest ->
                { activity with
                  miq_routes =
                    { route with selector_id = "miq.unknown" } :: rest })
          supplied_authority
    | Fact_mutant_control Invalid_sqlite_activity_effects ->
        mutate_first_activity
          (fun activity ->
            { activity with
              effect_kinds = [ Run_topology.Verification_suite_execution ] })
          supplied_authority
    | Fact_mutant_control Drop_sqlite_reelect_action ->
        let lifecycle_machines =
          List.map
            (fun (machine : Run_topology.lifecycle_machine) ->
              { machine with states =
                  List.map
                    (fun (state : Run_topology.lifecycle_state) ->
                      { state with transitions =
                          List.map
                            (fun (transition : Run_topology.lifecycle_transition) ->
                              if machine.stable_id = "DatabaseCloseLifecycle"
                                 && state.stable_id = "DatabaseCloseBlocked"
                                 && transition.signal = "blockersReleased"
                              then { transition with actions =
                                  List.filter
                                    (fun action -> action <> "reelectActor")
                                    transition.actions }
                              else transition)
                            state.transitions })
                    machine.states })
            supplied_authority.lifecycle_machines
        in
        { supplied_authority with lifecycle_machines }
    | _ -> supplied_authority
  in
  let builder = create_builder () in
  let policy = authority.formal_policy.sqlite in
  let machine_facts =
    List.mapi
      (fun index (machine : Run_topology.lifecycle_machine) ->
        let prefix = Printf.sprintf "sqlite.machine.%d" index in
        let machine_id, _ = add_string builder (prefix ^ ".id") machine.stable_id in
        let owner, _ = add_string builder (prefix ^ ".owner") machine.component_id in
        let initial, _ = add_string builder (prefix ^ ".initial") machine.initial_state in
        let state_ids =
          List.mapi
            (fun state_index (state : Run_topology.lifecycle_state) ->
              fst (add_string builder
                (Printf.sprintf "%s.state.%d" prefix state_index)
                state.stable_id))
            machine.states
        in
        let state_count =
          add_int builder (prefix ^ ".state-count") (List.length state_ids) in
        { sqlite_machine_id = machine_id; sqlite_machine_owner = owner;
          sqlite_initial_state = initial; sqlite_state_count = state_count;
          sqlite_state_ids = state_ids })
      authority.lifecycle_machines
  in
  let machine_conditions =
    let machine_count =
      add_int builder "sqlite.machine.count" (List.length machine_facts) in
    eq machine_count (smt_int (List.length policy.machine_state_ids))
    :: List.map
      (fun (machine_id, expected_states) ->
        or_
          (List.map
             (fun fact ->
               and_
                 (eq fact.sqlite_machine_id (smt_int (intern builder machine_id))
                  :: eq fact.sqlite_state_count (smt_int (List.length expected_states))
                  :: List.mapi
                       (fun index expected ->
                         match List.nth_opt fact.sqlite_state_ids index with
                         | None -> eq fact.sqlite_state_count
                             (smt_int (List.length expected_states))
                         | Some actual ->
                             eq actual (smt_int (intern builder expected)))
                       expected_states))
             machine_facts))
      policy.machine_state_ids
  in
  let transition_rows =
    List.concat_map
      (fun (machine : Run_topology.lifecycle_machine) ->
        List.concat_map
          (fun (state : Run_topology.lifecycle_state) ->
            List.map
              (fun (transition : Run_topology.lifecycle_transition) ->
                { machine_id = machine.stable_id; source_id = state.stable_id;
                  signal_id = transition.signal; target_id = transition.target_state;
                  action_ids = transition.actions })
              state.transitions)
          machine.states)
      authority.lifecycle_machines
  in
  let transition_facts =
    List.mapi
      (fun index row ->
        let text field value =
          fst (add_string builder
            (Printf.sprintf "sqlite.transition.%d.%s" index field) value) in
        let actions =
          List.mapi
            (fun action_index action ->
              fst (add_string builder
                (Printf.sprintf "sqlite.transition.%d.action.%d" index action_index)
                action))
            row.action_ids
        in
        { sqlite_transition_machine = text "machine" row.machine_id;
          sqlite_transition_source = text "source" row.source_id;
          sqlite_transition_signal = text "signal" row.signal_id;
          sqlite_transition_signal_length =
            add_int builder
              (Printf.sprintf "sqlite.transition.%d.signal-length" index)
              (String.length row.signal_id);
          sqlite_transition_target = text "target" row.target_id;
          sqlite_transition_actions = actions;
          sqlite_transition_action_count =
            add_int builder
              (Printf.sprintf "sqlite.transition.%d.action-count" index)
              (List.length actions) })
      transition_rows
  in
  let transition_conditions =
    List.map
      (fun (required : Run_topology.sqlite_transition_policy) ->
        let machine_id = smt_int (intern builder required.machine_id)
        and source_id = smt_int (intern builder required.source_state_id)
        and signal_id = smt_int (intern builder required.signal_id)
        and target_id = smt_int (intern builder required.target_state_id) in
        or_
          (List.map
             (fun fact ->
               and_
                 ([ eq fact.sqlite_transition_machine machine_id;
                    eq fact.sqlite_transition_source source_id;
                    eq fact.sqlite_transition_signal signal_id;
                    eq fact.sqlite_transition_target target_id ]
                  @ List.map
                      (fun required_action ->
                        membership (smt_int (intern builder required_action))
                          fact.sqlite_transition_actions)
                      required.required_action_ids))
             transition_facts))
      policy.required_transitions
  in
  let exact_variables label expected actual =
    let length = add_int builder (label ^ ".length") (List.length actual) in
    eq length (smt_int (List.length expected))
    :: List.mapi
         (fun index actual_value ->
           match List.nth_opt expected index with
           | None -> eq actual_value actual_value
           | Some wanted -> eq actual_value (smt_int (intern builder wanted)))
         actual
  in
  let fault_facts =
    List.mapi
      (fun index (fault : Run_topology.fault_event) ->
        let prefix = Printf.sprintf "sqlite.fault.%d" index in
        let text field value =
          fst (add_string builder (prefix ^ "." ^ field) value) in
        { sqlite_fault_id = text "id" fault.stable_id;
          sqlite_fault_owner = text "owner" fault.component_id;
          sqlite_fault_format_length =
            add_int builder (prefix ^ ".format-length")
              (String.length fault.format) })
      authority.fault_events
  in
  let gate_facts =
    List.mapi
      (fun index (gate : Run_topology.gate_command) ->
        let prefix = Printf.sprintf "sqlite.gate.%d" index in
        let text field value =
          fst (add_string builder (prefix ^ "." ^ field) value) in
        { sqlite_gate_id = text "id" gate.stable_id;
          sqlite_gate_owner = text "owner" gate.component_id;
          sqlite_gate_intent_length =
            add_int builder (prefix ^ ".intent-length")
              (String.length gate.intent_id) })
      authority.gate_commands
  in
  let activity_facts =
    List.mapi
      (fun index (activity : Run_topology.declarative_activity) ->
        let prefix = Printf.sprintf "sqlite.activity.%d" index in
        let text field value =
          fst (add_string builder (prefix ^ "." ^ field) value) in
        let commands =
          List.mapi
            (fun command_index command ->
              text (Printf.sprintf "command.%d" command_index) command)
            activity.command_ids
        in
        let capabilities =
          List.mapi
            (fun capability_index capability ->
              text (Printf.sprintf "capability.%d" capability_index)
                capability)
            activity.required_capability_ids
        in
        let contexts =
          List.mapi
            (fun context_index context ->
              text (Printf.sprintf "context.%d" context_index) context)
            activity.context_requirement_ids
        in
        let miq_routes =
          List.mapi
            (fun route_index (route : Run_topology.miq_route) ->
              let route_field field value =
                text (Printf.sprintf "miq.%d.%s" route_index field) value
              in
              { sqlite_miq_selector =
                  route_field "selector" route.selector_id;
                sqlite_miq_capability =
                  route_field "capability" route.required_capability_id;
                sqlite_miq_agent =
                  route_field "agent" route.assigned_agent_id })
            activity.miq_routes
        in
        let effects =
          List.mapi
            (fun effect_index kind ->
              text (Printf.sprintf "effect.%d" effect_index)
                (effect_kind_id kind))
            activity.effect_kinds
        in
        let sqlite_activity_id = text "id" activity.stable_id in
        let sqlite_activity_selected =
          add_bool builder (prefix ^ ".selected")
            (activity.stable_id = authority.formal_policy.sqlite.activity_id)
        in
        add_line builder
          (Printf.sprintf "(assert (= %s (= %s %d)))"
             sqlite_activity_selected sqlite_activity_id
             (intern builder authority.formal_policy.sqlite.activity_id));
        { sqlite_activity_id; sqlite_activity_selected;
          sqlite_activity_bridge = text "bridge" activity.bridge_component_id;
          sqlite_activity_target = text "target" activity.target_component_id;
          sqlite_activity_target_state = text "target-state" activity.target_state;
          sqlite_activity_intent_length =
            add_int builder (prefix ^ ".intent-length")
              (String.length activity.intent);
          sqlite_activity_constraint_count =
            add_int builder (prefix ^ ".constraint-count")
              (List.length activity.constraints);
          sqlite_activity_criteria_count =
            add_int builder (prefix ^ ".criteria-count")
              (List.length activity.success_criteria);
          sqlite_activity_capabilities = capabilities;
          sqlite_activity_contexts = contexts;
          sqlite_activity_miq_routes = miq_routes;
          sqlite_activity_miq_count =
            add_int builder (prefix ^ ".miq-count")
              (List.length miq_routes);
          sqlite_activity_effects = effects;
          sqlite_activity_commands = commands })
      authority.activities
  in
  let selected_count label required_ids actual_ids =
    let required = List.map (fun id -> smt_int (intern builder id)) required_ids in
    add_line builder ("; relation " ^ label ^ ".selected-count");
    eq
      (bool_sum (List.map (fun actual -> membership actual required) actual_ids))
      (smt_int (List.length required_ids))
  in
  let required_once label required_ids actual_ids =
    List.map
      (fun required_id ->
        add_line builder ("; relation " ^ label ^ ".required-once");
        let required = smt_int (intern builder required_id) in
        eq
          (bool_sum (List.map (fun actual -> eq actual required) actual_ids))
          "1")
      required_ids
  in
  let fault_ids = List.map (fun fact -> fact.sqlite_fault_id) fault_facts in
  let gate_ids = List.map (fun fact -> fact.sqlite_gate_id) gate_facts in
  let fault_conditions =
    selected_count "sqlite.faults" policy.fault_event_ids fault_ids
    :: required_once "sqlite.faults" policy.fault_event_ids fault_ids
  and gate_conditions =
    selected_count "sqlite.gates" policy.gate_command_ids gate_ids
    :: required_once "sqlite.gates" policy.gate_command_ids gate_ids
  in
  let activity_conditions =
    let closed_activity_conditions fact
        (expected : Run_topology.declarative_activity) =
      let miq_conditions =
        eq fact.sqlite_activity_miq_count
          (smt_int (List.length expected.miq_routes))
        :: List.concat
             (List.mapi
                (fun index actual ->
                  match List.nth_opt expected.miq_routes index with
                  | None ->
                      [ eq actual.sqlite_miq_selector actual.sqlite_miq_selector;
                        eq actual.sqlite_miq_capability actual.sqlite_miq_capability;
                        eq actual.sqlite_miq_agent actual.sqlite_miq_agent ]
                  | Some route ->
                      [ eq actual.sqlite_miq_selector
                          (smt_int (intern builder route.selector_id));
                        eq actual.sqlite_miq_capability
                          (smt_int
                             (intern builder route.required_capability_id));
                        eq actual.sqlite_miq_agent
                          (smt_int (intern builder route.assigned_agent_id)) ])
                fact.sqlite_activity_miq_routes)
      in
      [ eq fact.sqlite_activity_target_state
          (smt_int (intern builder expected.target_state)) ]
      @ exact_variables "sqlite.activity.capabilities"
          expected.required_capability_ids fact.sqlite_activity_capabilities
      @ exact_variables "sqlite.activity.contexts"
          expected.context_requirement_ids fact.sqlite_activity_contexts
      @ miq_conditions
      @ exact_variables "sqlite.activity.effects"
          (List.map effect_kind_id expected.effect_kinds)
          fact.sqlite_activity_effects
    in
    add_line builder "; relation sqlite.activity.selected-count";
    eq
      (bool_sum
         (List.map
            (fun fact -> fact.sqlite_activity_selected)
            activity_facts))
      "1"
    :: (List.concat_map
      (fun fact ->
        let expected =
          List.find_opt
            (fun (item : Run_topology.declarative_activity) ->
              item.stable_id = policy.activity_id)
            Run_topology.authority.activities
        in
        add_line builder "; relation sqlite.activity.selected-envelope";
        let sqlite_only =
          [ eq fact.sqlite_activity_bridge
              (smt_int
                 (intern builder
                    authority.formal_policy.execution.bridge_component_id));
            eq fact.sqlite_activity_target
              (smt_int (intern builder "runEventStore")) ]
          @ exact_variables "sqlite.activity.commands" policy.gate_command_ids
              fact.sqlite_activity_commands
          @ (match expected with
             | None -> [ "false" ]
             | Some expected -> closed_activity_conditions fact expected)
        in
        [ implies fact.sqlite_activity_selected (and_ sqlite_only) ])
      activity_facts)
  in
  let requirement_ids =
    List.mapi
      (fun index (item : Run_topology.requirement) ->
        fst
          (add_string builder
             (Printf.sprintf "sqlite.requirement.%d.id" index)
             item.stable_id))
      authority.requirements
  in
  let hazard_count =
    bool_sum
      (List.map
         (fun requirement_id ->
           eq requirement_id (smt_int (intern builder policy.hazard_requirement_id)))
         requirement_ids)
  in
  (* Every semantic condition consumes the SAME raw fact records used by the
     denominator checks above. There is no adjacent host reconstruction whose
     value could drift while the relation continues to pass. *)
  let event_store = smt_int (intern builder "runEventStore") in
  let machine_semantics =
    List.concat_map
      (fun fact ->
        [ eq fact.sqlite_machine_owner event_store;
          lt "0" fact.sqlite_state_count;
          membership fact.sqlite_initial_state fact.sqlite_state_ids ])
      machine_facts
  in
  let transition_semantics =
    List.concat_map
      (fun fact ->
        [ lt "0" fact.sqlite_transition_signal_length;
          lt "0" fact.sqlite_transition_action_count;
          or_
            (List.map
               (fun machine ->
                 and_
                   [ eq fact.sqlite_transition_machine machine.sqlite_machine_id;
                     membership fact.sqlite_transition_source machine.sqlite_state_ids;
                     membership fact.sqlite_transition_target machine.sqlite_state_ids ])
               machine_facts) ])
      transition_facts
  in
  let fault_semantics =
    let required =
      List.map (fun id -> smt_int (intern builder id)) policy.fault_event_ids
    in
    List.map
      (fun fact ->
        implies (membership fact.sqlite_fault_id required)
          (and_
             [ eq fact.sqlite_fault_owner event_store;
               lt "0" fact.sqlite_fault_format_length ]))
      fault_facts
  in
  let gate_semantics =
    let required =
      List.map (fun id -> smt_int (intern builder id)) policy.gate_command_ids
    in
    List.map
      (fun fact ->
        implies (membership fact.sqlite_gate_id required)
          (and_
             [ eq fact.sqlite_gate_owner event_store;
               lt "0" fact.sqlite_gate_intent_length ]))
      gate_facts
  in
  let activity_semantics =
    List.concat_map
      (fun fact ->
        [ lt "0" fact.sqlite_activity_intent_length;
          lt "0" fact.sqlite_activity_constraint_count;
          lt "0" fact.sqlite_activity_criteria_count ])
      activity_facts
  in
  let valid =
    and_ (machine_conditions @ transition_conditions @ fault_conditions
          @ gate_conditions @ activity_conditions
          @ machine_semantics @ transition_semantics
          @ fault_semantics @ gate_semantics
          @ activity_semantics
          @ [ eq hazard_count "1" ])
  in
  let stable_id, statement =
    match polarity with
    | Negated_law ->
        ("law.sqlite-finalization.negated",
         "The negation of explicit SQLite finalization and live close-failure recovery is impossible.")
    | Fact_mutant_control Drop_sqlite_reelect_action ->
        ("control.sqlite-finalization.false-witness",
         "Removing actor re-election from close recovery is a satisfiable dependability violation.")
    | Fact_mutant_control Invalid_sqlite_machine_owner ->
        ("control.sqlite-finalization.machine-owner-witness",
         "A lifecycle machine owned by anything but the event store is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_initial_state ->
        ("control.sqlite-finalization.initial-state-witness",
         "An initial state outside the machine's own states is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_transition_target ->
        ("control.sqlite-finalization.transition-target-witness",
         "A transition targeting a state the machine does not declare is a satisfiable violation.")
    | Fact_mutant_control Empty_sqlite_transition_signal ->
        ("control.sqlite-finalization.transition-signal-witness",
         "An empty transition signal is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_fault_owner ->
        ("control.sqlite-finalization.fault-owner-witness",
         "A fault event owned by anything but the event store is a satisfiable violation.")
    | Fact_mutant_control Empty_sqlite_fault_format ->
        ("control.sqlite-finalization.fault-format-witness",
         "A fault event with an empty format is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_gate_owner ->
        ("control.sqlite-finalization.gate-owner-witness",
         "A gate command owned by anything but the event store is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_gate_intent ->
        ("control.sqlite-finalization.gate-intent-witness",
         "A gate command with an empty intent is a satisfiable violation.")
    | Fact_mutant_control Empty_sqlite_transition_actions ->
        ("control.sqlite-finalization.transition-actions-witness",
         "A lifecycle transition with no action is a satisfiable violation.")
    | Fact_mutant_control Empty_sqlite_activity_intent ->
        ("control.sqlite-finalization.activity-intent-witness",
         "A declarative activity with an empty intent is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_activity_contract ->
        ("control.sqlite-finalization.activity-contract-witness",
         "A declarative activity with no constraints is a satisfiable violation.")
    | Fact_mutant_control Empty_sqlite_activity_success_criteria ->
        ("control.sqlite-finalization.activity-success-witness",
         "A declarative activity with no success criteria is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_activity_target_state ->
        ("control.sqlite-finalization.activity-target-state-witness",
         "A substituted declarative target state is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_activity_capabilities ->
        ("control.sqlite-finalization.activity-capabilities-witness",
         "A declarative activity with a substituted capability set is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_activity_context ->
        ("control.sqlite-finalization.activity-context-witness",
         "A declarative activity with a substituted context requirement set is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_activity_miq ->
        ("control.sqlite-finalization.activity-miq-witness",
         "A declarative activity with a substituted MIQ route is a satisfiable violation.")
    | Fact_mutant_control Invalid_sqlite_activity_effects ->
        ("control.sqlite-finalization.activity-effects-witness",
         "A declarative activity with a substituted effect denominator is a satisfiable violation.")
    | _ -> invalid_arg "sqlite_query: wrong mutant"
  in
  make_query ~stable_id ~requirement_id:"HZ-SQL-FIN-01" ~statement
    ~law:Sqlite_dependability ~polarity builder (not_ valid)

let sqlite_query polarity =
  sqlite_query_for_authority Run_topology.authority polarity

let pair theorem control = [ theorem Negated_law; control ]

let canonical =
  pair fpp_query
    (fpp_query (Fact_mutant_control Inject_fpp_cmp_01_passive_async))
  @ pair metric_query
      (metric_query (Fact_mutant_control Duplicate_metric_mapping))
  @ pair id_windows_query
      (id_windows_query (Fact_mutant_control Overlap_instance_window))
  (* the two omissions independent review named: a model can be internally
     disjoint and still collide with another owner, and an unbounded
     integer never overflows unless a maximum is a fact in the query *)
  @ [ id_windows_query (Fact_mutant_control Overlap_external_window);
      id_windows_query (Fact_mutant_control Overflow_instance_window);
      id_windows_query (Fact_mutant_control Mismatch_window_model_name);
      id_windows_query (Fact_mutant_control Remove_window_allocation);
      id_windows_query (Fact_mutant_control Remove_window_component);
      id_windows_query (Fact_mutant_control Change_window_observed_base);
      id_windows_query (Fact_mutant_control Include_unregistered_actual_window) ]
  @ pair execution_query
      (execution_query (Fact_mutant_control Add_execution_bypass))
  @ pair ui_query (ui_query (Fact_mutant_control Add_ui_admission_edge))
  @ pair mbse_query (mbse_query (Fact_mutant_control Drop_turtle_edge))
  @ [ mbse_query (Fact_mutant_control Drop_repository_action);
      mbse_query (Fact_mutant_control Duplicate_repository_action);
      mbse_query (Fact_mutant_control Substitute_repository_action_work);
      mbse_query (Fact_mutant_control Reorder_repository_actions) ]
  @ pair sqlite_query
      (sqlite_query (Fact_mutant_control Drop_sqlite_reelect_action))
  (* every machine, initial-state, transition, fault, gate and activity
     invariant the source validator enforces and the formula did not *)
  @ [ sqlite_query (Fact_mutant_control Invalid_sqlite_machine_owner);
      sqlite_query (Fact_mutant_control Invalid_sqlite_initial_state);
      sqlite_query (Fact_mutant_control Invalid_sqlite_transition_target);
      sqlite_query (Fact_mutant_control Empty_sqlite_transition_signal);
      sqlite_query (Fact_mutant_control Invalid_sqlite_fault_owner);
      sqlite_query (Fact_mutant_control Empty_sqlite_fault_format);
      sqlite_query (Fact_mutant_control Invalid_sqlite_gate_owner);
      sqlite_query (Fact_mutant_control Invalid_sqlite_gate_intent);
      sqlite_query (Fact_mutant_control Empty_sqlite_transition_actions);
      sqlite_query (Fact_mutant_control Empty_sqlite_activity_intent);
      sqlite_query (Fact_mutant_control Invalid_sqlite_activity_contract);
      sqlite_query (Fact_mutant_control Empty_sqlite_activity_success_criteria);
      sqlite_query (Fact_mutant_control Invalid_sqlite_activity_target_state);
      sqlite_query (Fact_mutant_control Invalid_sqlite_activity_capabilities);
      sqlite_query (Fact_mutant_control Invalid_sqlite_activity_context);
      sqlite_query (Fact_mutant_control Invalid_sqlite_activity_miq);
      sqlite_query (Fact_mutant_control Invalid_sqlite_activity_effects) ]

module For_test = struct
  let sqlite_query_for_authority = sqlite_query_for_authority
  let mbse_query_for_authority = mbse_query_for_authority
end

let fpp_probe_smt2 () =
  match !fpp_resolver_probe with
  | Some query -> query
  | None -> invalid_arg "canonical FPP resolver probe is absent"

let contains text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index =
    index + width <= length
    && (String.sub text index width = needle || loop (index + 1))
  in
  width > 0 && loop 0

let validate_query item =
  let gaps = ref [] in
  let add gap = gaps := gap :: !gaps in
  let marker =
    match item.polarity with Negated_law -> "none"
    | Fact_mutant_control mutant -> mutant_id mutant
  in
  if not (contains item.smt2 "; relational-authority-v1") then
    add "relational authority marker is missing";
  if not (contains item.smt2 ("; law " ^ law_id item.law)) then
    add "law marker differs";
  if not (contains item.smt2 ("; fact-mutant " ^ marker)) then
    add "fact-mutant marker differs";
  if contains item.smt2 "(assert (= violation true))"
     || contains item.smt2 "(assert (= violation false))"
  then add "host-precomputed violation Boolean is forbidden";
  if not (contains item.smt2 ("; facts-digest " ^ item.facts_digest)) then
    add "facts digest is not script-bound";
  if not (contains item.smt2 ("; relation-digest " ^ item.relation_digest)) then
    add "relation digest is not script-bound";
  if not (contains item.smt2 "(set-logic QF_LIA)"
          && contains item.smt2 "(check-sat)")
  then add "relational query is incomplete";
  begin match List.find_opt
      (fun (canonical_item : query) ->
        String.equal canonical_item.stable_id item.stable_id)
      canonical
  with
  | None -> add "relational query stable id is not canonical"
  | Some canonical_item when canonical_item <> item ->
      add "relational query differs from exact canonical derivation"
  | Some _ -> ()
  end;
  List.rev !gaps

let expected_ids =
  [ "law.fpp-valid.negated"; "control.fpp-valid.fpp-cmp-01-witness";
    "law.metric-total.negated"; "control.metric-total.false-witness";
    "law.id-windows.negated"; "control.id-windows.false-witness";
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

let validate_campaign queries =
  let gaps = ref [] in
  let add gap = gaps := gap :: !gaps in
  if List.map (fun item -> item.stable_id) queries <> expected_ids then
    add "relational obligation order or denominator differs";
  List.iter
    (fun item ->
      List.iter (fun gap -> add (item.stable_id ^ ": " ^ gap))
        (validate_query item))
    queries;
  let ids = List.map (fun item -> item.stable_id) queries in
  if List.length ids <> List.length (List.sort_uniq String.compare ids) then
    add "relational obligation ids are not unique";
  List.rev !gaps

let campaign_digest =
  canonical
  |> List.concat_map (fun item ->
         [ item.stable_id; item.requirement_id; item.facts_digest;
           item.relation_digest; digest item.smt2 ])
  |> digest_fields "run-formal-campaign-v1"

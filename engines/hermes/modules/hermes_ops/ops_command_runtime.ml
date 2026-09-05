let count_kind kind =
  List.length
    (List.filter
       (fun (declaration : Ops_capability.declaration) -> declaration.kind = kind)
       Ops_capability.all)

let surface_blockers () =
  Ops_capability.all
  |> List.concat_map (fun (declaration : Ops_capability.declaration) ->
         declaration.surfaces
         |> List.filter_map (fun (surface, applicability) ->
                match applicability with
                | Ops_capability.Applicable -> None
                | Ops_capability.Not_applicable reason ->
                    Some
                      (`Assoc
                        [ ("declaration", `String declaration.id);
                          ("surface", `String (Ops_capability.string_of_surface surface));
                          ("reason", `String reason) ])))

let debug_integration_gaps () =
  let known_capabilities =
    List.map (fun (item : Ops_capability.declaration) -> item.id)
      Ops_capability.all
  in
  let known_configuration =
    List.map (fun (item : Ops_config.element) -> item.key) Ops_config.elements
  in
  let gaps = ref (Run_fpp_authority.debug_mapping_gaps ()) in
  let add message = gaps := message :: !gaps in
  List.iter
    (fun (intent : Debug_intent.t) ->
      if Option.is_none (Module_intent.find intent.target_module_id) then
        add
          (Printf.sprintf "%s targets unknown module interface %s"
             intent.stable_id intent.target_module_id);
      List.iter
        (fun id ->
          if not (List.mem id known_capabilities) then
            add
              (Printf.sprintf "%s references unknown capability %s"
                 intent.stable_id id))
        intent.capability_ids;
      List.iter
        (fun id ->
          if not (List.mem id known_configuration) then
            add
              (Printf.sprintf "%s references undeclared configuration %s"
                 intent.stable_id id))
        intent.configuration_ids;
      match intent.effect_policy with
      | Debug_intent.Pure_diagnosis -> ()
      | Corrective_via_bridge activity ->
          if not (List.mem activity known_capabilities) then
            add
              (Printf.sprintf "%s references unknown bridge activity %s"
                 intent.stable_id activity))
    Debug_intent.all;
  List.rev !gaps

let metrics_json () =
  let coverage = Feature_model.coverage () in
  let fpp_gaps = Run_fpp_authority.validate () in
  let fpp_mapping_gaps = Run_fpp_authority.module_mapping_gaps () in
  let debug_gaps =
    Debug_intent.validate Debug_intent.all @ debug_integration_gaps ()
  in
  let module_fpp_mapped =
    List.length
      (List.filter
         (fun (item : Module_intent.t) ->
           match item.fpp with Module_intent.Fpp_components _ -> true | _ -> false)
         Module_intent.all)
  in
  `Assoc
    [ ("authority_declarations", `Int (List.length Ops_capability.all));
      ("governance_obligations", `Int (List.length Ops_governance.obligations));
      ("governance_validation_gaps", `Int (List.length (Ops_governance.validate ())));
      ("surface_blockers", `Int (List.length (surface_blockers ())));
      ("model_elements", `Int coverage.total);
      ("model_verified", `Int coverage.verified);
      ("model_gaps", `Int coverage.declared_only);
      ("model_dangling", `Int (List.length (Feature_model.dangling_dependencies ())));
      ("governance_ontology_nodes", `Int (List.length Ops_governance_model.nodes));
      ("governance_ontology_edges", `Int (List.length Ops_governance_model.edges));
      ("governance_mbse_gaps", `Int (List.length (Ops_mbse.validate ())));
      ("fpp_validation_gaps", `Int (List.length fpp_gaps));
      ("fpp_model_total", `Int (List.length Run_fpp_authority.all));
      ("fpp_portfolio_digest", `String Run_fpp_authority.source_digest);
      ("module_interface_total", `Int (List.length Module_intent.all));
      ("module_fpp_mapped", `Int module_fpp_mapped);
      ("module_fpp_mapping_gaps", `Int (List.length fpp_mapping_gaps));
      ("debug_intent_total", `Int (List.length Debug_intent.all));
      ("debug_validation_gaps", `Int (List.length debug_gaps));
      ("debug_authority_digest", `String Debug_intent.source_digest);
      ("debug_runtime_measurements_status", `String "Unavailable_observed");
      ("debug_runtime_measurement_channels",
       `List
         (List.map
            (fun (item : Run_topology.channel) -> `String item.fpp_name)
            Run_topology.debug_runtime_channels));
      ("fast_suites_discovered", `Int (List.length (Ops_verify.discover_suites Ops_verify.Fast)));
      ("full_suites_discovered", `Int (List.length (Ops_verify.discover_suites Ops_verify.Full)));
      ("metric_channels",
       `List
         (List.map
            (fun (item : Ops_governance.obligation) -> `String item.metric)
            Ops_governance.obligations));
      ("operations_fpp_channels",
       `List
         (List.map
            (fun (item : Run_topology.channel) -> `String item.fpp_name)
            Run_topology.authority.channels)) ]

let inventory_json () =
  `Assoc
    [ ("rules", `Int (count_kind Ops_capability.Rule));
      ("skills", `Int (count_kind Ops_capability.Skill));
      ("superpowers", `Int (count_kind Ops_capability.Superpower));
      ("agents", `Int (count_kind Ops_capability.Agent));
      ("capabilities", `Int (count_kind Ops_capability.Capability));
      ("sops", `Int (count_kind Ops_capability.Sop));
      ("activities", `Int (count_kind Ops_capability.Activity));
      ("module_interfaces", `Int (List.length Module_intent.all));
      ("dune_libraries", `Int (List.length Stanza.all));
      ("fpp_models", `Int (List.length Run_fpp_authority.all));
      ("module_intent_digest", `String Module_intent.source_digest);
      ("fpp_portfolio_digest", `String Run_fpp_authority.source_digest);
      ("debug_intents", `Int (List.length Debug_intent.all));
      ("debug_authority_digest", `String Debug_intent.source_digest);
      ("governance_obligations", `Int (List.length Ops_governance.obligations));
      ("surface_blockers", `List (surface_blockers ())) ]

let mbse_result () =
  let sysml = Feature_model.sysml_v2 () in
  let oml = Feature_model.oml_ttl () in
  let mms = Feature_model.mms_json () in
  let governance_sysml = Ops_mbse.sysml_v2 () in
  let governance_oml = Ops_mbse.oml_owl () in
  let governance_mms = Ops_mbse.openmbee_mms () in
  let governance_gaps = Ops_mbse.validate () in
  let operations_sysml = Run_mbse.sysml_v2 () in
  let operations_oml = Run_mbse.oml_owl () in
  let operations_mms = Run_mbse.openmbee_mms () in
  let operations_fpp = Run_mbse.fpp_dictionary () in
  let operations_gaps = Run_mbse.validate () in
  let gaps = Feature_model.model_gaps () in
  let dangling = Feature_model.dangling_dependencies () in
  let report =
    `Assoc
      [ ("sysml_bytes", `Int (String.length sysml));
        ("oml_bytes", `Int (String.length oml));
        ("openmbee_mms_bytes", `Int (String.length mms));
        ("governance_sysml_bytes", `Int (String.length governance_sysml));
        ("governance_oml_bytes", `Int (String.length governance_oml));
        ("governance_openmbee_mms_bytes", `Int (String.length governance_mms));
        ("operations_sysml_bytes", `Int (String.length operations_sysml));
        ("operations_oml_bytes", `Int (String.length operations_oml));
        ("operations_openmbee_mms_bytes", `Int (String.length operations_mms));
        ("operations_fpp_dictionary_bytes", `Int (String.length operations_fpp));
        ("operations_source_digest", `String Run_topology.source_digest);
        ("governance_model_gaps", `Int (List.length governance_gaps));
        ("operations_model_gaps", `Int (List.length operations_gaps));
        ("model_gaps", `Int (List.length gaps));
        ("dangling_dependencies", `Int (List.length dangling));
        ("projection_nonempty",
         `Bool
           (sysml <> "" && oml <> "" && mms <> ""
            && governance_sysml <> "" && governance_oml <> "" && governance_mms <> ""
            && operations_sysml <> "" && operations_oml <> "" && operations_mms <> ""
            && operations_fpp <> "")) ]
    |> Yojson.Safe.to_string
  in
  if sysml = "" || oml = "" || mms = "" || governance_sysml = ""
     || governance_oml = "" || governance_mms = "" || operations_sysml = ""
     || operations_oml = "" || operations_mms = "" || operations_fpp = ""
  then Error ("MBSE projection empty: " ^ report)
  else if dangling <> [] || gaps <> [] || governance_gaps <> [] || operations_gaps <> [] then
    Error ("MBSE completion blocked: " ^ report)
  else Ok report

let fpp_result () =
  let gaps = Run_fpp_authority.validate () in
  let report =
    match Run_fpp_authority.receipt_json () with
    | `Assoc fields ->
        `Assoc
          (fields
           @ [ ("validation_gaps", `List (List.map (fun gap -> `String gap) gaps));
               ("verdict", `String (if gaps = [] then "Verified" else "Failed_observed")) ])
    | value -> value
  in
  if gaps = [] then
    Ok (Yojson.Safe.to_string report)
  else
    Error (Yojson.Safe.to_string report)

let explain target =
  match List.find_opt (fun (d : Ops_capability.declaration) -> d.id = target) Ops_capability.all with
  | Some declaration ->
      Ok
        (Printf.sprintf "id=%s\nkind=%s\npurpose=%s\nauthority=%s\nowner=%s\n"
           declaration.id (Ops_capability.string_of_kind declaration.kind)
           declaration.purpose declaration.authority declaration.owner)
  | None ->
      begin match Module_intent.find target with
      | Some item ->
          Ok
            (Printf.sprintf
               "id=%s\nowner=%s\npurpose=%s\neffect=%s\nlibraries=%d\n"
               item.stable_id item.owner_directory item.purpose
               (Module_intent.string_of_effect_posture item.effect_posture)
               (List.length item.libraries))
      | None ->
          begin match Ops_governance.find_obligation target with
          | Some item -> Ok (Ops_governance.render_obligation item)
          | None -> Error ("unknown declaration, module interface, or obligation: " ^ target)
          end
      end

let debug_result target =
  match Debug_intent.find target with
  | None -> Error ("unknown debugging intent: " ^ target)
  | Some item ->
      let effect_policy = match item.Debug_intent.effect_policy with
        | Debug_intent.Pure_diagnosis -> `String "pure-diagnosis"
        | Corrective_via_bridge activity ->
            `Assoc [ ("kind", `String "corrective-via-run-swarm-bridge");
                     ("activity", `String activity);
                     ("availability", `String "Unavailable_observed") ]
      in
      let bounds = item.dependability.Debug_dependability.bounds in
      Ok
        (`Assoc
          [ ("authority", `String "Debug_intent.all");
            ("authority_digest", `String Debug_intent.source_digest);
            ("stable_id", `String item.stable_id);
            ("failure_family", `String item.failure_family);
            ("objective", `String item.objective);
            ("target_module_id", `String item.target_module_id);
            ("protocol_stage", `String "declared");
            ("symptom_patterns", `List (List.map (fun value -> `String value) item.symptom_patterns));
            ("constraints", `List (List.map (fun value -> `String value) item.constraints));
            ("success_criteria", `List (List.map (fun value -> `String value) item.success_criteria));
            ("path",
             `List (List.map (fun coordinate ->
               `String (Ops_capability.string_of_level coordinate.Ops_capability.level
                        ^ "/" ^ Ops_capability.string_of_phase coordinate.phase)) item.path));
            ("hypothesis_total", `Int (List.length item.hypotheses));
            ("hypotheses",
             `List (List.map (fun hypothesis ->
               `Assoc [ ("id", `String hypothesis.Debug_ontology.hypothesis_id);
                        ("statement", `String hypothesis.statement);
                        ("rca_origin", `String (Ops_capability.string_of_rca_origin hypothesis.rca_origin));
                        ("predictions", `List (List.map (fun value -> `String value) hypothesis.predictions)) ])
               item.hypotheses));
            ("next_measurement",
             `Assoc [ ("id", `String item.next_measurement.discriminator_id);
                      ("measurement", `String item.next_measurement.measurement);
                      ("maximum_cost", `Int item.next_measurement.maximum_cost) ]);
            ("dependability",
             `Assoc [ ("reproduction", `String item.dependability.reproduction);
                      ("failure_signature", `String item.dependability.failure_signature);
                      ("timeout_ms", `Int bounds.timeout_ms);
                      ("maximum_memory_bytes", `Intlit (Int64.to_string bounds.maximum_memory_bytes));
                      ("maximum_output_bytes", `Int bounds.maximum_output_bytes);
                      ("maximum_attempts", `Int bounds.maximum_attempts);
                      ("required_controls", `List (List.map (fun value -> `String value) item.dependability.required_controls));
                      ("mutation_targets", `List (List.map (fun value -> `String value) item.dependability.mutation_targets));
                      ("verify_original", `Bool item.dependability.verify_original);
                      ("verify_dependency_cone", `Bool item.dependability.verify_dependency_cone) ]);
            ("fpp",
             `Assoc [ ("owner", `String item.fpp.owner);
                      ("component", `String item.fpp.component);
                      ("channel", `String item.fpp.channel) ]);
            ("effect_policy", effect_policy);
            ("correction_available", `Bool false);
            ("rca_rule", `String "only an established Implementation origin may deny parity") ]
         |> Yojson.Safe.to_string)

let invocation_action = function
  | "capability.verify-fast" | "capability.verify-full"
  | "sop.fast-ooda-completion" | "activity.act-sop" -> Some Ops_command.Act
  | "capability.formal-check" -> Some Formal_check
  | "capability.mbse-sysml" | "capability.mbse-oml"
  | "capability.mbse-openmbee" -> Some Mbse_check
  | "capability.fpp-check" -> Some Fpp_check
  | "capability.metrics-observe" -> Some Metrics_observe
  | "capability.history-observe" -> Some History_observe
  | "capability.orientation-observe" -> Some Orientation_observe
  | "capability.debug-observe" | "sop.systematic-debugging" ->
      Some (Debug "debug.bridge-admission")
  | "activity.debug-correction" -> Some (Debug "debug.bridge-admission")
  | "activity.observe-inventory" -> Some Inventory
  | "activity.orient-gaps" -> Some Plan
  | "activity.decide-intent" -> Some Decide
  | "activity.verify-sqlite-dependability" -> Some Act
  | "capability.agent-surface-sync" | "capability.governance-check" -> Some Check
  | _ -> None

let run_verification profile =
  let report = Ops_verify.run ~profile () in
  let text, code = Ops_verify.render ~require_complete:true report in
  if code = 0 then Ok text else Error text

let rec invoke request target =
  match
    List.find_opt
      (fun (declaration : Ops_capability.declaration) -> declaration.id = target)
      Ops_capability.all
  with
  | None -> Error ("unknown invocation target: " ^ target)
  | Some { implementation = Ops_capability.Judgment_only reason; _ } ->
      Error ("judgment-only authority cannot be executed: " ^ reason)
  | Some { implementation = Command _; _ } ->
      begin match target with
      | "capability.verify-fast" -> run_verification Ops_verify.Fast
      | "capability.verify-full" | "sop.fast-ooda-completion" | "activity.act-sop" ->
          run_verification Ops_verify.Full
      | "activity.verify-sqlite-dependability" ->
          Error
            "activity.verify-sqlite-dependability is executable only through the admitted Run_swarm_bridge; generic Ops_command invocation is refused"
      | "activity.debug-correction" ->
          Error
            "activity.debug-correction is unavailable until an exact corrective action graph is admitted by Run_swarm_bridge"
      | _ ->
          begin match invocation_action target with
          | None -> Error ("declared command has no runtime mapping: " ^ target)
          | Some action -> execute_direct { request with action }
          end
      end

and execute_direct (request : Ops_command.request) =
  match request.action with
  | Ops_command.Inventory -> Ok (Yojson.Safe.to_string (inventory_json ()))
  | Plan ->
      Ok
        (`Assoc
          [ ("surface_blockers", `List (surface_blockers ()));
            ("model_gaps", `Int (List.length (Feature_model.model_gaps ())));
            ("model_gap_details",
             `List (List.map (fun gap -> `String gap) (Feature_model.model_gaps ())));
            ("governance_gaps", `List (List.map (fun gap -> `String gap) (Ops_governance.validate ())));
            ("governance_mbse_gaps",
             `List (List.map (fun gap -> `String gap) (Ops_mbse.validate ())));
            ("sop_steps", `Int (List.length Ops_governance.whole_system_sop)) ]
         |> Yojson.Safe.to_string)
  | Decide ->
      let intent : Sop_execution.declarative_intent =
        { goal = "Close every applicable whole-system governance obligation";
          constraints =
            [ "preserve ownership boundaries";
              "execute only real OCaml action closures";
              "reject skipped, stale, unavailable, or prose-only evidence";
              "require four-surface receipt equivalence" ];
          target_state =
            "all mandatory obligations Current at one source, configuration, and authority head";
          required_capabilities =
            [ "inventory"; "analysis"; "synthesis"; "verification";
              "formal-model-checking"; "audit" ] }
      in
      Ok
        (`Assoc
          [ ("goal", `String intent.goal);
            ("constraints", `List (List.map (fun value -> `String value) intent.constraints));
            ("target_state", `String intent.target_state);
            ("required_capabilities",
             `List (List.map (fun value -> `String value) intent.required_capabilities));
            ("model_gaps", `Int (List.length (Feature_model.model_gaps ())));
            ("governance_gaps", `Int (List.length (Ops_governance.validate ()))) ]
         |> Yojson.Safe.to_string)
  | Check ->
      let schema =
        Ops_capability_gate.validate ~root:"." @ Ops_governance.validate ()
      in
      let blockers = surface_blockers () in
      let model_gaps = Feature_model.model_gaps () in
      let source = Ops_observability.source_context ~root:"." in
      let current_execution =
        match Ops_completion_history.open_store Ops_command_service.default_history_location with
        | Error _ -> false
        | Ok store ->
            Fun.protect ~finally:(fun () -> Ops_completion_history.close store) (fun () ->
              match
                Ops_completion_history.has_current_success store ~source
                  ~action:"act" ~scope:"whole-system"
              with
              | Ok true -> true
              | Ok false | Error _ ->
                  begin match
                    Ops_completion_history.has_current_success store ~source
                      ~action:"run" ~scope:"whole-system"
                  with Ok value -> value | Error _ -> false
                  end)
      in
      if schema = [] && blockers = [] && model_gaps = [] && source.source_clean
         && current_execution
      then Ok "whole-system declaration, exact-head, and current execution checks passed"
      else
        Error
          (Printf.sprintf
             "completion blocked: schema=%d surfaces=%d model=%d source_clean=%b current_execution=%b"
             (List.length schema) (List.length blockers) (List.length model_gaps)
             source.source_clean current_execution)
  | Explain target -> explain target
  | Mbse_check -> mbse_result ()
  | Fpp_check -> fpp_result ()
  | Formal_check ->
      let report = Ops_formal.run () in
      let text, code = Ops_formal.render report in
      if code = 0 then Ok text else Error text
  | Metrics_observe -> Ok (Yojson.Safe.to_string (metrics_json ()))
  | Orientation_observe ->
      (* The durable orientation memory (R30). Absence is a DISCLOSED state,
         never an invented empty one: an agent asking before any pass has been
         recorded learns that, not a fabricated zero. *)
      let path = Ops_command_service.default_orientation_path in
      if not (Sys.file_exists path) then
        Ok (Yojson.Safe.to_string (`Assoc [ ("path", `String path); ("present", `Bool false) ]))
      else begin match Orientation_history.open_store path with
      | Error message -> Error ("orientation history unavailable: " ^ message)
      | Ok store ->
          Fun.protect ~finally:(fun () -> Orientation_history.close store) (fun () ->
            match (Orientation_history.state store, Orientation_history.counts store) with
            | Error message, _ | _, Error message ->
                Error ("orientation history unavailable: " ^ message)
            | Ok rows, Ok (state_n, history_n, passes) ->
                Ok
                  (`Assoc
                    [ ("path", `String path); ("present", `Bool true);
                      ("state_keys", `Int state_n); ("history_rows", `Int history_n);
                      ("passes", `Int passes);
                      ("state",
                       `Assoc
                         (List.map (fun (k, v, _, _) -> (k, `String v)) rows)) ]
                   |> Yojson.Safe.to_string))
      end
  | Debug target -> debug_result target
  | History_observe ->
      begin match Ops_completion_history.open_store Ops_command_service.default_history_location with
      | Error message -> Error ("completion history unavailable: " ^ message)
      | Ok store ->
          Fun.protect ~finally:(fun () -> Ops_completion_history.close store) (fun () ->
            match Ops_completion_history.counts store with
            | Error message -> Error ("completion history unavailable: " ^ message)
            | Ok counts ->
                let source = Ops_observability.source_context ~root:"." in
                Ok
                  (`Assoc
                    [ ("location_digest", `String
                         (Dependability_sqlite_location.reference_digest
                            Ops_command_service.default_history_location));
                      ("receipts", `Int counts.receipts);
                      ("observations", `Int counts.observations);
                      ("interactions", `Int counts.interactions);
                      ("source_revision", `String source.source_revision);
                      ("source_clean", `Bool source.source_clean);
                      ("configuration_digest", `String source.configuration_digest);
                      ("authority_digest", `String source.authority_digest) ]
                   |> Yojson.Safe.to_string))
      end
  | Act | Run ->
      run_verification Ops_verify.Full
  | Invoke target -> invoke request target

let execute (request : Ops_command.request) =
  let outcome = ref None in
  let step =
    { Sop_execution.step_id = "command-" ^ Ops_command.action_name request.action;
      name = "typed declarative command";
      assigned_agent = "agent_1";
      dependencies = [];
      action =
        (fun _ _ ->
          let result = execute_direct request in
          outcome := Some result;
          let payload = match result with Ok text | Error text -> text in
          (payload, (0, 0))) }
  in
  let execution = Sop_execution.execute_sop_workflow ~steps:[ step ] () in
  match !outcome, execution.step_results with
  | Some result, _ -> result
  | None, _ -> Error "Sop_execution returned without executing the command action"

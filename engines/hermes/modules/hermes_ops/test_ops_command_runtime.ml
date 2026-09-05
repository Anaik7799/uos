let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let request action scope = Ops_command.{ request_id = "runtime-test"; action; scope }
let json = function Ok text | Error text -> Yojson.Safe.from_string text

let int_member name value =
  match Yojson.Safe.Util.member name value with `Int n -> n | _ -> -1

let () =
  check "R1 inventory derives nonempty typed authority counts" (fun () ->
      let value = json (Ops_command_runtime.execute_direct (request Inventory Whole_system)) in
      int_member "rules" value = 31 && int_member "skills" value > 0
      && int_member "agents" value >= 2 && int_member "governance_obligations" value = 24
      && int_member "module_interfaces" value = 39
      && int_member "dune_libraries" value = 193
      && int_member "fpp_models" value = 5);
  check "R11 orientation-observe reads the durable store through the algebra" (fun () ->
      let value = json (Ops_command_runtime.execute_direct (request Orientation_observe Whole_system)) in
      (match Yojson.Safe.Util.member "path" value with
       | `String p -> p = Ops_command_service.default_orientation_path
       | _ -> false)
      && (match Yojson.Safe.Util.member "present" value with `Bool _ -> true | _ -> false));
  check "R2 plan exposes real current blockers and the executable SOP" (fun () ->
      let value = json (Ops_command_runtime.execute_direct (request Plan Whole_system)) in
      int_member "model_gaps" value > 0 && int_member "sop_steps" value = 5
      && Yojson.Safe.Util.member "surface_blockers" value = `List []);
  check "R3 completion check fails closed while required adapters or models are incomplete" (fun () ->
      Result.is_error (Ops_command_runtime.execute_direct (request Check Whole_system)));
  check "R3a decide emits a nonempty declarative intent without executing it" (fun () ->
      let value = json (Ops_command_runtime.execute_direct (request Decide Whole_system)) in
      Yojson.Safe.Util.member "goal" value <> `Null
      && Yojson.Safe.Util.member "target_state" value <> `Null
      && match Yojson.Safe.Util.member "required_capabilities" value with
         | `List capabilities -> List.length capabilities >= 5
         | _ -> false);
  check "R4 MBSE reports SysML OML OpenMBEE sizes and blocks on live model gaps" (fun () ->
      match Ops_command_runtime.execute_direct (request Mbse_check Data_plane) with
      | Ok _ -> false
      | Error text ->
          let prefix = "MBSE completion blocked: " in
          String.length text > String.length prefix
          && let value = Yojson.Safe.from_string
               (String.sub text (String.length prefix) (String.length text - String.length prefix)) in
             int_member "sysml_bytes" value > 10_000
             && int_member "oml_bytes" value > 10_000
             && int_member "openmbee_mms_bytes" value > 10_000
             && int_member "governance_sysml_bytes" value > 10_000
             && int_member "governance_oml_bytes" value > 10_000
             && int_member "governance_openmbee_mms_bytes" value > 10_000
             && int_member "governance_model_gaps" value = 0
             && int_member "model_gaps" value > 0);
  check "R5 FPP validation executes the exact five-owner portfolio including Wiki" (fun () ->
      match Ops_command_runtime.execute_direct (request Fpp_check Control_plane) with
      | Error _ -> false
      | Ok text ->
          let value = Yojson.Safe.from_string text in
          int_member "model_total" value = 5
          && int_member "model_valid" value = 5
          && int_member "module_interface_total" value = 39
          && int_member "module_mapping_gaps" value = 0
          && int_member "debug_intent_total" value = 9
          && int_member "debug_mapping_gaps" value = 0
          && Yojson.Safe.Util.member "model_owners" value
             = `List [ `String "Harness"; `String "Wiki"; `String "Ops_monitor";
                       `String "Completion"; `String "Operations" ]);
  check "R6 metrics are measured and enumerate all modeled channels" (fun () ->
      let value = Ops_command_runtime.metrics_json () in
      int_member "governance_obligations" value = 24
      && int_member "full_suites_discovered" value >= int_member "fast_suites_discovered" value
      && match Yojson.Safe.Util.member "metric_channels" value with
         | `List channels -> List.length channels = 24
         | _ -> false);
  check "R6a metrics derive FPP totals from the canonical portfolio" (fun () ->
      let value = Ops_command_runtime.metrics_json () in
      int_member "fpp_model_total" value = 5
      && int_member "module_interface_total" value = 39
      && int_member "module_fpp_mapping_gaps" value = 0);
  check "R7 the production executor routes the real action through Sop_execution" (fun () ->
      Ops_command_runtime.execute (request Inventory Whole_system)
      = Ops_command_runtime.execute_direct (request Inventory Whole_system));
  check "R8 explain resolves typed declarations and governance obligations" (fun () ->
      Result.is_ok (Ops_command_runtime.execute_direct (request (Explain "rule.R29") Control_plane))
      && Result.is_ok
           (Ops_command_runtime.execute_direct
              (request (Explain "module.hermes-ops") Control_plane))
      && Result.is_ok (Ops_command_runtime.execute_direct (request (Explain "GOV-09") Control_plane))
      && Result.is_error (Ops_command_runtime.execute_direct (request (Explain "ghost") Control_plane)));
  check "R9 every typed command declaration has a runtime invocation mapping" (fun () ->
      Ops_capability.all
      |> List.for_all (fun (declaration : Ops_capability.declaration) ->
             match declaration.implementation with
             | Ops_capability.Judgment_only _ -> true
             | Ops_capability.Command _ ->
                 Option.is_some (Ops_command_runtime.invocation_action declaration.id)));
  check "R9a the registered bridge activity cannot enter the generic runtime" (fun () ->
      match
        Ops_command_runtime.execute_direct
          (request (Invoke "activity.verify-sqlite-dependability") Control_plane)
      with
      | Ok _ -> false
      | Error text ->
          String.length text >= String.length "activity.verify-sqlite-dependability"
          && String.sub text 0 (String.length "activity.verify-sqlite-dependability")
             = "activity.verify-sqlite-dependability");
  check "R10 append-only completion history is queryable through the command algebra" (fun () ->
      match Ops_command_runtime.execute_direct (request History_observe Data_plane) with
      | Error _ -> false
      | Ok text ->
          let value = Yojson.Safe.from_string text in
          Yojson.Safe.Util.member "location_digest" value
          = `String
              (Dependability_sqlite_location.reference_digest
                 Ops_command_service.default_history_location)
          && Yojson.Safe.Util.member "path" value = `Null
          && int_member "receipts" value >= 0
          && int_member "observations" value >= 0
          && int_member "interactions" value >= 0);
  check "R12 typed debugging returns a declared intent and refuses unknown identity" (fun () ->
      match
        Ops_command_runtime.execute_direct
          (request (Debug "debug.formal-coverage-gap") Control_plane)
      with
      | Error _ -> false
      | Ok text ->
          let value = Yojson.Safe.from_string text in
          Yojson.Safe.Util.member "stable_id" value
            = `String "debug.formal-coverage-gap"
          && Yojson.Safe.Util.member "protocol_stage" value = `String "declared"
          && int_member "hypothesis_total" value >= 2
          && Result.is_error
               (Ops_command_runtime.execute_direct
                  (request (Debug "debug.ghost") Control_plane)));
  check "R13 debugging metrics derive from the typed registry" (fun () ->
      let value = Ops_command_runtime.metrics_json () in
      int_member "debug_intent_total" value = 9
      && int_member "debug_validation_gaps" value = 0
      && Yojson.Safe.Util.member "debug_runtime_measurements_status" value
         = `String "Unavailable_observed"
      && match Yojson.Safe.Util.member "debug_runtime_measurement_channels" value with
         | `List channels -> List.length channels = 12
         | _ -> false);
  check "R14 debugging references resolve through modules, config, capabilities, and FPP" (fun () ->
      Ops_command_runtime.debug_integration_gaps () = []
      && List.for_all
           (fun (intent : Debug_intent.t) ->
             Option.is_some (Module_intent.find intent.target_module_id))
           Debug_intent.all);

  Printf.printf "ops_command_runtime: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_command_runtime" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)

(* The BDD runner: executes every scenario in Fpp_usecases against the
   interpreter, the dictionary, and the connection graphs, printing
   Given/When/Then lines. A scenario is data; this runner is the only
   machinery. *)

let scenarios_run = ref 0
let steps_run = ref 0
let failures = ref 0

type context = {
  model : Fpp_model.model;
  machine : Fpp_model.state_machine option;
  mutable machine_state : Fpp_interp.machine_state option;
  mutable queue : Fpp_interp.queue;
  mutable last_dispatch :
    [ `Executed | `Enqueued | `Assert_failed | `Blocked | `Dropped | `Rejected | `None ];
  dictionary : (string * Yojson.Safe.t) list;  (* top-level assoc *)
  expanded : Fpp_model.connection list;
  direct : Fpp_model.connection list;
}

let dictionary_of model topology_name =
  match Fpp_model.to_dictionary model ~topology:topology_name with
  | Ok (`Assoc fields) -> fields
  | Ok _ -> []
  | Error e -> failwith ("dictionary: " ^ e)

let connections_of model topology_name =
  match
    List.find_opt
      (fun t -> t.Fpp_model.topo_name = topology_name)
      model.Fpp_model.topologies
  with
  | None -> ([], [])
  | Some topo ->
      let direct =
        List.concat_map
          (function
            | Fpp_model.Direct { connections; _ } -> connections
            | Fpp_model.Pattern _ -> [])
          topo.Fpp_model.graphs
      in
      let expanded =
        match Fpp_model.connections model topo with Ok c -> c | Error _ -> direct
      in
      (expanded, direct)

let start (s : Fpp_usecases.scenario) =
  let expanded, direct = connections_of s.model s.topology_name in
  let machine_state =
    match s.machine with
    | None -> None
    | Some m -> (
        match Fpp_interp.init m with
        | Ok st -> Some st
        | Error e -> failwith ("init: " ^ e))
  in
  { model = s.model; machine = s.machine; machine_state;
    queue = Fpp_interp.empty_queue ~capacity:s.queue_capacity;
    last_dispatch = `None;
    dictionary = dictionary_of s.model s.topology_name;
    expanded; direct }

let entries context key =
  match List.assoc_opt key context.dictionary with Some (`List l) -> l | _ -> []

let entry_field entry name =
  match entry with `Assoc f -> List.assoc_opt name f | _ -> None

let base_of context instance =
  match
    List.find_opt
      (fun i -> i.Fpp_model.inst_name = instance)
      context.model.Fpp_model.instances
  with
  | Some i -> Some i.Fpp_model.base_id
  | None -> None

let run_step context step : string * bool =
  match (step : Fpp_usecases.step) with
  | When_signal (signal, guards) -> (
      let label = Printf.sprintf "When signal %s" signal in
      match (context.machine, context.machine_state) with
      | Some machine, Some state -> (
          match Fpp_interp.dispatch ~machine ~guards state signal with
          | Ok state' ->
              context.machine_state <- Some state';
              (label, true)
          | Error e -> (label ^ " (" ^ e ^ ")", false))
      | _ -> (label ^ " (no machine in scenario)", false))
  | Then_state expected -> (
      let label = Printf.sprintf "Then the machine is in %s" expected in
      match context.machine_state with
      | Some s -> (label, s.Fpp_interp.current = expected)
      | None -> (label, false))
  | Then_log_includes action -> (
      let label = Printf.sprintf "Then action %s has run" action in
      match context.machine_state with
      | Some s -> (label, List.mem action s.Fpp_interp.log)
      | None -> (label, false))
  | When_command (instance, relative) -> (
      let label = Printf.sprintf "When command %s+0x%X is sent" instance relative in
      match base_of context instance with
      | None ->
          context.last_dispatch <- `Rejected;
          (label ^ " (unknown instance)", true)
      | Some base -> (
          match
            Fpp_interp.send_command context.model ~instance ~opcode:(base + relative)
              ~queue:(Some context.queue)
          with
          | Ok Fpp_interp.Executed ->
              context.last_dispatch <- `Executed;
              (label, true)
          | Ok (Fpp_interp.Enqueued q) ->
              context.queue <- q;
              context.last_dispatch <- `Enqueued;
              (label, true)
          | Ok (Fpp_interp.Dropped q) ->
              context.queue <- q;
              context.last_dispatch <- `Dropped;
              (label, true)
          | Ok Fpp_interp.Blocked ->
              context.last_dispatch <- `Blocked;
              (label, true)
          | Ok Fpp_interp.Assert_failed ->
              context.last_dispatch <- `Assert_failed;
              (label, true)
          | Error _ ->
              context.last_dispatch <- `Rejected;
              (label, true)))
  | Then_dispatch expected ->
      let show = function
        | `Executed -> "executed" | `Enqueued -> "enqueued"
        | `Assert_failed -> "assert-failed" | `Blocked -> "blocked"
        | `Dropped -> "dropped" | `Rejected -> "rejected" | `None -> "none"
      in
      ( Printf.sprintf "Then the dispatch is %s" (show expected),
        context.last_dispatch = (expected :> [ `Executed | `Enqueued | `Assert_failed | `Blocked | `Dropped | `Rejected | `None ]) )
  | Then_event_severity (instance, event, severity) ->
      let name = instance ^ "." ^ event in
      ( Printf.sprintf "Then event %s has severity %s" name severity,
        List.exists
          (fun e ->
            entry_field e "name" = Some (`String name)
            && entry_field e "severity" = Some (`String severity))
          (entries context "events") )
  | Then_channel (instance, channel, update) ->
      let name = instance ^ "." ^ channel in
      ( Printf.sprintf "Then channel %s updates %s" name update,
        List.exists
          (fun c ->
            entry_field c "name" = Some (`String name)
            && entry_field c "telemetryUpdate" = Some (`String update))
          (entries context "telemetryChannels") )
  | Then_no_command_named fragment ->
      let contains haystack =
        let n = String.length fragment and h = String.length haystack in
        let rec go i = i + n <= h && (String.sub haystack i n = fragment || go (i + 1)) in
        go 0
      in
      ( Printf.sprintf "Then no command named *%s* exists (read-only law)" fragment,
        not
          (List.exists
             (fun c ->
               match entry_field c "name" with
               | Some (`String name) -> contains name
               | _ -> false)
             (entries context "commands")) )
  | Then_connection (from_i, to_i) ->
      ( Printf.sprintf "Then a connection runs %s -> %s" from_i to_i,
        List.exists
          (fun (c : Fpp_model.connection) ->
            c.Fpp_model.from_.Fpp_model.ep_instance = from_i
            && c.Fpp_model.to_.Fpp_model.ep_instance = to_i)
          context.expanded )
  | Then_no_connection (from_set, to_set) ->
      ( "Then no direct connection crosses the forbidden boundary",
        not
          (List.exists
             (fun (c : Fpp_model.connection) ->
               List.mem c.Fpp_model.from_.Fpp_model.ep_instance from_set
               && List.mem c.Fpp_model.to_.Fpp_model.ep_instance to_set)
             context.direct) )
  | Then_law (label, law) -> ("Then " ^ label, law ())

let run_scenario (s : Fpp_usecases.scenario) =
  incr scenarios_run;
  Printf.printf "Scenario: %s\n  Given %s\n" s.name s.given;
  match start s with
  | exception e ->
      incr failures;
      Printf.printf "  SETUP FAILED: %s\n" (Printexc.to_string e)
  | context ->
      List.iter
        (fun step ->
          incr steps_run;
          match run_step context step with
          | label, true -> Printf.printf "  %s\n" label
          | label, false ->
              incr failures;
              Printf.printf "  %s  <-- FAILED\n" label
          | exception e ->
              incr failures;
              Printf.printf "  step raised %s  <-- FAILED\n" (Printexc.to_string e))
        s.steps

let () =
  List.iter run_scenario Fpp_usecases.all;
  Printf.printf "\nbdd: %d scenarios, %d steps, %d failures\n" !scenarios_run
    !steps_run !failures;
  (* The catalog must actually cover the space: enough generic use cases,
     and every harness workflow family. An empty catalog is a failure. *)
  if List.length Fpp_usecases.generic < 8 then begin
    print_endline "FAILED: fewer than 8 generic use cases";
    incr failures
  end;
  if List.length Fpp_usecases.workflows < 12 then begin
    print_endline "FAILED: fewer than 12 harness workflows mapped";
    incr failures
  end;
  if List.length Fpp_usecases.codegen < 6 then begin
    print_endline "FAILED: fewer than 6 code-generation scenarios";
    incr failures
  end;
  (* passed is steps minus failures: setup and catalog failures make it a
     conservative undercount, never an overcount; observe clamps negatives. *)
  let self =
    Suite_telemetry.observe ~suite:"test_fpp_bdd" ~passed:(!steps_run - !failures)
      ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)

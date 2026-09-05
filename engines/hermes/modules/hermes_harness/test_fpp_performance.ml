(* Performance and scalability for the FPP/formal layer and the control
   plane. Deterministic synthetic data, generous absolute wall-clock
   bounds (CI-safe), plus growth-RATIO laws with wide margins: a 4x input
   must not cost more than ~30x, which passes any O(n log n) or modest
   O(n^2) implementation and trips an accidental O(n^3). Every measured
   time is printed — the numbers are the observability, the bounds are
   the teeth. *)

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    print_endline ("FAILED: " ^ name)
  end

let time label f =
  let t0 = Unix.gettimeofday () in
  let result = f () in
  let dt = Unix.gettimeofday () -. t0 in
  Printf.printf "  %-52s %8.1f ms\n" label (dt *. 1000.);
  (result, dt)

open Fpp_model

(* ------------------------------------------------------------ builders *)

let data_port = { port_name = "DP"; params = [ ("v", Prim U32) ]; return_type = None }

let bulk_component i =
  { comp_name = Printf.sprintf "p%d" i; kind = Passive;
    ports = [ General { name = "out"; port = "DP"; direction = Output; count = 2 } ];
    commands =
      [ { cmd_name = "GO"; opcode = 0; cmd_kind = Sync_cmd; cmd_params = [] } ];
    events =
      [ { event_name = "E"; event_id = 1; severity = Diagnostic; format = "e";
          throttle = None } ];
    channels =
      [ { chan_name = "c"; chan_id = 2; chan_type = Prim U32; update = Always;
          chan_format = None; low = None; high = None } ];
    parameters = []; records = []; containers = []; internal_ports = [];
    machines = []; matched = [] }

let bulk_model n =
  let components = List.init n bulk_component in
  let instances =
    List.mapi
      (fun i (c : component) ->
        { inst_name = Printf.sprintf "i%d" i; of_component = c.comp_name;
          base_id = 0x100 + (i * 8); queue_size = None; stack_size = None;
          inst_priority = None; cpu = None })
      components
  in
  { model_name = "Bulk"; type_defs = []; port_defs = [ data_port ]; constants = [];
    components; machines = []; instances;
    topologies =
      [ { topo_name = "t"; members = List.map (fun i -> i.inst_name) instances;
          graphs =
            [ Direct
                { graph_name = "chain";
                  connections =
                    List.init (n - 1) (fun i ->
                        { from_ =
                            { ep_instance = Printf.sprintf "i%d" i; ep_port = "out";
                              ep_index = Some 0 };
                          to_ =
                            { ep_instance = Printf.sprintf "i%d" (i + 1); ep_port = "out";
                              ep_index = None } }) } ] } ] }

(* Chain wiring out->out is invalid (input side is an output) — perfect:
   validation must DIAGNOSE at scale, which costs more than accepting. *)

(* -------------------------------------------------- validate scalability *)

let () =
  print_endline "== validate scalability ==";
  let (d100, t100) = time "validate, 100 components (diagnosing)" (fun () ->
      validate (bulk_model 100)) in
  let (d400, t400) = time "validate, 400 components (diagnosing)" (fun () ->
      validate (bulk_model 400)) in
  check "validation diagnoses at both sizes (non-vacuous work)"
    (d100 <> [] && d400 <> []);
  check "validate(100) under 2s" (t100 < 2.0);
  check "validate(400) under 8s" (t400 < 8.0);
  check "validate growth ratio is sane (4x input, < 30x cost)"
    (t400 < 30.0 *. (max t100 0.001));
  let clean = { (bulk_model 400) with topologies = [] } in
  let (ok, t_clean) = time "validate, 400 components, clean model" (fun () ->
      validate clean = []) in
  check "the clean 400-component model validates clean under 4s" (ok && t_clean < 4.0)

(* -------------------------------------------------- emitter scalability *)

let () =
  print_endline "== emitters ==";
  let clean200 = { (bulk_model 200) with topologies = [ { topo_name = "t"; members = List.init 200 (Printf.sprintf "i%d"); graphs = [] } ] } in
  let (text, t_fpp) = time "to_fpp, 200 components" (fun () -> to_fpp clean200) in
  check "to_fpp(200) under 2s and non-trivial" (t_fpp < 2.0 && String.length text > 10_000);
  let (dict, t_dict) = time "to_dictionary, 200 instances" (fun () ->
      to_dictionary clean200 ~topology:"t") in
  check "to_dictionary(200) under 4s and Ok"
    (t_dict < 4.0 && match dict with Ok _ -> true | Error _ -> false);
  let (harness_dict, t_h) = time "to_dictionary, the real harness" (fun () ->
      Harness_topology.dictionary ()) in
  check "the real dictionary emits under 1s"
    (t_h < 1.0 && match harness_dict with Ok _ -> true | Error _ -> false)

(* ------------------------------------------------ interpreter throughput *)

let () =
  print_endline "== interpreter ==";
  let ring n =
    Internal_machine
      { machine_name = "Ring";
        signals = [ { signal_name = "step"; signal_type = None } ];
        guards = []; actions = [];
        states =
          List.init n (fun i ->
              { state_name = Printf.sprintf "S%d" i; entry = []; exit_ = [];
                transitions =
                  [ { on_signal = "step"; guard = None; do_actions = [];
                      target = To_state (Printf.sprintf "S%d" ((i + 1) mod n)) } ] });
        choices = []; initial = ([], "S0") }
  in
  let machine = ring 50 in
  let steps = 2000 in
  let (final, t_disp) =
    time (Printf.sprintf "dispatch x%d over a 50-state ring" steps) (fun () ->
        match Fpp_interp.init machine with
        | Error e -> failwith e
        | Ok start ->
            let state = ref start in
            for _ = 1 to steps do
              match Fpp_interp.dispatch ~machine ~guards:[] !state "step" with
              | Ok next -> state := next
              | Error e -> failwith e
            done;
            !state)
  in
  check "2000 dispatches land on the right state under 2s"
    (t_disp < 2.0 && final.Fpp_interp.current = Printf.sprintf "S%d" (steps mod 50));
  let resolutions = 50_000 in
  let (rejections, t_cmd) =
    time (Printf.sprintf "send_command x%d (opcode resolution)" resolutions) (fun () ->
        let hits = ref 0 in
        for i = 1 to resolutions do
          match
            Fpp_interp.send_command Harness_topology.model ~instance:"blueprint"
              ~opcode:(0x600 + (i mod 3)) ~queue:None
          with
          | Ok _ -> incr hits
          | Error _ -> ()
        done;
        !hits)
  in
  check "50k opcode resolutions under 2s, hits counted"
    (t_cmd < 2.0 && rejections > 0)

(* ------------------------------------------------- control-plane folds *)

let () =
  print_endline "== control plane at scale ==";
  let scenarios = 100 and runs = 100 in
  (* 10k rows: each scenario flaps late in its history. *)
  let history =
    List.concat
      (List.init scenarios (fun s ->
           List.init runs (fun r ->
               ( "contract",
                 Printf.sprintf "scenario%d" s,
                 not (r > 90 && r mod 2 = 0) ))))
  in
  let (leg1, t_reg) = time "l1_regressions over 10k rows" (fun () ->
      Control_plane.l1_regressions ~history) in
  let (leg2, t_flap) = time "l2_flaps over 10k rows" (fun () ->
      Control_plane.l2_flaps ~history) in
  ignore leg1; ignore leg2;
  check "regression fold over 10k rows under 2s" (t_reg < 2.0);
  check "flap fold over 10k rows under 2s" (t_flap < 2.0);
  let counts = List.init 10_000 (fun i -> i / 100) in
  let (alert, t_front) = time "frontier_alert over a 10k-point trajectory" (fun () ->
      Homeostasis.frontier_alert ~satisfied_counts:counts ~total:200) in
  check "frontier fold over 10k points under 1s, monotone stays green-or-stalled"
    (t_front < 1.0 && match alert with Homeostasis.P0 _ -> false | _ -> true)

(* -------------------------------------------- registry + census overhead *)

let () =
  print_endline "== formal coverage overhead ==";
  let (gaps, t_all) =
    time "all five completeness laws + census + reconcile" (fun () ->
        List.concat
          [ Formal_coverage.component_gaps (); Formal_coverage.aspect_gaps ();
            Formal_coverage.scenario_gaps (); Formal_coverage.interaction_gaps ();
            Formal_coverage.missing_files (); Formal_coverage.reconcile () ]
        @ List.map (fun (k, _) -> k) (Formal_coverage.census ()))
  in
  check "the whole registry sweep is under 1s (cheap enough to run always)"
    (t_all < 1.0 && List.length gaps > 20 (* census keys flow through *))

let () =
  Printf.printf "fpp_performance: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_fpp_performance" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)

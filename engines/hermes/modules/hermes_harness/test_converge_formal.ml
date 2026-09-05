(* The ConvergeLoop formal leg: bounded model checking over the REAL
   machine, through the REAL interpreter.

   The transition relation R is not hand-written: it is computed by
   driving Fpp_interp.dispatch over every (state, signal, guard valuation)
   of the ConvergeLoop machine in Harness_topology. Z3 then proves trace
   properties over symbolic k-step runs constrained by R:

   - every state is reachable from Idle (six SAT witnesses);
   - Anomalous is absorbing along ALL traces (UNSAT of an escape step) —
     one-step absorption suffices because the relation is memoryless;
   - Converged is entered only through progress/no_progress (the Kleene
     decision), Blocked only through preflight_refused (R13);
   - a mutant relation with an injected Anomalous->Idle escape is CAUGHT
     by the same encoding (SAT), so the proof provably proves.

   Two encodings, one machine: the OCaml interpreter defines the steps,
   the solver quantifies over every trace the steps allow. *)

module S = Smtml.Solver.Batch (Smtml.Z3_mappings)
open Smtml

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    print_endline ("FAILED: " ^ name)
  end

let int_sym name = Expr.symbol (Symbol.make Ty.Ty_int name)
let int_val n = Expr.value (Value.Int n)
let eq a b = Expr.relop Ty.Ty_bool Ty.Relop.Eq a b
let band a b = Expr.binop Ty.Ty_bool Ty.Binop.And a b
let bor a b = Expr.binop Ty.Ty_bool Ty.Binop.Or a b
let bnot a = Expr.unop Ty.Ty_bool Ty.Unop.Not a
let conj = function [] -> eq (int_val 0) (int_val 0) | x :: r -> List.fold_left band x r
let disj = function [] -> eq (int_val 0) (int_val 1) | x :: r -> List.fold_left bor x r

let solve assumptions =
  let solver = S.create () in
  S.check solver assumptions

(* ------------------------------------------------ the machine, as data *)

let machine =
  List.find
    (function
      | Fpp_model.Internal_machine { machine_name; _ } -> machine_name = "ConvergeLoop"
      | Fpp_model.External_machine _ -> false)
    Harness_topology.model.Fpp_model.machines

let state_names, signal_names =
  match machine with
  | Fpp_model.Internal_machine { states; signals; _ } ->
      ( List.map (fun s -> s.Fpp_model.state_name) states,
        List.map (fun s -> s.Fpp_model.signal_name) signals )
  | Fpp_model.External_machine _ -> ([], [])

let index_of names name =
  let rec go i = function
    | [] -> failwith ("no index for " ^ name)
    | x :: rest -> if x = name then i else go (i + 1) rest
  in
  go 0 names

let state_index = index_of state_names
let signal_index = index_of signal_names

(* R: (state, signal, guard-valuation, next-state), computed through the
   interpreter. gval 1 means frontier_advanced holds. *)
let relation =
  List.concat_map
    (fun state ->
      List.concat_map
        (fun signal ->
          List.map
            (fun gval ->
              let guards = [ ("frontier_advanced", gval = 1) ] in
              let start = { Fpp_interp.current = state; log = [] } in
              match Fpp_interp.dispatch ~machine ~guards start signal with
              | Ok next ->
                  (state_index state, signal_index signal, gval,
                   state_index next.Fpp_interp.current)
              | Error message -> failwith message)
            [ 0; 1 ])
        signal_names)
    state_names

let () =
  check "the computed relation covers every (state, signal, valuation)"
    (List.length relation = List.length state_names * List.length signal_names * 2)

(* ------------------------------------------------------ BMC scaffolding *)

let depth = 6

let xs = List.init (depth + 1) (fun i -> int_sym (Printf.sprintf "x%d" i))
let sigs = List.init depth (fun i -> int_sym (Printf.sprintf "g%d" i))
let gvs = List.init depth (fun i -> int_sym (Printf.sprintf "v%d" i))

let nth = List.nth

let trace_constraints relation_tuples =
  let step i =
    disj
      (List.map
         (fun (s, g, v, s') ->
           conj
             [ eq (nth xs i) (int_val s); eq (nth sigs i) (int_val g);
               eq (nth gvs i) (int_val v); eq (nth xs (i + 1)) (int_val s') ])
         relation_tuples)
  in
  eq (nth xs 0) (int_val (state_index "Idle"))
  :: List.init depth step

let base = trace_constraints relation

(* ---------------------------------------------------------- reachability *)

let () =
  List.iter
    (fun state ->
      let somewhere =
        disj (List.map (fun x -> eq x (int_val (state_index state))) xs)
      in
      check
        (Printf.sprintf "reachable: %s has a witness trace (SAT)" state)
        (solve (base @ [ somewhere ]) = `Sat))
    state_names

(* ------------------------------------------------------------- absorption *)

let anomalous = int_val (state_index "Anomalous")

let escape_exists =
  disj
    (List.init depth (fun i ->
         band (eq (nth xs i) anomalous) (bnot (eq (nth xs (i + 1)) anomalous))))

let () =
  check "Anomalous is absorbing along every trace (UNSAT of an escape)"
    (solve (base @ [ escape_exists ]) = `Unsat)

(* ------------------------------------------------------- entry-cause laws *)

let entered_wrongly ~target ~allowed_signals =
  let target = int_val (state_index target) in
  let allowed g =
    disj (List.map (fun s -> eq g (int_val (signal_index s))) allowed_signals)
  in
  disj
    (List.init depth (fun i ->
         conj
           [ eq (nth xs (i + 1)) target;
             bnot (eq (nth xs i) target);
             bnot (allowed (nth sigs i)) ]))

let () =
  check
    "Converged is entered only through progress/no_progress (the Kleene decision)"
    (solve (base @ [ entered_wrongly ~target:"Converged" ~allowed_signals:[ "progress"; "no_progress" ] ])
    = `Unsat);
  check "Blocked is entered only through preflight_refused (R13)"
    (solve (base @ [ entered_wrongly ~target:"Blocked" ~allowed_signals:[ "preflight_refused" ] ])
    = `Unsat);
  check "Observing is entered only through preflight_ok or progress"
    (solve (base @ [ entered_wrongly ~target:"Observing" ~allowed_signals:[ "preflight_ok"; "progress" ] ])
    = `Unsat)

(* ------------------------------------------------------------ mutant leg *)

let () =
  let escape_tuple =
    (state_index "Anomalous", signal_index "tick", 0, state_index "Idle")
  in
  let mutant = trace_constraints (escape_tuple :: relation) in
  check "mutant: an injected Anomalous->Idle escape is caught (SAT)"
    (solve (mutant @ [ escape_exists ]) = `Sat)

let () =
  Printf.printf "converge_formal: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_converge_formal" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)

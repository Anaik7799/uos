(* The smtml leg (zigvm Hia pattern, R14): the SECOND solver path -- in-process
   Z3 via smtml's Batch functor -- proving the lattice/gate laws over SYMBOLIC
   ints (rank encoding: Verified=0 < Unmapped=1 < Blocked=2 < Divergent=3), and
   agreeing with the z3-CLI verdicts formal_specs computes over the emitted
   tables. Two encodings, two solver paths, one set of laws.

   Symbolic, not ground: a,b,c are solver variables constrained to [0,3]; the
   negated laws are discharged by SOLVER reasoning over ite/le, not by OCaml
   evaluation. Sanity-SAT proves the solver actually answers (never vacuous).

   PINNED FINDING (measured 2026-08-08): smtml 0.29.0's SMT-LIB frontend crashes
   on declare-datatype (smtlib.ml:368 assertion), so it cannot consume the
   emitted datatype specs directly -- the reason this leg re-encodes over ints.
   The pin below notices if a future smtml starts parsing them (an upgrade). *)

module S = Smtml.Solver.Batch (Smtml.Z3_mappings)
open Smtml

let int_sym name = Expr.symbol (Symbol.make Ty.Ty_int name)
let int_val n = Expr.value (Value.Int n)
let eq a b = Expr.relop Ty.Ty_bool Ty.Relop.Eq a b
let le a b = Expr.relop Ty.Ty_int Ty.Relop.Le a b
let band a b = Expr.binop Ty.Ty_bool Ty.Binop.And a b
let bor a b = Expr.binop Ty.Ty_bool Ty.Binop.Or a b
let bnot a = Expr.unop Ty.Ty_bool Ty.Unop.Not a
let ite c t e = Expr.triop Ty.Ty_bool Ty.Triop.Ite c t e

(* combine over the rank encoding: max. gate: fail-closed. *)
let combine x y = ite (le y x) x y
let gate a b = ite (eq a (int_val 0)) (combine a b) a
let in_range x = band (le (int_val 0) x) (le x (int_val 3))

let a = int_sym "a"
let b = int_sym "b"
let c = int_sym "c"
let range = band (in_range a) (band (in_range b) (in_range c))

let check_law name negation expected =
  let solver = S.create () in
  let got = S.check solver [ range; negation ] in
  let show = function `Sat -> "sat" | `Unsat -> "unsat" | `Unknown -> "unknown" in
  if got <> expected then
    failwith (Printf.sprintf "law %s: expected %s, got %s" name (show expected) (show got))

let () =
  (* The negated laws must be UNSAT -- proved over all symbolic values. *)
  check_law "combine-comm" (bnot (eq (combine a b) (combine b a))) `Unsat;
  check_law "combine-assoc" (bnot (eq (combine (combine a b) c) (combine a (combine b c)))) `Unsat;
  check_law "combine-idem" (bnot (eq (combine a a) a)) `Unsat;
  check_law "divergent-absorbs" (bnot (eq (combine (int_val 3) a) (int_val 3))) `Unsat;
  check_law "credit-conjunction"
    (bnot
       (eq
          (ite (eq (combine a b) (int_val 0)) (int_val 1) (int_val 0))
          (ite (band (eq a (int_val 0)) (eq b (int_val 0))) (int_val 1) (int_val 0))))
    `Unsat;
  check_law "gate-fail-closed"
    (bor
       (band (bnot (eq a (int_val 0))) (bnot (eq (gate a b) a)))
       (band (eq a (int_val 0)) (bnot (eq (gate a b) (combine a b)))))
    `Unsat;
  (* Sanity-SAT: the solver genuinely answers; the harness is not vacuous. *)
  check_law "sanity-sat" (eq a (int_val 1)) `Sat;

  (* Agreement with the FIRST solver path: the z3 CLI over the emitted tables.
     When the CLI is present all three specs are Proved; absence is disclosed. *)
  let cli = Formal_specs.verify_all () in
  let proved =
    List.length
      (List.filter (fun (_, r) -> match r with Formal_specs.Proved -> true | _ -> false) cli)
  in
  let unavailable =
    List.exists (fun (_, r) -> match r with Formal_specs.Unavailable _ -> true | _ -> false) cli
  in
  if unavailable then
    print_endline
      "test_smtml_lattice: in-process laws PROVED; z3 CLI unavailable -- agreement \
       SKIPPED, disclosed (R2)"
  else if proved = List.length cli then
    print_endline
      "test_smtml_lattice: ok (in-process smtml-z3 and the z3 CLI AGREE: all laws proved \
       on both solver paths)"
  else failwith "solver paths disagree: CLI did not prove every spec the in-process path proved";

  (* The pinned frontend finding: the emitted datatype spec is NOT consumable by
     smtml's SMT-LIB parser today. If this starts succeeding, a future smtml
     gained ADT support -- notice it and reclaim the direct-artifact route. *)
  let spec_path = Filename.temp_file "smtml-pin-" ".smt2" in
  let out = open_out_bin spec_path in
  output_string out (Formal_specs.algebra_spec ());
  close_out out;
  (match (try Ok (Parse.Smtlib.from_file (Fpath.v spec_path)) with e -> Error (Printexc.to_string e)) with
  | Ok (Error _) | Error _ ->
      print_endline
        "test_smtml_lattice: datatype-frontend limitation still present (pinned finding F-SMTML-1)"
  | Ok (Ok _) ->
      print_endline
        "test_smtml_lattice: NOTE -- smtml now parses the datatype spec; the direct-artifact \
         route is available (upgrade opportunity)");
  Sys.remove spec_path

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_smtml_lattice" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)

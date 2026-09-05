(* The alert-lattice solver leg: the control-plane twin of
   test_smtml_lattice (R14 mirror — same Batch/Z3 path, second lattice).

   Rank encoding: Green=0 < P2=1 < P1=2 < P0=3. worst = max-join. The laws
   proved here over SYMBOLIC values are the ones Homeostasis's property
   suite pins over sampled windows: commutativity, associativity,
   idempotence, Green identity (the empty window is Green — absence is not
   a violation), P0 absorption (stop-the-line dominates), monotonicity
   (more severe input can never lower the fold), and the full
   least-upper-bound law for the three-element fold.

   The TWO-LATTICE law is deliberately NOT a theorem here: a rank
   isomorphism between alerts and verdicts exists mathematically, so its
   nonexistence cannot be proved — the forbidden morphism is ARCHITECTURAL
   (no code path carries alerts into verdicts) and is pinned structurally
   by harness_topology and the BDD suite instead. Claiming a solver proof
   of it would be theatre; this comment is the honest boundary.

   Non-vacuity: sanity-SAT legs plus a mutant join (drop the absorption)
   that the same encodings catch as SAT. *)

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
let le a b = Expr.relop Ty.Ty_int Ty.Relop.Le a b
let band a b = Expr.binop Ty.Ty_bool Ty.Binop.And a b
let bor a b = Expr.binop Ty.Ty_bool Ty.Binop.Or a b
let bnot a = Expr.unop Ty.Ty_bool Ty.Unop.Not a
let ite c t e = Expr.triop Ty.Ty_bool Ty.Triop.Ite c t e

(* worst over the rank encoding: max. *)
let worst x y = ite (le y x) x y

(* The deliberately broken join for the mutant leg: P0 fails to absorb
   (3 `worst_broken` x collapses to x). *)
let worst_broken x y = ite (eq x (int_val 3)) y (worst x y)

let in_range x = band (le (int_val 0) x) (le x (int_val 3))

let a = int_sym "a"
let b = int_sym "b"
let c = int_sym "c"
let u = int_sym "u"

let range =
  band (in_range a) (band (in_range b) (band (in_range c) (in_range u)))

let solve assumptions =
  let solver = S.create () in
  S.check solver assumptions

let prove name negation =
  check (name ^ " (UNSAT of negation)") (solve [ range; negation ] = `Unsat)

let () =
  prove "worst is commutative" (bnot (eq (worst a b) (worst b a)));
  prove "worst is associative"
    (bnot (eq (worst (worst a b) c) (worst a (worst b c))));
  prove "worst is idempotent" (bnot (eq (worst a a) a));
  prove "Green is the identity (the empty window is Green)"
    (bnot (eq (worst (int_val 0) a) a));
  prove "P0 absorbs (stop-the-line dominates every fold)"
    (bnot (eq (worst (int_val 3) a) (int_val 3)));
  prove "worst is monotone in each argument"
    (band (le a b) (bnot (le (worst a c) (worst b c))));
  (* Least upper bound, in both halves: the fold of three is an upper
     bound of each, and it is BELOW every other upper bound. *)
  let fold3 = worst (worst (worst (int_val 0) a) b) c in
  prove "the fold is an upper bound of every window element"
    (bor (bnot (le a fold3)) (bor (bnot (le b fold3)) (bnot (le c fold3))));
  prove "the fold is the LEAST upper bound"
    (band
       (band (le a u) (band (le b u) (le c u)))
       (bnot (le fold3 u)));
  (* Sanity: the solver is answering, not rubber-stamping. *)
  check "sanity: a strict fold increase is expressible (SAT)"
    (solve [ range; bnot (eq (worst a b) a) ] = `Sat);
  (* Mutant: the broken join is caught by the SAME absorption encoding. *)
  check "mutant: a join without absorption is detected (SAT)"
    (solve [ range; bnot (eq (worst_broken (int_val 3) a) (int_val 3)) ] = `Sat);
  check "mutant: the broken join even loses the upper-bound law (SAT)"
    (let broken3 = worst_broken (worst_broken (worst_broken (int_val 0) a) b) c in
     solve
       [ range;
         bor (bnot (le a broken3)) (bor (bnot (le b broken3)) (bnot (le c broken3))) ]
     = `Sat)

let () =
  Printf.printf "smtml_alerts: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_smtml_alerts" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)

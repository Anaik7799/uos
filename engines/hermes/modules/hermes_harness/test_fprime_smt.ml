(* The F Prime formal leg (smtml/Z3 in-process, the test_smtml_lattice
   pattern): three laws over the REAL harness topology.

   1. ALGORITHM law (symbolic): the validator checks only CONSECUTIVE pairs
      of the base-id-sorted instance list. Z3 proves that suffices: for
      sorted b1 <= b2 <= b3 with consecutive gaps >= spans, the NON-adjacent
      pair is also disjoint. The OCaml validator cannot prove its own
      criterion; this leg does.
   2. DATA law (concrete, solver path): the real instance layout is
      pairwise disjoint — UNSAT of "some pair overlaps" over the actual
      (base, span) values. A second solver path over the same data the
      OCaml check passes: two paths, one law.
   3. DICTIONARY law (concrete): all instance-qualified opcodes in the
      emitted dictionary are globally distinct.

   Non-vacuity: each law carries a SAT leg (overlap CAN be expressed; a
   duplicated opcode IS detected) — the solver provably answers, and the
   encoding provably distinguishes. *)

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
let add a b = Expr.binop Ty.Ty_int Ty.Binop.Add a b
let band a b = Expr.binop Ty.Ty_bool Ty.Binop.And a b
let bor a b = Expr.binop Ty.Ty_bool Ty.Binop.Or a b
let bnot a = Expr.unop Ty.Ty_bool Ty.Unop.Not a
let conj = function [] -> eq (int_val 0) (int_val 0) | x :: rest -> List.fold_left band x rest

let solve assumptions =
  let solver = S.create () in
  S.check solver assumptions

(* Ranges [b, b+s) disjoint: b1 + s1 <= b2 or b2 + s2 <= b1. *)
let disjoint b1 s1 b2 s2 = bor (le (add b1 s1) b2) (le (add b2 s2) b1)

(* ------------------------------------------------- 1. the algorithm law *)

let () =
  let b1 = int_sym "b1" and b2 = int_sym "b2" and b3 = int_sym "b3" in
  let s1 = int_sym "s1" and s2 = int_sym "s2" and s3 = int_sym "s3" in
  let sorted = band (le b1 b2) (le b2 b3) in
  let spans_positive =
    conj [ le (int_val 1) s1; le (int_val 1) s2; le (int_val 1) s3 ]
  in
  let consecutive_ok = band (le (add b1 s1) b2) (le (add b2 s2) b3) in
  (* Negation: consecutive gaps hold, yet SOME pair overlaps. Must be UNSAT:
     the consecutive criterion implies pairwise disjointness. *)
  let some_pair_overlaps =
    bor
      (bnot (disjoint b1 s1 b2 s2))
      (bor (bnot (disjoint b2 s2 b3 s3)) (bnot (disjoint b1 s1 b3 s3)))
  in
  check "ALGORITHM: consecutive-gap check implies pairwise disjointness (UNSAT)"
    (solve [ sorted; spans_positive; consecutive_ok; some_pair_overlaps ] = `Unsat);
  (* Sanity SAT: without the consecutive guarantee, overlap is expressible —
     the solver is answering, not rubber-stamping. *)
  check "ALGORITHM sanity: overlap is expressible without the guarantee (SAT)"
    (solve [ sorted; spans_positive; bnot (disjoint b1 s1 b2 s2) ] = `Sat)

(* ------------------------------------------------------ 2. the data law *)

let concrete_layout () =
  List.filter_map
    (fun (i : Fpp_model.instance) ->
      match
        List.find_opt
          (fun (c : Fpp_model.component) -> c.Fpp_model.comp_name = i.Fpp_model.of_component)
          Harness_topology.model.Fpp_model.components
      with
      | Some c -> Some (i.Fpp_model.inst_name, i.Fpp_model.base_id, Fpp_model.id_span c)
      | None -> None)
    Harness_topology.model.Fpp_model.instances

let rec pairs = function
  | [] -> []
  | x :: rest -> List.map (fun y -> (x, y)) rest @ pairs rest

let () =
  let layout = concrete_layout () in
  check "the layout covers every instance"
    (List.length layout = List.length Harness_topology.model.Fpp_model.instances);
  let overlap_exists =
    List.map
      (fun ((_, base_a, span_a), (_, base_b, span_b)) ->
        bnot (disjoint (int_val base_a) (int_val span_a) (int_val base_b) (int_val span_b)))
      (pairs layout)
  in
  check "DATA: the real harness layout is pairwise disjoint (UNSAT via Z3)"
    (solve [ List.fold_left bor (bnot (eq (int_val 0) (int_val 0))) overlap_exists ] = `Unsat);
  (* Mutant: collapse two bases onto each other — the encoding must notice. *)
  match layout with
  | (_, base_a, span_a) :: _ ->
      check "DATA mutant: a forced collision is SAT (the encoding can fail)"
        (solve [ bnot (disjoint (int_val base_a) (int_val span_a) (int_val base_a) (int_val span_a)) ]
        = `Sat)
  | [] -> check "DATA mutant: layout non-empty" false

(* ------------------------------------------------ 3. the dictionary law *)

let dictionary_opcodes () =
  match Harness_topology.dictionary () with
  | Error e -> failwith e
  | Ok (`Assoc fields) -> (
      match List.assoc_opt "commands" fields with
      | Some (`List commands) ->
          List.filter_map
            (fun c ->
              match c with
              | `Assoc f -> (
                  match List.assoc_opt "opcode" f with Some (`Int n) -> Some n | _ -> None)
              | _ -> None)
            commands
      | _ -> failwith "no commands key")
  | Ok _ -> failwith "dictionary is not an object"

let () =
  let opcodes = dictionary_opcodes () in
  check "the dictionary carries a real opcode population" (List.length opcodes >= 10);
  let collision values =
    List.map (fun (a, b) -> eq (int_val a) (int_val b)) (pairs values)
    |> List.fold_left bor (bnot (eq (int_val 0) (int_val 0)))
  in
  check "DICTIONARY: instance-qualified opcodes are globally distinct (UNSAT)"
    (solve [ collision opcodes ] = `Unsat);
  check "DICTIONARY mutant: a duplicated opcode is SAT (non-vacuous)"
    (solve [ collision (List.hd opcodes :: opcodes) ] = `Sat)

let () =
  Printf.printf "fprime_smt: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_fprime_smt" ~passed:!passed ~failed:!failed
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_core; Stanza.hermes_harness_inventory; Stanza.hermes_harness_evidence; Stanza.hermes_harness_evidence_import; Stanza.hermes_harness_bootstrap; Stanza.hermes_harness_report; Stanza.hermes_harness_parity; Stanza.hermes_harness_feature_catalog; Stanza.hermes_harness_fractal_parity; Stanza.hermes_harness_evolution_model; Stanza.hermes_harness_capability_catalog; Stanza.hermes_harness_fractal_catalog; Stanza.hermes_harness_contract_catalog; Stanza.hermes_harness_ocaml_only_guard; Stanza.hermes_harness_parity_normalizer; Stanza.hermes_harness_reference_capture; Stanza.hermes_harness_gospel_check; Stanza.hermes_harness_reference_artifacts; Stanza.hermes_harness_plan; Stanza.hermes_harness_openrouter_contract; Stanza.hermes_harness_turn_budget; Stanza.hermes_harness_info_math; Stanza.hermes_harness_diff_triage; Stanza.hermes_harness_expect_posterior; Stanza.hermes_harness_orientation_history; Stanza.hermes_harness_qcheck_seed; Stanza.hermes_harness_suite_telemetry; Stanza.hermes_harness_posterior_assessment; Stanza.hermes_harness_message_hygiene; Stanza.hermes_harness_turn_preflight; Stanza.hermes_harness_openrouter_transport; Stanza.hermes_harness_dependency_smt; Stanza.hermes_harness_capture_diagnostic; Stanza.hermes_harness_parity_algebra; Stanza.hermes_harness_fractal_ontology; Stanza.hermes_harness_formal_specs; Stanza.hermes_harness_parity_compare; Stanza.hermes_harness_parity_ledger; Stanza.hermes_harness_resource_envelope; Stanza.hermes_harness_fractal_countermeasures; Stanza.hermes_harness_replay_executor; Stanza.hermes_harness_session_fixture; Stanza.hermes_harness_determinism_verifier; Stanza.hermes_harness_hermes_analysis; Stanza.hermes_harness_hermes_imports; Stanza.hermes_harness_path_safety; Stanza.hermes_harness_retry_utils; Stanza.hermes_harness_blueprint; Stanza.hermes_harness_harness_config; Stanza.hermes_harness_evidence_rollup; Stanza.hermes_harness_hermes_rete; Stanza.hermes_harness_rust_rules; Stanza.hermes_harness_runtime_coverage; Stanza.hermes_harness_parity_dashboard; Stanza.hermes_harness_drift_rules; Stanza.hermes_harness_receipt_reliability; Stanza.hermes_harness_ruliad; Stanza.hermes_harness_parity_intent; Stanza.hermes_harness_ruliad_rules; Stanza.hermes_harness_rocq_lattice; Stanza.hermes_harness_route_resolution; Stanza.hermes_harness_anthropic_adapter; Stanza.hermes_harness_converge; Stanza.hermes_harness_homeostasis; Stanza.hermes_harness_control_plane; Stanza.hermes_harness_hermes_zenoh; Stanza.hermes_harness_codex_message_shapes; Stanza.hermes_harness_gemini_schema; Stanza.hermes_harness_bedrock_converse; Stanza.hermes_harness_harness_topology; Stanza.hermes_harness_fpp_usecases; Stanza.hermes_harness_formal_coverage; Stanza.hermes_harness_web_read_model; Stanza.hermes_harness_site_build; Stanza.hermes_harness_gap_plan; Stanza.hermes_harness_agent_model; Stanza.hermes_harness_e2e_framework; Stanza.hermes_harness_e2e_tier1_tests; Stanza.hermes_harness_e2e_tier2_tests; Stanza.hermes_harness_e2e_tier3_tests; Stanza.hermes_harness_e2e_tier4_tests ]);
  exit (Suite_telemetry.exit_code self)

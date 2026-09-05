let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L6/observe rca=Implementation hazard=HZ-T6-ASSURANCE-01 check=%s\n"
      name
  end

let provenance : Run_model.provenance =
  { source_revision = "task6-foundation"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let context run_id =
  match
    Run_safety.For_test.current_head_receipt ~run_id ~provenance
      ~observed_at_ns:900L ~current_at_ns:1_000L ~expires_at_ns:2_000L
  with
  | Error _ as error -> error
  | Ok current_head ->
      Run_safety.make_gate_context ~current_head
        ~request_id:"request-assurance"
        ~activity_id:"activity.decide-intent"
        ~coordinate:{ level = Ops_capability.L2; phase = Ops_capability.Decide }
        ~plane:Ops_capability.Control_plane

let unavailable_receipt context = function
  | Run_safety.Stpa_fmea ->
      Result.map snd (Run_safety.evaluate context Run_safety.model)
  | Run_safety.Rete_ul ->
      Run_safety.rete_unavailable_receipt context ~reason:"Rete unavailable"
  | Run_safety.Raven_matrix ->
      Run_safety.raven_unavailable_receipt context ~reason:"Raven unavailable"
  | Run_safety.Ruliad ->
      Run_safety.ruliad_unavailable_receipt context ~reason:"Ruliad unavailable"
  | Run_safety.Stan_model ->
      Run_safety.stan_unavailable_receipt context ~reason:"Stan unavailable"
  | Run_safety.Z3 ->
      Run_safety.z3_unavailable_receipt context ~reason:"Z3 unavailable"
  | Run_safety.Assurance -> invalid_arg "Assurance is not an upstream gate"

let upstream_gates =
  [ Run_safety.Stpa_fmea; Run_safety.Rete_ul; Run_safety.Raven_matrix;
    Run_safety.Ruliad; Run_safety.Stan_model; Run_safety.Z3 ]

let all_unavailable context =
  upstream_gates
  |> List.filter_map (fun gate ->
         unavailable_receipt context gate |> Result.to_option)

let evaluate_assurance_receipt context bundle =
  match Run_assurance.evaluate_inputs context bundle with
  | Ok (_, receipt) -> Some receipt
  | Error _ -> None

let ( let* ) option continuation = Option.bind option continuation

module Rete = Run_intelligence.Rete_ul
module Raven = Run_intelligence.Raven_matrix
module Ruliad = Run_analysis.Ruliad
module Stan = Run_analysis.Stan_model
module Z3 = Run_analysis.Z3

type exact_fixture = {
  safety_model : Run_safety.model;
  safety : Run_safety.receipt;
  rete_network : Rete.network;
  rete_facts : Rete.fact list;
  rete : Rete.dispatch_receipt;
  raven_matrix : Raven.matrix;
  raven : Raven.receipt;
  ruliad_system : Ruliad.system;
  ruliad_bounds : Ruliad.bounds;
  ruliad : Ruliad.receipt;
  stan_input : Stan.input;
  stan : Stan.receipt;
  z3_unavailable : Run_safety.receipt;
}

let controlled_safety context =
  let base = Run_safety.model in
  let lowered : Run_safety.risk =
    { severity = 1; occurrence = 1; detectability = 1 }
  in
  match
    Run_safety.For_test.control_evidence context base
      ~failure_mode_id:"FM-SQL-FIN-01" ~residual_risk:lowered
  with
  | Error _ -> None
  | Ok evidence ->
      let failure_modes =
        List.map
          (fun (mode : Run_safety.failure_mode) ->
            if String.equal mode.stable_id "FM-SQL-FIN-01" then
              { mode with residual_risk = lowered;
                          control_evidence = Some evidence; acceptance = None }
            else mode)
          base.failure_modes
      in
      let model = { base with failure_modes } in
      begin match Run_safety.evaluate context model with
      | Ok (Run_safety.Admit, receipt) -> Some (model, receipt)
      | Error _ | Ok (Run_safety.Block _, _) -> None
      end

let rete_budgets : Rete.budgets =
  { max_facts = 8; max_alpha_entries = 8; max_beta_tokens = 8;
    max_agenda = 8; max_firings = 8; max_trace_entries = 8 }

let rete_network () : Rete.network =
  { network_id = "network.assurance-exact"; budgets = rete_budgets;
    rules =
      [ { rule_id = "rule.assurance-block"; salience = 1;
          patterns =
            [ { pattern_id = "pattern.assurance-dispatch";
                fact_kind = "dispatch";
                conditions = [ Rete.Field_eq ("unsafe", Rete.Bool true) ] } ];
          actions = [ Rete.Block_rhs "unsafe dispatch" ] } ] }

let rete_fact fact_id =
  Rete.make_fact ~fact_id ~fact_kind:"dispatch"
    ~attrs:[ ("unsafe", Rete.Bool false) ]
  |> Result.to_option

let exact_rete context =
  let network = rete_network () in
  let* fact = rete_fact "dispatch-assurance-1" in
  let facts = [ fact ] in
  let* compiled = Rete.compile context network |> Result.to_option in
  let* _, replay =
    Rete.replay context compiled [ Rete.Assert_fact fact ] |> Result.to_option
  in
  let* exact =
    Rete.admit_dispatch context ~network ~facts replay |> Result.to_option
  in
  Some (network, facts, exact)

let raven_budgets : Raven.budgets =
  { max_alternatives = 4; max_criteria = 4; max_cells = 8;
    max_constraints = 4; max_trace_entries = 8; max_abs_value = 1_000L }

let raven_matrix ?(matrix_id = "matrix.assurance-exact") () : Raven.matrix =
  { matrix_id;
    criteria =
      [ { criterion_id = "criterion.reliability"; direction = Raven.Maximize;
          weight_ppm = 1_000_000; scale_min = 0L; scale_max = 100L } ];
    alternatives =
      [ { alternative_id = "alternative.alpha"; prohibited = false };
        { alternative_id = "alternative.beta"; prohibited = false } ];
    cells =
      [ { alternative_id = "alternative.alpha";
          criterion_id = "criterion.reliability"; value = 90L;
          evidence_digest = String.make 64 '1' };
        { alternative_id = "alternative.beta";
          criterion_id = "criterion.reliability"; value = 50L;
          evidence_digest = String.make 64 '2' } ];
    constraints = []; tie_order = [ "alternative.alpha"; "alternative.beta" ];
    selection_policy = Raven.Require_stable; min_sensitivity_ppm = 1;
    budgets = raven_budgets }

let exact_raven context matrix =
  Raven.decide context matrix |> Result.to_option

let ruliad_bounds : Ruliad.bounds =
  { max_states = 4; max_edges = 4; max_depth = 2; max_paths = 4L }

let ruliad_system evidence =
  Ruliad.make_system ~initial_state_id:"state.a"
    ~states:
      [ { Ruliad.stable_id = "state.a"; evidence_digest = String.make 64 evidence };
        { stable_id = "state.b"; evidence_digest = String.make 64 '4' } ]
    ~transitions:
      [ { Ruliad.stable_id = "transition.a-b";
          from_state_id = "state.a"; to_state_id = "state.b";
          move_digest = String.make 64 '5' } ]
  |> Result.to_option

let stan_input prior_alpha =
  let* observation =
    Stan.make_observation ~scenario_id:"scenario.assurance"
      ~family_id:"family.assurance" ~sequence:1L ~verdict:Stan.Passed
      ~evidence_digest:(String.make 64 '6')
    |> Result.to_option
  in
  Stan.make_input ~prior_alpha ~prior_beta:1.0
    ~all_families:[ "family.assurance" ] ~observations:[ observation ]
  |> Result.to_option

let build_exact_fixture context =
  let* safety_model, safety = controlled_safety context in
  let* rete_network, rete_facts, rete = exact_rete context in
  let raven_matrix = raven_matrix () in
  let* raven = exact_raven context raven_matrix in
  let* ruliad_system = ruliad_system '3' in
  let* ruliad =
    Ruliad.analyze context ~bounds:ruliad_bounds ruliad_system
    |> Result.to_option
  in
  let* stan_input = stan_input 1.0 in
  let* stan = Stan.analyze context stan_input |> Result.to_option in
  let* z3_unavailable =
    Run_safety.z3_unavailable_receipt context
      ~reason:"Task-3 admitted solver receipt is not yet available"
    |> Result.to_option
  in
  Some
    { safety_model; safety; rete_network; rete_facts; rete; raven_matrix;
      raven; ruliad_system; ruliad_bounds; ruliad; stan_input; stan;
      z3_unavailable }

let ordered_exact_inputs ?rete_facts ?raven_matrix ?ruliad_system
    ?ruliad_bounds:bounds ?ruliad ?stan_input ?stan ?z3_unavailable fixture =
  let choose candidate fallback = Option.value candidate ~default:fallback in
  [ Run_assurance.Safety_input (fixture.safety_model, fixture.safety);
    Run_assurance.Rete_input
      (fixture.rete_network, choose rete_facts fixture.rete_facts, fixture.rete);
    Run_assurance.Raven_input
      (choose raven_matrix fixture.raven_matrix, fixture.raven);
    Run_assurance.Ruliad_input
      (choose ruliad_system fixture.ruliad_system,
       choose bounds fixture.ruliad_bounds, choose ruliad fixture.ruliad);
    Run_assurance.Stan_input
      (choose stan_input fixture.stan_input, choose stan fixture.stan);
    Run_assurance.Z3_unavailable_input
      (choose z3_unavailable fixture.z3_unavailable) ]

let live_z3_campaign () =
  Z3.make_campaign_envelope ~maximum_total_elapsed_ms:180_000
    ~linked_max_allocated_bytes:268_435_456L
    ~linked_max_heap_words:33_554_432
    ~linked_virtual_memory_bytes:536_870_912L ~linked_cpu_seconds:2
    ~linked_maximum_query_bytes:1_048_576
    ~linked_maximum_output_bytes:65_536
    ~maximum_worker_rss_bytes:536_870_912L

let live_z3_configuration executable =
  Z3.make_cli_configuration ~executable ~timeout_ms:5_000
    ~termination_grace_ms:100 ~maximum_output_bytes:65_536

let ordered_live_inputs fixture campaign configuration z3 =
  [ Run_assurance.Safety_input (fixture.safety_model, fixture.safety);
    Run_assurance.Rete_input
      (fixture.rete_network, fixture.rete_facts, fixture.rete);
    Run_assurance.Raven_input (fixture.raven_matrix, fixture.raven);
    Run_assurance.Ruliad_input
      (fixture.ruliad_system, fixture.ruliad_bounds, fixture.ruliad);
    Run_assurance.Stan_input (fixture.stan_input, fixture.stan);
    Run_assurance.Z3_input (campaign, configuration, z3) ]

let run_exact_assurance_reds gate_context =
  Printf.printf
    "[exact-assurance] private six-gate carrier rejects every substitution\n";
  match build_exact_fixture gate_context with
  | None ->
      check "C1 exact assurance fixtures are independently coherent" false
  | Some fixture ->
      check "C1 exact assurance fixtures are independently coherent" true;
      let canonical = ordered_exact_inputs fixture in
      let constructed =
        Run_assurance.make_inputs ~context:gate_context canonical
      in
      check "C2 canonical fixed-arity inputs construct a private carrier"
        (Result.is_ok constructed);
      check "C3 unavailable Z3 remains explicit and cannot admit a bundle"
        (match constructed with
         | Ok inputs -> Result.is_error (Run_assurance.admit ~context:gate_context inputs)
         | Error _ -> false);
      check "C4 a missing gate cannot construct fixed-arity inputs"
        (Result.is_error
           (Run_assurance.make_inputs ~context:gate_context
              (List.rev (List.tl (List.rev canonical)))));
      check "C5 a duplicate gate cannot construct fixed-arity inputs"
        (match canonical with
         | first :: _ ->
             Result.is_error
               (Run_assurance.make_inputs ~context:gate_context
                  (first :: canonical))
         | [] -> false);
      check "C6 order substitution cannot construct fixed-arity inputs"
        (match canonical with
         | first :: second :: rest ->
             Result.is_error
               (Run_assurance.make_inputs ~context:gate_context
                  (second :: first :: rest))
         | [] | [ _ ] -> false);
      check "C7 a coherent Rete fact substitution cannot reuse dispatch authority"
        (match rete_fact "dispatch-assurance-2" with
         | None -> false
         | Some alternate_fact ->
             Result.is_error
               (Run_assurance.make_inputs ~context:gate_context
                  (ordered_exact_inputs ~rete_facts:[ alternate_fact ] fixture)));
      let raven_substitution = raven_matrix ~matrix_id:"matrix.assurance-other" () in
      check "C8 a Raven source cannot be paired with another receipt"
        (Result.is_error
           (Run_assurance.make_inputs ~context:gate_context
              (ordered_exact_inputs ~raven_matrix:raven_substitution fixture)));
      let tighter_bounds : Ruliad.bounds =
        { fixture.ruliad_bounds with max_paths = 3L }
      in
      check "C9 Ruliad bounds cannot be paired with another receipt"
        (Result.is_error
           (Run_assurance.make_inputs ~context:gate_context
              (ordered_exact_inputs ~ruliad_bounds:tighter_bounds fixture)));
      check "C10 Stan input cannot be paired with another receipt"
        (match stan_input 2.0 with
         | None -> false
         | Some stan_substitution ->
             Result.is_error
               (Run_assurance.make_inputs ~context:gate_context
                  (ordered_exact_inputs ~stan_input:stan_substitution fixture)));
      let mutated_safety =
        { fixture.safety_model with topology_digest = String.make 64 'f' }
      in
      let safety_substitution =
        match canonical with
        | _ :: rest ->
            Run_assurance.Safety_input (mutated_safety, fixture.safety) :: rest
        | [] -> []
      in
      check "C11 STPA source digest mutation cannot reuse its receipt"
        (Result.is_error
           (Run_assurance.make_inputs ~context:gate_context safety_substitution));
      let inverted =
        Run_safety.ruliad_unavailable_receipt gate_context
          ~reason:"analysis-only receipt substituted into Z3 slot"
        |> Result.to_option
      in
      check "C12 analysis-only authority cannot occupy the Z3 slot"
        (match inverted with
         | None -> false
         | Some receipt ->
             Result.is_error
               (Run_assurance.make_inputs ~context:gate_context
                  (ordered_exact_inputs ~z3_unavailable:receipt fixture)));
      let foreign = context "run-assurance-foreign" in
      check "C13 foreign context and head evidence is rejected"
        (match foreign with
         | Error _ -> false
         | Ok foreign_context ->
             begin match build_exact_fixture foreign_context with
             | None -> false
             | Some foreign_fixture ->
                 Result.is_error
                   (Run_assurance.make_inputs ~context:gate_context
                      (ordered_exact_inputs foreign_fixture))
             end);
      let stale_context =
        match
          Run_safety.For_test.current_head_receipt ~run_id:"run-assurance"
            ~provenance ~observed_at_ns:900L ~current_at_ns:1_001L
            ~expires_at_ns:2_000L
        with
        | Error _ -> None
        | Ok current_head ->
            Run_safety.make_gate_context ~current_head
              ~request_id:"request-assurance"
              ~activity_id:"activity.decide-intent"
              ~coordinate:{ level = Ops_capability.L2; phase = Ops_capability.Decide }
              ~plane:Ops_capability.Control_plane
            |> Result.to_option
      in
      check "C14 stale time substitution is rejected"
        (match stale_context with
         | None -> false
         | Some stale ->
             begin match build_exact_fixture stale with
             | None -> false
             | Some stale_fixture ->
                 Result.is_error
                   (Run_assurance.make_inputs ~context:gate_context
                      (ordered_exact_inputs stale_fixture))
             end);
      let alternate_analysis =
        let* system = ruliad_system '7' in
        let* ruliad =
          Ruliad.analyze gate_context ~bounds:ruliad_bounds system
          |> Result.to_option
        in
        let* input = stan_input 2.0 in
        let* stan = Stan.analyze gate_context input |> Result.to_option in
        Some (system, ruliad, input, stan)
      in
      check
        "C15 analysis receipts change completeness but never load-bearing identity"
        (match constructed, alternate_analysis with
         | Ok inputs, Some (system, ruliad, input, stan) ->
             begin match
               Run_assurance.make_inputs ~context:gate_context
                 (ordered_exact_inputs ~ruliad_system:system ~ruliad
                    ~stan_input:input ~stan fixture)
             with
             | Error _ -> false
             | Ok alternate ->
                 let left = Run_assurance.receipt inputs in
                 let right = Run_assurance.receipt alternate in
                 String.equal left.load_bearing_digest right.load_bearing_digest
                 && not
                      (String.equal left.completeness_digest
                         right.completeness_digest)
             end
         | Error _, _ | Ok _, None -> false);
      let alternate_raven = raven_matrix ~matrix_id:"matrix.assurance-coherent" () in
      let alternate_raven_receipt = exact_raven gate_context alternate_raven in
      check "C16 load-bearing source substitution changes load-bearing identity"
        (match constructed, alternate_raven_receipt with
         | Ok inputs, Some raven ->
             let alternate_inputs =
               match canonical with
               | safety :: _rete :: _raven :: rest ->
                   safety
                   :: Run_assurance.Rete_input
                        (fixture.rete_network, fixture.rete_facts, fixture.rete)
                   :: Run_assurance.Raven_input (alternate_raven, raven)
                   :: rest
               | _ -> []
             in
             begin match
               Run_assurance.make_inputs ~context:gate_context alternate_inputs
             with
             | Error _ -> false
             | Ok alternate ->
                 not
                   (String.equal
                      (Run_assurance.receipt inputs).load_bearing_digest
                      (Run_assurance.receipt alternate).load_bearing_digest)
             end
         | Error _, _ | Ok _, None -> false)

let run_foundation () =
  Printf.printf "[bdd] assurance requires the complete six-gate evidence denominator\n";
  begin match context "run-assurance" with
  | Error _ -> check "the assurance context is admitted" false
  | Ok gate_context ->
      check "the assurance context is admitted" true;
      check "Ruliad and Stan completeness joins the four load-bearing gates"
        (Run_assurance.required_gates = upstream_gates);
      run_exact_assurance_reds gate_context;
      begin match
        Run_assurance.evaluate_inputs gate_context (all_unavailable gate_context)
      with
      | Ok (Run_assurance.Block reasons, assurance) ->
          check "every unavailable upstream gate remains an explicit blocker"
            (List.length reasons = List.length upstream_gates);
          check "only the assurance evaluator emits an Assurance receipt"
            (assurance.gate = Run_safety.Assurance
             && assurance.authority = Run_safety.Load_bearing_dispatch_gate);
          check "assurance receipt remains exact-context bound"
            (Result.is_ok
               (Run_safety.validate_receipt ~context:gate_context assurance))
      | _ ->
          check "every unavailable upstream gate remains an explicit blocker" false;
          check "only the assurance evaluator emits an Assurance receipt" false;
          check "assurance receipt remains exact-context bound" false
      end;

      Printf.printf "[mutation] analysis-only evidence is required but cannot promote\n";
      let without_ruliad =
        all_unavailable gate_context
        |> List.filter (fun item -> item.Run_safety.gate <> Run_safety.Ruliad)
      in
      begin match Run_assurance.evaluate_inputs gate_context without_ruliad with
      | Ok (Run_assurance.Block reasons, assurance) ->
          check "missing Ruliad completeness blocks without gaining authority"
            (List.exists (String.equal "missing required gate: ruliad") reasons
             && Run_safety.authority_of_gate Run_safety.Ruliad
                = Run_safety.Analysis_only);
          check "the blocked assurance receipt is honest"
            (match assurance.outcome with Run_safety.Rejected _ -> true | _ -> false)
      | _ ->
          check "missing Ruliad completeness blocks without gaining authority" false;
          check "the blocked assurance receipt is honest" false
      end;

      Printf.printf "[mutation] duplicate and circular receipt bundles fail closed\n";
      let unavailable_bundle = all_unavailable gate_context in
      let rete =
        List.find_opt
          (fun (item : Run_safety.receipt) -> item.gate = Run_safety.Rete_ul)
          unavailable_bundle
      in
      begin match
        rete
      with
      | None -> check "a duplicate upstream gate is rejected before decision" false
      | Some rete ->
          begin match
            Run_assurance.evaluate_inputs gate_context (rete :: unavailable_bundle)
          with
          | Error errors ->
              check "a duplicate upstream gate is rejected before decision"
                (List.exists
                   (fun error -> error.Run_safety.code = Run_safety.Duplicate_receipt)
                   errors)
          | Ok _ -> check "a duplicate upstream gate is rejected before decision" false
          end
      end;

      let assurance_receipt =
        match Run_assurance.evaluate_inputs gate_context unavailable_bundle with
        | Ok (Run_assurance.Block _, value) -> Some value
        | _ -> None
      in
      begin match assurance_receipt with
      | None ->
          check "an Assurance input is rejected as circular" false;
          check "duplicate Assurance inputs are classified as duplicate and circular" false
      | Some assurance ->
          begin match
            Run_assurance.evaluate_inputs gate_context
              (assurance :: unavailable_bundle)
          with
          | Error errors ->
              check "an Assurance input is rejected as circular"
                (List.exists
                   (fun error -> error.Run_safety.code = Run_safety.Invalid_receipt)
                   errors)
          | Ok _ -> check "an Assurance input is rejected as circular" false
          end;
          begin match
            Run_assurance.evaluate_inputs gate_context
              (assurance :: assurance :: unavailable_bundle)
          with
          | Error errors ->
              check "duplicate Assurance inputs are classified as duplicate and circular"
                (List.exists
                   (fun error -> error.Run_safety.code = Run_safety.Duplicate_receipt)
                   errors
                 && List.exists
                      (fun error -> error.Run_safety.code = Run_safety.Invalid_receipt)
                      errors)
          | Ok _ ->
              check "duplicate Assurance inputs are classified as duplicate and circular" false
          end
      end;

      Printf.printf "[receipt-binding] exact six-receipt bundle is canonical authority\n";
      let full = all_unavailable gate_context in
      let reversed = List.rev full in
      begin match
        evaluate_assurance_receipt gate_context full,
        evaluate_assurance_receipt gate_context reversed
      with
      | Some left, Some right ->
          check "assurance bundle digest is input-order invariant"
            (String.equal left.evidence_digest right.evidence_digest
             && String.equal left.receipt_digest right.receipt_digest)
      | _ -> check "assurance bundle digest is input-order invariant" false
      end;
      let substituted =
        match
          Run_safety.z3_unavailable_receipt gate_context
            ~reason:"different unavailable solver evidence"
        with
        | Error _ -> []
        | Ok alternate ->
            alternate
            :: List.filter
                 (fun (item : Run_safety.receipt) -> item.gate <> Run_safety.Z3)
                 full
      in
      begin match
        evaluate_assurance_receipt gate_context full,
        evaluate_assurance_receipt gate_context substituted
      with
      | Some left, Some right ->
          check "substituting one valid same-gate receipt changes assurance evidence"
            (not (String.equal left.evidence_digest right.evidence_digest)
             && not (String.equal left.receipt_digest right.receipt_digest))
      | _ ->
          check "substituting one valid same-gate receipt changes assurance evidence" false
      end;
      let omitted =
        List.filter
          (fun (item : Run_safety.receipt) -> item.gate <> Run_safety.Stan_model)
          full
      in
      begin match
        evaluate_assurance_receipt gate_context full,
        evaluate_assurance_receipt gate_context omitted
      with
      | Some left, Some right ->
          check "omitting one required receipt changes assurance evidence"
            (not (String.equal left.evidence_digest right.evidence_digest))
      | _ -> check "omitting one required receipt changes assurance evidence" false
      end;

      begin match context "different-run" with
      | Error _ -> check "the mismatch context fixture is admitted" false
      | Ok other_context ->
          begin match
            Run_safety.z3_unavailable_receipt other_context
              ~reason:"foreign unavailable solver"
          with
          | Error _ -> check "the mismatch receipt fixture is constructed" false
          | Ok foreign ->
              begin match
                Run_assurance.evaluate_inputs gate_context
                  (foreign
                   :: (all_unavailable gate_context
                       |> List.filter
                            (fun item -> item.Run_safety.gate <> Run_safety.Z3)))
              with
              | Error errors ->
                  check "a cross-context receipt is rejected before decision"
                    (List.exists
                       (fun error -> error.Run_safety.code = Run_safety.Context_mismatch)
                       errors)
              | Ok _ -> check "a cross-context receipt is rejected before decision" false
              end
          end
      end
  end

let run_live_assurance_reds solver_path =
  Printf.printf
    "[live-assurance] exact six-source bundle consumes admitted Task-3 evidence\n";
  match context "run-assurance-live" with
  | Error _ -> check "L01 live assurance context is admitted" false
  | Ok gate_context ->
      check "L01 live assurance context is admitted" true;
      let campaign = live_z3_campaign () in
      let configuration = live_z3_configuration solver_path in
      check "L02 exact campaign and CLI authority construct"
        (Result.is_ok campaign && Result.is_ok configuration);
      begin match campaign, configuration, build_exact_fixture gate_context with
      | Ok campaign, Ok configuration, Some fixture ->
          let verified = Z3.verify gate_context ~campaign configuration in
          check "L03 Task-3 produces a real admitted Z3 receipt"
            (match verified with
             | Ok receipt -> receipt.admission = Z3.Admitted
             | Error _ -> false);
          begin match verified with
          | Error _ ->
              check "L04 exact live six-source inputs construct" false;
              check "L05 admitted sources mint an assurance bundle" false;
              check "L06 admitted bundle recomputes exactly" false
          | Ok z3 ->
              let inputs =
                Run_assurance.make_inputs ~context:gate_context
                  (ordered_live_inputs fixture campaign configuration z3)
              in
              check "L04 exact live six-source inputs construct"
                (Result.is_ok inputs);
              let bundle =
                match inputs with
                | Error _ -> None
                | Ok inputs ->
                    Run_assurance.admit ~context:gate_context inputs
                    |> Result.to_option
              in
              check "L05 admitted sources mint an assurance bundle"
                (match bundle with
                 | None -> false
                 | Some bundle ->
                     bundle.authority = Run_safety.Load_bearing_dispatch_gate
                     && String.equal bundle.context_digest
                          gate_context.context_digest
                     && String.equal bundle.current_head_digest
                          gate_context.current_head_digest
                     && Int64.equal bundle.current_at_ns
                          gate_context.current_at_ns
                     && String.length bundle.bundle_digest = 64);
              check "L06 admitted bundle recomputes exactly"
                (match bundle with
                 | None -> false
                 | Some bundle ->
                     Result.is_ok
                       (Run_assurance.validate_bundle ~context:gate_context bundle));
              let foreign = context "run-assurance-live-foreign" in
              check "L07 foreign context and head cannot validate the bundle"
                (match bundle, foreign with
                 | Some bundle, Ok foreign ->
                     Result.is_error
                       (Run_assurance.validate_bundle ~context:foreign bundle)
                 | None, _ | Some _, Error _ -> false);
              let mutations =
                [ ("L08 context digest mutation is rejected",
                   Run_assurance.For_test.Context_digest);
                  ("L09 current-head digest mutation is rejected",
                   Run_assurance.For_test.Current_head_digest);
                  ("L10 current-time mutation is rejected",
                   Run_assurance.For_test.Current_at_ns);
                  ("L11 authority inversion is rejected",
                   Run_assurance.For_test.Authority);
                  ("L12 receipt digest mutation is rejected",
                   Run_assurance.For_test.Receipt_digest);
                  ("L13 load-bearing digest mutation is rejected",
                   Run_assurance.For_test.Load_bearing_digest);
                  ("L14 completeness digest mutation is rejected",
                   Run_assurance.For_test.Completeness_digest);
                  ("L15 bundle digest mutation is rejected",
                   Run_assurance.For_test.Bundle_digest) ]
              in
              List.iter
                (fun (name, mutation) ->
                  check name
                    (match bundle with
                     | None -> false
                     | Some bundle ->
                         let mutant =
                           Run_assurance.For_test.mutate_bundle mutation bundle
                         in
                         Result.is_error
                           (Run_assurance.validate_bundle ~context:gate_context
                              mutant)))
                mutations
          end
      | _ ->
          check "L03 Task-3 produces a real admitted Z3 receipt" false;
          check "L04 exact live six-source inputs construct" false;
          check "L05 admitted sources mint an assurance bundle" false;
          check "L06 admitted bundle recomputes exactly" false
      end

let () =
  begin match Array.to_list Sys.argv |> List.tl with
  | [] -> run_foundation ()
  | [ "--z3"; solver_path ] ->
      run_foundation ();
      run_live_assurance_reds solver_path
  | arguments ->
      check ("unknown test mode: " ^ String.concat " " arguments) false
  end;
  Printf.printf "run_assurance_foundation: checks=%d failures=%d\n"
    !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_assurance"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)

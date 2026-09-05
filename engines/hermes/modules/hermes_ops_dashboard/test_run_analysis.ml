let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L6/observe rca=Implementation hazard=HZ-T6-ANALYSIS-01 check=%s\n"
      name
  end

let result_or_fail label = function
  | Ok value -> value
  | Error _ -> failwith label

let lowercase_sha256 value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let count_occurrences text needle =
  let width = String.length needle and length = String.length text in
  let rec loop index count =
    if width = 0 || index + width > length then count
    else if String.sub text index width = needle then
      loop (index + width) (count + 1)
    else loop (index + 1) count
  in
  loop 0 0

let close left right = Float.abs (left -. right) < 1e-12

let provenance : Run_model.provenance =
  { source_revision = "task6-analysis"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let context_for ~request_id =
  match
    Run_safety.For_test.current_head_receipt ~run_id:"run-analysis"
      ~provenance ~observed_at_ns:900L ~current_at_ns:1_000L
      ~expires_at_ns:2_000L
  with
  | Error _ as error -> error
  | Ok current_head ->
      Run_safety.make_gate_context ~current_head ~request_id
        ~activity_id:"activity.orient-gaps"
        ~coordinate:{ level = Ops_capability.L1; phase = Ops_capability.Orient }
        ~plane:Ops_capability.Control_plane

let context () = context_for ~request_id:"request-analysis"

let expected = function
  | Run_analysis.Ruliad -> (Run_safety.Ruliad, Run_safety.Analysis_only)
  | Run_analysis.Stan_model -> (Run_safety.Stan_model, Run_safety.Analysis_only)
  | Run_analysis.Z3 -> (Run_safety.Z3, Run_safety.Load_bearing_dispatch_gate)

let run_foundation () =
  Printf.printf "[unit] analysis authority is closed and non-promotable\n";
  begin match context () with
  | Error _ -> check "the analysis context is admitted" false
  | Ok context ->
      check "the analysis context is admitted" true;
      List.iter
        (fun engine ->
          let expected_gate, expected_authority = expected engine in
          match
            Run_analysis.unavailable_receipt context ~engine
              ~reason:"analysis engine evidence is not yet admitted"
          with
          | Error _ ->
              check "analysis engine constructs a receipt" false;
              check "analysis gate identity is exact" false;
              check "analysis authority is not promoted" false;
              check "analysis receipt remains context-bound" false
          | Ok receipt ->
              check "analysis engine constructs a receipt" true;
              check "analysis gate identity is exact"
                (receipt.gate = expected_gate);
              check "analysis authority is not promoted"
                (receipt.authority = expected_authority);
              check "analysis receipt remains context-bound"
                (Result.is_ok (Run_safety.validate_receipt ~context receipt)
                 && match receipt.outcome with
                    | Run_safety.Unavailable_observed _ -> true
                    | Run_safety.Satisfied | Run_safety.Rejected _ -> false))
        [ Run_analysis.Ruliad; Run_analysis.Stan_model; Run_analysis.Z3 ]
  end;
  check "Ruliad is analysis-only"
    (Run_analysis.authority Run_analysis.Ruliad = Run_safety.Analysis_only);
  check "Stan is analysis-only"
    (Run_analysis.authority Run_analysis.Stan_model = Run_safety.Analysis_only);
  check "Z3 remains a load-bearing gate"
    (Run_analysis.authority Run_analysis.Z3
     = Run_safety.Load_bearing_dispatch_gate)

type oracle_state = OA | OB | OC | OD

let oracle_key = function OA -> "a" | OB -> "b" | OC -> "c" | OD -> "d"

let oracle_moves = function
  | OA -> [ "left"; "right" ]
  | OB | OC -> [ "finish" ]
  | OD -> []

let oracle_apply state move =
  match state, move with
  | OA, "left" -> OB
  | OA, "right" -> OC
  | (OB | OC), "finish" -> OD
  | (OA | OB | OC | OD), _ -> state

let ruliad_states =
  [ { Run_analysis.Ruliad.stable_id = "a";
      evidence_digest = String.make 64 '1' };
    { stable_id = "b"; evidence_digest = String.make 64 '2' };
    { stable_id = "c"; evidence_digest = String.make 64 '3' };
    { stable_id = "d"; evidence_digest = String.make 64 '4' } ]

let ruliad_transitions =
  [ { Run_analysis.Ruliad.stable_id = "a-left-b"; from_state_id = "a";
      to_state_id = "b"; move_digest = String.make 64 '5' };
    { stable_id = "a-right-c"; from_state_id = "a"; to_state_id = "c";
      move_digest = String.make 64 '6' };
    { stable_id = "b-finish-d"; from_state_id = "b"; to_state_id = "d";
      move_digest = String.make 64 '7' };
    { stable_id = "c-finish-d"; from_state_id = "c"; to_state_id = "d";
      move_digest = String.make 64 '8' } ]

let ruliad_bounds : Run_analysis.Ruliad.bounds =
  { max_states = 16; max_edges = 32; max_depth = 8; max_paths = 64L }

let unavailable_reason expected = function
  | Some receipt ->
      begin match receipt.Run_analysis.Ruliad.outcome with
      | Run_analysis.Ruliad.Unavailable (observed, graph) ->
          observed = expected && not graph.confluent
      | Run_analysis.Ruliad.Completed _ -> false
      end
  | None -> false

let stan_observation ~scenario_id ~family_id ~sequence ~verdict digest =
  result_or_fail "valid Stan observation"
    (Run_analysis.Stan_model.make_observation ~scenario_id ~family_id ~sequence
       ~verdict ~evidence_digest:(String.make 64 digest))

let run_ruliad_and_stan () =
  let context = result_or_fail "valid analysis context" (context ()) in
  let other_context =
    result_or_fail "valid alternate analysis context"
      (context_for ~request_id:"request-analysis-other")
  in
  Printf.printf "[ruliad] bounded multiway evidence remains analysis-only\n";
  let system_result =
    Run_analysis.Ruliad.make_system ~initial_state_id:"a"
      ~states:ruliad_states ~transitions:ruliad_transitions
  in
  check "A1 canonical Ruliad system admits a closed referenced graph"
    (Result.is_ok system_result);
  let system = result_or_fail "valid Ruliad system" system_result in
  let first = Run_analysis.Ruliad.analyze context ~bounds:ruliad_bounds system in
  let receipt = match first with Ok receipt -> Some receipt | Error _ -> None in
  check "A2 completed Ruliad graph has exact state edge terminal path depth and confluence"
    (match receipt with
     | Some receipt ->
         begin match receipt.outcome with
         | Run_analysis.Ruliad.Completed graph ->
             graph.state_count = 4 && graph.edge_count = 4
             && graph.terminal_state_ids = [ "d" ]
             && graph.path_count = 2L && graph.max_depth = 2 && graph.confluent
         | Run_analysis.Ruliad.Unavailable _ -> false
         end
     | None -> false);
  let oracle : (oracle_state, string) Ruliad.system =
    { initial = OA; moves = oracle_moves; apply = oracle_apply;
      canonical = oracle_key }
  in
  let oracle_result = Ruliad.explore ~max_states:16 oracle in
  check "A3 completed adapter agrees with the independent existing Ruliad oracle"
    (match receipt, oracle_result with
     | Some receipt, Ok oracle_graph ->
         begin match receipt.outcome with
         | Run_analysis.Ruliad.Completed graph ->
             graph.state_count = oracle_graph.state_count
             && graph.edge_count = oracle_graph.edge_count
             && graph.path_count = Int64.of_int oracle_graph.path_count
             && graph.max_depth = oracle_graph.max_depth
             && graph.confluent = oracle_graph.confluent
         | Run_analysis.Ruliad.Unavailable _ -> false
         end
     | Some _, Error _ | None, (Ok _ | Error _) -> false);
  let replay = Run_analysis.Ruliad.analyze context ~bounds:ruliad_bounds system in
  check "A4 identical bounded analysis replays to an identical receipt digest"
    (match first, replay with
     | Ok first, Ok replay -> String.equal first.receipt_digest replay.receipt_digest
     | (Ok _ | Error _), (Ok _ | Error _) -> false);
  let permuted_system =
    result_or_fail "valid permuted Ruliad system"
      (Run_analysis.Ruliad.make_system ~initial_state_id:"a"
         ~states:(List.rev ruliad_states)
         ~transitions:(List.rev ruliad_transitions))
  in
  let permuted =
    Run_analysis.Ruliad.analyze context ~bounds:ruliad_bounds permuted_system
  in
  check "A5 input order cannot change Ruliad semantic identity"
    (match first, permuted with
     | Ok first, Ok permuted ->
         String.equal first.receipt_digest permuted.receipt_digest
     | (Ok _ | Error _), (Ok _ | Error _) -> false);
  check "A6 Ruliad receipt is current context-bound and analysis-only"
    (match receipt with
     | Some receipt ->
         receipt.authority = Run_safety.Analysis_only
         && receipt.context_digest = context.context_digest
         && receipt.current_head_digest = context.current_head_digest
         && receipt.current_at_ns = context.current_at_ns
         && lowercase_sha256 receipt.receipt_digest
         && Result.is_ok (Run_analysis.Ruliad.validate_receipt ~context receipt)
         && Result.is_error
              (Run_analysis.Ruliad.validate_receipt ~context:other_context receipt)
     | None -> false);
  let analyze_with bounds =
    match Run_analysis.Ruliad.analyze context ~bounds system with
    | Ok receipt -> Some receipt
    | Error _ -> None
  in
  check "A7 state cap returns bounded partial graph and never confluence"
    (unavailable_reason Run_analysis.Ruliad.State_cap
       (analyze_with { ruliad_bounds with max_states = 2 }));
  check "A8 edge cap returns bounded partial graph and never confluence"
    (unavailable_reason Run_analysis.Ruliad.Edge_cap
       (analyze_with { ruliad_bounds with max_edges = 2 }));
  check "A9 depth cap returns bounded partial graph and never confluence"
    (unavailable_reason Run_analysis.Ruliad.Depth_cap
       (analyze_with { ruliad_bounds with max_depth = 1 }));
  check "A10 path cap uses checked int64 arithmetic and returns unavailable"
    (unavailable_reason Run_analysis.Ruliad.Path_cap
       (analyze_with { ruliad_bounds with max_paths = 1L }));
  let cyclic =
    result_or_fail "valid cyclic relation"
      (Run_analysis.Ruliad.make_system ~initial_state_id:"a"
         ~states:(List.filter
           (fun (state : Run_analysis.Ruliad.state) ->
             List.mem state.stable_id [ "a"; "b" ])
           ruliad_states)
         ~transitions:
           [ List.hd ruliad_transitions;
             { Run_analysis.Ruliad.stable_id = "b-back-a";
               from_state_id = "b"; to_state_id = "a";
               move_digest = String.make 64 '9' } ])
  in
  check "A11 cyclic Ruliad relation is unavailable rather than divergent"
    (match Run_analysis.Ruliad.analyze context ~bounds:ruliad_bounds cyclic with
     | Ok receipt ->
         unavailable_reason Run_analysis.Ruliad.Cyclic_relation (Some receipt)
     | Error _ -> false);
  check "A12 zero or negative Ruliad bounds fail before exploration"
    (Result.is_error
       (Run_analysis.Ruliad.analyze context
          ~bounds:{ ruliad_bounds with max_edges = 0 } system));
  check "A13 duplicate state identity is rejected"
    (Result.is_error
       (Run_analysis.Ruliad.make_system ~initial_state_id:"a"
          ~states:(List.hd ruliad_states :: ruliad_states)
          ~transitions:ruliad_transitions));
  check "A14 unknown transition endpoint is rejected"
    (Result.is_error
       (Run_analysis.Ruliad.make_system ~initial_state_id:"a"
          ~states:ruliad_states
          ~transitions:
            ({ Run_analysis.Ruliad.stable_id = "d-missing";
               from_state_id = "d"; to_state_id = "missing";
               move_digest = String.make 64 'a' }
             :: ruliad_transitions)));
  check "A14.1 exact Ruliad validation accepts only the declared completed analysis"
    (match receipt with
     | Some receipt ->
         receipt.authority = Run_safety.Analysis_only
         && Result.is_ok
              (Run_analysis.Ruliad.validate_exact ~context ~system
                 ~bounds:ruliad_bounds receipt)
     | None -> false);
  let substituted_states =
    List.map
      (fun (state : Run_analysis.Ruliad.state) ->
        if String.equal state.stable_id "d" then
          { state with evidence_digest = String.make 64 'f' }
        else state)
      ruliad_states
  in
  let substituted_system =
    result_or_fail "valid substituted Ruliad system"
      (Run_analysis.Ruliad.make_system ~initial_state_id:"a"
         ~states:substituted_states ~transitions:ruliad_transitions)
  in
  let substituted_system_receipt =
    Run_analysis.Ruliad.analyze context ~bounds:ruliad_bounds substituted_system
  in
  check "A14.2 exact Ruliad validation rejects a coherent system substitution"
    (match substituted_system_receipt with
     | Ok substituted ->
         Result.is_ok
           (Run_analysis.Ruliad.validate_receipt ~context substituted)
         && Result.is_error
              (Run_analysis.Ruliad.validate_exact ~context ~system
                 ~bounds:ruliad_bounds substituted)
     | Error _ -> false);
  let substituted_bounds = { ruliad_bounds with max_states = 17 } in
  let substituted_bounds_receipt =
    Run_analysis.Ruliad.analyze context ~bounds:substituted_bounds system
  in
  check "A14.3 exact Ruliad validation rejects a coherent bounds substitution"
    (match substituted_bounds_receipt with
     | Ok substituted ->
         Result.is_ok
           (Run_analysis.Ruliad.validate_receipt ~context substituted)
         && Result.is_error
              (Run_analysis.Ruliad.validate_exact ~context ~system
                 ~bounds:ruliad_bounds substituted)
     | Error _ -> false);
  check "A14.4 exact Ruliad validation refuses incomplete bounded exploration"
    (match analyze_with { ruliad_bounds with max_depth = 1 } with
     | Some incomplete ->
         Result.is_ok
           (Run_analysis.Ruliad.validate_receipt ~context incomplete)
         && Result.is_error
              (Run_analysis.Ruliad.validate_exact ~context ~system
                 ~bounds:{ ruliad_bounds with max_depth = 1 } incomplete)
     | None -> false);
  check "A14.5 exact Ruliad validation preserves exact context and head identity"
    (match receipt with
     | Some receipt ->
         Result.is_error
           (Run_analysis.Ruliad.validate_exact ~context:other_context ~system
              ~bounds:ruliad_bounds receipt)
     | None -> false);

  Printf.printf "[stan] latest-per-scenario analytic reliability remains analysis-only\n";
  let old_a =
    stan_observation ~scenario_id:"scenario-a" ~family_id:"core" ~sequence:1L
      ~verdict:Run_analysis.Stan_model.Failed 'a'
  in
  let latest_a =
    stan_observation ~scenario_id:"scenario-a" ~family_id:"core" ~sequence:2L
      ~verdict:Run_analysis.Stan_model.Passed 'b'
  in
  let latest_b =
    stan_observation ~scenario_id:"scenario-b" ~family_id:"core" ~sequence:3L
      ~verdict:Run_analysis.Stan_model.Failed 'c'
  in
  let observations = [ old_a; latest_a; latest_b ] in
  let input_result =
    Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
      ~all_families:[ "core"; "ui" ] ~observations
  in
  check "A15 Stan input admits finite positive priors and unique latest evidence"
    (Result.is_ok input_result);
  let input = result_or_fail "valid Stan input" input_result in
  let stan_first = Run_analysis.Stan_model.analyze context input in
  let stan_receipt =
    match stan_first with Ok receipt -> Some receipt | Error _ -> None
  in
  let core_summary =
    match stan_receipt with
    | Some receipt ->
        List.find_opt
          (fun summary -> summary.Run_analysis.Stan_model.family_id = "core")
          receipt.summaries
    | None -> None
  in
  check "A16 historical reruns are not pseudo-replicated into the denominator"
    (match core_summary with
     | Some summary -> summary.scenario_count = 2 && summary.passing_count = 1
     | None -> false);
  let baseline = Receipt_reliability.posterior ~a:1.0 ~b:1.0 ~n:2 ~k:1 in
  let baseline_low, baseline_high = Receipt_reliability.cred95 baseline in
  check "A17 Stan analytic moments agree with the independent conjugate baseline"
    (match core_summary with
     | Some summary ->
         close summary.posterior_alpha baseline.alpha
         && close summary.posterior_beta baseline.beta
         && close summary.mean (Receipt_reliability.mean baseline)
         && close summary.variance (Receipt_reliability.variance baseline)
         && close summary.moment_band_low baseline_low
         && close summary.moment_band_high baseline_high
     | None -> false);
  check "A18 unmeasured families are disclosed outside the denominator"
    (match stan_receipt with
     | Some receipt ->
         receipt.unmeasured_families = [ "ui" ]
         && not receipt.coverage_complete
     | None -> false);
  check "A19 Stan receipt is current context-bound deterministic and analysis-only"
    (match stan_receipt with
     | Some receipt ->
         receipt.model = Run_analysis.Stan_model.Beta_binomial_analytic_moment_band_v1
         && receipt.authority = Run_safety.Analysis_only
         && receipt.context_digest = context.context_digest
         && receipt.current_head_digest = context.current_head_digest
         && receipt.current_at_ns = context.current_at_ns
         && lowercase_sha256 receipt.model_digest
         && lowercase_sha256 receipt.result_digest
         && lowercase_sha256 receipt.receipt_digest
         && Result.is_ok
              (Run_analysis.Stan_model.validate_receipt ~context receipt)
         && Result.is_error
              (Run_analysis.Stan_model.validate_receipt ~context:other_context
                 receipt)
     | None -> false);
  let permuted_input =
    result_or_fail "valid permuted Stan input"
      (Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
         ~all_families:[ "ui"; "core" ]
         ~observations:(List.rev observations))
  in
  check "A20 input order cannot change Stan receipt identity"
    (match stan_first, Run_analysis.Stan_model.analyze context permuted_input with
     | Ok first, Ok permuted ->
         String.equal first.receipt_digest permuted.receipt_digest
     | (Ok _ | Error _), (Ok _ | Error _) -> false);
  let conflicting_latest =
    stan_observation ~scenario_id:"scenario-a" ~family_id:"core" ~sequence:2L
      ~verdict:Run_analysis.Stan_model.Failed 'd'
  in
  check "A21 ambiguous duplicate latest scenario sequence is rejected"
    (Result.is_error
       (Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
          ~all_families:[ "core" ]
          ~observations:[ latest_a; conflicting_latest ]));
  let reused_evidence =
    result_or_fail "valid observation reusing evidence identity"
      (Run_analysis.Stan_model.make_observation ~scenario_id:"scenario-c"
         ~family_id:"core" ~sequence:4L
         ~verdict:Run_analysis.Stan_model.Passed
         ~evidence_digest:latest_b.evidence_digest)
  in
  check "A22 one evidence receipt cannot be pseudo-replicated across scenarios"
    (Result.is_error
       (Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
          ~all_families:[ "core" ]
          ~observations:[ latest_b; reused_evidence ]));
  check "A23 nonpositive NaN and infinite priors fail closed"
    (List.for_all Result.is_error
       [ Run_analysis.Stan_model.make_input ~prior_alpha:0.0 ~prior_beta:1.0
           ~all_families:[ "core" ] ~observations:[ latest_a ];
         Run_analysis.Stan_model.make_input ~prior_alpha:Float.nan ~prior_beta:1.0
           ~all_families:[ "core" ] ~observations:[ latest_a ];
         Run_analysis.Stan_model.make_input ~prior_alpha:1.0
           ~prior_beta:Float.infinity ~all_families:[ "core" ]
           ~observations:[ latest_a ] ]);
  check "A24 observation families must resolve in the declared population"
    (Result.is_error
       (Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
          ~all_families:[ "ui" ] ~observations:[ latest_a ]));
  let changed_latest =
    stan_observation ~scenario_id:"scenario-a" ~family_id:"core" ~sequence:2L
      ~verdict:Run_analysis.Stan_model.Failed 'e'
  in
  let changed_input =
    result_or_fail "valid changed Stan input"
      (Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
         ~all_families:[ "core"; "ui" ]
         ~observations:[ old_a; changed_latest; latest_b ])
  in
  check "A25 latest verdict mutation changes Stan result and receipt identity"
    (match stan_first, Run_analysis.Stan_model.analyze context changed_input with
     | Ok first, Ok changed ->
         not (String.equal first.result_digest changed.result_digest)
         && not (String.equal first.receipt_digest changed.receipt_digest)
     | (Ok _ | Error _), (Ok _ | Error _) -> false);
  let complete_input =
    result_or_fail "valid complete Stan input"
      (Run_analysis.Stan_model.make_input ~prior_alpha:1.0 ~prior_beta:1.0
         ~all_families:[ "core" ] ~observations)
  in
  let complete_receipt = Run_analysis.Stan_model.analyze context complete_input in
  check "A25.1 exact Stan validation accepts complete declared coverage only"
    (match complete_receipt with
     | Ok receipt ->
         receipt.authority = Run_safety.Analysis_only
         && receipt.coverage_complete
         && Result.is_ok
              (Run_analysis.Stan_model.validate_exact ~context
                 ~input:complete_input receipt)
     | Error _ -> false);
  let substituted_input =
    result_or_fail "valid substituted Stan input"
      (Run_analysis.Stan_model.make_input ~prior_alpha:2.0 ~prior_beta:1.0
         ~all_families:[ "core" ] ~observations)
  in
  let substituted_input_receipt =
    Run_analysis.Stan_model.analyze context substituted_input
  in
  check "A25.2 exact Stan validation rejects a coherent input substitution"
    (match substituted_input_receipt with
     | Ok substituted ->
         Result.is_ok
           (Run_analysis.Stan_model.validate_receipt ~context substituted)
         && Result.is_error
              (Run_analysis.Stan_model.validate_exact ~context
                 ~input:complete_input substituted)
     | Error _ -> false);
  check "A25.3 exact Stan validation refuses incomplete population coverage"
    (match stan_receipt with
     | Some incomplete ->
         Result.is_ok
           (Run_analysis.Stan_model.validate_receipt ~context incomplete)
         && Result.is_error
              (Run_analysis.Stan_model.validate_exact ~context ~input incomplete)
     | None -> false);
  check "A25.4 exact Stan validation preserves exact context and head identity"
    (match complete_receipt with
     | Ok receipt ->
         Result.is_error
           (Run_analysis.Stan_model.validate_exact ~context:other_context
              ~input:complete_input receipt)
     | Error _ -> false)

let starts_with ~prefix value =
  let width = String.length prefix in
  String.length value >= width && String.sub value 0 width = prefix

let fake_z3_mode () =
  let basename = Filename.basename Sys.argv.(0) in
  let prefix = "run-analysis-z3-fixture-" in
  if starts_with ~prefix basename then
    Some (String.sub basename (String.length prefix)
            (String.length basename - String.length prefix))
  else None

let fake_z3_child mode =
  (* The timeout fixture must be TERM-resistant from its first instruction.
     [with_fake_z3] establishes the inherited POSIX ignored disposition before
     exec; repeat it here before version dispatch or any wait so the query
     branch cannot accidentally weaken that fixture contract. *)
  if String.equal mode "timeout" then
    Sys.set_signal Sys.sigterm Sys.Signal_ignore;
  let version_request =
    Array.exists (fun argument -> String.equal argument "-version") Sys.argv
  in
  if version_request then begin
    begin match mode with
    | "wrong-version" -> print_endline "Z3 version 3.2.0 - 64 bit"
    | "malformed-version" -> print_endline "Z3 version not-a-version"
    | "version-nonzero" ->
        prerr_endline "fixture version failure";
        flush stderr;
        exit 8
    | "version-oversize" -> print_endline (String.make 4_096 'v')
    | _ -> print_endline "Z3 version 4.16.0 - 64 bit"
    end;
    flush stdout
  end else
    match mode with
    | "all-sat" -> print_endline "sat"; flush stdout
    | "all-unsat" -> print_endline "unsat"; flush stdout
    | "malformed" -> print_endline "not-a-solver-result"; flush stdout
    | "unknown" -> print_endline "unknown"; flush stdout
    | "slow-sat" ->
        ignore (Unix.select [] [] [] 0.05);
        print_endline "sat";
        flush stdout
    | "nonzero" -> prerr_endline "fixture solver failure"; flush stderr; exit 7
    | "timeout" ->
        ignore (Unix.select [] [] [] 2.0);
        print_endline "sat";
        flush stdout
    | "oversize" ->
        print_string (String.make 4_096 'x');
        print_endline "sat";
        flush stdout
    | "wrong-version" | "malformed-version" | "version-oversize" ->
        print_endline "sat";
        flush stdout
    | _ -> prerr_endline "unknown fixture mode"; flush stderr; exit 9

let fixture_executable_authority = Unix.realpath Sys.executable_name

let with_fake_z3 mode use =
  let seed = Filename.temp_dir ~perms:0o700 "run-analysis-z3-" ".fixture" in
  let executable =
    Filename.concat seed ("run-analysis-z3-fixture-" ^ mode)
  in
  let use_fixture () =
    Unix.symlink fixture_executable_authority executable;
    use executable
  in
  Fun.protect
    ~finally:(fun () ->
      (try
         if (Unix.lstat executable).st_kind = Unix.S_LNK then
           Sys.remove executable
       with Unix.Unix_error _ | Sys_error _ -> ());
      (try Unix.rmdir seed with Unix.Unix_error _ -> ()))
    (fun () ->
      if String.equal mode "timeout" then
        let previous = Sys.signal Sys.sigterm Sys.Signal_ignore in
        Fun.protect
          ~finally:(fun () -> Sys.set_signal Sys.sigterm previous)
          use_fixture
      else use_fixture ())

let make_z3_configuration ?(timeout_ms = 5_000)
    ?(termination_grace_ms = 100) ?(maximum_output_bytes = 65_536)
    executable =
  Run_analysis.Z3.make_cli_configuration ~executable ~timeout_ms
    ~termination_grace_ms ~maximum_output_bytes

let make_z3_campaign ?(maximum_total_elapsed_ms = 180_000) () =
  Run_analysis.Z3.make_campaign_envelope ~maximum_total_elapsed_ms
    ~linked_max_allocated_bytes:268_435_456L
    ~linked_max_heap_words:33_554_432
    ~linked_virtual_memory_bytes:536_870_912L ~linked_cpu_seconds:2
    ~linked_maximum_query_bytes:1_048_576
    ~linked_maximum_output_bytes:65_536
    ~maximum_worker_rss_bytes:536_870_912L

let process_succeeded (process : Run_analysis.Z3.process_receipt) =
  process.status = Run_analysis.Z3.Exited 0
  && process.child_created && process.reaped

let obligation_for stable_id =
  List.find_opt
    (fun (obligation : Run_formal.obligation) ->
      String.equal obligation.stable_id stable_id)
    Run_formal.obligations

let backend_metadata_exact (row : Run_analysis.Z3.backend_receipt) =
  match obligation_for row.obligation_stable_id with
  | None -> false
  | Some obligation ->
      String.equal row.requirement_id obligation.requirement_id
      && row.kind = obligation.kind
      && row.expected = obligation.expected
      && String.equal row.query_digest obligation.query_digest
      && row.query_bytes = String.length obligation.smt2
      && row.obligation_timeout_ms = obligation.timeout_ms
      && String.equal row.solver_id obligation.solver_id
      && String.equal row.solver_version_constraint
           obligation.solver_version_constraint

let formal_obligation_count = List.length Run_formal.obligations

let formal_kind_count kind =
  List.fold_left
    (fun count (obligation : Run_formal.obligation) ->
      if obligation.kind = kind then count + 1 else count)
    0 Run_formal.obligations

let exact_backend_order rows =
  List.length rows = formal_obligation_count
  && List.map
       (fun (row : Run_analysis.Z3.backend_receipt) -> row.obligation_stable_id)
       rows
     = List.map
         (fun (obligation : Run_formal.obligation) -> obligation.stable_id)
         Run_formal.obligations

let observed_exact expected_kind expected_result
    (row : Run_analysis.Z3.backend_receipt) =
  row.kind = expected_kind && row.observed = expected_result

let first_cli_receipt = function
  | Ok receipt ->
      begin match receipt.Run_analysis.Z3.cli with
      | row :: _ -> Some row
      | [] -> None
      end
  | Error _ -> None

let run_z3_case context campaign ~mode ?(timeout_ms = 5_000)
    ?(maximum_output_bytes = 65_536) () =
  with_fake_z3 mode (fun executable ->
    match
      make_z3_configuration executable ~timeout_ms ~maximum_output_bytes
        ~termination_grace_ms:(max 1 (min 50 timeout_ms))
    with
    | Error errors -> Error (`Configuration (String.concat "; " errors))
    | Ok configuration ->
        match Run_analysis.Z3.verify context ~campaign configuration with
        | Error error -> Error (`Verification error.Run_safety.message)
        | Ok receipt ->
            begin match
              Run_analysis.Z3.validate_receipt ~context ~campaign configuration
                receipt
            with
            | Ok () -> Ok receipt
            | Error error -> Error (`Verification error.Run_safety.message)
            end)

let copy_executable_with_trailing_byte source destination =
  let input_channel = open_in_bin source in
  let output_channel = open_out_bin destination in
  Fun.protect
    ~finally:(fun () ->
      close_in_noerr input_channel;
      close_out_noerr output_channel)
    (fun () ->
      let chunk = Bytes.create 65_536 in
      let rec copy () =
        match input input_channel chunk 0 (Bytes.length chunk) with
        | 0 ->
            output_char output_channel '\000';
            flush output_channel
        | count ->
            output output_channel chunk 0 count;
            copy ()
      in
      copy ());
  Unix.chmod destination 0o700

let run_z3_executable_toctou context campaign =
  with_fake_z3 "all-sat" (fun executable ->
    match make_z3_configuration executable with
    | Error _ -> Error `Configuration
    | Ok configuration ->
        let replacement = executable ^ ".replacement" in
        Fun.protect
          ~finally:(fun () ->
            try Sys.remove replacement with Sys_error _ -> ())
          (fun () ->
            copy_executable_with_trailing_byte
              fixture_executable_authority replacement;
            Sys.remove executable;
            Unix.rename replacement executable;
            match Run_analysis.Z3.verify context ~campaign configuration with
            | Ok receipt -> Ok receipt
            | Error _ -> Error `Verification))

let run_z3 solver_path =
  let context = result_or_fail "valid Z3 analysis context" (context ()) in
  let other_context =
    result_or_fail "valid alternate Z3 analysis context"
      (context_for ~request_id:"request-analysis-z3-other")
  in
  Printf.printf "[z3] exact Run_formal obligations require two supervised solver paths\n";
  let campaign_result = make_z3_campaign () in
  check "Z0 declared total and linked-memory limits form a private campaign envelope"
    (match campaign_result with
     | Ok value ->
         not (Filename.is_relative value.linked_worker_executable)
         && lowercase_sha256 value.linked_worker_executable_digest
         && let maximum_obligation_timeout_ms =
              List.fold_left
                (fun maximum (obligation : Run_formal.obligation) ->
                  Int.max maximum obligation.timeout_ms)
                0 Run_formal.obligations
            in
            let worker_timeout_ms =
              Int.min value.maximum_total_elapsed_ms
                maximum_obligation_timeout_ms
            in
            value.maximum_teardown_ms =
              worker_timeout_ms + (2 * Int.min 100 worker_timeout_ms)
         && let authoritative_query_bytes =
              List.fold_left
                (fun total (obligation : Run_formal.obligation) ->
                  total + String.length obligation.smt2)
                0 Run_formal.obligations
            in
            value.maximum_receipt_materialization_ms =
              formal_obligation_count
              + ((authoritative_query_bytes + 2_047) / 2_048)
         && value.linked_virtual_memory_bytes = 536_870_912L
         && value.linked_cpu_seconds = 2
         && value.maximum_worker_rss_bytes = 536_870_912L
         && lowercase_sha256 value.envelope_digest
     | Error _ -> false);
  let campaign = result_or_fail "valid Z3 campaign envelope" campaign_result in
  let configuration_result = make_z3_configuration solver_path in
  check "Z1 absolute solver path and bounded policy form private configuration"
    (match configuration_result with
     | Ok value ->
         value.version_probe_timeout_ms = Int.max 2_000 value.timeout_ms
         && value.version_probe_timeout_ms <= 60_000
     | Error _ -> false);
  let configuration =
    result_or_fail "valid Z3 CLI configuration" configuration_result
  in
  check "Z2 malformed path and nonpositive supervision settings fail closed"
    (List.for_all Result.is_error
       [ make_z3_configuration "relative-z3";
         make_z3_configuration solver_path ~timeout_ms:0;
         make_z3_configuration solver_path ~termination_grace_ms:0;
         make_z3_configuration solver_path ~maximum_output_bytes:0 ]);
  check "Z3 formal authority is exactly 42 obligations with 35 controls and 7 laws"
    (formal_obligation_count = 42
     && formal_kind_count Run_formal.False_control = 35
     && formal_kind_count Run_formal.Negated_law = 7
     && Run_formal.validate_obligations Run_formal.obligations = []);
  let verified = Run_analysis.Z3.verify context ~campaign configuration in
  check "Z4 exact linked and CLI solver campaign returns an evidence receipt"
    (Result.is_ok verified);
  let receipt = match verified with Ok value -> Some value | Error _ -> None in
  check "Z5 receipt binds load-bearing authority current context and specification"
    (match receipt with
     | Some value ->
         value.authority = Run_safety.Load_bearing_dispatch_gate
         && String.equal value.context_digest context.context_digest
         && String.equal value.current_head_digest context.current_head_digest
         && value.current_at_ns = context.current_at_ns
         && String.equal value.specification_digest Run_formal.specification_digest
         && String.equal value.cli_configuration_digest
              configuration.configuration_digest
         && String.equal value.campaign_envelope_digest
              campaign.envelope_digest
     | None -> false);
  check "Z6 each backend has exactly one row for every formal obligation"
    (match receipt with
     | Some value ->
         List.length value.in_process = formal_obligation_count
         && List.length value.cli = formal_obligation_count
     | None -> false);
  check "Z7 backend rows preserve exact query requirement kind expected and budgets"
    (match receipt with
     | Some value ->
         exact_backend_order value.in_process
         && exact_backend_order value.cli
         && List.for_all backend_metadata_exact value.in_process
         && List.for_all backend_metadata_exact value.cli
     | None -> false);
  check "Z8 linked worker and injected CLI have independent exact executable provenance"
    (match receipt with
     | Some value ->
         exact_backend_order value.in_process
         && exact_backend_order value.cli
         && List.for_all
           (fun (row : Run_analysis.Z3.backend_receipt) ->
             row.backend = Run_analysis.Z3.Linked_smtml_z3
             && Option.is_some row.linked_library_version
             && row.executable_path = Some campaign.linked_worker_executable
             && row.executable_digest =
                  Some campaign.linked_worker_executable_digest
             && campaign.linked_worker_executable <> solver_path
             && campaign.linked_worker_executable_digest
                  <> configuration.executable_digest
             && Option.fold ~none:false ~some:process_succeeded row.process
             && Option.fold ~none:false ~some:lowercase_sha256
                  row.linked_request_digest
             && Option.fold ~none:false ~some:lowercase_sha256
                  row.linked_limits_digest
             && Option.fold ~none:false ~some:lowercase_sha256
                  row.linked_handshake_digest
             && Option.fold ~none:false ~some:lowercase_sha256
                  row.linked_result_digest
             && String.trim row.solver_version <> "")
           value.in_process
         && List.for_all
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.backend = Run_analysis.Z3.Injected_z3_cli
                && row.linked_library_version = None
                && row.executable_path = Some solver_path
                && row.executable_digest = Some configuration.executable_digest
                && Option.is_some row.process
                && String.trim row.solver_version <> "")
              value.cli
     | None -> false);
  check "Z9 CLI version discovery is argv-only bounded successful and reaped"
    (match receipt with
     | Some value ->
         process_succeeded value.cli_version_process
         && value.cli_version_process.stdout_bytes
              <= configuration.maximum_output_bytes
         && value.cli_version_process.stderr_bytes
              <= configuration.maximum_output_bytes
     | None -> false);
  check "Z10 every CLI obligation process exits zero and is reaped"
    (match receipt with
     | Some value ->
         exact_backend_order value.cli
         && List.for_all
           (fun (row : Run_analysis.Z3.backend_receipt) ->
             match row.process with
             | Some process -> process_succeeded process
             | None -> false)
           value.cli
     | None -> false);
  check "Z11 every process output is bounded with full byte and digest evidence"
    (match receipt with
     | Some value ->
         exact_backend_order value.cli
         && List.for_all
           (fun (row : Run_analysis.Z3.backend_receipt) ->
             match row.process with
             | Some process ->
                 process.stdout_bytes <= configuration.maximum_output_bytes
                 && process.stderr_bytes <= configuration.maximum_output_bytes
                 && lowercase_sha256 process.stdout_digest
                 && lowercase_sha256 process.stderr_digest
                 && lowercase_sha256 process.receipt_digest
             | None -> false)
           value.cli
     | None -> false);
  check "Z12 both backends observe every false control as Sat"
    (match receipt with
     | Some value ->
         List.length
           (List.filter
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.kind = Run_formal.False_control)
              (value.in_process @ value.cli))
         = 2 * formal_kind_count Run_formal.False_control
         && List.for_all
           (fun row ->
             if row.Run_analysis.Z3.kind = Run_formal.False_control then
               observed_exact Run_formal.False_control Run_formal.Sat row
             else true)
           (value.in_process @ value.cli)
     | None -> false);
  check "Z13 both backends observe every negated law as Unsat"
    (match receipt with
     | Some value ->
         List.length
           (List.filter
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.kind = Run_formal.Negated_law)
              (value.in_process @ value.cli))
         = 2 * formal_kind_count Run_formal.Negated_law
         && List.for_all
           (fun row ->
             if row.Run_analysis.Z3.kind = Run_formal.Negated_law then
               observed_exact Run_formal.Negated_law Run_formal.Unsat row
             else true)
           (value.in_process @ value.cli)
     | None -> false);
  check "Z14 complete controls laws and cross-backend agreement are all required for admission"
    (match receipt with
     | Some value ->
         value.controls_complete && value.laws_complete
         && value.cross_backend_agreement
         && value.admission = Run_analysis.Z3.Admitted
     | None -> false);
  check "Z15 receipt validation accepts exact current context and rejects another"
    (match receipt with
     | Some value ->
         Result.is_ok
           (Run_analysis.Z3.validate_receipt ~context ~campaign configuration
              value)
         && Result.is_error
              (Run_analysis.Z3.validate_receipt ~context:other_context ~campaign
                 configuration value)
     | None -> false);
  check "Z16 campaign and row identities are canonical lowercase SHA-256"
    (match receipt with
     | Some value ->
         lowercase_sha256 value.obligation_set_digest
         && lowercase_sha256 value.result_digest
         && lowercase_sha256 value.receipt_digest
         && exact_backend_order value.in_process
         && exact_backend_order value.cli
         && List.for_all
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                lowercase_sha256 row.query_digest
                && lowercase_sha256 row.receipt_digest)
              (value.in_process @ value.cli)
     | None -> false);
  let changed_configuration =
    make_z3_configuration solver_path ~timeout_ms:4_999
  in
  check "Z17 CLI timeout mutation changes declarative configuration identity"
    (match changed_configuration with
     | Ok changed ->
         not
           (String.equal configuration.configuration_digest
              changed.configuration_digest)
     | Error _ -> false);
  let disagreement = run_z3_case context campaign ~mode:"all-sat" () in
  check "Z18 CLI law disagreement blocks instead of copying expected host truth"
    (match disagreement with
     | Ok value ->
         not value.cross_backend_agreement
         && value.admission = Run_analysis.Z3.Blocked
         && List.exists
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.kind = Run_formal.Negated_law
                && row.observed = Run_formal.Sat)
              value.cli
     | Error _ -> false);
  let malformed = run_z3_case context campaign ~mode:"malformed" () in
  check "Z19 malformed zero-exit solver output is typed Unavailable and blocks"
    (match malformed, first_cli_receipt malformed with
     | Ok value, Some row ->
         value.admission = Run_analysis.Z3.Blocked
         && row.observed = Run_formal.Unavailable
         && Option.fold ~none:false ~some:process_succeeded row.process
     | (Ok _ | Error _), _ -> false);
  let unknown = run_z3_case context campaign ~mode:"unknown" () in
  check "Z20 solver Unknown remains typed and blocks load-bearing admission"
    (match unknown, first_cli_receipt unknown with
     | Ok value, Some row ->
         value.admission = Run_analysis.Z3.Blocked
         && row.observed = Run_formal.Unknown
     | (Ok _ | Error _), _ -> false);
  let nonzero = run_z3_case context campaign ~mode:"nonzero" () in
  check "Z21 nonzero CLI status is reaped typed Unavailable and blocking"
    (match nonzero, first_cli_receipt nonzero with
     | Ok value, Some row ->
         value.admission = Run_analysis.Z3.Blocked
         && row.observed = Run_formal.Unavailable
         && Option.fold ~none:false
              ~some:(fun process ->
                process.Run_analysis.Z3.status = Run_analysis.Z3.Exited 7
                && process.reaped)
              row.process
     | (Ok _ | Error _), _ -> false);
  let missing =
    make_z3_configuration
      (Filename.concat (Filename.get_temp_dir_name ())
         "run-analysis-z3-does-not-exist")
  in
  check "Z22 missing injected executable fails before it can fabricate credit"
    (Result.is_error missing);
  let timed_out =
    (* The fixture is this OCaml executable reached through a symlink.  Give
       its version-only startup a bounded 250 ms, then the query path still
       deterministically ignores TERM for two seconds and exercises KILL. *)
    run_z3_case context campaign ~mode:"timeout" ~timeout_ms:250 ()
  in
  check "Z23 timed out TERM-resistant child is killed reaped and blocking"
    (match timed_out, first_cli_receipt timed_out with
     | Ok value, Some row ->
         value.admission = Run_analysis.Z3.Blocked
         && row.observed = Run_formal.Timeout
         && Option.fold ~none:false
              ~some:(fun process ->
                process.Run_analysis.Z3.status = Run_analysis.Z3.Timed_out
                && process.child_created && process.reaped)
              row.process
     | (Ok _ | Error _), _ -> false);
  let oversized =
    run_z3_case context campaign ~mode:"oversize" ~maximum_output_bytes:64 ()
  in
  check "Z24 output beyond the declared bound is unavailable without unbounded receipt text"
    (match oversized, first_cli_receipt oversized with
     | Ok value, Some row ->
         value.admission = Run_analysis.Z3.Blocked
         && row.observed = Run_formal.Unavailable
         && Option.fold ~none:false
              ~some:(fun process ->
                process.Run_analysis.Z3.stdout_bytes > 64
                && String.length process.stdout <= 64
                && process.reaped)
              row.process
     | (Ok _ | Error _), _ -> false);
  let wrong_version = run_z3_case context campaign ~mode:"wrong-version" () in
  check "Z25 successful out-of-range version probe is explicitly diagnosed before rows"
    (match wrong_version with
     | Ok value ->
         value.admission = Run_analysis.Z3.Blocked
         && process_succeeded value.cli_version_process
         && String.equal value.cli_version_process.stdout
              "Z3 version 3.2.0 - 64 bit\n"
         && value.cli = []
         && List.exists
              (fun (diagnostic : Run_analysis.Z3.diagnostic) ->
                String.equal diagnostic.code "Z3-UNSUPPORTED-VERSION"
                && lowercase_sha256 diagnostic.detail_digest
                && lowercase_sha256 diagnostic.diagnostic_digest
                && diagnostic.coordinate = context.coordinate
                && diagnostic.rca_origin = Ops_capability.Environment
                && String.equal diagnostic.hazard_id "HZ-T6-Z3-01")
              value.diagnostics
     | Error _ -> false);
  let all_unsat = run_z3_case context campaign ~mode:"all-unsat" () in
  check "Z26 false-control Unsat mutation independently blocks host-truth fabrication"
    (match all_unsat with
     | Ok value ->
         value.admission = Run_analysis.Z3.Blocked
         && not value.controls_complete
         && List.exists
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.kind = Run_formal.False_control
                && row.observed = Run_formal.Unsat)
              value.cli
     | Error _ -> false);
  check "Z27 every backend row binds exact executed and stable readback query identity"
    (match receipt with
     | Some value ->
         List.for_all
           (fun (row : Run_analysis.Z3.backend_receipt) ->
             String.equal row.executed_query_digest row.query_digest
             && String.equal row.readback_query_digest row.query_digest
             && row.readback_query_bytes = row.query_bytes
             && row.query_object_identity_stable
             && lowercase_sha256 row.query_object_identity_digest)
           (value.in_process @ value.cli)
     | None -> false);
  check "Z28 linked rows prove one real solver call and parsed assertion denominator"
    (match receipt with
     | Some value ->
         exact_backend_order value.in_process
         && List.for_all
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                match row.linked_invocation with
                | Some invocation ->
                    invocation.solver_call_delta = 1
                    && Option.fold ~none:false
                         ~some:(fun obligation ->
                           invocation.assertion_count =
                           count_occurrences obligation.Run_formal.smt2
                             "(assert ")
                         (obligation_for row.obligation_stable_id)
                    && lowercase_sha256 invocation.invocation_digest
                | None -> false)
              value.in_process
         && List.for_all
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.linked_invocation = None)
              value.cli
     | None -> false);
  check "Z29 unreaped or adverse supervision facts can never become process credit"
    (Run_analysis.Z3.supervision_admissible
       ~status:(Run_analysis.Z3.Exited 0) ~child_created:true
       ~term_sent:false ~kill_sent:false ~reaped:true
     && not
          (Run_analysis.Z3.supervision_admissible
             ~status:(Run_analysis.Z3.Exited 0) ~child_created:true
             ~term_sent:false ~kill_sent:false ~reaped:false)
     && not
          (Run_analysis.Z3.supervision_admissible
             ~status:Run_analysis.Z3.Timed_out ~child_created:true
             ~term_sent:true ~kill_sent:true ~reaped:true)
     && not
          (Run_analysis.Z3.supervision_admissible
             ~status:Run_analysis.Z3.Supervision_failed ~child_created:true
             ~term_sent:true ~kill_sent:true ~reaped:false));
  check "Z30 TERM-resistant timeout records TERM KILL and successful reap"
    (match timed_out, first_cli_receipt timed_out with
     | Ok _, Some row ->
         Option.fold ~none:false
           ~some:(fun process ->
             process.Run_analysis.Z3.term_sent
             && process.kill_sent && process.reaped)
           row.process
     | (Ok _ | Error _), _ -> false);
  let post_version_cases =
    [ disagreement; malformed; unknown; nonzero; timed_out; oversized; all_unsat ]
  in
  check "Z31 every post-version adverse campaign emits the exact typed formal denominator per backend"
    (List.for_all
       (function
         | Ok value ->
             value.Run_analysis.Z3.row_policy = Run_analysis.Z3.Full_denominator
             && exact_backend_order value.in_process
             && exact_backend_order value.cli
         | Error _ -> false)
       post_version_cases);
  let malformed_version =
    run_z3_case context campaign ~mode:"malformed-version" ()
  in
  check "Z32 malformed successful version output fails fast with zero solver rows"
    (match malformed_version with
     | Ok value ->
         value.Run_analysis.Z3.row_policy = Run_analysis.Z3.Preflight_fail_fast
         && value.in_process = [] && value.cli = []
         && process_succeeded value.cli_version_process
         && List.exists
              (fun (diagnostic : Run_analysis.Z3.diagnostic) ->
                String.equal diagnostic.code "Z3-VERSION-MALFORMED")
              value.diagnostics
     | Error _ -> false);
  let version_nonzero =
    run_z3_case context campaign ~mode:"version-nonzero" ()
  in
  check "Z33 nonzero reaped version probe fails fast with exact process evidence"
    (match version_nonzero with
     | Ok value ->
         value.Run_analysis.Z3.row_policy = Run_analysis.Z3.Preflight_fail_fast
         && value.in_process = [] && value.cli = []
         && value.cli_version_process.status = Run_analysis.Z3.Exited 8
         && value.cli_version_process.child_created
         && value.cli_version_process.reaped
     | Error _ -> false);
  let version_oversize =
    run_z3_case context campaign ~mode:"version-oversize"
      ~maximum_output_bytes:64 ()
  in
  check "Z34 oversized version probe fails fast with bounded text and full bytes"
    (match version_oversize with
     | Ok value ->
         value.Run_analysis.Z3.row_policy = Run_analysis.Z3.Preflight_fail_fast
         && value.in_process = [] && value.cli = []
         && value.cli_version_process.stdout_bytes > 64
         && String.length value.cli_version_process.stdout <= 64
         && value.cli_version_process.reaped
     | Error _ -> false);
  let executable_toctou = run_z3_executable_toctou context campaign in
  check "Z35 executable content TOCTOU fails before any solver row"
    (match executable_toctou with
     | Ok value ->
         value.Run_analysis.Z3.row_policy = Run_analysis.Z3.Preflight_fail_fast
         && value.in_process = [] && value.cli = []
         && List.exists
              (fun (diagnostic : Run_analysis.Z3.diagnostic) ->
                String.equal diagnostic.code "Z3-EXECUTABLE-CHANGED")
              value.diagnostics
     | Error _ -> false);
  check "Z36 pure query execution admission rejects every digest identity mismatch"
    (Run_analysis.Z3.query_execution_admissible
       ~authoritative_digest:(String.make 64 'a')
       ~executed_digest:(String.make 64 'a')
       ~readback_digest:(String.make 64 'a')
       ~authoritative_bytes:17 ~readback_bytes:17
       ~object_identity_stable:true
     && not
          (Run_analysis.Z3.query_execution_admissible
             ~authoritative_digest:(String.make 64 'a')
             ~executed_digest:(String.make 64 'b')
             ~readback_digest:(String.make 64 'a')
             ~authoritative_bytes:17 ~readback_bytes:17
             ~object_identity_stable:true)
     && not
          (Run_analysis.Z3.query_execution_admissible
             ~authoritative_digest:(String.make 64 'a')
             ~executed_digest:(String.make 64 'a')
             ~readback_digest:(String.make 64 'a')
             ~authoritative_bytes:17 ~readback_bytes:16
             ~object_identity_stable:true)
     && not
          (Run_analysis.Z3.query_execution_admissible
             ~authoritative_digest:(String.make 64 'a')
             ~executed_digest:(String.make 64 'a')
             ~readback_digest:(String.make 64 'a')
             ~authoritative_bytes:17 ~readback_bytes:17
             ~object_identity_stable:false));
  check "Z37 linked worker memory evidence proves hard isolation and measured RSS below the declared sub-1-GiB bound"
    (match receipt with
     | Some value ->
         String.equal value.memory_evidence.envelope_digest
           campaign.envelope_digest
         && value.memory_evidence.hard_isolated
         && value.memory_evidence.within_envelope
         && value.memory_evidence.peak_rss_bytes > 0L
         && value.memory_evidence.peak_rss_bytes
              <= campaign.maximum_worker_rss_bytes
         && value.memory_evidence.peak_rss_bytes < 1_073_741_824L
         && value.memory_evidence.virtual_memory_limit_bytes
              = campaign.linked_virtual_memory_bytes
         && value.memory_evidence.cpu_limit_seconds
              = campaign.linked_cpu_seconds
         && String.equal value.memory_evidence.worker_executable_digest
              campaign.linked_worker_executable_digest
         && lowercase_sha256 value.memory_evidence.limits_digest
         && lowercase_sha256 value.memory_evidence.evidence_digest
     | None -> false);
  check "Z38 complete exact dual-backend evidence admits without an isolation-unavailable diagnostic"
    (match receipt with
     | Some value ->
         value.admission = Run_analysis.Z3.Admitted
         && not (List.exists
              (fun (diagnostic : Run_analysis.Z3.diagnostic) ->
                String.equal diagnostic.code
                  "Z3-LINKED-MEMORY-ISOLATION-UNAVAILABLE")
              value.diagnostics)
     | None -> false);
  let short_campaign =
    result_or_fail "valid short Z3 campaign envelope"
      (make_z3_campaign ~maximum_total_elapsed_ms:120 ())
  in
  let deadline_partial =
    run_z3_case context short_campaign ~mode:"slow-sat" ()
  in
  check "Z39 one total campaign deadline yields typed bounded partial rows on expiry"
    (match deadline_partial with
     | Ok value ->
         value.Run_analysis.Z3.row_policy =
           Run_analysis.Z3.Campaign_deadline_partial
         && value.campaign_deadline_exhausted
         && value.campaign_elapsed_ns >= 120_000_000L
         && value.campaign_elapsed_ns
              <= Int64.mul
                   (Int64.of_int
                      (short_campaign.maximum_total_elapsed_ms
                       + short_campaign.maximum_teardown_ms
                       + short_campaign.maximum_receipt_materialization_ms))
                   1_000_000L
         && exact_backend_order value.in_process
         && exact_backend_order value.cli
         && List.exists
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.observed = Run_formal.Unavailable
                && row.process = None
                && List.exists
                     (fun diagnostic ->
                       String.equal diagnostic.Run_analysis.Z3.code
                         "Z3-CAMPAIGN-DEADLINE")
                     row.diagnostics)
              value.cli
         && value.admission = Run_analysis.Z3.Blocked
         && List.exists
              (fun (diagnostic : Run_analysis.Z3.diagnostic) ->
                String.equal diagnostic.code "Z3-CAMPAIGN-DEADLINE")
              value.diagnostics
     | Error _ -> false)
  ;
  check "Z40 every linked row binds the canonical worker request limits handshake result and process receipts"
    (match receipt with
     | Some value ->
         exact_backend_order value.in_process
         && List.for_all
              (fun (row : Run_analysis.Z3.backend_receipt) ->
                row.backend = Run_analysis.Z3.Linked_smtml_z3
                && Option.fold ~none:false ~some:lowercase_sha256
                     row.linked_request_digest
                && row.linked_limits_digest =
                     Some value.memory_evidence.limits_digest
                && Option.fold ~none:false ~some:lowercase_sha256
                     row.linked_handshake_digest
                && Option.fold ~none:false ~some:lowercase_sha256
                     row.linked_result_digest
                && Option.fold ~none:false ~some:process_succeeded row.process)
              value.in_process
     | None -> false);
  check "Z41 exact validation rejects a positive but wrong linked assertion denominator"
    (match receipt with
     | Some value ->
         Run_analysis.Z3.For_test.mutate_receipt
           Positive_wrong_assertion_count value
         |> Run_analysis.Z3.validate_receipt ~context ~campaign configuration
         |> Result.is_error
     | None -> false);
  check "Z42 exact validation rejects every syntactically valid substituted linked transcript digest"
    (match receipt with
     | Some value ->
         [ Run_analysis.Z3.For_test.Substituted_linked_request_digest;
           Substituted_linked_handshake_digest;
           Substituted_linked_result_digest ]
         |> List.for_all (fun mutation ->
              Run_analysis.Z3.For_test.mutate_receipt mutation value
              |> Run_analysis.Z3.validate_receipt ~context ~campaign configuration
              |> Result.is_error)
     | None -> false)

let () =
  match fake_z3_mode () with
  | Some mode -> fake_z3_child mode
  | None ->
      begin match Array.to_list Sys.argv |> List.tl with
      | [] -> run_foundation ()
      | [ "--analysis" ] -> run_ruliad_and_stan ()
      | [ "--z3"; solver_path ] -> run_z3 solver_path
      | arguments ->
          check ("unknown test mode: " ^ String.concat " " arguments) false
      end;
      Printf.printf "run_analysis: checks=%d failures=%d\n" !checks !failures;
      let self =
        Suite_telemetry.observe ~suite:"test_run_analysis"
          ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
      in
      print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
      exit (Suite_telemetry.exit_code self)

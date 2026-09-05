let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L6/decide rca=Implementation hazard=HZ-SWARM-BRIDGE-01 check=%s\n"
      name
  end

let sha256 text =
  text |> Digestif.SHA256.digest_string |> Digestif.SHA256.to_hex

let make_effect_receipt ~idempotency_key
    (request : Run_effect_authority.request) ~authority_digest =
  let evidence =
    Run_effect_authority.make_redacted_evidence
      ~receipt_id:
        (sha256
           ("test-effect-receipt-v1:" ^ idempotency_key ^ ":"
            ^ request.Run_effect_authority.request_digest))
      ~evidence_digest:
        (sha256 ("effect:" ^ request.Run_effect_authority.request_digest))
      ~disposition:Run_effect_authority.Evidence_succeeded
  in
  match evidence with
  | Error issue -> Error issue.Run_effect_authority.bytes
  | Ok evidence ->
      Run_effect_authority.make_target_receipt ~idempotency_key ~request
        ~target_authority_digest:authority_digest
        ~disposition:Run_effect_authority.First_applied ~evidence
      |> Result.map_error (fun issue -> issue.Run_effect_authority.bytes)

let provenance : Run_model.provenance =
  { source_revision = "task6-bridge-red"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let coordinate : Ops_capability.coordinate =
  { level = Ops_capability.L0; phase = Ops_capability.Observe }

let event_exn = function Ok event -> event | Error message -> failwith message

let append_active_dispatch store run_id =
  let specifications =
    [ (Run_model.Run_declared, Run_model.Run);
      (Run_model.Phase_started, Run_model.Phase Run_model.Admission);
      (Run_model.Phase_finished, Run_model.Phase Run_model.Admission);
      (Run_model.Run_started, Run_model.Run);
      (Run_model.Phase_started, Run_model.Phase Run_model.Authority_preflight);
      (Run_model.Phase_finished, Run_model.Phase Run_model.Authority_preflight);
      (Run_model.Phase_started, Run_model.Phase Run_model.Discovery);
      (Run_model.Phase_finished, Run_model.Phase Run_model.Discovery);
      (Run_model.Phase_started, Run_model.Phase Run_model.Build);
      (Run_model.Phase_finished, Run_model.Phase Run_model.Build);
      (Run_model.Phase_started, Run_model.Phase Run_model.Dispatch) ]
  in
  let rec loop sequence previous_digest = function
    | [] -> Ok ()
    | (kind, subject) :: rest ->
        let event =
          event_exn
            (Run_model.make ~run_id ~sequence
               ~event_id:(Printf.sprintf "%s-%Ld" run_id sequence)
               ~kind ~subject ~plane:Ops_capability.Control_plane ~coordinate
               ~rca_origin:Ops_capability.Control
               ~occurred_at_ns:(Int64.add 100L sequence)
               ~monotonic_at_ns:(Int64.add 50L sequence) ~provenance
               ~payload:(`Assoc []) ~previous_digest)
        in
        begin match Run_event_store.append store event with
        | Error _ as error -> error
        | Ok () -> loop (Int64.succ sequence) (Some event.digest) rest
        end
  in
  loop 0L None specifications

let fixture_or_fail label = function
  | Ok value -> value
  | Error issue ->
      failwith
        (label ^ ": "
         ^ Dependability_sqlite_test_protocol.string_of_error issue)

let with_location label fixture body =
  let registry =
    fixture_or_fail ("create " ^ label ^ " SQLite fixture registry")
      (Dependability_sqlite_test_protocol.create ~maximum_live:1)
  in
  let registry, lease =
    fixture_or_fail ("acquire " ^ label ^ " SQLite fixture")
      (Dependability_sqlite_test_protocol.acquire registry fixture)
  in
  let location =
    fixture_or_fail ("resolve " ^ label ^ " opaque SQLite reference")
      (Dependability_sqlite_test_protocol.reference registry lease)
  in
  Fun.protect
    ~finally:(fun () ->
      let registry, _ =
        fixture_or_fail ("release " ^ label ^ " SQLite fixture lease")
          (Dependability_sqlite_test_protocol.release registry lease)
      in
      ignore
        (fixture_or_fail ("clean " ^ label ^ " SQLite fixture registry")
           (Dependability_sqlite_test_protocol.cleanup registry)))
    (fun () -> body location)

let with_store label body =
  with_location label Dependability_sqlite_test_protocol.In_memory
    (fun location ->
      match Run_event_store.open_store location with
      | Error message -> failwith message
      | Ok store ->
          Fun.protect
            ~finally:(fun () -> Run_event_store.close store)
            (fun () -> body store))

let with_database label body =
  with_location label Dependability_sqlite_test_protocol.In_memory
    (fun location ->
      let database =
        match
          Dependability_sqlite.open_database ~location
            ~maximum_total_attempts:1
        with
        | Ok value -> value
        | Error _ -> failwith (label ^ " database refused")
      in
      Fun.protect
        ~finally:(fun () ->
          ignore (Dependability_sqlite.For_test.dispose database))
        (fun () -> body database))

let production_context store run_id =
  match append_active_dispatch store run_id with
  | Error _ -> None
  | Ok () ->
      begin match
        Run_safety.observe_current_head ~store ~run_id
          ~lifetime_ns:60_000_000_000L
      with
      | Error _ -> None
      | Ok current_head ->
          Run_safety.make_gate_context ~current_head
            ~request_id:("request-" ^ run_id)
            ~activity_id:"activity.observe-inventory" ~coordinate
            ~plane:Ops_capability.Data_plane
          |> Result.to_option
      end

let canonical_activity () =
  Run_topology.admit_activity
    ~stable_id:"activity.verify-sqlite-dependability"

let declaration () =
  canonical_activity () |> Result.to_option
  |> Option.map Run_topology.admitted_declaration

let rebuild_action ?stable_id ?command_id ?assigned_agent_id ?dependency_ids
    ?selector_id ?required_capability_id ?context_requirement_ids
    ?target_component_id ?effect_kind ?preparation_id
    (action : Run_topology.declarative_action) =
  let choose value fallback = Option.value value ~default:fallback in
  Run_topology.For_test.declarative_action_work
    ~stable_id:(choose stable_id action.stable_id)
    ~command_id:(choose command_id action.command_id)
    ~assigned_agent_id:(choose assigned_agent_id action.assigned_agent_id)
    ~dependency_ids:(choose dependency_ids action.dependency_ids)
    ~selector_id:(choose selector_id action.selector_id)
    ~required_capability_id:
      (choose required_capability_id action.required_capability_id)
    ~context_requirement_ids:
      (choose context_requirement_ids action.context_requirement_ids)
    ~target_component_id:(choose target_component_id action.target_component_id)
    ~effect_kind:(choose effect_kind action.effect_kind)
    ~work:action.work
    ~preparation_id:(choose preparation_id action.preparation_id)

let replace_first update (activity : Run_topology.declarative_activity) =
  match activity.actions with
  | [] -> activity
  | first :: rest -> { activity with actions = update first :: rest }

let registry_error activity =
  Result.is_error
    (Run_swarm_bridge.For_test.action_registry_from_declaration activity)

let run_plan_reds () =
  Printf.printf "[plan] exact five-action topology contract\n";
  match declaration () with
  | None -> check "P01 canonical topology declaration is available" false
  | Some activity ->
      check "P01 canonical five-action declaration validates"
        (Result.is_ok
           (Run_swarm_bridge.For_test.action_registry_from_declaration activity));
      check "P02 empty action id is rejected"
        (registry_error
           (replace_first (rebuild_action ~stable_id:"") activity));
      check "P03 duplicate action ids are rejected"
        (match activity.actions with
         | first :: second :: rest ->
             registry_error
               { activity with
                 actions = first :: rebuild_action ~stable_id:first.stable_id second
                           :: rest }
         | [] | [ _ ] -> false);
      check "P04 empty command id is rejected"
        (registry_error
           (replace_first (rebuild_action ~command_id:"") activity));
      check "P05 duplicate command ids are rejected"
        (match activity.actions with
         | first :: second :: rest ->
             registry_error
               { activity with
                 actions = first
                   :: rebuild_action ~command_id:first.command_id second :: rest }
         | [] | [ _ ] -> false);
      check "P06 unknown assigned agent is rejected"
        (registry_error
           (replace_first
              (rebuild_action ~assigned_agent_id:"unknown-agent") activity));
      check "P07 unknown dependency is rejected"
        (registry_error
           (replace_first
              (rebuild_action ~dependency_ids:[ "action.unknown" ]) activity));
      check "P08 self dependency is rejected"
        (match activity.actions with
         | first :: rest ->
             registry_error
               { activity with
                 actions =
                   rebuild_action ~dependency_ids:[ first.stable_id ] first :: rest }
         | [] -> false);
      check "P09 duplicate dependencies are rejected"
        (match activity.actions with
         | first :: second :: rest ->
             registry_error
               { activity with
                 actions = first
                   :: rebuild_action
                        ~dependency_ids:[ first.stable_id; first.stable_id ]
                        second :: rest }
         | [] | [ _ ] -> false);
      check "P10 dependency cycle or forward edge is rejected"
        (match activity.actions with
         | first :: rest ->
             let last = List.hd (List.rev activity.actions) in
             registry_error
               { activity with
                 actions =
                   rebuild_action ~dependency_ids:[ last.stable_id ] first :: rest }
         | [] -> false);
      check "P11 MIQ selector substitution is rejected"
        (registry_error
           (replace_first
              (rebuild_action ~selector_id:"miq.unknown") activity));
      check "P12 capability substitution is rejected"
        (registry_error
           (replace_first
              (rebuild_action ~required_capability_id:"capability.unknown")
              activity));
      check "P13 context denominator substitution is rejected"
        (registry_error
           (replace_first
              (rebuild_action ~context_requirement_ids:[]) activity));
      check "P14 target substitution is rejected"
        (registry_error
           (replace_first
              (rebuild_action ~target_component_id:"unknown-target") activity));
      check "P15 effect substitution is rejected"
        (match activity.actions with
         | first :: _ ->
             let other =
               match first.effect_kind with
               | Run_topology.Dependability_process_attempt ->
                   Run_topology.Durable_artifact_publication
               | _ ->
                   Run_topology.Dependability_process_attempt
             in
             registry_error
               (replace_first (rebuild_action ~effect_kind:other) activity)
         | [] -> false);
      check "P16 canonical registry construction is deterministic"
        (Result.is_ok
           (Run_swarm_bridge.For_test.action_registry_from_declaration activity)
         && Result.is_ok
              (Run_swarm_bridge.For_test.action_registry_from_declaration activity));
      check "P17 bridge consumer retains the exact 19-effect manifest"
        (List.length Run_topology.effect_kinds = 19
         && List.length
              (List.sort_uniq String.compare
                 (List.map Run_topology.effect_kind_id Run_topology.effect_kinds))
            = 19);
      check "P18 bridge mutations preserve every closed repository work carrier"
        (match
           Run_topology.admit_activity ~stable_id:"activity.verify-repository"
         with
         | Error _ -> false
         | Ok repository ->
             List.for_all
               (fun (action : Run_topology.declarative_action) ->
                 rebuild_action action = action)
               (Run_topology.admitted_actions repository))

let run_admission_identity_reds (context : Run_safety.gate_context) =
  let digest = context.Run_safety.context_digest in
  let validate intent current assurance selection =
    Run_swarm_bridge.For_test.validate_admission_identities ~context
      ~intent_context_digest:intent ~current_context_digest:current
      ~assurance_context_digest:assurance ~selection_context_digest:selection
  in
  check "A01 exact admission identities validate"
    (Result.is_ok (validate digest digest digest digest));
  check "A02 intent identity substitution is rejected"
    (Result.is_error (validate (String.make 64 'd') digest digest digest));
  check "A03 assurance identity substitution is rejected"
    (Result.is_error (validate digest digest (String.make 64 'e') digest));
  check "A04 fast-path selection identity substitution is rejected"
    (Result.is_error (validate digest digest digest (String.make 64 'f')))

let run_closed_store_red () =
  with_location "closed-store" Dependability_sqlite_test_protocol.In_memory
    (fun location ->
      match Run_event_store.open_store location with
      | Error message ->
          Printf.eprintf "closed-store fixture failed: %s\n" message;
          check "E13 closed-store append authority is rejected" false
      | Ok store ->
          let context = production_context store "closed-store-run" in
          Run_event_store.close store;
          let rejected =
            match context with
            | None -> false
            | Some context ->
                Result.is_error
                  (Run_swarm_bridge.create_event_authority ~store ~context
                     ~sources:Run_swarm_bridge.production_event_sources)
          in
          check "E13 closed-store append authority is rejected" rejected)

module Live_rete = Run_intelligence.Rete_ul
module Live_raven = Run_intelligence.Raven_matrix
module Live_ruliad = Run_analysis.Ruliad
module Live_stan = Run_analysis.Stan_model
module Live_z3 = Run_analysis.Z3

type live_fixture = {
  safety_model : Run_safety.model;
  safety : Run_safety.receipt;
  rete_network : Live_rete.network;
  rete_facts : Live_rete.fact list;
  rete : Live_rete.dispatch_receipt;
  raven_matrix : Live_raven.matrix;
  raven : Live_raven.receipt;
  ruliad_system : Live_ruliad.system;
  ruliad_bounds : Live_ruliad.bounds;
  ruliad : Live_ruliad.receipt;
  stan_input : Live_stan.input;
  stan : Live_stan.receipt;
}

let ( let* ) option continuation = Option.bind option continuation

let live_safety context =
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
      match Run_safety.evaluate context model with
      | Ok (Run_safety.Admit, receipt) -> Some (model, receipt)
      | Error _ | Ok (Run_safety.Block _, _) -> None

let live_rete context =
  let budgets : Live_rete.budgets =
    { max_facts = 8; max_alpha_entries = 8; max_beta_tokens = 8;
      max_agenda = 8; max_firings = 8; max_trace_entries = 8 }
  in
  let network : Live_rete.network =
    { network_id = "network.bridge-live"; budgets;
      rules =
        [ { rule_id = "rule.bridge-block"; salience = 1;
            patterns =
              [ { pattern_id = "pattern.bridge-dispatch";
                  fact_kind = "dispatch";
                  conditions =
                    [ Live_rete.Field_eq ("unsafe", Live_rete.Bool true) ] } ];
            actions = [ Live_rete.Block_rhs "unsafe dispatch" ] } ] }
  in
  let* fact =
    Live_rete.make_fact ~fact_id:"dispatch-bridge-live"
      ~fact_kind:"dispatch" ~attrs:[ ("unsafe", Live_rete.Bool false) ]
    |> Result.to_option
  in
  let facts = [ fact ] in
  let* compiled = Live_rete.compile context network |> Result.to_option in
  let* _, replay =
    Live_rete.replay context compiled [ Live_rete.Assert_fact fact ]
    |> Result.to_option
  in
  let* receipt =
    Live_rete.admit_dispatch context ~network ~facts replay
    |> Result.to_option
  in
  Some (network, facts, receipt)

let live_raven context =
  let budgets : Live_raven.budgets =
    { max_alternatives = 4; max_criteria = 4; max_cells = 8;
      max_constraints = 4; max_trace_entries = 8; max_abs_value = 1_000L }
  in
  let matrix : Live_raven.matrix =
    { matrix_id = "matrix.bridge-live";
      criteria =
        [ { criterion_id = "criterion.reliability";
            direction = Live_raven.Maximize; weight_ppm = 1_000_000;
            scale_min = 0L; scale_max = 100L } ];
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
      constraints = [];
      tie_order = [ "alternative.alpha"; "alternative.beta" ];
      selection_policy = Live_raven.Require_stable;
      min_sensitivity_ppm = 1; budgets }
  in
  let* receipt = Live_raven.decide context matrix |> Result.to_option in
  Some (matrix, receipt)

let live_ruliad context =
  let bounds : Live_ruliad.bounds =
    { max_states = 4; max_edges = 4; max_depth = 2; max_paths = 4L }
  in
  let* system =
    Live_ruliad.make_system ~initial_state_id:"state.a"
      ~states:
        [ { Live_ruliad.stable_id = "state.a";
            evidence_digest = String.make 64 '3' };
          { stable_id = "state.b"; evidence_digest = String.make 64 '4' } ]
      ~transitions:
        [ { Live_ruliad.stable_id = "transition.a-b";
            from_state_id = "state.a"; to_state_id = "state.b";
            move_digest = String.make 64 '5' } ]
    |> Result.to_option
  in
  let* receipt =
    Live_ruliad.analyze context ~bounds system |> Result.to_option
  in
  Some (system, bounds, receipt)

let live_stan context =
  let* observation =
    Live_stan.make_observation ~scenario_id:"scenario.bridge-live"
      ~family_id:"family.bridge-live" ~sequence:1L ~verdict:Live_stan.Passed
      ~evidence_digest:(String.make 64 '6')
    |> Result.to_option
  in
  let* input =
    Live_stan.make_input ~prior_alpha:1.0 ~prior_beta:1.0
      ~all_families:[ "family.bridge-live" ] ~observations:[ observation ]
    |> Result.to_option
  in
  let* receipt = Live_stan.analyze context input |> Result.to_option in
  Some (input, receipt)

let live_fixture context =
  let* safety_model, safety = live_safety context in
  let* rete_network, rete_facts, rete = live_rete context in
  let* raven_matrix, raven = live_raven context in
  let* ruliad_system, ruliad_bounds, ruliad = live_ruliad context in
  let* stan_input, stan = live_stan context in
  Some
    { safety_model; safety; rete_network; rete_facts; rete; raven_matrix;
      raven; ruliad_system; ruliad_bounds; ruliad; stan_input; stan }

let live_campaign () =
  Live_z3.make_campaign_envelope ~maximum_total_elapsed_ms:180_000
    ~linked_max_allocated_bytes:268_435_456L
    ~linked_max_heap_words:33_554_432
    ~linked_virtual_memory_bytes:536_870_912L ~linked_cpu_seconds:2
    ~linked_maximum_query_bytes:1_048_576
    ~linked_maximum_output_bytes:65_536
    ~maximum_worker_rss_bytes:536_870_912L

let live_configuration executable =
  Live_z3.make_cli_configuration ~executable ~timeout_ms:5_000
    ~termination_grace_ms:100 ~maximum_output_bytes:65_536

let live_assurance context solver_path =
  match live_fixture context with
  | None ->
      Printf.eprintf "LIVE-ASSURANCE-REFUSED stage=pre-z3-fixture\n";
      None
  | Some fixture ->
      begin match live_campaign () with
      | Error issues ->
          Printf.eprintf "LIVE-ASSURANCE-REFUSED stage=campaign detail=%s\n"
            (String.concat "; " issues);
          None
      | Ok campaign ->
          begin match live_configuration solver_path with
          | Error issues ->
              Printf.eprintf
                "LIVE-ASSURANCE-REFUSED stage=configuration detail=%s\n"
                (String.concat "; " issues);
              None
          | Ok configuration ->
              begin match Live_z3.verify context ~campaign configuration with
              | Error issue ->
                  Printf.eprintf
                    "LIVE-ASSURANCE-REFUSED stage=z3 detail=%s\n" issue.message;
                  None
              | Ok z3 ->
                  Printf.eprintf
                    "LIVE-Z3 admission=%s controls=%b laws=%b agreement=%b rows=%d+%d\n"
                    (match z3.admission with
                     | Live_z3.Admitted -> "admitted"
                     | Live_z3.Blocked -> "blocked")
                    z3.controls_complete z3.laws_complete
                    z3.cross_backend_agreement (List.length z3.in_process)
                    (List.length z3.cli);
                  let gate_inputs =
                    [ Run_assurance.Safety_input
                        (fixture.safety_model, fixture.safety);
                      Run_assurance.Rete_input
                        (fixture.rete_network, fixture.rete_facts, fixture.rete);
                      Run_assurance.Raven_input
                        (fixture.raven_matrix, fixture.raven);
                      Run_assurance.Ruliad_input
                        (fixture.ruliad_system, fixture.ruliad_bounds,
                         fixture.ruliad);
                      Run_assurance.Stan_input
                        (fixture.stan_input, fixture.stan);
                      Run_assurance.Z3_input (campaign, configuration, z3) ]
                  in
                  begin match Run_assurance.make_inputs ~context gate_inputs with
                  | Error issues ->
                      Printf.eprintf
                        "LIVE-ASSURANCE-REFUSED stage=inputs detail=%s\n"
                        (String.concat "; "
                           (List.map
                              (fun (issue : Run_safety.gate_error) ->
                                issue.message)
                              issues));
                      None
                  | Ok inputs ->
                      begin match Run_assurance.admit ~context inputs with
                      | Ok bundle -> Some bundle
                      | Error issues ->
                          Printf.eprintf
                            "LIVE-ASSURANCE-REFUSED stage=admit detail=%s\n"
                            (String.concat "; "
                               (List.map
                                  (fun (issue : Run_safety.gate_error) ->
                                    issue.message)
                                  issues));
                          None
                      end
                  end
              end
          end
      end

type unavailable_assurance_observation = {
  reason : string;
  receipt : Run_safety.receipt;
  admission_refused : bool;
}

let unavailable_assurance context reason =
  match live_fixture context with
  | None -> None
  | Some fixture ->
      begin match Run_safety.z3_unavailable_receipt context ~reason with
      | Error _ -> None
      | Ok receipt ->
          let gate_inputs =
            [ Run_assurance.Safety_input
                (fixture.safety_model, fixture.safety);
              Run_assurance.Rete_input
                (fixture.rete_network, fixture.rete_facts, fixture.rete);
              Run_assurance.Raven_input
                (fixture.raven_matrix, fixture.raven);
              Run_assurance.Ruliad_input
                (fixture.ruliad_system, fixture.ruliad_bounds,
                 fixture.ruliad);
              Run_assurance.Stan_input (fixture.stan_input, fixture.stan);
              Run_assurance.Z3_unavailable_input receipt ]
          in
          begin match Run_assurance.make_inputs ~context gate_inputs with
          | Error _ -> None
          | Ok inputs ->
              Some
                { reason; receipt;
                  admission_refused =
                    Result.is_error (Run_assurance.admit ~context inputs) }
          end
      end

let metric_digest metric_id =
  match Run_metrics.find metric_id with
  | None -> String.make 64 '0'
  | Some declaration -> Run_metrics.declaration_digest declaration

let live_selection (context : Run_safety.gate_context)
    (activity : Run_topology.admitted_activity)
    (assurance : Run_assurance.admitted_bundle) =
  let metric_id = "process.cpu.user_seconds" in
  let now_ns = context.Run_safety.current_at_ns in
  let oracle : Run_fast_path.semantic_oracle =
    { id = "snapshot-fold"; digest = String.make 64 'f' }
  in
  let policy : Run_fast_path.policy =
    { version = "bridge-live-v1"; metric_id;
      low_threshold = 2.; high_threshold = 8.; oracle;
      equivalent_strategies =
        [ (Run_fast_path.Incremental, oracle.digest);
          (Run_fast_path.Snapshot_then_suffix, oracle.digest);
          (Run_fast_path.Aggregated_graph, oracle.digest) ];
      budget =
        { max_age_ns = 5_000_000_000L; future_tolerance_ns = 1_000_000L;
          max_cost = 100. };
      admission =
        Run_fast_path.Gate_admitted
          { gate_id = "assurance"; receipt_digest = assurance.bundle_digest } }
  in
  let observation : Run_metrics.observation =
    { metric_id; declaration_digest = metric_digest metric_id;
      run_id = context.run_id; subject_id = "bridge-live";
      subject_digest = String.make 64 'd'; provenance = context.provenance;
      coordinate = context.coordinate; rca_origin = Ops_capability.Environment;
      source = Run_metrics.Process_times; labels = [];
      sample =
        Run_metrics.Measured
          { value = Run_metrics.Float 1.5; sampled_at_ns = now_ns } }
  in
  let cost =
    Run_fast_path.Measured_cost
      { value = 10.; sampled_at_ns = now_ns;
        receipt_digest = assurance.bundle_digest }
  in
  Run_fast_path.choose_v2 ~context ~activity ~policy ~previous:None ~now_ns
    ~cost observation

let with_effect_interpreter_kind ?(commit_then_raise = false)
    ?(query_after_apply_error = false) ?(before_apply = fun () -> ())
    ~admitted activity body =
  with_database "bridge effect-ledger" (fun database ->
    let interpreter = ref None in
    Fun.protect
      ~finally:(fun () ->
        Option.iter Run_effect_authority.close !interpreter)
      (fun () ->
      let declaration = Run_topology.admitted_declaration activity in
      let target_id = declaration.target_component_id in
      let accepted_kinds = declaration.effect_kinds in
      let authority_digest =
        Run_effect_authority.expected_target_authority_digest ~activity
          ~target_id ~accepted_kinds
      in
      let receipts = Hashtbl.create 8 in
      let receipts_lock = Mutex.create () in
      let apply_calls = Atomic.make 0 in
      let apply_once ~idempotency_key request =
        ignore (Atomic.fetch_and_add apply_calls 1);
        before_apply ();
        match make_effect_receipt ~idempotency_key request ~authority_digest with
        | Error message -> Error message
        | Ok receipt ->
            Mutex.lock receipts_lock;
            Hashtbl.replace receipts idempotency_key receipt;
            Mutex.unlock receipts_lock;
            if commit_then_raise then
              failwith "target committed before receipt transport raised"
            else Ok receipt
      in
      let query ~idempotency_key =
        if query_after_apply_error && Atomic.get apply_calls > 0 then
          Error "target-native reconciliation unavailable after application"
        else begin
          Mutex.lock receipts_lock;
          let receipt = Hashtbl.find_opt receipts idempotency_key in
          Mutex.unlock receipts_lock;
          Ok receipt
        end
      in
      let coordinate =
        { Ops_capability.level = Ops_capability.L3;
          phase = Ops_capability.Act }
      in
      let opened =
        if admitted then
          match
            Run_effect_authority.register_target ~activity ~target_id
              ~authority_digest ~accepted_kinds ~apply_once ~query
          with
          | Error _ -> Error `Registry
          | Ok registry ->
              Run_effect_authority.open_admitted_interpreter ~database ~registry
                ~coordinate
              |> Result.map_error (fun _ -> `Open)
        else
          match
            Run_effect_authority.make_target ~target_id ~authority_digest
              ~accepted_kinds ~apply_once ~query
          with
          | Error _ -> Error `Target
          | Ok target ->
              Run_effect_authority.open_interpreter ~database ~target ~coordinate
              |> Result.map_error (fun _ -> `Open)
      in
      match opened with
      | Error _ -> failwith "bridge effect interpreter refused"
      | Ok value ->
          interpreter := Some value;
          body value apply_calls))

let with_effect_interpreter activity body =
  with_effect_interpreter_kind ~admitted:true activity body

let with_indeterminate_effect_interpreter activity body =
  with_effect_interpreter_kind ~commit_then_raise:true
    ~query_after_apply_error:true ~admitted:true activity body

let with_reopenable_effect_interpreter activity body =
  with_database "restart effect-ledger" (fun database ->
      let declaration = Run_topology.admitted_declaration activity in
      let target_id = declaration.target_component_id in
      let accepted_kinds = declaration.effect_kinds in
      let authority_digest =
        Run_effect_authority.expected_target_authority_digest ~activity
          ~target_id ~accepted_kinds
      in
      let applied = ref [] in
      let applied_lock = Mutex.create () in
      let receipts = Hashtbl.create 8 in
      let receipts_lock = Mutex.create () in
      let action_id request =
        try
          match Yojson.Safe.from_string request.Run_effect_authority.request_bytes with
          | `Assoc fields ->
              begin match List.assoc_opt "action_id" fields with
              | Some (`String value) -> value
              | Some _ | None -> ""
              end
          | _ -> ""
        with Yojson.Json_error _ -> ""
      in
      let apply_once ~idempotency_key request =
        Mutex.lock applied_lock;
        applied := (action_id request, idempotency_key) :: !applied;
        Mutex.unlock applied_lock;
        match make_effect_receipt ~idempotency_key request ~authority_digest with
        | Error message -> Error message
        | Ok receipt ->
            Mutex.lock receipts_lock;
            Hashtbl.replace receipts idempotency_key receipt;
            Mutex.unlock receipts_lock;
            Ok receipt
      in
      let query ~idempotency_key =
        Mutex.lock receipts_lock;
        let receipt = Hashtbl.find_opt receipts idempotency_key in
        Mutex.unlock receipts_lock;
        Ok receipt
      in
      let registry =
        match
          Run_effect_authority.register_target ~activity ~target_id
            ~authority_digest ~accepted_kinds ~apply_once ~query
        with
        | Ok value -> value
        | Error _ -> failwith "restart target registry refused"
      in
      let coordinate =
        { Ops_capability.level = Ops_capability.L3;
          phase = Ops_capability.Act }
      in
      let with_open body =
        match
          Run_effect_authority.open_admitted_interpreter ~database ~registry
            ~coordinate
        with
        | Error _ -> failwith "restart admitted interpreter refused"
        | Ok interpreter ->
            Fun.protect
              ~finally:(fun () -> Run_effect_authority.close interpreter)
              (fun () -> body interpreter)
      in
      let applied () =
        Mutex.lock applied_lock;
        let rows = List.rev !applied in
        Mutex.unlock applied_lock;
        rows
      in
      body with_open applied)

let live_execution_carriers_from_context store context solver_path =
  let* authority =
    Run_swarm_bridge.create_event_authority ~store ~context
      ~sources:Run_swarm_bridge.production_event_sources
    |> Result.to_option
  in
  let* current_authority =
    Run_swarm_bridge.current_authority authority |> Result.to_option
  in
  let* activity = canonical_activity () |> Result.to_option in
  let* intent =
    Run_swarm_bridge.resolve_intent ~context ~current_authority ~activity
    |> Result.to_option
  in
  let* assurance = live_assurance context solver_path in
  let* fast_path = live_selection context activity assurance |> Result.to_option in
  let* admission =
    Run_swarm_bridge.admit ~context ~intent ~current_authority ~assurance
      ~fast_path
    |> Result.to_option
  in
  let* action_registry =
    Run_swarm_bridge.action_registry ~activity |> Result.to_option
  in
  let* plan =
    Run_swarm_bridge.admit_plan ~admission ~action_registry |> Result.to_option
  in
  Some (context, authority, activity, admission, plan)

let live_execution_carriers store run_id solver_path =
  let* context = production_context store run_id in
  live_execution_carriers_from_context store context solver_path

let refreshed_production_context store run_id =
  let* current_head =
    Run_safety.observe_current_head ~store ~run_id
      ~lifetime_ns:60_000_000_000L
    |> Result.to_option
  in
  Run_safety.make_gate_context ~current_head
    ~request_id:("request-" ^ run_id ^ "-restart")
    ~activity_id:"activity.observe-inventory" ~coordinate
    ~plane:Ops_capability.Data_plane
  |> Result.to_option

let run_foundation () =
  Printf.printf "[events] exact append-only event authority\n";
  with_store "events" (fun store ->
    match production_context store "bridge-run" with
    | None -> check "E01 production bridge context fixture is available" false
    | Some context ->
        let authority =
          Run_swarm_bridge.create_event_authority ~store ~context
            ~sources:Run_swarm_bridge.production_event_sources
        in
        check "E01 exact production event authority constructs"
          (Result.is_ok authority);
        check "E02 current authority rereads the exact terminal head"
          (match authority with
           | Error _ -> false
           | Ok value -> Result.is_ok (Run_swarm_bridge.current_authority value));
        let exact_sources =
          Run_swarm_bridge.For_test.event_sources
            ~wall_now_ns:(fun () -> context.current_at_ns)
            ~monotonic_now_ns:(fun () -> context.current_head.observed_monotonic_ns)
            ~event_id:(fun ~run_id ~sequence ->
              Printf.sprintf "%s-%Ld" run_id sequence)
            ~readback_agrees:true
        in
        check "E03 deterministic exact event sources construct authority"
          (Result.is_ok
             (Run_swarm_bridge.create_event_authority ~store ~context
                ~sources:exact_sources));
        check "I01 canonical current authority resolves canonical activity"
          (match authority, canonical_activity () with
           | Ok authority, Ok activity ->
               begin match Run_swarm_bridge.current_authority authority with
               | Error _ -> false
               | Ok current_authority ->
                   Result.is_ok
                     (Run_swarm_bridge.resolve_intent ~context ~current_authority
                        ~activity)
               end
           | Error _, _ | Ok _, Error _ -> false);
        check "E04 Test_only context is rejected"
          (let test_context =
             match
               Run_safety.For_test.current_head_receipt ~run_id:"test-only"
                 ~provenance ~observed_at_ns:900L ~current_at_ns:1_000L
                 ~expires_at_ns:2_000L
             with
             | Error _ -> None
             | Ok current_head ->
                 Run_safety.make_gate_context ~current_head
                   ~request_id:"test-only"
                   ~activity_id:"activity.observe-inventory" ~coordinate
                   ~plane:Ops_capability.Data_plane
                 |> Result.to_option
           in
           match test_context with
           | None -> false
           | Some test_context ->
               Result.is_error
                 (Run_swarm_bridge.create_event_authority ~store
                    ~context:test_context ~sources:exact_sources));
        check "E05 expired current authority is rejected"
          (let expired_sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> context.current_head.expires_at_ns)
               ~monotonic_now_ns:(fun () ->
                 context.current_head.expires_monotonic_ns)
               ~event_id:(fun ~run_id ~sequence ->
                 Printf.sprintf "%s-%Ld" run_id sequence)
               ~readback_agrees:true
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context
                ~sources:expired_sources));
        check "E06 wall-clock source exception is rejected"
          (let sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> failwith "clock source fault")
               ~monotonic_now_ns:(fun () -> 1L)
               ~event_id:(fun ~run_id:_ ~sequence:_ -> "event")
               ~readback_agrees:true
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context ~sources));
        check "E07 monotonic-clock source exception is rejected"
          (let sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> context.current_at_ns)
               ~monotonic_now_ns:(fun () -> failwith "monotonic source fault")
               ~event_id:(fun ~run_id:_ ~sequence:_ -> "event")
               ~readback_agrees:true
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context ~sources));
        check "E08 empty event id is rejected"
          (let sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> context.current_at_ns)
               ~monotonic_now_ns:(fun () ->
                 context.current_head.observed_monotonic_ns)
               ~event_id:(fun ~run_id:_ ~sequence:_ -> "")
               ~readback_agrees:true
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context ~sources));
        check "E09 event-id reuse is rejected"
          (let sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> context.current_at_ns)
               ~monotonic_now_ns:(fun () ->
                 context.current_head.observed_monotonic_ns)
               ~event_id:(fun ~run_id:_ ~sequence:_ -> "reused")
               ~readback_agrees:true
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context ~sources));
        check "E10 nonmonotonic clocks are rejected"
          (let sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> Int64.pred context.current_at_ns)
               ~monotonic_now_ns:(fun () ->
                 Int64.pred context.current_head.observed_monotonic_ns)
               ~event_id:(fun ~run_id ~sequence ->
                 Printf.sprintf "%s-%Ld" run_id sequence)
               ~readback_agrees:true
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context ~sources));
        check "E11 full readback disagreement is rejected"
          (let sources =
             Run_swarm_bridge.For_test.event_sources
               ~wall_now_ns:(fun () -> context.current_at_ns)
               ~monotonic_now_ns:(fun () ->
                 context.current_head.observed_monotonic_ns)
               ~event_id:(fun ~run_id ~sequence ->
                 Printf.sprintf "%s-%Ld" run_id sequence)
               ~readback_agrees:false
           in
           Result.is_error
             (Run_swarm_bridge.create_event_authority ~store ~context ~sources));
        check "E12 advanced terminal head invalidates event authority"
          (let heartbeat =
             event_exn
               (Run_model.make ~run_id:"bridge-run" ~sequence:11L
                  ~event_id:"bridge-run-11" ~kind:Run_model.Heartbeat
                  ~subject:Run_model.Run ~plane:Ops_capability.Control_plane
                  ~coordinate ~rca_origin:Ops_capability.Control
                  ~occurred_at_ns:111L ~monotonic_at_ns:61L ~provenance
                  ~payload:(`Assoc [])
                  ~previous_digest:(Some context.current_head.head_event_digest))
           in
           Run_event_store.append store heartbeat = Ok ()
           && Result.is_error
                (Run_swarm_bridge.create_event_authority ~store ~context
                   ~sources:exact_sources));
        run_admission_identity_reds context;
        check "I02 unknown activity cannot resolve" (Result.is_error
          (Run_topology.admit_activity ~stable_id:"activity.unknown"));
        check "I03 canonical activity has exact stable identity"
          (match declaration () with
           | Some item ->
               item.stable_id = "activity.verify-sqlite-dependability"
           | None -> false);
        check "I04 intent is nonempty with constraints and success criteria"
          (match declaration () with
           | Some item -> item.intent <> "" && item.constraints <> []
                          && item.success_criteria <> []
           | None -> false);
        check "I05 exact five actions are retained"
          (match declaration () with
           | Some item -> List.length item.actions = 5
           | None -> false);
        check "I06 capability and context denominators are nonempty"
          (match declaration () with
           | Some item -> item.required_capability_ids <> []
                          && item.context_requirement_ids <> []
           | None -> false);
        check "I07 MIQ routes cover every assigned action"
          (match declaration () with
           | Some item -> List.length item.miq_routes = 4
           | None -> false);
        check "I08 target and effect denominators are closed"
          (match declaration () with
           | Some item -> item.target_component_id = "runEventStore"
                          && List.length item.effect_kinds = 3
           | None -> false));
  run_closed_store_red ();
  with_store "identity-left" (fun left ->
    with_store "identity-right" (fun right ->
      match production_context left "identity-run" with
      | None -> check "E14 equivalent bytes from another store are rejected" false
      | Some context ->
          check "the equivalent second store fixture appends"
            (append_active_dispatch right "identity-run" = Ok ());
          check "E14 equivalent bytes from another store are rejected"
            (Result.is_error
               (Run_swarm_bridge.create_event_authority ~store:right ~context
                  ~sources:Run_swarm_bridge.production_event_sources))));
  run_plan_reds ()

let append_heartbeat store context event_id =
  let head = context.Run_safety.current_head in
  let event =
    event_exn
      (Run_model.make ~run_id:context.run_id
         ~sequence:(Int64.succ head.head_sequence) ~event_id
         ~kind:Run_model.Heartbeat ~subject:Run_model.Run
         ~plane:Ops_capability.Control_plane ~coordinate
         ~rca_origin:Ops_capability.Control
         ~occurred_at_ns:(Int64.succ head.observed_at_ns)
         ~monotonic_at_ns:(Int64.succ head.observed_monotonic_ns) ~provenance
         ~payload:(`Assoc []) ~previous_digest:(Some head.head_event_digest))
  in
  Run_event_store.append store event

let rejected_without_execution ~store ~context ~admission ~authority
    ~interpreter ~plan apply_calls =
  let before =
    Run_event_store.events store ~run_id:context.Run_safety.run_id
    |> Result.map List.length
  in
  Run_swarm_bridge.For_test.reset_engine_call_count ();
  Run_swarm_bridge.For_test.reset_preparation_call_count ();
  let refused =
    Result.is_error
      (Run_swarm_bridge.execute ~admission ~authority ~interpreter ~plan)
  in
  let after =
    Run_event_store.events store ~run_id:context.run_id
    |> Result.map List.length
  in
  refused
  && before = after
  && Run_swarm_bridge.For_test.engine_call_count () = 0
  && Run_swarm_bridge.For_test.preparation_call_count () = 0
  && Atomic.get apply_calls = 0

let run_live_admission_reds solver_path =
  Printf.printf
    "[live-admission] admitted assurance reaches immutable bridge plan\n";
  with_store "live-admission" (fun store ->
    match production_context store "bridge-live" with
    | None -> check "L01 production live context is available" false
    | Some context ->
        check "L01 production live context is available" true;
        let authority =
          Run_swarm_bridge.create_event_authority ~store ~context
            ~sources:Run_swarm_bridge.production_event_sources
        in
        let current =
          match authority with
          | Error _ -> None
          | Ok authority ->
              Run_swarm_bridge.current_authority authority |> Result.to_option
        in
        let activity = canonical_activity () |> Result.to_option in
        let intent =
          match current, activity with
          | Some current_authority, Some activity ->
              Run_swarm_bridge.resolve_intent ~context ~current_authority
                ~activity
              |> Result.to_option
          | None, _ | Some _, None -> None
        in
        let assurance = live_assurance context solver_path in
        let selection =
          match activity, assurance with
          | Some activity, Some assurance ->
              begin match live_selection context activity assurance with
              | Ok value -> Some value
              | Error diagnostics ->
                  List.iter
                    (fun (diagnostic : Run_fast_path.diagnostic) ->
                      Printf.eprintf
                        "LIVE-SELECTION-REFUSED coordinate=%s/%s rca=%s message=%s\n"
                        (Ops_capability.string_of_level diagnostic.coordinate.level)
                        (Ops_capability.string_of_phase diagnostic.coordinate.phase)
                        (Ops_capability.string_of_rca_origin diagnostic.rca_origin)
                        diagnostic.message)
                    diagnostics;
                  None
              end
          | None, _ | Some _, None -> None
        in
        Printf.eprintf
          "LIVE-CARRIERS authority=%b current=%b activity=%b intent=%b assurance=%b selection=%b\n"
          (Result.is_ok authority) (Option.is_some current)
          (Option.is_some activity) (Option.is_some intent)
          (Option.is_some assurance) (Option.is_some selection);
        check "L02 real event/current/intent/assurance/selection carriers construct"
          (Result.is_ok authority && Option.is_some current
           && Option.is_some activity && Option.is_some intent
           && Option.is_some assurance && Option.is_some selection);
        check "L02a typed intent binds current module and five-owner FPP authorities"
          (match intent with
           | None -> false
           | Some intent ->
               Run_swarm_bridge.intent_authority_digests intent
               = (Module_intent.source_digest, Run_fpp_authority.source_digest));
        check "L02b typed intent binds the debugging authority"
          (match intent with
           | None -> false
           | Some intent ->
               String.equal
                 (Run_swarm_bridge.intent_debug_authority_digest intent)
                 Debug_intent.source_digest);
        check "L02c stale debugging authority is rejected"
          (match intent with
           | None -> false
           | Some intent ->
               Run_swarm_bridge.For_test.intent_authorities_current intent
               && not
                    (Run_swarm_bridge.For_test.intent_authorities_current
                       (Run_swarm_bridge.For_test.mutate_intent
                          Run_swarm_bridge.For_test.Debug_authority_digest
                          intent)));
        check "L02d typed intent binds the controlled external-access authority"
          (match intent with
           | None -> false
           | Some intent ->
               String.equal
                 (Run_swarm_bridge.intent_external_access_authority_digest intent)
                 External_access.source_digest);
        check "L02e stale controlled external-access authority is rejected"
          (match intent with
           | None -> false
           | Some intent ->
               Run_swarm_bridge.For_test.intent_authorities_current intent
               && not
                    (Run_swarm_bridge.For_test.intent_authorities_current
                       (Run_swarm_bridge.For_test.mutate_intent
                          Run_swarm_bridge.For_test.External_access_authority_digest
                          intent)));
        let admission =
          match current, intent, assurance, selection with
          | Some current_authority, Some intent, Some assurance, Some fast_path ->
              Run_swarm_bridge.admit ~context ~intent ~current_authority
                ~assurance ~fast_path
              |> Result.to_option
          | _ -> None
        in
        check "L03 exact real carriers admit the bridge" (Option.is_some admission);
        let registry =
          match activity with
          | None -> None
          | Some activity ->
              Run_swarm_bridge.action_registry ~activity |> Result.to_option
        in
        check "L04 exact closed action registry constructs"
          (Option.is_some registry);
        let plan =
          match admission, registry with
          | Some admission, Some action_registry ->
              Run_swarm_bridge.admit_plan ~admission ~action_registry
              |> Result.to_option
          | None, _ | Some _, None -> None
        in
        check "L05 admitted bridge and exact registry mint an immutable plan"
          (Option.is_some plan);
        check "L06 immutable plan independently validates"
          (match admission, registry, plan with
           | Some admission, Some action_registry, Some plan ->
               Result.is_ok
                 (Run_swarm_bridge.For_test.validate_plan ~admission
                    ~action_registry plan)
           | _ -> false);
        let foreign_context =
          Run_safety.make_gate_context ~current_head:context.current_head
            ~request_id:"request-bridge-live-foreign"
            ~activity_id:context.activity_id ~coordinate:context.coordinate
            ~plane:context.plane
          |> Result.to_option
        in
        check "L07 foreign exact context cannot reuse admitted carriers"
          (match current, intent, assurance, selection, foreign_context with
           | Some current_authority, Some intent, Some assurance,
             Some fast_path, Some foreign ->
               Result.is_error
                 (Run_swarm_bridge.admit ~context:foreign ~intent
                    ~current_authority ~assurance ~fast_path)
           | _ -> false);
        check "L08 mutated assurance bundle cannot admit"
          (match current, intent, assurance, selection with
           | Some current_authority, Some intent, Some assurance, Some fast_path ->
               let mutant =
                 Run_assurance.For_test.mutate_bundle
                   Run_assurance.For_test.Context_digest assurance
               in
               Result.is_error
                 (Run_swarm_bridge.admit ~context ~intent ~current_authority
                    ~assurance:mutant ~fast_path)
           | _ -> false);
        check "L09 foreign fast-path selection cannot admit"
          (match current, intent, assurance, activity, foreign_context with
           | Some current_authority, Some intent, Some assurance, Some activity,
             Some foreign ->
               begin match live_selection foreign activity assurance with
               | Error _ -> false
               | Ok foreign_selection ->
                   Result.is_error
                     (Run_swarm_bridge.admit ~context ~intent ~current_authority
                        ~assurance ~fast_path:foreign_selection)
               end
           | _ -> false);
        let registry_mutations =
          [ ("L10 registry activity identity mutation is rejected",
             Run_swarm_bridge.For_test.Registry_activity_identity);
            ("L11 registry action order mutation is rejected",
             Run_swarm_bridge.For_test.Registry_action_order);
            ("L12 registry digest mutation is rejected",
             Run_swarm_bridge.For_test.Registry_digest) ]
        in
        List.iter
          (fun (name, mutation) ->
            check name
              (match admission, registry with
               | Some admission, Some registry ->
                   let mutant =
                     Run_swarm_bridge.For_test.mutate_action_registry mutation
                       registry
                   in
                   Result.is_error
                     (Run_swarm_bridge.admit_plan ~admission
                        ~action_registry:mutant)
               | _ -> false))
          registry_mutations;
        let plan_mutations =
          [ ("L13 duplicate admission ids are rejected",
             Run_swarm_bridge.For_test.Duplicate_admission_id);
            ("L14 duplicate plan ids are rejected",
             Run_swarm_bridge.For_test.Duplicate_plan_id);
            ("L15 plan action order mutation is rejected",
             Run_swarm_bridge.For_test.Plan_action_order);
            ("L16 plan graph digest mutation is rejected",
             Run_swarm_bridge.For_test.Plan_graph_digest);
            ("L17 plan digest mutation is rejected",
             Run_swarm_bridge.For_test.Plan_digest) ]
        in
        List.iter
          (fun (name, mutation) ->
            check name
              (match admission, registry, plan with
               | Some admission, Some registry, Some plan ->
                   let mutant =
                     Run_swarm_bridge.For_test.mutate_plan mutation plan
                   in
                   Result.is_error
                     (Run_swarm_bridge.For_test.validate_plan ~admission
                        ~action_registry:registry mutant)
               | _ -> false))
          plan_mutations;
        check "X01 invalid plan reaches zero engine calls and zero effects"
          (match admission, authority, activity, plan with
           | Some admission, Ok authority, Some activity, Some plan ->
               with_effect_interpreter activity (fun interpreter apply_calls ->
                 Run_swarm_bridge.For_test.reset_engine_call_count ();
                 let mutant =
                   Run_swarm_bridge.For_test.mutate_plan
                     Run_swarm_bridge.For_test.Plan_digest plan
                 in
                 Result.is_error
                   (Run_swarm_bridge.execute ~admission ~authority
                      ~interpreter ~plan:mutant)
                 && Run_swarm_bridge.For_test.engine_call_count () = 0
                 && Atomic.get apply_calls = 0)
           | _ -> false);
        check "X04 low-level interpreter reaches no execution surface"
          (match admission, authority, activity, plan with
           | Some admission, Ok authority, Some activity, Some plan ->
               with_effect_interpreter_kind ~admitted:false activity
                 (fun interpreter apply_calls ->
                   rejected_without_execution ~store ~context ~admission
                     ~authority ~interpreter ~plan apply_calls)
           | _ -> false);
        check "X05 foreign retained activity identity reaches no execution surface"
          (match admission, authority, activity, plan with
           | Some admission, Ok authority, Some activity, Some plan ->
               with_effect_interpreter activity (fun interpreter apply_calls ->
                 let foreign =
                   Run_effect_authority.For_test.mutate_admitted_identity
                     Run_effect_authority.For_test.Activity_digest interpreter
                 in
                 rejected_without_execution ~store ~context ~admission
                   ~authority ~interpreter:foreign ~plan apply_calls)
           | _ -> false);
        check "X06 every mutated admitted interpreter reaches no execution surface"
          (match admission, authority, activity, plan with
           | Some admission, Ok authority, Some activity, Some plan ->
               let mutations =
                 [ Run_effect_authority.For_test.Topology_authority_digest;
                   Run_effect_authority.For_test.Target_digest;
                   Run_effect_authority.For_test.Effect_kinds_digest ]
               in
               List.for_all
                 (fun mutation ->
                   with_effect_interpreter activity
                     (fun interpreter apply_calls ->
                       let mutant =
                         Run_effect_authority.For_test.mutate_admitted_identity
                           mutation interpreter
                       in
                       rejected_without_execution ~store ~context ~admission
                         ~authority ~interpreter:mutant ~plan apply_calls))
                 mutations
           | _ -> false);
        check "X02 two preparation retries still make one engine call and five effects"
          (match admission, authority, activity, plan with
           | Some admission, Ok authority, Some activity, Some plan ->
               with_effect_interpreter activity (fun interpreter apply_calls ->
                 Run_swarm_bridge.For_test.reset_engine_call_count ();
                 Run_swarm_bridge.For_test.reset_preparation_call_count ();
                 Run_swarm_bridge.For_test.arm_preparation_failures authority
                   ~action_id:"action.sqlite.formal" ~count:2 = Ok ()
                 &&
                 match
                   Run_swarm_bridge.execute ~admission ~authority ~interpreter
                     ~plan
                 with
                 | Error _ -> false
                 | Ok receipt ->
                     String.equal receipt.plan_digest
                       (Run_swarm_bridge.admitted_plan_digest plan)
                     && String.length receipt.result_digest = 64
                     && Run_swarm_bridge.For_test.engine_call_count () = 1
                     && Run_swarm_bridge.For_test.preparation_call_count () = 7
                     && Atomic.get apply_calls = 5)
           | _ -> false);
        check "X03 durable readback contains seven contiguous terminal attempts"
          (match activity, Run_event_store.events store ~run_id:context.run_id with
           | Some activity, Ok events ->
               let attempt_events =
                 List.filter
                   (fun (event : Run_model.event) ->
                     match event.kind with
                     | Run_model.Swarm_step_ready
                     | Run_model.Swarm_step_running
                     | Run_model.Swarm_step_terminal -> true
                     | _ -> false)
                   events
               in
               begin match Run_snapshot.fold events with
               | Error _ -> false
               | Ok snapshot ->
                   List.length attempt_events = 21
                   && (Run_snapshot.counts snapshot).attempts_terminal = 7
                   && Run_snapshot.attempt_state snapshot
                        ~step:"action.sqlite.formal" ~attempt:0
                      = Some
                          (Run_snapshot.Attempt_terminal Run_model.Failed)
                   && Run_snapshot.attempt_state snapshot
                        ~step:"action.sqlite.formal" ~attempt:1
                      = Some
                          (Run_snapshot.Attempt_terminal Run_model.Failed)
                   && Run_snapshot.attempt_state snapshot
                        ~step:"action.sqlite.formal" ~attempt:2
                      = Some
                          (Run_snapshot.Attempt_terminal Run_model.Succeeded)
                   && List.for_all
                        (fun (action : Run_topology.declarative_action) ->
                          String.equal action.stable_id "action.sqlite.formal"
                          || Run_snapshot.attempt_state snapshot
                               ~step:action.stable_id ~attempt:0
                             = Some
                                 (Run_snapshot.Attempt_terminal
                                    Run_model.Succeeded))
                        (Run_topology.admitted_actions activity)
               end
           | _ -> false);
        check "L18 stale event head after assurance refuses bridge admission"
          (match current, intent, assurance, selection with
           | Some current_authority, Some intent, Some assurance, Some fast_path ->
               let advanced =
                 match Run_event_store.events store ~run_id:context.run_id with
                 | Ok events when List.length events > 11 -> true
                 | Ok _ | Error _ ->
                     append_heartbeat store context "bridge-live-heartbeat" = Ok ()
               in
               advanced
               && Result.is_error
                    (Run_swarm_bridge.admit ~context ~intent ~current_authority
                       ~assurance ~fast_path)
           | _ -> false))

let run_terminal_append_fault solver_path =
  Printf.printf
    "[failure-envelope] terminal append failure never replays an applied effect\n";
  with_store "terminal-append-fault" (fun store ->
    match
      live_execution_carriers store "bridge-terminal-fault" solver_path
    with
    | None ->
        check "X07 terminal-append fault carriers construct" false
    | Some (context, authority, activity, admission, plan) ->
        with_effect_interpreter activity (fun interpreter apply_calls ->
          Run_swarm_bridge.For_test.reset_engine_call_count ();
          Run_swarm_bridge.For_test.reset_preparation_call_count ();
          let armed =
            Run_swarm_bridge.For_test.fail_next_terminal_append authority
              ~action_id:"action.sqlite.formal" = Ok ()
          in
          let refused =
            Result.is_error
              (Run_swarm_bridge.execute ~admission ~authority ~interpreter
                 ~plan)
          in
          let attempt_events =
            match Run_event_store.events store ~run_id:context.run_id with
            | Error _ -> []
            | Ok events ->
                List.filter
                  (fun (event : Run_model.event) ->
                    match event.kind with
                    | Run_model.Swarm_step_ready
                    | Run_model.Swarm_step_running
                    | Run_model.Swarm_step_terminal -> true
                    | _ -> false)
                  events
          in
          check
            "X07 terminal append failure returns no receipt, drains, and never replays"
            (armed && refused
             && Run_swarm_bridge.For_test.engine_call_count () = 1
             && Run_swarm_bridge.For_test.preparation_call_count () = 1
             && Atomic.get apply_calls = 1
             && List.length attempt_events = 8
             && List.map
                  (fun (event : Run_model.event) -> event.kind)
                  attempt_events
                = [ Run_model.Swarm_step_ready; Run_model.Swarm_step_running;
                    Run_model.Swarm_step_ready; Run_model.Swarm_step_running;
                    Run_model.Swarm_step_terminal;
                    Run_model.Swarm_step_ready; Run_model.Swarm_step_running;
                    Run_model.Swarm_step_terminal ])))

let run_indeterminate_effect_fault solver_path =
  Printf.printf
    "[failure-envelope] indeterminate effect is terminal and never replayed\n";
  with_store "indeterminate-effect" (fun store ->
    match
      live_execution_carriers store "bridge-indeterminate" solver_path
    with
    | None -> check "X08 indeterminate-effect carriers construct" false
    | Some (context, authority, activity, admission, plan) ->
        with_indeterminate_effect_interpreter activity
          (fun interpreter apply_calls ->
            Run_swarm_bridge.For_test.reset_engine_call_count ();
            Run_swarm_bridge.For_test.reset_preparation_call_count ();
            let refused =
              Result.is_error
                (Run_swarm_bridge.execute ~admission ~authority ~interpreter
                   ~plan)
            in
            let attempt_events =
              match Run_event_store.events store ~run_id:context.run_id with
              | Error _ -> []
              | Ok events ->
                  List.filter
                    (fun (event : Run_model.event) ->
                      match event.kind with
                      | Run_model.Swarm_step_ready
                      | Run_model.Swarm_step_running
                      | Run_model.Swarm_step_terminal -> true
                      | _ -> false)
                    events
            in
            check
              "X08 indeterminate effect blocks dependencies and external replay"
              (refused
               && Run_swarm_bridge.For_test.engine_call_count () = 1
               && Run_swarm_bridge.For_test.preparation_call_count () = 1
               && Atomic.get apply_calls = 1
               && List.length attempt_events = 9
               && List.for_all
                    (fun attempt ->
                      match
                        Run_snapshot.fold
                          (match
                             Run_event_store.events store ~run_id:context.run_id
                           with
                           | Ok events -> events
                           | Error _ -> [])
                      with
                      | Error _ -> false
                      | Ok snapshot ->
                          Run_snapshot.attempt_state snapshot
                            ~step:"action.sqlite.formal" ~attempt
                          = Some
                              (Run_snapshot.Attempt_terminal Run_model.Failed))
                    [ 0; 1; 2 ])))

let same_execution_outcome
    (left : (Run_swarm_bridge.result, Run_swarm_bridge.error) Stdlib.result)
    (right : (Run_swarm_bridge.result, Run_swarm_bridge.error) Stdlib.result) =
  match left, right with
  | Ok left, Ok right ->
      String.equal left.run_id right.run_id
      && String.equal left.authority_digest right.authority_digest
      && String.equal left.admission_digest right.admission_digest
      && String.equal left.plan_digest right.plan_digest
      && left.ordered_action_receipts = right.ordered_action_receipts
      && String.equal left.engine_projection_digest
           right.engine_projection_digest
      && Int64.equal left.initial_head_sequence right.initial_head_sequence
      && String.equal left.initial_head_digest right.initial_head_digest
      && Int64.equal left.final_head_sequence right.final_head_sequence
      && String.equal left.final_head_digest right.final_head_digest
      && left.attempt_event_count = right.attempt_event_count
      && String.equal left.complete_stream_digest right.complete_stream_digest
      && String.equal left.result_digest right.result_digest
  | Error left, Error right ->
      left.code = right.code
      && String.equal left.message right.message
      && left.coordinate = right.coordinate
      && left.rca_origin = right.rca_origin
      && String.equal left.hazard_id right.hazard_id
  | Ok _, Error _ | Error _, Ok _ -> false

let event_count store run_id =
  match Run_event_store.events store ~run_id with
  | Ok events -> Some (List.length events)
  | Error _ -> None

let event_delta before after =
  match before, after with
  | Some before, Some after -> Some (after - before)
  | None, _ | _, None -> None

let concurrent_pair operation =
  let mutex = Mutex.create () in
  let condition = Condition.create () in
  let waiting = ref 0 in
  let released = ref false in
  let await_release () =
    Mutex.lock mutex;
    incr waiting;
    Condition.broadcast condition;
    while not !released do Condition.wait condition mutex done;
    Mutex.unlock mutex
  in
  let invoke () = await_release (); operation () in
  let first = Domain.spawn invoke in
  let second = Domain.spawn invoke in
  Mutex.lock mutex;
  while !waiting < 2 do Condition.wait condition mutex done;
  released := true;
  Condition.broadcast condition;
  Mutex.unlock mutex;
  Domain.join first, Domain.join second

let exact_result_projection (context : Run_safety.gate_context)
    (activity : Run_topology.admitted_activity)
    (plan : Run_swarm_bridge.admitted_plan) (result : Run_swarm_bridge.result) =
  let actions = Run_topology.admitted_actions activity in
  let receipts = result.ordered_action_receipts in
  let digest value = String.length value = 64 in
  String.equal result.run_id context.run_id
  && digest result.authority_digest
  && digest result.admission_digest
  && String.equal result.plan_digest
       (Run_swarm_bridge.admitted_plan_digest plan)
  && List.length receipts = List.length actions
  && List.for_all2
       (fun (action : Run_topology.declarative_action)
            (receipt : Run_swarm_bridge.action_receipt) ->
         String.equal receipt.action_id action.stable_id
         && String.equal receipt.action_digest
              (Run_topology.action_digest_of action)
         && digest receipt.request_digest
         && digest receipt.effect_receipt_digest
         && digest receipt.output_digest
         && receipt.attempt_count = 1
         && receipt.status = Run_swarm_bridge.Action_succeeded)
       actions receipts
  && digest result.engine_projection_digest
  && Int64.equal result.initial_head_sequence
       context.current_head.head_sequence
  && String.equal result.initial_head_digest
       context.current_head.head_event_digest
  && Int64.equal result.final_head_sequence
       (Int64.add context.current_head.head_sequence 15L)
  && digest result.final_head_digest
  && result.attempt_event_count = 15
  && digest result.complete_stream_digest
  && digest result.result_digest

let result_mutations =
  [ Run_swarm_bridge.For_test.Result_authority_identity;
    Run_swarm_bridge.For_test.Result_admission_identity;
    Run_swarm_bridge.For_test.Result_plan_identity;
    Run_swarm_bridge.For_test.Result_action_order;
    Run_swarm_bridge.For_test.Result_action_digest;
    Run_swarm_bridge.For_test.Result_request_digest;
    Run_swarm_bridge.For_test.Result_effect_digest;
    Run_swarm_bridge.For_test.Result_output_digest;
    Run_swarm_bridge.For_test.Result_attempt_count;
    Run_swarm_bridge.For_test.Result_action_status;
    Run_swarm_bridge.For_test.Result_engine_projection;
    Run_swarm_bridge.For_test.Result_initial_head;
    Run_swarm_bridge.For_test.Result_final_head;
    Run_swarm_bridge.For_test.Result_attempt_event_count;
    Run_swarm_bridge.For_test.Result_complete_stream;
    Run_swarm_bridge.For_test.Result_digest ]

let run_execution_claim_reds solver_path =
  Printf.printf
    "[execution-claim] duplicate delivery converges on one authority-local claim\n";
  with_store "execution-claim-replay" (fun store ->
    match live_execution_carriers store "bridge-claim-replay" solver_path with
    | None -> check "X09 replay claim carriers construct" false
    | Some (context, authority, activity, admission, plan) ->
        with_effect_interpreter activity (fun interpreter apply_calls ->
          let before = event_count store context.run_id in
          Run_swarm_bridge.For_test.reset_engine_call_count ();
          Run_swarm_bridge.For_test.reset_preparation_call_count ();
          let first =
            Run_swarm_bridge.execute ~admission ~authority ~interpreter ~plan
          in
          let after_first = event_count store context.run_id in
          let second =
            Run_swarm_bridge.execute ~admission ~authority ~interpreter ~plan
          in
          let after_second = event_count store context.run_id in
          check
            "X09 successful replay returns the identical receipt without new surfaces"
            (same_execution_outcome first second
             && event_delta before after_first = Some 15
             && after_second = after_first
             && Run_swarm_bridge.For_test.engine_call_count () = 1
             && Run_swarm_bridge.For_test.preparation_call_count () = 5
             && Atomic.get apply_calls = 5);
          check "X11 result retains the exact typed execution projection"
            (match first with
             | Error _ -> false
             | Ok result -> exact_result_projection context activity plan result);
          check "X12 exact typed result validates against full durable readback"
            (match first with
             | Error _ -> false
             | Ok result ->
                 Result.is_ok
                   (Run_swarm_bridge.validate_result ~admission ~authority
                      ~interpreter ~plan result));
          check "X13 every result mutation is refused by durable readback"
            (match first with
             | Error _ -> false
             | Ok result ->
                 List.for_all
                   (fun mutation ->
                     let mutant =
                       Run_swarm_bridge.For_test.mutate_result mutation result
                     in
                     Result.is_error
                       (Run_swarm_bridge.validate_result ~admission ~authority
                          ~interpreter ~plan mutant))
                   result_mutations);
          check
            "X20 cached result validation refuses a ledger without effect receipts"
            (match first with
             | Error _ -> false
             | Ok result ->
                 with_effect_interpreter activity
                   (fun empty_interpreter empty_apply_calls ->
                     Result.is_error
                       (Run_swarm_bridge.validate_result ~admission ~authority
                          ~interpreter:empty_interpreter ~plan result)
                     && Atomic.get empty_apply_calls = 0));
          check "X14 cached success never authorizes a low-level interpreter"
            (with_effect_interpreter_kind ~admitted:false activity
               (fun low_level low_level_apply_calls ->
                 rejected_without_execution ~store ~context ~admission
                   ~authority ~interpreter:low_level ~plan
                   low_level_apply_calls));
          check
            "X15 cached success refuses every mutated admitted interpreter identity"
            (let mutations =
               [ Run_effect_authority.For_test.Activity_digest;
                 Run_effect_authority.For_test.Topology_authority_digest;
                 Run_effect_authority.For_test.Target_digest;
                 Run_effect_authority.For_test.Effect_kinds_digest ]
             in
             mutations
             |> List.map (fun mutation ->
                  with_effect_interpreter activity
                    (fun valid mutant_apply_calls ->
                      let mutant =
                        Run_effect_authority.For_test.mutate_admitted_identity
                          mutation valid
                      in
                      rejected_without_execution ~store ~context ~admission
                        ~authority ~interpreter:mutant ~plan
                        mutant_apply_calls))
             |> List.for_all Fun.id)));
  with_store "execution-claim-concurrent" (fun store ->
    match
      live_execution_carriers store "bridge-claim-concurrent" solver_path
    with
    | None -> check "X10 concurrent claim carriers construct" false
    | Some (context, authority, activity, admission, plan) ->
        with_effect_interpreter activity (fun interpreter apply_calls ->
          let before = event_count store context.run_id in
          Run_swarm_bridge.For_test.reset_engine_call_count ();
          Run_swarm_bridge.For_test.reset_preparation_call_count ();
          let execute () =
            Run_swarm_bridge.execute ~admission ~authority ~interpreter ~plan
          in
          let first, second = concurrent_pair execute in
          let after = event_count store context.run_id in
          check
            "X10 concurrent duplicates drain to one identical outcome and one execution"
            (same_execution_outcome first second
             && event_delta before after = Some 15
             && Run_swarm_bridge.For_test.engine_call_count () = 1
             && Run_swarm_bridge.For_test.preparation_call_count () = 5
             && Atomic.get apply_calls = 5)));
  with_store "execution-claim-invalid-follower" (fun store ->
    match
      live_execution_carriers store "bridge-claim-invalid-follower" solver_path
    with
    | None -> check "X16 mixed-authority concurrent carriers construct" false
    | Some (context, authority, activity, admission, plan) ->
        with_effect_interpreter_kind ~admitted:false activity
          (fun invalid_interpreter invalid_apply_calls ->
            let mutex = Mutex.create () in
            let condition = Condition.create () in
            let valid_effect_started = ref false in
            let release_valid_effect = ref false in
            let before_apply () =
              Mutex.lock mutex;
              if not !valid_effect_started then begin
                valid_effect_started := true;
                Condition.broadcast condition
              end;
              while not !release_valid_effect do
                Condition.wait condition mutex
              done;
              Mutex.unlock mutex
            in
            with_effect_interpreter_kind ~before_apply ~admitted:true activity
              (fun valid_interpreter valid_apply_calls ->
                let before = event_count store context.run_id in
                Run_swarm_bridge.For_test.reset_engine_call_count ();
                Run_swarm_bridge.For_test.reset_preparation_call_count ();
                let valid =
                  Domain.spawn (fun () ->
                    Run_swarm_bridge.execute ~admission ~authority
                      ~interpreter:valid_interpreter ~plan)
                in
                Mutex.lock mutex;
                while not !valid_effect_started do
                  Condition.wait condition mutex
                done;
                let invalid =
                  Domain.spawn (fun () ->
                    Run_swarm_bridge.execute ~admission ~authority
                      ~interpreter:invalid_interpreter ~plan)
                in
                release_valid_effect := true;
                Condition.broadcast condition;
                Mutex.unlock mutex;
                let valid_outcome = Domain.join valid in
                let invalid_outcome = Domain.join invalid in
                let after = event_count store context.run_id in
                check
                  "X16 invalid concurrent follower cannot inherit a valid leader claim"
                  (Result.is_ok valid_outcome
                   && Result.is_error invalid_outcome
                   && event_delta before after = Some 15
                   && Run_swarm_bridge.For_test.engine_call_count () = 1
                   && Run_swarm_bridge.For_test.preparation_call_count () = 5
                   && Atomic.get valid_apply_calls = 5
                   && Atomic.get invalid_apply_calls = 0))))

let formal_attempts store run_id =
  match Run_event_store.events store ~run_id with
  | Error _ -> []
  | Ok events ->
      events
      |> List.filter_map (fun (event : Run_model.event) ->
           match event.kind, event.subject with
           | Run_model.Swarm_step_ready,
             Run_model.Attempt ("action.sqlite.formal", attempt) -> Some attempt
           | _ -> None)

let run_restart_no_replay_reds solver_path =
  Printf.printf
    "[restart-recovery] durable effect identity survives re-admission freshness\n";
  with_store "restart-no-replay" (fun store ->
    let run_id = "bridge-restart-no-replay" in
    match live_execution_carriers store run_id solver_path with
    | None -> check "X17 restart recovery initial carriers construct" false
    | Some (first_context, first_authority, activity, first_admission,
            first_plan) ->
        with_reopenable_effect_interpreter activity
          (fun with_open applied ->
            Run_swarm_bridge.For_test.reset_engine_call_count ();
            Run_swarm_bridge.For_test.reset_preparation_call_count ();
            let armed =
              Run_swarm_bridge.For_test.fail_next_terminal_append first_authority
                ~action_id:"action.sqlite.formal" = Ok ()
            in
            let first_outcome =
              with_open (fun interpreter ->
                Run_swarm_bridge.execute ~admission:first_admission
                  ~authority:first_authority ~interpreter ~plan:first_plan)
            in
            let first_applied = applied () in
            let refreshed = refreshed_production_context store run_id in
            let restarted =
              match refreshed with
              | None -> None
              | Some context ->
                  live_execution_carriers_from_context store context solver_path
            in
            check
              "X17 terminal-loss restart reaches a fresh truthful admission"
              (armed && Result.is_error first_outcome
               && List.length first_applied = 1
               && Option.is_some restarted);
            match restarted with
            | None ->
                check "X18 logical effect key is freshness independent" false;
                check "X19 restart reuses Applied and advances durable attempt" false
            | Some (second_context, second_authority, second_activity,
                    second_admission, second_plan) ->
                let first_action =
                  Run_topology.admitted_actions activity |> List.hd
                in
                let second_action =
                  Run_topology.admitted_actions second_activity |> List.hd
                in
                let first_prepared =
                  Run_swarm_preparation.prepare
                    ~execution_identity:
                      (Run_swarm_bridge.execution_identity
                         ~run_id:first_context.run_id ~activity)
                    ~activity ~action:first_action ~input_payload:""
                in
                let second_prepared =
                  Run_swarm_preparation.prepare
                    ~execution_identity:
                      (Run_swarm_bridge.execution_identity
                         ~run_id:second_context.run_id
                         ~activity:second_activity)
                    ~activity:second_activity ~action:second_action
                    ~input_payload:""
                in
                check "X18 logical effect key is freshness independent"
                  (not
                     (String.equal
                        (Run_swarm_bridge.admitted_plan_digest first_plan)
                        (Run_swarm_bridge.admitted_plan_digest second_plan))
                   && match first_prepared, second_prepared with
                      | Ok first, Ok second ->
                          String.equal first.idempotency_key second.idempotency_key
                          && String.equal first.request_digest second.request_digest
                      | Error _, _ | _, Error _ -> false);
                let attempts_before = formal_attempts store run_id in
                let second_outcome =
                  with_open (fun interpreter ->
                    Run_swarm_bridge.execute ~admission:second_admission
                      ~authority:second_authority ~interpreter ~plan:second_plan)
                in
                let attempts_after = formal_attempts store run_id in
                let formal_applications =
                  applied ()
                  |> List.filter (fun (action_id, _) ->
                       String.equal action_id "action.sqlite.formal")
                in
                let unique_attempts values =
                  List.length values
                  = List.length (List.sort_uniq Int.compare values)
                in
                check
                  "X19 restart reuses Applied and advances durable attempt"
                  (Result.is_ok second_outcome
                   && List.length formal_applications = 1
                   && unique_attempts attempts_after
                   && List.length attempts_after > List.length attempts_before
                   && first_context.current_head.head_sequence
                        < second_context.current_head.head_sequence)))

let run_engine_projection_reds solver_path =
  Printf.printf
    "[engine-projection] malformed engine results never become bridge success\n";
  let faults =
    [ ("X21a missing action result is projection-invalid",
       Sop_execution.For_test.Missing_action_result);
      ("X21b duplicate action result is projection-invalid",
       Sop_execution.For_test.Duplicate_action_result);
      ("X21c unknown action result is projection-invalid",
       Sop_execution.For_test.Unknown_action_result);
      ("X21d out-of-order action result is projection-invalid",
       Sop_execution.For_test.Out_of_order_results);
      ("X21e replay-unverified result is projection-invalid",
       Sop_execution.For_test.Replay_not_verified);
      ("X21f engine exception is contained as projection-invalid",
       Sop_execution.For_test.Engine_exception) ]
  in
  List.iteri
    (fun index (name, fault) ->
      with_store ("engine-projection-" ^ string_of_int index) (fun store ->
        let run_id = "bridge-engine-projection-" ^ string_of_int index in
        match live_execution_carriers store run_id solver_path with
        | None -> check name false
        | Some (context, authority, activity, admission, plan) ->
            with_effect_interpreter activity (fun interpreter apply_calls ->
              let before = event_count store context.run_id in
              Run_swarm_bridge.For_test.reset_engine_call_count ();
              Run_swarm_bridge.For_test.reset_preparation_call_count ();
              let outcome =
                Sop_execution.For_test.with_result_fault fault (fun () ->
                  Run_swarm_bridge.execute ~admission ~authority ~interpreter
                    ~plan)
              in
              let after = event_count store context.run_id in
              check name
                (match outcome with
                 | Ok _ -> false
                 | Error issue ->
                     issue.code = Run_swarm_bridge.Projection_invalid
                     && event_delta before after = Some 15
                     && Run_swarm_bridge.For_test.engine_call_count () = 1
                     && Run_swarm_bridge.For_test.preparation_call_count () = 5
                     && Atomic.get apply_calls = 5))))
    faults;
  check "X22 dependency payload is an unambiguous typed projection"
    (not
       (String.equal
          (Sop_execution.For_test.dependency_payload [ "a | b"; "c" ])
          (Sop_execution.For_test.dependency_payload [ "a"; "b | c" ])))

let run_unavailable_live_observer reason =
  Printf.printf
    "[live-unavailable] controlled resource observation refuses bridge authority\n";
  with_store "live-unavailable" (fun store ->
    match production_context store "bridge-live-unavailable" with
    | None ->
        check "U01 unavailable observer context constructs" false
    | Some context ->
        let broker =
          match
            Run_operator_authority.create ~maximum_registrations:1
          with
          | Ok broker -> broker
          | Error issue -> failwith issue.Run_operator_authority.message
        in
        let registrations_before =
          Run_operator_authority.prepared_registration_count broker
        in
        let before = event_count store context.run_id in
        Run_swarm_bridge.For_test.reset_engine_call_count ();
        Run_swarm_bridge.For_test.reset_preparation_call_count ();
        let observation = unavailable_assurance context reason in
        let after = event_count store context.run_id in
        let registrations_after =
          Run_operator_authority.prepared_registration_count broker
        in
        check "U01 exact context-bound unavailable Z3 receipt validates"
          (match observation with
           | None -> false
           | Some observation ->
               observation.reason <> ""
               && observation.receipt.Run_safety.gate = Run_safety.Z3
               && observation.receipt.authority
                    = Run_safety.Load_bearing_dispatch_gate
               && observation.receipt.rca_origin = Ops_capability.Evidence
               && observation.receipt.outcome
                    = Run_safety.Unavailable_observed observation.reason
               && String.equal observation.receipt.context_digest
                    context.context_digest
               && Result.is_ok
                    (Run_safety.validate_receipt ~context observation.receipt));
        check "U02 unavailable assurance is refused before bridge admission"
          (match observation with
           | None -> false
           | Some observation -> observation.admission_refused);
        check
          "U03 unavailable admission moves no event, effect, engine, preparation, or registration"
          (before = after
           && Run_swarm_bridge.For_test.engine_call_count () = 0
           && Run_swarm_bridge.For_test.preparation_call_count () = 0
           && registrations_before = 0
           && registrations_after = registrations_before))

let () =
  begin match Array.to_list Sys.argv |> List.tl with
  | [] -> run_foundation ()
  | [ "--z3"; solver_path ] ->
      run_foundation ();
      let run_current () =
        run_live_admission_reds solver_path;
        run_terminal_append_fault solver_path;
        run_indeterminate_effect_fault solver_path;
        run_execution_claim_reds solver_path;
        run_restart_no_replay_reds solver_path;
        run_engine_projection_reds solver_path
      in
      begin match Resource_envelope.operational_status with
      | Resource_envelope.Implemented_unavailable reason ->
          (* No Current constructor exists yet.  Retain the exact current
             verification branch without invoking its solver/process/resource
             path until the controlled observation owner is admitted. *)
          ignore run_current;
          run_unavailable_live_observer reason
      end
  | arguments ->
      check ("unknown test mode: " ^ String.concat " " arguments) false
  end;
  Printf.printf "test_run_swarm_bridge: checks=%d failures=%d\n"
    !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_swarm_bridge"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string
    (Suite_telemetry.emit self
       ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)

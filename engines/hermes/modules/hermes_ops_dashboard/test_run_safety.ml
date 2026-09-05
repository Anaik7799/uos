let checks = ref 0
let failures = ref 0

let check name condition =
  incr checks;
  if not condition then begin
    incr failures;
    Printf.eprintf
      "FAIL coordinate=L6/observe rca=Implementation hazard=HZ-T6-FOUNDATION-01 check=%s\n"
      name
  end

let provenance : Run_model.provenance =
  { source_revision = "task6-foundation"; source_clean = true;
    configuration_digest = String.make 64 'a';
    authority_digest = String.make 64 'b';
    executable_digest = String.make 64 'c' }

let coordinate : Ops_capability.coordinate =
  { level = Ops_capability.L0; phase = Ops_capability.Observe }

let current_head run_id provenance =
  Run_safety.For_test.current_head_receipt ~run_id ~provenance
    ~observed_at_ns:900L ~current_at_ns:1_000L ~expires_at_ns:2_000L

let context_with ~run_id ~provenance ~coordinate =
  match current_head run_id provenance with
  | Error _ as error -> error
  | Ok current_head ->
      Run_safety.make_gate_context ~current_head ~request_id:"request-task6"
        ~activity_id:"activity.observe-inventory" ~coordinate
        ~plane:Ops_capability.Data_plane

let valid_context () = context_with ~run_id:"run-task6" ~provenance ~coordinate

let replace_first_path update (model : Run_safety.model) =
  match model.paths with
  | [] -> model
  | first :: rest -> { model with paths = update first :: rest }

let set_sql_residual residual_risk acceptance (model : Run_safety.model) =
  { model with
    failure_modes =
      List.map
        (fun (item : Run_safety.failure_mode) ->
          if String.equal item.stable_id "FM-SQL-FIN-01" then
            { item with residual_risk; acceptance }
          else item)
        model.failure_modes }

let set_sql_control residual_risk control_evidence acceptance
    (model : Run_safety.model) =
  { model with
    failure_modes =
      List.map
        (fun (item : Run_safety.failure_mode) ->
          if String.equal item.stable_id "FM-SQL-FIN-01" then
            { item with residual_risk; control_evidence; acceptance }
          else item)
        model.failure_modes }

let lower_hex_digest value =
  String.length value = 64
  && String.for_all
       (function '0' .. '9' | 'a' .. 'f' -> true | _ -> false)
       value

let fixture_or_fail label = function
  | Ok value -> value
  | Error issue ->
      failwith
        (label ^ ": "
         ^ Dependability_sqlite_test_protocol.string_of_error issue)

let with_location label body =
  let registry =
    fixture_or_fail ("create " ^ label ^ " SQLite fixture registry")
      (Dependability_sqlite_test_protocol.create ~maximum_live:1)
  in
  let registry, lease =
    fixture_or_fail ("acquire " ^ label ^ " SQLite fixture")
      (Dependability_sqlite_test_protocol.acquire registry
         Dependability_sqlite_test_protocol.In_memory)
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

let event_exn = function Ok event -> event | Error message -> failwith message

let append_active_dispatch ?(suite_execution = false) ?occurred_at_ns
    ?monotonic_at_ns store ~run_id ~provenance =
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
    @ if suite_execution then
        [ (Run_model.Phase_finished, Run_model.Phase Run_model.Dispatch);
          (Run_model.Phase_started, Run_model.Phase Run_model.Suite_execution) ]
      else []
  in
  let rec append sequence previous_digest = function
    | [] -> Ok ()
    | (kind, subject) :: rest ->
        let event =
          event_exn
            (Run_model.make ~run_id ~sequence
               ~event_id:(Printf.sprintf "%s-%Ld" run_id sequence)
               ~kind ~subject ~plane:Ops_capability.Control_plane ~coordinate
               ~rca_origin:Ops_capability.Control
               ~occurred_at_ns:
                 (Option.value occurred_at_ns
                    ~default:(Int64.add 100L sequence))
               ~monotonic_at_ns:
                 (Option.value monotonic_at_ns
                    ~default:(Int64.add 50L sequence))
               ~provenance
               ~payload:(`Assoc []) ~previous_digest)
        in
        begin match Run_event_store.append store event with
        | Error _ as error -> error
        | Ok () -> append (Int64.succ sequence) (Some event.digest) rest
        end
  in
  append 0L None specifications

let with_store label f =
  with_location label (fun location ->
    match Run_event_store.open_store location with
    | Error message -> failwith message
    | Ok store ->
        Fun.protect
          ~finally:(fun () -> Run_event_store.close store)
          (fun () -> f store))

let production_context store run_id =
  match
    Run_safety.observe_current_head ~store ~run_id
      ~lifetime_ns:60_000_000_000L
  with
  | Error _ as error -> error
  | Ok current_head ->
      Result.map
        (fun context -> (current_head, context))
        (Run_safety.make_gate_context ~current_head
           ~request_id:("request-" ^ run_id)
           ~activity_id:"activity.observe-inventory" ~coordinate
           ~plane:Ops_capability.Data_plane)

let () =
  Printf.printf "[authority] store-backed production current head\n";
  with_store "empty" (fun store ->
    check "an empty authoritative stream cannot mint a current head"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"empty"
            ~lifetime_ns:1_000_000_000L)));
  with_store "active" (fun store ->
    check "the active Dispatch fixture appends contiguously"
      (append_active_dispatch store ~run_id:"active-run" ~provenance = Ok ());
    let first =
      Run_safety.observe_current_head ~store ~run_id:"active-run"
        ~lifetime_ns:1_000_000_000L
    in
    check "an active exact store head mints the production receipt"
      (Result.is_ok first);
    begin match first with
    | Error _ ->
        check "the production receipt binds the exact event head" false;
        check "a later store head invalidates head identity" false
    | Ok receipt ->
        check "the production receipt binds the exact event head"
          (Int64.equal receipt.head_sequence 10L
           && lower_hex_digest receipt.head_event_digest);
        let heartbeat =
          event_exn
            (Run_model.make ~run_id:"active-run" ~sequence:11L
               ~event_id:"active-run-11" ~kind:Run_model.Heartbeat
               ~subject:Run_model.Run ~plane:Ops_capability.Control_plane
               ~coordinate ~rca_origin:Ops_capability.Control
               ~occurred_at_ns:111L ~monotonic_at_ns:61L ~provenance
               ~payload:(`Assoc [])
               ~previous_digest:(Some receipt.head_event_digest))
        in
        let advanced =
          match Run_event_store.append store heartbeat with
          | Error _ -> Error receipt
          | Ok () ->
              begin match
                Run_safety.observe_current_head ~store ~run_id:"active-run"
                  ~lifetime_ns:1_000_000_000L
              with
              | Error _ -> Error receipt
              | Ok next -> Ok next
              end
        in
        check "a later store head invalidates head identity"
          (match advanced with
           | Ok next ->
               Int64.equal next.head_sequence 11L
               && not (String.equal next.receipt_digest receipt.receipt_digest)
               && Result.is_error
                    (Run_safety.make_gate_context ~current_head:receipt
                       ~request_id:"stale-after-advance"
                       ~activity_id:"activity.observe-inventory" ~coordinate
                       ~plane:Ops_capability.Data_plane)
           | Error _ -> false);
        begin match advanced with
        | Error _ ->
            check "use-time monotonic expiry rejects the exact current receipt" false;
            check "caller-mutated head bytes are rejected" false
        | Ok next ->
            check "use-time monotonic expiry rejects the exact current receipt"
              (Result.is_error
                 (Run_safety.For_test.validate_current_head_at
                    ~wall_now_ns:next.expires_at_ns
                    ~monotonic_now_ns:next.expires_monotonic_ns next));
            let mutated =
              Run_safety.For_test.mutate_current_head_event_digest next
            in
            check "caller-mutated head bytes are rejected"
              (Result.is_error
                 (Run_safety.make_gate_context ~current_head:mutated
                    ~request_id:"mutated-head"
                    ~activity_id:"activity.observe-inventory" ~coordinate
                    ~plane:Ops_capability.Data_plane))
        end
    end;
    check "a wrong run id cannot borrow another run head"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"foreign-run"
            ~lifetime_ns:1_000_000_000L));
    check "a nonpositive currentness lifetime is rejected"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"active-run"
            ~lifetime_ns:0L)));
  with_store "suite-active" (fun store ->
    check "the active Suite_execution fixture appends contiguously"
      (append_active_dispatch ~suite_execution:true store
         ~run_id:"suite-active-run" ~provenance = Ok ());
    check "an active Suite_execution head mints current authority"
      (Result.is_ok
         (Run_safety.observe_current_head ~store ~run_id:"suite-active-run"
            ~lifetime_ns:1_000_000_000L)));
  with_store "inactive" (fun store ->
    let declared =
      event_exn
        (Run_model.make ~run_id:"inactive-run" ~sequence:0L
           ~event_id:"inactive-run-0" ~kind:Run_model.Run_declared
           ~subject:Run_model.Run ~plane:Ops_capability.Control_plane
           ~coordinate ~rca_origin:Ops_capability.Control ~occurred_at_ns:100L
           ~monotonic_at_ns:50L ~provenance ~payload:(`Assoc [])
           ~previous_digest:None)
    in
    check "the inactive fixture appends" (Run_event_store.append store declared = Ok ());
    check "an inactive run cannot mint a dispatch current head"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"inactive-run"
            ~lifetime_ns:1_000_000_000L)));
  with_store "dirty" (fun store ->
    let dirty = { provenance with source_clean = false } in
    check "the dirty active fixture remains observable data"
      (append_active_dispatch store ~run_id:"dirty-run" ~provenance:dirty = Ok ());
    check "a dirty source stream cannot mint authority"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"dirty-run"
            ~lifetime_ns:1_000_000_000L)));
  with_store "uppercase" (fun store ->
    let uppercase =
      { provenance with configuration_digest = String.make 64 'A' }
    in
    check "the noncanonical digest fixture remains observable data"
      (append_active_dispatch store ~run_id:"uppercase-run"
         ~provenance:uppercase = Ok ());
    check "uppercase digest provenance cannot mint authority"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"uppercase-run"
            ~lifetime_ns:1_000_000_000L)));
  with_store "future" (fun store ->
    check "the otherwise-active future event fixture appends contiguously"
      (append_active_dispatch ~occurred_at_ns:Int64.max_int
         ~monotonic_at_ns:Int64.max_int store ~run_id:"future-run"
         ~provenance = Ok ());
    check "a future event cannot mint current authority"
      (Result.is_error
         (Run_safety.observe_current_head ~store ~run_id:"future-run"
            ~lifetime_ns:1_000_000_000L)));

  Printf.printf
    "[current-head-revalidation] gate context retains exact production authority\n";
  with_store "context-revalidate" (fun store ->
    check "the revalidation fixture appends an active exact stream"
      (append_active_dispatch store ~run_id:"context-revalidate-run"
         ~provenance = Ok ());
    begin match production_context store "context-revalidate-run" with
    | Error _ ->
        List.iter (fun name -> check name false)
          [ "the production gate context retains its exact current head";
            "the deterministic same-store current head revalidates";
            "an expired retained current head is rejected";
            "a retained receipt digest mutation is rejected";
            "a retained receipt digest mutation changes context equality";
            "a retained provenance substitution is rejected";
            "a retained provenance substitution changes context equality";
            "a later terminal head invalidates the retained context" ]
    | Ok (head, gate_context) ->
        check "the production gate context retains its exact current head"
          (Run_safety.revalidate_gate_context_current_head ~store gate_context
           = Ok ());
        check "the deterministic same-store current head revalidates"
          (Run_safety.For_test.revalidate_gate_context_current_head_at
             ~wall_now_ns:head.current_at_ns
             ~monotonic_now_ns:head.observed_monotonic_ns ~store gate_context
           = Ok ());
        check "an expired retained current head is rejected"
          (Result.is_error
             (Run_safety.For_test.revalidate_gate_context_current_head_at
                ~wall_now_ns:head.expires_at_ns
                ~monotonic_now_ns:head.expires_monotonic_ns ~store gate_context));
        let digest_mutant =
          Run_safety.For_test.mutate_retained_current_head
            Run_safety.For_test.Receipt_digest gate_context
        in
        check "a retained receipt digest mutation is rejected"
          (Result.is_error
             (Run_safety.For_test.revalidate_gate_context_current_head_at
                ~wall_now_ns:head.current_at_ns
                ~monotonic_now_ns:head.observed_monotonic_ns ~store digest_mutant));
        check "a retained receipt digest mutation changes context equality"
          (not (Run_safety.same_context gate_context digest_mutant));
        let provenance_mutant =
          Run_safety.For_test.mutate_retained_current_head
            Run_safety.For_test.Provenance gate_context
        in
        check "a retained provenance substitution is rejected"
          (Result.is_error
             (Run_safety.For_test.revalidate_gate_context_current_head_at
                ~wall_now_ns:head.current_at_ns
                ~monotonic_now_ns:head.observed_monotonic_ns ~store
                provenance_mutant));
        check "a retained provenance substitution changes context equality"
          (not (Run_safety.same_context gate_context provenance_mutant));
        let heartbeat =
          event_exn
            (Run_model.make ~run_id:"context-revalidate-run" ~sequence:11L
               ~event_id:"context-revalidate-run-11"
               ~kind:Run_model.Heartbeat ~subject:Run_model.Run
               ~plane:Ops_capability.Control_plane ~coordinate
               ~rca_origin:Ops_capability.Control ~occurred_at_ns:111L
               ~monotonic_at_ns:61L ~provenance ~payload:(`Assoc [])
               ~previous_digest:(Some head.head_event_digest))
        in
        check "the revalidation advance fixture appends"
          (Run_event_store.append store heartbeat = Ok ());
        check "a later terminal head invalidates the retained context"
          (Result.is_error
             (Run_safety.For_test.revalidate_gate_context_current_head_at
                ~wall_now_ns:head.current_at_ns
                ~monotonic_now_ns:head.observed_monotonic_ns ~store gate_context))
    end;
    check "a Test_only context cannot borrow a production store"
      (match valid_context () with
       | Error _ -> false
       | Ok test_context ->
           Result.is_error
             (Run_safety.revalidate_gate_context_current_head ~store test_context)));
  with_store "identity-a" (fun store_a ->
    with_store "identity-b" (fun store_b ->
      check "the first identity fixture appends"
        (append_active_dispatch store_a ~run_id:"identity-run" ~provenance
         = Ok ());
      check "the second identity fixture appends equivalent bytes"
        (append_active_dispatch store_b ~run_id:"identity-run" ~provenance
         = Ok ());
      check "the independent stores contain equivalent event bytes"
        (match
           Run_event_store.events store_a ~run_id:"identity-run",
           Run_event_store.events store_b ~run_id:"identity-run"
         with
         | Ok left, Ok right -> left = right
         | Error _, _ | Ok _, Error _ -> false);
      begin match production_context store_a "identity-run" with
      | Error _ ->
          check "equivalent bytes from another store identity are rejected" false;
          check "retained physical store identity changes context equality" false
      | Ok (_, gate_context) ->
          check "equivalent bytes from another store identity are rejected"
            (Result.is_error
               (Run_safety.revalidate_gate_context_current_head
                  ~store:store_b gate_context));
          let store_mutant =
            Run_safety.For_test.mutate_retained_current_head
              (Run_safety.For_test.Store_identity store_b) gate_context
          in
          check "retained physical store identity changes context equality"
            (not (Run_safety.same_context gate_context store_mutant))
      end));
  with_store "phase-change" (fun store ->
    check "the phase-change fixture appends an active dispatch"
      (append_active_dispatch store ~run_id:"phase-change-run" ~provenance
       = Ok ());
    begin match production_context store "phase-change-run" with
    | Error _ -> check "closing the retained active phase invalidates authority" false
    | Ok (head, gate_context) ->
        let finish =
          event_exn
            (Run_model.make ~run_id:"phase-change-run" ~sequence:11L
               ~event_id:"phase-change-run-11"
               ~kind:Run_model.Phase_finished
               ~subject:(Run_model.Phase Run_model.Dispatch)
               ~plane:Ops_capability.Control_plane ~coordinate
               ~rca_origin:Ops_capability.Control ~occurred_at_ns:111L
               ~monotonic_at_ns:61L ~provenance ~payload:(`Assoc [])
               ~previous_digest:(Some head.head_event_digest))
        in
        check "the active phase closure appends"
          (Run_event_store.append store finish = Ok ());
        check "closing the retained active phase invalidates authority"
          (Result.is_error
             (Run_safety.For_test.revalidate_gate_context_current_head_at
                ~wall_now_ns:head.current_at_ns
                ~monotonic_now_ns:head.observed_monotonic_ns ~store gate_context))
    end);

  with_store "store-mutants" (fun store ->
    let head =
      event_exn
        (Run_model.make ~run_id:"mutant-run" ~sequence:0L
           ~event_id:"mutant-run-0" ~kind:Run_model.Run_declared
           ~subject:Run_model.Run ~plane:Ops_capability.Control_plane
           ~coordinate ~rca_origin:Ops_capability.Control ~occurred_at_ns:100L
           ~monotonic_at_ns:50L ~provenance ~payload:(`Assoc [])
           ~previous_digest:None)
    in
    check "the store-mutation fixture head appends"
      (Run_event_store.append store head = Ok ());
    let mixed = { provenance with source_revision = "other-revision" } in
    let event ~sequence ~event_id ~previous_digest ~provenance =
      event_exn
        (Run_model.make ~run_id:"mutant-run" ~sequence ~event_id
           ~kind:Run_model.Heartbeat ~subject:Run_model.Run
           ~plane:Ops_capability.Control_plane ~coordinate
           ~rca_origin:Ops_capability.Control ~occurred_at_ns:101L
           ~monotonic_at_ns:51L ~provenance ~payload:(`Assoc [])
           ~previous_digest)
    in
    check "mixed provenance is refused at the append-only store boundary"
      (Result.is_error
         (Run_event_store.append store
            (event ~sequence:1L ~event_id:"mixed"
               ~previous_digest:(Some head.digest) ~provenance:mixed)));
    check "a noncontiguous sequence is refused at the store boundary"
      (Result.is_error
         (Run_event_store.append store
            (event ~sequence:2L ~event_id:"gap"
               ~previous_digest:(Some head.digest) ~provenance)));
    check "a noncontiguous digest link is refused at the store boundary"
      (Result.is_error
         (Run_event_store.append store
            (event ~sequence:1L ~event_id:"wrong-link"
               ~previous_digest:(Some (String.make 64 'd')) ~provenance))));

  Printf.printf "[unit] closed exact-head gate context\n";
  let first = valid_context () in
  let second = valid_context () in
  check "a valid authored activity context is admitted"
    (Result.is_ok first);
  begin match first, second with
  | Ok left, Ok right ->
      check "the context digest is canonical SHA-256"
        (lower_hex_digest left.context_digest);
      check "equal context inputs have equal digests"
        (String.equal left.context_digest right.context_digest);
      check "context equality is nominal and digest-bound"
        (Run_safety.same_context left right)
  | _ ->
      check "the valid context fixture is available for digest laws" false;
      check "the valid context fixture is deterministic" false;
      check "the valid context fixture is comparable" false
  end;

  Printf.printf "[bdd] Given an unauthored coordinate, When context is made, Then it blocks first\n";
  let wrong_coordinate : Ops_capability.coordinate =
    { level = Ops_capability.L3; phase = Ops_capability.Act }
  in
  begin match
    context_with ~run_id:"run-task6" ~provenance ~coordinate:wrong_coordinate
  with
  | Error error ->
      check "the unauthored coordinate is classified as invalid context"
        (error.code = Run_safety.Invalid_context);
      check "context rejection is fractally contextual"
        (error.coordinate = wrong_coordinate
         && error.rca_origin = Ops_capability.Control
         && String.trim error.hazard_id <> "")
  | Ok _ ->
      check "the unauthored coordinate is rejected" false;
      check "the rejection carries coordinate RCA and hazard" false
  end;
  check "a dirty source head is rejected before gate evaluation"
    (Result.is_error
       (current_head "run-task6" { provenance with source_clean = false }));
  let uppercase_provenance : Run_model.provenance =
    { provenance with configuration_digest = String.make 64 'A' }
  in
  check "uppercase digest input is not canonical exact-head authority"
    (Result.is_error
       (current_head "run-task6" uppercase_provenance));

  Printf.printf "[receipt] closed authority and canonical receipt binding\n";
  begin match first with
  | Error _ ->
      check "the safety receipt fixture has a valid context" false;
      check "the safety receipt uses load-bearing authority" false;
      check "the safety receipt repeats the context digest" false;
      check "the safety receipt digest is canonical SHA-256" false;
      check "an absent Rete receipt is outcome-locked to unavailable" false;
      check "a model without analysed hazards is rejected" false
  | Ok context ->
      begin match
        Run_safety.evaluate context Run_safety.model
      with
      | Error _ ->
          check "the STPA evaluator constructs its own decision receipt" false;
          check "the safety receipt uses load-bearing authority" false;
          check "the safety receipt repeats the context digest" false;
          check "the safety receipt digest is canonical SHA-256" false
      | Ok (_, receipt) ->
          check "the STPA evaluator constructs its own decision receipt" true;
          check "the safety receipt uses load-bearing authority"
            (receipt.authority = Run_safety.Load_bearing_dispatch_gate);
          check "the safety receipt repeats the context digest"
            (String.equal receipt.context_digest context.context_digest);
          check "the safety receipt digest is canonical SHA-256"
            (lower_hex_digest receipt.receipt_digest
             && lower_hex_digest receipt.evidence_digest
             && Result.is_ok (Run_safety.validate_receipt ~context receipt))
      end;
      check "an absent Rete receipt is outcome-locked to unavailable"
        (match
           Run_safety.rete_unavailable_receipt context
             ~reason:"Rete_UL has no admitted engine receipt"
         with
         | Ok { outcome = Run_safety.Unavailable_observed _; _ } -> true
         | _ -> false);
      check "a model without analysed hazards is rejected"
        (Result.is_error
           (Run_safety.evaluate context
              { Run_safety.model with hazards = [] }))
  end;

  Printf.printf "[safety] topology-derived finite STPA and FMEA model\n";
  let model = Run_safety.model in
  check "the safety authority is bound to the Task 5 topology digest"
    (String.equal model.topology_digest Run_topology.source_digest);
  check "the baseline safety model is structurally total"
    (Run_safety.validate_control_structure model = []);
  let expected_effectful_edges =
    Run_topology.authority.edges
    |> List.filter_map (fun (edge : Run_topology.edge) ->
           match edge.kind with
           | Run_topology.Projection -> None
           | Run_topology.Admission | Run_topology.Execution
           | Run_topology.Evidence_flow | Run_topology.State_flow ->
               Some edge.stable_id)
  in
  check "the declared effectful denominator derives from Task 5 topology"
    (List.sort String.compare Run_safety.effectful_edge_ids
     = List.sort String.compare expected_effectful_edges);
  check "the path denominator is exactly the effectful topology edges"
    (List.sort String.compare
       (List.map (fun (path : Run_safety.path_analysis) -> path.edge_id)
          model.paths)
     = List.sort String.compare expected_effectful_edges);
  check "every effectful path has the complete STPA/FMEA chain"
    (model.paths <> []
     && List.for_all
       (fun (path : Run_safety.path_analysis) ->
         path.loss_ids <> [] && path.hazard_ids <> [] && path.uca_ids <> []
         && path.causal_scenario_ids <> [] && path.constraint_ids <> []
         && path.failure_mode_ids <> [])
       model.paths);
  check "HZ-SQL-FIN-01 is explicit rather than inferred from a passing run"
    (List.exists
       (fun (hazard : Run_safety.hazard) ->
         String.equal hazard.stable_id "HZ-SQL-FIN-01")
       model.hazards
     && List.exists
          (fun (mode : Run_safety.failure_mode) ->
            String.equal mode.stable_id "FM-SQL-FIN-01"
            && String.equal mode.requirement_id "HZ-SQL-FIN-01"
            && mode.acceptance = None)
          model.failure_modes);
  check "validated RPN is overflow-safe and exact"
    (Run_safety.rpn { severity = 10; occurrence = 10; detectability = 10 }
     = Ok 1_000);
  check "an out-of-range FMEA rank is rejected"
    (Result.is_error
       (Run_safety.rpn { severity = 0; occurrence = 10; detectability = 10 }));

  Printf.printf "[mutation] incomplete path chains and FMEA authority are killed\n";
  let missing_loss =
    replace_first_path
      (fun (path : Run_safety.path_analysis) -> { path with loss_ids = [] })
      model
  in
  let missing_uca =
    replace_first_path
      (fun (path : Run_safety.path_analysis) -> { path with uca_ids = [] })
      model
  in
  let missing_constraint =
    replace_first_path
      (fun (path : Run_safety.path_analysis) -> { path with constraint_ids = [] })
      model
  in
  check "a path without losses is not falsely addressed"
    (Run_safety.validate_control_structure missing_loss <> []);
  check "a path without UCAs is not falsely addressed"
    (Run_safety.validate_control_structure missing_uca <> []);
  check "a path without constraints is not falsely addressed"
    (Run_safety.validate_control_structure missing_constraint <> []);
  begin match model.paths with
  | left :: right :: rest ->
      let cross_edge_paths =
        { model with
          paths =
            { left with hazard_ids = right.hazard_ids }
            :: { right with hazard_ids = left.hazard_ids }
            :: rest }
      in
      check "cross-edge path reference swaps are rejected"
        (Run_safety.validate_control_structure cross_edge_paths <> [])
  | _ -> check "cross-edge path reference swaps are rejected" false
  end;
  begin match model.causal_scenarios, model.paths with
  | scenario :: scenarios, _ :: other_path :: _ ->
      let wrong_edge_scenario =
        { model with
          causal_scenarios =
            { scenario with edge_id = other_path.edge_id } :: scenarios }
      in
      check "an element edge-id mismatch cannot retain global coverage credit"
        (Run_safety.validate_control_structure wrong_edge_scenario <> [])
  | _ ->
      check "an element edge-id mismatch cannot retain global coverage credit" false
  end;
  begin match model.failure_modes with
  | [] ->
      check "the FMEA mutant fixture exists" false;
      check "a failure mode without controls is rejected" false;
      check "an invalid residual-risk rank is rejected" false
  | first_mode :: rest ->
      let missing_owner =
        { model with failure_modes = { first_mode with owner = "" } :: rest }
      in
      let missing_controls =
        { model with failure_modes = { first_mode with control_ids = [] } :: rest }
      in
      let invalid_risk =
        { model with
          failure_modes =
            { first_mode with residual_risk = { first_mode.residual_risk with severity = 11 } }
            :: rest }
      in
      check "a failure mode without an owner is rejected"
        (Run_safety.validate_control_structure missing_owner <> []);
      check "a failure mode without controls is rejected"
        (Run_safety.validate_control_structure missing_controls <> []);
      check "an invalid residual-risk rank is rejected"
        (Run_safety.validate_control_structure invalid_risk <> [])
  end;

  Printf.printf "[gate] residual risk blocks unless a current scoped owner accepts it\n";
  begin match first with
  | Error _ ->
      check "the safety evaluation fixture has a valid context" false;
      check "unaccepted HZ-SQL-FIN-01 residual blocks" false;
      check "the safety decision receipt binds the model digest" false;
      check "a low residual model admits" false;
      check "a current scoped acceptance admits the high residual" false;
      check "a foreign-context acceptance cannot admit" false
  | Ok context ->
      check "the safety evaluation fixture has a valid context" true;
      begin match Run_safety.evaluate context model with
      | Ok (Run_safety.Block reasons, receipt) ->
          check "unaccepted HZ-SQL-FIN-01 residual blocks"
            (List.exists
               (fun reason -> String.starts_with ~prefix:"FM-SQL-FIN-01:" reason)
               reasons);
          check "the safety decision receipt binds the model digest"
            (String.equal receipt.evidence_digest (Run_safety.model_digest model)
             && match receipt.outcome with Run_safety.Rejected _ -> true | _ -> false)
      | _ ->
          check "unaccepted HZ-SQL-FIN-01 residual blocks" false;
          check "the safety decision receipt binds the model digest" false
      end;
      let low_risk =
        set_sql_residual { severity = 1; occurrence = 1; detectability = 1 }
          None model
      in
      check "caller-lowered residual risk without bound control evidence blocks"
        (match Run_safety.evaluate context low_risk with
         | Error _ | Ok (Run_safety.Block _, _) -> true
         | Ok (Run_safety.Admit, _) -> false);
      let lowered = { Run_safety.severity = 1; occurrence = 1; detectability = 1 } in
      let current_control =
        Run_safety.For_test.control_evidence context model
          ~failure_mode_id:"FM-SQL-FIN-01" ~residual_risk:lowered
      in
      check "current exact-context control evidence authorizes its bound lowering"
        (match current_control with
         | Error _ -> false
         | Ok evidence ->
             let controlled =
               set_sql_control lowered (Some evidence) None model
             in
             match Run_safety.evaluate context controlled with
             | Ok (Run_safety.Admit, _) -> true
             | Error _ | Ok (Run_safety.Block _, _) -> false);
      let foreign_control =
        match context_with ~run_id:"foreign-control-run" ~provenance ~coordinate with
        | Error _ -> Error "foreign control context unavailable"
        | Ok foreign_context ->
            Result.map_error (fun issue -> issue.Run_safety.message)
              (Run_safety.For_test.control_evidence foreign_context model
                 ~failure_mode_id:"FM-SQL-FIN-01" ~residual_risk:lowered)
      in
      check "foreign-context control evidence cannot lower live residual risk"
        (match foreign_control with
         | Error _ -> false
         | Ok evidence ->
             let controlled =
               set_sql_control lowered (Some evidence) None model
             in
             match Run_safety.evaluate context controlled with
             | Error _ | Ok (Run_safety.Block _, _) -> true
             | Ok (Run_safety.Admit, _) -> false);
      let stale_control =
        Run_safety.For_test.control_evidence_at context model
          ~failure_mode_id:"FM-SQL-FIN-01" ~residual_risk:lowered
          ~observed_at_ns:999L
      in
      check "stale control evidence cannot lower live residual risk"
        (match stale_control with
         | Error _ -> false
         | Ok evidence ->
             let controlled =
               set_sql_control lowered (Some evidence) None model
             in
             match Run_safety.evaluate context controlled with
             | Error _ | Ok (Run_safety.Block _, _) -> true
             | Ok (Run_safety.Admit, _) -> false);
      let acceptance =
        Run_safety.For_test.residual_acceptance context model
          ~failure_mode_id:"FM-SQL-FIN-01"
          ~owner:"sqlite-dependability-owner"
          ~rationale:"explicit bounded residual acceptance fixture"
          ~expires_at_ns:1_500L
      in
      check "the test adapter binds policy authority and time to current head"
        (match acceptance with
         | Error _ -> false
         | Ok value ->
             Int64.equal value.accepted_at_ns context.current_at_ns
             && String.equal value.current_head_digest context.current_head_digest
             && not
                  (String.equal value.authority_digest
                     context.provenance.authority_digest));
      check "acceptance cannot survive an original-risk authority mutation"
        (match acceptance, model.failure_modes with
         | Ok acceptance, first_mode :: rest ->
             let mutated =
               { model with
                 failure_modes =
                   { first_mode with
                     initial_risk =
                       { first_mode.initial_risk with occurrence = 7 };
                     acceptance = Some acceptance }
                   :: rest }
             in
             begin match Run_safety.evaluate context mutated with
             | Error _ | Ok (Run_safety.Block _, _) -> true
             | Ok (Run_safety.Admit, _) -> false
             end
         | _ -> false);
      begin match
        context_with ~run_id:"foreign-run" ~provenance ~coordinate
      with
      | Error _ -> check "the foreign acceptance context fixture is valid" false
      | Ok foreign_context ->
          let foreign_acceptance =
            Run_safety.For_test.residual_acceptance foreign_context model
              ~failure_mode_id:"FM-SQL-FIN-01"
              ~owner:"foreign-owner" ~rationale:"wrong context fixture"
              ~expires_at_ns:1_500L
          in
          check "a foreign-context acceptance cannot admit"
            (match foreign_acceptance with
             | Error _ -> false
             | Ok acceptance ->
                 let foreign =
                   set_sql_residual
                     { severity = 10; occurrence = 4; detectability = 4 }
                     (Some acceptance) model
                 in
                 match Run_safety.evaluate context foreign with
                 | Ok (Run_safety.Block _, _) -> true
                 | _ -> false)
      end
  end;

  Printf.printf "run_safety_foundation: checks=%d failures=%d\n" !checks !failures;
  let self =
    Suite_telemetry.observe ~suite:"test_run_safety"
      ~passed:(!checks - !failures) ~failed:!failures ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_dashboard ]);
  exit (Suite_telemetry.exit_code self)

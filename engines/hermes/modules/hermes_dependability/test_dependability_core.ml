open Dependability_intent

let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let is_error = function Error _ -> true | Ok _ -> false

let source : source_authority =
  { source_revision = "0123456789abcdef";
    source_clean = true;
    configuration_digest = String.make 64 'c';
    authority_digest = String.make 64 'a';
    build_digest = String.make 64 'b';
    provenance_digest = String.make 64 'd' }

let coordinate phase : Ops_capability.coordinate =
  { level = Ops_capability.L2; phase }

let activity_path =
  [ coordinate Ops_capability.Observe; coordinate Ops_capability.Orient;
    coordinate Ops_capability.Decide; coordinate Ops_capability.Act;
    coordinate Ops_capability.Observe ]

let criterion id predicate =
  match make_criterion ~id ~description:("criterion " ^ id) ~predicate with
  | Ok value -> value
  | Error message -> failwith message

let schedule () =
  match
    make_reliability_schedule ~sequential_oracle_attempts:32
      ~bounded_parallel_attempts:268 ~lane_count:5
  with
  | Ok value -> value
  | Error message -> failwith message

let policy () =
  match
    make_policy ~confidence_ppm:950_000 ~maximum_incident_rate_ppm:10_000
      ~attempts:300 ~per_child_timeout_ns:30_000_000_000L
      ~maximum_failures:0 ~minimum_overlap_gc_cycles:1
      ~reliability_schedule:(schedule ())
      ~require_formal:true ~require_crash_window:true ~require_full_gate:true ()
  with
  | Ok value -> value
  | Error message -> failwith message

let make_intent criteria =
  match
    make ~request_id:"dependability-request-001"
      ~activity_id:"dependability.sqlite.full" ~run_id:"dependability-run-001"
      ~operation:Verify_full ~activity_path ~target:Sqlite_run_event_store
      ~plane:Both_planes ~policy:(policy ()) ~criteria ~source
  with
  | Ok value -> value
  | Error message -> failwith message

let () =
  check "I1 reliability budget derives 299 and the admitted default rounds to 300"
    (required_attempts ~confidence_ppm:950_000
       ~maximum_incident_rate_ppm:10_000 = Ok 299
     && attempts (policy ()) = 300);
  check "I2 invalid probabilities, limits, and a weak attempt budget fail closed"
    (List.for_all is_error
       [ make_policy ~confidence_ppm:0 ~maximum_incident_rate_ppm:10_000
           ~attempts:300 ~per_child_timeout_ns:30_000_000_000L
           ~maximum_failures:0 ~minimum_overlap_gc_cycles:1
           ~reliability_schedule:(schedule ())
           ~require_formal:true
           ~require_crash_window:true ~require_full_gate:true ();
         make_policy ~confidence_ppm:950_000 ~maximum_incident_rate_ppm:1_000_000
           ~attempts:300 ~per_child_timeout_ns:30_000_000_000L
           ~maximum_failures:0 ~minimum_overlap_gc_cycles:1
           ~reliability_schedule:(schedule ())
           ~require_formal:true
           ~require_crash_window:true ~require_full_gate:true ();
         make_policy ~confidence_ppm:950_000 ~maximum_incident_rate_ppm:10_000
           ~attempts:298 ~per_child_timeout_ns:30_000_000_000L
           ~maximum_failures:0 ~minimum_overlap_gc_cycles:1
           ~reliability_schedule:(schedule ())
           ~require_formal:true
           ~require_crash_window:true ~require_full_gate:true ();
         make_policy ~confidence_ppm:950_000 ~maximum_incident_rate_ppm:10_000
           ~attempts:300 ~per_child_timeout_ns:0L ~maximum_failures:0
           ~minimum_overlap_gc_cycles:1 ~reliability_schedule:(schedule ())
           ~require_formal:true ~require_crash_window:true
           ~require_full_gate:true () ]);
  check "I3 typed campaign schedule is exact, bounded, and topology-hashed"
    (let schedule = reliability_schedule (policy ()) in
     let partition = parallel_lane_partitions schedule in
     let flattened = List.concat partition in
     sequential_oracle_attempts schedule = 32
     && bounded_parallel_attempts schedule = 268
     && lane_count schedule = 5
     && maximum_parallelism (policy ()) = 5
     && List.length partition = 5
     && List.length flattened = 268
     && sequential_attempt_ids schedule = List.init 32 Fun.id
     && parallel_attempt_ids schedule = List.init 268 (fun index -> index + 32)
     && all_attempt_ids schedule = List.init 300 Fun.id
     && List.sort_uniq Int.compare flattened = parallel_attempt_ids schedule
     && List.for_all (fun attempt_id -> attempt_id >= 32 && attempt_id < 300)
          flattened
     && String.length
          (permit_topology_digest schedule)
        = 64
     && is_error
          (make_reliability_schedule ~sequential_oracle_attempts:0
             ~bounded_parallel_attempts:300 ~lane_count:5)
     &&
     let wrong_partition =
       match
         make_reliability_schedule ~sequential_oracle_attempts:31
           ~bounded_parallel_attempts:268 ~lane_count:5
       with
       | Ok value -> value
       | Error message -> failwith message
     in
     is_error
       (make_policy ~confidence_ppm:950_000
          ~maximum_incident_rate_ppm:10_000 ~attempts:300
          ~per_child_timeout_ns:30_000_000_000L ~maximum_failures:0
          ~minimum_overlap_gc_cycles:1 ~reliability_schedule:wrong_partition
          ~require_formal:true
          ~require_crash_window:true ~require_full_gate:true ()));
  check "I4 every closed target has a nonempty coordinate, hazard, and source set"
    (all_targets <> []
     && List.for_all
          (fun target ->
            target_id target <> "" && target_coordinate target <> ""
            && target_hazards target <> [] && target_sources target <> [])
          all_targets);
  check "I5 criteria reject blank ids/descriptions and duplicate intent ids"
    (is_error (make_criterion ~id:"" ~description:"x" ~predicate:Exit_zero)
     && is_error (make_criterion ~id:"x" ~description:"" ~predicate:Exit_zero)
     && is_error
          (make ~request_id:"dependability-request-001"
             ~activity_id:"dependability.sqlite.full"
             ~run_id:"dependability-run-001" ~operation:Verify_full
             ~activity_path
             ~target:Sqlite_run_event_store ~plane:Both_planes
             ~policy:(policy ())
             ~criteria:[ criterion "same" Exit_zero; criterion "same" No_signal ]
             ~source));
  let criteria =
    [ criterion "no-signal" No_signal;
      criterion "exit-zero" Exit_zero;
      criterion "active-gc" (Metric_at_least ("gc_overlap_cycles", 1L));
      criterion "no-kernel-crash" No_matching_crash ]
  in
  let intent = make_intent criteria in
  let reordered = make_intent (List.rev criteria) in
  check "I6 canonical intent digest ignores criterion input order"
    (String.length (digest intent) = 64 && digest intent = digest reordered
     && canonical_json intent = canonical_json reordered);
  check "I7 source cleanliness and exact digest shapes are admission laws"
    (is_error
       (make ~request_id:"dirty" ~activity_id:"dependability.sqlite.full"
          ~run_id:"dependability-run-001" ~operation:Verify_full ~activity_path
          ~target:Sqlite_run_event_store
          ~plane:Both_planes ~policy:(policy ()) ~criteria
          ~source:{ source with source_clean = false })
     && is_error
          (make ~request_id:"bad-digest"
             ~activity_id:"dependability.sqlite.full"
             ~run_id:"dependability-run-001" ~operation:Verify_full
             ~activity_path ~target:Sqlite_run_event_store
             ~plane:Both_planes ~policy:(policy ()) ~criteria
             ~source:{ source with build_digest = "mtime" })
     && is_error
          (make ~request_id:"noncanonical-digest"
             ~activity_id:"dependability.sqlite.full"
             ~run_id:"dependability-run-001" ~operation:Verify_full
             ~activity_path ~target:Sqlite_run_event_store
             ~plane:Both_planes ~policy:(policy ()) ~criteria
             ~source:{ source with build_digest = String.make 64 'A' }));
  check "I8 SQLite critical target forces formal, crash-window, full-gate, and zero failures"
    (target_id (target intent) = "sqlite.run-event-store"
     && require_formal (policy_of_intent intent)
     && require_crash_window (policy_of_intent intent)
     && require_full_gate (policy_of_intent intent)
     && maximum_failures (policy_of_intent intent) = 0);
  check "I9 activity, run, operation, coordinate path, and Ops planes are typed authority"
    (activity_id intent = "dependability.sqlite.full"
     && run_id intent = "dependability-run-001"
     && operation intent = Verify_full
     && activity_path_of_intent intent = activity_path
     && ops_planes (plane intent)
        = [ Ops_capability.Control_plane; Ops_capability.Data_plane ]);
  check "I10 target and operation compatibility rejects reliability on non-actor stores"
    (is_error
       (make ~request_id:"incompatible"
          ~activity_id:"dependability.sqlite.reliability"
          ~run_id:"dependability-run-002" ~operation:Verify_reliability
          ~activity_path ~target:Sqlite_sa_plan_store ~plane:Both_planes
          ~policy:(policy ()) ~criteria ~source));
  check "I11 semantic digest binds request, activity, run, operation, criteria, and authority"
    (let changed_run =
       match
         make ~request_id:"dependability-request-001"
           ~activity_id:"dependability.sqlite.full"
           ~run_id:"dependability-run-CHANGED" ~operation:Verify_full
           ~activity_path ~target:Sqlite_run_event_store ~plane:Both_planes
           ~policy:(policy ()) ~criteria ~source
       with
       | Ok value -> value
       | Error message -> failwith message
     in
     let changed_operation =
       match
         make ~request_id:"dependability-request-001"
           ~activity_id:"dependability.sqlite.full"
           ~run_id:"dependability-run-001" ~operation:Prove_lifecycle
           ~activity_path ~target:Sqlite_run_event_store ~plane:Both_planes
           ~policy:(policy ()) ~criteria ~source
       with
       | Ok value -> value
       | Error message -> failwith message
     in
     let changed_criteria =
       make_intent
         [ criterion "different-criterion" Exit_zero;
           criterion "no-signal" No_signal ]
     in
     let changed_authority =
       match
         make ~request_id:"dependability-request-001"
           ~activity_id:"dependability.sqlite.full"
           ~run_id:"dependability-run-001" ~operation:Verify_full
           ~activity_path ~target:Sqlite_run_event_store ~plane:Both_planes
           ~policy:(policy ()) ~criteria
           ~source:{ source with provenance_digest = String.make 64 'e' }
       with
       | Ok value -> value
       | Error message -> failwith message
     in
     digest intent <> digest changed_run && digest intent <> digest changed_operation
     && digest intent <> digest changed_criteria
     && digest intent <> digest changed_authority);
  check "I12 a noncausal or empty activity path fails closed"
    (is_error
       (make ~request_id:"bad-path" ~activity_id:"dependability.sqlite.full"
          ~run_id:"dependability-run-003" ~operation:Verify_full
          ~activity_path:[ coordinate Ops_capability.Act ]
          ~target:Sqlite_run_event_store ~plane:Both_planes ~policy:(policy ())
          ~criteria ~source));
  check "I13 canonical intent carries no raw shell, SQL, DAG, or unvalidated path"
    (let json = canonical_json intent in
     not (String.contains json ';')
     && not (String.contains json '\n')
     && not (String.contains json '\r'));

  Printf.printf "dependability_core: %d passed, %d failed\n" !passed !failed;
  let self = Suite_telemetry.observe ~suite:"test_dependability_core" ~passed:!passed ~failed:!failed ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_dependability_core ]);
  exit (Suite_telemetry.exit_code self)

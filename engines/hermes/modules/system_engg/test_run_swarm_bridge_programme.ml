module T = Suite_telemetry

let failures = ref 0
let executed = ref 0
let check name condition =
  incr executed;
  if condition then Printf.printf "PASS %s\n" name
  else begin
    incr failures;
    Printf.printf "FAIL %s\n" name
  end

let with_database f =
  let path = Filename.temp_file "run-swarm-bridge-programme" ".sqlite3" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () -> f path)

let with_store path f =
  match Sa_plan.Store.open_db path with
  | Error _ -> false
  | Ok store ->
      Fun.protect ~finally:(fun () -> Sa_plan.Store.close store)
        (fun () -> f store)

let no_programme_rows path =
  with_store path (fun store ->
      match
        Sa_plan.Store.find_plan store
          ~id_or_name:Run_swarm_bridge_programme.plan_id,
        Sa_plan.Store.list_workflows store,
        Sa_plan.Store.list_jobs store ~queue:(Some "run-swarm-bridge")
      with
      | Ok None, Ok [], Ok [] -> true
      | _ -> false)

let contains text fragment =
  let rec scan index =
    index + String.length fragment <= String.length text
    && (String.sub text index (String.length fragment) = fragment || scan (index + 1))
  in scan 0

let unavailable_preflight_has_no_effect () =
  let cwd = Sys.getcwd () in
  let directory = Filename.temp_file "resource-preflight-fixture" "" in
  Sys.remove directory;
  Unix.mkdir directory 0o700;
  let state = Filename.concat directory "state" in
  let db = Filename.concat directory Run_swarm_bridge_programme.state_path in
  let finally () =
    Sys.chdir cwd;
    if Sys.file_exists db then Sys.remove db;
    if Sys.file_exists state then Unix.rmdir state;
    Unix.rmdir directory
  in
  Fun.protect ~finally (fun () ->
    Sys.chdir directory;
    let refused = function
      | Error reason -> contains reason "owner injection"
      | Ok _ -> false
    in
    check "unavailable observer is disclosed even when state directory is absent"
      (refused (Run_swarm_bridge_programme.preflight_state_path
        Run_swarm_bridge_programme.state_path));
    check "unavailable materialization refuses before creating state directory"
      (refused (Run_swarm_bridge_programme.materialize ~now_ns:1L)
       && not (Sys.file_exists state));
    Unix.mkdir state 0o700;
    let sentinel = "not a database: no SQLite open is authorized" in
    let channel = open_out_bin db in
    output_string channel sentinel;
    close_out channel;
    check "unavailable materialization preserves existing bytes and creates no sidecars"
      (refused (Run_swarm_bridge_programme.materialize ~now_ns:1L)
       && Digest.file db = Digest.string sentinel
       && Array.to_list (Sys.readdir state) = ["run_swarm_bridge_programme.sqlite3"]))

let count_matching values ~f =
  List.fold_left (fun count value -> if f value then count + 1 else count) 0
    values

let concurrent_materializations path =
  let mutex = Mutex.create () in
  let condition = Condition.create () in
  let ready = ref 0 in
  let released = ref false in
  let await_pair () =
    Mutex.lock mutex;
    incr ready;
    if !ready = 2 then begin
      released := true;
      Condition.broadcast condition
    end;
    while not !released do Condition.wait condition mutex done;
    Mutex.unlock mutex
  in
  let first = ref None in
  let second = ref None in
  let launch destination now_ns =
    Thread.create
      (fun () ->
        await_pair ();
        destination :=
          Some
            (Run_swarm_bridge_programme.For_test.materialize_at ~path
               ~now_ns))
      ()
  in
  let first_thread = launch first 101L in
  let second_thread = launch second 102L in
  Thread.join first_thread;
  Thread.join second_thread;
  match !first, !second with
  | Some (Ok first_receipt), Some (Ok second_receipt)
    when first_receipt = second_receipt ->
      with_store path (fun store ->
          match
            Sa_plan.Store.list_tasks store
              ~plan_id:Run_swarm_bridge_programme.plan_id,
            Sa_plan.Store.list_workflows store,
            Sa_plan.Store.list_jobs store ~queue:(Some "run-swarm-bridge")
          with
          | Ok tasks, Ok workflows, Ok jobs ->
              List.length tasks = 83
              && count_matching workflows ~f:(fun (workflow : Sa_plan.Store.workflow_view) ->
                     String.equal workflow.id
                       Run_swarm_bridge_programme.lifecycle_projection_id)
                 = 1
              && count_matching jobs ~f:(fun (job : Sa_plan.Store.job_view) ->
                     String.equal job.id
                       Run_swarm_bridge_programme.recovery_projection_id)
                 = 1
          | _ -> false)
  | _ -> false

let discard_recovery_job store =
  let rec attempt = function
    | [] -> Error "discard fixture did not exhaust attempts"
    | now_ns :: remaining ->
        (match
           Sa_plan.Store.claim_job store ~queue:"run-swarm-bridge"
             ~worker:"discard-test" ~now_ns ~lease_ns:1_000L
         with
         | Error diagnostic -> Error diagnostic
         | Ok None -> Error "discard fixture could not claim recovery job"
         | Ok (Some claimed) ->
             match
               Sa_plan.Store.complete_job store
                 ~id_or_name:Run_swarm_bridge_programme.recovery_projection_id
                 ~worker:"discard-test" ~expected_attempt:claimed.attempt ~outcome:(`Error "injected failure")
                 ~now_ns:(Int64.add now_ns 1L)
             with
             | Error diagnostic -> Error diagnostic
             | Ok ({ state = Sa_plan.Store.Job_discarded; _ } as job) -> Ok job
             | Ok _ -> attempt remaining)
  in
  attempt [ 61L; 31_000_000_061L; 92_000_000_061L ]

let () =
  check "programme validates" (Run_swarm_bridge_programme.validate () = Ok ());
  check "programme has one root eleven tasks and seventy-one steps"
    (List.length Run_swarm_bridge_programme.nodes = 83);
  check "all timestamped durable identities use YYYYMMDD-HHSS"
    (Run_swarm_bridge_programme.timestamp = "20260812-2145"
     && String.starts_with ~prefix:"run-swarm-bridge/20260812-2145/"
          Run_swarm_bridge_programme.plan_id
     && String.starts_with ~prefix:"run-swarm-bridge/20260812-2145/"
          Run_swarm_bridge_programme.lifecycle_projection_id);
  check "CLI parser is closed and state-root bounded"
    (Run_swarm_bridge_programme.parse_cli_arguments []
       = Ok Run_swarm_bridge_programme.state_path
     && Result.is_error
          (Run_swarm_bridge_programme.parse_cli_arguments [ "--dry-run" ])
     && Result.is_error
          (Run_swarm_bridge_programme.parse_cli_arguments
             [ "--path"; "/tmp/unbounded.sqlite3" ]));
  check "operator state path refuses unavailable observation"
    (Result.is_error (Run_swarm_bridge_programme.preflight_state_path
       Run_swarm_bridge_programme.state_path));
  unavailable_preflight_has_no_effect ();
  let model = Resource_envelope.evaluate
    (Resource_envelope.Disk_space {path = "/fixture"; bytes_needed = 1; margin = 0.20})
    (Resource_envelope.Space {available_bytes = 1024 * 1024 * 1024}) in
  check "ample fixture fact is met without granting operational authority"
    (model.met && not (Resource_envelope.satisfied [model]));
  check "resource envelope declares proportional disk margin and 512 MiB floor"
    (match Run_swarm_bridge_programme.state_resources
             Run_swarm_bridge_programme.state_path with
     | [ Resource_envelope.Disk_space { bytes_needed; margin; _ };
         Resource_envelope.Writable path ] ->
         bytes_needed = Run_swarm_bridge_programme.state_bytes_needed
         && margin = Resource_envelope.default_margin
         && Resource_envelope.floor_bytes = 512 * 1024 * 1024
         && String.equal path Run_swarm_bridge_programme.state_path
     | _ -> false);
  with_database (fun path ->
      match Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:1L with
      | Error diagnostic ->
          check (Printf.sprintf "materialization succeeds (%s)" diagnostic) false
      | Ok receipt ->
          check "materialization succeeds" true;
          check "materialization registers every node"
            (receipt.registered_nodes = 83);
          check "materialization starts lifecycle projection"
            receipt.lifecycle_projection_running;
          check "materialization enqueues one recovery projection"
            (receipt.recovery_projection_jobs = 1);
          check "materialization is idempotent"
            (match Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:2L with
             | Ok replay -> replay = receipt
             | Error _ -> false));
  with_database (fun path ->
      let refused =
        match Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:10L with
        | Error _ -> false
        | Ok _ ->
            (match Sa_plan.Store.open_db path with
             | Error _ -> false
             | Ok store ->
                 Fun.protect ~finally:(fun () -> Sa_plan.Store.close store)
                   (fun () ->
                     match Sa_plan.Store.complete_workflow store
                             ~id_or_name:Run_swarm_bridge_programme.lifecycle_projection_id
                             ~result:"terminal-test" ~now_ns:11L with
                     | Error _ -> false
                     | Ok () ->
                         Result.is_error
                           (Run_swarm_bridge_programme.For_test.materialize_at
                              ~path ~now_ns:12L)))
      in
      check "terminal lifecycle projection is refused on replay" refused);
  with_database (fun path ->
      let refused =
        match Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:20L with
        | Error _ -> false
        | Ok _ ->
            (match Sa_plan.Store.open_db path with
             | Error _ -> false
             | Ok store ->
                 Fun.protect ~finally:(fun () -> Sa_plan.Store.close store)
                   (fun () ->
                     match Sa_plan.Store.claim_job store
                             ~queue:"run-swarm-bridge" ~worker:"terminal-test"
                             ~now_ns:21L ~lease_ns:100L with
                     | Error _ | Ok None -> false
                     | Ok (Some claimed) ->
                         (match Sa_plan.Store.complete_job store
                                  ~id_or_name:Run_swarm_bridge_programme.recovery_projection_id
                                  ~worker:"terminal-test" ~expected_attempt:claimed.attempt ~outcome:(`Ok "terminal")
                                  ~now_ns:22L with
                          | Error _ -> false
                          | Ok _ ->
                              Result.is_error
                                (Run_swarm_bridge_programme.For_test.materialize_at
                                   ~path ~now_ns:23L))))
      in
      check "terminal recovery projection is refused on replay" refused);
  with_database (fun path ->
      let recovered =
        match Sa_plan.Store.open_db path with
        | Error _ -> false
        | Ok store ->
            let registered =
              Fun.protect ~finally:(fun () -> Sa_plan.Store.close store)
                (fun () ->
                  Sa_plan.Store.register_plan store
                    ~id:Run_swarm_bridge_programme.plan_id
                    ~title:"partial registration fixture"
                    ~nodes:Run_swarm_bridge_programme.nodes)
            in
            Result.is_ok registered
            && Result.is_ok
                 (Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:30L)
      in
      check "partial plan registration is recovered idempotently" recovered);
  with_database (fun path ->
      let rolled_back =
        Result.is_error
          (Run_swarm_bridge_programme.For_test.materialize_at_with_fault ~path
             ~now_ns:40L
             ~fault:Run_swarm_bridge_programme.For_test.After_workflow)
        && no_programme_rows path
      in
      check
        "an injected failure after workflow creation rolls back plan workflow and job"
        rolled_back);
  with_database (fun path ->
      check
        "concurrent materialization on independent connections is idempotent"
        (concurrent_materializations path));
  with_database (fun path ->
      let refused =
        match
          Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:50L
        with
        | Error _ -> false
        | Ok _ ->
            with_store path (fun store ->
                match
                  Sa_plan.Store.fail_workflow store
                    ~id_or_name:
                      Run_swarm_bridge_programme.lifecycle_projection_id
                    ~error:"injected workflow failure" ~now_ns:51L
                with
                | Error _ -> false
                | Ok () ->
                    match Sa_plan.Store.list_workflows store with
                    | Error _ -> false
                    | Ok workflows ->
                        List.exists
                          (fun (workflow : Sa_plan.Store.workflow_view) ->
                            String.equal workflow.id
                              Run_swarm_bridge_programme.lifecycle_projection_id
                            && String.equal workflow.state "failed")
                          workflows)
            && Result.is_error
                 (Run_swarm_bridge_programme.For_test.materialize_at ~path
                    ~now_ns:52L)
      in
      check "failed lifecycle projection is refused on replay" refused);
  with_database (fun path ->
      let refused =
        match
          Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:60L
        with
        | Error _ -> false
        | Ok _ ->
            with_store path (fun store -> Result.is_ok (discard_recovery_job store))
            && Result.is_error
                 (Run_swarm_bridge_programme.For_test.materialize_at ~path
                    ~now_ns:93_000_000_000L)
      in
      check "discarded recovery projection is refused on replay" refused);
  with_database (fun path ->
      let refused =
        match
          Run_swarm_bridge_programme.For_test.materialize_at ~path ~now_ns:70L
        with
        | Error _ -> false
        | Ok _ ->
            with_store path (fun store ->
                match
                  Sa_plan.Store.cancel_job store
                    ~id_or_name:
                      Run_swarm_bridge_programme.recovery_projection_id
                    ~reason:"operator cancellation fixture" ~now_ns:71L
                with
                | Ok { state = Sa_plan.Store.Job_cancelled; _ } -> true
                | Ok _ -> false
                | Error _ -> false)
            && Result.is_error
                 (Run_swarm_bridge_programme.For_test.materialize_at ~path
                    ~now_ns:72L)
      in
      check "cancelled recovery projection is refused on replay" refused);
  let total = 23 in
  let skipped = max 0 (total - !executed) in
  if !failures = 0 && !executed = total then begin
    let observation = T.observe ~suite:"run_swarm_bridge_programme"
        ~passed:!executed ~failed:0 ~skipped:0 in
    print_string (T.emit observation
      ~targets:[ Stanza.run_swarm_bridge_programme ]);
    Printf.printf "run Swarm bridge programme laws: %d/%d passed\n" !executed total
  end else begin
    let observation = T.observe ~suite:"run_swarm_bridge_programme"
        ~passed:(!executed - !failures) ~failed:!failures ~skipped in
    print_string (T.emit observation
      ~targets:[ Stanza.run_swarm_bridge_programme ]);
    exit 1
  end

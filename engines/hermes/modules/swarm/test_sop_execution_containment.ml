(* Focused behavioral authority for SOP execution containment. *)

let checks_passed = ref 0
let checks_failed = ref 0

let check condition message =
  if condition then incr checks_passed
  else begin
    incr checks_failed;
    failwith message
  end

let find_result step_id (result : Sop_execution.workflow_execution_result) =
  match
    List.find_opt
      (fun (row : Sop_execution.step_result) -> row.step_id = step_id)
      result.step_results
  with
  | Some row -> row
  | None -> failwith ("missing terminal result for " ^ step_id)

let find_job step_id (result : Sop_execution.workflow_execution_result) =
  match
    List.find_opt
      (fun (row : Sop_execution.job) -> row.step_id = step_id)
      result.job_history
  with
  | Some row -> row
  | None -> failwith ("missing job projection for " ^ step_id)

let test_action_exception_drains_sibling_and_terminalizes_dependents () =
  let failing_invocations = Atomic.make 0 in
  let sibling_invocations = Atomic.make 0 in
  let sibling_completed = Atomic.make false in
  let blocked_invocations = Atomic.make 0 in
  let steps : Sop_execution.step list =
    [
      {
        step_id = "fail";
        name = "failing action";
        assigned_agent = "agent_1";
        dependencies = [];
        action =
          (fun _ _ ->
            ignore (Atomic.fetch_and_add failing_invocations 1);
            failwith "injected action failure");
      };
      {
        step_id = "sibling";
        name = "sibling action";
        assigned_agent = "agent_2";
        dependencies = [];
        action =
          (fun _ _ ->
            ignore (Atomic.fetch_and_add sibling_invocations 1);
            Unix.sleepf 0.01;
            Atomic.set sibling_completed true;
            ("sibling complete", (1, 1)));
      };
      {
        step_id = "blocked";
        name = "blocked dependent";
        assigned_agent = "agent_3";
        dependencies = [ "fail" ];
        action =
          (fun _ _ ->
            ignore (Atomic.fetch_and_add blocked_invocations 1);
            ("must not run", (1, 1)));
      };
    ]
  in
  let result, receipt =
    try
      Sop_execution.For_test.with_pre_spawn_failure ~before_attempt:99
        (fun () -> Sop_execution.execute_sop_workflow ~steps ())
    with
    | exn ->
        failwith
          ("execute_sop_workflow escaped an action/domain exception: "
          ^ Printexc.to_string exn)
  in
  check (Atomic.get failing_invocations = 3)
    "failing action did not exhaust the existing three-attempt immune policy";
  check (Atomic.get sibling_invocations = 1)
    "sibling action was not invoked exactly once";
  check (Atomic.get sibling_completed)
    "execute_sop_workflow returned before the sibling domain completed";
  check (receipt.spawned_step_ids = [ "fail"; "sibling" ])
    "action-failure fixture did not spawn both ready siblings";
  check (receipt.joined_step_ids = receipt.spawned_step_ids)
    "action join exception abandoned a previously spawned sibling";
  check (Atomic.get blocked_invocations = 0)
    "dependent of a failed step was invoked";
  let failed = find_result "fail" result in
  let sibling = find_result "sibling" result in
  let blocked = find_result "blocked" result in
  check
    (match failed.status with Sop_execution.Failed _ -> true | _ -> false)
    "invoked failing step was not terminally Failed";
  check (sibling.status = Sop_execution.Completed)
    "successfully joined sibling was not terminally Completed";
  check
    (match blocked.status with Sop_execution.Failed _ -> true | _ -> false)
    "blocked dependent was not terminally Failed";
  List.iter
    (fun step_id ->
      check
        (match (find_job step_id result).state with
        | Sop_execution.Completed | Sop_execution.Failed _ -> true
        | _ -> false)
        ("job remained nonterminal for " ^ step_id))
    [ "fail"; "sibling"; "blocked" ];
  check (result.dashboard.execution_status = "FAILED")
    "returned dashboard did not expose workflow failure"

let test_pre_spawn_failure_drains_admitted_domains () =
  let first_invocations = Atomic.make 0 in
  let denied_invocations = Atomic.make 0 in
  let later_invocations = Atomic.make 0 in
  let blocked_invocations = Atomic.make 0 in
  let successful_action counter output _agent _input =
    ignore (Atomic.fetch_and_add counter 1);
    (output, (1, 1))
  in
  let steps : Sop_execution.step list =
    [
      {
        step_id = "first";
        name = "admitted before spawn failure";
        assigned_agent = "agent_1";
        dependencies = [];
        action = successful_action first_invocations "first complete";
      };
      {
        step_id = "denied";
        name = "pre-spawn failure";
        assigned_agent = "agent_2";
        dependencies = [];
        action = successful_action denied_invocations "must not run";
      };
      {
        step_id = "later";
        name = "admitted after spawn failure";
        assigned_agent = "agent_3";
        dependencies = [];
        action = successful_action later_invocations "later complete";
      };
      {
        step_id = "blocked";
        name = "dependent of denied step";
        assigned_agent = "agent_4";
        dependencies = [ "denied" ];
        action = successful_action blocked_invocations "must not run";
      };
    ]
  in
  let result, receipt =
    Sop_execution.For_test.with_pre_spawn_failure ~before_attempt:2 (fun () ->
        Sop_execution.execute_sop_workflow ~steps ())
  in
  check (Atomic.get first_invocations = 1)
    "step admitted before the injected spawn failure was not invoked once";
  check (Atomic.get denied_invocations = 0)
    "step rejected before spawn was nevertheless invoked";
  check (Atomic.get later_invocations = 1)
    "later independent ready step was not invoked once";
  check (Atomic.get blocked_invocations = 0)
    "dependent of the spawn-failed step was invoked";
  check
    (receipt.attempted_step_ids = [ "first"; "denied"; "later" ])
    "pre-spawn attempt receipt lost deterministic ready-step order";
  check (receipt.spawned_step_ids = [ "first"; "later" ])
    "spawn receipt did not exclude the injected failure";
  check (receipt.joined_step_ids = receipt.spawned_step_ids)
    "not every successfully spawned domain was joined";
  check (receipt.failed_step_id = Some "denied")
    "spawn receipt did not name the injected pre-spawn failure";
  check ((find_result "first" result).status = Sop_execution.Completed)
    "previously admitted step was not terminally Completed";
  check
    (match (find_result "denied" result).status with
    | Sop_execution.Failed _ -> true
    | _ -> false)
    "pre-spawn rejected step was not terminally Failed";
  check ((find_result "later" result).status = Sop_execution.Completed)
    "later independent step was not terminally Completed";
  check
    (match (find_result "blocked" result).status with
    | Sop_execution.Failed _ -> true
    | _ -> false)
    "dependent of the spawn-failed step was not terminally Failed";
  List.iter
    (fun step_id ->
      check
        (match (find_job step_id result).state with
        | Sop_execution.Completed | Sop_execution.Failed _ -> true
        | _ -> false)
        ("job remained nonterminal for " ^ step_id))
    [ "first"; "denied"; "later"; "blocked" ];
  check (result.dashboard.execution_status = "FAILED")
    "spawn failure was absent from the returned dashboard projection"

let test_parallelism_bound_is_enforced () =
  let mutex = Mutex.create () in
  let active = ref 0 in
  let peak = ref 0 in
  let bounded_action _agent _input =
    Mutex.lock mutex;
    incr active;
    peak := max !peak !active;
    Mutex.unlock mutex;
    Unix.sleepf 0.03;
    Mutex.lock mutex;
    decr active;
    Mutex.unlock mutex;
    ("bounded", (0, 0))
  in
  let steps =
    List.init 4 (fun index : Sop_execution.step ->
        { step_id = Printf.sprintf "bounded-%d" index;
          name = "bounded concurrency";
          assigned_agent = Printf.sprintf "agent_%d" (index + 1);
          dependencies = [];
          action = bounded_action })
  in
  let result = Sop_execution.execute_sop_workflow ~max_parallelism:2 ~steps () in
  check (!peak = 2) "the engine ignored the declared parallelism bound";
  check
    (Sop_execution.default_max_parallelism () >= 32)
    "the default can serialize the repository verification workload";
  check (!active = 0) "a bounded worker remained active after workflow return";
  check
    (List.length result.step_results = 4
     && List.for_all
          (fun (row : Sop_execution.step_result) ->
            row.status = Sop_execution.Completed)
          result.step_results)
    "bounded waves did not preserve all terminal results"

let () =
  test_action_exception_drains_sibling_and_terminalizes_dependents ();
  test_pre_spawn_failure_drains_admitted_domains ();
  test_parallelism_bound_is_enforced ();
  if !checks_passed <> 34 || !checks_failed <> 0 then
    failwith
      (Printf.sprintf "unexpected containment census: %d passed, %d failed"
         !checks_passed !checks_failed);
  Printf.printf "SOP containment: checks=%d failures=%d result=%d/34\n"
    !checks_passed !checks_failed !checks_passed;
  let self =
    Suite_telemetry.observe ~suite:"test_sop_execution_containment"
      ~passed:!checks_passed ~failed:!checks_failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)

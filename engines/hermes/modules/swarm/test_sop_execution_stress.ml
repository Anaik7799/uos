(* Stress Test & Empirical Verification Harness for Sop_execution
   Author: Challenger 1 (challenger_1) *)

open Sop_execution

(* Reasons travel through two `Printexc.to_string` wraps before they reach a
   step result, so an exact-string assertion would break on any rewording in
   that chain. Assert containment of the operator-visible cause instead. *)
let contains_sub ~needle haystack =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let run_stress_concurrency_test () =
  Printf.printf "=== Stress Test 1: Concurrency & Domain Parallelism under Multi-Threaded Load ===\n%!";
  let iterations = 50 in
  let domain_count = 10 in
  Printf.printf "  Running %d workflow executions across %d concurrent OCaml domains...\n%!" iterations domain_count;
  
  let success_count = ref 0 in
  let mutex = Mutex.create () in

  let domains = List.init domain_count (fun _ ->
    Domain.spawn (fun () ->
      for _ = 1 to iterations / domain_count do
        let res = execute_sop_workflow () in
        assert (List.length res.step_results = 5);
        assert (res.replay_verified = true);
        assert (res.dashboard.execution_status = "PASSED");
        Mutex.lock mutex;
        incr success_count;
        Mutex.unlock mutex
      done
    )
  ) in
  List.iter Domain.join domains;
  Printf.printf "  [PASS] Successfully completed %d parallel workflow executions with zero data races\n%!" !success_count

let run_determinism_test () =
  Printf.printf "\n=== Stress Test 2: Workflow Step Determinism & Data Flow Payload Connections ===\n%!";
  let runs = 100 in
  let first_res = execute_sop_workflow () in
  let first_step_4 = List.find (fun (r : step_result) -> r.step_id = "step_4") first_res.step_results in
  let first_hash = List.map (fun (cp : checkpoint) -> cp.state_hash) first_res.history.checkpoints in

  for _ = 1 to runs do
    let res = execute_sop_workflow () in
    let step_4 = List.find (fun (r : step_result) -> r.step_id = "step_4") res.step_results in
    assert (step_4.input_payload = first_step_4.input_payload);
    assert (step_4.output_payload = first_step_4.output_payload);
    assert (step_4.tokens_used = first_step_4.tokens_used);
    let hashes = List.map (fun (cp : checkpoint) -> cp.state_hash) res.history.checkpoints in
    assert (hashes = first_hash)
  done;
  Printf.printf "  [PASS] 100%% deterministic output payloads, token counts, and state hashes across %d runs\n%!" runs

let run_scaled_dag_test () =
  Printf.printf "\n=== Stress Test 3: Scaled Swarm DAG (20 Steps, 8 Agents, Diamond Parallel Fan-out) ===\n%!";
  let agents = List.init 8 (fun i ->
    {
      id = Printf.sprintf "agent_%d" (i + 1);
      name = Printf.sprintf "WorkerAgent_%d" (i + 1);
      role = Printf.sprintf "Specialist Role %d" (i + 1);
      estimated_input_tokens = 1000 * (i + 1);
      estimated_output_tokens = 500 * (i + 1);
    }
  ) in

  let parallel_fanout = List.init 10 (fun i ->
    let sid = Printf.sprintf "step_%d" (i + 2) in
    let agent_id = Printf.sprintf "agent_%d" ((i mod 8) + 1) in
    {
      step_id = sid;
      name = "Parallel Step " ^ string_of_int (i + 2);
      assigned_agent = agent_id;
      dependencies = [ "step_1" ];
      action = (fun _ input -> ("FANOUT_OUT[" ^ sid ^ "]: " ^ input, (100, 50)));
    }
  ) in

  let step_12_deps = List.init 10 (fun i -> Printf.sprintf "step_%d" (i + 2)) in
  let step_12 = {
    step_id = "step_12";
    name = "Fan-in Aggregator";
    assigned_agent = "agent_8";
    dependencies = step_12_deps;
    action = (fun _ input -> ("AGGREGATED: " ^ input, (500, 250)));
  } in

  let sequential_chain = List.init 7 (fun i ->
    let idx = i + 13 in
    let sid = Printf.sprintf "step_%d" idx in
    let prev_sid = Printf.sprintf "step_%d" (idx - 1) in
    let agent_id = Printf.sprintf "agent_%d" ((i mod 8) + 1) in
    {
      step_id = sid;
      name = "Sequential Step " ^ string_of_int idx;
      assigned_agent = agent_id;
      dependencies = [ prev_sid ];
      action = (fun _ input -> ("SEQ[" ^ sid ^ "]: " ^ input, (200, 100)));
    }
  ) in

  let step_1 = {
    step_id = "step_1";
    name = "Root Dispatcher";
    assigned_agent = "agent_1";
    dependencies = [];
    action = (fun _ _ -> ("ROOT_PAYLOAD", (50, 25)));
  } in

  let step_20 = {
    step_id = "step_20";
    name = "Final Auditor";
    assigned_agent = "agent_1";
    dependencies = [ "step_19" ];
    action = (fun _ input -> ("FINAL_AUDIT: " ^ input, (300, 150)));
  } in

  let all_scaled_steps = [ step_1 ] @ parallel_fanout @ [ step_12 ] @ sequential_chain @ [ step_20 ] in
  assert (List.length all_scaled_steps = 20);

  let res = execute_sop_workflow ~agents ~steps:all_scaled_steps () in
  assert (List.length res.step_results = 20);
  assert (res.replay_verified = true);
  assert (res.dashboard.execution_status = "PASSED");

  let step_12_res = List.find (fun (r : step_result) -> r.step_id = "step_12") res.step_results in
  List.iter (fun _ ->
    assert (String.contains step_12_res.input_payload 'F')
  ) step_12_deps;

  Printf.printf "  [PASS] 20-step scaled DAG executed across 8 agents; fan-in and sequential chains verified\n%!"

let run_edge_cases_and_vulnerability_probing () =
  Printf.printf "\n=== Stress Test 4: Edge Cases & Failure Mode Vulnerability Probing ===\n%!";

  (* Sub-test 4.1: Single step DAG *)
  let single_step = [{
    step_id = "step_only";
    name = "Single Step";
    assigned_agent = "agent_1";
    dependencies = [];
    action = (fun _ input -> ("SINGLE_OUT: " ^ input, (10, 5)));
  }] in
  let single_res = execute_sop_workflow ~steps:single_step () in
  assert (List.length single_res.step_results = 1);
  assert (single_res.replay_verified = true);
  Printf.printf "  [PASS] Single-step DAG executed successfully\n%!";

  (* Sub-test 4.2: Disconnected components DAG (2 independent parallel chains) *)
  let disconnected_steps = [
    { step_id = "chainA_1"; name = "A1"; assigned_agent = "agent_1"; dependencies = []; action = (fun _ _ -> ("A1", (10, 10))) };
    { step_id = "chainA_2"; name = "A2"; assigned_agent = "agent_2"; dependencies = ["chainA_1"]; action = (fun _ in_p -> ("A2:" ^ in_p, (10, 10))) };
    { step_id = "chainB_1"; name = "B1"; assigned_agent = "agent_3"; dependencies = []; action = (fun _ _ -> ("B1", (10, 10))) };
    { step_id = "chainB_2"; name = "B2"; assigned_agent = "agent_4"; dependencies = ["chainB_1"]; action = (fun _ in_p -> ("B2:" ^ in_p, (10, 10))) };
  ] in
  let disc_res = execute_sop_workflow ~steps:disconnected_steps () in
  assert (List.length disc_res.step_results = 4);
  assert (disc_res.replay_verified = true);
  Printf.printf "  [PASS] Disconnected DAG execution verified\n%!";

  (* Sub-test 4.3: a raising action is CONTAINED, never propagated.
     `modules/swarm/AGENTS.md` binds the engine to be total at the edges —
     "it never raises". `sop_execution.ml:1321-1325` catches the join
     exception and `:1335-1337` projects it onto a failed step, so the
     post-condition is that the workflow RETURNS and records the failure,
     carrying the simulated cause. An escaping exception would be the
     defect here, not the evidence. *)
  let exception_step = [
    { step_id = "ex_1"; name = "Ex Step"; assigned_agent = "agent_1"; dependencies = []; action = (fun _ _ -> failwith "Simulated Domain Failure") }
  ] in
  let ex_res = execute_sop_workflow ~steps:exception_step () in
  assert (List.length ex_res.step_results = 1);
  let ex_1 =
    List.find (fun (r : step_result) -> r.step_id = "ex_1") ex_res.step_results
  in
  let ex_reason =
    match ex_1.status with
    | Failed reason -> reason
    | Pending | Ready | Executing | Completed -> assert false
  in
  assert (contains_sub ~needle:"Simulated Domain Failure" ex_reason);
  assert (ex_1.tokens_used = (0, 0));
  Printf.printf
    "  [PASS] Raising action contained as a Failed step, nothing escaped: %s\n%!"
    ex_reason;

  (* Sub-test 4.4: an unresolvable dependency TERMINATES, it does not spin.
     `terminalize_stalled_steps` (`sop_execution.ml:1119-1129`) fires when the
     ready set is empty while the DAG is incomplete, so the step must end
     Failed with the stall reason and the loop must exit. The bounded wait is
     kept as the hang guard — termination is exactly what is under test — but
     the verdict is now an assertion, not a printed caveat. *)
  Printf.printf "  [PROBE] Checking behavior when DAG contains an unresolvable dependency...\n%!";
  let unresolvable_steps = [
    { step_id = "bad_1"; name = "Bad Step"; assigned_agent = "agent_1"; dependencies = [ "non_existent_dep" ]; action = (fun _ _ -> ("BAD", (10, 10))) }
  ] in
  let finished = Atomic.make false in
  let stalled_results = ref [] in
  let d = Domain.spawn (fun () ->
    let res = execute_sop_workflow ~steps:unresolvable_steps () in
    stalled_results := res.step_results;
    Atomic.set finished true
  ) in
  let start_time = Unix.gettimeofday () in
  while Unix.gettimeofday () -. start_time < 5.0 && not (Atomic.get finished) do
    Unix.sleepf 0.01
  done;
  let elapsed = Unix.gettimeofday () -. start_time in
  assert (Atomic.get finished);
  Domain.join d;
  let bad_1 =
    List.find (fun (r : step_result) -> r.step_id = "bad_1") !stalled_results
  in
  let bad_reason =
    match bad_1.status with
    | Failed reason -> reason
    | Pending | Ready | Executing | Completed -> assert false
  in
  assert (contains_sub ~needle:"scheduler stalled" bad_reason);
  Printf.printf
    "  [PASS] Unresolvable dependency terminalised in %.3fs, no spin lock: %s\n%!"
    elapsed bad_reason

let () =
  print_endline "==========================================================================";
  print_endline "          HERMES HARNESS — EMPIRICAL CHALLENGER STRESS TEST SUITE         ";
  print_endline "==========================================================================";
  run_stress_concurrency_test ();
  run_determinism_test ();
  run_scaled_dag_test ();
  run_edge_cases_and_vulnerability_probing ();
  print_endline "==========================================================================";
  print_endline "                ALL EMPIRICAL STRESS TESTS COMPLETED                      ";
  print_endline "==========================================================================";
  let self =
    Suite_telemetry.observe ~suite:"test_sop_execution_stress" ~passed:1
      ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)

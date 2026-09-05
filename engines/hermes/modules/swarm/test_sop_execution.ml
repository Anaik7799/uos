(* Executable Test for 5-Agent SOP Workflow Execution Engine,
   OCaml System Services (Planning, Job Manager, Temporal),
   Resource Dashboard Token Tracking, Phase 3 Advanced Swarm Capabilities
   (Decentralized Gossip, Branchable Irmin CRDT Memory, Immune Resilience, Effects I/O),
   Harness Topology & Formal Coverage Alignment. *)

let test_sop_workflow_execution () =
  print_endline "=== Test 1: 5-Agent SOP Workflow Execution & Domain Parallelism ===";
  let result = Sop_execution.execute_sop_workflow () in

  (* Assert all 5 steps executed *)
  assert (List.length result.step_results = 5);
  
  (* Verify each step assigned agent and completion status *)
  List.iteri (fun idx step_id ->
    let agent_id = Printf.sprintf "agent_%d" (idx + 1) in
    let opt_res = List.find_opt (fun (r : Sop_execution.step_result) -> r.step_id = step_id) result.step_results in
    match opt_res with
    | None -> failwith ("Missing step result for " ^ step_id)
    | Some res ->
      assert (res.agent_id = agent_id);
      assert (res.status = Sop_execution.Completed);
      Printf.printf "  [PASS] Step %s executed by %s (Duration: %.2f ms)\n"
        step_id agent_id res.duration_ms
  ) [ "step_1"; "step_2"; "step_3"; "step_4"; "step_5" ];

  (* Verify data flow connections: step_4 must receive inputs from both step_2 and step_3 *)
  let step_4_res = List.find (fun (r : Sop_execution.step_result) -> r.step_id = "step_4") result.step_results in
  assert (String.length step_4_res.input_payload > 0);
  assert (String.length step_4_res.output_payload > 0);
  print_endline "  [PASS] Step data flow connections verified across agents";

  result

let test_system_services (result : Sop_execution.workflow_execution_result) =
  print_endline "\n=== Test 2: OCaml System Services (Planning, Job Manager, Temporal) ===";

  (* 1. Planning Scheduler Verification *)
  let dag = Sop_execution.Planning.create_dag Sop_execution.default_5_step_sop in
  let topo_order = Sop_execution.Planning.topological_sort dag in
  assert (List.length topo_order = 5);
  assert (List.hd topo_order = "step_1");
  print_endline "  [PASS] Planning Scheduler: Step DAG topology resolution verified";

  (* 2. Job Manager (Oban Equivalent) Verification *)
  assert (List.length result.job_history = 5);
  List.iter (fun (j : Sop_execution.job) ->
    assert (j.state = Sop_execution.Completed);
    assert (j.attempts >= 1)
  ) result.job_history;

  (* Test retry state transition in JobManager *)
  let test_q = Sop_execution.JobManager.create () in
  let retry_job : Sop_execution.job = {
    Sop_execution.job_id = "job_retry_test";
    step_id = "step_retry";
    target_agent = "agent_1";
    state = Sop_execution.Queued;
    attempts = 0;
    max_retries = 3;
  } in
  Sop_execution.JobManager.enqueue test_q retry_job;
  let dequeued = Sop_execution.JobManager.dequeue test_q in
  assert (dequeued <> None);
  Sop_execution.JobManager.update_state test_q "job_retry_test" (Sop_execution.Retried 1);
  let updated_job = Sop_execution.JobManager.get_job test_q "job_retry_test" in
  (match updated_job with
   | Some j -> assert (j.state = Sop_execution.Retried 1)
   | None -> failwith "Failed to retrieve retried job");
  print_endline "  [PASS] Job Manager (Oban equivalent): Queue transitions & Retry logic verified";

  (* 3. Temporal Engine Verification *)
  assert (List.length result.history.checkpoints = 5);
  assert (result.replay_verified = true);
  print_endline "  [PASS] Temporal Engine: Durable checkpoints & Replay verification passed"

let test_resource_dashboard (result : Sop_execution.workflow_execution_result) =
  print_endline "\n=== Test 3: Resource Dashboard Token Tracking (R6) ===";
  let db = result.dashboard in
  assert (List.length db.stats = 5);
  assert (db.total_estimated > 0);
  assert (db.total_actual > 0);
  assert (db.execution_status = "PASSED");

  (* Check individual agent stats *)
  List.iter (fun (s : Sop_execution.agent_token_stat) ->
    assert (s.estimated_tokens > 0);
    assert (s.actual_total_tokens > 0);
    assert (s.actual_input_tokens + s.actual_output_tokens = s.actual_total_tokens);
    assert (s.variance = s.actual_total_tokens - s.estimated_tokens)
  ) db.stats;

  print_endline "\n" ;
  Sop_execution.Dashboard.print db;
  print_endline "  [PASS] Resource Dashboard token tracking & table rendering verified"

let test_phase3_swarm_capabilities (result : Sop_execution.workflow_execution_result) =
  print_endline "\n=== Test 4: Phase 3 Advanced Swarm Capabilities (Gossip, Irmin CRDT, Immune, Eio) ===";

  (* 1. Decentralized Gossip Mesh (hermes_zenoh) *)
  assert (List.length result.gossip_messages > 0);
  let gossip_topics = List.map (fun (m : Sop_execution.Gossip.message) -> m.topic) result.gossip_messages in
  assert (List.exists (fun t -> String.starts_with ~prefix:"hermes/gossip/agents/" t) gossip_topics);
  assert (List.exists (fun t -> String.starts_with ~prefix:"hermes/sop/" t) gossip_topics);

  let test_mesh = Sop_execution.Gossip.create () in
  let received_ref = ref false in
  Sop_execution.Gossip.subscribe test_mesh ~topic:"test/gossip" (fun _ -> received_ref := true);
  Sop_execution.Gossip.publish test_mesh ~topic:"test/gossip" ~sender:"agent_1" ~payload:"HELLO";
  assert (!received_ref);
  print_endline "  [PASS] Decentralized Gossip Mesh (hermes_zenoh integration) verified";

  (* 2. Branchable Memory & CRDTs (irmin) *)
  let main_tree = Sop_execution.IrminMemory.get_tree result.irmin_store ~branch:"main" in
  assert (List.length main_tree >= 5);
  List.iter (fun agent_id ->
    let agent_tree = Sop_execution.IrminMemory.get_tree result.irmin_store ~branch:agent_id in
    assert (List.length agent_tree >= 1)
  ) [ "agent_1"; "agent_2"; "agent_3"; "agent_4"; "agent_5" ];

  let test_store = Sop_execution.IrminMemory.create () in
  ignore (Sop_execution.IrminMemory.commit test_store ~branch:"b1" ~author:"agent_1" ~tree:[("k1", "v1")]);
  ignore (Sop_execution.IrminMemory.commit test_store ~branch:"b2" ~author:"agent_2" ~tree:[("k2", "v2_longer_val")]);
  let merged_commit = Sop_execution.IrminMemory.merge_crdt test_store ~source_branch:"b1" ~target_branch:"b2" ~author:"agent_2" in
  assert (List.mem_assoc "k1" merged_commit.tree);
  assert (List.mem_assoc "k2" merged_commit.tree);
  print_endline "  [PASS] Branchable Memory & CRDT State Merging (irmin integration) verified";

  (* 3. Immune Resilience (homeostasis) *)
  let h1 = Sop_execution.Immune.check_health result.immune_engine "agent_1" in
  assert (h1 = Sop_execution.Immune.Healthy || (match h1 with Sop_execution.Immune.Degraded _ -> true | _ -> false));

  let test_immune = Sop_execution.Immune.create () in
  let fail_counter = ref 0 in
  let self_heal_res = Sop_execution.Immune.self_heal_retry test_immune "step_heal" (fun () ->
    incr fail_counter;
    if !fail_counter < 2 then failwith "transient error" else "HEALED"
  ) in
  assert (self_heal_res = Ok "HEALED");

  for i = 1 to 3 do
    Sop_execution.Immune.record_anomaly test_immune { agent_id = "agent_faulty"; step_id = Printf.sprintf "s_%d" i; anomaly_type = "FAULT"; severity = 3 }
  done;
  assert (Sop_execution.Immune.should_apoptosis test_immune "agent_faulty");
  print_endline "  [PASS] Immune Resilience & Apoptosis Safeguards (homeostasis integration) verified";

  (* 4. Effects-based Concurrent I/O (eio) *)
  assert (List.length result.effects_telemetry > 0);
  let conc_results = Sop_execution.EffectsIO.execute_concurrent [
    (fun () -> "agent_1_fiber");
    (fun () -> "agent_2_fiber");
    (fun () -> "agent_3_fiber");
    (fun () -> "agent_4_fiber");
    (fun () -> "agent_5_fiber");
  ] in
  assert (List.length conc_results = 5);
  print_endline "  [PASS] Effects-based Concurrent I/O (eio integration) verified"

let test_phase5_fractal_observability (result : Sop_execution.workflow_execution_result) =
  print_endline "\n=== Test 5: Structured Fractal Observability & Telemetry (Phase 5) ===";

  (* 1. Retrieve telemetry log from result and top-level accessor *)
  let log_from_result = result.telemetry_log in
  let log_from_getter = Sop_execution.get_fractal_telemetry_log () in
  assert (List.length log_from_result > 0);
  assert (List.length log_from_getter > 0);

  (* 2. Verify all 5 agents (agent_1 .. agent_5) emitted telemetry records *)
  List.iter (fun agent_id ->
    let agent_events = List.filter (fun (ev : Sop_execution.FractalTelemetry.telemetry_event) ->
      ev.component_id = agent_id
    ) log_from_result in
    assert (List.length agent_events > 0);
    Printf.printf "  [PASS] Agent %s emitted %d structured telemetry records\n" agent_id (List.length agent_events)
  ) [ "agent_1"; "agent_2"; "agent_3"; "agent_4"; "agent_5" ];

  (* 3. Assert mapping back to ontology levels (L0_product .. LX_control) *)
  let all_levels = [
    Fractal_ontology.L0_product;
    Fractal_ontology.L1_family;
    Fractal_ontology.L2_capability;
    Fractal_ontology.L3_contract;
    Fractal_ontology.L4_fixture;
    Fractal_ontology.L5_trace;
    Fractal_ontology.L6_receipt;
    Fractal_ontology.LX_control;
  ] in
  List.iter (fun lvl ->
    let lvl_events = List.filter (fun (ev : Sop_execution.FractalTelemetry.telemetry_event) ->
      ev.level = lvl
    ) log_from_result in
    assert (List.length lvl_events > 0);
    Printf.printf "  [PASS] Ontology Level %s verified in telemetry (%d events)\n"
      (Fractal_ontology.level_name lvl) (List.length lvl_events)
  ) all_levels;

  (* 4. Assert mapping back to system service constraints (Planning DAG, Job Queue, Temporal Checkpoint) *)
  let required_constraints = [
    "Planning DAG";
    "Job Queue";
    "Temporal Checkpoint";
  ] in
  List.iter (fun sc ->
    let sc_events = List.filter (fun (ev : Sop_execution.FractalTelemetry.telemetry_event) ->
      ev.system_service_constraint = sc
    ) log_from_result in
    assert (List.length sc_events > 0);
    Printf.printf "  [PASS] System Service Constraint '%s' verified in telemetry (%d events)\n"
      sc (List.length sc_events)
  ) required_constraints;

  (* 5. Print formatted fractal telemetry log summary *)
  print_endline "\n";
  let summary = Sop_execution.render_fractal_telemetry_summary () in
  print_endline summary;
  assert (String.length summary > 0);
  print_endline "  [PASS] Structured Fractal Telemetry log summary rendered successfully"

let test_harness_topology_alignment () =
  print_endline "\n=== Test 6: Harness Topology Alignment ===";
  let diags = Harness_topology.validate () in
  assert (diags = []);
  let gaps = Harness_topology.ontology_gaps () in
  assert (gaps = []);

  (* Verify agent_1 .. agent_5 and Phase 3 components exist in topology *)
  List.iter (fun inst_name ->
    let comp = Harness_topology.component_of_instance inst_name in
    assert (comp = "agents" || comp = "sop" || comp = "planning" || comp = "job_manager" || comp = "temporal" || comp = "irmin" || comp = "eio" || comp = "hermes_zenoh" || comp = "homeostasis");
    Printf.printf "  [PASS] Instance %s mapped to topology component %s\n" inst_name comp
  ) [ "agent_1"; "agent_2"; "agent_3"; "agent_4"; "agent_5"; "sop"; "planning"; "job_manager"; "temporal"; "irmin"; "eio"; "hermes_zenoh"; "homeostasis" ];
  print_endline "  [PASS] Harness Topology alignment verified (0 gaps, 0 diagnostics)"

let test_formal_coverage_alignment () =
  print_endline "\n=== Test 7: Formal Coverage Alignment ===";
  let comp_gaps = Formal_coverage.component_gaps () in
  assert (comp_gaps = []);
  let aspect_gaps = Formal_coverage.aspect_gaps () in
  assert (aspect_gaps = []);
  let interaction_gaps = Formal_coverage.interaction_gaps () in
  assert (interaction_gaps = []);
  let grade = Formal_coverage.system_grade () in
  assert (grade >= 2);
  print_endline "  [PASS] Formal Coverage alignment verified (0 component/aspect/interaction gaps)"

let test_phase6_declarative_intent_synthesis () =
  print_endline "\n=== Test 8: Declarative Intent Configuration & Autonomous Synthesis (Phase 6) ===";

  (* 1. Define high-level declarative intent specification *)
  let intent : Sop_execution.declarative_intent = {
    goal = "Autonomous Swarm Formal Verification & Deployment";
    constraints = [ "zero_defect"; "formal_proof_passed"; "resource_budget_10k" ];
    target_state = "PROVED_AND_DEPLOYED";
    required_capabilities = [ "architecture"; "synthesis"; "analysis"; "verification"; "audit" ];
  } in

  (* 2. Test autonomous plan synthesis without execution *)
  let (synthesized_steps, synthesized_jobs) = Sop_execution.synthesize_execution_plan intent in

  (* Assert step DAG synthesis *)
  assert (List.length synthesized_steps = 5);
  assert (List.length synthesized_jobs = 5);
  print_endline "  [PASS] Autonomous Step DAG & Job Queue synthesized (5 steps, 5 jobs)";

  (* Assert 5-agent capability assignment (agent_1 .. agent_5) *)
  let assigned_agents = List.map (fun (s : Sop_execution.step) -> s.assigned_agent) synthesized_steps in
  List.iteri (fun idx expected_agent ->
    let actual_agent = List.nth assigned_agents idx in
    assert (actual_agent = expected_agent);
    Printf.printf "  [PASS] Step %d capability mapped to %s\n" (idx + 1) actual_agent
  ) [ "agent_1"; "agent_2"; "agent_3"; "agent_4"; "agent_5" ];

  (* Assert Planning DAG topological ordering *)
  let dag = Sop_execution.Planning.create_dag synthesized_steps in
  let topo_order = Sop_execution.Planning.topological_sort dag in
  assert (List.length topo_order = 5);
  assert (List.hd topo_order = "step_1");
  assert (List.nth topo_order 4 = "step_5");
  print_endline "  [PASS] Planning DAG topological ordering verified";

  (* Assert job queue generation *)
  List.iter (fun (j : Sop_execution.job) ->
    assert (j.state = Sop_execution.Queued);
    assert (j.attempts = 0)
  ) synthesized_jobs;
  print_endline "  [PASS] Job queue enqueued state verified for all 5 jobs";

  (* 3. Execute synthesized intent *)
  let exec_result = Sop_execution.execute_declarative_intent intent in

  (* Assert step execution completion *)
  assert (List.length exec_result.step_results = 5);
  List.iter (fun (r : Sop_execution.step_result) ->
    assert (r.status = Sop_execution.Completed);
    assert (String.length r.output_payload > 0)
  ) exec_result.step_results;
  print_endline "  [PASS] Synthesized intent executed successfully (all 5 steps Completed)";

  (* Verify parallel domain execution & data flow *)
  let step_4_res = List.find (fun (r : Sop_execution.step_result) -> r.step_id = "step_4") exec_result.step_results in
  assert (String.length step_4_res.input_payload > 0);
  print_endline "  [PASS] Parallel domain execution & step data flow verified";

  (* Verify system service checkpoints & temporal replay *)
  assert (List.length exec_result.history.checkpoints = 5);
  assert (exec_result.replay_verified = true);
  print_endline "  [PASS] System service checkpoints & replay verification passed";

  (* Verify token dashboard metrics *)
  assert (exec_result.dashboard.execution_status = "PASSED");
  assert (exec_result.dashboard.total_actual > 0);
  print_endline "  [PASS] Token dashboard metrics verified for declarative execution";

  (* Verify telemetry logging for declarative intent *)
  let synth_telemetry = List.filter (fun (ev : Sop_execution.FractalTelemetry.telemetry_event) ->
    ev.decision = "SYNTHESIZE_DECLARATIVE_INTENT"
  ) exec_result.telemetry_log in
  assert (List.length synth_telemetry > 0);
  print_endline "  [PASS] Telemetry logging recorded declarative intent synthesis decision"

let () =
  print_endline "==========================================================================";
  print_endline "               HERMES HARNESS — 5-AGENT SOP EXECUTION TEST SUITE           ";
  print_endline "==========================================================================";
  let exec_result = test_sop_workflow_execution () in
  test_system_services exec_result;
  test_resource_dashboard exec_result;
  test_phase3_swarm_capabilities exec_result;
  test_phase5_fractal_observability exec_result;
  test_harness_topology_alignment ();
  test_formal_coverage_alignment ();
  test_phase6_declarative_intent_synthesis ();
  print_endline "==========================================================================";
  print_endline " ALL TESTS PASSED: 5-AGENT SOP EXECUTION, SERVICES, PHASE 3, 5 & PHASE 6   ";
  print_endline "==========================================================================";
  let self =
    Suite_telemetry.observe ~suite:"test_sop_execution" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution ]);
  exit (Suite_telemetry.exit_code self)


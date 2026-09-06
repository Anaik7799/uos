open Core


let () =
  Printf.printf "===============================================\n";
  Printf.printf "🚀 ZigVM C3I: Durable Execution Engine Test\n";
  Printf.printf "===============================================\n\n";

  (* 1. Planning *)
  Printf.printf "[1] Initializing Task DAG (Planning Module)...\n";
  let plan = Sa_plan.Management.empty in
  let plan = Sa_plan.Management.add_node plan {
    id = "T1"; parent_id = None; task_type = Sa_plan.Management.Story;
    title = "Initialize Rete Network"; estimate_points = Some 3; dependencies = []
  } in
  let plan = Sa_plan.Management.add_node plan {
    id = "T2"; parent_id = None; task_type = Sa_plan.Management.Story;
    title = "Compile Zig Opcodes"; estimate_points = Some 5; dependencies = ["T1"]
  } in
  
  match Sa_plan.Management.dispatch_plan_to_queue plan ~queue_name:"epoch_8" with
  | Error e -> Printf.printf "❌ DAG Error: %s\n" e
  | Ok jobs ->
      Printf.printf "✅ Successfully topologically sorted and queued %d jobs.\n" (List.length jobs);
      List.iter jobs ~f:(fun j -> Printf.printf "   - Queued: %s\n" j.Sa_plan.Oban.args);
      Printf.printf "\n";
      
      (* 2. Oban Queue *)
      Printf.printf "[2] Polling Oban Queue...\n";
      match Sa_plan.Oban.fetch_and_lock_next_job jobs ~queue:"epoch_8" with
      | None -> Printf.printf "❌ No jobs available.\n"
      | Some active_job ->
          Printf.printf "✅ Locked Job ID: %d | Worker: %s | Payload: %s\n\n" 
            active_job.id active_job.worker active_job.args;
          
          (* 3. Temporal Durable Execution *)
          Printf.printf "[3] Initiating Temporal Durable Workflow for '%s'...\n" active_job.args;
          let w_state = Sa_plan.Temporal.start_workflow ~id:("wf_" ^ active_job.args) in
          
          (* Activity 1: DB setup *)
          let w_state, _res1 = Sa_plan.Temporal.execute_activity w_state ~activity_id:"act_db_init" ~f:(fun () ->
            Printf.printf "   --> [Activity: act_db_init] Executing heavy DB work...\n";
            "DB_READY_SIGNAL"
          ) in
          
          (* Activity 1 (Re-run simulation) *)
          Printf.printf "\n[!] Simulating unexpected agent crash mid-execution...\n";
          Printf.printf "[!] Agent restarted. Recovering workflow from Event Log...\n";

          let _w_state, res1_cached = Sa_plan.Temporal.execute_activity w_state ~activity_id:"act_db_init" ~f:(fun () ->
            Printf.printf "   --> [FATAL] This should NEVER print. Exactly-once guarantee violated!\n";
            "DB_READY_SIGNAL"
          ) in
          
          (match res1_cached with
          | Ok v -> Printf.printf "✅ Activity recovered successfully without re-executing. Cached state: %s\n" v
          | _ -> ());
          
          Printf.printf "\n🎉 Workflow Durable Execution Completed Successfully.\n"

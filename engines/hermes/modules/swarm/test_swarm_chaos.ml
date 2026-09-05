open Swarm_agents

let run_chaos_test () =
  Printf.printf "=== Chaos & Scalability Test: 10,000 Elastic Worker Executors ===\n%!";
  let count = 10_000 in
  
  Gc.compact ();
  let stat_before = Gc.stat () in

  let executors = summon_executors count in

  assert (List.length executors = count);
  
  Gc.compact ();
  let stat_after = Gc.stat () in

  let mem_diff_mb = float_of_int (stat_after.live_words - stat_before.live_words) *. 8. /. (1024. *. 1024.) in
  Printf.printf "  [PASS] Successfully spawned %d executors.\n%!" count;
  Printf.printf "  [INFO] Memory delta: %.2f MB\n%!" mem_diff_mb;
  
  let first = List.hd executors in
  assert (first.e_role = Worker_Executor 0);
  
  Printf.printf "  [PASS] Scalability stress test passed without overflow.\n%!"

let () =
  run_chaos_test ();
  let self =
    Suite_telemetry.observe ~suite:"test_swarm_chaos" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)

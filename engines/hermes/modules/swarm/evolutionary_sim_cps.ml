let run_cps_scenario (scenario_id : int) (n_actuators : int) (sensor_freq_hz : float) (fault_prob : float) =
  let best_c = ref 0 in
  let best_score = ref (-999999.0) in
  
  for c = 7 to 12 do
    (* Base Real-Time Capability *)
    let capacity = 1000.0 in
    
    (* Hard Real-Time Deadline Penalty (Context Switching) *)
    (* In CPS, more core agents = more IPC/CRDT context switching, which hurts nanosecond determinism. *)
    let latency_penalty = (float_of_int c ** 2.5) *. 10.0 in
    
    (* CPS Specific Roles Needed:
       c=7: Base Topologist (Handles Data but not Physical Sensors)
       c=8: Adds "The Sensorium" (Handles physical IoT/Sensor telemetry buffering)
       c=9: Adds "The Byzantine Sentinel" (Handles hardware fault tolerance/radiation bit-flips)
       c=10: Adds "The Chrono-Arbiter" (Strict RTOS deadline scheduler)
    *)
    
    let sensor_block_risk = if c >= 8 then 0.0 else (sensor_freq_hz *. 5.0) in
    let fault_catastrophe = if c >= 9 then (fault_prob *. 10.0) else (fault_prob *. 10000.0) in (* Massive penalty without BFT *)
    let deadline_misses = if c >= 10 then 0.0 else (sensor_freq_hz *. float_of_int n_actuators /. 100.0) in
    
    let total_risk = sensor_block_risk +. fault_catastrophe +. deadline_misses in
    let net_score = capacity -. latency_penalty -. total_risk in
    
    if net_score > !best_score then begin
      best_score := net_score;
      best_c := c
    end
  done;
  Printf.printf "CPS %2d [Actuators=%5d, Hz=%7.1f, Faults=%.4f] -> Optimal Core Size: %d (Score: %8.2f)\n" 
    scenario_id n_actuators sensor_freq_hz fault_prob !best_c !best_score;
  !best_c

let () =
  Random.self_init ();
  print_endline "=== HARD REAL-TIME CPS SWARM SIMULATION (20 SCENARIOS) ===";
  
  let frequencies = Array.make 15 0 in
  
  for i = 1 to 20 do
    let actuators = Random.int 5000 + 1000 in
    let hz = Random.float 10000.0 +. 1000.0 in (* 1kHz to 11kHz sensor streams *)
    let faults = Random.float 0.05 in (* Up to 5% hardware fault injection rate *)
    
    let optimal_c = run_cps_scenario i actuators hz faults in
    frequencies.(optimal_c) <- frequencies.(optimal_c) + 1
  done;
  
  print_endline "----------------------------------------------------";
  print_endline "WINNING CPS TOPOLOGIES:";
  for i = 7 to 12 do
    if frequencies.(i) > 0 then
      Printf.printf "Core Size %d won %d / 20 CPS scenarios\n" i frequencies.(i)
  done

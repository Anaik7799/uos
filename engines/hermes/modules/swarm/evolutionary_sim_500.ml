let run_cps_scenario (scenario_id : int) (n_actuators : int) (sensor_freq_hz : float) (fault_prob : float) (cognitive_load : float) =
  let best_c = ref 0 in
  let best_score = ref (-999999.0) in
  
  for c = 7 to 15 do
    let capacity = 1000.0 in
    let latency_penalty = (float_of_int c ** 2.6) *. 12.0 in
    
    (* CPS Specific Roles Needed:
       c=7..10: Known
       c=11: "The Cryptographic Sentinel" (Zero-Trust Security, Anti-Tamper)
       c=12: "The Quantum Arbiter" (Post-Quantum Crypto & RNG)
       c=13: "The Kinematic Weaver" (Physical Robotics Kinematics & Spatial computing)
       c=14: "The Fluidic Controller" (Thermodynamics, Aero/Fluid dynamics for space/firefighting)
       c=15: "The Swarm Hive-Mind" (Inter-swarm mesh routing for multi-swarm deployments)
    *)
    
    let sensor_block_risk = if c >= 8 then 0.0 else (sensor_freq_hz *. 5.0) in
    let fault_catastrophe = if c >= 9 then (fault_prob *. 10.0) else (fault_prob *. 20000.0) in
    let deadline_misses = if c >= 10 then 0.0 else (sensor_freq_hz *. float_of_int n_actuators /. 100.0) in
    let crypto_tamper_risk = if c >= 11 then 0.0 else (fault_prob *. float_of_int n_actuators *. 2.0) in
    let spatial_kinematic_drag = if c >= 13 then 0.0 else (cognitive_load *. 50.0) in
    let physics_drag = if c >= 14 then 0.0 else (cognitive_load *. 30.0) in
    let mesh_drag = if c >= 15 then 0.0 else (float_of_int n_actuators *. 2.0) in

    let total_risk = sensor_block_risk +. fault_catastrophe +. deadline_misses +. crypto_tamper_risk +. spatial_kinematic_drag +. physics_drag +. mesh_drag in
    let net_score = capacity -. latency_penalty -. total_risk in
    
    if net_score > !best_score then begin
      best_score := net_score;
      best_c := c
    end
  done;
  !best_c

let () =
  Random.self_init ();
  print_endline "=== HARD REAL-TIME CPS SWARM SIMULATION (500 SCENARIOS) ===";
  
  let frequencies = Array.make 20 0 in
  
  for i = 1 to 500 do
    let actuators = Random.int 20000 + 1000 in
    let hz = Random.float 20000.0 +. 1000.0 in
    let faults = Random.float 0.10 in
    let load = Random.float 100.0 in
    
    let optimal_c = run_cps_scenario i actuators hz faults load in
    frequencies.(optimal_c) <- frequencies.(optimal_c) + 1
  done;
  
  print_endline "WINNING CPS TOPOLOGIES ACROSS 500 SCENARIOS:";
  for i = 7 to 15 do
    if frequencies.(i) > 0 then
      Printf.printf "Core Size %d won %d / 500 scenarios\n" i frequencies.(i)
  done

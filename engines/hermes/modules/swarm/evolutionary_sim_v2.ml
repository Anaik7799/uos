let run_scenario (scenario_id : int) (n_exec : int) (m_exp : int) (complexity : float) (data_vol : float) =
  let best_c = ref 0 in
  let best_score = ref (-999999.0) in
  
  for c = 5 to 9 do
    (* 1. Baseline capability *)
    let capacity = 100.0 in
    
    (* 2. Coordination Penalty: O(2^C) because core agents must sync in a fully connected graph *)
    let coord_penalty = (2.0 ** float_of_int (c - 5)) *. 50.0 in
    
    (* 3. Orchestration / Data / Chaos routing *)
    (* c=5: base
       c=6: adds Conductor (handles N)
       c=7: adds Data Mesh Router (handles data_vol)
       c=8: adds Chaos Injector (handles high complexity via fuzzy logic)
       c=9: adds redundant fallback (no new capability, just bloat) *)
    
    let orchestration_drag = if c >= 6 then (float_of_int n_exec /. 100.0) else (float_of_int n_exec /. 5.0) in
    let data_drag = if c >= 7 then (data_vol /. 100.0) else (data_vol /. 10.0) in
    let complexity_drag = if c >= 8 then (complexity /. 10.0) else (complexity /. 1.5) in
    
    let total_drag = orchestration_drag +. data_drag +. complexity_drag in
    
    let net_score = (float_of_int c *. capacity) -. coord_penalty -. total_drag in
    
    if net_score > !best_score then begin
      best_score := net_score;
      best_c := c
    end
  done;
  Printf.printf "Scenario %2d [N=%5d, Data=%6.1f] -> Optimal Core Size: %d (Score: %8.2f)\n" 
    scenario_id n_exec data_vol !best_c !best_score;
  !best_c

let () =
  Random.self_init ();
  print_endline "=== EVOLUTIONARY SWARM SIMULATION V2 (20 SCENARIOS) ===";
  
  let frequencies = Array.make 10 0 in
  
  for i = 1 to 20 do
    let n = Random.int 20000 + 5000 in
    let m = Random.int 200 + 5 in
    let comp = Random.float 100.0 in
    let data = Random.float 50000.0 in
    
    let optimal_c = run_scenario i n m comp data in
    frequencies.(optimal_c) <- frequencies.(optimal_c) + 1
  done;
  
  print_endline "----------------------------------------------------";
  print_endline "WINNING CORE TOPOLOGIES:";
  for i = 5 to 9 do
    if frequencies.(i) > 0 then
      Printf.printf "Core Size %d won %d / 20 scenarios\n" i frequencies.(i)
  done

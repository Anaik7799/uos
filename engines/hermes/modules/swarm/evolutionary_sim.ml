let run_scenario (scenario_id : int) (n_exec : int) (m_exp : int) (complexity : float) (data_vol : float) =
  let best_c = ref 0 in
  let best_score = ref (-999999.0) in
  
  for c = 5 to 12 do
    (* Base capacity *)
    let capacity = 100.0 *. (if c >= 6 then 1.5 else 1.0) in (* Conductor boost *)
    let capacity = capacity *. (if c >= 7 then 1.2 else 1.0) in (* Data/Context Router boost? *)
    let capacity = capacity *. (if c >= 8 then 1.1 else 1.0) in (* Security/Audit boost? *)
    
    (* Coordination penalty: increases non-linearly with C *)
    let coord_penalty = (float_of_int c ** 2.2) *. 1.5 in
    
    (* Bottleneck resolution: As complexity and data volume rise, we need specialized cores. *)
    (* C=6 gives Conductor. C=7 gives Data Mesh Router. C=8 gives Chaos/Entropy injector. *)
    let capability_match = 
      let score = ref 1.0 in
      if complexity > 50.0 && c < 7 then score := !score *. 0.6;
      if data_vol > 5000.0 && c < 7 then score := !score *. 0.5;
      if complexity > 80.0 && c < 8 then score := !score *. 0.8;
      !score
    in
    
    let total_capacity = (float_of_int c *. capacity) -. coord_penalty in
    let elastic_drag = (float_of_int (n_exec + m_exp) *. complexity *. data_vol) /. (1000.0 *. float_of_int c) in
    
    let net_score = (total_capacity *. capability_match) -. elastic_drag in
    
    if net_score > !best_score then begin
      best_score := net_score;
      best_c := c
    end
  done;
  Printf.printf "Scenario %2d [N=%5d, M=%3d, Comp=%5.1f, Data=%6.1f] -> Optimal Core Size: %d (Score: %8.2f)\n" 
    scenario_id n_exec m_exp complexity data_vol !best_c !best_score;
  !best_c

let () =
  Random.self_init ();
  print_endline "=== EVOLUTIONARY SWARM SIMULATION (20 SCENARIOS) ===";
  
  let frequencies = Array.make 15 0 in
  
  for i = 1 to 20 do
    let n = Random.int 20000 + 100 in
    let m = Random.int 200 + 5 in
    let comp = Random.float 100.0 in
    let data = Random.float 10000.0 in
    
    let optimal_c = run_scenario i n m comp data in
    frequencies.(optimal_c) <- frequencies.(optimal_c) + 1
  done;
  
  print_endline "----------------------------------------------------";
  print_endline "WINNING CORE TOPOLOGIES:";
  for i = 5 to 12 do
    if frequencies.(i) > 0 then
      Printf.printf "Core Size %d won %d / 20 scenarios\n" i frequencies.(i)
  done

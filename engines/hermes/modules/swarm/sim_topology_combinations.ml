let evaluate_topology core_size n_executors m_experts =
  (* Base baseline cognitive capacity per core agent *)
  let capacity = 100.0 in
  
  (* Coordination penalty: O(C^2) due to full mesh synchronization in ASSP/CRDT *)
  let coord_penalty = float_of_int (core_size * core_size) *. 0.5 in
  
  (* Capability Coverage Penalty: Under 5 agents, we drop critical safety/memory bounds *)
  let coverage_penalty = 
    if core_size < 3 then 0.50
    else if core_size < 5 then 0.80
    else 1.00
  in

  (* Processing throughput formula *)
  let total_capacity = (float_of_int core_size *. capacity) -. coord_penalty in
  let effective_throughput = total_capacity *. coverage_penalty in
  
  (* Elastic drag: time it takes for Core to manage N+M *)
  let elastic_drag = float_of_int (n_executors + m_experts) *. (float_of_int core_size /. 10.0) in
  
  let net_score = effective_throughput -. elastic_drag in
  Printf.printf "Topology: %d Core Agents (N=%d, M=%d) | Net Efficiency Score: %.2f\n" 
    core_size n_executors m_experts net_score

let () =
  print_endline "--- SWARM TOPOLOGY OPTIMIZATION SIMULATION ---";
  let scenarios = [3; 4; 5; 6; 7; 8; 9] in
  let n = 1000 in
  let m = 50 in
  List.iter (fun c -> evaluate_topology c n m) scenarios;
  print_endline "----------------------------------------------"

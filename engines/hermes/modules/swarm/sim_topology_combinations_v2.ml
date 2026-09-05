let evaluate_topology core_size n_executors m_experts =
  (* Base baseline cognitive capacity per core agent *)
  let capacity = 100.0 in
  
  (* Coordination penalty: O(C^2) *)
  let coord_penalty = float_of_int (core_size * core_size) *. 0.5 in
  
  (* Capability Coverage Penalty *)
  let coverage_penalty = 
    if core_size < 5 then 0.50 (* Missing core cognition *)
    else 1.00
  in

  (* Bottleneck: If core_size < 6, the Synthesizer is overloaded doing BOTH DAG planning AND elastic orchestration of N fibers.
     If core_size >= 6, we have a dedicated Conductor, removing the elastic drag bottleneck. *)
  let orchestration_efficiency = 
    if core_size < 6 then 0.4 (* Synthesizer is bottlenecked by N *)
    else 1.0 (* Conductor cleanly handles N *)
  in

  (* Processing throughput formula *)
  let total_capacity = (float_of_int core_size *. capacity) -. coord_penalty in
  
  (* Elastic drag on the core council *)
  let elastic_drag = float_of_int (n_executors + m_experts) /. (if core_size >= 6 then 50.0 else 10.0) in
  
  let net_score = (total_capacity *. coverage_penalty *. orchestration_efficiency) -. elastic_drag in
  Printf.printf "Topology: %d Core Agents | Net Score: %.2f\n" core_size net_score

let () =
  print_endline "--- SWARM TOPOLOGY OPTIMIZATION SIMULATION V2 ---";
  let scenarios = [4; 5; 6; 7; 8] in
  let n = 1000 in
  let m = 50 in
  List.iter (fun c -> evaluate_topology c n m) scenarios;
  print_endline "-------------------------------------------------"

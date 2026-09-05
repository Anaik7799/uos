let () =
  match Array.to_list Sys.argv |> List.tl
        |> Run_swarm_bridge_programme.parse_cli_arguments with
  | Error diagnostic ->
      prerr_endline ("run_swarm_bridge_plan_bridge: " ^ diagnostic);
      exit 2
  | Ok path ->
      (match Run_swarm_bridge_programme.preflight_state_path path with
       | Error diagnostic -> prerr_endline diagnostic; exit 2
       | Ok () -> ());
      let now_ns = Int64.of_float (Unix.gettimeofday () *. 1_000_000_000.) in
      (match Run_swarm_bridge_programme.materialize ~now_ns with
       | Error diagnostic ->
           prerr_endline diagnostic;
           exit 1
       | Ok receipt ->
           `Assoc
             [ "schema", `String "hermes.run-swarm-bridge-programme/v1";
               "timestamp", `String Run_swarm_bridge_programme.timestamp;
               "plan_id", `String Run_swarm_bridge_programme.plan_id;
               "lifecycle_projection_id",
                 `String Run_swarm_bridge_programme.lifecycle_projection_id;
               "recovery_projection_id",
                 `String Run_swarm_bridge_programme.recovery_projection_id;
               "registered_nodes", `Int receipt.registered_nodes;
               "lifecycle_projection_running",
                 `Bool receipt.lifecycle_projection_running;
               "recovery_projection_jobs",
                 `Int receipt.recovery_projection_jobs ]
           |> Yojson.Safe.pretty_to_channel stdout;
           output_char stdout '\n')

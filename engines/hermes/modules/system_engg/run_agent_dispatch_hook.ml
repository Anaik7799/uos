(* run_agent_dispatch_hook.ml — Executable entrypoint for DMC & TCM MCP Dispatch Interceptor *)

let () =
  match Agent_dispatch_hook.parse_arguments (List.tl (Array.to_list Sys.argv)) with
  | Ok Agent_dispatch_hook.Self_test -> exit (Agent_dispatch_hook.run_self_test ())
  | Error refusal ->
    print_endline (Agent_dispatch_hook.render_verdict refusal); exit 2
  | Ok (Agent_dispatch_hook.Intercept { require_authority }) ->
    let verdict = match Agent_dispatch_hook.read_payload Unix.stdin with
      | Error refusal -> refusal
      | Ok payload -> Agent_dispatch_hook.validate_tool_payload
          ~require_authority payload in
    print_endline (Agent_dispatch_hook.render_verdict verdict);
    match verdict with
    | Agent_dispatch_hook.Pass _ -> exit 0
    | Agent_dispatch_hook.FailClosed _ -> exit 2

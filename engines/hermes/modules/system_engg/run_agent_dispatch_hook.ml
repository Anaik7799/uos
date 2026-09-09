(* run_agent_dispatch_hook.ml — Executable entrypoint for DMC & TCM MCP Dispatch Interceptor *)

let () =
  let args = Array.to_list Sys.argv in
  if List.mem "--self-test" args then
    exit (Agent_dispatch_hook.run_self_test ())
  else if List.mem "--intercept-mcp" args then begin
    let verdict = match Agent_dispatch_hook.read_payload Unix.stdin with
      | Error refusal -> refusal
      | Ok payload -> Agent_dispatch_hook.validate_tool_payload
          ~require_authority:(List.mem "--enforce-dmc-tcm" args) payload in
    print_endline (Agent_dispatch_hook.render_verdict verdict);
    match verdict with
    | Agent_dispatch_hook.Pass _ -> exit 0
    | Agent_dispatch_hook.FailClosed _ -> exit 2
  end else begin
    print_endline "Usage: run_agent_dispatch_hook.exe [--self-test | --intercept-mcp --enforce-dmc-tcm]";
    exit 1
  end

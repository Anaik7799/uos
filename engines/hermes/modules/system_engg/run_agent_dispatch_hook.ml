(* run_agent_dispatch_hook.ml — Executable entrypoint for DMC & TCM MCP Dispatch Interceptor *)

let () =
  let args = Array.to_list Sys.argv in
  if List.mem "--self-test" args then
    exit (Agent_dispatch_hook.run_self_test ())
  else if List.mem "--intercept-mcp" args then begin
    (* Read incoming payload from stdin *)
    let buffer = Buffer.create 1024 in
    (try
      while true do
        let line = input_line stdin in
        Buffer.add_string buffer line;
        Buffer.add_char buffer '\n'
      done
    with End_of_file -> ());
    let payload = Buffer.contents buffer in
    let verdict = Agent_dispatch_hook.validate_tool_payload payload in
    print_endline (Agent_dispatch_hook.render_verdict verdict);
    match verdict with
    | Agent_dispatch_hook.Pass _ -> exit 0
    | Agent_dispatch_hook.FailClosed _ -> exit 2
  end else begin
    print_endline "Usage: run_agent_dispatch_hook.exe [--self-test | --intercept-mcp --enforce-dmc-tcm]";
    exit 1
  end

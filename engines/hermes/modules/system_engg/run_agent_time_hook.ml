let oracle = "/home/an/.claude/hooks/claude-time-sync.sh"

let () =
  Agent_time_hook.invoke ~program:oracle ~argv:[| oracle; "session" |]
  |> Agent_time_hook.render_pre_invocation |> print_endline

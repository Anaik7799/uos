let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else (
    incr failed;
    Printf.printf "FAILED: %s\n" name)

let injected_message rendered =
  let open Yojson.Safe.Util in
  rendered |> Yojson.Safe.from_string |> member "injectSteps" |> to_list
  |> List.hd |> member "ephemeralMessage" |> to_string

let () =
  check "success is a valid Agy PreInvocation response" (
      injected_message (Agent_time_hook.render_pre_invocation (Ok "clock receipt"))
      = "clock receipt");
  check "JSON escaping preserves the oracle message exactly" (
      let message = "authoritative \"clock\"\nsecond line" in
      injected_message (Agent_time_hook.render_pre_invocation (Ok message)) = message);
  check "oracle failure remains explicit and machine-readable" (
      let message =
        injected_message
          (Agent_time_hook.render_pre_invocation (Error "oracle exited 7"))
      in
      String.starts_with ~prefix:"Unavailable_observed:" message
      && String.ends_with ~suffix:"oracle exited 7" message);
  check "process invocation captures exact stdout" (
      Agent_time_hook.invoke ~program:"/bin/printf"
        ~argv:[| "/bin/printf"; "host receipt" |]
      = Ok "host receipt");
  check "process invocation reports a non-zero exit" (
      match
        Agent_time_hook.invoke ~program:"/bin/sh"
          ~argv:[| "/bin/sh"; "-c"; "exit 7" |]
      with
      | Error reason -> String.ends_with ~suffix:"exit 7" reason
      | Ok _ -> false);
  Printf.printf "agent_time_hook: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_agent_time_hook" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.agent_time_hook ]);
  exit (Suite_telemetry.exit_code self)

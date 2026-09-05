let passed = ref 0
let failed = ref 0

let check name condition =
  if condition then incr passed
  else begin
    incr failed;
    Printf.printf "FAILED: %s\n" name
  end

let get = function
  | Ok value -> value
  | Error errors -> failwith (String.concat "; " errors)

let contains_change predicate changes = List.exists predicate changes

let make_temp_directory () =
  let path = Filename.temp_file "hermes-zellij-" ".dir" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let () =
  let intent = get (Zellij_intent.default ()) in
  let successful =
    Zellij_observe.
      {
        status = Unix.WEXITED 0;
        stdout = "zlt-1\nzlt-2\nzlt-3\nzlt-4\nzlt-5\nzlt-6\n";
        stderr = "";
      }
  in
  check "L1 exact short session output parses as the closed carrier"
    (match Zellij_observe.parse_sessions successful with
    | Zellij_observe.Known sessions -> sessions = Zellij_intent.all_sessions
    | Zellij_observe.Unknown _ -> false);
  check "L2 malformed and nonzero session observations fail closed"
    (match
       ( Zellij_observe.parse_sessions
           { successful with stdout = "zlt-1\nother\n" },
         Zellij_observe.parse_sessions
           { successful with status = Unix.WEXITED 2 } )
     with
    | Zellij_observe.Unknown _, Zellij_observe.Unknown _ -> true
    | _ -> false);
  check "L2b Zellij's explicit no-active-sessions exit is a known empty set"
    (match
       Zellij_observe.parse_sessions
         {
           status = Unix.WEXITED 1;
           stdout = "";
           stderr = "No active zellij sessions found.\n";
         }
     with
    | Zellij_observe.Known [] -> true
    | _ -> false);
  let missing =
    Zellij_observe.make ~version:(Known "zellij 0.43.1")
      ~sessions:(Known [ Zellij_intent.Zlt_1 ]) ~config_digest:(Known None)
      ~launcher_present:(Known false)
      ~command_links:
        (List.map
           (fun session -> (session, Zellij_observe.Missing))
           Zellij_intent.all_sessions)
      ~tmux_sessions:(Known "tmux-a\n") ~nested_session:(Known false)
  in
  let changes = get (Zellij_configurator.plan intent missing) in
  check "L3 partial state plans config, launcher, six links, and five sessions"
    (contains_change
       (function Zellij_configurator.Write_config -> true | _ -> false)
       changes
    && contains_change
         (function Zellij_configurator.Install_launcher -> true | _ -> false)
         changes
    && List.length
         (List.filter
            (function Zellij_configurator.Link_command _ -> true | _ -> false)
            changes)
       = 6
    && List.length
         (List.filter
            (function
              | Zellij_configurator.Ensure_session _ -> true | _ -> false)
            changes)
       = 5);
  let unknown =
    Zellij_observe.make ~version:(Unknown "probe failed")
      ~sessions:(Unknown "list failed") ~config_digest:(Known None)
      ~launcher_present:(Known false) ~command_links:[]
      ~tmux_sessions:(Unknown "tmux unavailable") ~nested_session:(Known false)
  in
  check "L4 unknown observations refuse planning instead of becoming success"
    (Result.is_error (Zellij_configurator.plan intent unknown));
  let tmux_unknown =
    Zellij_observe.make ~version:(Known "zellij 0.44.3")
      ~sessions:(Known Zellij_intent.all_sessions)
      ~config_digest:
        (Known
           (Some
              (Zellij_projection.render_config_kdl intent
              |> Zellij_projection.digest)))
      ~launcher_present:(Known true)
      ~command_links:
        (List.map
           (fun session -> (session, Zellij_observe.Correct))
           Zellij_intent.all_sessions)
      ~tmux_sessions:(Unknown "permission denied") ~nested_session:(Known false)
  in
  check "L4b unknown tmux baseline blocks non-interference planning"
    (Result.is_error (Zellij_configurator.plan intent tmux_unknown));
  check "L5 launcher basename maps only exact declared session commands"
    (Zellij_configurator.launcher_session "/home/an/.local/bin/zlt-6"
     = Ok Zellij_intent.Zlt_6
    && Result.is_error
         (Zellij_configurator.launcher_session "/home/an/.local/bin/z1")
    && Result.is_error
         (Zellij_configurator.launcher_session
            "/home/an/.local/bin/zellij-attach-harness-bionic"));
  check "L6 CLI grammar is closed"
    (Zellij_configurator.command_of_argv [| "zellij-harness"; "plan" |]
     = Ok Zellij_configurator.Plan
    && Result.is_error
         (Zellij_configurator.command_of_argv [| "zellij-harness"; "unknown" |])
    && Result.is_error
         (Zellij_configurator.command_of_argv
            [| "zellij-harness"; "plan"; "extra" |]));
  let directory = make_temp_directory () in
  let target = Filename.concat directory "config.kdl" in
  let channel = open_out_bin target in
  output_string channel "prior";
  close_out channel;
  let result =
    Zellij_configurator.write_atomic_with
      ~emit:(fun output _content ->
        output_string output "partial";
        Error "injected interruption")
      target "replacement"
  in
  let observed = In_channel.with_open_bin target In_channel.input_all in
  check "L7 interrupted atomic write preserves prior destination bytes"
    (Result.is_error result && observed = "prior");
  let checks =
    Zellij_configurator.preflight_resources intent
    |> List.map (fun resource ->
        Resource_envelope.evaluate resource (Resource_envelope.Unknown "chaos"))
  in
  check "L8 unknown resource facts block every declared preflight check"
    (checks <> [] && not (Resource_envelope.satisfied checks));
  let telemetry =
    Suite_telemetry.observe ~suite:"test_zellij_live" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit telemetry ~targets:[]);
  exit (Suite_telemetry.exit_code telemetry)

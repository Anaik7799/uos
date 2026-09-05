let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let get = function Ok value -> value | Error message -> failwith message

let () =
  let calls = ref [] in
  let execute (request : Ops_command.request) =
    calls := Ops_command.action_name request.action :: !calls;
    Ok ("executed:" ^ Ops_command.action_name request.action ^ ":" ^
        Ops_command.scope_name request.scope)
  in
  let request =
    { Ops_command.request_id = "req-1"; action = Ops_command.Check;
      scope = Ops_command.Whole_system }
  in
  let api = Ops_command.dispatch ~execute ~surface:Ops_command.Ocaml_api request in
  let cli =
    Ops_command.dispatch_cli ~execute
      [ "completion"; "check"; "--scope"; "whole-system";
        "--request-id"; "req-1" ] |> get
  in
  let mcp =
    Ops_command.dispatch_mcp ~execute
      (`Assoc [ ("request_id", `String "req-1"); ("action", `String "check");
                ("scope", `String "whole-system") ]) |> get
  in
  let zenoh =
    Ops_command.dispatch_zenoh ~execute
      ~key:"hermes/control/completion/check"
      ~payload:"{\"request_id\":\"req-1\",\"scope\":\"whole-system\"}" () |> get
  in
  let normalized observation = Ops_command.receipt_json observation.Ops_command.receipt in
  check "S1 API, CLI, MCP, and Zenoh normalize to one receipt" (fun () ->
      normalized api = normalized cli && normalized cli = normalized mcp
      && normalized mcp = normalized zenoh);
  check "S2 each native adapter invokes the one executor exactly once" (fun () ->
      List.length !calls = 4 && List.for_all (( = ) "check") !calls);
  check "S3 observations retain their transport without contaminating receipt identity" (fun () ->
      api.surface = Ops_command.Ocaml_api && cli.surface = Ops_command.Cli
      && mcp.surface = Ops_command.Mcp && zenoh.surface = Ops_command.Zenoh);
  check "S4 normalized receipts carry a SHA-256 identity" (fun () ->
      String.length api.receipt.digest = 64
      && api.receipt.digest = cli.receipt.digest
      && api.receipt.digest = mcp.receipt.digest
      && api.receipt.digest = zenoh.receipt.digest);
  check "S5 control and data plane commands share the Zenoh ingress algebra" (fun () ->
      let data =
        Ops_command.dispatch_zenoh ~execute
          ~key:"hermes/data/completion/metrics-observe"
          ~payload:"{\"request_id\":\"req-2\",\"scope\":\"data-plane\"}" () |> get
      in
      data.receipt.action = "metrics-observe" && data.receipt.scope = "data-plane");
  check "S6 malformed or unknown native requests fail closed" (fun () ->
      Result.is_error (Ops_command.dispatch_cli ~execute [ "completion"; "destroy" ])
      && Result.is_error (Ops_command.dispatch_mcp ~execute (`Assoc []))
      && Result.is_error
           (Ops_command.dispatch_zenoh ~execute ~key:"hermes/control/wrong/check"
              ~payload:"{}" ()));
  check "S7 model, formal, and observability actions are first-class" (fun () ->
      List.for_all
        (fun name -> List.mem name Ops_command.supported_actions)
        [ "mbse-check"; "fpp-check"; "formal-check"; "metrics-observe";
          "history-observe"; "orientation-observe"; "debug"; "decide"; "act" ]);
  check "S8 MCP schema names the same supported action enum" (fun () ->
      let text = Yojson.Safe.to_string Ops_command.mcp_tool_schema in
      List.for_all (fun name -> String.contains text name.[0]
        && let n = String.length name in n > 0
        && let rec contains_at i =
             i + n <= String.length text
             && (String.sub text i n = name || contains_at (i + 1))
           in contains_at 0)
        Ops_command.supported_actions);
  check "S9a every Fast OODA action parses on CLI, MCP, and Zenoh" (fun () ->
      List.for_all
        (fun action ->
          Result.is_ok
            (Ops_command.dispatch_cli ~execute
               [ "completion"; action; "--scope"; "whole-system";
                 "--request-id"; "ooda-" ^ action ])
          && Result.is_ok
               (Ops_command.dispatch_mcp ~execute
                  (`Assoc [ ("request_id", `String ("ooda-" ^ action));
                            ("action", `String action);
                            ("scope", `String "whole-system") ]))
          && Result.is_ok
               (Ops_command.dispatch_zenoh ~execute
                  ~key:("hermes/control/completion/" ^ action)
                  ~payload:(Printf.sprintf
                    "{\"request_id\":\"ooda-%s\",\"scope\":\"whole-system\"}" action)
                  ()))
        [ "inventory"; "plan"; "decide"; "act"; "check" ]);
  check "S9 generic declarative invocation is equivalent on CLI MCP and Zenoh" (fun () ->
      let cli =
        Ops_command.dispatch_cli ~execute
          [ "completion"; "invoke"; "capability.metrics-observe";
            "--scope"; "data-plane"; "--request-id"; "invoke-1" ] |> get
      in
      let mcp =
        Ops_command.dispatch_mcp ~execute
          (`Assoc [ ("request_id", `String "invoke-1"); ("action", `String "invoke");
                    ("target", `String "capability.metrics-observe");
                    ("scope", `String "data-plane") ]) |> get
      in
      let zenoh =
        Ops_command.dispatch_zenoh ~execute ~key:"hermes/data/completion/invoke"
          ~payload:"{\"request_id\":\"invoke-1\",\"scope\":\"data-plane\",\"target\":\"capability.metrics-observe\"}" () |> get
      in
      normalized cli = normalized mcp && normalized mcp = normalized zenoh);
  check "S10 declarative debugging intent is equivalent on CLI MCP and Zenoh" (fun () ->
      let cli =
        Ops_command.dispatch_cli ~execute
          [ "completion"; "debug"; "debug.formal-coverage-gap";
            "--scope"; "control-plane"; "--request-id"; "debug-1" ] |> get
      in
      let mcp =
        Ops_command.dispatch_mcp ~execute
          (`Assoc [ ("request_id", `String "debug-1"); ("action", `String "debug");
                    ("target", `String "debug.formal-coverage-gap");
                    ("scope", `String "control-plane") ]) |> get
      in
      let zenoh =
        Ops_command.dispatch_zenoh ~execute ~key:"hermes/control/completion/debug"
          ~payload:"{\"request_id\":\"debug-1\",\"scope\":\"control-plane\",\"target\":\"debug.formal-coverage-gap\"}" () |> get
      in
      normalized cli = normalized mcp && normalized mcp = normalized zenoh
      && Result.is_error
           (Ops_command.dispatch_cli ~execute
              [ "completion"; "debug"; "--scope"; "control-plane";
                "--request-id"; "debug-missing" ]));

  Printf.printf "ops_command: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_command" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)

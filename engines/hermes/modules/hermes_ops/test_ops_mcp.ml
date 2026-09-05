let passed = ref 0
let failed = ref 0

let check name f =
  match f () with
  | true -> incr passed
  | false -> incr failed; Printf.printf "FAILED: %s\n" name
  | exception exn ->
      incr failed;
      Printf.printf "FAILED: %s (raised %s)\n" name (Printexc.to_string exn)

let result = function Ok (Some json) -> json | Ok None -> failwith "no response" | Error e -> failwith e
let member key json = Yojson.Safe.Util.member key json

let execute (request : Ops_command.request) =
  Ok ("mcp:" ^ Ops_command.action_name request.action ^ ":" ^ Ops_command.scope_name request.scope)

let call id method_ params =
  `Assoc [ ("jsonrpc", `String "2.0"); ("id", `Int id);
           ("method", `String method_); ("params", params) ]

let () =
  check "M1 initialize advertises tools without inventing capabilities" (fun () ->
      let response =
        Ops_mcp.handle ~execute
          (call 1 "initialize"
             (`Assoc [ ("protocolVersion", `String "2024-11-05") ])) |> result
      in
      member "jsonrpc" response = `String "2.0"
      && member "id" response = `Int 1
      && member "protocolVersion" (member "result" response) = `String "2024-11-05"
      && member "tools" (member "capabilities" (member "result" response)) <> `Null);
  check "M2 tools/list projects the canonical command schema" (fun () ->
      let response = Ops_mcp.handle ~execute (call 2 "tools/list" (`Assoc [])) |> result in
      match member "tools" (member "result" response) with
      | `List [ tool ] -> member "name" tool = `String "hermes_completion"
      | _ -> false);
  check "M3 tools/call uses the one MCP adapter and normalized receipt" (fun () ->
      let arguments =
        `Assoc [ ("request_id", `String "mcp-1"); ("action", `String "check");
                 ("scope", `String "whole-system") ]
      in
      let response =
        Ops_mcp.handle ~execute
          (call 3 "tools/call"
             (`Assoc [ ("name", `String "hermes_completion");
                       ("arguments", arguments) ])) |> result
      in
      let direct = Ops_command.dispatch_mcp ~execute arguments in
      match member "content" (member "result" response), direct with
      | `List [ `Assoc fields ], Ok observation ->
          List.assoc_opt "text" fields = Some (`String (Ops_command.receipt_json observation.receipt))
          && member "isError" (member "result" response) = `Bool false
      | _ -> false);
  check "M4 blocked commands are protocol success with isError true and full receipt" (fun () ->
      let blocked _ = Error "current evidence is incomplete" in
      let arguments =
        `Assoc [ ("request_id", `String "mcp-2"); ("action", `String "check");
                 ("scope", `String "whole-system") ]
      in
      let response =
        Ops_mcp.handle ~execute:blocked
          (call 4 "tools/call"
             (`Assoc [ ("name", `String "hermes_completion");
                       ("arguments", arguments) ])) |> result
      in
      member "isError" (member "result" response) = `Bool true);
  check "M5 unknown method and tool fail closed as JSON-RPC errors" (fun () ->
      let method_error = Ops_mcp.handle ~execute (call 5 "destroy" (`Assoc [])) |> result in
      let tool_error =
        Ops_mcp.handle ~execute
          (call 6 "tools/call"
             (`Assoc [ ("name", `String "wrong"); ("arguments", `Assoc []) ])) |> result
      in
      member "code" (member "error" method_error) = `Int (-32601)
      && member "code" (member "error" tool_error) = `Int (-32602));
  check "M6 initialized notification has no response" (fun () ->
      Ops_mcp.handle ~execute
        (`Assoc [ ("jsonrpc", `String "2.0");
                  ("method", `String "notifications/initialized") ])
      = Ok None);

  Printf.printf "ops_mcp: %d passed, %d failed\n" !passed !failed;
  let self =
    Suite_telemetry.observe ~suite:"test_ops_mcp" ~passed:!passed
      ~failed:!failed ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_ops_capability; Stanza.hermes_ops_governance; Stanza.hermes_ops_topology; Stanza.hermes_ops_completion_topology; Stanza.hermes_ops ]);
  exit (Suite_telemetry.exit_code self)

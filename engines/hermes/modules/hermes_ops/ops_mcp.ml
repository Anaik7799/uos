let member key = function `Assoc fields -> List.assoc_opt key fields | _ -> None

let response id result =
  `Assoc [ ("jsonrpc", `String "2.0"); ("id", id); ("result", result) ]

let error id code message =
  `Assoc
    [ ("jsonrpc", `String "2.0"); ("id", id);
      ("error", `Assoc [ ("code", `Int code); ("message", `String message) ]) ]

let request_id json = Option.value ~default:`Null (member "id" json)

let handle ?dispatcher ~execute json =
  if member "jsonrpc" json <> Some (`String "2.0") then
    Ok (Some (error (request_id json) (-32600) "invalid JSON-RPC request"))
  else
    match member "method" json with
    | Some (`String "notifications/initialized") -> Ok None
    | Some (`String "initialize") ->
        let protocol =
          match member "params" json with
          | Some params ->
              begin match member "protocolVersion" params with
              | Some (`String value) -> value | _ -> "2024-11-05"
              end
          | None -> "2024-11-05"
        in
        Ok
          (Some
             (response (request_id json)
                (`Assoc
                  [ ("protocolVersion", `String protocol);
                    ("capabilities", `Assoc [ ("tools", `Assoc []) ]);
                    ("serverInfo",
                     `Assoc [ ("name", `String "hermes-ops");
                              ("version", `String "1") ]) ])))
    | Some (`String "tools/list") ->
        Ok
          (Some
             (response (request_id json)
                (`Assoc [ ("tools", `List [ Ops_command.mcp_tool_schema ]) ])))
    | Some (`String "tools/call") ->
        let id = request_id json in
        begin match member "params" json with
        | Some params ->
            begin match member "name" params, member "arguments" params with
            | Some (`String "hermes_completion"), Some arguments ->
                begin match Ops_command.dispatch_mcp ?dispatcher ~execute arguments with
                | Error message -> Ok (Some (error id (-32602) message))
                | Ok observation ->
                    let is_error = observation.receipt.verdict = Ops_command.Blocked in
                    Ok
                      (Some
                         (response id
                            (`Assoc
                              [ ("content",
                                 `List
                                   [ `Assoc
                                       [ ("type", `String "text");
                                         ("text", `String (Ops_command.receipt_json observation.receipt)) ] ]);
                                ("isError", `Bool is_error) ])))
                end
            | Some (`String name), _ ->
                Ok (Some (error id (-32602) ("unknown tool: " ^ name)))
            | _ -> Ok (Some (error id (-32602) "tools/call requires name and arguments"))
            end
        | None -> Ok (Some (error id (-32602) "tools/call requires params"))
        end
    | Some (`String method_) ->
        Ok (Some (error (request_id json) (-32601) ("method not found: " ^ method_)))
    | _ -> Ok (Some (error (request_id json) (-32600) "missing method"))

let serve ?dispatcher ~execute () =
  let rec loop () =
    match input_line stdin with
    | line ->
        let response_value =
          match Yojson.Safe.from_string line with
          | exception Yojson.Json_error message ->
              Some (error `Null (-32700) ("parse error: " ^ message))
          | json ->
              begin match handle ?dispatcher ~execute json with
              | Ok response -> response
              | Error message -> Some (error (request_id json) (-32603) message)
              end
        in
        Option.iter
          (fun json -> Yojson.Safe.to_channel stdout json; output_char stdout '\n'; flush stdout)
          response_value;
        loop ()
    | exception End_of_file -> ()
  in
  loop ()

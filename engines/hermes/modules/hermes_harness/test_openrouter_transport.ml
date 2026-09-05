let request ?(api_key = Some "secret") () =
  Openrouter_contract.{ endpoint = "https://openrouter.ai/api/v1/chat/completions"; api_key;
    body = `Assoc [ ("model", `String "openai/gpt-5.4"); ("messages", `List []) ] }

let () =
  let open Openrouter_transport in
  let executor ~endpoint:_ ~api_key:_ ~body:_ =
    Ok (200, "{\"id\":\"chat-1\",\"choices\":[{\"finish_reason\":\"tool_calls\",\"message\":{\"content\":\"hello\",\"tool_calls\":[{\"id\":\"call-1\",\"function\":{\"name\":\"read\",\"arguments\":\"{}\"}}]}}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":5}}")
  in
  match submit ~execute:executor (request ()) with
  | Error _ -> failwith "expected normalized response"
  | Ok response ->
      assert (response.id = Some "chat-1");
      assert (response.content = Some "hello");
      assert (response.finish_reason = "tool_calls");
      assert (response.usage = Some { prompt_tokens = Some 3; completion_tokens = Some 5; total_tokens = None });
      assert (response.tool_calls = [ { id = "call-1"; name = "read"; arguments = "{}" } ]);
  assert (submit ~execute:executor (request ~api_key:None ()) = Error Missing_credentials);
  assert (submit ~execute:(fun ~endpoint:_ ~api_key:_ ~body:_ -> Ok (401, "unauthorized")) (request ()) = Error (Http_error 401));
  assert (submit ~execute:(fun ~endpoint:_ ~api_key:_ ~body:_ -> Ok (200, "not-json")) (request ()) = Error Malformed_response);
  assert (submit ~execute:(fun ~endpoint:_ ~api_key:_ ~body:_ -> Error "offline") (request ()) = Error (Transport_error "offline"))

(* Refusal promotion, faithful to chat_completions.normalize_response: when a
   non-empty refusal is the SOLE payload -- no visible text, no tool calls --
   adopt it as content and, if the finish reason is "stop", mark it
   content_filter. A refusal alongside real content or tool calls is a normal,
   usable turn and is NOT promoted. *)
let () =
  let open Openrouter_transport in
  let decode_str s = decode (Yojson.Safe.from_string s) in
  (match decode_str {|{"choices":[{"message":{"content":null,"refusal":"I cannot help with that"},"finish_reason":"stop"}]}|} with
   | Some r ->
       assert (r.content = Some "I cannot help with that");
       assert (r.finish_reason = "content_filter");
       assert (r.tool_calls = [])
   | None -> failwith "refusal (sole payload): expected a decoded response");
  (match decode_str {|{"choices":[{"message":{"content":"here you go","refusal":"minor note"},"finish_reason":"stop"}]}|} with
   | Some r ->
       assert (r.content = Some "here you go");
       assert (r.finish_reason = "stop")
   | None -> failwith "refusal+content: expected a decoded response");
  (match decode_str {|{"choices":[{"message":{"content":null,"refusal":"no","tool_calls":[{"id":"c1","function":{"name":"f","arguments":"{}"}}]},"finish_reason":"tool_calls"}]}|} with
   | Some r ->
       assert (r.content = None);
       assert (r.finish_reason = "tool_calls");
       assert (r.tool_calls = [ { id = "c1"; name = "f"; arguments = "{}" } ])
   | None -> failwith "refusal+tools: expected a decoded response");
  (* total_tokens is a pass-through of the provider figure (frozen source reads
     getattr(u, "total_tokens", 0)), not a computed sum. *)
  (match decode_str {|{"choices":[{"message":{"content":"hi"},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}|} with
   | Some r ->
       assert (r.usage = Some { prompt_tokens = Some 10; completion_tokens = Some 5; total_tokens = Some 15 })
   | None -> failwith "usage total_tokens: expected a decoded response")

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_openrouter_transport" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_openrouter_transport ]);
  exit (Suite_telemetry.exit_code self)

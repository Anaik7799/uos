let member name = function
  | `Assoc fields -> List.assoc_opt name fields
  | _ -> None

let expect_string name = function
  | Some (`String value) -> value
  | _ -> failwith ("missing string field: " ^ name)

let () =
  let open Openrouter_contract in
  let credentials =
    { supplied_key = None; openrouter_key = Some "openrouter-key"; openai_key = Some "openai-key";
      base_url_override = None }
  in
  let resolved = resolve_credentials credentials in
  assert (resolved.base_url = default_base_url);
  assert (resolved.api_key = Some "openrouter-key");
  let custom =
    resolve_credentials { credentials with base_url_override = Some "https://gateway.example/v1" }
  in
  assert (custom.api_key = Some "openai-key");
  assert (parse_reasoning "none" = Disabled);
  assert (parse_reasoning "ultra" = Effort "ultra");
  assert (parse_reasoning "not-a-level" = Unspecified);
  let request =
    build ~credentials ~model_id:"openai/gpt-5.4" ~messages:[ `Assoc [ ("role", `String "user"); ("content", `String "hello") ] ]
      ~reasoning:Unspecified ~supports_reasoning:true ~session_id:(Some "session-123")
      ~provider_preferences:(Some (`Assoc [ ("order", `List [ `String "a" ]) ]))
      ~pareto_min_coding_score:None ()  in
  assert (expect_string "model" (member "model" request.body) = "openai/gpt-5.4");
  let extra = match member "extra_body" request.body with Some value -> value | None -> failwith "missing extra body" in
  assert (expect_string "session_id" (member "session_id" extra) = "session-123");
  assert (member "provider" extra = Some (`Assoc [ ("order", `List [ `String "a" ]) ]));
  assert (member "reasoning" extra = Some (`Assoc [ ("enabled", `Bool true); ("effort", `String "medium") ]));
  let disabled =
    build ~credentials ~model_id:"anthropic/claude-sonnet-4.5" ~messages:[] ~reasoning:Disabled
      ~supports_reasoning:true ~session_id:None ~provider_preferences:None ~pareto_min_coding_score:None ()  in
  let disabled_extra = match member "extra_body" disabled.body with Some value -> value | None -> failwith "missing disabled extra" in
  assert (member "reasoning" disabled_extra = Some (`Assoc [ ("enabled", `Bool false) ]));
  let mandatory =
    build ~credentials ~model_id:"anthropic/claude-sonnet-4.6" ~messages:[] ~reasoning:(Effort "high")
      ~supports_reasoning:true ~session_id:None ~provider_preferences:None ~pareto_min_coding_score:None ()  in
  assert (member "reasoning" mandatory.body = None);
  assert (member "verbosity" mandatory.body = Some (`String "high"));
  let pareto =
    build ~credentials ~model_id:"openrouter/pareto-code" ~messages:[] ~reasoning:Unspecified
      ~supports_reasoning:false ~session_id:None ~provider_preferences:None ~pareto_min_coding_score:(Some 0.8) ()  in
  let pareto_extra = match member "extra_body" pareto.body with Some value -> value | None -> failwith "missing pareto extra" in
  assert (member "plugins" pareto_extra = Some (`List [ `Assoc [ ("id", `String "pareto-router"); ("min_coding_score", `Float 0.8) ] ]));
  let invalid_pareto =
    build ~credentials ~model_id:"openrouter/pareto-code" ~messages:[] ~reasoning:Unspecified
      ~supports_reasoning:false ~session_id:None ~provider_preferences:None ~pareto_min_coding_score:(Some 1.2) ()  in
  assert (member "extra_body" invalid_pareto.body = None);

  (* Developer-role swap, faithful to DEVELOPER_ROLE_MODELS = (gpt-5, codex).
     A leading system message becomes developer for a gpt-5 model. *)
  let sys_messages =
    [ `Assoc [ ("role", `String "system"); ("content", `String "be terse") ];
      `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ]
  in
  let swapped =
    build ~credentials ~model_id:"openai/gpt-5.4" ~messages:sys_messages ~reasoning:Unspecified
      ~supports_reasoning:false ~session_id:None ~provider_preferences:None
      ~pareto_min_coding_score:None ()
  in
  let first_role m =
    match member "messages" m with
    | Some (`List (`Assoc fields :: _)) -> (
        match List.assoc_opt "role" fields with Some (`String r) -> r | _ -> "?")
    | _ -> "?"
  in
  assert (first_role swapped.body = "developer");
  (* Only the first message is swapped; the user message keeps its role. *)
  (match member "messages" swapped.body with
  | Some (`List [ _; `Assoc second ]) ->
      assert (List.assoc_opt "role" second = Some (`String "user"))
  | _ -> failwith "expected two messages");
  (* No swap for a non-gpt-5/codex model. *)
  let unswapped =
    build ~credentials ~model_id:"anthropic/claude-sonnet-4.5" ~messages:sys_messages
      ~reasoning:Unspecified ~supports_reasoning:false ~session_id:None
      ~provider_preferences:None ~pareto_min_coding_score:None ()
  in
  assert (first_role unswapped.body = "system");
  (* No swap when the first message is not a system message, even for gpt-5. *)
  let user_first =
    build ~credentials ~model_id:"openai/gpt-5.4"
      ~messages:[ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ]
      ~reasoning:Unspecified ~supports_reasoning:false ~session_id:None
      ~provider_preferences:None ~pareto_min_coding_score:None ()
  in
  assert (first_role user_first.body = "user");
  (* codex is also a developer-role model. *)
  let codex =
    build ~credentials ~model_id:"openai/codex-mini" ~messages:sys_messages
      ~reasoning:Unspecified ~supports_reasoning:false ~session_id:None
      ~provider_preferences:None ~pareto_min_coding_score:None ()
  in
  assert (first_role codex.body = "developer");

  (* Tools appear in the body when passed, and are absent when not. *)
  let tool =
    `Assoc [ ("type", `String "function");
             ("function", `Assoc [ ("name", `String "lookup") ]) ]
  in
  let with_tools =
    build ~credentials ~model_id:"openai/gpt-5.4"
      ~messages:[ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ]
      ~tools:[ tool ] ~reasoning:Unspecified ~supports_reasoning:false ~session_id:None
      ~provider_preferences:None ~pareto_min_coding_score:None ()
  in
  assert (member "tools" with_tools.body = Some (`List [ tool ]));
  let without_tools =
    build ~credentials ~model_id:"openai/gpt-5.4"
      ~messages:[ `Assoc [ ("role", `String "user"); ("content", `String "hi") ] ]
      ~reasoning:Unspecified ~supports_reasoning:false ~session_id:None
      ~provider_preferences:None ~pareto_min_coding_score:None ()
  in
  assert (member "tools" without_tools.body = None)

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_openrouter_contract" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_openrouter_contract ]);
  exit (Suite_telemetry.exit_code self)

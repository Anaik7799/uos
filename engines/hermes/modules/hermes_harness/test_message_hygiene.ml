let member name = function `Assoc fields -> List.assoc_opt name fields | _ -> None

let test_original_case () =
  let open Message_hygiene in
  let message =
    `Assoc
      [ ("role", `String "assistant"); ("_thinking_prefill", `Bool true);
        ("tool_name", `String "lookup");
        ("content", `String "bad\237\189\160text");
        ("tool_calls", `List [ `Assoc [ ("id", `String "tool-1"); ("call_id", `String "internal");
          ("response_item_id", `String "item"); ("extra_content", `Assoc [ ("thought_signature", `String "s") ]) ] ]) ]
  in
  let sanitized = sanitize_messages ~model_id:"openai/gpt-5.4" [ message ] in
  let output = List.hd sanitized in
  assert (member "_thinking_prefill" output = None);
  assert (member "tool_name" output = None);
  assert (member "content" output = Some (`String "bad\239\191\189text"));
  let calls = match member "tool_calls" output with Some (`List [ call ]) -> call | _ -> failwith "missing call" in
  assert (member "call_id" calls = None);
  assert (member "response_item_id" calls = None);
  assert (member "extra_content" calls = None);
  let gemini = List.hd (sanitize_messages ~model_id:"google/gemini-3" [ message ]) in
  let gemini_calls = match member "tool_calls" gemini with Some (`List [ call ]) -> call | _ -> failwith "missing gemini call" in
  assert (member "extra_content" gemini_calls <> None);
  assert (sanitize_messages ~model_id:"openai/gpt-5.4" sanitized = sanitized)

let test_gemma_and_case_insensitive () =
  let open Message_hygiene in
  assert (model_consumes_thought_signature "google/gemma-2-9b");
  assert (model_consumes_thought_signature "GOOGLE/GEMINI-2.5");
  assert (model_consumes_thought_signature "GEMMA-7B-IT");
  assert (not (model_consumes_thought_signature "openai/gpt-4o"));
  assert (not (model_consumes_thought_signature "anthropic/claude-3-5-sonnet"));

  let msg =
    `Assoc
      [ ("role", `String "assistant");
        ("tool_calls", `List [ `Assoc [ ("id", `String "t1");
          ("extra_content", `Assoc [ ("sig", `String "abc") ]) ] ]) ]
  in
  let gemma_res = List.hd (sanitize_messages ~model_id:"google/gemma-2-9b" [ msg ]) in
  let gemma_call = match member "tool_calls" gemma_res with Some (`List [ c ]) -> c | _ -> failwith "missing call" in
  assert (member "extra_content" gemma_call <> None);

  let upper_gemini_res = List.hd (sanitize_messages ~model_id:"GOOGLE/GEMINI-2.5" [ msg ]) in
  let upper_gemini_call = match member "tool_calls" upper_gemini_res with Some (`List [ c ]) -> c | _ -> failwith "missing call" in
  assert (member "extra_content" upper_gemini_call <> None)

let test_codex_field_stripping () =
  let open Message_hygiene in
  let msg =
    `Assoc
      [ ("role", `String "assistant");
        ("codex_reasoning_items", `List [ `String "reasoning_step_1" ]);
        ("codex_message_items", `List [ `String "message_item_1" ]);
        ("content", `String "normal content") ]
  in
  let res = List.hd (sanitize_messages ~model_id:"openai/gpt-4o" [ msg ]) in
  assert (member "codex_reasoning_items" res = None);
  assert (member "codex_message_items" res = None);
  assert (member "content" res = Some (`String "normal content"))

let test_surrogate_boundary_cases () =
  let open Message_hygiene in
  assert (replace_surrogate_utf8 "" = "");
  assert (replace_surrogate_utf8 "plain ascii" = "plain ascii");
  (* Truncated 0xED at end of string *)
  assert (replace_surrogate_utf8 "abc\237" = "abc\237");
  assert (replace_surrogate_utf8 "abc\237\160" = "abc\237\160");
  (* U+D7FF: \237\159\191 (byte 2 = 0x9F < 0xA0, so valid UTF-8, not a surrogate) *)
  assert (replace_surrogate_utf8 "\237\159\191" = "\237\159\191");
  (* U+D800 surrogate codepoint: \237\160\128 -> replaced by replacement char \239\191\189 *)
  assert (replace_surrogate_utf8 "\237\160\128" = "\239\191\189");
  (* U+DFFF surrogate codepoint: \237\191\191 -> replaced by replacement char \239\191\189 *)
  assert (replace_surrogate_utf8 "\237\191\191" = "\239\191\189")

let test_non_object_json_fallbacks () =
  let open Message_hygiene in
  let str_node = `String "hello\237\160\128world" in
  let sanitized_str = sanitize_message ~model_id:"openai/gpt-4o" str_node in
  assert (sanitized_str = `String "hello\239\191\189world");

  let int_node = `Int 42 in
  assert (sanitize_message ~model_id:"openai/gpt-4o" int_node = `Int 42);

  let null_node = `Null in
  assert (sanitize_message ~model_id:"openai/gpt-4o" null_node = `Null);

  let bool_node = `Bool true in
  assert (sanitize_message ~model_id:"openai/gpt-4o" bool_node = `Bool true);

  let list_node = `List [ `String "bad\237\160\128" ] in
  assert (sanitize_message ~model_id:"openai/gpt-4o" list_node = `List [ `String "bad\239\191\189" ]);

  (* Non-Assoc tool call fallback *)
  assert (sanitize_tool_call ~keep_thought_signature:false (`String "call\237\160\128") = `String "call\239\191\189");
  assert (sanitize_tool_call ~keep_thought_signature:false (`Int 100) = `Int 100);

  (* tool_calls field containing non-List value *)
  let invalid_tool_calls_msg = `Assoc [ ("tool_calls", `String "not_a_list\237\160\128") ] in
  let sanitized_invalid = sanitize_message ~model_id:"openai/gpt-4o" invalid_tool_calls_msg in
  assert (member "tool_calls" sanitized_invalid = Some (`String "not_a_list\239\191\189"))

let () =
  test_original_case ();
  test_gemma_and_case_insensitive ();
  test_codex_field_stripping ();
  test_surrogate_boundary_cases ();
  test_non_object_json_fallbacks ()

let () =
  let self =
    Suite_telemetry.observe ~suite:"test_message_hygiene" ~passed:1 ~failed:0 ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_message_hygiene ]);
  exit (Suite_telemetry.exit_code self)

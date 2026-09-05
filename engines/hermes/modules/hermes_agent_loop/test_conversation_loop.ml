let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

let test_init () =
  let st = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
  assert_bool "init step is Init" (st.step = Conversation_loop.Init);
  assert_bool "init count is 0" (st.message_count = 0);
  assert_bool "init model_id" (st.model_id = "openai/gpt-5.4");
  assert_bool "init not complete" (not (Conversation_loop.is_complete st))

let test_zero_and_negative_budget () =
  let st_zero = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:0 in
  let msg = `Assoc [ ("role", `String "user"); ("content", `String "hello") ] in
  let st_zero_res, _ = Conversation_loop.step_turn st_zero ~messages:[ msg ] in
  assert_bool "zero budget step is Interrupted" (st_zero_res.step = Conversation_loop.Interrupted);
  assert_bool "zero budget is_complete" (Conversation_loop.is_complete st_zero_res);

  let st_neg = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:(-10) in
  let st_neg_res, _ = Conversation_loop.step_turn st_neg ~messages:[ msg ] in
  assert_bool "negative budget clamped to zero (Interrupted)" (st_neg_res.step = Conversation_loop.Interrupted);
  assert_bool "negative budget is_complete" (Conversation_loop.is_complete st_neg_res)

let test_budget_exhaustion () =
  let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:1 in
  let msg = `Assoc [ ("role", `String "user"); ("content", `String "hello") ] in
  let st1, _ = Conversation_loop.step_turn st0 ~messages:[ msg ] in
  assert_bool "st1 message_count" (st1.message_count = 1);
  let st2, _ = Conversation_loop.step_turn st1 ~messages:[ msg ] in
  assert_bool "st2 interrupted" (st2.step = Conversation_loop.Interrupted);
  assert_bool "st2 is_complete" (Conversation_loop.is_complete st2)

let test_multi_turn_budget () =
  let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:2 in
  let user_msg = `Assoc [ ("role", `String "user"); ("content", `String "turn 1") ] in
  let st1, _ = Conversation_loop.step_turn st0 ~messages:[ user_msg ] in
  assert_bool "multi-turn 1 step AssistantResponse" (st1.step = Conversation_loop.AssistantResponse);
  assert_bool "multi-turn 1 not complete" (not (Conversation_loop.is_complete st1));

  let assistant_msg = `Assoc [ ("role", `String "assistant"); ("content", `String "reply 1") ] in
  let st2, _ = Conversation_loop.step_turn st1 ~messages:[ user_msg; assistant_msg ] in
  assert_bool "multi-turn 2 step Complete" (st2.step = Conversation_loop.Complete);
  assert_bool "multi-turn 2 is_complete" (Conversation_loop.is_complete st2);

  let st3, _ = Conversation_loop.step_turn st2 ~messages:[ user_msg; assistant_msg ] in
  assert_bool "multi-turn 3 interrupted" (st3.step = Conversation_loop.Interrupted)

let test_tool_call_detection () =
  let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:10 in
  let tool_msg =
    `Assoc
      [
        ("role", `String "assistant");
        ( "tool_calls",
          `List [ `Assoc [ ("id", `String "call_1"); ("type", `String "function") ] ] );
      ]
  in
  let st1, _ = Conversation_loop.step_turn st0 ~messages:[ tool_msg ] in
  assert_bool "tool call step" (st1.step = Conversation_loop.ToolCall);

  let role_tool_msg = `Assoc [ ("role", `String "tool"); ("content", `String "result") ] in
  let st2, _ = Conversation_loop.step_turn st0 ~messages:[ role_tool_msg ] in
  assert_bool "role=tool step is ToolCall" (st2.step = Conversation_loop.ToolCall)

let test_empty_model_id () =
  let st = Conversation_loop.init_state ~model_id:"" ~max_turns:3 in
  assert_bool "empty model_id init" (st.model_id = "");
  let res = Conversation_loop.process ~model_id:"" ~messages:[] in
  assert_bool "empty model_id process" (res = `Assoc [ ("messages", `List []); ("model", `String "") ])

let test_malformed_messages_no_crash () =
  let st0 = Conversation_loop.init_state ~model_id:"openai/gpt-5.4" ~max_turns:5 in
  let malformed_msgs =
    [
      `Int 42;
      `String "invalid";
      `Assoc [ ("role", `Int 999) ];
      `Assoc [ ("tool_calls", `Int 123) ];
    ]
  in
  let st1, sanitized = Conversation_loop.step_turn st0 ~messages:malformed_msgs in
  assert_bool "malformed msgs step complete without crash" (st1.step = Conversation_loop.Complete);
  assert_bool "sanitized length preserves elements" (List.length sanitized = 4)

let test_process_nominal () =
  let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for conversation_loop") ] ] in
  let res = Conversation_loop.process ~model_id:"openai/gpt-5.4" ~messages:msgs in
  match res with
  | `Assoc fields ->
      let has_messages = List.mem_assoc "messages" fields in
      let has_model = List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") in
      assert_bool "process nominal output structure" (has_messages && has_model)
  | _ -> assert_bool "process nominal output structure" false

let test_process_empty () =
  let res = Conversation_loop.process ~model_id:"test-model" ~messages:[] in
  match res with
  | `Assoc [ ("messages", `List []); ("model", `String "test-model") ] ->
      assert_bool "process empty messages" true
  | _ -> assert_bool "process empty messages" false

let () =
  Printf.printf "=== Running test_conversation_loop ===\n";
  test_init ();
  test_zero_and_negative_budget ();
  test_budget_exhaustion ();
  test_multi_turn_budget ();
  test_tool_call_detection ();
  test_empty_model_id ();
  test_malformed_messages_no_crash ();
  test_process_nominal ();
  test_process_empty ();
  Printf.printf "=== test_conversation_loop PASSED ===\n";
  let self = Suite_telemetry.observe ~suite:"test_conversation_loop" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_conversation_loop ]);
  exit (Suite_telemetry.exit_code self)


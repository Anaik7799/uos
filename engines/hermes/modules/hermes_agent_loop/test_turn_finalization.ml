open Turn_finalization

let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

let test_create_receipt_nominal () =
  let r =
    create_receipt
      ~turn_id:"turn_123"
      ~status:"success"
      ~turns:3
      ~tokens:1500
      ~final_output:(Some "Done")
  in
  assert_bool "receipt turn_id" (r.turn_id = "turn_123");
  assert_bool "receipt status" (r.status = "success");
  assert_bool "receipt turns_executed" (r.turns_executed = 3);
  assert_bool "receipt total_tokens_used" (r.total_tokens_used = 1500);
  assert_bool "receipt final_output" (r.final_output = Some "Done")

let test_create_receipt_clamping () =
  (* Negative turns *)
  let r_neg_turns =
    create_receipt
      ~turn_id:"turn_neg"
      ~status:"ok"
      ~turns:(-5)
      ~tokens:100
      ~final_output:None
  in
  assert_bool "negative turns clamped to 0" (r_neg_turns.turns_executed = 0);
  assert_bool "positive tokens preserved" (r_neg_turns.total_tokens_used = 100);

  (* Negative tokens *)
  let r_neg_tokens =
    create_receipt
      ~turn_id:"turn_neg_tok"
      ~status:"ok"
      ~turns:2
      ~tokens:(-500)
      ~final_output:None
  in
  assert_bool "positive turns preserved" (r_neg_tokens.turns_executed = 2);
  assert_bool "negative tokens clamped to 0" (r_neg_tokens.total_tokens_used = 0);

  (* Empty turn_id *)
  let r_empty_id =
    create_receipt
      ~turn_id:""
      ~status:"pending"
      ~turns:1
      ~tokens:50
      ~final_output:None
  in
  assert_bool "empty turn_id defaulted to unknown" (r_empty_id.turn_id = "unknown");

  (* All boundary clamping combined *)
  let r_all_clamped =
    create_receipt
      ~turn_id:""
      ~status:"error"
      ~turns:(-99)
      ~tokens:(-999)
      ~final_output:None
  in
  assert_bool "combined empty turn_id -> unknown" (r_all_clamped.turn_id = "unknown");
  assert_bool "combined negative turns -> 0" (r_all_clamped.turns_executed = 0);
  assert_bool "combined negative tokens -> 0" (r_all_clamped.total_tokens_used = 0)

let test_summarize () =
  let r =
    create_receipt
      ~turn_id:"t_sum"
      ~status:"complete"
      ~turns:4
      ~tokens:800
      ~final_output:(Some "Result")
  in
  let meta = [ ("duration_ms", `Int 120); ("model", `String "gpt-5.4") ] in
  let s = summarize r ~metadata:meta in
  assert_bool "summarize receipt match" (s.receipt = r);
  assert_bool "summarize metadata match" (s.metadata = meta);

  (* Empty metadata *)
  let s_empty = summarize r ~metadata:[] in
  assert_bool "summarize empty metadata match" (s_empty.metadata = [])

let test_finalize_nominal () =
  let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for turn_finalization") ] ] in
  let res = finalize ~model_id:"openai/gpt-5.4" ~messages:msgs in
  match res with
  | `Assoc fields ->
      let has_messages = List.mem_assoc "messages" fields in
      let has_model = List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") in
      assert_bool "finalize nominal structure" (has_messages && has_model)
  | _ -> assert_bool "finalize nominal structure" false

let test_finalize_empty_and_hygiene () =
  (* Empty messages *)
  let res_empty = finalize ~model_id:"openai/gpt-5.4" ~messages:[] in
  assert_bool
    "finalize empty messages"
    (res_empty = `Assoc [ ("messages", `List []); ("model", `String "openai/gpt-5.4") ]);

  (* Empty model_id *)
  let res_empty_model = finalize ~model_id:"" ~messages:[] in
  assert_bool
    "finalize empty model_id"
    (res_empty_model = `Assoc [ ("messages", `List []); ("model", `String "") ]);

  (* Internal field filtering hygiene *)
  let private_msg =
    `Assoc
      [
        ("role", `String "user");
        ("content", `String "hello");
        ("_internal_tag", `String "secret");
        ("tool_name", `String "search");
        ("codex_reasoning_items", `List []);
      ]
  in
  let res_hygiene = finalize ~model_id:"openai/gpt-5.4" ~messages:[ private_msg ] in
  match res_hygiene with
  | `Assoc [ ("messages", `List [ `Assoc fields ]); ("model", `String "openai/gpt-5.4") ] ->
      let has_role = List.mem_assoc "role" fields in
      let has_content = List.mem_assoc "content" fields in
      let has_internal = List.mem_assoc "_internal_tag" fields in
      let has_tool_name = List.mem_assoc "tool_name" fields in
      let has_codex = List.mem_assoc "codex_reasoning_items" fields in
      assert_bool
        "private and internal fields stripped by hygiene"
        (has_role && has_content && not has_internal && not has_tool_name && not has_codex)
  | _ -> assert_bool "private and internal fields stripped by hygiene" false

let test_finalize_tool_call_thought_signature () =
  let tool_call =
    `Assoc
      [
        ("id", `String "call_1");
        ("type", `String "function");
        ("extra_content", `String "thought data");
      ]
  in
  let msg =
    `Assoc
      [
        ("role", `String "assistant");
        ("tool_calls", `List [ tool_call ]);
      ]
  in
  (* For openai/gpt-5.4: extra_content is stripped *)
  let res_openai = finalize ~model_id:"openai/gpt-5.4" ~messages:[ msg ] in
  (match res_openai with
  | `Assoc [ ("messages", `List [ `Assoc fields ]); ("model", `String "openai/gpt-5.4") ] ->
      (match List.assoc_opt "tool_calls" fields with
      | Some (`List [ `Assoc tc_fields ]) ->
          assert_bool "extra_content stripped for openai model" (not (List.mem_assoc "extra_content" tc_fields))
      | _ -> assert_bool "extra_content stripped for openai model" false)
  | _ -> assert_bool "extra_content stripped for openai model" false);

  (* For google/gemini-2.5-pro: extra_content is kept *)
  let res_gemini = finalize ~model_id:"google/gemini-2.5-pro" ~messages:[ msg ] in
  match res_gemini with
  | `Assoc [ ("messages", `List [ `Assoc fields ]); ("model", `String "google/gemini-2.5-pro") ] ->
      (match List.assoc_opt "tool_calls" fields with
      | Some (`List [ `Assoc tc_fields ]) ->
          assert_bool "extra_content kept for gemini model" (List.mem_assoc "extra_content" tc_fields)
      | _ -> assert_bool "extra_content kept for gemini model" false)
  | _ -> assert_bool "extra_content kept for gemini model" false

let test_finalize_surrogate_utf8 () =
  (* UTF-8 surrogate high surrogate sequence: \xED\xA0\x80 *)
  let surrogate_msg =
    `Assoc
      [
        ("role", `String "user");
        ("content", `String "invalid \xED\xA0\x80 surrogate");
      ]
  in
  let res_utf8 = finalize ~model_id:"openai/gpt-5.4" ~messages:[ surrogate_msg ] in
  match res_utf8 with
  | `Assoc [ ("messages", `List [ `Assoc fields ]); ("model", `String "openai/gpt-5.4") ] ->
      (match List.assoc_opt "content" fields with
      | Some (`String content_str) ->
          assert_bool
            "surrogate utf8 replaced with U+FFFD"
            (content_str = "invalid \239\191\189 surrogate")
      | _ -> assert_bool "surrogate utf8 replaced with U+FFFD" false)
  | _ -> assert_bool "surrogate utf8 replaced with U+FFFD" false

let () =
  Printf.printf "=== Running test_turn_finalization ===\n";
  test_create_receipt_nominal ();
  test_create_receipt_clamping ();
  test_summarize ();
  test_finalize_nominal ();
  test_finalize_empty_and_hygiene ();
  test_finalize_tool_call_thought_signature ();
  test_finalize_surrogate_utf8 ();
  Printf.printf "=== test_turn_finalization PASSED ===\n";
  let self = Suite_telemetry.observe ~suite:"test_turn_finalization" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_turn_finalization ]);
  exit (Suite_telemetry.exit_code self)

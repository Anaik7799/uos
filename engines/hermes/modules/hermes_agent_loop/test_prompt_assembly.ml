let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

let test_developer_role_detection () =
  assert_bool "gpt-5 model uses dev role" (Prompt_assembly.model_uses_developer_role "openai/gpt-5.4");
  assert_bool "codex model uses dev role" (Prompt_assembly.model_uses_developer_role "openai/codex-v1");
  assert_bool "GPT-5 uppercase uses dev role" (Prompt_assembly.model_uses_developer_role "OPENAI/GPT-5-TURBO");
  assert_bool "claude model does not use dev role" (not (Prompt_assembly.model_uses_developer_role "anthropic/claude-sonnet-4.5"));
  assert_bool "llama model does not use dev role" (not (Prompt_assembly.model_uses_developer_role "meta/llama-3-70b"));
  assert_bool "empty model_id does not use dev role" (not (Prompt_assembly.model_uses_developer_role ""))

let test_apply_developer_role () =
  let sys_msg = `Assoc [ ("role", `String "system"); ("content", `String "be concise") ] in
  let user_msg = `Assoc [ ("role", `String "user"); ("content", `String "hi") ] in
  let msgs = [ sys_msg; user_msg ] in

  let dev_formatted = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" msgs in
  (match dev_formatted with
  | `Assoc fields :: _ ->
      assert_bool "first message role changed to developer" (List.assoc_opt "role" fields = Some (`String "developer"))
  | _ -> assert_bool "dev format match" false);

  let non_dev_formatted = Prompt_assembly.apply_developer_role ~model_id:"anthropic/claude-sonnet-4.5" msgs in
  (match non_dev_formatted with
  | `Assoc fields :: _ ->
      assert_bool "first message role remains system" (List.assoc_opt "role" fields = Some (`String "system"))
  | _ -> assert_bool "non dev format match" false);

  let user_leading_msgs = [ user_msg; sys_msg ] in
  let user_leading_formatted = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" user_leading_msgs in
  (match user_leading_formatted with
  | `Assoc fields :: _ ->
      assert_bool "non-system leading message role unchanged" (List.assoc_opt "role" fields = Some (`String "user"))
  | _ -> assert_bool "user leading format match" false)

let test_empty_and_malformed_messages () =
  let empty_res = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" [] in
  assert_bool "empty messages apply_developer_role" (empty_res = []);

  let non_assoc_msgs = [ `Int 123; `String "test" ] in
  let non_assoc_res = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" non_assoc_msgs in
  assert_bool "non-assoc leading item unchanged without crash" (non_assoc_res = non_assoc_msgs);

  let malformed_role_msg = `Assoc [ ("role", `Int 42); ("content", `String "hello") ] in
  let malformed_res = Prompt_assembly.apply_developer_role ~model_id:"openai/gpt-5.4" [ malformed_role_msg ] in
  assert_bool "malformed role field unchanged without crash" (malformed_res = [ malformed_role_msg ])

let test_assemble_nominal () =
  let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for prompt_assembly") ] ] in
  let res = Prompt_assembly.assemble ~model_id:"openai/gpt-5.4" ~messages:msgs in
  match res with
  | `Assoc fields ->
      let has_messages = List.mem_assoc "messages" fields in
      let has_model = List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") in
      assert_bool "assemble nominal output structure" (has_messages && has_model)
  | _ -> assert_bool "assemble nominal output structure" false

let test_assemble_empty () =
  let res = Prompt_assembly.assemble ~model_id:"test-model" ~messages:[] in
  match res with
  | `Assoc [ ("messages", `List []); ("model", `String "test-model") ] ->
      assert_bool "assemble empty messages" true
  | _ -> assert_bool "assemble empty messages" false

let () =
  Printf.printf "=== Running test_prompt_assembly ===\n";
  test_developer_role_detection ();
  test_apply_developer_role ();
  test_empty_and_malformed_messages ();
  test_assemble_nominal ();
  test_assemble_empty ();
  Printf.printf "=== test_prompt_assembly PASSED ===\n";
  let self = Suite_telemetry.observe ~suite:"test_prompt_assembly" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_prompt_assembly ]);
  exit (Suite_telemetry.exit_code self)


let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

let test_is_system_msg () =
  let sys_msg = `Assoc [ ("role", `String "system"); ("content", `String "sys prompt") ] in
  let dev_msg = `Assoc [ ("role", `String "developer"); ("content", `String "dev prompt") ] in
  let user_msg = `Assoc [ ("role", `String "user"); ("content", `String "hello") ] in
  let assist_msg = `Assoc [ ("role", `String "assistant"); ("content", `String "reply") ] in
  let non_assoc = `String "invalid" in
  let malformed_role = `Assoc [ ("role", `Int 100) ] in

  assert_bool "is_system_msg system role" (Context_compression.is_system_msg sys_msg);
  assert_bool "is_system_msg developer role" (Context_compression.is_system_msg dev_msg);
  assert_bool "is_system_msg user role" (not (Context_compression.is_system_msg user_msg));
  assert_bool "is_system_msg assistant role" (not (Context_compression.is_system_msg assist_msg));
  assert_bool "is_system_msg non_assoc" (not (Context_compression.is_system_msg non_assoc));
  assert_bool "is_system_msg malformed_role" (not (Context_compression.is_system_msg malformed_role))

let test_truncate_oldest () =
  let sys_hdr = `Assoc [ ("role", `String "system"); ("content", `String "sys") ] in
  let u1 = `Assoc [ ("role", `String "user"); ("content", `String "turn 1") ] in
  let a1 = `Assoc [ ("role", `String "assistant"); ("content", `String "resp 1") ] in
  let u2 = `Assoc [ ("role", `String "user"); ("content", `String "turn 2") ] in
  let a2 = `Assoc [ ("role", `String "assistant"); ("content", `String "resp 2") ] in

  let msgs = [ sys_hdr; u1; a1; u2; a2 ] in

  (* Keep last 2 normal messages: sys_hdr, u2, a2 *)
  let res_k2 = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 2 }) msgs in
  assert_bool "truncate keep 2 original_count 5" (res_k2.original_count = 5);
  assert_bool "truncate keep 2 compressed_count 3" (res_k2.compressed_count = 3);
  assert_bool "truncate keep 2 tokens_saved 20" (res_k2.tokens_saved = 20);
  assert_bool "truncate keep 2 sys_hdr preserved" (List.hd res_k2.compressed_messages = sys_hdr);
  assert_bool "truncate keep 2 u2 preserved" (List.nth res_k2.compressed_messages 1 = u2);
  assert_bool "truncate keep 2 a2 preserved" (List.nth res_k2.compressed_messages 2 = a2);

  (* Keep last 0 normal messages with negative keep_last_n clamping *)
  let res_neg = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = (-3) }) msgs in
  assert_bool "truncate negative keep clamped count 1" (res_neg.compressed_count = 1);
  assert_bool "truncate negative keep sys_hdr only" (res_neg.compressed_messages = [ sys_hdr ]);

  (* Keep last 10 (larger than normal_msgs) *)
  let res_k10 = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 10 }) msgs in
  assert_bool "truncate keep 10 retains all" (res_k10.compressed_count = 5);
  assert_bool "truncate keep 10 tokens_saved 0" (res_k10.tokens_saved = 0);

  (* Truncate without system header *)
  let no_sys_msgs = [ u1; a1; u2; a2 ] in
  let res_nosys = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 1 }) no_sys_msgs in
  assert_bool "truncate no_sys count 1" (res_nosys.compressed_count = 1);
  assert_bool "truncate no_sys last msg kept" (res_nosys.compressed_messages = [ a2 ]);

  (* Empty messages list *)
  let res_empty = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 2 }) [] in
  assert_bool "truncate empty list count 0" (res_empty.compressed_count = 0);
  assert_bool "truncate empty list tokens_saved 0" (res_empty.tokens_saved = 0)

let test_summarize_history () =
  let dev_hdr = `Assoc [ ("role", `String "developer"); ("content", `String "instructions") ] in
  let u1 = `Assoc [ ("role", `String "user"); ("content", `String "turn 1") ] in
  let a1 = `Assoc [ ("role", `String "assistant"); ("content", `String "resp 1") ] in
  let u2 = `Assoc [ ("role", `String "user"); ("content", `String "turn 2") ] in

  let msgs = [ dev_hdr; u1; a1; u2 ] in

  let res_sum = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "Summary:" }) msgs in
  assert_bool "summarize original_count 4" (res_sum.original_count = 4);
  assert_bool "summarize compressed_count 2" (res_sum.compressed_count = 2);
  assert_bool "summarize tokens_saved 30" (res_sum.tokens_saved = 30);
  assert_bool "summarize dev_hdr preserved" (List.hd res_sum.compressed_messages = dev_hdr);
  (match List.nth res_sum.compressed_messages 1 with
  | `Assoc fields ->
      let role = List.assoc_opt "role" fields in
      let content = List.assoc_opt "content" fields in
      assert_bool "summary message role user" (role = Some (`String "user"));
      assert_bool "summary message content prefix" (content = Some (`String "Summary: [summarized 3 turns]"))
  | _ -> assert_bool "summary message structure" false);

  (* Summarize with <= 1 normal message: no summarization performed *)
  let short_msgs = [ dev_hdr; u1 ] in
  let res_short = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "Summary:" }) short_msgs in
  assert_bool "summarize short msgs unchanged" (res_short.compressed_messages = short_msgs);
  assert_bool "summarize short msgs tokens_saved 0" (res_short.tokens_saved = 0)

let test_cache_ephemeral_prompts () =
  let msg1 = `Assoc [ ("role", `String "system"); ("content", `String "sys") ] in
  let msg2 = `Assoc [ ("role", `String "user"); ("content", `String "user") ] in
  let non_assoc = `String "raw text" in

  let msgs = [ msg1; msg2; non_assoc ] in

  let res_cache = Context_compression.compress_history ~strategy:Cache_ephemeral_prompts msgs in
  assert_bool "cache original_count 3" (res_cache.original_count = 3);
  assert_bool "cache compressed_count 3" (res_cache.compressed_count = 3);
  assert_bool "cache tokens_saved 50" (res_cache.tokens_saved = 50);

  (match res_cache.compressed_messages with
  | [ `Assoc f1; `Assoc f2; raw ] ->
      assert_bool "f1 has cache_control" (List.mem_assoc "cache_control" f1);
      assert_bool "f2 has cache_control" (List.mem_assoc "cache_control" f2);
      assert_bool "non_assoc preserved" (raw = non_assoc)
  | _ -> assert_bool "cache compressed_messages structure" false)

let test_compress () =
  let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for context_compression") ] ] in
  let res = Context_compression.compress ~model_id:"openai/gpt-5.4" ~messages:msgs in
  (match res with
  | `Assoc fields ->
      let has_messages = List.mem_assoc "messages" fields in
      let has_model = List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") in
      assert_bool "compress nominal output structure" (has_messages && has_model)
  | _ -> assert_bool "compress nominal output structure" false);

  let empty_res = Context_compression.compress ~model_id:"test-model" ~messages:[] in
  (match empty_res with
  | `Assoc [ ("messages", `List []); ("model", `String "test-model") ] ->
      assert_bool "compress empty messages" true
  | _ -> assert_bool "compress empty messages" false);

  (* Hygiene sanitization check *)
  let surrogate_msg = `Assoc [ ("role", `String "user"); ("content", `String "bad \237\160\128 UTF-8") ] in
  let sanitize_res = Context_compression.compress ~model_id:"openai/gpt-5.4" ~messages:[ surrogate_msg ] in
  (match sanitize_res with
  | `Assoc fields -> (
      match List.assoc_opt "messages" fields with
      | Some (`List [ `Assoc msg_fields ]) ->
          let content = List.assoc_opt "content" msg_fields in
          assert_bool "surrogate sanitized in compress" (content = Some (`String "bad \239\191\189 UTF-8"))
      | _ -> assert_bool "sanitized message structure" false)
  | _ -> assert_bool "sanitized output structure" false)

let () =
  Printf.printf "=== Running test_context_compression ===\n";
  test_is_system_msg ();
  test_truncate_oldest ();
  test_summarize_history ();
  test_cache_ephemeral_prompts ();
  test_compress ();
  Printf.printf "=== test_context_compression PASSED ===\n";
  let self = Suite_telemetry.observe ~suite:"test_context_compression" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_context_compression ]);
  exit (Suite_telemetry.exit_code self)

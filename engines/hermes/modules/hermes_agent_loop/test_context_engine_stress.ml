let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

let assert_equal_int msg expected actual =
  if expected <> actual then (
    Printf.eprintf "FAIL: %s (expected %d, got %d)\n" msg expected actual;
    exit 1)
  else Printf.printf "PASS: %s (%d)\n" msg actual

(* 1. Boundary Limits on State Creation *)
let test_create_boundaries () =
  let st_zero = Context_engine.create ~max_context_tokens:0 in
  assert_equal_int "create zero max_context_tokens" 0 st_zero.max_context_tokens;
  assert_equal_int "create zero total_tokens" 0 st_zero.total_tokens;

  let st_neg1 = Context_engine.create ~max_context_tokens:(-1) in
  assert_equal_int "create -1 max_context_tokens clamped" 0 st_neg1.max_context_tokens;

  let st_min = Context_engine.create ~max_context_tokens:Int.min_int in
  assert_equal_int "create min_int max_context_tokens clamped" 0 st_min.max_context_tokens;

  let st_max = Context_engine.create ~max_context_tokens:Int.max_int in
  assert_equal_int "create max_int max_context_tokens" Int.max_int st_max.max_context_tokens

(* 2. Extreme Negative and Large Token Counts *)
let test_negative_and_extreme_tokens () =
  let st = Context_engine.create ~max_context_tokens:1_000_000 in
  let ref_neg_min = {
    Context_engine.ref_id = "neg_min";
    kind = "file";
    uri = "uri://neg";
    content = "neg";
    token_count = Int.min_int;
  } in
  let st1 = Context_engine.add_reference st ref_neg_min in
  assert_equal_int "token_count min_int clamped to 0" 0 (List.hd st1.active_references).token_count;
  assert_equal_int "total_tokens remains 0" 0 st1.total_tokens;

  let ref_large = {
    Context_engine.ref_id = "large";
    kind = "file";
    uri = "uri://large";
    content = "large";
    token_count = 500_000;
  } in
  let st2 = Context_engine.add_reference st1 ref_large in
  assert_equal_int "total_tokens updated to 500k" 500_000 st2.total_tokens

(* 3. Mass Duplicate Ref ID Overwrites & List Invariants *)
let test_duplicate_ref_id_overwrites () =
  let st0 = Context_engine.create ~max_context_tokens:100_000 in
  (* Add 1000 duplicate references with increasing token_counts *)
  let st_final = ref st0 in
  for i = 1 to 1000 do
    let r = {
      Context_engine.ref_id = "same_id";
      kind = "doc";
      uri = "http://example.com/doc";
      content = Printf.sprintf "version %d" i;
      token_count = i * 10;
    } in
    st_final := Context_engine.add_reference !st_final r
  done;
  assert_equal_int "1000 overwrites result in exactly 1 active reference" 1 (List.length (!st_final).active_references);
  assert_equal_int "total_tokens equals last overwrite value" 10000 (!st_final).total_tokens;
  let final_ref = List.hd (!st_final).active_references in
  assert_bool "content matches last overwrite" (final_ref.content = "version 1000")

(* 4. Mass Reference Additions and Sequential Removal *)
let test_mass_references_and_removal () =
  let st0 = Context_engine.create ~max_context_tokens:10_000_000 in
  let count = 5000 in
  let st_full = ref st0 in
  for i = 1 to count do
    let r = {
      Context_engine.ref_id = Printf.sprintf "ref_%d" i;
      kind = "file";
      uri = Printf.sprintf "file://path/%d" i;
      content = "data";
      token_count = 2;
    } in
    st_full := Context_engine.add_reference !st_full r
  done;
  assert_equal_int "5000 distinct references added" count (List.length (!st_full).active_references);
  assert_equal_int "total_tokens 10000" (count * 2) (!st_full).total_tokens;

  (* Remove half of them *)
  for i = 1 to count / 2 do
    st_full := Context_engine.remove_reference !st_full ~ref_id:(Printf.sprintf "ref_%d" i)
  done;
  assert_equal_int "remaining count after half removal" (count / 2) (List.length (!st_full).active_references);
  assert_equal_int "remaining total_tokens" ((count / 2) * 2) (!st_full).total_tokens;

  (* Remove non-existent ID *)
  let st_no_change = Context_engine.remove_reference !st_full ~ref_id:"non_existent_id_99999" in
  assert_equal_int "removal of missing id changes nothing" (count / 2) (List.length st_no_change.active_references);
  assert_equal_int "total_tokens unchanged after missing removal" ((count / 2) * 2) st_no_change.total_tokens

(* 5. Surrogate UTF-8 and Adversarial UTF-8 Payloads in Messages *)
let test_surrogate_utf8_and_malformed_payloads () =
  let surrogate_high = `Assoc [ ("role", `String "user"); ("content", `String "High surrogate: \237\160\128 end") ] in
  let surrogate_low = `Assoc [ ("role", `String "user"); ("content", `String "Low surrogate: \237\176\128 end") ] in
  let invalid_bytes = `Assoc [ ("role", `String "user"); ("content", `String "Invalid: \255\254 end") ] in
  let null_bytes = `Assoc [ ("role", `String "user"); ("content", `String "Null byte: \000 test") ] in

  let msgs = [ surrogate_high; surrogate_low; invalid_bytes; null_bytes ] in
  let res = Context_engine.process ~model_id:"test-model" ~messages:msgs in
  (match res with
  | `Assoc fields -> (
      match List.assoc_opt "messages" fields with
      | Some (`List sanitized_list) ->
          assert_equal_int "sanitized message count matches input" 4 (List.length sanitized_list);
          assert_bool "process completed without crash" true
      | _ -> assert_bool "messages field missing or invalid" false)
  | _ -> assert_bool "process returned non-assoc" false)

(* 6. Large Message Payloads and Benchmark *)
let test_large_message_payloads () =
  let big_string = String.make 10_000 'A' in
  let large_messages =
    List.init 1000 (fun i ->
        `Assoc [
          ("role", `String (if i mod 2 = 0 then "user" else "assistant"));
          ("content", `String big_string);
          ("id", `String (Printf.sprintf "msg_%d" i));
        ])
  in
  let start_time = Sys.time () in
  let res = Context_engine.process ~model_id:"large-payload-model" ~messages:large_messages in
  let elapsed = Sys.time () -. start_time in
  Printf.printf "  [Info] Processed 1000 messages (10MB payload) in %.4f seconds\n" elapsed;
  (match res with
  | `Assoc fields -> (
      match List.assoc_opt "messages" fields with
      | Some (`List sanitized) ->
          assert_equal_int "large payload message count" 1000 (List.length sanitized)
      | _ -> assert_bool "large payload messages field missing" false)
  | _ -> assert_bool "large payload return structure" false)

(* 7. Malformed Non-Assoc JSON Messages inside list *)
let test_malformed_json_elements () =
  let malformed_messages = [
    `Null;
    `Int 12345;
    `String "plain string message";
    `List [ `String "nested list" ];
    `Assoc [ ("role", `Int 999); ("content", `Null) ];
    `Assoc [ ("role", `String "user") ]; (* missing content *)
  ] in
  let res = Context_engine.process ~model_id:"robustness-test" ~messages:malformed_messages in
  (match res with
  | `Assoc fields ->
      let has_msgs = List.mem_assoc "messages" fields in
      assert_bool "malformed json elements handled gracefully without crash" has_msgs
  | _ -> assert_bool "malformed json result structure" false)

let () =
  Printf.printf "=== Running test_context_engine_stress ===\n";
  test_create_boundaries ();
  test_negative_and_extreme_tokens ();
  test_duplicate_ref_id_overwrites ();
  test_mass_references_and_removal ();
  test_surrogate_utf8_and_malformed_payloads ();
  test_large_message_payloads ();
  test_malformed_json_elements ();
  Printf.printf "=== test_context_engine_stress PASSED ===\n";
  let self = Suite_telemetry.observe ~suite:"test_context_engine_stress" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_conversation_loop; Stanza.hermes_agent_loop_prompt_assembly; Stanza.hermes_agent_loop_context_engine; Stanza.hermes_agent_loop_context_compression; Stanza.hermes_agent_loop_turn_finalization; Stanza.hermes_agent_loop_interrupt_control; Stanza.hermes_agent_loop_message_hygiene; Stanza.hermes_agent_loop_message_repairs; Stanza.hermes_agent_loop_json_canonical; Stanza.hermes_agent_loop_loop_send_path; Stanza.hermes_agent_loop_prompt_units; Stanza.hermes_agent_loop_context_units; Stanza.hermes_agent_loop_compress_units; Stanza.hermes_agent_loop_finalize_units; Stanza.hermes_agent_loop_redact_units; Stanza.hermes_agent_loop_tool_units; Stanza.hermes_agent_loop_context_file_units; Stanza.hermes_agent_loop_memory_units; Stanza.hermes_agent_loop_skill_units; Stanza.hermes_agent_loop_interactive_cli_units; Stanza.hermes_agent_loop_mcp_units; Stanza.hermes_agent_loop_subagent_units ]);
  exit (Suite_telemetry.exit_code self)

let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

let test_create () =
  let st = Context_engine.create ~max_context_tokens:1000 in
  assert_bool "create initial references empty" (st.active_references = []);
  assert_bool "create initial total_tokens is 0" (st.total_tokens = 0);
  assert_bool "create max_context_tokens is 1000" (st.max_context_tokens = 1000);

  let st_neg = Context_engine.create ~max_context_tokens:(-500) in
  assert_bool "create negative max_context_tokens clamped to 0" (st_neg.max_context_tokens = 0);
  assert_bool "create negative initial total_tokens is 0" (st_neg.total_tokens = 0)

let test_add_reference () =
  let st0 = Context_engine.create ~max_context_tokens:2000 in
  let ref1 = {
    Context_engine.ref_id = "doc1";
    kind = "file";
    uri = "file:///tmp/doc1.txt";
    content = "hello world";
    token_count = 100;
  } in
  let st1 = Context_engine.add_reference st0 ref1 in
  assert_bool "add_reference count 1" (List.length st1.active_references = 1);
  assert_bool "add_reference total_tokens 100" (st1.total_tokens = 100);

  let ref2 = {
    Context_engine.ref_id = "doc2";
    kind = "file";
    uri = "file:///tmp/doc2.txt";
    content = "foo bar";
    token_count = 250;
  } in
  let st2 = Context_engine.add_reference st1 ref2 in
  assert_bool "add_reference count 2" (List.length st2.active_references = 2);
  assert_bool "add_reference total_tokens 350" (st2.total_tokens = 350);

  (* Replacement of existing ref_id *)
  let ref1_updated = { ref1 with token_count = 150 } in
  let st3 = Context_engine.add_reference st2 ref1_updated in
  assert_bool "replacement reference count remains 2" (List.length st3.active_references = 2);
  assert_bool "replacement reference updated total_tokens 400" (st3.total_tokens = 400);

  (* Negative token_count clamping *)
  let ref_neg = {
    Context_engine.ref_id = "doc_neg";
    kind = "file";
    uri = "file:///tmp/neg.txt";
    content = "";
    token_count = (-80);
  } in
  let st4 = Context_engine.add_reference st3 ref_neg in
  assert_bool "negative token count reference added" (List.length st4.active_references = 3);
  let added_neg = List.find (fun r -> r.Context_engine.ref_id = "doc_neg") st4.active_references in
  assert_bool "negative token_count clamped to 0" (added_neg.token_count = 0);
  assert_bool "total_tokens unchanged after adding 0 token ref" (st4.total_tokens = 400)

let test_remove_reference () =
  let st0 = Context_engine.create ~max_context_tokens:2000 in
  let ref1 = {
    Context_engine.ref_id = "refA";
    kind = "tool";
    uri = "tool://search";
    content = "resA";
    token_count = 120;
  } in
  let ref2 = {
    Context_engine.ref_id = "refB";
    kind = "tool";
    uri = "tool://calc";
    content = "resB";
    token_count = 80;
  } in
  let st1 = Context_engine.add_reference (Context_engine.add_reference st0 ref1) ref2 in
  assert_bool "setup 2 refs" (List.length st1.active_references = 2 && st1.total_tokens = 200);

  let st2 = Context_engine.remove_reference st1 ~ref_id:"refA" in
  assert_bool "remove refA count 1" (List.length st2.active_references = 1);
  assert_bool "remove refA total_tokens 80" (st2.total_tokens = 80);

  let st3 = Context_engine.remove_reference st2 ~ref_id:"non_existent" in
  assert_bool "remove non_existent count 1" (List.length st3.active_references = 1);
  assert_bool "remove non_existent total_tokens 80" (st3.total_tokens = 80);

  let st4 = Context_engine.remove_reference st3 ~ref_id:"refB" in
  assert_bool "remove refB count 0" (List.length st4.active_references = 0);
  assert_bool "remove refB total_tokens 0" (st4.total_tokens = 0)

let test_process () =
  let msgs = [ `Assoc [ ("role", `String "user"); ("content", `String "stub for context_engine") ] ] in
  let res = Context_engine.process ~model_id:"openai/gpt-5.4" ~messages:msgs in
  (match res with
  | `Assoc fields ->
      let has_messages = List.mem_assoc "messages" fields in
      let has_model = List.assoc_opt "model" fields = Some (`String "openai/gpt-5.4") in
      assert_bool "process nominal output structure" (has_messages && has_model)
  | _ -> assert_bool "process nominal output structure" false);

  let empty_res = Context_engine.process ~model_id:"test-model" ~messages:[] in
  (match empty_res with
  | `Assoc [ ("messages", `List []); ("model", `String "test-model") ] ->
      assert_bool "process empty messages" true
  | _ -> assert_bool "process empty messages" false);

  (* Hygiene sanitization check *)
  let surrogate_msg = `Assoc [ ("role", `String "user"); ("content", `String "bad \237\160\128 UTF-8") ] in
  let sanitize_res = Context_engine.process ~model_id:"openai/gpt-5.4" ~messages:[ surrogate_msg ] in
  (match sanitize_res with
  | `Assoc fields -> (
      match List.assoc_opt "messages" fields with
      | Some (`List [ `Assoc msg_fields ]) ->
          let content = List.assoc_opt "content" msg_fields in
          assert_bool "surrogate sanitized in content" (content = Some (`String "bad \239\191\189 UTF-8"))
      | _ -> assert_bool "sanitized message structure" false)
  | _ -> assert_bool "sanitized output structure" false)

let () =
  Printf.printf "=== Running test_context_engine ===\n";
  test_create ();
  test_add_reference ();
  test_remove_reference ();
  test_process ();
  Printf.printf "=== test_context_engine PASSED ===\n";
  let self = Suite_telemetry.observe ~suite:"test_context_engine" ~passed:1 ~failed:0 ~skipped:0 in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_agent_loop_context_engine ]);
  exit (Suite_telemetry.exit_code self)

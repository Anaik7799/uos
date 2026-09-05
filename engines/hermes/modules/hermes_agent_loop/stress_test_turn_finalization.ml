open Turn_finalization

let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL: %s\n" msg;
    exit 1)
  else Printf.printf "PASS: %s\n" msg

(* Validate predicate valid_turn_receipt manually in OCaml *)
let is_valid_turn_receipt r =
  r.turns_executed >= 0 && r.total_tokens_used >= 0 && r.turn_id <> ""

(* 1. Create Receipt Extreme Boundary Matrix *)
let test_receipt_extreme_boundaries () =
  Printf.printf "[Challenger] Testing Receipt Extreme Boundaries...\n";
  let turn_inputs = [ 0; 1; 100; max_int; -1; -99999; min_int ] in
  let token_inputs = [ 0; 1; 500000; max_int; -1; -1000000; min_int ] in
  let id_inputs = [ ""; "t1"; "   "; "\000null\000id\000"; String.make 1000 'a' ] in
  let status_inputs = [ ""; "success"; "error"; "CANCELLED"; "\000status\000" ] in
  let output_inputs = [ None; Some ""; Some "ok"; Some "\000out\000"; Some (String.make 5000 'z') ] in

  let total_tested = ref 0 in
  List.iter (fun turns ->
    List.iter (fun tokens ->
      List.iter (fun turn_id ->
        List.iter (fun status ->
          List.iter (fun final_output ->
            incr total_tested;
            let r = create_receipt ~turn_id ~status ~turns ~tokens ~final_output in
            (* Check invariants *)
            if not (is_valid_turn_receipt r) then (
              Printf.eprintf "FAIL: Invalid turn receipt generated for turns=%d tokens=%d turn_id='%s'\n"
                turns tokens turn_id;
              exit 1);
            if turns < 0 && r.turns_executed <> 0 then (
              Printf.eprintf "FAIL: Negative turns %d not clamped to 0\n" turns;
              exit 1);
            if turns >= 0 && r.turns_executed <> turns then (
              Printf.eprintf "FAIL: Positive turns %d altered to %d\n" turns r.turns_executed;
              exit 1);
            if tokens < 0 && r.total_tokens_used <> 0 then (
              Printf.eprintf "FAIL: Negative tokens %d not clamped to 0\n" tokens;
              exit 1);
            if tokens >= 0 && r.total_tokens_used <> tokens then (
              Printf.eprintf "FAIL: Positive tokens %d altered to %d\n" tokens r.total_tokens_used;
              exit 1);
            if turn_id = "" && r.turn_id <> "unknown" then (
              Printf.eprintf "FAIL: Empty turn_id not converted to 'unknown'\n";
              exit 1);
            if turn_id <> "" && r.turn_id <> turn_id then (
              Printf.eprintf "FAIL: Non-empty turn_id '%s' altered to '%s'\n" turn_id r.turn_id;
              exit 1)
          ) output_inputs
        ) status_inputs
      ) id_inputs
    ) token_inputs
  ) turn_inputs;
  Printf.printf "PASS: Verified %d receipt boundary combinations.\n" !total_tested

(* 2. Summarize Boundary & Metadata Matrix *)
let test_summarize_boundaries () =
  Printf.printf "[Challenger] Testing Summarize Boundaries...\n";
  let r = create_receipt ~turn_id:"turn_boundary" ~status:"ok" ~turns:(-100) ~tokens:(-500) ~final_output:None in
  let empty_sum = summarize r ~metadata:[] in
  assert_bool "summarize empty metadata" (empty_sum.receipt = r && empty_sum.metadata = []);

  let complex_meta = [
    ("", `Null);
    ("null_byte_key\000", `Int min_int);
    ("large_int", `Int max_int);
    ("nested", `Assoc [ ("a", `List [ `String "\xED\xA0\x80" ]) ]);
    ("duplicate", `Bool true);
    ("duplicate", `Bool false);
  ] in
  let s = summarize r ~metadata:complex_meta in
  assert_bool "summarize complex metadata receipt match" (s.receipt = r);
  assert_bool "summarize complex metadata match" (s.metadata = complex_meta)

(* 3. Finalize Malformed Yojson & Surrogate UTF-8 Matrix *)
let test_finalize_fuzzing () =
  Printf.printf "[Challenger] Testing Finalize Malformed Yojson & Surrogate UTF-8...\n";

  (* Test 3.1: Non-Assoc top-level messages in list *)
  let non_assoc_messages = [
    `Null;
    `Bool true;
    `Int 999;
    `Float 3.14159;
    `String "plain_string";
    `List [ `Int 1; `String "\xED\xA0\x80" ];
    `Assoc [ ("role", `String "user"); ("content", `String "normal") ]
  ] in
  let res_non_assoc = finalize ~model_id:"openai/gpt-5.4" ~messages:non_assoc_messages in
  (match res_non_assoc with
  | `Assoc [ ("messages", `List msgs); ("model", `String "openai/gpt-5.4") ] ->
      assert_bool "finalize non-assoc length preserved" (List.length msgs = List.length non_assoc_messages)
  | _ -> assert_bool "finalize non-assoc structure" false);

  (* Test 3.2: Surrogate UTF-8 boundary cases *)
  let high_surrogate = "\xED\xA0\x80" in
  let low_surrogate = "\xED\xB0\x80" in
  let paired_surrogate = "\xED\xA0\xBD\xED\xB8\x80" in
  let truncated_surrogate = "hello \xED\xA0" in
  let valid_japanese = "\xE3\x81\x82" in (* Hiragana 'a' *)

  let utf8_msg = `Assoc [
    ("role", `String "user");
    ("high", `String high_surrogate);
    ("low", `String low_surrogate);
    ("paired", `String paired_surrogate);
    ("trunc", `String truncated_surrogate);
    ("valid", `String valid_japanese);
  ] in
  let res_utf8 = finalize ~model_id:"openai/gpt-5.4" ~messages:[ utf8_msg ] in
  (match res_utf8 with
  | `Assoc [ ("messages", `List [ `Assoc fields ]); ("model", `String "openai/gpt-5.4") ] ->
      let get_str k = match List.assoc_opt k fields with Some (`String s) -> s | _ -> "" in
      let replacement = "\239\191\189" in
      assert_bool "high surrogate replaced" (get_str "high" = replacement);
      assert_bool "low surrogate replaced" (get_str "low" = replacement);
      assert_bool "paired surrogate double replaced" (get_str "paired" = replacement ^ replacement);
      assert_bool "truncated surrogate preserved (no crash)" (get_str "trunc" = truncated_surrogate);
      assert_bool "valid Japanese UTF-8 untouched" (get_str "valid" = valid_japanese)
  | _ -> assert_bool "finalize utf8 response shape" false);

  (* Test 3.3: Idempotence of Message_hygiene.replace_surrogate_utf8 *)
  let test_strings = [
    "hello";
    high_surrogate;
    low_surrogate;
    paired_surrogate;
    truncated_surrogate;
    valid_japanese;
    "mix \xED\xA0\x80 and \xE3\x81\x82 end \xED\xBF\xBF"
  ] in
  List.iter (fun s ->
    let once = Message_hygiene.replace_surrogate_utf8 s in
    let twice = Message_hygiene.replace_surrogate_utf8 once in
    if once <> twice then (
      Printf.eprintf "FAIL: replace_surrogate_utf8 idempotence violated for '%s'\n" s;
      exit 1
    )
  ) test_strings;
  Printf.printf "PASS: Verified replace_surrogate_utf8 idempotence.\n";

  (* Test 3.4: Deeply nested Yojson structure (no stack overflow / crash) *)
  let rec make_nested depth acc =
    if depth = 0 then acc
    else make_nested (depth - 1) (`Assoc [ ("level", acc); ("text", `String "\xED\xA0\x80") ])
  in
  let deep_msg = make_nested 300 (`String "leaf") in
  let res_deep = finalize ~model_id:"openai/gpt-5.4" ~messages:[ deep_msg ] in
  (match res_deep with
  | `Assoc [ ("messages", `List [ _ ]); ("model", `String "openai/gpt-5.4") ] ->
      assert_bool "deeply nested structure finalized without crash" true
  | _ -> assert_bool "deeply nested structure shape" false);

  (* Test 3.5: Massively large messages list (tail-recursion test) *)
  let count = 20000 in
  let msg_item = `Assoc [ ("role", `String "user"); ("content", `String "bulk message") ] in
  let large_msgs = List.init count (fun _ -> msg_item) in
  let res_large = finalize ~model_id:"google/gemini-2.5-pro" ~messages:large_msgs in
  (match res_large with
  | `Assoc [ ("messages", `List msgs); ("model", `String "google/gemini-2.5-pro") ] ->
      assert_bool "large messages list processed (tail-recursive)" (List.length msgs = count)
  | _ -> assert_bool "large messages list shape" false)

let () =
  Printf.printf "=== STARTING EMPIRICAL CHALLENGE SUITE: Turn_finalization ===\n";
  test_receipt_extreme_boundaries ();
  test_summarize_boundaries ();
  test_finalize_fuzzing ();
  Printf.printf "=== EMPIRICAL CHALLENGE SUITE PASSED WITH ZERO FAILURES ===\n"

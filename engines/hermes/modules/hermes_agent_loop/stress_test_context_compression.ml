(* Adversarial Stress Test Suite for Context_compression *)
open Context_compression

let assert_bool msg cond =
  if not cond then (
    Printf.eprintf "FAIL [STRESS]: %s\n" msg;
    exit 1)
  else Printf.printf "PASS [STRESS]: %s\n" msg

let check_gospel_invariants _strategy messages res =
  let orig_len = List.length messages in
  assert_bool "Gospel: original_count matches length" (res.Context_compression.original_count = orig_len);
  assert_bool "Gospel: compressed_count <= original_count" (res.compressed_count <= res.original_count);
  assert_bool "Gospel: tokens_saved >= 0" (res.tokens_saved >= 0);
  assert_bool "Gospel: compressed_messages length matches compressed_count" (List.length res.compressed_messages = res.compressed_count)

(* 1. Boundary limits for keep_last_n: 0, negative, min_int, extremely large *)
let test_keep_last_n_boundaries () =
  let sys_hdr = `Assoc [ ("role", `String "system"); ("content", `String "sys prompt") ] in
  let msgs = [
    sys_hdr;
    `Assoc [ ("role", `String "user"); ("content", `String "u1") ];
    `Assoc [ ("role", `String "assistant"); ("content", `String "a1") ];
    `Assoc [ ("role", `String "user"); ("content", `String "u2") ];
    `Assoc [ ("role", `String "assistant"); ("content", `String "a2") ];
  ] in

  (* keep_last_n = 0 *)
  let res_0 = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 0 }) msgs in
  check_gospel_invariants (Truncate_oldest { keep_last_n = 0 }) msgs res_0;
  assert_bool "keep_last_n=0 retains system header only" (res_0.compressed_messages = [ sys_hdr ]);
  assert_bool "keep_last_n=0 tokens_saved correct" (res_0.tokens_saved = (5 - 1) * 10);

  (* keep_last_n = -1 *)
  let res_neg1 = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = -1 }) msgs in
  check_gospel_invariants (Truncate_oldest { keep_last_n = -1 }) msgs res_neg1;
  assert_bool "keep_last_n=-1 clamped to 0" (res_neg1.compressed_messages = [ sys_hdr ]);

  (* keep_last_n = min_int *)
  let res_min = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = min_int }) msgs in
  check_gospel_invariants (Truncate_oldest { keep_last_n = min_int }) msgs res_min;
  assert_bool "keep_last_n=min_int clamped to 0 without crash" (res_min.compressed_messages = [ sys_hdr ]);

  (* keep_last_n = max_int *)
  let res_max = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = max_int }) msgs in
  check_gospel_invariants (Truncate_oldest { keep_last_n = max_int }) msgs res_max;
  assert_bool "keep_last_n=max_int retains all" (res_max.compressed_messages = msgs);
  assert_bool "keep_last_n=max_int tokens_saved 0" (res_max.tokens_saved = 0)

(* 2. Single turn & short history summarization *)
let test_summarization_turn_limits () =
  let dev_hdr = `Assoc [ ("role", `String "developer"); ("content", `String "dev instructions") ] in
  let u1 = `Assoc [ ("role", `String "user"); ("content", `String "u1") ] in
  let a1 = `Assoc [ ("role", `String "assistant"); ("content", `String "a1") ] in

  (* 0 turns (empty list) *)
  let res_empty = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "SUM" }) [] in
  check_gospel_invariants (Summarize_history { summary_prefix = "SUM" }) [] res_empty;
  assert_bool "summarize empty list unchanged" (res_empty.compressed_messages = []);

  (* 1 turn with header (1 header + 1 normal turn) *)
  let res_1turn_hdr = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "SUM" }) [ dev_hdr; u1 ] in
  check_gospel_invariants (Summarize_history { summary_prefix = "SUM" }) [ dev_hdr; u1 ] res_1turn_hdr;
  assert_bool "summarize 1 normal turn with header bypassed" (res_1turn_hdr.compressed_messages = [ dev_hdr; u1 ]);
  assert_bool "summarize 1 turn tokens_saved 0" (res_1turn_hdr.tokens_saved = 0);

  (* 1 normal turn without header *)
  let res_1turn_nohdr = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "SUM" }) [ u1 ] in
  check_gospel_invariants (Summarize_history { summary_prefix = "SUM" }) [ u1 ] res_1turn_nohdr;
  assert_bool "summarize 1 normal turn no header bypassed" (res_1turn_nohdr.compressed_messages = [ u1 ]);

  (* 2 normal turns with header *)
  let res_2turns_hdr = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "SUM:" }) [ dev_hdr; u1; a1 ] in
  check_gospel_invariants (Summarize_history { summary_prefix = "SUM:" }) [ dev_hdr; u1; a1 ] res_2turns_hdr;
  assert_bool "summarize 2 normal turns produces 2 messages" (res_2turns_hdr.compressed_count = 2);
  assert_bool "summarize 2 turns tokens_saved" (res_2turns_hdr.tokens_saved = (3 - 2) * 15);
  assert_bool "summarize header preserved at head" (List.hd res_2turns_hdr.compressed_messages = dev_hdr);

  (* Custom & extreme summary prefix *)
  let long_prefix = String.make 1000 'A' in
  let res_long_prefix = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = long_prefix }) [ u1; a1 ] in
  check_gospel_invariants (Summarize_history { summary_prefix = long_prefix }) [ u1; a1 ] res_long_prefix;
  (match res_long_prefix.compressed_messages with
  | [ `Assoc fields ] ->
      (match List.assoc_opt "content" fields with
      | Some (`String c) -> assert_bool "long summary prefix preserved" (String.sub c 0 1000 = long_prefix)
      | _ -> assert_bool "summary content field" false)
  | _ -> assert_bool "summary message structure" false)

(* 3. System header retention under extreme truncation *)
let test_system_header_extreme_truncation () =
  let sys_hdr = `Assoc [ ("role", `String "system"); ("content", `String "CRITICAL SYSTEM INSTRUCTION") ] in
  let dev_hdr = `Assoc [ ("role", `String "developer"); ("content", `String "DEV POLICY") ] in

  (* Construct 10,000 normal messages *)
  let rec make_turns n acc =
    if n <= 0 then acc
    else
      let turn = `Assoc [ ("role", `String (if n mod 2 = 0 then "user" else "assistant")); ("content", `String ("turn " ^ string_of_int n)) ] in
      make_turns (n - 1) (turn :: acc)
  in
  let normal_10k = make_turns 10000 [] in

  (* Extreme truncation with system header to keep_last_n = 0 *)
  let msgs_sys = sys_hdr :: normal_10k in
  let res_sys_trunc = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 0 }) msgs_sys in
  check_gospel_invariants (Truncate_oldest { keep_last_n = 0 }) msgs_sys res_sys_trunc;
  assert_bool "10k turns + sys truncated to sys header only" (res_sys_trunc.compressed_messages = [ sys_hdr ]);
  assert_bool "10k turns tokens_saved formula" (res_sys_trunc.tokens_saved = (10001 - 1) * 10);

  (* Extreme truncation with developer header to keep_last_n = 1 *)
  let msgs_dev = dev_hdr :: normal_10k in
  let res_dev_trunc = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 1 }) msgs_dev in
  check_gospel_invariants (Truncate_oldest { keep_last_n = 1 }) msgs_dev res_dev_trunc;
  assert_bool "10k turns + dev truncated to dev header + 1 turn" (res_dev_trunc.compressed_count = 2);
  assert_bool "10k turns dev header is first" (List.hd res_dev_trunc.compressed_messages = dev_hdr)

(* 4. Prompt Caching Tags & Non-Assoc / Malformed JSON payloads *)
let test_prompt_caching_and_malformed_json () =
  let sys_msg = `Assoc [ ("role", `String "system"); ("content", `String "sys") ] in
  let user_msg = `Assoc [ ("role", `String "user"); ("content", `String "user") ] in
  let raw_str = `String "unwrapped text" in
  let raw_int = `Int 42 in
  let raw_null = `Null in
  let raw_list = `List [ `String "nested" ] in
  let malformed_role = `Assoc [ ("role", `Int 999); ("content", `String "bad role type") ] in
  let empty_assoc = `Assoc [] in

  let heterogeneous_msgs = [ sys_msg; raw_str; user_msg; raw_int; raw_null; raw_list; malformed_role; empty_assoc ] in

  (* Cache_ephemeral_prompts *)
  let res_cache = Context_compression.compress_history ~strategy:Cache_ephemeral_prompts heterogeneous_msgs in
  check_gospel_invariants Cache_ephemeral_prompts heterogeneous_msgs res_cache;
  assert_bool "cache count matches original" (res_cache.compressed_count = List.length heterogeneous_msgs);

  (match res_cache.compressed_messages with
  | [ `Assoc s; r_str; `Assoc u; r_int; r_null; r_lst; `Assoc m_role; `Assoc e_assoc ] ->
      assert_bool "sys has cache_control" (List.mem_assoc "cache_control" s);
      assert_bool "user has cache_control" (List.mem_assoc "cache_control" u);
      assert_bool "malformed_role has cache_control" (List.mem_assoc "cache_control" m_role);
      assert_bool "empty_assoc has cache_control" (List.mem_assoc "cache_control" e_assoc);
      assert_bool "raw_str unmodified" (r_str = raw_str);
      assert_bool "raw_int unmodified" (r_int = raw_int);
      assert_bool "raw_null unmodified" (r_null = raw_null);
      assert_bool "raw_list unmodified" (r_lst = raw_list)
  | _ -> assert_bool "cache heterogeneous structure" false);

  (* Truncate_oldest on heterogeneous msgs *)
  let res_trunc = Context_compression.compress_history ~strategy:(Truncate_oldest { keep_last_n = 2 }) heterogeneous_msgs in
  check_gospel_invariants (Truncate_oldest { keep_last_n = 2 }) heterogeneous_msgs res_trunc;
  assert_bool "truncate heterogeneous retains sys header + last 2 items" (res_trunc.compressed_count = 3);
  assert_bool "sys header preserved first" (List.hd res_trunc.compressed_messages = sys_msg);

  (* Summarize_history on heterogeneous msgs *)
  let res_sum = Context_compression.compress_history ~strategy:(Summarize_history { summary_prefix = "SUM" }) heterogeneous_msgs in
  check_gospel_invariants (Summarize_history { summary_prefix = "SUM" }) heterogeneous_msgs res_sum;
  assert_bool "summarize heterogeneous count 2" (res_sum.compressed_count = 2);
  assert_bool "sys header preserved first in summarize" (List.hd res_sum.compressed_messages = sys_msg)

(* 5. compress function: Hygiene, Field Filtering, UTF-8 Sanitization *)
let test_compress_hygiene_and_thought_stripping () =
  let extra_fields_msg = `Assoc [
    ("role", `String "assistant");
    ("_private_metadata", `String "secret");
    ("tool_name", `String "foo");
    ("content", `String "normal content");
    ("tool_calls", `List [
      `Assoc [
        ("id", `String "call_1");
        ("extra_content", `String "thought signature");
        ("function", `Assoc [ ("name", `String "test") ]);
      ]
    ]);
  ] in
  let bad_utf8_msg = `Assoc [
    ("role", `String "user");
    ("content", `String "invalid surrogate \237\160\128 here");
  ] in
  let msgs = [ extra_fields_msg; bad_utf8_msg ] in

  (* Test for model that strips extra_content (e.g. claude-3-5-sonnet) *)
  let res = Context_compression.compress ~model_id:"claude-3-5-sonnet" ~messages:msgs in
  (match res with
  | `Assoc fields ->
      assert_bool "compress model matches" (List.assoc_opt "model" fields = Some (`String "claude-3-5-sonnet"));
      (match List.assoc_opt "messages" fields with
      | Some (`List [ `Assoc m1; `Assoc m2 ]) ->
          assert_bool "private_metadata field stripped" (not (List.mem_assoc "_private_metadata" m1));
          assert_bool "tool_name field stripped" (not (List.mem_assoc "tool_name" m1));
          assert_bool "content field preserved" (List.assoc_opt "content" m1 = Some (`String "normal content"));
          (match List.assoc_opt "tool_calls" m1 with
          | Some (`List [ `Assoc tc1 ]) ->
              assert_bool "extra_content stripped for non-gemini model" (not (List.mem_assoc "extra_content" tc1))
          | _ -> assert_bool "tool_calls structure" false);
          let c2 = List.assoc_opt "content" m2 in
          assert_bool "bad utf8 replaced in compress" (c2 = Some (`String "invalid surrogate \239\191\189 here"))
      | _ -> assert_bool "compress sanitized messages output" false)
  | _ -> assert_bool "compress assoc output" false);

  (* Test for model that keeps extra_content (e.g. google/gemini-2.0-flash) *)
  let res_gemini = Context_compression.compress ~model_id:"google/gemini-2.0-flash" ~messages:[ extra_fields_msg ] in
  (match res_gemini with
  | `Assoc fields ->
      (match List.assoc_opt "messages" fields with
      | Some (`List [ `Assoc m1 ]) ->
          (match List.assoc_opt "tool_calls" m1 with
          | Some (`List [ `Assoc tc1 ]) ->
              assert_bool "extra_content preserved for gemini model" (List.mem_assoc "extra_content" tc1)
          | _ -> assert_bool "gemini tool_calls structure" false)
      | _ -> assert_bool "gemini messages output" false)
  | _ -> assert_bool "gemini assoc output" false)

let () =
  Printf.printf "=== Running stress_test_context_compression ===\n";
  test_keep_last_n_boundaries ();
  test_summarization_turn_limits ();
  test_system_header_extreme_truncation ();
  test_prompt_caching_and_malformed_json ();
  test_compress_hygiene_and_thought_stripping ();
  Printf.printf "=== ALL STRESS TESTS PASSED CLEANLY (ZERO CRASHES) ===\n"

open Lmstudio_intent
open Lmstudio_monitor

let test_contains_sub () =
  print_endline "=== Test 1: LM Studio contains_sub helper ===";
  assert (contains_sub "hello VRAM world" "VRAM");
  assert (contains_sub "context window exceeded" "context");
  assert (not (contains_sub "normal logs here" "VRAM"));
  assert (not (contains_sub "normal logs here" "context"));
  print_endline "  [PASS] contains_sub verified."

let test_parse_log_line () =
  print_endline "\n=== Test 2: LM Studio parse_log_line ===";
  
  (* VRAM error *)
  (match parse_log_line "Error: Out of VRAM limit!" with
   | Some (Crash_Fault "Out of VRAM") -> ()
   | _ -> assert false);

  (* Context error *)
  (match parse_log_line "Failed: context window overflow!" with
   | Some (Crash_Fault "Context Window Overflow") -> ()
   | _ -> assert false);

  (* Normal Loaded *)
  (match parse_log_line "Model Loaded successfully" with
   | Some (Active "Gemma-4-E4B") -> ()
   | _ -> assert false);

  (* Normal Unloaded *)
  (match parse_log_line "Model Unloaded successfully" with
   | Some (Unloaded "Gemma-4-E4B") -> ()
   | _ -> assert false);

  (* No match *)
  (match parse_log_line "Normal query processed" with
   | None -> ()
   | _ -> assert false);
   
  print_endline "  [PASS] parse_log_line verified."

let test_synthesize_curl_command () =
  print_endline "\n=== Test 3: LM Studio synthesize_curl_command ===";
  let env = default_gemma_4_envelope in
  let cmd = synthesize_curl_command env "Hello Gemma" in
  assert (contains_sub cmd "http://100.114.9.28:1234/v1/chat/completions");
  assert (contains_sub cmd "google/gemma-4-e4b");
  assert (contains_sub cmd "Hello Gemma");
  assert (contains_sub cmd "--max-time 30");
  print_endline "  [PASS] synthesize_curl_command verified."

let test_history_survives_reopen () =
  print_endline "\n=== Test 4: LM Studio append-only history ===";
  let path = Filename.temp_file "lmstudio-history-" ".sqlite" in
  Sys.remove path;
  Fun.protect
    ~finally:(fun () ->
      List.iter
        (fun candidate ->
          try if Sys.file_exists candidate then Sys.remove candidate
          with Sys_error _ -> ())
        [ path; path ^ "-journal"; path ^ "-wal"; path ^ "-shm" ])
    (fun () ->
      let first = match Lmstudio_db.init_db path with Ok db -> db | Error e -> failwith e in
      assert
        (Result.is_ok
           (Lmstudio_db.log_transaction first "persist-marker" 1 "prompt" "response"
              1.0 true true "verified" "/v1/chat/completions" "model" "curl"
              "INFO" 0.0 1 "Zero_Shot" ""));
      Lmstudio_db.close_db first;
      let reopened =
        match Lmstudio_db.init_db path with Ok db -> db | Error e -> failwith e
      in
      let out = Buffer.create 256 in
      Lmstudio_db.print_history reopened out;
      Lmstudio_db.close_db reopened;
      assert (contains_sub (Buffer.contents out) "persist-marker"));
  print_endline "  [PASS] history survives reopen."

let () =
  test_contains_sub ();
  test_parse_log_line ();
  test_history_survives_reopen ();
  test_synthesize_curl_command ();
  print_endline "\nAll LM Studio unit tests passed successfully.";
  let self =
    Suite_telemetry.observe ~suite:"test_lmstudio_monitor" ~passed:1 ~failed:0
      ~skipped:0
  in
  print_string (Suite_telemetry.emit self ~targets:[ Stanza.hermes_harness_sop_execution; Stanza.hermes_harness_swarm_algebra ]);
  exit (Suite_telemetry.exit_code self)

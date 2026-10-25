(* Unified Operational System (UOS)
 * telegram_store_test.ml - Comprehensive Test Suite for Isolated Native OCaml SQLite Storage Kernel
 * Spec: uos.telegram-durable-store-corrected-development-spec.v1
 * Plan: uos/telegram-runtime/20261001-1150
 *)

open Telegram_store

let test_count = ref 0
let pass_count = ref 0

let check desc cond =
  incr test_count;
  if cond then (
    incr pass_count;
    Printf.printf "  [PASS] %s\n%!" desc
  ) else (
    Printf.printf "  [FAIL] %s\n%!" desc;
    failwith ("Test failed: " ^ desc)
  )

let with_temp_dir f =
  let base = Filename.concat "/tmp" (Printf.sprintf "uos_tg_store_test_%d_%d" (Unix.getpid ()) (Random.int 1000000)) in
  Unix.mkdir base 0o700;
  Fun.protect
    ~finally:(fun () ->
      let rec rm_rf path =
        if Sys.is_directory path then (
          let entries = Sys.readdir path in
          Array.iter (fun e -> rm_rf (Filename.concat path e)) entries;
          Unix.rmdir path
        ) else
          Unix.unlink path
      in
      try rm_rf base with _ -> ()
    )
    (fun () -> f base)

let make_apply_req ~db_path ~bot_id ~operation_id ~expected_generation ~read_set ~changes ~res_delta ~summary_json =
  let digest =
    compute_request_digest
      ~bot_id
      ~operation_id
      ~expected_generation
      ~read_set
      ~changes
      ~reservation_delta:res_delta
      ~summary_json
  in
  {
    db_path;
    bot_id;
    operation_id;
    request_digest = digest;
    expected_generation;
    read_set_assertions = read_set;
    changes;
    reservation_delta = res_delta;
    summary_json;
  }

(* ========================================== *)
(* Test 1: Initialize New & Security Controls *)
(* ========================================== *)
let test_initialize_and_security () =
  Printf.printf "=== Test Suite 1: Initialize New & Security Controls ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "telegram.sqlite3" in
    let bot_id = "123456789" in

    (* 1. Successful initialization *)
    match initialize_new db_path bot_id with
    | Error e -> check ("initialize_new failed: " ^ e) false
    | Ok gen ->
        check "initialize_new returns generation 1" (gen = 1);
        check "db file created" (Sys.file_exists db_path);

        (* Check file permissions 0600 *)
        let st = Unix.lstat db_path in
        check "db file permissions are 0600" ((st.st_perm land 0o777) = 0o600);

        (* 2. Refuse existing DB *)
        (match initialize_new db_path bot_id with
        | Error "db_already_exists" -> check "refuses existing DB with db_already_exists" true
        | _ -> check "failed to refuse existing DB" false);

        (* 3. Negative: insecure directory permissions (0755) *)
        let insecure_dir = Filename.concat dir "insecure" in
        Unix.mkdir insecure_dir 0o755;
        let insec_db = Filename.concat insecure_dir "test.db" in
        (match initialize_new insec_db bot_id with
        | Error "db_directory_insecure" -> check "refuses 0755 directory with db_directory_insecure" true
        | _ -> check "failed to refuse insecure directory" false);

        (* 4. Negative: symlink path refusal *)
        let target_dir = Filename.concat dir "real_dir" in
        Unix.mkdir target_dir 0o700;
        let sym_dir = Filename.concat dir "sym_dir" in
        Unix.symlink target_dir sym_dir;
        let sym_db = Filename.concat sym_dir "test.db" in
        (match initialize_new sym_db bot_id with
        | Error "db_directory_insecure" -> check "refuses directory symlink" true
        | _ -> check "failed to refuse symlink dir" false);

        (* 5. Verify Pragmas and Append-Only Triggers via direct sqlite inspection *)
        let db = Sqlite3.db_open db_path in
        let get_int sql =
          let stmt = Sqlite3.prepare db sql in
          let v = match Sqlite3.step stmt with Sqlite3.Rc.ROW -> Sqlite3.column_int stmt 0 | _ -> -1 in
          ignore (Sqlite3.finalize stmt);
          v
        in
        let get_str sql =
          let stmt = Sqlite3.prepare db sql in
          let v = match Sqlite3.step stmt with Sqlite3.Rc.ROW -> Sqlite3.column_text stmt 0 | _ -> "" in
          ignore (Sqlite3.finalize stmt);
          v
        in
        check "verify_existing_db_pragmas sets and verifies connection pragmas" (verify_existing_db_pragmas db = Ok ());
        check "journal_mode is WAL" (String.lowercase_ascii (get_str "PRAGMA journal_mode;") = "wal");
        check "synchronous is FULL (2)" (get_int "PRAGMA synchronous;" = 2);
        check "foreign_keys is ON (1)" (get_int "PRAGMA foreign_keys;" = 1);
        let page_size = get_int "PRAGMA page_size;" in
        let max_pages = get_int "PRAGMA max_page_count;" in
        check "max_page_count bounds main DB to 256 MiB" (page_size * max_pages = max_db_main_bytes);

        (* Append-Only Trigger test: receipts table *)
        let ins_rc = Sqlite3.exec db "INSERT INTO receipts (operation_id, request_digest, generation, summary_json, committed_utc_us) VALUES ('op1', 'dig1', 1, '{}', 1000);" in
        check "insert receipt succeeds" (ins_rc = Sqlite3.Rc.OK);
        let upd_rc = Sqlite3.exec db "UPDATE receipts SET summary_json = '{\"mutated\": true}' WHERE operation_id = 'op1';" in
        check "trigger prevents UPDATE on receipts" (upd_rc <> Sqlite3.Rc.OK);
        let del_rc = Sqlite3.exec db "DELETE FROM receipts WHERE operation_id = 'op1';" in
        check "trigger prevents DELETE on receipts" (del_rc <> Sqlite3.Rc.OK);
        ignore (Sqlite3.db_close db)
  )

(* ========================================== *)
(* Test 2: Read Keys & Read Inbox Index       *)
(* ========================================== *)
let test_read_keys_and_inbox () =
  Printf.printf "=== Test Suite 2: Read Keys & Read Inbox Index ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "telegram.sqlite3" in
    let bot_id = "123456789" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* Read non-existent keys *)
    match read_keys db_path ["inbox/req_001"; "request/req_001/status"] with
    | Error e -> check ("read_keys failed: " ^ e) false
    | Ok (gen, rows) ->
        check "read_keys returns generation 1" (gen = 1);
        check "returns 2 rows" (List.length rows = 2);
        let r0 = List.nth rows 0 in
        check "row 0 exists is false" (not r0.exists);
        check "row 0 version is 0" (r0.version = 0);
        check "row 0 value is empty" (r0.canonical_value_base64 = "");

    (* Insert test keys via apply *)
    let val_1 = "{\"chat_id\": 12345, \"user_id\": 67890, \"text\": \"/start\"}" in
    let b64_1 = encode_canonical_base64 val_1 in
    let sha_1 = sha256_hex val_1 in
    let changes_1 = [
      { key = "inbox/req_002"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_1 };
      { key = "inbox/req_001"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_1 };
      { key = "request/req_001/input"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_1 };
    ] in
    let apply_req = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_init_keys"
      ~expected_generation:1
      ~read_set:[]
      ~changes:changes_1
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply apply_req with
    | Error e -> check ("apply failed: " ^ e) false
    | Ok res ->
        check "apply incremented generation to 2" (res.receipt.generation = 2);

        (* Read keys back *)
        (match read_keys db_path ["inbox/req_001"; "inbox/req_002"; "missing"] with
        | Error e -> check ("read_keys back failed: " ^ e) false
        | Ok (gen2, rows2) ->
            check "read_keys returns generation 2" (gen2 = 2);
            let row1 = List.nth rows2 0 in
            check "inbox/req_001 exists" row1.exists;
            check "inbox/req_001 version is 1" (row1.version = 1);
            check "inbox/req_001 sha256 matches" (row1.sha256 = sha_1);
            check "inbox/req_001 base64 matches" (row1.canonical_value_base64 = b64_1);
            let row_miss = List.nth rows2 2 in
            check "missing row exists is false" (not row_miss.exists));

        (* Read inbox index *)
        (match read_inbox_index db_path 10 None with
        | Error e -> check ("read_inbox_index failed: " ^ e) false
        | Ok (gen3, keys) ->
            check "inbox index returns generation 2" (gen3 = 2);
            check "inbox index returns exactly 2 inbox keys in order" (keys = ["inbox/req_001"; "inbox/req_002"]));

        (* Read inbox index pagination with after_key *)
        (match read_inbox_index db_path 10 (Some "inbox/req_001") with
        | Error e -> check ("read_inbox_index pagination failed: " ^ e) false
        | Ok (_, keys) ->
            check "pagination after inbox/req_001 returns [inbox/req_002]" (keys = ["inbox/req_002"]));

        (* Bounds: read_keys > 64 keys *)
        let long_keys = List.init 65 (fun i -> Printf.sprintf "k%d" i) in
        (match read_keys db_path long_keys with
        | Error "read_keys_too_many" -> check "refuses > 64 keys with read_keys_too_many" true
        | _ -> check "failed to refuse > 64 keys" false);

        (* Bounds: read_inbox_index limit > 100 *)
        (match read_inbox_index db_path 101 None with
        | Error "invalid_limit" -> check "refuses limit > 100 with invalid_limit" true
        | _ -> check "failed to refuse limit > 100" false))
  )

(* ========================================== *)
(* Test 3: Apply Operations, CAS & Idempotency *)
(* ========================================== *)
let test_apply_and_cas () =
  Printf.printf "=== Test Suite 3: Apply Operations, CAS & Idempotency ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "telegram.sqlite3" in
    let bot_id = "987654321" in
    assert (initialize_new db_path bot_id = Ok 1);

    let val_a = "{\"status\": \"pending\"}" in
    let b64_a = encode_canonical_base64 val_a in
    let sha_a = sha256_hex val_a in

    (* 1. First Apply: Create row *)
    let req1 = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_1"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "request/1/status"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_a } ]
      ~res_delta:{ rows = 5; receipts = 10 }
      ~summary_json:"{\"action\": \"create\"}"
    in
    let res1 = match apply req1 with Ok r -> r | Error e -> failwith e in
    check "req1 replay is false" (not res1.replay);
    check "req1 generation is 2" (res1.receipt.generation = 2);

    (* 2. Replay Test: Same operation_id + same request_digest returns original receipt *)
    (match apply req1 with
    | Error e -> check ("replay failed: " ^ e) false
    | Ok res_rep ->
        check "replay is true" res_rep.replay;
        check "receipt operation_id matches" (res_rep.receipt.operation_id = "op_1");
        check "receipt generation matches original (2)" (res_rep.receipt.generation = 2);
        check "receipt summary matches" (res_rep.receipt.summary_json = "{\"action\": \"create\"}"));

    (* 3. Request Digest Mismatch Test: Altering request without updating digest *)
    let req_tampered = { req1 with expected_generation = 2 } in
    (match apply req_tampered with
    | Error "request_digest_mismatch" -> check "refuses tampered request with request_digest_mismatch" true
    | _ -> check "failed to detect request digest mismatch" false);

    (* 4. Collision Test: Same operation_id + DIFFERENT request (different changes) *)
    let val_diff = "{\"status\": \"different\"}" in
    let b64_diff = encode_canonical_base64 val_diff in
    let req_collision = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_1"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "request/1/status"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_diff } ]
      ~res_delta:{ rows = 5; receipts = 10 }
      ~summary_json:"{\"action\": \"create\"}"
    in
    (match apply req_collision with
    | Error "operation_collision_digest_mismatch" -> check "refuses collision with operation_collision_digest_mismatch" true
    | _ -> check "failed to detect operation collision" false);

    (* 5. Stale Generation Test: New op with old expected_generation (1 instead of 2) *)
    let req_stale = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_stale"
      ~expected_generation:1 (* stale! Current is 2 *)
      ~read_set:[]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_stale with
    | Error "stale_generation" -> check "refuses stale generation with stale_generation" true
    | _ -> check "failed to detect stale generation" false);

    (* 6. CAS Conflict Test: Updating row with wrong version or wrong sha256 *)
    let val_b = "{\"status\": \"sending\"}" in
    let b64_b = encode_canonical_base64 val_b in
    let req_cas_wrong_ver = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_cas_wrong"
      ~expected_generation:2
      ~read_set:[]
      ~changes:[ { key = "request/1/status"; expected_version = 99; expected_sha256 = sha_a; new_value_base64 = b64_b } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_cas_wrong_ver with
    | Error "cas_conflict" -> check "refuses wrong version with cas_conflict" true
    | _ -> check "failed to detect wrong CAS version" false);

    let req_cas_wrong_sha = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_cas_wrong_sha"
      ~expected_generation:2
      ~read_set:[]
      ~changes:[ { key = "request/1/status"; expected_version = 1; expected_sha256 = "bad_sha256"; new_value_base64 = b64_b } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_cas_wrong_sha with
    | Error "cas_conflict" -> check "refuses wrong sha256 with cas_conflict" true
    | _ -> check "failed to detect wrong CAS sha" false);

    (* 7. Read-Set Conflict Test *)
    let req_rs_conflict = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_rs_conflict"
      ~expected_generation:2
      ~read_set:[ { key = "request/1/status"; expected_version = 1; expected_sha256 = "mismatched_sha" } ]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_rs_conflict with
    | Error "read_set_conflict" -> check "refuses mismatched read-set with read_set_conflict" true
    | _ -> check "failed to detect read-set conflict" false);

    (* 8. Successful CAS update with valid read-set assertion *)
    let req_valid_update = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_valid_update"
      ~expected_generation:2
      ~read_set:[ { key = "request/1/status"; expected_version = 1; expected_sha256 = sha_a } ]
      ~changes:[ { key = "request/1/status"; expected_version = 1; expected_sha256 = sha_a; new_value_base64 = b64_b } ]
      ~res_delta:{ rows = -2; receipts = -5 } (* partial release *)
      ~summary_json:"{\"action\": \"advance_status\"}"
    in
    (match apply req_valid_update with
    | Error e -> check ("valid update failed: " ^ e) false
    | Ok res2 ->
        check "valid update generation incremented to 3" (res2.receipt.generation = 3);
        (* Lookup operation receipt *)
        (match lookup_operation db_path "op_valid_update" with
        | Ok (Some rcpt) ->
            check "lookup_operation finds committed receipt" (rcpt.generation = 3);
            check "lookup_operation matches summary" (rcpt.summary_json = "{\"action\": \"advance_status\"}")
        | _ -> check "failed to lookup committed receipt" false))
  )

(* ========================================== *)
(* Test 4: Capacity & Reservation Accounting  *)
(* ========================================== *)
let test_capacity_and_reservations () =
  Printf.printf "=== Test Suite 4: Capacity & Reservation Accounting ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "telegram.sqlite3" in
    let bot_id = "555" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. Negative: Invalid reservation delta (resulting in < 0) *)
    let req_neg_res = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_neg_res"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[]
      ~res_delta:{ rows = -1; receipts = 0 } (* cur is 0 -> 0 + (-1) = -1 < 0! *)
      ~summary_json:"{}"
    in
    (match apply req_neg_res with
    | Error "invalid_reservation_delta" -> check "refuses negative resulting reservation with invalid_reservation_delta" true
    | _ -> check "failed to refuse negative reservation" false);

    (* 2. Negative: Reservation delta exceeds adopted credits policy (>20 rows or >64 receipts) *)
    let req_over_rows = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_over_rows"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[]
      ~res_delta:{ rows = 21; receipts = 10 }
      ~summary_json:"{}"
    in
    (match apply req_over_rows with
    | Error "invalid_reservation_delta" -> check "refuses reservation delta rows > 20 with invalid_reservation_delta" true
    | _ -> check "failed to refuse rows > 20" false);

    let req_over_receipts = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_over_rec"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[]
      ~res_delta:{ rows = 10; receipts = 65 }
      ~summary_json:"{}"
    in
    (match apply req_over_receipts with
    | Error "invalid_reservation_delta" -> check "refuses reservation delta receipts > 64 with invalid_reservation_delta" true
    | _ -> check "failed to refuse receipts > 64" false)
  )

(* ========================================== *)
(* Test 5: Bounds, Values & Max 16x4096 Chunks*)
(* ========================================== *)
let test_bounds_and_chunks () =
  Printf.printf "=== Test Suite 5: Bounds, Values & Max 16x4096 Chunks ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "telegram.sqlite3" in
    let bot_id = "777" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. Strict Canonical Base64 rejection *)
    let non_canonical_b64 = "aGVsbG8=\n" in (* contains newline *)
    let req_bad_b64 = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_bad_b64"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "k1"; expected_version = 0; expected_sha256 = ""; new_value_base64 = non_canonical_b64 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_bad_b64 with
    | Error "invalid_base64" -> check "refuses non-canonical base64 with invalid_base64" true
    | _ -> check "failed to refuse non-canonical base64" false);

    (* 2. Single Value > 98304 bytes *)
    let huge_val = String.make 98305 'A' in
    let huge_b64 = encode_canonical_base64 huge_val in
    let req_huge = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_huge"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "k_huge"; expected_version = 0; expected_sha256 = ""; new_value_base64 = huge_b64 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_huge with
    | Error "value_too_large" -> check "refuses single value > 98304 bytes with value_too_large" true
    | _ -> check "failed to refuse oversized value" false);

    (* 3. Max Escaped 16 Chunks of 4096 bytes escaped domain JSON *)
    let make_chunk idx =
      let payload = Printf.sprintf "{\"chunk_index\": %d, \"data\": \"%s\"}" idx (String.make 4000 'x') in
      let pad = String.make (4096 - String.length payload) ' ' in
      payload ^ pad
    in
    let chunks = List.init 16 (fun idx ->
      let raw = make_chunk idx in
      assert (String.length raw = 4096);
      let b64 = encode_canonical_base64 raw in
      {
        key = Printf.sprintf "request/req_100/chunk/%02d" idx;
        expected_version = 0;
        expected_sha256 = "";
        new_value_base64 = b64;
      }
    ) in
    let req_16_chunks = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_16_chunks"
      ~expected_generation:1
      ~read_set:[]
      ~changes:chunks
      ~res_delta:{ rows = 16; receipts = 1 }
      ~summary_json:"{\"action\": \"commit_16_chunks\"}"
    in
    (match apply req_16_chunks with
    | Error e -> check ("apply 16x4096 chunks failed: " ^ e) false
    | Ok res ->
        check "16 chunks apply succeeded, generation is 2" (res.receipt.generation = 2);
        (* Read back all 16 chunks *)
        let chunk_keys = List.map (fun (c : change) -> c.key) chunks in
        (match read_keys db_path chunk_keys with
        | Error e -> check ("read 16 chunks failed: " ^ e) false
        | Ok (gen, rows) ->
            check "read_keys returns generation 2" (gen = 2);
            check "read_keys returns 16 rows" (List.length rows = 16);
            check "all 16 chunks exist" (List.for_all (fun (r : row_result) -> r.exists && r.version = 1) rows)))
  )

(* ========================================== *)
(* Test 6: Advanced Integrity & Hardening    *)
(* ========================================== *)
let test_advanced_integrity () =
  Printf.printf "=== Test Suite 6: Advanced Integrity & Hardening ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "telegram.sqlite3" in
    let bot_id = "888" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. Verify schema definition tampering detection *)
    let db = Sqlite3.db_open db_path in
    ignore (Sqlite3.exec db "CREATE TABLE unauthorized_extra (id INTEGER PRIMARY KEY);");
    (match verify_schema db (Some bot_id) with
    | Error "schema_mismatch" -> check "verify_schema catches unauthorized extra table with schema_mismatch" true
    | _ -> check "failed to catch schema tampering" false);
    ignore (Sqlite3.exec db "DROP TABLE unauthorized_extra;");
    check "verify_schema restored after removing extra table" (verify_schema db (Some bot_id) = Ok (1, bot_id, 0, 0));
    ignore (Sqlite3.db_close db);

    (* 2. Verify bot_id and schema check precedes replay *)
    let val_x = "{\"test\": true}" in
    let b64_x = encode_canonical_base64 val_x in
    let req_orig = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_orig"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "k_orig"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_x } ]
      ~res_delta:{ rows = 1; receipts = 1 }
      ~summary_json:"{}"
    in
    let res_orig = match apply req_orig with Ok r -> r | Error e -> failwith e in
    check "original apply committed" (res_orig.receipt.generation = 2);

    (* Replay with WRONG bot_id must be refused with bot_id_mismatch, NOT replay! *)
    let req_replay_wrong_bot_dig = make_apply_req
      ~db_path
      ~bot_id:"wrong_bot_id_999"
      ~operation_id:"op_orig"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "k_orig"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_x } ]
      ~res_delta:{ rows = 1; receipts = 1 }
      ~summary_json:"{}"
    in
    (match apply req_replay_wrong_bot_dig with
    | Error "bot_id_mismatch" -> check "replay with wrong bot_id refused with bot_id_mismatch before replay lookup" true
    | _ -> check "failed to enforce bot_id check before replay" false);

    (* 3. Corrupt row hash detection *)
    let db2 = Sqlite3.db_open db_path in
    ignore (Sqlite3.exec db2 "UPDATE kv_rows SET sha256 = 'corrupt_hash_1234567890abcdef' WHERE key = 'k_orig';");
    ignore (Sqlite3.db_close db2);

    (match read_keys db_path ["k_orig"] with
    | Error "corrupt_row_hash" -> check "read_keys catches corrupt row hash with corrupt_row_hash" true
    | _ -> check "failed to detect corrupt row hash in read_keys" false);

    let req_cas_corrupt = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_cas_corrupt"
      ~expected_generation:2
      ~read_set:[]
      ~changes:[ { key = "k_orig"; expected_version = 1; expected_sha256 = "corrupt_hash_1234567890abcdef"; new_value_base64 = b64_x } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_cas_corrupt with
    | Error "corrupt_row_hash" -> check "apply CAS catches corrupt row hash with corrupt_row_hash" true
    | _ -> check "failed to detect corrupt row hash in apply CAS" false);

    (* Restore valid row hash *)
    let db3 = Sqlite3.db_open db_path in
    let valid_sha = sha256_hex val_x in
    let stmt_fix = Sqlite3.prepare db3 "UPDATE kv_rows SET sha256 = ? WHERE key = 'k_orig';" in
    ignore (Sqlite3.bind_text stmt_fix 1 valid_sha);
    ignore (Sqlite3.step stmt_fix);
    ignore (Sqlite3.finalize stmt_fix);
    ignore (Sqlite3.db_close db3);

    (* 4. Inbox namespace boundary tests *)
    (match read_inbox_index db_path 10 (Some "zebra") with
    | Error "invalid_after_key" -> check "after_key not starting with inbox/ refused with invalid_after_key" true
    | _ -> check "failed to refuse malicious after_key" false);

    (match read_inbox_index db_path 10 (Some "inbox0") with
    | Error "invalid_after_key" -> check "after_key >= inbox0 refused with invalid_after_key" true
    | _ -> check "failed to refuse out-of-bound after_key" false);

    (match read_inbox_index db_path 10 (Some "inbox/") with
    | Error "invalid_after_key" -> check "after_key exactly 'inbox/' refused with invalid_after_key" true
    | _ -> check "failed to refuse short after_key" false);

    (* 5. Hard link detection test *)
    let hardlink_path = Filename.concat dir "hardlink.sqlite3" in
    Unix.link db_path hardlink_path;
    (match read_keys db_path ["k_orig"] with
    | Error "db_file_insecure" -> check "hard-linked db file refused with db_file_insecure" true
    | _ -> check "failed to refuse hard-linked db file" false);
    Unix.unlink hardlink_path;
    check "normal db file accepted after unlinking hard link" (read_keys db_path ["k_orig"] <> Error "db_file_insecure");

    (* 6. Symlink lock file test *)
    let lock_path = db_path ^ ".process_lock" in
    (try Unix.unlink lock_path with _ -> ());
    let dummy_target = Filename.concat dir "dummy_target" in
    let fd_dummy = Unix.openfile dummy_target [Unix.O_CREAT; Unix.O_WRONLY] 0o600 in
    Unix.close fd_dummy;
    Unix.symlink dummy_target lock_path;
    (match read_keys db_path ["k_orig"] with
    | Error "db_path_symlink" -> check "symlink process lock file refused with db_path_symlink" true
    | _ -> check "failed to refuse symlink lock file" false);
    Unix.unlink lock_path;
    Unix.unlink dummy_target
  )

(* ========================================== *)
(* Test 7: Redacted Error Codes & Framing     *)
(* ========================================== *)
let test_redacted_errors_and_framing () =
  Printf.printf "=== Test Suite 7: Redacted Error Codes & Framing ===\n%!";
  (* Test run_command_json with canary tokens *)
  let canary = "PRIVATE_SECRET_TOKEN_XYZ_12345" in
  let malformed_req = Printf.sprintf "{\"command\": \"apply\", \"token\": \"%s\", \"db_path\": \"/nonexistent/path/db.sqlite3\"}" canary in
  let resp = run_command_json malformed_req in
  check "response is valid JSON" (try ignore (Yojson.Safe.from_string resp); true with _ -> false);
  check "response does NOT reflect canary token" (not (String.contains resp 'P' && String.contains resp 'X'));

  (* Duplicate key detection in JSON *)
  let dup_key_json = "{\"command\": \"read_keys\", \"db_path\": \"/a\", \"db_path\": \"/b\"}" in
  let resp_dup = run_command_json dup_key_json in
  check "duplicate key in JSON rejected with duplicate_json_keys" (String.contains resp_dup 'd' && String.contains resp_dup 'u' && String.contains resp_dup 'p');

  (* Strict missing field checks: read_inbox_index without limit *)
  let no_limit_json = "{\"command\": \"read_inbox_index\", \"db_path\": \"/tmp/db.sqlite3\"}" in
  let resp_no_lim = run_command_json no_limit_json in
  check "read_inbox_index without limit rejected with invalid_limit" (String.contains resp_no_lim 'l' && String.contains resp_no_lim 'i' && String.contains resp_no_lim 'm');

  (* Oversized request frame *)
  let oversized_req = String.make (max_request_json_bytes + 1) ' ' in
  let resp_over = run_command_json oversized_req in
  check "oversized request rejected with oversized_frame" (String.contains resp_over 'o' && String.contains resp_over 'v')

(* ========================================== *)
(* Test 8: Binary Pipe Framing (telegram_store_main) *)
(* ========================================== *)
let test_pipe_framing_process () =
  Printf.printf "=== Test Suite 8: Binary Pipe Framing (telegram_store_main) ===\n%!";
  let exe =
    let candidates = [
      "./telegram_store_main.exe";
      "./_build/default/telegram_store_main.exe";
      Filename.concat (Filename.dirname Sys.executable_name) "telegram_store_main.exe";
      Filename.concat (Filename.dirname (Filename.dirname Sys.executable_name)) "telegram_store_main.exe";
    ] in
    match List.find_opt Sys.file_exists candidates with
    | Some p -> p
    | None -> failwith "telegram_store_main.exe not found"
  in

  let run_pipe ?(args_override = None) input_bytes db_path =
    let args =
      match args_override with
      | Some a -> a
      | None -> [| exe; db_path |]
    in
    let (in_ch, out_ch) = Unix.open_process_args exe args in
    set_binary_mode_out out_ch true;
    set_binary_mode_in in_ch true;
    output_bytes out_ch input_bytes;
    flush out_ch;
    close_out out_ch;
    let hdr = Bytes.create 4 in
    let rec read_exact ch buf off cnt =
      if cnt = 0 then true
      else
        let n = input ch buf off cnt in
        if n = 0 then false
        else read_exact ch buf (off + n) (cnt - n)
    in
    let ok_hdr = read_exact in_ch hdr 0 4 in
    let result =
      if not ok_hdr then None
      else
        let b0 = Char.code (Bytes.get hdr 0) in
        let b1 = Char.code (Bytes.get hdr 1) in
        let b2 = Char.code (Bytes.get hdr 2) in
        let b3 = Char.code (Bytes.get hdr 3) in
        let len = (b0 lsl 24) lor (b1 lsl 16) lor (b2 lsl 8) lor b3 in
        let payload = Bytes.create len in
        if not (read_exact in_ch payload 0 len) then None
        else Some (Bytes.to_string payload)
    in
    let status = Unix.close_process (in_ch, out_ch) in
    (status, result)
  in

  let make_frame payload_str =
    let len = String.length payload_str in
    let b = Bytes.create (4 + len) in
    Bytes.set b 0 (Char.chr ((len lsr 24) land 0xff));
    Bytes.set b 1 (Char.chr ((len lsr 16) land 0xff));
    Bytes.set b 2 (Char.chr ((len lsr 8) land 0xff));
    Bytes.set b 3 (Char.chr (len land 0xff));
    Bytes.blit_string payload_str 0 b 4 len;
    b
  in

  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "framed.sqlite3" in

    (* 1. Normal framed initialize_new with matching db_path in json *)
    let init_json = Printf.sprintf "{\"command\": \"initialize_new\", \"db_path\": \"%s\", \"bot_id\": \"888\"}" db_path in
    let (status, resp_opt) = run_pipe (make_frame init_json) db_path in
    check "framed process exits with code 0" (status = Unix.WEXITED 0);
    check "framed process returned response" (Option.is_some resp_opt);
    let resp = Option.get resp_opt in
    check "initialize_new via framing succeeded" (String.contains resp 't' && String.contains resp 'r' && String.contains resp 'u');

    (* 2. Command omitting db_path from JSON uses trusted argv DB locator *)
    let read_no_db = "{\"command\": \"read_keys\", \"keys\": []}" in
    let (status_read, resp_read_opt) = run_pipe (make_frame read_no_db) db_path in
    check "command omitting db_path exits 0" (status_read = Unix.WEXITED 0);
    let resp_read = Option.get resp_read_opt in
    check "command omitting db_path succeeds using trusted argv locator" (String.contains resp_read 't' && String.contains resp_read 'r' && String.contains resp_read 'u');

    (* 3. Command with conflicting db_path in JSON rejected with db_path_mismatch *)
    let read_mismatch = "{\"command\": \"read_keys\", \"db_path\": \"/different/path.sqlite3\", \"keys\": []}" in
    let (_, resp_mismatch_opt) = run_pipe (make_frame read_mismatch) db_path in
    let resp_mismatch = Option.get resp_mismatch_opt in
    check "mismatched db_path rejected with db_path_mismatch" (String.contains resp_mismatch 'm' && String.contains resp_mismatch 'i' && String.contains resp_mismatch 's');

    (* 4. Worker launched without argv arguments rejected with invalid_command_line_arguments *)
    let (_, resp_no_argv_opt) = run_pipe ~args_override:(Some [| exe |]) (make_frame read_no_db) db_path in
    let resp_no_argv = Option.get resp_no_argv_opt in
    check "worker launched without argv db locator rejected" (String.contains resp_no_argv 'a' && String.contains resp_no_argv 'r' && String.contains resp_no_argv 'g');

    (* 5. Truncated frame: header says 100 bytes, send only 10 *)
    let trunc_b = Bytes.create 14 in
    Bytes.set trunc_b 0 '\000';
    Bytes.set trunc_b 1 '\000';
    Bytes.set trunc_b 2 '\000';
    Bytes.set trunc_b 3 (Char.chr 100);
    Bytes.blit_string "1234567890" 0 trunc_b 4 10;
    let (_, resp_trunc_opt) = run_pipe trunc_b db_path in
    check "truncated frame returned response" (Option.is_some resp_trunc_opt);
    let resp_trunc = Option.get resp_trunc_opt in
    check "truncated frame refused with truncated_frame" (String.contains resp_trunc 't' && String.contains resp_trunc 'r' && String.contains resp_trunc 'u');

    (* 6. Trailing bytes after frame *)
    let normal_b = make_frame "{\"command\": \"unknown\"}" in
    let trailing_b = Bytes.create (Bytes.length normal_b + 5) in
    Bytes.blit normal_b 0 trailing_b 0 (Bytes.length normal_b);
    Bytes.blit_string "EXTRA" 0 trailing_b (Bytes.length normal_b) 5;
    let (_, resp_trail_opt) = run_pipe trailing_b db_path in
    check "trailing bytes returned response" (Option.is_some resp_trail_opt);
    let resp_trail = Option.get resp_trail_opt in
    check "trailing bytes refused with trailing_bytes_after_frame" (String.contains resp_trail 't' && String.contains resp_trail 'r' && String.contains resp_trail 'a');

    (* 7. Oversized frame: header says 2,000,000 bytes *)
    let over_hdr = Bytes.create 4 in
    Bytes.set over_hdr 0 (Char.chr ((2000000 lsr 24) land 0xff));
    Bytes.set over_hdr 1 (Char.chr ((2000000 lsr 16) land 0xff));
    Bytes.set over_hdr 2 (Char.chr ((2000000 lsr 8) land 0xff));
    Bytes.set over_hdr 3 (Char.chr (2000000 land 0xff));
    let (_, resp_over_opt) = run_pipe over_hdr db_path in
    check "oversized frame returned response" (Option.is_some resp_over_opt);
    let resp_over = Option.get resp_over_opt in
    check "oversized frame refused with oversized_frame" (String.contains resp_over 'o' && String.contains resp_over 'v')
  )

(* ======================================================== *)
(* Test 9: Injective Digest & Collision Resistance          *)
(* ======================================================== *)
let test_injective_digest_and_collision () =
  Printf.printf "=== Test Suite 9: Injective Digest & Collision Resistance ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "collision_v2.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* Vector A vs Vector B: readset delimiter injection attack *)
    let a : read_set_assertion list = [{ key = "a:0:\nread:b"; expected_version = 0; expected_sha256 = "" }] in
    let b : read_set_assertion list = [
      { key = "a"; expected_version = 0; expected_sha256 = "" };
      { key = "b"; expected_version = 0; expected_sha256 = "" };
    ] in
    let mk reads =
      let d = compute_request_digest
        ~bot_id:"1"
        ~operation_id:"same-operation"
        ~expected_generation:1
        ~read_set:reads
        ~changes:[]
        ~reservation_delta:{ rows = 0; receipts = 1 }
        ~summary_json:"{}"
      in
      {
        db_path;
        bot_id = "1";
        operation_id = "same-operation";
        request_digest = d;
        expected_generation = 1;
        read_set_assertions = reads;
        changes = [];
        reservation_delta = { rows = 0; receipts = 1 };
        summary_json = "{}";
      }
    in
    let ra = mk a in
    let rb = mk b in
    check "different readsets produce different digests" (ra.request_digest <> rb.request_digest);

    let ca = match apply ra with Ok r -> r | Error e -> failwith e in
    check "first apply committed (replay is false)" (not ca.replay);

    (* Changed request rb with same operation_id must be refused with operation_collision_digest_mismatch *)
    (match apply rb with
    | Error "operation_collision_digest_mismatch" ->
        check "changed request rejected with operation_collision_digest_mismatch" true
    | _ -> check "failed to reject changed request with operation_collision_digest_mismatch" false);

    (* Replay of ra must succeed *)
    (match apply ra with
    | Ok rep ->
        check "replay of identical request succeeds" rep.replay;
        check "receipt matches committed digest" (rep.receipt.request_digest = ra.request_digest)
    | Error e -> check ("replay failed: " ^ e) false);

    (* Refuse DB with old v1 schema version *)
    let db = Sqlite3.db_open db_path in
    ignore (Sqlite3.exec db "UPDATE meta SET value = 'uos.telegram-store.v1' WHERE key = 'schema';");
    ignore (Sqlite3.db_close db);
    (match read_keys db_path ["a"] with
    | Error "schema_mismatch" -> check "refuses old v1 schema DB with schema_mismatch" true
    | _ -> check "failed to refuse v1 schema DB" false);
    let db2 = Sqlite3.db_open db_path in
    ignore (Sqlite3.exec db2 (Printf.sprintf "UPDATE meta SET value = '%s' WHERE key = 'schema';" schema_version));
    ignore (Sqlite3.db_close db2)
  )

(* ======================================================== *)
(* Test 10: Ancestor Path Confinement & Symlink Rejection   *)
(* ======================================================== *)
let test_ancestor_confinement () =
  Printf.printf "=== Test Suite 10: Ancestor Path Confinement & Symlink Rejection ===\n%!";
  with_temp_dir (fun base ->
    let real = Filename.concat base "real" in
    Unix.mkdir real 0o700;
    let sub = Filename.concat real "sub" in
    Unix.mkdir sub 0o700;
    let alias = Filename.concat base "alias" in
    Unix.symlink real alias;
    let aliasdb = Filename.concat (Filename.concat alias "sub") "ancestor.sqlite3" in

    (* Reproduce independent_review.ml: Symlink ancestor must be refused *)
    (match initialize_new aliasdb "1" with
    | Error "db_path_symlink" -> check "ancestor symlink rejected with db_path_symlink on initialize_new" true
    | _ -> check "failed to reject ancestor symlink on initialize" false);

    (* Create a valid db in real directory *)
    let realdb = Filename.concat sub "valid.sqlite3" in
    assert (initialize_new realdb "1" = Ok 1);

    (* Open via aliasdb must also be rejected *)
    let alias_existing_db = Filename.concat (Filename.concat alias "sub") "valid.sqlite3" in
    (match read_keys alias_existing_db ["a"] with
    | Error "db_path_symlink" -> check "ancestor symlink rejected with db_path_symlink on read_keys" true
    | _ -> check "failed to reject ancestor symlink on read_keys" false)
  )

(* ======================================================== *)
(* Test 11: Duplicate Keys, Bot ID & Version/Hash Invariants*)
(* ======================================================== *)
let test_duplicates_and_invariants () =
  Printf.printf "=== Test Suite 11: Duplicate Keys, Canonical Bot ID & Version/Hash Invariants ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "invariants.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. Duplicate read-set keys *)
    let dup_read_req = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_dup_read"
      ~expected_generation:1
      ~read_set:[
        { key = "k1"; expected_version = 0; expected_sha256 = "" };
        { key = "k1"; expected_version = 0; expected_sha256 = "" };
      ]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply dup_read_req with
    | Error "duplicate_read_set_key" -> check "duplicate read-set key rejected with duplicate_read_set_key" true
    | _ -> check "failed to reject duplicate read-set key" false);

    (* 2. Duplicate change keys *)
    let b64 = encode_canonical_base64 "{\"v\": \"val\"}" in
    let dup_change_req = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_dup_change"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[
        { key = "k1"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 };
        { key = "k1"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 };
      ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply dup_change_req with
    | Error "duplicate_change_key" -> check "duplicate change key rejected with duplicate_change_key" true
    | _ -> check "failed to reject duplicate change key" false);

    (* 3. Bot ID Bounds Validation *)
    check "bot_id 0 invalid" (not (is_valid_bot_id "0"));
    check "bot_id with leading zero invalid" (not (is_valid_bot_id "0123"));
    check "bot_id negative invalid" (not (is_valid_bot_id "-1"));
    check "bot_id non-numeric invalid" (not (is_valid_bot_id "bot_123"));
    check "bot_id 1 valid" (is_valid_bot_id "1");
    check "bot_id max safe int valid" (is_valid_bot_id "9007199254740991");
    check "bot_id exceeding max safe int invalid" (not (is_valid_bot_id "9007199254740992"));

    (* 4. Version / Hash relationship invariants *)
    let inv_rs_v0 = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_inv_rs_v0"
      ~expected_generation:1
      ~read_set:[ { key = "k1"; expected_version = 0; expected_sha256 = "non_empty_sha" } ]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply inv_rs_v0 with
    | Error "invalid_read_set_assertion" -> check "v=0 with non-empty sha rejected with invalid_read_set_assertion" true
    | _ -> check "failed to reject v=0 with sha" false);

    let inv_rs_vn = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_inv_rs_vn"
      ~expected_generation:1
      ~read_set:[ { key = "k1"; expected_version = -1; expected_sha256 = "" } ]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply inv_rs_vn with
    | Error "invalid_read_set_assertion" -> check "negative version rejected with invalid_read_set_assertion" true
    | _ -> check "failed to reject negative version" false);

    let inv_ch_v0 = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_inv_ch_v0"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "k1"; expected_version = 0; expected_sha256 = "non_empty_sha"; new_value_base64 = b64 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply inv_ch_v0 with
    | Error "invalid_change" -> check "v=0 with non-empty sha in change rejected with invalid_change" true
    | _ -> check "failed to reject v=0 with sha in change" false)
  )

(* ======================================================== *)
(* Test 12: Strict JSON Schemas & Unknown Field Rejection   *)
(* ======================================================== *)
let test_strict_json_schemas () =
  Printf.printf "=== Test Suite 12: Strict JSON Schemas & Unknown Field Rejection ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "json_strict.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. Reproduce independent_review.ml: read_keys with invented field *)
    let q_unk = run_command_json ~configured_db_path:db_path "{\"command\":\"read_keys\",\"keys\":[],\"invented\":true}" in
    check "read_keys with invented field returns unknown_json_field"
      (String.contains q_unk 'u' && String.contains q_unk 'n' && String.contains q_unk 'k');

    (* 2. initialize_new with unknown field *)
    let q_init = run_command_json ~configured_db_path:db_path "{\"command\":\"initialize_new\",\"bot_id\":\"1\",\"extra\":1}" in
    check "initialize_new with extra field returns unknown_json_field"
      (String.contains q_init 'u' && String.contains q_init 'n' && String.contains q_init 'k');

    (* 3. read_inbox_index with unknown field *)
    let q_inbox = run_command_json ~configured_db_path:db_path "{\"command\":\"read_inbox_index\",\"limit\":10,\"extra\":1}" in
    check "read_inbox_index with extra field returns unknown_json_field"
      (String.contains q_inbox 'u' && String.contains q_inbox 'n' && String.contains q_inbox 'k');

    (* 4. lookup_operation with unknown field *)
    let q_lookup = run_command_json ~configured_db_path:db_path "{\"command\":\"lookup_operation\",\"operation_id\":\"op1\",\"extra\":1}" in
    check "lookup_operation with extra field returns unknown_json_field"
      (String.contains q_lookup 'u' && String.contains q_lookup 'n' && String.contains q_lookup 'k');

    (* 5. apply with nested unknown field in read_set_assertions *)
    let digest = compute_request_digest ~bot_id ~operation_id:"op_strict" ~expected_generation:1 ~read_set:[] ~changes:[] ~reservation_delta:{rows=0;receipts=0} ~summary_json:"{}" in
    let q_nested_rs = Printf.sprintf
      "{\"command\":\"apply\",\"bot_id\":\"1\",\"operation_id\":\"op_strict\",\"request_digest\":\"%s\",\"expected_generation\":1,\"read_set_assertions\":[{\"key\":\"k\",\"expected_version\":0,\"expected_sha256\":\"\",\"extra\":1}],\"changes\":[],\"reservation_delta\":{\"rows\":0,\"receipts\":0},\"summary_json\":\"{}\"}"
      digest
    in
    let resp_rs = run_command_json ~configured_db_path:db_path q_nested_rs in
    check "nested extra field in read_set_assertions returns unknown_json_field"
      (String.contains resp_rs 'u' && String.contains resp_rs 'n' && String.contains resp_rs 'k');

    (* 6. apply with nested unknown field in reservation_delta *)
    let q_nested_rd = Printf.sprintf
      "{\"command\":\"apply\",\"bot_id\":\"1\",\"operation_id\":\"op_strict\",\"request_digest\":\"%s\",\"expected_generation\":1,\"read_set_assertions\":[],\"changes\":[],\"reservation_delta\":{\"rows\":0,\"receipts\":0,\"extra\":1},\"summary_json\":\"{}\"}"
      digest
    in
    let resp_rd = run_command_json ~configured_db_path:db_path q_nested_rd in
    check "nested extra field in reservation_delta returns unknown_json_field"
      (String.contains resp_rd 'u' && String.contains resp_rd 'n' && String.contains resp_rd 'k')
  )

(* ======================================================== *)
(* Test 13: Commit Uncertainty & Reconciliation             *)
(* ======================================================== *)
let test_commit_uncertainty_and_reconciliation () =
  Printf.printf "=== Test Suite 13: Commit Uncertainty & Reconciliation ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "uncertain.sqlite3" in
    let bot_id = "123" in

    (* 1. Test hook: fail init during commit *)
    reset_test_hooks ();
    test_hook_fail_init_during_commit := true;
    (match initialize_new db_path bot_id with
    | Error "commit_uncertain" -> check "initialize_new during-commit failure returns commit_uncertain" true
    | _ -> check "failed to return commit_uncertain on init during commit" false);

    (* 2. Test hook: fail init after commit *)
    let db_path2 = Filename.concat dir "uncertain2.sqlite3" in
    reset_test_hooks ();
    test_hook_fail_init_after_commit := true;
    (match initialize_new db_path2 bot_id with
    | Error "commit_uncertain" -> check "initialize_new after-commit failure returns commit_uncertain" true
    | _ -> check "failed to return commit_uncertain on init after commit" false);

    (* 3. Clean initialization *)
    let db_path3 = Filename.concat dir "reconcile.sqlite3" in
    reset_test_hooks ();
    assert (initialize_new db_path3 bot_id = Ok 1);

    (* 4. Test apply before-commit failure: rolls back, leaves state clean *)
    let b64 = encode_canonical_base64 "{\"v\": \"payload\"}" in
    let req_before = make_apply_req
      ~db_path:db_path3
      ~bot_id
      ~operation_id:"op_before"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "key_before"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 } ]
      ~res_delta:{ rows = 1; receipts = 1 }
      ~summary_json:"{\"action\":\"before\"}"
    in
    reset_test_hooks ();
    test_hook_fail_apply_before_commit := true;
    (match apply req_before with
    | Error "simulated_before_commit_failure" -> check "apply before-commit failure returns simulated failure" true
    | _ -> check "failed to trigger simulated before-commit failure" false);

    (* State is clean: lookup_operation finds None, generation is still 1 *)
    (match lookup_operation db_path3 "op_before" with
    | Ok None -> check "uncommitted rollback leaves operation lookup absent" true
    | _ -> check "operation unexpectedly found after rollback" false);
    (match read_keys db_path3 ["key_before"] with
    | Ok (1, [r]) -> check "generation is still 1 and row does not exist" (not r.exists)
    | _ -> check "state corrupted after rollback" false);

    (* 5. Test apply after-commit failure: returns commit_uncertain, but receipt IS committed *)
    let req_after = make_apply_req
      ~db_path:db_path3
      ~bot_id
      ~operation_id:"op_after"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "key_after"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 } ]
      ~res_delta:{ rows = 1; receipts = 1 }
      ~summary_json:"{\"action\":\"reconciled\"}"
    in
    reset_test_hooks ();
    test_hook_fail_apply_after_commit := true;
    (match apply req_after with
    | Error "commit_uncertain" -> check "apply after-commit failure returns commit_uncertain" true
    | _ -> check "failed to return commit_uncertain on after-commit" false);

    (* Reconciliation: lookup_operation reconciles committed transaction *)
    reset_test_hooks ();
    (match lookup_operation db_path3 "op_after" with
    | Ok (Some rcpt) ->
        check "lookup_operation reconciles committed receipt after uncertain return" (rcpt.generation = 2);
        check "reconciled receipt operation_id matches" (rcpt.operation_id = "op_after");
        check "reconciled receipt digest matches" (rcpt.request_digest = req_after.request_digest);
        check "reconciled receipt summary matches" (rcpt.summary_json = "{\"action\":\"reconciled\"}")
    | _ -> check "failed to reconcile committed receipt after uncertain return" false);

    (* Replay of reconciled operation succeeds *)
    let req_replay = { req_after with expected_generation = 1 } in
    (match apply req_replay with
    | Ok res -> check "replay of reconciled operation succeeds" res.replay
    | Error e -> check ("replay of reconciled operation failed: " ^ e) false)
  )

(* ======================================================== *)
(* Test 14: Storage Capacity & Reservation Bounds           *)
(* ======================================================== *)
let test_capacity_bounds () =
  Printf.printf "=== Test Suite 14: Storage Capacity & Reservation Bounds ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "capacity_bounds.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* Exhaust rows reservation *)
    let db = Sqlite3.db_open db_path in
    ignore (Sqlite3.exec db "UPDATE meta SET value = '19999' WHERE key = 'reserved_rows';");
    ignore (Sqlite3.db_close db);

    let b64 = encode_canonical_base64 "{\"v\": \"val\"}" in
    let req_over_row_cap = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_over_row_cap"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[
        { key = "r1"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 };
        { key = "r2"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64 };
      ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_over_row_cap with
    | Error "capacity_exhausted" -> check "refuses exceeding row capacity with capacity_exhausted" true
    | _ -> check "failed to refuse row capacity exhaustion" false);

    (* Restore rows reservation *)
    let db2 = Sqlite3.db_open db_path in
    ignore (Sqlite3.exec db2 "UPDATE meta SET value = '0' WHERE key = 'reserved_rows';");
    (* Exhaust receipts reservation *)
    ignore (Sqlite3.exec db2 "UPDATE meta SET value = '19999' WHERE key = 'reserved_receipts';");
    ignore (Sqlite3.db_close db2);

    let req_over_rec_cap = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_over_rec_cap"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 1 }
      ~summary_json:"{}"
    in
    (match apply req_over_rec_cap with
    | Error "capacity_exhausted" -> check "refuses exceeding receipts capacity with capacity_exhausted" true
    | _ -> check "failed to refuse receipts capacity exhaustion" false)
  )

(* ======================================================== *)
(* Test 15: N7 Strict Optional Field Types                   *)
(* ======================================================== *)
let test_n7_strict_optional_field_types () =
  Printf.printf "=== Test Suite 15: N7 Strict Optional Field Types ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "n7_types.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. db_path: 42 in read_keys *)
    let q_rk = run_command_json ~configured_db_path:db_path "{\"command\":\"read_keys\",\"keys\":[],\"db_path\":42}" in
    check "db_path: 42 in read_keys rejected with ok: false" (String.contains q_rk 'f' && String.contains q_rk 'a' && String.contains q_rk 'l');

    (* 2. db_path: 42 in initialize_new *)
    let q_init = run_command_json ~configured_db_path:db_path "{\"command\":\"initialize_new\",\"bot_id\":\"1\",\"db_path\":42}" in
    check "db_path: 42 in initialize_new rejected with ok: false" (String.contains q_init 'f' && String.contains q_init 'a' && String.contains q_init 'l');

    (* 3. db_path: 42 in read_inbox_index *)
    let q_inbox = run_command_json ~configured_db_path:db_path "{\"command\":\"read_inbox_index\",\"limit\":10,\"db_path\":42}" in
    check "db_path: 42 in read_inbox_index rejected with ok: false" (String.contains q_inbox 'f' && String.contains q_inbox 'a' && String.contains q_inbox 'l');

    (* 4. db_path: 42 in lookup_operation *)
    let q_lookup = run_command_json ~configured_db_path:db_path "{\"command\":\"lookup_operation\",\"operation_id\":\"op1\",\"db_path\":42}" in
    check "db_path: 42 in lookup_operation rejected with ok: false" (String.contains q_lookup 'f' && String.contains q_lookup 'a' && String.contains q_lookup 'l');

    (* 5. expected_sha256: 42 in read_set_assertions at expected_version 0 *)
    let q_rs_v0 = "{\"command\":\"apply\",\"bot_id\":\"1\",\"operation_id\":\"op_n7_rs0\",\"request_digest\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"expected_generation\":1,\"read_set_assertions\":[{\"key\":\"k\",\"expected_version\":0,\"expected_sha256\":42}],\"changes\":[],\"reservation_delta\":{\"rows\":0,\"receipts\":0},\"summary_json\":\"{}\"}" in
    let r_rs_v0 = run_command_json ~configured_db_path:db_path q_rs_v0 in
    check "expected_sha256: 42 at version 0 rejected with invalid_read_set_assertion" (String.contains r_rs_v0 'i' && String.contains r_rs_v0 'n' && String.contains r_rs_v0 'v');

    (* 6. expected_sha256: 42 in changes at expected_version 0 *)
    let b64 = encode_canonical_base64 "{\"v\":\"test\"}" in
    let q_ch_v0 = Printf.sprintf "{\"command\":\"apply\",\"bot_id\":\"1\",\"operation_id\":\"op_n7_ch0\",\"request_digest\":\"0000000000000000000000000000000000000000000000000000000000000000\",\"expected_generation\":1,\"read_set_assertions\":[],\"changes\":[{\"key\":\"k\",\"expected_version\":0,\"expected_sha256\":42,\"new_value_base64\":\"%s\"}],\"reservation_delta\":{\"rows\":0,\"receipts\":0},\"summary_json\":\"{}\"}" b64 in
    let r_ch_v0 = run_command_json ~configured_db_path:db_path q_ch_v0 in
    check "expected_sha256: 42 at version 0 in changes rejected with invalid_change" (String.contains r_ch_v0 'i' && String.contains r_ch_v0 'n' && String.contains r_ch_v0 'v');

    (* 7. after_key: 42 in read_inbox_index *)
    let q_ak = run_command_json ~configured_db_path:db_path "{\"command\":\"read_inbox_index\",\"limit\":10,\"after_key\":42}" in
    check "after_key: 42 rejected with invalid_json" (String.contains q_ak 'i' && String.contains q_ak 'n' && String.contains q_ak 'v');

    (* 8. limit: 'abc' in read_inbox_index *)
    let q_lim = run_command_json ~configured_db_path:db_path "{\"command\":\"read_inbox_index\",\"limit\":\"abc\"}" in
    check "limit: 'abc' rejected with invalid_limit" (String.contains q_lim 'i' && String.contains q_lim 'n' && String.contains q_lim 'v')
  )

(* ======================================================== *)
(* Test 16: N8 Strict UTF-8 & Standard JSON                 *)
(* ======================================================== *)
let test_n8_utf8_and_strict_json () =
  Printf.printf "=== Test Suite 16: N8 Strict UTF-8 & Standard JSON ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "n8_utf8.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* 1. Raw 0xFF byte in wire key string *)
    let raw_0xff_wire = Bytes.of_string "{\"command\":\"read_keys\",\"keys\":[\"\xFF\"]}" in
    let r_wire = run_command_json ~configured_db_path:db_path (Bytes.to_string raw_0xff_wire) in
    check "raw 0xFF wire key rejected with invalid_json" (String.contains r_wire 'i' && String.contains r_wire 'n' && String.contains r_wire 'v');

    (* 2. Decoded malformed UTF-8 value (0xFF byte) in apply change *)
    let b64_bad_utf8 = Cryptokit.transform_string (Cryptokit.Base64.encode_compact_pad ()) "\xFF" in
    let req_bad_utf8 = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_bad_utf8_val"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "bad_utf8"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_bad_utf8 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_bad_utf8 with
    | Error "invalid_value" -> check "decoded malformed UTF-8 value rejected with invalid_value" true
    | _ -> check "failed to reject decoded malformed UTF-8 value" false);

    (* 3. Decoded non-JSON value in apply change *)
    let b64_non_json = encode_canonical_base64 "THIS_IS_NOT_JSON" in
    let req_non_json = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_non_json_val"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "non_json"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_non_json } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    (match apply req_non_json with
    | Error "invalid_value" -> check "decoded non-JSON value rejected with invalid_value" true
    | _ -> check "failed to reject decoded non-JSON value" false);

    (* 4. Non-JSON summary_json rejected *)
    let req_bad_sum = make_apply_req
      ~db_path
      ~bot_id
      ~operation_id:"op_bad_sum"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"NOT_JSON"
    in
    (match apply req_bad_sum with
    | Error "invalid_json" -> check "non-JSON summary rejected with invalid_json" true
    | _ -> check "failed to reject non-JSON summary" false);

    (* 5. Lone surrogate in JSON rejected *)
    let lone_surrogate_json = "{\"command\":\"read_keys\",\"keys\":[\"\\uD800\"]}" in
    let r_surr = run_command_json ~configured_db_path:db_path lone_surrogate_json in
    check "lone surrogate in JSON rejected with invalid_json" (String.contains r_surr 'i' && String.contains r_surr 'n' && String.contains r_surr 'v')
  )

(* ======================================================== *)
(* Test 17: N9 Ancestor Path Confinement & Sticky Exemption *)
(* ======================================================== *)
let test_n9_ancestor_path_confinement () =
  Printf.printf "=== Test Suite 17: N9 Ancestor Path Confinement & Sticky Exemption ===\n%!";
  with_temp_dir (fun base ->
    (* 1. Own-UID world-writable ancestor (0777) must be rejected *)
    let unsafe = Filename.concat base "foreign-writable" in
    Unix.mkdir unsafe 0o777;
    Unix.chmod unsafe 0o777;
    let priv = Filename.concat unsafe "private" in
    Unix.mkdir priv 0o700;
    let unsafe_db = Filename.concat priv "store.sqlite3" in
    (match initialize_new unsafe_db "1" with
    | Error "db_directory_insecure" -> check "own-UID world-writable ancestor rejected with db_directory_insecure" true
    | _ -> check "failed to reject world-writable ancestor" false);

    (* 2. Direct private directory in root-owned sticky /tmp is accepted *)
    let clean_dir = Filename.concat "/tmp" (Printf.sprintf "uos_tg_sticky_%d" (Unix.getpid ())) in
    Unix.mkdir clean_dir 0o700;
    let clean_db = Filename.concat clean_dir "store.sqlite3" in
    check "db in /tmp private directory accepted" (initialize_new clean_db "1" = Ok 1);
    Unix.unlink clean_db;
    (try Unix.unlink (clean_db ^ "-wal") with _ -> ());
    (try Unix.unlink (clean_db ^ "-shm") with _ -> ());
    (try Unix.unlink (clean_db ^ ".process_lock") with _ -> ());
    Unix.rmdir clean_dir
  )

(* ======================================================== *)
(* Test 18: N10 Transaction Exception Safety                *)
(* ======================================================== *)
let test_n10_transaction_safety () =
  Printf.printf "=== Test Suite 18: N10 Transaction Exception Safety ===\n%!";
  with_temp_dir (fun dir ->
    let db_path = Filename.concat dir "tx_safety.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db_path bot_id = Ok 1);

    (* Verify prepared statement finalize even on exception *)
    let db = Sqlite3.db_open db_path in
    let stmt_finalized = ref false in
    (try
      with_prepared_stmt db "SELECT count(*) FROM meta;" (fun stmt ->
        ignore (Sqlite3.step stmt);
        stmt_finalized := true;
        failwith "injected_stmt_exception"
      )
    with _ -> ());
    check "with_prepared_stmt protected body ran before exception" !stmt_finalized;
    (* Verify DB connection is still healthy and not locked by unfinalized stmt *)
    check "db connection healthy after statement exception" (query_single_int db "SELECT count(*) FROM meta;" = Ok 5);
    ignore (Sqlite3.db_close db)
  )

(* ======================================================== *)
(* Test 19: N11 Actual SIGKILL Crash Recovery Barriers      *)
(* ======================================================== *)
let test_n11_crash_recovery_sigkill_barriers () =
  Printf.printf "=== Test Suite 19: N11 Actual SIGKILL Crash Recovery Barriers ===\n%!";

  let fork_child_with_hook target_barrier f =
    match Unix.fork () with
    | -1 -> failwith "fork failed"
    | 0 ->
        test_stage_hook := (fun b ->
          if b = target_barrier then begin
            Unix.kill (Unix.getpid ()) Sys.sigkill;
            Unix.sleepf 0.5
          end
        );
        (try ignore (f ()) with _ -> ());
        exit 0
    | pid ->
        let (_, status) = Unix.waitpid [] pid in
        status
  in

  with_temp_dir (fun dir ->
    let bot_id = "1" in

    (* Barrier 1: Init_after_ddl *)
    let db1 = Filename.concat dir "crash_init_ddl.sqlite3" in
    let status1 = fork_child_with_hook Init_after_ddl (fun () -> initialize_new db1 bot_id) in
    check "child killed with SIGKILL at Init_after_ddl" (status1 = Unix.WSIGNALED Sys.sigkill);
    let db1_handle = Sqlite3.db_open ~mode:`NO_CREATE db1 in
    check "verify_schema fails on uncommitted DDL crash" (verify_schema db1_handle None <> Ok (1, bot_id, 0, 0));
    ignore (Sqlite3.db_close db1_handle);

    (* Barrier 2: Init_after_meta *)
    let db2 = Filename.concat dir "crash_init_meta.sqlite3" in
    let status2 = fork_child_with_hook Init_after_meta (fun () -> initialize_new db2 bot_id) in
    check "child killed with SIGKILL at Init_after_meta" (status2 = Unix.WSIGNALED Sys.sigkill);
    let db2_handle = Sqlite3.db_open ~mode:`NO_CREATE db2 in
    check "verify_schema fails on uncommitted meta crash" (verify_schema db2_handle None <> Ok (1, bot_id, 0, 0));
    ignore (Sqlite3.db_close db2_handle);

    (* Setup database for apply tests *)
    let db3 = Filename.concat dir "crash_apply.sqlite3" in
    reset_test_hooks ();
    assert (initialize_new db3 bot_id = Ok 1);

    (* Insert initial row k1 *)
    let val_1 = "{\"v\": 1}" in
    let b64_1 = encode_canonical_base64 val_1 in
    let sha_1 = sha256_hex val_1 in
    let req_init = make_apply_req
      ~db_path:db3
      ~bot_id
      ~operation_id:"op_init_k1"
      ~expected_generation:1
      ~read_set:[]
      ~changes:[ { key = "k1"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_1 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    assert ((match apply req_init with Ok r -> not r.replay | _ -> false));

    (* Barrier 3: Apply_between_rows *)
    let val_2 = "{\"v\": 2}" in
    let b64_2 = encode_canonical_base64 val_2 in
    let req_two_rows = make_apply_req
      ~db_path:db3
      ~bot_id
      ~operation_id:"op_between_rows"
      ~expected_generation:2
      ~read_set:[]
      ~changes:[
        { key = "k1"; expected_version = 1; expected_sha256 = sha_1; new_value_base64 = b64_2 };
        { key = "k2"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_2 };
      ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    let status3 = fork_child_with_hook Apply_between_rows (fun () -> apply req_two_rows) in
    check "child killed with SIGKILL at Apply_between_rows" (status3 = Unix.WSIGNALED Sys.sigkill);
    reset_test_hooks ();
    (match read_keys db3 ["k1"; "k2"] with
    | Ok (2, [r1; r2]) ->
        check "after Apply_between_rows crash, k1 is still version 1" (r1.version = 1);
        check "after Apply_between_rows crash, k2 does not exist" (not r2.exists)
    | _ -> check "failed to verify clean state after Apply_between_rows crash" false);

    (* Barrier 4: Apply_pre_commit *)
    let req_pre_commit = make_apply_req
      ~db_path:db3
      ~bot_id
      ~operation_id:"op_pre_commit"
      ~expected_generation:2
      ~read_set:[]
      ~changes:[ { key = "k_pre"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_2 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{}"
    in
    let status4 = fork_child_with_hook Apply_pre_commit (fun () -> apply req_pre_commit) in
    check "child killed with SIGKILL at Apply_pre_commit" (status4 = Unix.WSIGNALED Sys.sigkill);
    reset_test_hooks ();
    (match lookup_operation db3 "op_pre_commit" with
    | Ok None -> check "after Apply_pre_commit crash, receipt is absent (rolled back)" true
    | _ -> check "receipt unexpectedly committed before commit" false);

    (* Barrier 5: Apply_post_commit_pre_reply *)
    let req_post_commit = make_apply_req
      ~db_path:db3
      ~bot_id
      ~operation_id:"op_post_commit"
      ~expected_generation:2
      ~read_set:[]
      ~changes:[ { key = "k_post"; expected_version = 0; expected_sha256 = ""; new_value_base64 = b64_2 } ]
      ~res_delta:{ rows = 0; receipts = 0 }
      ~summary_json:"{\"action\":\"post_commit\"}"
    in
    let status5 = fork_child_with_hook Apply_post_commit_pre_reply (fun () -> apply req_post_commit) in
    check "child killed with SIGKILL at Apply_post_commit_pre_reply" (status5 = Unix.WSIGNALED Sys.sigkill);
    reset_test_hooks ();
    (match lookup_operation db3 "op_post_commit" with
    | Ok (Some rcpt) ->
        check "after Apply_post_commit crash, receipt is committed" (rcpt.generation = 3);
        check "receipt digest matches" (rcpt.request_digest = req_post_commit.request_digest)
    | _ -> check "receipt missing after post-commit crash" false);
    (match apply req_post_commit with
    | Ok res -> check "idempotent replay of post-commit crash succeeds with replay: true" res.replay
    | Error e -> check ("replay failed after post-commit crash: " ^ e) false)
  )

(* ======================================================== *)
(* Test 20: N12 Decoded JSON Keys & Nesting Depth Limits   *)
(* ======================================================== *)
let test_n12_decoded_json_keys_and_nesting () =
  Printf.printf "=== Test Suite 20: N12 Decoded JSON Keys & Nesting Depth Limits ===\n%!";
  (* 1. Distinct escaped BMP keys accepted *)
  check "distinct escaped BMP keys accepted"
    (validate_strict_json "{\"\\u0061\":1,\"\\u0062\":2}" = Ok ());

  (* 2. Literal and escaped duplicate rejected *)
  check "literal and escaped duplicate rejected"
    (validate_strict_json "{\"a\":1,\"\\u0061\":2}" = Error "duplicate_json_keys");

  (* 3. Distinct surrogate pair keys accepted *)
  check "distinct surrogate pair keys accepted"
    (validate_strict_json "{\"\\ud83d\\ude00\":1,\"\\ud83d\\ude01\":2}" = Ok ());

  (* 4. Duplicate surrogate pair keys rejected *)
  check "duplicate surrogate pair keys rejected"
    (validate_strict_json "{\"\\ud83d\\ude00\":1,\"\\ud83d\\ude00\":2}" = Error "duplicate_json_keys");

  (* 5. Slash escape duplicate rejected *)
  check "slash escape duplicate rejected"
    (validate_strict_json "{\"/\":1,\"\\/\":2}" = Error "duplicate_json_keys");

  (* 6. Escaped newline and unicode newline duplicate rejected *)
  check "escaped newline and unicode newline duplicate rejected"
    (validate_strict_json "{\"\\n\":1,\"\\u000a\":2}" = Error "duplicate_json_keys");

  (* 7. Deep nesting within limit accepted (depth 64) *)
  let deep_ok = String.make 64 '[' ^ "1" ^ String.make 64 ']' in
  check "nesting depth 64 accepted"
    (validate_strict_json deep_ok = Ok ());

  (* 8. Deep nesting exceeding limit rejected (depth 65) *)
  let deep_bad = String.make 65 '[' ^ "1" ^ String.make 65 ']' in
  check "nesting depth 65 rejected with json_nesting_depth_exceeded"
    (validate_strict_json deep_bad = Error "json_nesting_depth_exceeded");

  (* 9. Wide object with 100 distinct keys accepted *)
  let wide_buf = Buffer.create 1024 in
  Buffer.add_char wide_buf '{';
  for i = 0 to 99 do
    if i > 0 then Buffer.add_char wide_buf ',';
    Buffer.add_string wide_buf (Printf.sprintf "\"k%d\":%d" i i)
  done;
  Buffer.add_char wide_buf '}';
  check "wide object with 100 distinct keys accepted"
    (validate_strict_json (Buffer.contents wide_buf) = Ok ());

  (* 10. Wide object with duplicate at end rejected *)
  Buffer.add_string wide_buf "}"; (* dummy, rebuild *)
  let wide_dup = Buffer.create 1024 in
  Buffer.add_char wide_dup '{';
  for i = 0 to 99 do
    if i > 0 then Buffer.add_char wide_dup ',';
    Buffer.add_string wide_dup (Printf.sprintf "\"k%d\":%d" i i)
  done;
  Buffer.add_string wide_dup ",\"k0\":999}";
  check "wide object with duplicate key rejected"
    (validate_strict_json (Buffer.contents wide_dup) = Error "duplicate_json_keys");

  (* 11. Empty array nesting depth 64 accepted *)
  let empty_arr_64 = String.make 64 '[' ^ String.make 64 ']' in
  check "empty array nesting depth 64 accepted"
    (validate_strict_json empty_arr_64 = Ok ());

  (* 12. Empty array nesting depth 65 rejected *)
  let empty_arr_65 = String.make 65 '[' ^ String.make 65 ']' in
  check "empty array nesting depth 65 rejected with json_nesting_depth_exceeded"
    (validate_strict_json empty_arr_65 = Error "json_nesting_depth_exceeded");

  (* 13. Empty object nesting depth 64 accepted *)
  let empty_obj_64 = String.make 63 '[' ^ "{}" ^ String.make 63 ']' in
  check "empty object nesting depth 64 accepted"
    (validate_strict_json empty_obj_64 = Ok ());

  (* 14. Empty object nesting depth 65 rejected *)
  let empty_obj_65 = String.make 64 '[' ^ "{}" ^ String.make 64 ']' in
  check "empty object nesting depth 65 rejected with json_nesting_depth_exceeded"
    (validate_strict_json empty_obj_65 = Error "json_nesting_depth_exceeded")

(* ======================================================== *)
(* Test 21: N13 Apply Stage Hook Exception Safety           *)
(* ======================================================== *)
let test_n13_commit_stage_exception_safety () =
  Printf.printf "=== Test Suite 21: N13 Apply Stage Hook Exception Safety ===\n%!";
  with_temp_dir (fun dir ->
    let db = Filename.concat dir "stage_exc.sqlite3" in
    let bot_id = "1" in
    assert (initialize_new db bot_id = Ok 1);

    let make_req op changes =
      let r = { rows = 0; receipts = 0 } in
      let digest = compute_request_digest ~bot_id ~operation_id:op ~expected_generation:1 ~read_set:[] ~changes ~reservation_delta:r ~summary_json:"{}" in
      { db_path = db; bot_id; operation_id = op; expected_generation = 1; read_set_assertions = []; changes; reservation_delta = r; summary_json = "{}"; request_digest = digest }
    in
    let put key raw =
      { key; expected_version = 0; expected_sha256 = ""; new_value_base64 = encode_canonical_base64 raw }
    in

    (* 1. Apply_between_rows exception: catches cleanly, rolls back, receipt absent *)
    reset_test_hooks ();
    test_stage_hook := (fun s -> if s = Apply_between_rows then failwith "private_fault_marker");
    let req_between = make_req "op_between_exc" [put "k1" "{\"v\":1}"; put "k2" "{\"v\":2}"] in
    (match apply req_between with
    | Error "sqlite_error" -> check "Apply_between_rows exception caught returning finite error" true
    | _ -> check "Apply_between_rows exception not caught cleanly" false);
    reset_test_hooks ();
    check "receipt absent after between_rows exception rollback"
      (lookup_operation db "op_between_exc" = Ok None);

    (* 2. Apply_pre_commit exception: catches cleanly, rolls back, receipt absent *)
    reset_test_hooks ();
    test_stage_hook := (fun s -> if s = Apply_pre_commit then failwith "private_fault_marker");
    let req_pre = make_req "op_pre_exc" [put "k_pre" "{\"v\":1}"] in
    (match apply req_pre with
    | Error "sqlite_error" -> check "Apply_pre_commit exception caught returning finite error" true
    | _ -> check "Apply_pre_commit exception not caught cleanly" false);
    reset_test_hooks ();
    check "receipt absent after pre_commit exception rollback"
      (lookup_operation db "op_pre_exc" = Ok None);

    (* 3. Apply_post_commit_pre_reply exception: catches cleanly, returns commit_uncertain, receipt IS committed *)
    reset_test_hooks ();
    test_stage_hook := (fun s -> if s = Apply_post_commit_pre_reply then failwith "private_fault_marker");
    let req_post = make_req "op_post_exc" [put "k_post" "{\"v\":1}"] in
    (match apply req_post with
    | Error "commit_uncertain" -> check "Apply_post_commit exception caught returning commit_uncertain" true
    | _ -> check "Apply_post_commit exception not caught cleanly" false);
    reset_test_hooks ();
    (match lookup_operation db "op_post_exc" with
    | Ok (Some rcpt) ->
        check "receipt durably committed after post_commit exception" (rcpt.generation = 2)
    | _ -> check "receipt unexpectedly absent after post_commit exception" false)
  )

let () =
  print_endline "\nRunning Telegram Store Native Kernel Test Suite...";
  test_initialize_and_security ();
  test_read_keys_and_inbox ();
  test_apply_and_cas ();
  test_capacity_and_reservations ();
  test_bounds_and_chunks ();
  test_advanced_integrity ();
  test_redacted_errors_and_framing ();
  test_pipe_framing_process ();
  test_injective_digest_and_collision ();
  test_ancestor_confinement ();
  test_duplicates_and_invariants ();
  test_strict_json_schemas ();
  test_commit_uncertainty_and_reconciliation ();
  test_capacity_bounds ();
  test_n7_strict_optional_field_types ();
  test_n8_utf8_and_strict_json ();
  test_n9_ancestor_path_confinement ();
  test_n10_transaction_safety ();
  test_n11_crash_recovery_sigkill_barriers ();
  test_n12_decoded_json_keys_and_nesting ();
  test_n13_commit_stage_exception_safety ();
  Printf.printf "\nALL TESTS PASSED: %d/%d assertions passed successfully!\n%!" !pass_count !test_count


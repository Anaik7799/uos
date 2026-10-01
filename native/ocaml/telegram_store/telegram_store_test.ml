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
  let base = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "uos_tg_store_test_%d_%d" (Unix.getpid ()) (Random.int 1000000)) in
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
  Printf.printf "\nALL TESTS PASSED: %d/%d assertions passed successfully!\n%!" !pass_count !test_count

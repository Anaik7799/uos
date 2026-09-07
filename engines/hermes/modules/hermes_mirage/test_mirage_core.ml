(** Test Suite for MirageOS Unikernel Engine in UOS (EV-87) *)

let test_block_device () =
  Printf.printf "Testing Mirage Memory Block Device...\n";
  match Mirage_memory_block.create 16L with
  | Error e -> failwith ("Failed to create block device: " ^ e)
  | Ok dev ->
      let info = Mirage_memory_block.get_info dev in
      assert (info.sector_size = 512);
      assert (info.size_sectors = 16L);
      let write_buf = Bytes.of_string "Hello MirageOS Block Sector!" in
      let pad_buf = Bytes.make 512 '\000' in
      Bytes.blit write_buf 0 pad_buf 0 (Bytes.length write_buf);
      begin match Mirage_memory_block.write dev 0L [pad_buf] with
      | Error _ -> failwith "Write failed"
      | Ok () -> ()
      end;
      let read_buf = Bytes.make 512 '\000' in
      begin match Mirage_memory_block.read dev 0L [read_buf] with
      | Error _ -> failwith "Read failed"
      | Ok () ->
          assert (Bytes.sub_string read_buf 0 (Bytes.length write_buf) = "Hello MirageOS Block Sector!");
          Printf.printf "  [PASS] Mirage Memory Block Device I/O verified.\n"
      end

let test_merkle_kv () =
  Printf.printf "Testing Irmin-style Merkle KV Store...\n";
  let store = Mirage_merkle_kv.create () in
  let store = match Mirage_merkle_kv.set store ["config"; "network"] "dhcp=true" with
    | Ok s -> s | Error _ -> failwith "Set failed" in
  let store = match Mirage_merkle_kv.set store ["config"; "ports"] "4100" with
    | Ok s -> s | Error _ -> failwith "Set failed" in
  let hash1 = Mirage_merkle_kv.root_hash store in
  assert (String.length hash1 = 64);
  
  begin match Mirage_merkle_kv.get store ["config"; "ports"] with
  | Ok "4100" -> ()
  | _ -> failwith "Get failed"
  end;
  
  (* Branch and merge test *)
  let branch1 = Mirage_merkle_kv.branch store in
  let branch2 = Mirage_merkle_kv.branch store in
  let branch1 = match Mirage_merkle_kv.set branch1 ["worker"; "w1"] "active" with
    | Ok s -> s | Error _ -> failwith "Set branch1 failed" in
  let branch2 = match Mirage_merkle_kv.set branch2 ["worker"; "w2"] "standby" with
    | Ok s -> s | Error _ -> failwith "Set branch2 failed" in
  
  begin match Mirage_merkle_kv.merge ~our:branch1 ~their:branch2 with
  | Error e -> failwith ("Merge failed: " ^ e)
  | Ok merged ->
      begin match Mirage_merkle_kv.get merged ["worker"; "w1"] with
      | Ok "active" -> ()
      | _ -> failwith "m1"
      end;
      begin match Mirage_merkle_kv.get merged ["worker"; "w2"] with
      | Ok "standby" -> ()
      | _ -> failwith "m2"
      end;
      Printf.printf "  [PASS] Irmin-style Merkle KV branching and 3-way merge verified.\n"
  end

let test_solo5_tender () =
  Printf.printf "Testing Solo5 Tender Configuration...\n";
  let config = Mirage_solo5_tender.default_tender_config "hermes-interceptor" in
  match Mirage_solo5_tender.verify_sandbox_safety config with
  | Error e -> failwith ("Safety check failed: " ^ e)
  | Ok () ->
      let cold_start = Mirage_solo5_tender.cold_start_estimate_ms config in
      assert (cold_start < 20.0);
      let json = Mirage_solo5_tender.generate_manifest_json config in
      assert (String.length json > 50);
      Printf.printf "  [PASS] Solo5 Tender safety and cold start verified (cold_start: %.2f ms).\n" cold_start

let test_interceptor () =
  Printf.printf "Testing Mirage Zero-Trust Interceptor...\n";
  (* Trap null bytes *)
  begin match Mirage_interceptor.inspect_payload "safe_prefix\000malicious_suffix" with
  | Mirage_interceptor.Trapped_null_byte -> ()
  | _ -> failwith "Failed to trap null byte"
  end;
  
  (* Trap SQL injection *)
  begin match Mirage_interceptor.inspect_payload "query; DROP TABLE users;--" with
  | Mirage_interceptor.Trapped_sql_injection "DROP TABLE" -> ()
  | _ -> failwith "Failed to trap SQL injection"
  end;
  
  (* Admitted payload *)
  match Mirage_interceptor.inspect_payload "{\"tool\":\"get_health\",\"params\":{}}" with
  | Mirage_interceptor.Admitted digest ->
      assert (String.length digest = 64);
      (* Ed25519 signing *)
      let seed = "12345678901234567890123456789012" in
      begin match Mirage_interceptor.sign_admission_receipt ~secret_seed:seed digest with
      | Error e -> failwith ("Signing failed: " ^ e)
      | Ok sig_bytes ->
          assert (String.length sig_bytes = 64);
          Printf.printf "  [PASS] Zero-Trust Interceptor and Ed25519 receipt verified.\n"
      end
  | _ -> failwith "Failed to admit safe payload"

let () =
  Printf.printf "=== Running MirageOS Unikernel Core Verification Suite ===\n";
  test_block_device ();
  test_merkle_kv ();
  test_solo5_tender ();
  test_interceptor ();
  Printf.printf "=== All MirageOS Unikernel Core Tests Passed (100%% Green) ===\n"

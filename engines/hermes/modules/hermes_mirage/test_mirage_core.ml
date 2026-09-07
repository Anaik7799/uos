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
          ()
      end;
      let sector = Bytes.make 512 '\001' in
      begin match Mirage_memory_block.write dev (-1L) [sector] with
      | Error (`Write_error _) -> ()
      | _ -> failwith "Negative sector write was not rejected"
      end;
      begin match Mirage_memory_block.read dev (-1L) [Bytes.make 512 '\000'] with
      | Error (`Read_error _) -> ()
      | _ -> failwith "Negative sector read was not rejected"
      end;
      begin match Mirage_memory_block.write dev 17L [] with
      | Error (`Write_error _) -> ()
      | _ -> failwith "Out-of-range empty write was not rejected"
      end;
      begin match Mirage_memory_block.write dev 1L [Bytes.make 511 '\000'] with
      | Error (`Write_error _) -> ()
      | _ -> failwith "Short sector write was not rejected"
      end;
      begin match Mirage_memory_block.read dev 1L [Bytes.make 1024 '\000'] with
      | Error (`Read_error _) -> ()
      | _ -> failwith "Oversized sector read was not rejected"
      end;
      (* A failing multi-sector write must not commit its in-range prefix. *)
      begin match Mirage_memory_block.write dev 15L [sector; sector] with
      | Error (`Write_error _) -> ()
      | _ -> failwith "Out-of-bounds multi-sector write was not rejected"
      end;
      let rollback_control = Bytes.make 512 '\001' in
      begin match Mirage_memory_block.read dev 15L [rollback_control] with
      | Error _ -> failwith "Rollback control read failed"
      | Ok () -> assert (rollback_control = Bytes.make 512 '\000')
      end;
      let read_rollback_a = Bytes.make 512 '\004' in
      let read_rollback_b = Bytes.make 512 '\005' in
      begin match Mirage_memory_block.read dev 15L [read_rollback_a; read_rollback_b] with
      | Error (`Read_error _) ->
          assert (read_rollback_a = Bytes.make 512 '\004');
          assert (read_rollback_b = Bytes.make 512 '\005')
      | _ -> failwith "Out-of-bounds multi-sector read was not rejected"
      end;
      let sector_a = Bytes.make 512 '\002' in
      let sector_b = Bytes.make 512 '\003' in
      begin match Mirage_memory_block.write dev 1L [sector_a; sector_b] with
      | Error _ -> failwith "Valid multi-sector write failed"
      | Ok () -> ()
      end;
      let read_a = Bytes.make 512 '\000' in
      let read_b = Bytes.make 512 '\000' in
      begin match Mirage_memory_block.read dev 1L [read_a; read_b] with
      | Error _ -> failwith "Valid multi-sector read failed"
      | Ok () ->
          assert (read_a = sector_a);
          assert (read_b = sector_b)
      end;
      Printf.printf "  [PASS] Mirage Memory Block Device I/O and bounds verified.\n"

let test_merkle_kv () =
  Printf.printf "Testing content-hashed KV Store...\n";
  let store = Mirage_merkle_kv.create () in
  let store = match Mirage_merkle_kv.set store ["config"; "network"] "dhcp=true" with
    | Ok s -> s | Error _ -> failwith "Set failed" in
  let store = match Mirage_merkle_kv.set store ["config"; "ports"] "4100" with
    | Ok s -> s | Error _ -> failwith "Set failed" in
  let hash1 = Mirage_merkle_kv.root_hash store in
  assert (String.length hash1 = 64);

  let set_ok store key value =
    match Mirage_merkle_kv.set store key value with
    | Ok next -> next
    | Error _ -> failwith "Merkle test setup failed"
  in
  let segmented = set_ok (Mirage_merkle_kv.create ()) ["a"; "b"] "v" in
  let slash_in_segment = set_ok (Mirage_merkle_kv.create ()) ["a/b"] "v" in
  assert (Mirage_merkle_kv.root_hash segmented <>
          Mirage_merkle_kv.root_hash slash_in_segment);
  let ordered =
    Mirage_merkle_kv.create ()
    |> fun s -> set_ok s ["a"; "b"] "v"
    |> fun s -> set_ok s ["x:y"; "z|w"] "second"
  in
  let reversed =
    Mirage_merkle_kv.create ()
    |> fun s -> set_ok s ["x:y"; "z|w"] "second"
    |> fun s -> set_ok s ["a"; "b"] "v"
  in
  assert (Mirage_merkle_kv.root_hash ordered = Mirage_merkle_kv.root_hash reversed);
  
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
      Printf.printf "  [PASS] Content-hashed KV branching and two-way merge verified.\n"
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
      Printf.printf "  [PASS] Tender configuration predicates and formula %.2f ms; no tender execution.\n" cold_start

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
          let key = match Mirage_crypto_ec.Ed25519.priv_of_octets seed with
            | Ok key -> key | Error _ -> failwith "test key construction failed" in
          let public_key_octets = Mirage_crypto_ec.Ed25519.(pub_to_octets (pub_of_priv key)) in
          let verify = Mirage_interceptor.verify_admission_receipt ~public_key_octets in
          assert (verify digest ~signature:sig_bytes);
          assert (not (verify (digest ^ "tampered") ~signature:sig_bytes));
          assert (not (verify digest ~signature:"short"));
          assert (not (Mirage_interceptor.verify_admission_receipt
            ~public_key_octets:"invalid" digest ~signature:sig_bytes));
          assert (Result.is_error (Mirage_interceptor.sign_admission_receipt
            ~secret_seed:"short" digest));
          Printf.printf "  [PASS] Host payload filter and Ed25519 valid/tampered/malformed controls; no authorization claim.\n"
      end
  | _ -> failwith "Failed to admit safe payload"

let () =
  Printf.printf "=== Running Hermes Mirage Host Library Checks ===\n";
  test_block_device ();
  test_merkle_kv ();
  test_solo5_tender ();
  test_interceptor ();
  Printf.printf "=== Host library checks passed; Solo5 deployment remains NOT_VERIFIED ===\n"

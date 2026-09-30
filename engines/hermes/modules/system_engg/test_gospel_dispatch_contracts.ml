(* test_gospel_dispatch_contracts.ml — Unit and differential tests for Gospel contracts (EV-107) *)

let test_valid_payload () =
  let payload = "{\"tool\":\"read_file\",\"args\":{\"path\":\"/home/an/doc.txt\"}}" in
  match Gospel_dispatch_contracts.validate_dispatch_contract payload with
  | Gospel_dispatch_contracts.Pass { digest; _ } ->
      assert (String.length digest = 64);
      print_endline "PASS: Valid payload contract satisfied"
  | Gospel_dispatch_contracts.FailClosed _ ->
      failwith "FAIL: Valid payload unexpectedly rejected"

let test_nul_byte_trapping () =
  let payload = "{\"tool\":\"eval\",\"code\":\"print(\x00)\"}" in
  match Gospel_dispatch_contracts.validate_dispatch_contract payload with
  | Gospel_dispatch_contracts.FailClosed { error_code; _ } ->
      assert (error_code = -2);
      print_endline "PASS: Embedded NUL byte trapped (code -2)"
  | Gospel_dispatch_contracts.Pass _ ->
      failwith "FAIL: NUL byte was not trapped"

let test_sql_injection_rejection () =
  let payload = "{\"query\":\"SELECT * FROM users; DROP TABLE users;\"}" in
  match Gospel_dispatch_contracts.validate_dispatch_contract payload with
  | Gospel_dispatch_contracts.FailClosed { error_code; _ } ->
      assert (error_code = -3);
      print_endline "PASS: SQL injection trapped (code -3)"
  | Gospel_dispatch_contracts.Pass _ ->
      failwith "FAIL: SQL injection was not trapped"

let test_differential_oracle_parity () =
  let payload_good = "{\"tool\":\"system_health\"}" in
  (match Gospel_dispatch_contracts.bounded_differential_oracle payload_good (Gospel_dispatch_contracts.sha256_digest payload_good) with
   | Ok true -> print_endline "PASS: Differential oracle parity verified on clean payload"
   | _ -> failwith "FAIL: Differential oracle discrepancy on clean payload");

  let payload_bad = "{\"tool\":\"exec\",\"cmd\":\"ls\x00-la\"}" in
  (match Gospel_dispatch_contracts.bounded_differential_oracle payload_bad (Gospel_dispatch_contracts.sha256_digest payload_bad) with
   | Ok true -> print_endline "PASS: Differential oracle parity verified on malicious payload"
   | _ -> failwith "FAIL: Differential oracle discrepancy on malicious payload")

let expect_agreement payload expected () =
  match Gospel_dispatch_contracts.bounded_differential_oracle payload expected with
  | Ok true -> ()
  | _ -> failwith "expected exact digest agreement"

let expect_refusal payload expected () =
  match Gospel_dispatch_contracts.bounded_differential_oracle payload expected with
  | Error _ -> ()
  | Ok _ -> failwith "expected digest refusal, observed positive comparison"

let abc_digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
let empty_digest = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

let () =
  let cases = [
    "valid_payload", test_valid_payload;
    "nul_trapped", test_nul_byte_trapping;
    "sql_trapped", test_sql_injection_rejection;
    "retained_parity", test_differential_oracle_parity;
    "known_abc_digest", expect_agreement "abc" abc_digest;
    "known_empty_payload_digest", expect_agreement "" empty_digest;
    "same_length_wrong_digest", expect_refusal "abc" (String.make 64 '0');
    "different_payload_same_expected", expect_refusal "abd" abc_digest;
    "missing_expected_digest", expect_refusal "abc" "";
    "short_digest", expect_refusal "abc" (String.sub abc_digest 0 63);
    "long_digest", expect_refusal "abc" (abc_digest ^ "0");
    "nonhex_digest", expect_refusal "abc" (String.make 64 'g');
    "uppercase_digest", expect_refusal "abc" (String.uppercase_ascii abc_digest);
    "nul_in_digest", expect_refusal "abc" ("\x00" ^ String.sub abc_digest 1 63);
    "whitespace_digest", expect_refusal "abc" (" " ^ abc_digest);
    "rejected_payload_wrong_expected", expect_refusal "\x00" abc_digest;
    "rejected_payload_missing_expected", expect_refusal "\x00" "";
    "sql_rejection_exact_digest", (let p = "UNION SELECT" in expect_agreement p (Gospel_dispatch_contracts.sha256_digest p));
  ] in
  let failures = ref 0 in
  List.iter (fun (id, check) ->
    try check (); Printf.printf "CASE PASS %s\n%!" id
    with error -> incr failures; Printf.printf "CASE FAIL %s: %s\n%!" id (Printexc.to_string error)) cases;
  Printf.printf "SUMMARY total=%d failed=%d\n%!" (List.length cases) !failures;
  if !failures <> 0 then exit 1
